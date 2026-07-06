local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "QuickDisenchant"
C.SLUG = "QuickDisenchant"
C.VERSION = "0.1.0"

-- 分解法术（附魔专业授予）。用 ID 做"是否会附魔"判定，用其本地化名
-- 作为安全按钮的 spell 属性（CastSpellByName 需要本地化名）。
C.DISENCHANT_SPELL_ID = 13262

-- Enum.ItemClass：武器 2、护甲 4。只有这两类可能被分解。
C.ITEM_CLASS = {
  WEAPON = 2,
  ARMOR = 4,
}

-- 可分解的品质（Enum.ItemQuality）：优良 2、精良 3、史诗 4。
-- 劣质/普通/传说/神器等不可分解，不纳入候选。
C.QUALITY = {
  UNCOMMON = 2,
  RARE = 3,
  EPIC = 4,
}

-- 品质分级：内部键 -> 品质枚举值。用于设置面板与配置读写。
C.TIER_ORDER = { "uncommon", "rare", "epic" }
C.TIER_QUALITY = {
  uncommon = C.QUALITY.UNCOMMON,
  rare = C.QUALITY.RARE,
  epic = C.QUALITY.EPIC,
}
C.QUALITY_TIER = {
  [C.QUALITY.UNCOMMON] = "uncommon",
  [C.QUALITY.RARE] = "rare",
  [C.QUALITY.EPIC] = "epic",
}
C.TIER_LABEL = {
  uncommon = "优良（绿）",
  rare = "精良（蓝）",
  epic = "史诗（紫）",
}

-- 扫描的背包范围：0 背包 + 1..4 普通背包。materia/声望等袋不含装备。
C.SCAN_BAG_MIN = 0
C.SCAN_BAG_MAX = 4

-- 安全按钮名（供 Bindings.xml 的 CLICK 绑定引用）。
C.CAST_BUTTON_NAME = "QuickDisenchantCastButton"

C.DB_VERSION = 1

-- 按键绑定在"按键设置"里的分组标题与条目名（供 Bindings.xml 显示）。
BINDING_HEADER_QUICKDISENCHANT = "QuickDisenchant 快速分解"
_G["BINDING_NAME_CLICK " .. C.CAST_BUTTON_NAME .. ":LeftButton"] = "分解下一件勾选的装备"
