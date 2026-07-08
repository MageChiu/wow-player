local addonName, ns = ...

-- 数独生成与求解。
--
-- 表示：棋盘为长度 81 的一维数组 g[1..81]，值 0 表示空，1..9 为数字。
-- (row,col) 与下标互转见 Utils.Index / Utils.RowCol。
--
-- 关键约束：挖空后必须"唯一解"。故生成流程为：
--   1) 随机回溯填出一整盘合法完整解（terminal）。
--   2) 打乱格子顺序，逐个尝试挖空；每挖一个就用求解器数解，
--      若解不再唯一则撤销该挖空。直到达到目标已知数（clues）。
local Generator = {}
ns.Generator = ns.Core:RegisterModule("Generator", Generator)

local Const = ns.Constants

-- 3x3 宫下标（0..8）。
local function boxOf(r, c)
  return math.floor((r - 1) / 3) * 3 + math.floor((c - 1) / 3)
end

-- Fisher–Yates 洗牌。
local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- 从棋盘构建 行/列/宫 的已用数字标记（used[x] 为 9 位布尔表）。
local function buildMarks(g)
  local rowU, colU, boxU = {}, {}, {}
  for i = 1, 9 do rowU[i] = {}; colU[i] = {} end
  for i = 0, 8 do boxU[i] = {} end
  for idx = 1, 81 do
    local v = g[idx]
    if v ~= 0 then
      local r = math.floor((idx - 1) / 9) + 1
      local c = (idx - 1) % 9 + 1
      rowU[r][v] = true
      colU[c][v] = true
      boxU[boxOf(r, c)][v] = true
    end
  end
  return rowU, colU, boxU
end

-- 求解器：从当前棋盘出发数解，最多数到 limit（用于唯一性判定，limit=2 即可）。
-- 采用 MRV（选候选最少的空格）以显著减少回溯。返回解的个数（0/1/.../limit）。
local function countSolutions(g, limit)
  local rowU, colU, boxU = buildMarks(g)
  local count = 0

  local function solve()
    if count >= limit then return end

    -- 选候选最少的空格。
    local bestIdx, bestCands, bestCount = nil, nil, 10
    for idx = 1, 81 do
      if g[idx] == 0 then
        local r = math.floor((idx - 1) / 9) + 1
        local c = (idx - 1) % 9 + 1
        local b = boxOf(r, c)
        local ru, cu, bu = rowU[r], colU[c], boxU[b]
        local cands, n = {}, 0
        for d = 1, 9 do
          if not ru[d] and not cu[d] and not bu[d] then
            n = n + 1
            cands[n] = d
          end
        end
        if n == 0 then return end        -- 死路，直接回溯。
        if n < bestCount then
          bestCount, bestIdx, bestCands = n, idx, cands
          if n == 1 then break end        -- 不会更好了。
        end
      end
    end

    if not bestIdx then
      -- 无空格：找到一个完整解。
      count = count + 1
      return
    end

    local r = math.floor((bestIdx - 1) / 9) + 1
    local c = (bestIdx - 1) % 9 + 1
    local b = boxOf(r, c)
    for _, d in ipairs(bestCands) do
      g[bestIdx] = d
      rowU[r][d], colU[c][d], boxU[b][d] = true, true, true
      solve()
      g[bestIdx] = 0
      rowU[r][d], colU[c][d], boxU[b][d] = nil, nil, nil
      if count >= limit then return end
    end
  end

  solve()
  return count
end

Generator.CountSolutions = countSolutions

-- 随机回溯填出一整盘完整合法解。返回长度 81 的数组。
local function makeFullSolution()
  local g = {}
  for i = 1, 81 do g[i] = 0 end
  local rowU, colU, boxU = buildMarks(g)

  local function fill(pos)
    if pos > 81 then return true end
    local idx = pos
    local r = math.floor((idx - 1) / 9) + 1
    local c = (idx - 1) % 9 + 1
    local b = boxOf(r, c)
    local ru, cu, bu = rowU[r], colU[c], boxU[b]

    local digits = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    shuffle(digits)
    for _, d in ipairs(digits) do
      if not ru[d] and not cu[d] and not bu[d] then
        g[idx] = d
        ru[d], cu[d], bu[d] = true, true, true
        if fill(pos + 1) then return true end
        g[idx] = 0
        ru[d], cu[d], bu[d] = nil, nil, nil
      end
    end
    return false
  end

  fill(1)
  return g
end

-- 生成一局。difficultyKey 缺省用默认难度。
-- 返回： puzzle（含空 0 的题面）, solution（完整解）, givens（布尔表：哪些格是题目已知）。
function Generator:Generate(difficultyKey)
  local diff = Const.DIFFICULTY_BY_KEY[difficultyKey] or Const.DIFFICULTY_BY_KEY[Const.DEFAULT_DIFFICULTY]
  local targetClues = diff and diff.clues or 40

  local solution = makeFullSolution()

  -- 从完整解出发挖空。
  local puzzle = {}
  for i = 1, 81 do puzzle[i] = solution[i] end

  local cells = {}
  for i = 1, 81 do cells[i] = i end
  shuffle(cells)

  local clues = 81
  for _, idx in ipairs(cells) do
    if clues <= targetClues then break end
    local backup = puzzle[idx]
    if backup ~= 0 then
      puzzle[idx] = 0
      -- 挖掉后仍唯一解才允许；否则还原。
      if countSolutions(puzzle, 2) ~= 1 then
        puzzle[idx] = backup
      else
        clues = clues - 1
      end
    end
  end

  local givens = {}
  for i = 1, 81 do
    givens[i] = puzzle[i] ~= 0
  end

  return puzzle, solution, givens, diff and diff.key or Const.DEFAULT_DIFFICULTY
end

function Generator:Init()
  -- 用时间做一次随机种子扰动（WoW 的 math.random 已由客户端播种，这里再扰动更随机）。
  if math.randomseed and time then
    pcall(math.randomseed, time() + math.floor((GetTime and GetTime() or 0) * 1000))
  end
end
