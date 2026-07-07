local addonName, ns = ...

-- SavedVariables 结构（账号级 QuickDisenchantDB）。
--   profile: 用户可调设置（/qde reset 会还原）。
--
-- 设计原则：分解什么完全由用户明确决定——品质分级开关 + 面板逐件勾选，
-- 双重把关，避免误分解。默认只圈"优良（绿）"，蓝/紫需手动开启分级开关。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    -- 品质分级开关：某品质开启后，该品质装备才会进入候选。
    -- 默认仅绿装，蓝/紫默认关闭（更安全）。
    tiers = {
      uncommon = true,
      rare = false,
      epic = false,
    },

    -- 永不分解白名单：键为 itemID，值为 true。面板/命令可加。
    neverList = {},

    -- 是否忽略"未绑定"的装备（避免误分解还能退货/上架的新装）。
    -- 默认 true：只分解已绑定装备。
    onlyBound = true,

    -- UI 偏好。
    showMinimapButton = true,
    minimapButtonAngle = 200,

    -- 面板每次打开时是否默认全部勾选候选（false 则需手动勾）。
    autoSelectOnScan = false,
  },
}
