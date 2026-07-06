local addonName, ns = ...

local Panel = {}
ns.Panel = ns.Core:RegisterModule("Panel", Panel)

local Const = ns.Constants
local Utils = ns.Utils

local FRAME_WIDTH = 340
local FRAME_HEIGHT = 420
local ROW_H = 26
local LIST_TOP = -84
local LIST_BOTTOM = 84

function Panel:Init()
  self.selected = {}   -- sig -> true
  self.candidates = {}
  self.rows = {}
end

local function sigOf(c)
  return c.bag .. ":" .. c.slot .. ":" .. c.itemID
end

function Panel:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "QuickDisenchantPanel", UIParent, "BackdropTemplate")
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
  title:SetText(Const.ADDON_TITLE)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 顶部批量操作。
  local selAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selAll:SetSize(64, 22)
  selAll:SetPoint("TOPLEFT", 14, -40)
  selAll:SetText("全选")
  selAll:SetScript("OnClick", function() ns.Core:SafeCall(function() Panel:_selectAll(true) end) end)

  local selNone = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selNone:SetSize(64, 22)
  selNone:SetPoint("LEFT", selAll, "RIGHT", 6, 0)
  selNone:SetText("全不选")
  selNone:SetScript("OnClick", function() ns.Core:SafeCall(function() Panel:_selectAll(false) end) end)

  local rescan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  rescan:SetSize(64, 22)
  rescan:SetPoint("LEFT", selNone, "RIGHT", 6, 0)
  rescan:SetText("重新扫描")
  rescan:SetScript("OnClick", function() ns.Core:SafeCall(function() Panel:Refresh() end) end)

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -66)
  hint:SetText("勾选要分解的装备，然后连点下方按钮（或绑定按键连按）。")

  -- 候选列表滚动区。
  local scroll = CreateFrame("ScrollFrame", "QuickDisenchantPanelScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -34, LIST_BOTTOM)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(FRAME_WIDTH - 50, 10)
  scroll:SetScrollChild(content)
  f.content = content

  -- 底部状态与安全按钮容器。
  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 14, 56)
  status:SetPoint("BOTTOMRIGHT", -14, 56)
  status:SetJustifyH("LEFT")
  f.status = status

  local notice = f:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
  notice:SetPoint("BOTTOMLEFT", 14, 40)
  notice:SetPoint("BOTTOMRIGHT", -14, 40)
  notice:SetJustifyH("LEFT")
  f.notice = notice

  self.frame = f
  self.buttonAnchor = { point = "BOTTOM", x = 0, y = 12 }
  return f
end

-- 把安全连点按钮放到面板底部（脱战时）。
function Panel:_placeButton()
  local f = self.frame
  local btn = ns.SecureButton:PlaceInPanel(f, "BOTTOM", f, "BOTTOM", 0, 12)
  return btn
end

local function acquireRow(parent, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetHitRectInsets(0, -200, 0, 0)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", row, "RIGHT", 2, 0)
  row.icon = icon

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  label:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
  label:SetJustifyH("LEFT")
  row.label = label

  -- 悬浮显示物品 tooltip。
  row:SetScript("OnEnter", function(self)
    if self._link then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self._link)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)

  rows[i] = row
  return row
end

function Panel:Refresh()
  local f = self:_ensureFrame()

  if not ns.Scanner:CanDisenchant() then
    for _, row in ipairs(self.rows) do row:Hide() end
    f.status:SetText("")
    f.notice:SetText("当前角色未学习附魔（分解），插件不可用。")
    self.candidates = {}
    ns.SecureButton:SetQueue({})
    return
  end
  f.notice:SetText("")

  local list = ns.Scanner:Scan()
  self.candidates = list

  -- 首次扫描按配置决定是否默认全选。
  if ns.Config:Get("profile.autoSelectOnScan") then
    for _, c in ipairs(list) do self.selected[sigOf(c)] = true end
  end

  for i, c in ipairs(list) do
    local row = acquireRow(f.content, self.rows, i)
    local hex = Utils.QualityHex(c.quality)
    local name = c.name or (c.link and c.link:match("%[(.-)%]")) or ("物品 " .. c.itemID)
    row.label:SetText(Utils.ColorText(hex, name))
    if c.icon then row.icon:SetTexture(c.icon) end
    row._link = c.link
    row._sig = sigOf(c)
    row:SetChecked(self.selected[row._sig] == true)
    row:SetScript("OnClick", function(self)
      ns.Core:SafeCall(function()
        Panel.selected[self._sig] = self:GetChecked() and true or nil
        Panel:_syncQueue()
      end)
    end)
    row:Show()
  end
  for i = #list + 1, #self.rows do self.rows[i]:Hide() end
  f.content:SetHeight(math.max(10, #list * ROW_H))

  self:_syncQueue()
  self:_placeButton()
  self:NotifyCombat(InCombatLockdown())
end

-- 依据勾选集合刷新安全按钮队列与状态文本。
function Panel:_syncQueue()
  local queue = {}
  for _, c in ipairs(self.candidates) do
    if self.selected[sigOf(c)] then queue[#queue + 1] = c end
  end
  ns.SecureButton:SetQueue(queue)
  local f = self.frame
  if f then
    f.status:SetText(string.format("候选 %d 件，已勾选 |cff33ff99%d|r 件。",
      #self.candidates, #queue))
  end
end

function Panel:_selectAll(on)
  for _, c in ipairs(self.candidates) do
    self.selected[sigOf(c)] = on and true or nil
  end
  for _, row in ipairs(self.rows) do
    if row:IsShown() then row:SetChecked(on) end
  end
  self:_syncQueue()
end

-- SecureButton 分解成功后回调：重扫刷新（消耗掉的物品会自然消失）。
function Panel:NotifyConsumed(entry)
  if entry then self.selected[entry.bag .. ":" .. entry.slot .. ":" .. entry.itemID] = nil end
  if self.frame and self.frame:IsShown() then
    self:Refresh()
  end
end

-- 战斗状态变化：战斗中安全按钮无法改属性，给出提示。
function Panel:NotifyCombat(inCombat)
  local f = self.frame
  if not f then return end
  if inCombat then
    f.notice:SetText("战斗中：分解按钮暂不可用，脱战后自动恢复。")
  elseif ns.Scanner:CanDisenchant() then
    f.notice:SetText("")
  end
end

function Panel:Open()
  local f = self:_ensureFrame()
  self:Refresh()
  f:Show()
  return true
end

function Panel:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then
    f:Hide()
  else
    self:Open()
  end
end
