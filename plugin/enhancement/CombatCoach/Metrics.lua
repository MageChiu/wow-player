local addonName, ns = ...

local Metrics = {}
ns.Metrics = ns.Core:RegisterModule("Metrics", Metrics)

local Utils = ns.Utils
local Div = Utils.Div

-- 从一个已收尾的段构建报告对象。duration 已由调用方算好（单调时钟差）。
-- 返回 report，或 nil（数据不足）。
function Metrics:Build(seg, duration)
  if not seg or duration <= 0 then return nil end

  local profile, specID = ns.SpecProfiles.ForCurrent()
  local role = profile and profile.role or self:GuessRole()
  local className = self:ClassName()

  local m = {}
  m.dps = Div(seg.damageDone, duration)
  m.hps = Div(seg.healDone, duration)
  m.dtps = Div(seg.damageTaken, duration)

  -- 过量治疗比例：over / (有效 + over)。无治疗时为 0。
  local totalHealRaw = seg.healDone + seg.overheal
  m.overhealPct = Div(seg.overheal, totalHealRaw)

  m.deaths = seg.deaths or 0
  m.interrupts = seg.interrupts or 0
  m.dispels = seg.dispels or 0

  -- 活跃时间估算：施法/行为跨度里，是否几乎一直在动。
  -- 用首末行为时钟界定"实际投入"窗口，再与整段时长比。
  -- 这是近似——日志拿不到 GCD 精确空档，但足够抓"站桩空转"这类大问题。
  local span = 0
  if seg.firstActionClock and seg.lastActionClock then
    span = seg.lastActionClock - seg.firstActionClock
  end
  m.activeTimePct = Div(span, duration)
  m.activeSpan = span

  -- 光环覆盖率：total / duration，截断到 [0,1]。
  m.uptime = {}
  for spellId, a in pairs(seg.auras) do
    local ratio = Div(a.total or 0, duration)
    if ratio > 1 then ratio = 1 end
    m.uptime[spellId] = { ratio = ratio, name = a.name }
  end

  -- 主动减伤总覆盖率（坦克）：把 profile.mitigation 列出的光环覆盖率取并集近似。
  -- 简化处理：取其中最高的一个作为"减伤在线"比例（多数坦克核心减伤是单一主 buff）。
  m.mitigationPct = 0
  if profile and profile.mitigation then
    local best = 0
    for spellId in pairs(profile.mitigation) do
      local u = m.uptime[spellId]
      if u and u.ratio > best then best = u.ratio end
    end
    m.mitigationPct = best
  end

  -- 主 CD 使用次数：从施法记录里挑出 profile.majorCDs。
  m.cdUsage = {}
  if profile and profile.majorCDs then
    for spellId, name in pairs(profile.majorCDs) do
      local cast = seg.casts[spellId]
      m.cdUsage[spellId] = { count = cast and cast.count or 0, name = name }
    end
  end

  -- 维持类 debuff/buff 覆盖率：从 profile.maintain 取。
  m.maintain = {}
  if profile and profile.maintain then
    for spellId, name in pairs(profile.maintain) do
      local u = m.uptime[spellId]
      m.maintain[spellId] = { ratio = u and u.ratio or 0, name = name }
    end
  end

  -- Top 伤害技能（用于报告里展示占比，帮助判断循环重心）。
  m.topDamage = self:TopSpells(seg.dmgBySpell, seg.damageDone, 5)

  return {
    startedAt = seg.startedAt,
    duration = duration,
    source = seg.source,
    bossName = seg.bossName,
    kill = seg.kill,
    role = role,
    specID = specID,
    className = className,
    hasProfile = profile ~= nil,
    metrics = m,
  }
end

-- 按伤害量降序取前 N 个技能，附带占总量比例。
function Metrics:TopSpells(dmgBySpell, total, n)
  local list = {}
  for spellId, b in pairs(dmgBySpell) do
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

-- 无 profile 时的角色兜底判断，用官方 API。
function Metrics:GuessRole()
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
