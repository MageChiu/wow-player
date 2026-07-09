local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "RoleManager"
C.SLUG = "RoleManager"
C.VERSION = "0.2.0"

-- Enum.WeeklyRewardChestThresholdType（宝库活动分类）。
-- MythicPlus=1、RankedPvP=2、Raid=3 为官方长期稳定值（见 wiki）。
-- TWW 世界/地下堡分类的枚举值官方文档未明确固定，因此汇总槽数时
-- 直接遍历 GetActivities 返回的所有分类，不硬依赖某个"世界"枚举值。
C.VAULT_TYPE = {
  NONE = 0,
  MYTHIC_PLUS = 1,  -- 大秘境
  RANKED_PVP = 2,   -- 竞技
  RAID = 3,         -- 团本
}

-- 宝库分类的中文短名，用于 UI 列头与文本汇总。
C.VAULT_LABEL = {
  [C.VAULT_TYPE.MYTHIC_PLUS] = "大秘境",
  [C.VAULT_TYPE.RANKED_PVP] = "竞技",
  [C.VAULT_TYPE.RAID] = "团本",
}

-- Enum.BankType（C_Bank.FetchDepositedMoney），11.0 新增。
-- 2 = Account = 战团银行（账号共享）。
C.BANK_TYPE_ACCOUNT = 2

-- 采集时机：登录进图、金币变动、货币变动、宝库刷新、大秘境结算、
-- 战团银行金币变动、登出前补一刀。
C.COLLECT_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_MONEY",
  "ACCOUNT_MONEY",
  "CURRENCY_DISPLAY_UPDATE",
  "WEEKLY_REWARDS_UPDATE",
  "CHALLENGE_MODE_COMPLETED",
  "ENCOUNTER_END",
  "PLAYER_LOGOUT",
}

-- 数据结构版本；改缓存结构或需一次性迁移时递增。
-- v2: 清除 v1 曾硬编码写入存档的过时默认货币（3008 神勇石 / 3028）。
C.DB_VERSION = 2

-- v1 曾作为默认写入存档的遗留货币 ID。迁移时若用户未自行改动，则清除。
C.LEGACY_DEFAULT_CURRENCIES = { 3008, 3028 }
