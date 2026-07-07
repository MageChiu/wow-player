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
