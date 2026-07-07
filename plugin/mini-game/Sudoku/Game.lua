local addonName, ns = ...

-- 对局逻辑：持有当前棋盘状态、处理填数/擦除/笔记/提示/检查/胜负，
-- 并负责序列化到 SavedVariables（登录后继续未完成的一局）。
--
-- 状态字段：
--   given[i]     boolean  是否为题目已知（不可修改）
--   value[i]     0..9     玩家当前填入（含 given；0 为空）
--   solution[i]  1..9     唯一解
--   notes[i]     table    该格的铅笔笔记 { [d]=true }
--   difficulty   string   难度 key
--   elapsed      number   已用秒数（快照时刻）
--   startedAt    number   本次会话开始计时的 GetTime 基准
--   won          boolean  是否已完成
local Game = {}
ns.Game = ns.Core:RegisterModule("Game", Game)

local Utils = ns.Utils
local Const = ns.Constants

local function boxOf(r, c)
  return math.floor((r - 1) / 3) * 3 + math.floor((c - 1) / 3)
end

-- 复制长度 81 的数组，避免存档与运行时状态共享同一张表。
local function copyBoard(src)
  local out = {}
  for i = 1, 81 do out[i] = src[i] end
  return out
end

function Game:Init()
  -- 若有未完成的存档则恢复，否则等玩家开新局。
  local snap = ns.Config:GetSaved()
  if snap then
    self:Restore(snap)
  end
end

function Game:HasGame()
  return self.value ~= nil
end

-- 开新局。difficultyKey 缺省用配置里的难度。
function Game:NewGame(difficultyKey)
  difficultyKey = difficultyKey or ns.Config:Get("profile.difficulty") or Const.DEFAULT_DIFFICULTY

  local puzzle, solution, givens, usedKey = ns.Generator:Generate(difficultyKey)

  self.difficulty = usedKey
  self.given = givens
  self.solution = solution
  self.value = {}
  self.notes = {}
  for i = 1, 81 do
    self.value[i] = puzzle[i]
    self.notes[i] = {}
  end
  self.elapsed = 0
  self.startedAt = GetTime and GetTime() or 0
  self.won = false
  self.selected = nil

  ns.Config:Set("profile.difficulty", usedKey)
  self:Save()
end

-- 当前累计用时（秒）。进行中会叠加本次会话的实时增量。
function Game:GetElapsed()
  local base = self.elapsed or 0
  if not self.won and self.startedAt and GetTime then
    base = base + (GetTime() - self.startedAt)
  end
  return math.floor(base)
end

-- 冻结计时：把实时增量并入 elapsed，重置基准。用于暂停/保存/胜利。
local function freezeClock(self)
  if self.startedAt and GetTime then
    self.elapsed = (self.elapsed or 0) + (GetTime() - self.startedAt)
    self.startedAt = GetTime()
  end
end

function Game:Select(index)
  if index and (index < 1 or index > 81) then return end
  self.selected = index
end

function Game:GetSelected()
  return self.selected
end

function Game:IsGiven(index)
  return self.given and self.given[index] == true
end

function Game:GetValue(index)
  return self.value and self.value[index] or 0
end

function Game:GetNotes(index)
  return self.notes and self.notes[index] or nil
end

-- 冲突检测：同行/列/宫内是否有相同的非零值。返回布尔。
function Game:IsConflict(index)
  local v = self.value[index]
  if not v or v == 0 then return false end
  local r, c = Utils.RowCol(index)
  local b = boxOf(r, c)
  for j = 1, 81 do
    if j ~= index and self.value[j] == v then
      local r2, c2 = Utils.RowCol(j)
      if r2 == r or c2 == c or boxOf(r2, c2) == b then
        return true
      end
    end
  end
  return false
end

-- 是否填错（与唯一解不符）。仅在配置开启 showMistakes 时由 UI 使用。
function Game:IsWrong(index)
  local v = self.value[index]
  if not v or v == 0 then return false end
  return self.solution and self.solution[index] ~= v
end

-- 填入数字。given 格不可改。返回是否发生变化。
function Game:SetValue(index, digit)
  if self.won then return false end
  if not self.value or self:IsGiven(index) then return false end
  if digit < 0 or digit > 9 then return false end
  if self.value[index] == digit then return false end

  self.value[index] = digit
  -- 填入正式数字时清掉该格笔记。
  if digit ~= 0 then
    self.notes[index] = {}
  end
  self:Save()
  self:_checkWin()
  return true
end

function Game:Clear(index)
  return self:SetValue(index, 0)
end

-- 切换某格的一个铅笔笔记。given 或已填正式数字的格不记笔记。
function Game:ToggleNote(index, digit)
  if self.won then return false end
  if not self.value or self:IsGiven(index) then return false end
  if digit < 1 or digit > 9 then return false end
  if self.value[index] ~= 0 then return false end
  local n = self.notes[index]
  if not n then n = {}; self.notes[index] = n end
  n[digit] = (not n[digit]) or nil
  self:Save()
  return true
end

-- 提示：把选中空格（或第一个空格）填成正解。返回被填的下标或 nil。
function Game:Hint(index)
  if self.won or not self.value then return nil end
  local target = index
  if not target or self.value[target] ~= 0 or self:IsGiven(target) then
    target = nil
    for i = 1, 81 do
      if self.value[i] == 0 then target = i; break end
    end
  end
  if not target then return nil end
  self.value[target] = self.solution[target]
  self.notes[target] = {}
  self:Save()
  self:_checkWin()
  return target
end

-- 检查：返回填错的格子下标数组（空表示暂无错误）。
function Game:FindMistakes()
  local out = {}
  if not self.value then return out end
  for i = 1, 81 do
    local v = self.value[i]
    if v ~= 0 and not self:IsGiven(i) and self.solution[i] ~= v then
      out[#out + 1] = i
    end
  end
  return out
end

-- 剩余空格数。
function Game:RemainingCount()
  if not self.value then return 81 end
  local n = 0
  for i = 1, 81 do
    if self.value[i] == 0 then n = n + 1 end
  end
  return n
end

-- 某数字（1..9）在盘面上已正确/已填入的个数，用于键盘置灰已用完的数字。
function Game:DigitCount(digit)
  if not self.value then return 0 end
  local n = 0
  for i = 1, 81 do
    if self.value[i] == digit then n = n + 1 end
  end
  return n
end

function Game:IsWon()
  return self.won == true
end

function Game:GetDifficulty()
  return self.difficulty or Const.DEFAULT_DIFFICULTY
end

-- 胜负判定：所有格非空且与唯一解一致。
function Game:_checkWin()
  if self.won or not self.value then return end
  for i = 1, 81 do
    if self.value[i] == 0 or self.value[i] ~= self.solution[i] then
      return
    end
  end
  self.won = true
  freezeClock(self)
  local seconds = math.floor(self.elapsed or 0)
  ns.Config:RecordWin(self:GetDifficulty(), seconds)
  ns.Config:ClearSaved()
  Utils.Print(string.format("恭喜完成！用时 %s。", Utils.FormatClock(seconds)))
  -- 通知 UI 刷新胜利态。
  if ns.Board and ns.Board.OnWin then
    ns.Core:SafeCall(function() ns.Board:OnWin() end)
  end
end

-- 序列化当前对局为可存档 table。
function Game:Serialize()
  if not self.value then return nil end
  freezeClock(self)
  -- 笔记压成每格的数字数组，减少存档体积。
  local notes = {}
  for i = 1, 81 do
    local n = self.notes[i]
    if n and next(n) then
      local arr = {}
      for d = 1, 9 do if n[d] then arr[#arr + 1] = d end end
      notes[i] = arr
    end
  end
  return {
    difficulty = self.difficulty,
    given = copyBoard(self.given),
    value = copyBoard(self.value),
    solution = copyBoard(self.solution),
    notes = notes,
    elapsed = math.floor(self.elapsed or 0),
    won = self.won or false,
  }
end

-- 从存档恢复。容错：结构不完整则忽略。
function Game:Restore(snap)
  if type(snap) ~= "table" then return false end
  if type(snap.value) ~= "table" or type(snap.solution) ~= "table" or type(snap.given) ~= "table" then
    return false
  end
  self.difficulty = snap.difficulty or Const.DEFAULT_DIFFICULTY
  self.given = {}
  self.value = {}
  self.solution = {}
  self.notes = {}
  for i = 1, 81 do
    self.given[i] = snap.given[i] and true or false
    self.value[i] = tonumber(snap.value[i]) or 0
    self.solution[i] = tonumber(snap.solution[i]) or 0
    self.notes[i] = {}
  end
  if type(snap.notes) == "table" then
    for i, arr in pairs(snap.notes) do
      if type(arr) == "table" then
        for _, d in ipairs(arr) do
          if d >= 1 and d <= 9 then self.notes[i][d] = true end
        end
      end
    end
  end
  self.elapsed = tonumber(snap.elapsed) or 0
  self.startedAt = GetTime and GetTime() or 0
  self.won = snap.won and true or false
  self.selected = nil
  return true
end

-- 存档：仅在有进行中的对局（未胜利）时写入。
function Game:Save()
  if not self.value or self.won then return end
  local snap = self:Serialize()
  if snap then
    ns.Config:SetSaved(snap)
  end
end
