local addonName, ns = ...

local CombatLog = {}
ns.CombatLog = ns.Core:RegisterModule("CombatLog", CombatLog)

local Const = ns.Constants
local CLEU_KIND = Const.CLEU_KIND

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local UnitExists = UnitExists

-- 我们只跟踪自己与自己的宠物。别的 GUID 直接丢，避免团本里累加全团数据
-- （那是 Details! 的活，也会拖垮性能）。这两个 GUID 在 Init/UNIT_PET 时刷新。
local selfGUID = nil
local petGUID = nil

local function refreshGUIDs()
  selfGUID = UnitGUID and UnitGUID("player") or nil
  if UnitExists and UnitExists("pet") then
    petGUID = UnitGUID("pet")
  else
    petGUID = nil
  end
end

-- 判断某 GUID 是否属于"我方"（自己或宠物）。
local function isMine(guid)
  return guid and (guid == selfGUID or guid == petGUID)
end

-- ---- CLEU 分派：热路径，务必精简 ----
-- payload 结构（CombatLogGetCurrentEventInfo）:
--   timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags,
--   sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...
-- 之后是子事件特定参数。
local function handleCLEU()
  local seg = ns.Segment.current
  if not seg then return end  -- 不在战斗段内，直接忽略（登录/城市里省开销）

  local _, subevent, _, sourceGUID, _, _, _,
        destGUID, _, _, _,
        p12, p13, p14, p15, p16, p17, p18 = CombatLogGetCurrentEventInfo()

  local kind = CLEU_KIND[subevent]
  if not kind then return end

  if kind == "damage" then
    -- 我方造成的伤害。SWING 无 spellId，用固定桶 (1, "自动攻击")。
    if isMine(sourceGUID) then
      if subevent == "SWING_DAMAGE" then
        -- SWING: p12=amount
        ns.Segment:AddDamageDone(6603, "自动攻击", p12 or 0)
      else
        -- SPELL_*: p12=spellId, p13=spellName, p15=amount
        ns.Segment:AddDamageDone(p12 or 0, p13, p15 or 0)
      end
    end
    -- 自己承受的伤害（用于坦克 DTPS / 可避免伤害）。
    if destGUID == selfGUID then
      if subevent == "SWING_DAMAGE" then
        ns.Segment:AddDamageTaken(p12 or 0)
      else
        ns.Segment:AddDamageTaken(p15 or 0)
      end
    end

  elseif kind == "heal" then
    -- SPELL_HEAL: p12=spellId, p13=name, p15=amount, p16=overheal, p17=absorbed
    if isMine(sourceGUID) then
      local amount = p15 or 0
      local over = p16 or 0
      ns.Segment:AddHeal(amount, over)
    end

  elseif kind == "absorb" then
    -- SPELL_ABSORBED 参数排布随来源不同而变；用最后几位里合理的数字近似吸收量。
    if isMine(sourceGUID) then
      local absorbed = tonumber(p18) or tonumber(p17) or tonumber(p16) or 0
      ns.Segment:AddAbsorb(absorbed)
    end

  elseif kind == "cast" then
    -- SPELL_CAST_SUCCESS: p12=spellId, p13=name
    if isMine(sourceGUID) then
      ns.Segment:AddCast(p12 or 0, p13)
    end

  elseif kind == "aura_on" then
    -- 我方给自己上的 buff/debuff（覆盖率跟踪，主要针对维持类）。
    if isMine(sourceGUID) or destGUID == selfGUID then
      ns.Segment:AuraOn(p12 or 0, p13)
    end

  elseif kind == "aura_off" then
    if isMine(sourceGUID) or destGUID == selfGUID then
      ns.Segment:AuraOff(p12 or 0)
    end

  elseif kind == "interrupt" then
    if isMine(sourceGUID) then ns.Segment:AddInterrupt() end

  elseif kind == "dispel" then
    if isMine(sourceGUID) then ns.Segment:AddDispel() end

  elseif kind == "death" then
    if destGUID == selfGUID then ns.Segment:AddDeath() end
  end
end

-- ---- 生命周期事件：段的开始/结束由这里编排 ----
local function onlyBoss()
  return ns.Config and ns.Config:Get("profile.onlyBossFights")
end

function CombatLog:OnEvent(event, ...)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    handleCLEU()

  elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PET" then
    refreshGUIDs()

  elseif event == "ENCOUNTER_START" then
    local encounterID, encounterName = ...
    refreshGUIDs()
    ns.Segment:Start(Const.SEGMENT_SOURCE.ENCOUNTER, {
      encounterID = encounterID, name = encounterName,
    })

  elseif event == "ENCOUNTER_END" then
    local _, _, _, _, success = ...
    local seg = ns.Segment:Finish(success == 1)
    ns.Core:SafeCall(function() CombatLog:Complete(seg) end)

  elseif event == "PLAYER_REGEN_DISABLED" then
    -- 进入战斗。若无首领段（普通打怪），开一个 combat 段。
    if not onlyBoss() and not ns.Segment:IsActive() then
      refreshGUIDs()
      ns.Segment:Start(Const.SEGMENT_SOURCE.COMBAT)
    end

  elseif event == "PLAYER_REGEN_ENABLED" then
    -- 脱战。只收尾 combat 段；encounter 段交给 ENCOUNTER_END，避免提前截断。
    local seg = ns.Segment:Get()
    if seg and seg.source == Const.SEGMENT_SOURCE.COMBAT then
      seg = ns.Segment:Finish()
      ns.Core:SafeCall(function() CombatLog:Complete(seg) end)
    end
  end
end

-- 段结束后的编排：交给 Metrics 聚合 -> Analyzer 分析 -> Store 归档 -> UI。
-- 太短的段直接丢弃。
function CombatLog:Complete(seg)
  if not seg then return end
  local minSec = tonumber(ns.Config:Get("profile.minSegmentSeconds"))
    or Const.MIN_SEGMENT_SECONDS
  local duration = (seg.endClock or 0) - (seg.startClock or 0)
  if duration < minSec then return end

  local report = ns.Metrics:Build(seg, duration)
  if not report then return end
  report.suggestions = ns.Analyzer:Analyze(report)
  ns.Store:Add(report)

  if ns.Config:Get("profile.autoShowReport") and ns.ReportFrame then
    ns.ReportFrame:ShowReport(report)
  end
end

function CombatLog:Init()
  refreshGUIDs()
  self.frame = CreateFrame("Frame")
  self.frame:SetScript("OnEvent", function(_, event, ...)
    -- CLEU 极高频，直接调用不再包 pcall（异常会被外层战斗结束的 SafeCall 兜底）。
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      handleCLEU()
    else
      -- 生命周期事件参数不多（ENCOUNTER_END 最多 5 个），捕获后再进 SafeCall。
      local a1, a2, a3, a4, a5 = ...
      ns.Core:SafeCall(function() CombatLog:OnEvent(event, a1, a2, a3, a4, a5) end)
    end
  end)
  self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  for _, ev in ipairs(Const.LIFECYCLE_EVENTS) do
    pcall(function() self.frame:RegisterEvent(ev) end)
  end
end
