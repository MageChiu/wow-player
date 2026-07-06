local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

function Config:Init()
  if type(CombatCoachDB) ~= "table" then
    CombatCoachDB = {}
  end
  self.db = CombatCoachDB
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

function Config:GetProfile()
  return self.db and self.db.profile
end

-- 历史战斗段数组（最新在前）。运行时由 Store 维护。
function Config:GetHistory()
  if not self.db.history then self.db.history = {} end
  return self.db.history
end

-- 还原用户设置；历史战斗记录保留。
function Config:ResetProfile()
  if not self.db then return end
  self.db.profile = Utils.DeepCopy(ns.Defaults.profile)
end

-- 清空所有历史战斗记录。
function Config:WipeHistory()
  if not self.db then return end
  self.db.history = {}
end
