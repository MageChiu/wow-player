local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "CombatCoach"
C.SLUG = "CombatCoach"
C.VERSION = "0.2.0"

-- 数据结构版本；将来改缓存结构时用它做迁移/清空判断。
C.DB_VERSION = 1

-- 角色枚举。用 GetSpecializationRole 判定当前专精定位。
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
  -- 12.0 精简后越来越多伤害走这些"非主动施法"子事件，必须一并采集，
  -- 否则总量会漏（如反射/近战法术护盾/分摊伤害）。
  DAMAGE_SHIELD = "damage",
  DAMAGE_SPLIT = "damage",
  SPELL_BUILDING_DAMAGE = "damage",
  RANGE_HEAL = "heal",
  SPELL_HEAL = "heal",
  SPELL_PERIODIC_HEAL = "heal",
  SPELL_ABSORBED = "absorb",
  SPELL_CAST_SUCCESS = "cast",
  SPELL_INTERRUPT = "interrupt",
  SPELL_DISPEL = "dispel",
  SPELL_AURA_APPLIED = "aura_on",
  SPELL_AURA_REFRESH = "aura_on",
  SPELL_AURA_REMOVED = "aura_off",
  SPELL_SUMMON = "summon",
  UNIT_DIED = "death",
}

-- SWING_DAMAGE 的固定桶 spellId（自动攻击无 spellId）。6603 是"自动攻击"法术。
C.MELEE_SPELL_ID = 6603
