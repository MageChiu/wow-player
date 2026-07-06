local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "CombatCoach"
C.SLUG = "CombatCoach"
C.VERSION = "0.1.0"

-- 数据结构版本；将来改缓存结构时用它做迁移/清空判断。
C.DB_VERSION = 1

-- 角色枚举。用 GetSpecializationRole / SpecProfiles 的 role 字段判定。
C.ROLE = {
  TANK = "TANK",
  DAMAGER = "DAMAGER",
  HEALER = "HEALER",
}

-- 改进点严重度。数字越大越靠前显示，配不同颜色。
C.SEVERITY = {
  INFO = 1,      -- 灰：可留意
  SUGGEST = 2,   -- 黄：建议改进
  CRITICAL = 3,  -- 红：明显问题
}

C.SEVERITY_COLOR = {
  [1] = "ff9d9d9d",
  [2] = "ffffd100",
  [3] = "ffff5555",
}

-- 战斗分段来源。首领战优先用 ENCOUNTER_*，其余用进出战斗。
C.SEGMENT_SOURCE = {
  ENCOUNTER = "encounter",
  COMBAT = "combat",
}

-- 一场战斗低于该秒数视为无意义（路上蹭一下怪），不生成报告。
C.MIN_SEGMENT_SECONDS = 5

-- 保留的历史战斗段数量上限（环形，超出丢最旧）。
C.MAX_HISTORY = 20

-- CLEU 之外还需要监听的边界/生命周期事件。
C.LIFECYCLE_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",  -- 进入战斗
  "PLAYER_REGEN_ENABLED",   -- 脱离战斗
  "ENCOUNTER_START",
  "ENCOUNTER_END",
  "UNIT_PET",
}

-- 我们关心的 CLEU 子事件前缀/类型。热路径里用查表判断，避免多次字符串比较。
-- 值为内部归一化的类别，Segment 据此累加。
C.CLEU_KIND = {
  SPELL_DAMAGE = "damage",
  SPELL_PERIODIC_DAMAGE = "damage",
  RANGE_DAMAGE = "damage",
  SWING_DAMAGE = "damage",
  SPELL_HEAL = "heal",
  SPELL_PERIODIC_HEAL = "heal",
  SPELL_ABSORBED = "absorb",
  SPELL_CAST_SUCCESS = "cast",
  SPELL_INTERRUPT = "interrupt",
  SPELL_DISPEL = "dispel",
  SPELL_AURA_APPLIED = "aura_on",
  SPELL_AURA_REFRESH = "aura_on",
  SPELL_AURA_REMOVED = "aura_off",
  UNIT_DIED = "death",
}
