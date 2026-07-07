local addonName, ns = ...

local Analyzer = {}
ns.Analyzer = ns.Core:RegisterModule("Analyzer", Analyzer)

local Utils = ns.Utils
local Const = ns.Constants
local ROLE = Const.ROLE
local SEV = Const.SEVERITY

local function threshold(key, fallback)
  local t = ns.Config and ns.Config:Get("profile.thresholds." .. key)
  if type(t) == "number" then return t end
  return fallback
end

-- 规则表。每条规则：
--   id       唯一标识（也用于将来"忽略某条建议"）。
--   roles    适用角色集合，nil 表示全部。
--   evaluate function(report) -> suggestion | nil
--            suggestion = { severity, text }
--
-- 原则：只写高置信度、跨专精都成立、不易误判的少数规则。宁缺毋滥。
-- 依赖 profile 的规则在无 profile 时自然返回 nil（表为空），不会误报。
local RULES = {

  -- 通用：活跃时间过低 = 有站桩空档（对 DPS/HEALER 最有意义）。
  {
    id = "active_time_low",
    roles = { [ROLE.DAMAGER] = true, [ROLE.HEALER] = true },
    evaluate = function(r)
      local m = r.metrics
      -- 战斗太短时活跃度估算不稳，跳过。
      if r.duration < 15 then return nil end
      local limit = threshold("activeTimePct", 0.95)
      if m.activeTimePct < limit then
        return {
          severity = SEV.SUGGEST,
          text = string.format("活跃时间约 %s（目标 >%s），存在施法空档，注意减少站桩与走位空转。",
            Utils.Pct(m.activeTimePct), Utils.Pct(limit)),
        }
      end
    end,
  },

  -- 通用：本场发生自身死亡。死亡是最硬的可执行信号。
  {
    id = "deaths",
    roles = nil,
    evaluate = function(r)
      local m = r.metrics
      if (m.deaths or 0) > 0 then
        return {
          severity = SEV.CRITICAL,
          text = string.format("本场阵亡 %d 次，优先复盘致死的机制/地板，减伤或走位没跟上。",
            m.deaths),
        }
      end
    end,
  },

  -- DPS/HEALER：主要 CD 一次没用。CD 空转是最常见的输出/治疗损失。
  {
    id = "cd_unused",
    roles = { [ROLE.DAMAGER] = true, [ROLE.HEALER] = true },
    evaluate = function(r)
      if not r.hasProfile then return nil end
      if r.duration < 30 then return nil end  -- 短战斗 CD 可能确实转不出来
      local m = r.metrics
      local unused = {}
      for _, cd in pairs(m.cdUsage) do
        if (cd.count or 0) == 0 then
          unused[#unused + 1] = cd.name or "主要技能"
        end
      end
      if #unused > 0 then
        return {
          severity = SEV.SUGGEST,
          text = string.format("整场没有使用：%s。这类爆发/团队 CD 应在战斗中打出。",
            table.concat(unused, "、")),
        }
      end
    end,
  },

  -- DPS：维持类 DoT/debuff 覆盖率不足 = 掉了没续。
  {
    id = "maintain_uptime_low",
    roles = { [ROLE.DAMAGER] = true },
    evaluate = function(r)
      if not r.hasProfile then return nil end
      local m = r.metrics
      local limit = threshold("uptimePct", 0.90)
      local low = {}
      for _, mm in pairs(m.maintain) do
        if mm.ratio < limit then
          low[#low + 1] = string.format("%s(%s)", mm.name or "维持技能", Utils.Pct(mm.ratio))
        end
      end
      if #low > 0 then
        return {
          severity = SEV.SUGGEST,
          text = string.format("维持类覆盖率偏低：%s，目标 >%s，注意及时续上不要断。",
            table.concat(low, "、"), Utils.Pct(limit)),
        }
      end
    end,
  },

  -- HEALER：过量治疗过高 = 手法/选目标问题，最可执行的治疗信号。
  {
    id = "overheal_high",
    roles = { [ROLE.HEALER] = true },
    evaluate = function(r)
      local m = r.metrics
      if m.hps <= 0 then return nil end
      local limit = threshold("overhealPct", 0.40)
      if m.overhealPct > limit then
        return {
          severity = SEV.SUGGEST,
          text = string.format("过量治疗约 %s（目标 <%s），存在过量施放，注意读条治疗的目标选择与时机。",
            Utils.Pct(m.overhealPct), Utils.Pct(limit)),
        }
      end
    end,
  },

  -- TANK：主动减伤覆盖率不足 = 减伤没铺满，坦克的核心 KPI。
  {
    id = "mitigation_low",
    roles = { [ROLE.TANK] = true },
    evaluate = function(r)
      if not r.hasProfile then return nil end
      local m = r.metrics
      -- profile 没配 mitigation 时 mitigationPct 恒为 0，此处需区分"没配"与"真低"。
      local hasMit = false
      local profile = ns.SpecProfiles[r.specID]
      if profile and profile.mitigation and next(profile.mitigation) then hasMit = true end
      if not hasMit then return nil end
      local limit = threshold("mitigationPct", 0.55)
      if m.mitigationPct < limit then
        return {
          severity = SEV.SUGGEST,
          text = string.format("主动减伤覆盖率约 %s（目标 >%s），注意在承伤期间保持减伤在线。",
            Utils.Pct(m.mitigationPct), Utils.Pct(limit)),
        }
      end
    end,
  },

  -- 无 profile 时的兜底提示：让用户知道为什么建议偏少，且如何补全。
  {
    id = "no_profile_hint",
    roles = nil,
    evaluate = function(r)
      if r.hasProfile then return nil end
      return {
        severity = SEV.INFO,
        text = "当前专精暂无细化模型，只做了通用分析。可在 SpecProfiles 补充该专精以获得针对性建议。",
      }
    end,
  },
}

-- 对一份报告跑全部规则，返回按严重度降序排序的改进点数组（截断到上限）。
function Analyzer:Analyze(report)
  local out = {}
  for _, rule in ipairs(RULES) do
    local applies = (rule.roles == nil) or (rule.roles[report.role] == true)
    if applies then
      local ok, sug = pcall(rule.evaluate, report)
      if ok and type(sug) == "table" then
        sug.id = rule.id
        out[#out + 1] = sug
      end
    end
  end

  table.sort(out, function(a, b) return (a.severity or 0) > (b.severity or 0) end)

  local max = tonumber(ns.Config:Get("profile.maxSuggestions")) or 5
  if #out > max then
    local trimmed = {}
    for i = 1, max do trimmed[i] = out[i] end
    return trimmed
  end
  return out
end

function Analyzer:Init()
  -- 无状态。
end
