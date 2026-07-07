local addonName, ns = ...

-- SavedVariables 结构（账号级 WowPlayerSuiteDB）。
--   profile: 用户可调设置（/wp reset 会还原）。
--
-- 设计原则：Hub 不保管任何"属于子插件的配置"。这里只放 Hub 自身的
-- 界面偏好（小地图按钮位置等）。子插件配置的真相源永远在各自的 DB。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    -- 小地图按钮。
    showMinimapButton = true,
    minimapButtonAngle = 195,   -- 初始角度（度），落在小地图圆环外侧。
  },
}
