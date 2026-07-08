local addonName, ns = ...

local Metrics = {}
ns.Metrics = ns.Core:RegisterModule("Metrics", Metrics)

local Utils = ns.Utils
local Div = Utils.Div

-- 从一个段构建分析用报告对象。duration 由调用方算好（可为活体段的当前时长）。
-- 返回 report，或 nil（数据不足）。
-- 注意：本版已去除白名单（majorCDs/maintain/mitigation），分析只基于可观测数据。
function Metrics:Build(seg, duration)
  if not seg or duration <= 0 then return nil end

  local role = self:CurrentRole()
  local className = self:ClassName()

  local m = {}
  m.dps = Div(seg.damageDone, duration)
  m.hps = Div(seg.healDone, duration)
  m.dtps = Div(seg.damageTaken, duration)

  local totalHealRaw = seg.healDone + seg.overheal
  m.overhealPct = Div(seg.overheal, totalHealRaw)

  m.deaths = seg.deaths or 0
  m.interrupts = seg.interrupts or 0
  m.dispels = seg.dispels or 0

  -- 光环覆盖率：total / duration，截断到 [0,1]，并带上"施放次数"用于运行时
  -- 推断哪些是"你在主动维持"的光环（供 Analyzer 用，不依赖白名单）。
  m.uptime = {}
  for spellId, a in pairs(seg.auras) do
    local total = a.total or 0
    -- 若段仍在进行、光环当前处于激活状态，把"至今"的这段也补上，避免活体段低估。
    if a.up and a.onClock then
      total = total + (ns.Segment:LiveDuration(seg) + (seg.startClock or 0) - a.onClock)
    end
    local ratio = Div(total, duration)
    if ratio > 1 then ratio = 1 end
    m.uptime[spellId] = { ratio = ratio, name = a.name, applies = a.applies or 0 }
  end

  m.topDamage = self:TopSpells(seg.dmgBySpell, seg.damageDone, 5)
  m.topHeal = self:TopSpells(seg.healBySpell, seg.healDone, 5)

  return {
    startedAt = seg.startedAt,
    duration = duration,
    source = seg.source,
    bossName = seg.bossName,
    kill = seg.kill,
    role = role,
    className = className,
    zeroCollected = seg.zeroCollected,
    metrics = m,
  }
end

-- 按数值降序取前 N 个技能，附带占总量比例。
function Metrics:TopSpells(bySpell, total, n)
  local list = {}
  for spellId, b in pairs(bySpell or {}) do
    list[#list + 1] = { spellId = spellId, name = b.name, amount = b.amount }
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  local out = {}
  for i = 1, math.min(n, #list) do
    local e = list[i]
    e.pct = Div(e.amount, total)
    out[i] = e
  end
  return out
end

-- 当前角色定位，用官方 API（TANK/HEALER/DAMAGER）。
function Metrics:CurrentRole()
  if GetSpecialization and GetSpecializationRole then
    local idx = GetSpecialization()
    if idx then
      local r = GetSpecializationRole(idx)
      if r == "TANK" then return ns.Constants.ROLE.TANK end
      if r == "HEALER" then return ns.Constants.ROLE.HEALER end
      if r == "DAMAGER" then return ns.Constants.ROLE.DAMAGER end
    end
  end
  return ns.Constants.ROLE.DAMAGER
end

function Metrics:ClassName()
  if UnitClass then
    local name = UnitClass("player")
    return name
  end
  return "?"
end

function Metrics:Init()
  -- 无状态。
end
