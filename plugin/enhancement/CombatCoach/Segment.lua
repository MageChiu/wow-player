local addonName, ns = ...

local Segment = {}
ns.Segment = ns.Core:RegisterModule("Segment", Segment)

local Const = ns.Constants
local GetTime = GetTime
local time = time

-- 当前进行中的战斗段。nil 表示不在战斗中。
Segment.current = nil

-- 新建一个空段。所有累加器在此初始化，热路径只做 += 不再建表。
local function newSegment(source, info)
  return {
    startedAt = time(),
    startClock = GetTime(),   -- 单调时钟，用于算时长
    endClock = nil,
    source = source,
    bossName = info and info.name or nil,
    encounterID = info and info.encounterID or nil,
    kill = nil,

    damageDone = 0,
    damageTaken = 0,
    healDone = 0,
    overheal = 0,
    absorbDone = 0,

    interrupts = 0,
    dispels = 0,
    deaths = 0,          -- 玩家自身死亡次数

    dmgBySpell = {},     -- [spellId] = { amount, name }
    casts = {},          -- [spellId] = { count, name }

    -- 光环覆盖时间跟踪：[spellId] = { up, onClock, total, name }
    -- "至少一个实例存在"即视为覆盖，作为主目标覆盖率的近似。
    auras = {},

    -- 首次/末次有伤害或治疗行为的时钟，用于活跃时间估算的边界。
    firstActionClock = nil,
    lastActionClock = nil,
  }
end

function Segment:IsActive()
  return self.current ~= nil
end

function Segment:Get()
  return self.current
end

function Segment:Start(source, info)
  -- 已有段在跑（例如首领战覆盖普通战斗）时，保留更"权威"的首领段。
  if self.current then
    if self.current.source == Const.SEGMENT_SOURCE.ENCOUNTER then
      return
    end
  end
  self.current = newSegment(source, info)
end

-- 结束当前段并返回它（已收尾）。无进行中段时返回 nil。
function Segment:Finish(kill)
  local seg = self.current
  if not seg then return nil end
  seg.endClock = GetTime()
  if kill ~= nil then seg.kill = kill end

  -- 收尾仍处于激活状态的光环，把最后一段区间计入总覆盖时间。
  for _, a in pairs(seg.auras) do
    if a.up and a.onClock then
      a.total = a.total + (seg.endClock - a.onClock)
      a.up = false
    end
  end

  self.current = nil
  return seg
end

function Segment:Abort()
  self.current = nil
end

-- ---- 热路径累加器：只做加法与表查询，禁止在此创建新表以外的开销 ----

local function markAction(seg)
  local now = GetTime()
  if not seg.firstActionClock then seg.firstActionClock = now end
  seg.lastActionClock = now
end

function Segment:AddDamageDone(spellId, name, amount)
  local seg = self.current
  if not seg then return end
  seg.damageDone = seg.damageDone + amount
  local bucket = seg.dmgBySpell[spellId]
  if bucket then
    bucket.amount = bucket.amount + amount
  else
    seg.dmgBySpell[spellId] = { amount = amount, name = name }
  end
  markAction(seg)
end

function Segment:AddDamageTaken(amount)
  local seg = self.current
  if not seg then return end
  seg.damageTaken = seg.damageTaken + amount
end

function Segment:AddHeal(amount, overheal)
  local seg = self.current
  if not seg then return end
  seg.healDone = seg.healDone + amount
  seg.overheal = seg.overheal + (overheal or 0)
  markAction(seg)
end

function Segment:AddAbsorb(amount)
  local seg = self.current
  if not seg then return end
  seg.absorbDone = seg.absorbDone + amount
end

function Segment:AddCast(spellId, name)
  local seg = self.current
  if not seg then return end
  local bucket = seg.casts[spellId]
  if bucket then
    bucket.count = bucket.count + 1
  else
    seg.casts[spellId] = { count = 1, name = name }
  end
end

function Segment:AddInterrupt()
  local seg = self.current
  if seg then seg.interrupts = seg.interrupts + 1 end
end

function Segment:AddDispel()
  local seg = self.current
  if seg then seg.dispels = seg.dispels + 1 end
end

function Segment:AddDeath()
  local seg = self.current
  if seg then seg.deaths = seg.deaths + 1 end
end

function Segment:AuraOn(spellId, name)
  local seg = self.current
  if not seg then return end
  local a = seg.auras[spellId]
  local now = GetTime()
  if a then
    if not a.up then
      a.up = true
      a.onClock = now
    end
  else
    seg.auras[spellId] = { up = true, onClock = now, total = 0, name = name }
  end
end

function Segment:AuraOff(spellId)
  local seg = self.current
  if not seg then return end
  local a = seg.auras[spellId]
  if a and a.up then
    a.total = a.total + (GetTime() - (a.onClock or GetTime()))
    a.up = false
  end
end

function Segment:Init()
  -- 无状态初始化；段对象按需创建。保留 Init 以统一生命周期。
end
