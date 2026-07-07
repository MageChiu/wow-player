local addonName, ns = ...

local Const = ns.Constants
local ROLE = Const.ROLE

-- 每个专精（specID）一项，纯数据描述"该专精该被关注什么"。Analyzer 是通用的，
-- 只是喂进不同 profile。新增职业 = 加一行；版本平衡改动 = 改 spellId。逻辑不动。
--
-- 字段说明：
--   role            -- 角色，决定跑哪组规则（TANK/DAMAGER/HEALER）。
--   resource        -- 主资源名（仅用于文案，不做精确追踪，日志拿不到别人资源）。
--   maintain        -- { [spellId] = "显示名" } 需要高覆盖率维持的 debuff/buff。
--   majorCDs        -- { [spellId] = "显示名" } 主要爆发/防御 CD，统计使用次数。
--   mitigation      -- { [spellId] = "显示名" } 坦克主动减伤类光环，算覆盖率。
--
-- specID 取自 GetSpecializationInfo(GetSpecialization())，是官方稳定数值。
-- 下面先填每个角色各 1~2 个常见专精作为样例，其余留空由社区/后续补齐。
-- 缺 profile 的专精不会崩：Analyzer 只跑通用指标（DPS/HPS/活跃时间/死亡）。
ns.SpecProfiles = {

  ---------------------------------------------------------------------------
  -- 坦克 TANK
  ---------------------------------------------------------------------------
  [250] = {  -- 鲜血死亡骑士
    role = ROLE.TANK,
    resource = "符文能量",
    mitigation = {
      [195181] = "骨盾",
    },
    majorCDs = {
      [55233] = "吸血鬼之血",
      [48792] = "冰封之韧",
    },
    maintain = {},
  },

  [104] = {  -- 守护德鲁伊
    role = ROLE.TANK,
    resource = "怒气",
    mitigation = {
      [192081] = "铁鬃",   -- Ironfur
    },
    majorCDs = {
      [61336] = "生存本能",
      [22812] = "树皮术",
    },
    maintain = {},
  },

  ---------------------------------------------------------------------------
  -- 输出 DAMAGER
  ---------------------------------------------------------------------------
  [253] = {  -- 兽王猎人
    role = ROLE.DAMAGER,
    resource = "集中值",
    maintain = {},
    majorCDs = {
      [193530] = "野性狂怒",
      [19574]  = "狂野怒火",
    },
  },

  [262] = {  -- 元素萨满
    role = ROLE.DAMAGER,
    resource = "法力/极效",
    maintain = {
      [188389] = "火焰震击",  -- Flame Shock（DoT，需维持）
    },
    majorCDs = {
      [191634] = "风暴之眼",
    },
  },

  [267] = {  -- 毁灭术士
    role = ROLE.DAMAGER,
    resource = "灵魂裂片",
    maintain = {
      [157736] = "献祭",       -- Immolate（DoT）
    },
    majorCDs = {
      [1122] = "召唤地狱火",
    },
  },

  ---------------------------------------------------------------------------
  -- 治疗 HEALER
  ---------------------------------------------------------------------------
  [105] = {  -- 恢复德鲁伊
    role = ROLE.HEALER,
    resource = "法力",
    maintain = {},
    majorCDs = {
      [740]    = "宁静",
      [197721] = "繁盛",
    },
  },

  [270] = {  -- 织雾武僧
    role = ROLE.HEALER,
    resource = "法力",
    maintain = {},
    majorCDs = {
      [115310] = "复苏",
      [322118] = "玉莲踏跃",
    },
  },
}

-- 取当前角色的 profile；无则返回 nil（Analyzer 会退化到通用规则）。
function ns.SpecProfiles.ForCurrent()
  if not GetSpecialization or not GetSpecializationInfo then return nil, nil end
  local idx = GetSpecialization()
  if not idx then return nil, nil end
  local specID = GetSpecializationInfo(idx)
  if not specID then return nil, nil end
  return ns.SpecProfiles[specID], specID
end
