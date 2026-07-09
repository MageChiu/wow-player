local addonName, ns = ...

local Collector = {}
ns.Collector = ns.Core:RegisterModule("Collector", Collector)

local Utils = ns.Utils
local Const = ns.Constants

local time = time
local wipe = wipe

-- 所有 WoW API 访问都走 pcall 包裹，客户端不同版本缺函数时不炸。
local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f
end

-- 采集当前角色的静态身份信息。
local function collectIdentity(rec)
  rec.name = UnitName and UnitName("player") or rec.name
  rec.realm = (GetRealmName and GetRealmName()) or rec.realm
  rec.level = UnitLevel and UnitLevel("player") or rec.level
  local _, classFile = safe(UnitClass, "player")
  rec.class = classFile or rec.class
  rec.faction = safe(UnitFactionGroup, "player") or rec.faction
end

-- 个人金币（身上/背包）。TWW 已把角色金币统一为一个值。
local function collectMoney(rec)
  rec.money = safe(GetMoney) or rec.money or 0
end

-- 战团银行金币（账号共享）。存到 account 段，所有角色同一个值。
-- 只有当 API 返回非 nil 时才更新，避免离开银行区域时被清空。
local function collectWarbandMoney()
  if not C_Bank or not C_Bank.FetchDepositedMoney then return end
  local amount = safe(C_Bank.FetchDepositedMoney, Const.BANK_TYPE_ACCOUNT)
  if type(amount) == "number" then
    local acc = ns.Config:GetAccount()
    acc.warbandMoney = amount
    acc.warbandMoneyAt = time()
  end
end

-- 追踪货币（代币 / roll 币）。显示的唯一依据是"当前货币列表 ∩ 已勾选"：
-- 只有既被用户勾选、又存在于当前货币列表里的货币才采集。非当前赛季/已下架
-- 的货币（如旧的神勇石）即使存档里仍被追踪，也不在此显示——config 优先。
local function collectCurrencies(rec)
  rec.currencies = rec.currencies or {}
  wipe(rec.currencies)
  if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return end

  -- 当前货币列表（面板可见范围）。列表为空（登录早期未就绪）时不清空既有
  -- 数据、直接返回，避免把上次采到的货币误抹掉。
  local ownedList, ownedSet = ns.Utils.EnumerateOwnedCurrencies()
  if not ownedList or #ownedList == 0 then return end

  local tracked = ns.Config:Get("profile.trackedCurrencies") or {}
  for _, id in ipairs(tracked) do
    if ownedSet[id] then
      local info = safe(C_CurrencyInfo.GetCurrencyInfo, id)
      if type(info) == "table" and info.name and info.name ~= "" then
        rec.currencies[id] = {
          name = info.name,
          quantity = info.quantity or 0,
          max = info.maxQuantity or 0,
          earnedThisWeek = info.quantityEarnedThisWeek or 0,
          icon = info.iconFileID,
        }
      end
    end
  end
end

-- 宝库进度：三类活动（大秘境/团本/世界）各三档 slot。
-- 每档含 threshold（需要的次数）与 progress（本周已达成）。
local function collectVault(rec)
  rec.vault = rec.vault or {}
  wipe(rec.vault)
  if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return end
  local activities = safe(C_WeeklyRewards.GetActivities)
  if type(activities) ~= "table" then return end
  for _, a in ipairs(activities) do
    local t = a.type
    if t then
      local bucket = rec.vault[t]
      if not bucket then
        bucket = {}
        rec.vault[t] = bucket
      end
      bucket[#bucket + 1] = {
        index = a.index,
        threshold = a.threshold or 0,
        progress = a.progress or 0,
        level = a.level or 0,
      }
    end
  end
end

-- 大秘境本周进度：本周完成的钥石场次（层数/地图），以及当前持有的钥石。
-- 钥石不是货币，必须用 C_MythicPlus 专用接口读，不能靠货币面板。
local function collectMythicPlus(rec)
  rec.mplus = rec.mplus or {}
  wipe(rec.mplus)
  if not C_MythicPlus then return end

  -- 本周完成场次。includePreviousWeeks=false, includeIncompleteRuns=false。
  if C_MythicPlus.GetRunHistory then
    local runs = safe(C_MythicPlus.GetRunHistory, false, false)
    local best, count = 0, 0
    if type(runs) == "table" then
      for _, r in ipairs(runs) do
        if r.thisWeek ~= false then
          count = count + 1
          if (r.level or 0) > best then best = r.level end
        end
      end
    end
    rec.mplus.weeklyCount = count
    rec.mplus.weeklyBest = best
  end

  -- 当前持有的钥石（层数 + 地图名）。
  local level = safe(C_MythicPlus.GetOwnedKeystoneLevel)
  if type(level) == "number" and level > 0 then
    rec.mplus.keystoneLevel = level
    local mapID = safe(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
      or safe(C_MythicPlus.GetOwnedKeystoneMapID)
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
      local mapName = safe(C_ChallengeMode.GetMapUIInfo, mapID)
      rec.mplus.keystoneMap = mapName
    end
  end

  rec.mplus.rating = safe(C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) or 0
end

-- 可配置周任务的完成状态。配置 profile.weeklyQuests 是 {[questID]=显示名}，
-- 这里只读取它的 key（任务 ID），把完成状态写到独立字段 rec.weeklyQuestDone，
-- 不覆写配置本身。
local function collectWeeklyQuests(rec)
  rec.weeklyQuestDone = rec.weeklyQuestDone or {}
  wipe(rec.weeklyQuestDone)
  local quests = ns.Config:Get("profile.weeklyQuests") or {}
  if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
  for questID in pairs(quests) do
    local done = safe(C_QuestLog.IsQuestFlaggedCompleted, tonumber(questID))
    rec.weeklyQuestDone[questID] = done and true or false
  end
end

-- 采集当前角色全部数据并写回缓存。可被多个事件触发，需幂等。
function Collector:CollectSelf()
  if not ns.Config or not ns.Config.db then return end
  local chars = ns.Config:GetChars()
  local key = Utils.CharKey()
  local rec = chars[key]
  if type(rec) ~= "table" then
    rec = {}
    chars[key] = rec
  end

  collectIdentity(rec)
  collectMoney(rec)
  collectWarbandMoney()
  collectCurrencies(rec)
  collectVault(rec)
  collectMythicPlus(rec)
  collectWeeklyQuests(rec)

  rec.updatedAt = time()
  rec.key = key
end

function Collector:Init()
  self.frame = CreateFrame("Frame")
  self.frame:SetScript("OnEvent", function()
    -- 事件可能在数据尚未就绪时触发；延迟一帧再采集更稳。
    if self.pending then return end
    self.pending = true
    C_Timer.After(0.5, function()
      self.pending = false
      ns.Core:SafeCall(function() Collector:CollectSelf() end)
    end)
  end)
  for _, ev in ipairs(Const.COLLECT_EVENTS) do
    pcall(function() self.frame:RegisterEvent(ev) end)
  end
end
