local addonName, ns = ...

-- SavedVariables 结构（账号级 CombatCoachDB）。
--   profile: 用户可调设置（/cc reset 只清采集数据，不动这里；还原设置需手动）。
--
-- 设计定位：这是一个"常驻实时技能采集/占比计量器"。窗口打开即采集并实时刷新，
-- 关闭即停止。战斗结束后可按需点「分析」对某个分段做后处理分析。
-- 采集数据只存在内存的分段里（current/overall/history），不落 SavedVariables，
-- 因此 profile 只保留少量用户偏好。分析只做有客观依据的少数判断，
-- 不做需要外部基准（如"某专精理想循环/占比"）的评判——那类基准无可靠来源。
ns.Defaults = {
  dbVersion = ns.Constants and ns.Constants.DB_VERSION or 1,

  profile = {
    -- 分段自检的最短时长（秒）：短于此的段不判定"零采集异常"。
    minSegmentSeconds = 5,

    -- 分析视图里最多展示几条改进点（按严重度排序取前 N）。宁缺毋滥。
    maxSuggestions = 5,

    -- 分析判据阈值。集中在此便于按体验微调。仅作参考值，非绝对标准。
    thresholds = {
      overhealPct = 0.40,  -- 过量治疗高于此比例 -> 提示可能过量施放
      uptimePct = 0.90,    -- 你在主动维持的光环覆盖率低于此值 -> 提示断档
    },
  },
}
