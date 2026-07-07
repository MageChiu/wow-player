local addonName, ns = ...

local Config = {}
ns.Config = ns.Core:RegisterModule("Config", Config)

local Utils = ns.Utils

-- SavedVariables 在 ADDON_LOADED 后才保证就绪，Core:Init 正是此时运行，
-- 故在此读取全局是安全的。
function Config:Init()
  if type(SudokuDB) ~= "table" then
    SudokuDB = {}
  end
  self.db = SudokuDB
  Utils.DeepMergeDefaults(self.db, ns.Defaults)
end

-- 解析 "profile.difficulty" 这样的点路径为 (parentTable, key)。
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

-- 对局快照读写：交给 Game 模块序列化，这里只做存取。
function Config:GetSaved()
  return self.db and self.db.saved or nil
end

function Config:SetSaved(snapshot)
  if not self.db then return end
  self.db.saved = snapshot
end

function Config:ClearSaved()
  if not self.db then return end
  self.db.saved = nil
end

-- 统计：记录一局完成，更新胜场与最佳用时。
function Config:RecordWin(difficultyKey, seconds)
  if not self.db then return end
  self.db.stats = self.db.stats or {}
  local s = self.db.stats[difficultyKey]
  if type(s) ~= "table" then
    s = { wins = 0, bestSeconds = nil }
    self.db.stats[difficultyKey] = s
  end
  s.wins = (s.wins or 0) + 1
  if type(seconds) == "number" and (not s.bestSeconds or seconds < s.bestSeconds) then
    s.bestSeconds = seconds
  end
end

function Config:GetStats(difficultyKey)
  if not self.db or not self.db.stats then return nil end
  return self.db.stats[difficultyKey]
end
