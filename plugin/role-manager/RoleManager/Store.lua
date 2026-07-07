local addonName, ns = ...

local Store = {}
ns.Store = ns.Core:RegisterModule("Store", Store)

local Utils = ns.Utils
local Const = ns.Constants

local time = time

function Store:Init()
  -- 无状态模块，读取都实时从 Config 拿。保留 Init 以统一生命周期。
end

-- 返回按更新时间倒序排列的角色快照数组。已隐藏的角色被过滤掉。
function Store:GetCharacters()
  local chars = ns.Config and ns.Config:GetChars() or {}
  local list = {}
  local showOffline = ns.Config:Get("profile.overviewShowOffline")
  local selfKey = Utils.CharKey()
  for key, rec in pairs(chars) do
    local visible = (showOffline or key == selfKey) and not ns.Config:IsCharHidden(key)
    if visible then
      list[#list + 1] = rec
    end
  end
  table.sort(list, function(a, b)
    return (a.updatedAt or 0) > (b.updatedAt or 0)
  end)
  return list
end

-- 战团银行金币（账号共享，单一值）。
function Store:GetWarbandMoney()
  local acc = ns.Config and ns.Config:GetAccount()
  if not acc then return nil end
  return acc.warbandMoney, acc.warbandMoneyAt
end

-- 所有角色个人金币合计。
function Store:GetGoldTotal()
  local total = 0
  for _, rec in pairs(ns.Config:GetChars()) do
    total = total + (rec.money or 0)
  end
  return total
end

-- 距离每周重置的剩余秒数（用于判断快照是否跨周期已失效）。
function Store:SecondsUntilWeeklyReset()
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    local ok, s = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if ok then return s end
  end
  return nil
end

-- 判断某快照的"本周期数据"是否已过期：更新时间早于本周重置点。
-- 本周重置点 = now + 剩余秒数 - 7 天。早于它说明是上周期采集的。
function Store:IsWeeklyStale(updatedAt)
  if type(updatedAt) ~= "number" then return true end
  local remain = self:SecondsUntilWeeklyReset()
  if not remain then return false end
  local weekStart = time() + remain - 7 * 24 * 3600
  return updatedAt < weekStart
end

-- 把宝库某分类整理为 "已达成档/总档" 概览，返回 progress, unlockedSlots, totalSlots。
function Store:SummarizeVault(rec, vaultType)
  local bucket = rec.vault and rec.vault[vaultType]
  if type(bucket) ~= "table" or #bucket == 0 then
    return 0, 0, 0
  end
  local progress = 0
  local unlocked, total = 0, #bucket
  for _, slot in ipairs(bucket) do
    if (slot.progress or 0) > progress then progress = slot.progress end
    if (slot.progress or 0) >= (slot.threshold or 0) and (slot.threshold or 0) > 0 then
      unlocked = unlocked + 1
    end
  end
  return progress, unlocked, total
end

-- 团本本周进度文本，如 "4/6 (2档)"。
function Store:RaidText(rec)
  local progress, unlocked = self:SummarizeVault(rec, Const.VAULT_TYPE.RAID)
  local maxThreshold = 0
  local bucket = rec.vault and rec.vault[Const.VAULT_TYPE.RAID]
  if bucket then
    for _, slot in ipairs(bucket) do
      if (slot.threshold or 0) > maxThreshold then maxThreshold = slot.threshold end
    end
  end
  if maxThreshold == 0 then return "—" end
  return string.format("%d/%d·%d档", progress, maxThreshold, unlocked)
end

-- 大秘境本周进度文本，如 "3场·最高+10"。仅本周场次统计。
function Store:MythicText(rec)
  local m = rec.mplus
  if not m or (m.weeklyCount or 0) == 0 then return "—" end
  local best = m.weeklyBest or 0
  return string.format("%d场·最高+%d", m.weeklyCount or 0, best)
end

-- 当前持有钥石文本，如 "通道之厅+10"；无则返回 "无"。
function Store:KeystoneText(rec)
  local m = rec.mplus
  if not m or not m.keystoneLevel then return "无" end
  local mapName = m.keystoneMap
  if mapName and mapName ~= "" then
    return string.format("%s+%d", mapName, m.keystoneLevel)
  end
  return string.format("+%d", m.keystoneLevel)
end

-- 宝库整体解锁槽数文本，如 "宝库 5/9"。遍历所有实际返回的活动分类，
-- 避免依赖某个可能变动的枚举值（如世界/地下堡分类）。
function Store:VaultText(rec)
  if type(rec.vault) ~= "table" then return "—" end
  local total, unlocked = 0, 0
  for vt in pairs(rec.vault) do
    local _, u, t = self:SummarizeVault(rec, vt)
    unlocked = unlocked + u
    total = total + t
  end
  if total == 0 then return "—" end
  return string.format("%d/%d", unlocked, total)
end

-- 周任务完成情况文本，如 "2/3"。
function Store:WeeklyQuestText(rec)
  local quests = ns.Config:Get("profile.weeklyQuests") or {}
  local total, done = 0, 0
  for questID in pairs(quests) do
    total = total + 1
    if rec.weeklyQuests and rec.weeklyQuests[questID] then done = done + 1 end
  end
  if total == 0 then return "—" end
  return string.format("%d/%d", done, total)
end
