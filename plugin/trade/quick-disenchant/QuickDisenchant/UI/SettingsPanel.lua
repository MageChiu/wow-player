local addonName, ns = ...

local Settings = {}
ns.SettingsPanel = ns.Core:RegisterModule("SettingsPanel", Settings)

local Const = ns.Constants

local FRAME_WIDTH = 380
local FRAME_HEIGHT = 420
local ROW_H = 24

function Settings:Init()
  -- 懒创建。
end

function Settings:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "QuickDisenchantSettings", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText(Const.ADDON_TITLE .. " 设置")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 品质分级开关。
  local tierHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  tierHeader:SetPoint("TOPLEFT", 14, -44)
  tierHeader:SetText("|cffffd200分解品质|r（勾选的品质才会进入候选）")

  f.tierChecks = {}
  local y = -66
  for _, tier in ipairs(Const.TIER_ORDER) do
    local cb = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 20, y)
    cb.Text:SetText(Const.TIER_LABEL[tier])
    cb:SetChecked(ns.Config:IsTierEnabled(tier))
    cb:SetScript("OnClick", function(self)
      ns.Config:SetTierEnabled(tier, self:GetChecked())
      if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsShown() then
        ns.Panel:Refresh()
      end
    end)
    f.tierChecks[tier] = cb
    y = y - ROW_H
  end

  -- 行为开关。
  local behHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  behHeader:SetPoint("TOPLEFT", 14, y - 6)
  behHeader:SetText("|cffffd200行为|r")
  y = y - 28

  local boundCB = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
  boundCB:SetPoint("TOPLEFT", 20, y)
  boundCB.Text:SetText("只分解已绑定的装备（保护未绑定新装）")
  boundCB:SetChecked(ns.Config:Get("profile.onlyBound") and true or false)
  boundCB:SetScript("OnClick", function(self)
    ns.Config:Set("profile.onlyBound", self:GetChecked() and true or false)
    if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsShown() then ns.Panel:Refresh() end
  end)
  y = y - ROW_H

  local autoCB = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
  autoCB:SetPoint("TOPLEFT", 20, y)
  autoCB.Text:SetText("打开面板时默认勾选全部候选")
  autoCB:SetChecked(ns.Config:Get("profile.autoSelectOnScan") and true or false)
  autoCB:SetScript("OnClick", function(self)
    ns.Config:Set("profile.autoSelectOnScan", self:GetChecked() and true or false)
  end)
  y = y - ROW_H

  local mmCB = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
  mmCB:SetPoint("TOPLEFT", 20, y)
  mmCB.Text:SetText("显示小地图按钮")
  mmCB:SetChecked(ns.Config:Get("profile.showMinimapButton") and true or false)
  mmCB:SetScript("OnClick", function(self)
    if ns.MinimapButton then ns.MinimapButton:Toggle() end
    self:SetChecked(ns.Config:Get("profile.showMinimapButton") and true or false)
  end)

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 14, 40)
  hint:SetPoint("BOTTOMRIGHT", -14, 40)
  hint:SetJustifyH("LEFT")
  hint:SetText("提示：分解蓝/紫装备时游戏会弹二次确认框，需你手动确认（暴雪限制，插件不能自动点掉）。")

  local hint2 = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint2:SetPoint("BOTTOMLEFT", 14, 14)
  hint2:SetText("可在 系统-按键设置-QuickDisenchant 里绑定按键实现连按分解。")

  self.frame = f
  return f
end

function Settings:_refresh()
  local f = self.frame
  if not f then return end
  for _, tier in ipairs(Const.TIER_ORDER) do
    if f.tierChecks[tier] then f.tierChecks[tier]:SetChecked(ns.Config:IsTierEnabled(tier)) end
  end
end

function Settings:Open()
  local f = self:_ensureFrame()
  self:_refresh()
  f:Show()
  return true
end

function Settings:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then f:Hide() else self:Open() end
end
