local addonName, ns = ...

local Store = {}
ns.Store = ns.Core:RegisterModule("Store", Store)

local Const = ns.Constants

function Store:Init()
  -- 无状态；读写都实时走 Config。保留 Init 以统一生命周期。
end

-- 追加一份报告到历史（最新在前），并裁剪到上限。
function Store:Add(report)
  if type(report) ~= "table" then return end
  local hist = ns.Config:GetHistory()
  table.insert(hist, 1, report)
  local max = Const.MAX_HISTORY
  for i = #hist, max + 1, -1 do
    hist[i] = nil
  end
  self.last = report
end

-- 最近一场（内存优先，回退历史第一条）。
function Store:GetLast()
  if self.last then return self.last end
  local hist = ns.Config:GetHistory()
  return hist[1]
end

-- 历史数组（最新在前）。直接返回引用，调用方只读。
function Store:GetHistory()
  return ns.Config:GetHistory()
end

-- 按下标取某场（1 = 最新）。
function Store:GetAt(index)
  local hist = ns.Config:GetHistory()
  return hist[tonumber(index) or 0]
end

-- 一行简述，用于 /cc history 列表。
function Store:SummaryLine(report, index)
  if type(report) ~= "table" then return "" end
  local m = report.metrics or {}
  local who = report.bossName or (report.source == Const.SEGMENT_SOURCE.ENCOUNTER
    and "首领战" or "战斗")
  local roleTag = ({
    [Const.ROLE.TANK] = "T",
    [Const.ROLE.HEALER] = "治疗",
    [Const.ROLE.DAMAGER] = "DPS",
  })[report.role] or "?"

  local perf
  if report.role == Const.ROLE.HEALER then
    perf = "HPS " .. ns.Utils.Short(m.hps or 0)
  elseif report.role == Const.ROLE.TANK then
    perf = "DTPS " .. ns.Utils.Short(m.dtps or 0)
  else
    perf = "DPS " .. ns.Utils.Short(m.dps or 0)
  end

  return string.format("%d. [%s] %s · %s · %s · %d条建议",
    index or 0, roleTag, who,
    ns.Utils.Duration(report.duration or 0),
    perf,
    report.suggestions and #report.suggestions or 0)
end
