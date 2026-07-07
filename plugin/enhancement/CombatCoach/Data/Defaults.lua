local addonName, ns = ...

-- SavedVariables 结构（账号级 CombatCoachDB）。
--   profile: 用户可调设置（/cc reset 会还原）。
--   history: 最近若干场战斗的复盘快照（环形，最新在前）。
--
-- 设计原则：这个插件只做"战斗结束后的复盘 + 少而准的改进点"。它不做实时
-- 伤害表、不做威胁值、不做团队排名——那些是 Details!/Skada 的职责。
-- 数据全部来自战斗日志（CLEU），因此只对"日志范围内的自己与队友"负责。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    -- 战斗结束是否自动弹出报告窗口。关掉则只用 /cc 手动看。
    autoShowReport = true,

    -- 生成报告的最短战斗时长（秒）。太短的战斗没有分析价值。
    minSegmentSeconds = 5,

    -- 报告里最多展示几条改进点（按严重度排序取前 N）。宁缺毋滥。
    maxSuggestions = 5,

    -- 是否只在首领战（ENCOUNTER）后弹报告，忽略普通打怪。
    onlyBossFights = false,

    -- 各项指标的判据阈值。集中在这里，方便按体验微调，不散落在规则里。
    thresholds = {
      activeTimePct = 0.95,   -- 活跃时间低于此值 -> 有空档
      overhealPct = 0.40,     -- 过量治疗高于此比例 -> 治疗手法/选目标问题
      uptimePct = 0.90,       -- 维持类 debuff/buff 覆盖率低于此值 -> 掉了没续
      mitigationPct = 0.55,   -- 坦克主动减伤覆盖率低于此值 -> 减伤没铺满
    },
  },

  history = {},
}

-- 单场战斗复盘快照的形状（仅作文档说明，实际由 Segment/Metrics 构造）：
-- history[i] = {
--   startedAt = <epoch>, duration = <sec>,
--   source = "encounter"|"combat", bossName = <string?>, kill = <bool?>,
--   role = "TANK"|"DAMAGER"|"HEALER", specID = <number>, className = <string>,
--   metrics = {
--     dps, hps, dtps,
--     activeTimePct,
--     overhealPct,
--     deaths = <number>,
--     casts = { [spellId] = <count> },
--     uptime = { [spellId] = <ratio> },
--     mitigationPct,
--     cdUsage = { [spellId] = <count> },
--   },
--   suggestions = { { id, severity, text }, ... },
-- }
