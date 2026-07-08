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
--   id       唯一标识。
--   roles    适用角色集合，nil 表示全部。
--   evaluate function(report) -> suggestion | nil，suggestion = { severity, text }
--
-- 设计原则（本版重构后）：只保留"有客观依据、不依赖预写白名单、不靠拍脑袋阈值"
-- 的规则。凡是需要"该专精理想循环/占比/该用几次"这类外部基准的判断，一律不做，
-- 因为那类基准我们没有可靠来源，硬做只会误导。分析是"锦上添花"，采集才是主体。
local RULES = {

  -- 【硬】自身死亡。死了就是问题，无需任何基准。
  {
    id = "deaths",
    roles = nil,
    evaluate = function(r)
      local m = r.metrics
      if (m.deaths or 0) > 0 then
        return {
          severity = SEV.CRITICAL,
          text = string.format("本段阵亡 %d 次，优先复盘致死的机制/地板。", m.deaths),
        }
      end
    end,
  },

  -- 【硬】过量治疗过高。数据来自日志原生字段，"溢出高=效率低"是治疗通识。
  -- 阈值可在设置里调；默认值仅作参考，不同专精健康区间不同。
  {
    id = "overheal_high",
    roles = { [ROLE.HEALER] = true },
    evaluate = function(r)
      local m = r.metrics
      if (m.hps or 0) <= 0 then return nil end
      local limit = threshold("overhealPct", 0.40)
      if m.overhealPct > limit then
        return {
          severity = SEV.SUGGEST,
          text = string.format("过量治疗约 %s（参考 <%s），存在过量施放，可留意治疗目标与时机。",
            Utils.Pct(m.overhealPct), Utils.Pct(limit)),
        }
      end
    end,
  },

  -- 【运行时推断，无白名单】维持类光环覆盖率偏低。
  -- 不预设"哪个技能该维持"，而是从本段数据推断：一个被你反复施放/刷新
  -- （applies 高）的光环，说明你本就在主动维持它；若它的覆盖率却明显偏低，
  -- 就是"想维持但断了"的真实信号。这样对任何职业、任何赛季都成立，且不会过时。
  {
    id = "maintain_uptime_low",
    roles = { [ROLE.DAMAGER] = true, [ROLE.TANK] = true },
    evaluate = function(r)
      local m = r.metrics
      if (r.duration or 0) < 15 then return nil end
      local limit = threshold("uptimePct", 0.90)
      local low = {}
      for _, u in pairs(m.uptime or {}) do
        -- 只看"你明显在主动维持"的光环：施放次数≥3 且理应保持较高覆盖。
        if (u.applies or 0) >= 3 and u.ratio < limit then
          low[#low + 1] = string.format("%s(%s)", u.name or "光环", Utils.Pct(u.ratio))
        end
      end
      if #low > 0 then
        -- 只提最多 3 个，避免刷屏。
        while #low > 3 do low[#low] = nil end
        return {
          severity = SEV.SUGGEST,
          text = string.format("以下你在维持的光环覆盖率偏低（参考 >%s）：%s，注意及时续上。",
            Utils.Pct(limit), table.concat(low, "、")),
        }
      end
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
