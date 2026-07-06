local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

function Config:Init()
  if type(QuickDisenchantDB) ~= "table" then
    QuickDisenchantDB = {}
  end
  self.db = QuickDisenchantDB
  Utils.DeepMergeDefaults(self.db, ns.Defaults)
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

-- 品质分级开关。
function Config:IsTierEnabled(tier)
  return self:Get("profile.tiers." .. tostring(tier)) == true
end

function Config:SetTierEnabled(tier, enabled)
  self:Set("profile.tiers." .. tostring(tier), enabled and true or false)
end

-- 白名单：itemID -> true。
function Config:IsNeverListed(itemID)
  if not itemID then return false end
  local list = self:Get("profile.neverList") or {}
  return list[itemID] == true
end

function Config:SetNeverListed(itemID, never)
  if not itemID then return end
  local list = self:Get("profile.neverList") or {}
  list[itemID] = never and true or nil
  self:Set("profile.neverList", list)
end

function Config:GetNeverList()
  return self:Get("profile.neverList") or {}
end

-- 还原用户设置。
function Config:ResetProfile()
  if not self.db then return end
  self.db.profile = Utils.DeepCopy(ns.Defaults.profile)
end
