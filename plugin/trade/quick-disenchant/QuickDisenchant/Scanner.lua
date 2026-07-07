local addonName, ns = ...

local Scanner = {}
ns.Scanner = ns.Core:RegisterModule("Scanner", Scanner)

local Const = ns.Constants

function Scanner:Init()
  -- 无状态，候选每次现算。
end

-- 是否拥有分解能力（学了附魔）。C_Spell.IsSpellUsable 在没学时返回 false。
function Scanner:CanDisenchant()
  local id = Const.DISENCHANT_SPELL_ID
  if C_Spell and C_Spell.IsSpellKnown then
    local ok, known = pcall(C_Spell.IsSpellKnown, id)
    if ok then return known and true or false end
  end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, id)
    if ok then return known and true or false end
  end
  -- 兜底：拿得到法术信息且在法术书里就当作会。
  return false
end

-- 分解法术的本地化名，作为安全按钮 spell 属性用（CastSpellByName 需要）。
function Scanner:GetSpellName()
  local id = Const.DISENCHANT_SPELL_ID
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and name and name ~= "" then return name end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" and info.name then return info.name end
  end
  return nil
end

local function containerItemInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    return C_Container.GetContainerItemInfo(bag, slot)
  end
  return nil
end

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return 0
end

-- 单个背包格是否为"可分解候选"。返回候选表或 nil。
function Scanner:_evaluate(bag, slot)
  local info = containerItemInfo(bag, slot)
  if not info or not info.itemID then return nil end
  if info.isLocked then return nil end

  local quality = info.quality
  local tier = quality and Const.QUALITY_TIER[quality]
  if not tier then return nil end                        -- 非绿/蓝/紫
  if not ns.Config:IsTierEnabled(tier) then return nil end -- 该品质未开启

  if ns.Config:IsNeverListed(info.itemID) then return nil end

  -- 只保留武器/护甲。用即时接口拿 classID，不触发服务器查询。
  local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
  if classID ~= Const.ITEM_CLASS.WEAPON and classID ~= Const.ITEM_CLASS.ARMOR then
    return nil
  end

  -- 未绑定过滤（可选）。isBound 为 true 表示已绑定。
  if ns.Config:Get("profile.onlyBound") and info.isBound ~= true then
    return nil
  end

  return {
    bag = bag,
    slot = slot,
    itemID = info.itemID,
    link = info.hyperlink,
    quality = quality,
    tier = tier,
    icon = info.iconFileID,
    name = info.itemName,
    -- target-item 属性需要 "bag slot" 字符串。
    target = bag .. " " .. slot,
  }
end

-- 扫描全部背包，返回候选数组。按品质降序、同品质按背包格排序，稳定可预期。
function Scanner:Scan()
  local out = {}
  for bag = Const.SCAN_BAG_MIN, Const.SCAN_BAG_MAX do
    local slots = numSlots(bag)
    for slot = 1, slots do
      local cand = self:_evaluate(bag, slot)
      if cand then out[#out + 1] = cand end
    end
  end
  table.sort(out, function(a, b)
    if a.quality ~= b.quality then return a.quality < b.quality end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
  end)
  return out
end
