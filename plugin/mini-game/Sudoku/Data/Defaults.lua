local addonName, ns = ...

-- SavedVariables 结构（账号级 SudokuDB）。
--   profile: 用户偏好（难度、笔记默认开关、是否显示小地图按钮/角度）。
--   saved:   未完成的一局快照，登录后可继续。
--   stats:   各难度完成局数与最佳用时。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    difficulty = "easy",
    autoHighlight = true,       -- 高亮同数字与冲突。
    showMistakes = true,        -- 填错（与唯一解不符）立即标红。
    showMinimapButton = true,
    minimapButtonAngle = 210,   -- 初始角度（度），落在小地图圆环外侧。
  },

  -- 进行中的对局快照；无则为 nil。结构见 Game:Serialize。
  saved = nil,

  -- 统计：key 为难度 key。
  stats = {
    -- easy = { wins = 0, bestSeconds = nil },
  },
}
