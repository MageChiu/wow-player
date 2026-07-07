local addonName, ns = ...

local Settings = {}
ns.SettingsPanel = ns.Core:RegisterModule("SettingsPanel", Settings)

local Utils = ns.Utils
local Const = ns.Constants

local FRAME_WIDTH = 460
local FRAME_HEIGHT = 520
local ROW_H = 22

function Settings:Init()
  -- 懒创建。
end

function Settings:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "RoleManagerSettings", UIParent, "BackdropTemplate")
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

  -- 货币区标题。
  local curHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  curHeader:SetPoint("TOPLEFT", 14, -40)
  curHeader:SetText("|cffffd200追踪货币|r（勾选要在汇总里显示的货币）")

  local curScroll = CreateFrame("ScrollFrame", "RoleManagerSettingsCurScroll", f, "UIPanelScrollFrameTemplate")
  curScroll:SetPoint("TOPLEFT", 14, -62)
  curScroll:SetPoint("TOPRIGHT", -34, -62)
  curScroll:SetHeight(240)
  local curContent = CreateFrame("Frame", nil, curScroll)
  curContent:SetSize(FRAME_WIDTH - 50, 10)
  curScroll:SetScrollChild(curContent)
  f.curContent = curContent
  f.curRows = {}

  -- 角色区标题。
  local charHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  charHeader:SetPoint("TOPLEFT", 14, -314)
  charHeader:SetText("|cffffd200显示角色|r（取消勾选则在汇总里隐藏）")

  local charScroll = CreateFrame("ScrollFrame", "RoleManagerSettingsCharScroll", f, "UIPanelScrollFrameTemplate")
  charScroll:SetPoint("TOPLEFT", 14, -336)
  charScroll:SetPoint("TOPRIGHT", -34, -336)
  charScroll:SetHeight(130)
  local charContent = CreateFrame("Frame", nil, charScroll)
  charContent:SetSize(FRAME_WIDTH - 50, 10)
  charScroll:SetScrollChild(charContent)
  f.charContent = charContent
  f.charRows = {}

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 14, 14)
  hint:SetText("货币列表来自你当前拥有的货币。切换角色后重开可看到该角色的货币。")

  self.frame = f
  return f
end

-- 复用行：一个 CheckButton + 文本。
local function acquireCheckRow(parent, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  rows[i] = row
  return row
end

function Settings:_refreshCurrencies()
  local f = self.frame
  local list = Utils.EnumerateOwnedCurrencies()
  for i, cur in ipairs(list) do
    local row = acquireCheckRow(f.curContent, f.curRows, i)
    row.Text:SetText(string.format("%s  |cff888888(%d, ID %d)|r", cur.name, cur.quantity, cur.id))
    row:SetChecked(ns.Config:IsCurrencyTracked(cur.id))
    row:SetScript("OnClick", function(btn)
      ns.Config:SetCurrencyTracked(cur.id, btn:GetChecked() and true or false)
      ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
      if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
        ns.OverviewFrame:Refresh()
      end
    end)
    row:Show()
  end
  for i = #list + 1, #f.curRows do f.curRows[i]:Hide() end
  f.curContent:SetHeight(math.max(10, #list * ROW_H))
  if #list == 0 then
    if not f.curEmpty then
      f.curEmpty = f.curContent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      f.curEmpty:SetPoint("TOPLEFT", 4, -4)
      f.curEmpty:SetText("未读取到货币（打开一次货币面板或稍后重试）。")
    end
    f.curEmpty:Show()
  elseif f.curEmpty then
    f.curEmpty:Hide()
  end
end

function Settings:_refreshChars()
  local f = self.frame
  local chars = {}
  for key, rec in pairs(ns.Config:GetChars()) do
    chars[#chars + 1] = { key = key, rec = rec }
  end
  table.sort(chars, function(a, b) return (a.rec.updatedAt or 0) > (b.rec.updatedAt or 0) end)

  for i, entry in ipairs(chars) do
    local row = acquireCheckRow(f.charContent, f.charRows, i)
    local name = Utils.ShortName(entry.rec.name) or entry.key
    row.Text:SetText(string.format("%s-%s", name, entry.rec.realm or "?"))
    row:SetChecked(not ns.Config:IsCharHidden(entry.key))
    row:SetScript("OnClick", function(btn)
      ns.Config:SetCharHidden(entry.key, not btn:GetChecked())
      if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
        ns.OverviewFrame:Refresh()
      end
    end)
    row:Show()
  end
  for i = #chars + 1, #f.charRows do f.charRows[i]:Hide() end
  f.charContent:SetHeight(math.max(10, #chars * ROW_H))
end

function Settings:Open()
  local f = self:_ensureFrame()
  ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
  self:_refreshCurrencies()
  self:_refreshChars()
  f:Show()
  return true
end

function Settings:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then f:Hide() else self:Open() end
end
