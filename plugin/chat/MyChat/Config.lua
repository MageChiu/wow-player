local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

-- SavedVariables is only guaranteed populated after ADDON_LOADED, which is
-- also when Core:Init runs, so reading the global here is safe.
function Config:Init()
  if type(MyChatDB) ~= "table" then
    MyChatDB = {}
  end
  self.db = MyChatDB
  -- Fill any missing keys from defaults without clobbering user values.
  Utils.DeepMergeDefaults(self.db, ns.Defaults)
end

-- Resolve a dot path like "profile.showTimestamps" to (parentTable, key).
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
  self.dirty = true
end

function Config:GetProfile()
  return self.db and self.db.profile
end

function Config:GetRuntime()
  return self.db and self.db.runtime
end

-- Reset only the profile; runtime state (whisper history, joined channels)
-- is intentionally preserved.
function Config:ResetProfile()
  if not self.db then return end
  self.db.profile = Utils.DeepCopy(ns.Defaults.profile)
  self.dirty = true
end
