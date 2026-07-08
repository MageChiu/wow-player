local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

-- SavedVariables 在 ADDON_LOADED 后才保证就绪，Core:Init 正是此时运行，
-- 故在此读取全局是安全的。
function Config:Init()
  if type(WowPlayerSuiteDB) ~= "table" then
    WowPlayerSuiteDB = {}
  end
  self.db = WowPlayerSuiteDB
  Utils.DeepMergeDefaults(self.db, ns.Defaults)
end

-- 解析 "profile.showMinimapButton" 这样的点路径为 (parentTable, key)。
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

function Config:ResetProfile()
  if not self.db then return end
  self.db.profile = Utils.DeepCopy(ns.Defaults.profile)
end
