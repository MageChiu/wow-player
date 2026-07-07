local addonName, ns = ...

local SB = {}
ns.SecureButton = ns.Core:RegisterModule("SecureButton", SB)

local Const = ns.Constants
local Utils = ns.Utils

-- 队列：面板勾选的候选（{bag, slot, itemID, link, ...}）。每次硬件点击在
-- PreClick 里挑出第一件仍然在原格的候选，写进 target-item，交给安全 OnClick
-- 施放分解。分解成功后（UNIT_SPELLCAST_SUCCEEDED）标记消耗并通知面板刷新。
--
-- 为什么用 PreClick：改 target-item 属于改受保护属性，只能脱战执行；PreClick
-- 在安全 OnClick 之前运行，脱战时改的属性对本次点击立即生效——这是把
-- "对下一件装备施法"绑到单次硬件点击上的标准手法。

function SB:Init()
  self.queue = {}
  self.currentEntry = nil
  self:_ensureButton()
  self:_ensureEvents()
end

local function slotStillHas(entry)
  if not (C_Container and C_Container.GetContainerItemInfo) then return false end
  local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
  return info ~= nil and info.itemID == entry.itemID and not info.isLocked
end

-- 找到队列里下一件仍有效的候选。
function SB:_nextEntry()
  for _, entry in ipairs(self.queue) do
    if not entry.done and slotStillHas(entry) then
      return entry
    end
  end
  return nil
end

function SB:_ensureButton()
  if self.button then return self.button end

  local btn = CreateFrame("Button", Const.CAST_BUTTON_NAME, UIParent,
    "SecureActionButtonTemplate, UIPanelButtonTemplate")
  btn:SetSize(150, 24)
  btn:Hide()
  btn:SetAttribute("type", "spell")
  btn:SetAttribute("useOnKeyDown", false)
  btn:RegisterForClicks("AnyUp")
  btn:SetText("分解下一件")

  -- PreClick：脱战时把目标切到下一件候选。战斗中直接跳过（受保护属性锁定）。
  btn:SetScript("PreClick", function(self)
    ns.Core:SafeCall(function()
      if InCombatLockdown() then return end
      local spellName = ns.Scanner:GetSpellName()
      local entry = SB:_nextEntry()
      if spellName and entry then
        self:SetAttribute("spell", spellName)
        self:SetAttribute("target-item", entry.bag .. " " .. entry.slot)
        SB.currentEntry = entry
      else
        self:SetAttribute("spell", nil)
        self:SetAttribute("target-item", nil)
        SB.currentEntry = nil
        if not spellName then
          Utils.Print("未学习附魔（分解），无法使用。")
        elseif #SB.queue == 0 then
          Utils.Print("没有勾选待分解的装备。")
        else
          Utils.Print("勾选的装备已分解完毕。")
        end
      end
    end)
  end)

  self.button = btn
  return btn
end

function SB:_ensureEvents()
  if self.eventFrame then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    ns.Core:SafeCall(function() SB:_onEvent(event, unit, castGUID, spellID) end)
  end)
  self.eventFrame = f
end

function SB:_onEvent(event, unit, castGUID, spellID)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if unit == "player" and spellID == Const.DISENCHANT_SPELL_ID then
      local entry = self.currentEntry
      if entry then
        entry.done = true
        self.currentEntry = nil
        self:_pruneDone()
        if ns.Panel and ns.Panel.NotifyConsumed then
          ns.Core:SafeCall(function() ns.Panel:NotifyConsumed(entry) end)
        end
      end
    end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    if ns.Panel and ns.Panel.NotifyCombat then
      ns.Core:SafeCall(function() ns.Panel:NotifyCombat(event == "PLAYER_REGEN_DISABLED") end)
    end
  end
end

function SB:_pruneDone()
  local kept = {}
  for _, entry in ipairs(self.queue) do
    if not entry.done then kept[#kept + 1] = entry end
  end
  self.queue = kept
end

-- 面板调用：设置本轮要分解的候选队列。
function SB:SetQueue(list)
  self.queue = {}
  for _, entry in ipairs(list or {}) do
    self.queue[#self.queue + 1] = {
      bag = entry.bag,
      slot = entry.slot,
      itemID = entry.itemID,
      link = entry.link,
    }
  end
  self.currentEntry = nil
end

function SB:GetRemaining()
  local n = 0
  for _, entry in ipairs(self.queue) do
    if not entry.done then n = n + 1 end
  end
  return n
end

function SB:GetButton()
  return self:_ensureButton()
end

-- 把安全按钮挂到面板容器里并定位（脱战时调用，战斗中改父级/锚点会被锁定）。
function SB:PlaceInPanel(parent, point, relTo, relPoint, x, y)
  local btn = self:_ensureButton()
  if InCombatLockdown() then return btn end
  btn:SetParent(parent)
  btn:ClearAllPoints()
  btn:SetPoint(point, relTo, relPoint, x, y)
  btn:Show()
  return btn
end
