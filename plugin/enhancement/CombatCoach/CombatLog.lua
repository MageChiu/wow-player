local addonName, ns = ...

local CombatLog = {}
ns.CombatLog = ns.Core:RegisterModule("CombatLog", CombatLog)

local Const = ns.Constants
local CLEU_KIND = Const.CLEU_KIND
local MELEE = Const.MELEE_SPELL_ID

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local UnitExists = UnitExists

-- 我们只跟踪自己与自己的召唤物（宠物/图腾/守护/镜像等）。别的 GUID 直接丢，
-- 避免累加全团数据（那是 Details! 的活，也会拖垮性能）。
-- ownedGUIDs 是"归属于我"的 GUID 集合：自己 + 当前宠物 + 运行时通过
-- SPELL_SUMMON 发现的召唤物。这样多召唤物职业的伤害不再漏。
local selfGUID = nil
local ownedGUIDs = {}

local function refreshGUIDs()
  selfGUID = UnitGUID and UnitGUID("player") or nil
  wipe(ownedGUIDs)
  if selfGUID then ownedGUIDs[selfGUID] = true end
  if UnitExists and UnitExists("pet") then
    local pg = UnitGUID("pet")
    if pg then ownedGUIDs[pg] = true end
  end
end

-- 判断某 GUID 是否属于"我方"。selfGUID 尚未就绪时惰性补取一次，
-- 防止登录早期 GUID 为 nil 导致整场伤害被判成"不是我打的"而丢弃。
local function isMine(guid)
  if not guid then return false end
  if not selfGUID then refreshGUIDs() end
  return ownedGUIDs[guid] == true
end

-- 调试计数器：用来定位"采集不到"到底断在哪一环。由 /cc debug 读取。
local dbg = {
  cleuTotal = 0,
  cleuRecorded = 0,
  mineSrc = 0,
  dmgAdds = 0,
  knownKind = 0,
  lastSub = "",
  lastSrc = "",
}
CombatLog.dbg = dbg

function CombatLog:DebugText()
  local owned = 0
  for _ in pairs(ownedGUIDs) do owned = owned + 1 end
  return {
    "===== CombatCoach 诊断 =====",
    "采集中: " .. (ns.Segment:IsRecording() and "是" or "否（打开窗口即开始）"),
    "selfGUID: " .. tostring(selfGUID),
    "归属GUID数: " .. owned,
    "战斗段: " .. (ns.Segment.current and "进行中" or "无"),
    string.format("CLEU 总数: %d | 采集: %d", dbg.cleuTotal, dbg.cleuRecorded),
    string.format("命中类型: %d | 判定我方: %d | 记伤害: %d",
      dbg.knownKind, dbg.mineSrc, dbg.dmgAdds),
    "最近子事件: " .. tostring(dbg.lastSub),
    "最近来源GUID: " .. tostring(dbg.lastSrc),
  }
end

-- ---- CLEU 分派：热路径，务必精简 ----
-- 基础参数：timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags,
--   sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, 之后是子事件参数。
-- SPELL 前缀：12=spellId 13=spellName 14=school；_DAMAGE 后缀：15=amount。
-- SWING 无前缀：12=amount。（已对照 Wowpedia/wowcoach.gg 12.0+ 规范核对）
local function handleCLEU()
  dbg.cleuTotal = dbg.cleuTotal + 1
  if not ns.Segment.recording then return end
  dbg.cleuRecorded = dbg.cleuRecorded + 1

  local _, subevent, _, sourceGUID, _, _, _,
        destGUID, _, _, _,
        p12, p13, p14, p15, p16, p17, p18 = CombatLogGetCurrentEventInfo()

  dbg.lastSub = subevent
  dbg.lastSrc = sourceGUID

  local kind = CLEU_KIND[subevent]
  if not kind then return end
  dbg.knownKind = dbg.knownKind + 1

  if kind == "damage" then
    if isMine(sourceGUID) then
      dbg.mineSrc = dbg.mineSrc + 1
      dbg.dmgAdds = dbg.dmgAdds + 1
      if subevent == "SWING_DAMAGE" then
        ns.Segment:AddDamageDone(MELEE, "自动攻击", p12 or 0)
      else
        ns.Segment:AddDamageDone(p12 or 0, p13, p15 or 0)
      end
    end
    if destGUID == selfGUID then
      if subevent == "SWING_DAMAGE" then
        ns.Segment:AddDamageTaken(p12 or 0)
      else
        ns.Segment:AddDamageTaken(p15 or 0)
      end
    end

  elseif kind == "heal" then
    -- SPELL_HEAL: 12=spellId 13=name 15=amount 16=overheal 17=absorbed
    if isMine(sourceGUID) then
      ns.Segment:AddHeal(p12 or 0, p13, p15 or 0, p16 or 0)
    end

  elseif kind == "absorb" then
    if isMine(sourceGUID) then
      local absorbed = tonumber(p18) or tonumber(p17) or tonumber(p16) or 0
      ns.Segment:AddAbsorb(absorbed)
    end

  elseif kind == "cast" then
    if isMine(sourceGUID) then
      ns.Segment:AddCast(p12 or 0, p13)
    end

  elseif kind == "aura_on" then
    if isMine(sourceGUID) or destGUID == selfGUID then
      ns.Segment:AuraOn(p12 or 0, p13)
    end

  elseif kind == "aura_off" then
    if isMine(sourceGUID) or destGUID == selfGUID then
      ns.Segment:AuraOff(p12 or 0)
    end

  elseif kind == "summon" then
    -- 我召唤出来的单位，纳入归属集合，其后续伤害才会算作我的。
    if isMine(sourceGUID) and destGUID then
      ownedGUIDs[destGUID] = true
    end

  elseif kind == "interrupt" then
    if isMine(sourceGUID) then ns.Segment:AddInterrupt() end

  elseif kind == "dispel" then
    if isMine(sourceGUID) then ns.Segment:AddDispel() end

  elseif kind == "death" then
    if destGUID == selfGUID then ns.Segment:AddDeath() end
  end
end

-- ---- 战斗边界：仅在采集中时划分战斗段，且不再触发任何分析/弹窗 ----
function CombatLog:OnEvent(event, ...)
  if event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PET" then
    refreshGUIDs()

  elseif event == "ENCOUNTER_START" then
    local encounterID, encounterName = ...
    refreshGUIDs()
    ns.Segment:StartCombat(Const.SEGMENT_SOURCE.ENCOUNTER, {
      encounterID = encounterID, name = encounterName,
    })

  elseif event == "ENCOUNTER_END" then
    local _, _, _, _, success = ...
    if ns.Segment:Get() then
      ns.Segment:FinishCurrent(success == 1)
      if ns.MeterFrame then ns.MeterFrame:OnSegmentEnd() end
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    refreshGUIDs()
    ns.Segment:StartCombat(Const.SEGMENT_SOURCE.COMBAT)

  elseif event == "PLAYER_REGEN_ENABLED" then
    if ns.Segment:Get() then
      ns.Segment:FinishCurrent()
      if ns.MeterFrame then ns.MeterFrame:OnSegmentEnd() end
    end
  end
end

-- ---- 采集开关：由计量窗口驱动。窗口开=注册 CLEU 并开始采集，关=注销停采 ----
function CombatLog:SetRecording(on)
  if on then
    refreshGUIDs()
    ns.Segment:StartRecording()
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  else
    ns.Segment:StopRecording()
    self.frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  end
end

function CombatLog:Init()
  refreshGUIDs()
  self.frame = CreateFrame("Frame")
  self.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      handleCLEU()
    else
      local a1, a2, a3, a4, a5 = ...
      ns.Core:SafeCall(function() CombatLog:OnEvent(event, a1, a2, a3, a4, a5) end)
    end
  end)
  -- 边界/生命周期事件常驻注册（开销极小）；CLEU 只在采集时注册。
  for _, ev in ipairs(Const.LIFECYCLE_EVENTS) do
    pcall(function() self.frame:RegisterEvent(ev) end)
  end
end
