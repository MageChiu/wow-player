local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "WowPlayerSuite"
C.SLUG = "WowPlayerSuite"
C.VERSION = "0.1.0"

-- 全局握手对象的名字。供愿意深度集成的插件可选地自愿上报（见 Discovery.lua）。
C.API_GLOBAL = "WowPlayerSuiteAPI"

-- 数据结构版本；将来改存档结构时用它做迁移判断。
C.DB_VERSION = 1

-- 分类：约定「plugin/ 下的一级目录 = 一个分类」。键为一级目录名，值为
-- 概览页显示的中文分类名。新增分类时在此加一行；Discovery.KNOWN 每条的
-- category 必须等于该插件所在的一级目录名（打包脚本会交叉校验）。
C.CATEGORY = {
  ["chat"]         = "聊天增强",
  ["role-manager"] = "角色数据",
  ["enhancement"]  = "战斗增强",
  ["trade"]        = "物品与交易",
  ["mini-game"]    = "休闲小游戏",
}

-- 概览页分组的显示顺序（未列出的分类排在最后）。
C.CATEGORY_ORDER = {
  "chat",
  "role-manager",
  "enhancement",
  "trade",
  "mini-game",
}
