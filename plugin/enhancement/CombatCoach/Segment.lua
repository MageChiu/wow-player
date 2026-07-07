local addonName, ns = ...

local Segment = {}
ns.Segment = ns.Core:RegisterModule("Segment", Segment)

local Const = ns.Constants
local GetTime = GetTime
local time = time

-- 多分段并存模型：
--   recording  采集开关。窗口打开=true 才采集；关闭=false 停止（数据保留）。
--   current    当前正在进行的战斗段（脱战后收尾并压入 history，随后置 nil）。
--   overall    从"开始采集"至今的累加段（跨多场战斗）。
--   history    已结束的战斗段列表（最新在前，环形，超上限丢最旧）。
-- 分段只是"数据分组维度"，自动划界（进出战斗）不再触发任何分析或弹窗。
Segment.recording = false
Segment.current = nil
Segment.overall = nil
Segment.history = {}

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
    healBySpell = {},    -- [spellId] = { amount, name }
    casts = {},          -- [spellId] = { count, name }

    -- 光环覆盖时间跟踪：[spellId] = { up, onClock, total, name }
    -- "至少一个实例存在"即视为覆盖，作为主目标覆盖率的近似。
    auras = {},

    -- 首次/末次有伤害或治疗行为的时钟，用于活跃时间估算的边界。
    firstActionClock = nil,
    lastActionClock = nil,
  }
end

-- ---- 采集开关（由计量窗口驱动） ----

-- 开始采集：窗口打开时调用。保留既有 overall 与 history（关窗只是停采集）。
function Segment:StartRecording()
  self.recording = true
  if not self.overall then
    self.overall = newSegment(Const.SEGMENT_SOURCE.COMBAT, { name = "总计" })
    self.overall.source = "overall"
  end
end

-- 停止采集：窗口关闭时调用。收尾进行中的战斗段，数据全部保留。
function Segment:StopRecording()
  if self.current then
    self:FinishCurrent()
  end
  self.recording = false
end

function Segment:IsRecording()
  return self.recording
end

-- 清空所有采集数据（重置按钮 / 命令）。history 一并清空，overall 重建。
function Segment:ResetAll()
  self.current = nil
  self.history = {}
  self.overall = self.recording
    and (function() local s = newSegment(Const.SEGMENT_SOURCE.COMBAT, { name = "总计" }); s.source = "overall"; return s end)()
    or nil
end

-- ---- 战斗段边界（进出战斗 / 首领战），仅在 recording 时有效 ----

function Segment:IsActive()
  return self.current ~= nil
end

function Segment:Get()
  return self.current
end

-- 开一个新的战斗段。首领段比普通战斗段"权威"，普通段进行中遇到首领开始会升级。
function Segment:StartCombat(source, info)
  if not self.recording then return end
  if self.current then
    -- 已在战斗中：普通段可被首领段升级，其余保持。
    if source == Const.SEGMENT_SOURCE.ENCOUNTER
      and self.current.source ~= Const.SEGMENT_SOURCE.ENCOUNTER then
      self.current.source = Const.SEGMENT_SOURCE.ENCOUNTER
      self.current.bossName = info and info.name or self.current.bossName
      self.current.encounterID = info and info.encounterID or self.current.encounterID
    end
    return
  end
  self.current = newSegment(source, info)
end

-- 收尾当前战斗段：关闭光环区间、判定零采集、压入 history。返回收尾后的段。
function Segment:FinishCurrent(kill)
  local seg = self.current
  if not seg then return nil end
  seg.endClock = GetTime()
  if kill ~= nil then seg.kill = kill end

  for _, a in pairs(seg.auras) do
    if a.up and a.onClock then
      a.total = a.total + (seg.endClock - a.onClock)
      a.up = false
    end
  end

  -- 自检：时长够却完全没采到自己的伤害/治疗，标记异常，供窗口显式提示，
  -- 而不是静默展示一个 0（这曾是"看起来在跑其实断了"的根源）。
  local dur = seg.endClock - seg.startClock
  local minSec = tonumber(ns.Config and ns.Config:Get("profile.minSegmentSeconds"))
    or Const.MIN_SEGMENT_SECONDS
  seg.zeroCollected = (dur >= minSec)
    and (seg.damageDone == 0 and seg.healDone == 0 and seg.damageTaken == 0)

  table.insert(self.history, 1, seg)
  local max = Const.MAX_HISTORY
  for i = #self.history, max + 1, -1 do
    self.history[i] = nil
  end

  self.current = nil
  return seg
end

-- 段的"当前时长"（活体段用到现在，已收尾段用固定值）。
function Segment:LiveDuration(seg)
  if not seg then return 0 end
  local endc = seg.endClock or GetTime()
  return endc - (seg.startClock or endc)
end

-- ---- 热路径累加器：写入 overall 与 current（若存在）。禁止在此建表以外的开销 ----

local function applyDamageDone(seg, spellId, name, amount)
  seg.damageDone = seg.damageDone + amount
  local bucket = seg.dmgBySpell[spellId]
  if bucket then
    bucket.amount = bucket.amount + amount
  else
    seg.dmgBySpell[spellId] = { amount = amount, name = name }
  end
  local now = GetTime()
  if not seg.firstActionClock then seg.firstActionClock = now end
  seg.lastActionClock = now
end

function Segment:AddDamageDone(spellId, name, amount)
  if not self.recording then return end
  if self.overall then applyDamageDone(self.overall, spellId, name, amount) end
  if self.current then applyDamageDone(self.current, spellId, name, amount) end
end

function Segment:AddDamageTaken(amount)
  if not self.recording then return end
  if self.overall then self.overall.damageTaken = self.overall.damageTaken + amount end
  if self.current then self.current.damageTaken = self.current.damageTaken + amount end
end

local function applyHeal(seg, spellId, name, amount, overheal)
  seg.healDone = seg.healDone + amount
  seg.overheal = seg.overheal + (overheal or 0)
  local bucket = seg.healBySpell[spellId]
  if bucket then
    bucket.amount = bucket.amount + amount
  else
    seg.healBySpell[spellId] = { amount = amount, name = name }
  end
  local now = GetTime()
  if not seg.firstActionClock then seg.firstActionClock = now end
  seg.lastActionClock = now
end

function Segment:AddHeal(spellId, name, amount, overheal)
  if not self.recording then return end
  if self.overall then applyHeal(self.overall, spellId, name, amount, overheal) end
  if self.current then applyHeal(self.current, spellId, name, amount, overheal) end
end

function Segment:AddAbsorb(amount)
  if not self.recording then return end
  if self.overall then self.overall.absorbDone = self.overall.absorbDone + amount end
  if self.current then self.current.absorbDone = self.current.absorbDone + amount end
end

local function applyCast(seg, spellId, name)
  local bucket = seg.casts[spellId]
  if bucket then
    bucket.count = bucket.count + 1
  else
    seg.casts[spellId] = { count = 1, name = name }
  end
end

function Segment:AddCast(spellId, name)
  if not self.recording then return end
  if self.overall then applyCast(self.overall, spellId, name) end
  if self.current then applyCast(self.current, spellId, name) end
end

function Segment:AddInterrupt()
  if not self.recording then return end
  if self.overall then self.overall.interrupts = self.overall.interrupts + 1 end
  if self.current then self.current.interrupts = self.current.interrupts + 1 end
end

function Segment:AddDispel()
  if not self.recording then return end
  if self.overall then self.overall.dispels = self.overall.dispels + 1 end
  if self.current then self.current.dispels = self.current.dispels + 1 end
end

function Segment:AddDeath()
  if not self.recording then return end
  if self.overall then self.overall.deaths = self.overall.deaths + 1 end
  if self.current then self.current.deaths = self.current.deaths + 1 end
end

local function applyAuraOn(seg, spellId, name, now)
  local a = seg.auras[spellId]
  if a then
    a.applies = (a.applies or 0) + 1
    if not a.up then
      a.up = true
      a.onClock = now
    end
  else
    -- applies 记录"施放/刷新次数"：多次刷新说明这是玩家在主动维持的光环，
    -- 用于运行时推断"哪些是维持类"，从而不依赖白名单。
    seg.auras[spellId] = { up = true, onClock = now, total = 0, name = name, applies = 1 }
  end
end

function Segment:AuraOn(spellId, name)
  if not self.recording then return end
  local now = GetTime()
  if self.overall then applyAuraOn(self.overall, spellId, name, now) end
  if self.current then applyAuraOn(self.current, spellId, name, now) end
end

local function applyAuraOff(seg, spellId, now)
  local a = seg.auras[spellId]
  if a and a.up then
    a.total = a.total + (now - (a.onClock or now))
    a.up = false
  end
end

function Segment:AuraOff(spellId)
  if not self.recording then return end
  local now = GetTime()
  if self.overall then applyAuraOff(self.overall, spellId, now) end
  if self.current then applyAuraOff(self.current, spellId, now) end
end

function Segment:Init()
  -- 无状态初始化；段对象按需创建。保留 Init 以统一生命周期。
end
