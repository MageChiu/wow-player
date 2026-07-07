local addonName, ns = ...

-- SavedVariables 结构（账号级 RoleManagerDB）。
--   profile: 用户可调设置（/rm reset 会还原）。
--   chars:   每个角色的最新快照，键为 "角色名-服务器"。跨账号共享的
--            战团银行金币单独存 account 段（所有角色同一个值）。
--
-- 设计原则：其他角色的数据只能是"最后登录快照"，不是实时——这是 WoW
-- 插件的硬限制，UI 必须显示每条的更新时间，避免误导。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    -- 追踪的货币（代币/roll币）。默认空——用 /rm config 从"当前拥有的货币"
    -- 里勾选即可，无需记 ID。不同赛季货币 ID 会变，故不预置任何硬编码 ID。
    trackedCurrencies = {},

    -- 不显示的角色（键为 "角色名-服务器"，值为 true）。在 /rm config 里勾选管理。
    hiddenChars = {},

    -- 可配置的每周任务清单（questID -> 显示名）。留空则只用宝库进度。
    -- 例：{ [82946] = "周常世界任务" }
    weeklyQuests = {},

    -- 代币列每角色最多显示几种（避免过长挤歪后面的列）。
    currencyDisplayLimit = 3,

    -- UI 偏好。
    showMinimapButton = true,
    minimapButtonAngle = 210,   -- 小地图按钮初始角度（度）
    overviewShowOffline = true, -- 是否显示当前未登录角色的快照

    -- 是否把角色个人金币汇总为一行合计。
    showGoldTotal = true,
  },

  -- 账号级共享数据（与具体角色无关）。
  account = {
    warbandMoney = nil,      -- C_Bank.FetchDepositedMoney(Account)
    warbandMoneyAt = nil,    -- 最后更新时间戳
  },

  -- 每角色快照，运行时由 Collector 填充。
  chars = {},
}

-- 单个角色快照的形状（仅作文档说明，实际由 Collector 构造）：
-- chars["名-服"] = {
--   name, realm, class, level, faction,
--   money = <copper>,               -- 个人背包/身上金币
--   currencies = { [id] = { quantity, name, icon, max } },
--   vault = {                       -- 宝库各类活动
--     [type] = { { threshold, progress, level }, ... }
--   },
--   mplus = { weeklyRuns = { {mapID, level, name}, ... }, best = <level> },
--   weeklyQuests = { [questID] = true/false },
--   updatedAt = <epoch>,
-- }
