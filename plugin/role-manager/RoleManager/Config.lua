local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

function Config:Init()
  if type(RoleManagerDB) ~= "table" then
    RoleManagerDB = {}
  end
  self.db = RoleManagerDB
  self:_migrate()
  Utils.DeepMergeDefaults(self.db, ns.Defaults)
end

-- 一次性存档迁移。按 dbVersion 逐步执行，执行后把版本号提到最新。
function Config:_migrate()
  local Const = ns.Constants
  local from = tonumber(self.db.dbVersion) or 1

  -- v1 → v2：清除 v1 曾硬编码写入存档的过时默认货币（如神勇石 3008）。
  -- 逐个剔除已知的遗留 ID，不影响用户自己勾选的其他货币。
  if from < 2 then
    local list = self.db.profile and self.db.profile.trackedCurrencies
    if type(list) == "table" then
      local legacy = {}
      for _, id in ipairs(Const.LEGACY_DEFAULT_CURRENCIES or {}) do legacy[id] = true end
      for i = #list, 1, -1 do
        if legacy[list[i]] then table.remove(list, i) end
      end
    end
  end

  self.db.dbVersion = Const.DB_VERSION or from
end

local function resolve(db, path, createMissing)
  local node = db
  local lastKey
  for segment in tostring(path):gmatch("[^%.]+") do
    if lastKey ~= nil then
      local child = node[lastKey]
      if type(child) ~= "table" then
        if not createMissing then return nil, nil end
        child = {}
        node[lastKey] = child
      end
      node = child
    end
    lastKey = segment
  end
  return node, lastKey
end

function Config:Get(path)
  if not self.db then return nil end
  local parent, key = resolve(self.db, path, false)
  if not parent or key == nil then return nil end
  return parent[key]
end

function Config:Set(path, value)
  if not self.db then return end
  local parent, key = resolve(self.db, path, true)
  if not parent or key == nil then return end
  parent[key] = value
end

function Config:GetProfile()
  return self.db and self.db.profile
end

function Config:GetChars()
  if not self.db.chars then self.db.chars = {} end
  return self.db.chars
end

function Config:GetAccount()
  if not self.db.account then self.db.account = {} end
  return self.db.account
end

-- 货币追踪：增/删/查。存于 profile.trackedCurrencies（ID 数组）。
function Config:IsCurrencyTracked(id)
  local list = self:Get("profile.trackedCurrencies") or {}
  for _, v in ipairs(list) do
    if v == id then return true end
  end
  return false
end

function Config:SetCurrencyTracked(id, tracked)
  local list = self:Get("profile.trackedCurrencies") or {}
  local found
  for i, v in ipairs(list) do
    if v == id then found = i break end
  end
  if tracked and not found then
    list[#list + 1] = id
  elseif not tracked and found then
    table.remove(list, found)
  end
  self:Set("profile.trackedCurrencies", list)
end

-- 角色显示：隐藏集合，键为 "名-服"。
function Config:IsCharHidden(key)
  local hidden = self:Get("profile.hiddenChars") or {}
  return hidden[key] == true
end

function Config:SetCharHidden(key, hidden)
  local map = self:Get("profile.hiddenChars") or {}
  map[key] = hidden and true or nil
  self:Set("profile.hiddenChars", map)
end

-- 周任务：存于 profile.weeklyQuests = { [questID]=显示名 }。
function Config:AddWeeklyQuest(id, name)
  id = tonumber(id)
  if not id then return end
  local quests = self:Get("profile.weeklyQuests") or {}
  if not name or name == "" then
    -- 名称留空时优先取游戏内任务名，取不到回退 "任务 <ID>"。
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
      local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
      if ok and type(title) == "string" and title ~= "" then name = title end
    end
    if not name or name == "" then name = "任务 " .. id end
  end
  quests[id] = name
  self:Set("profile.weeklyQuests", quests)
end

function Config:RemoveWeeklyQuest(id)
  id = tonumber(id)
  if not id then return end
  local quests = self:Get("profile.weeklyQuests") or {}
  quests[id] = nil
  self:Set("profile.weeklyQuests", quests)
end

-- 还原用户设置；角色快照与账号数据保留。
function Config:ResetProfile()
  if not self.db then return end
  self.db.profile = Utils.DeepCopy(ns.Defaults.profile)
end

-- 清空所有缓存的角色快照（/rm reset all）。
function Config:WipeChars()
  if not self.db then return end
  self.db.chars = {}
  self.db.account = Utils.DeepCopy(ns.Defaults.account)
end
