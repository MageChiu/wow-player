local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "Sudoku"
C.SLUG = "Sudoku"
C.VERSION = "0.1.0"

-- 数据结构版本；将来改存档结构时用它做迁移判断。
C.DB_VERSION = 1

-- 难度：给出挖空数量区间。数字越多空格越多、越难。
-- 生成器会在区间内挖空并始终保证唯一解。
C.DIFFICULTY = {
  { key = "easy",   label = "简单", clues = 40 },  -- 约 41 个已知
  { key = "medium", label = "中等", clues = 32 },
  { key = "hard",   label = "困难", clues = 26 },
}

-- 难度 key -> 配置项，便于 O(1) 查询。
C.DIFFICULTY_BY_KEY = {}
for _, d in ipairs(C.DIFFICULTY) do
  C.DIFFICULTY_BY_KEY[d.key] = d
end

C.DEFAULT_DIFFICULTY = "easy"

-- 棋盘尺寸常量。
C.SIZE = 9        -- 9x9
C.BOX = 3         -- 3x3 宫
C.CELLS = 81
