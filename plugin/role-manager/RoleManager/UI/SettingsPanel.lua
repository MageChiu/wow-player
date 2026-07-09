local addonName, ns = ...

local Settings = {}
ns.SettingsPanel = ns.Core:RegisterModule("SettingsPanel", Settings)

local Utils = ns.Utils
local Const = ns.Constants

local FRAME_WIDTH = 460
local FRAME_HEIGHT = 640
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

  -- 货币区。
  local curHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  curHeader:SetPoint("TOPLEFT", 14, -40)
  curHeader:SetText("|cffffd200追踪货币|r（勾选要在汇总里显示的货币）")

  local curScroll = CreateFrame("ScrollFrame", "RoleManagerSettingsCurScroll", f, "UIPanelScrollFrameTemplate")
  curScroll:SetPoint("TOPLEFT", 14, -62)
  curScroll:SetPoint("TOPRIGHT", -34, -62)
  curScroll:SetHeight(190)
  local curContent = CreateFrame("Frame", nil, curScroll)
  curContent:SetSize(FRAME_WIDTH - 50, 10)
  curScroll:SetScrollChild(curContent)
  f.curContent = curContent
  f.curRows = {}

  -- 周任务区：标题 + (ID 输入框 + 名称输入框 + 添加按钮) + 已追踪列表。
  local wqHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  wqHeader:SetPoint("TOPLEFT", 14, -262)
  wqHeader:SetText("|cffffd200周常任务|r（手动填任务 ID，名称留空则自动取）")

  local idBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  idBox:SetSize(70, 20)
  idBox:SetPoint("TOPLEFT", 20, -284)
  idBox:SetAutoFocus(false)
  idBox:SetNumeric(true)
  idBox:SetMaxLetters(10)
  f.wqIdBox = idBox

  local idLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  idLabel:SetPoint("BOTTOMLEFT", idBox, "TOPLEFT", 0, 1)
  idLabel:SetText("任务ID")

  local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  nameBox:SetSize(180, 20)
  nameBox:SetPoint("LEFT", idBox, "RIGHT", 20, 0)
  nameBox:SetAutoFocus(false)
  nameBox:SetMaxLetters(40)
  f.wqNameBox = nameBox

  local nameLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  nameLabel:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 0, 1)
  nameLabel:SetText("名称（可留空）")

  local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  addBtn:SetSize(50, 22)
  addBtn:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
  addBtn:SetText("添加")
  addBtn:SetScript("OnClick", function()
    local id = tonumber(idBox:GetText())
    if not id then return end
    ns.Config:AddWeeklyQuest(id, Utils.Trim(nameBox:GetText() or ""))
    idBox:SetText(""); nameBox:SetText("")
    idBox:ClearFocus(); nameBox:ClearFocus()
    ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
    Settings:_refreshWeeklyQuests()
    if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
      ns.OverviewFrame:Refresh()
    end
  end)

  local wqScroll = CreateFrame("ScrollFrame", "RoleManagerSettingsWqScroll", f, "UIPanelScrollFrameTemplate")
  wqScroll:SetPoint("TOPLEFT", 14, -312)
  wqScroll:SetPoint("TOPRIGHT", -34, -312)
  wqScroll:SetHeight(120)
  local wqContent = CreateFrame("Frame", nil, wqScroll)
  wqContent:SetSize(FRAME_WIDTH - 50, 10)
  wqScroll:SetScrollChild(wqContent)
  f.wqContent = wqContent
  f.wqRows = {}

  -- 角色区。
  local charHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  charHeader:SetPoint("TOPLEFT", 14, -444)
  charHeader:SetText("|cffffd200显示角色|r（取消勾选则在汇总里隐藏）")

  local charScroll = CreateFrame("ScrollFrame", "RoleManagerSettingsCharScroll", f, "UIPanelScrollFrameTemplate")
  charScroll:SetPoint("TOPLEFT", 14, -466)
  charScroll:SetPoint("TOPRIGHT", -34, -466)
  charScroll:SetHeight(120)
  local charContent = CreateFrame("Frame", nil, charScroll)
  charContent:SetSize(FRAME_WIDTH - 50, 10)
  charScroll:SetScrollChild(charContent)
  f.charContent = charContent
  f.charRows = {}

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 14, 12)
  hint:SetText("货币列表来自当前拥有的货币；周任务 ID 可在 Wowhead 查询。")

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

-- 周任务行：文本 + 右侧删除按钮（复用池）。
local function acquireQuestRow(parent, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, parent)
  row:SetSize(parent:GetWidth(), ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("LEFT", 4, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(parent:GetWidth() - 60)
  label:SetWordWrap(false)
  row.label = label

  local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  del:SetSize(44, 18)
  del:SetPoint("RIGHT", 0, 0)
  del:SetText("删除")
  row.del = del

  rows[i] = row
  return row
end

function Settings:_refreshWeeklyQuests()
  local f = self.frame
  local quests = ns.Config:Get("profile.weeklyQuests") or {}
  local list = {}
  for id, name in pairs(quests) do
    list[#list + 1] = { id = id, name = name }
  end
  table.sort(list, function(a, b) return a.id < b.id end)

  -- 完成状态取当前角色的快照（面板打开前已 CollectSelf 过）。
  local selfRec = ns.Config:GetChars()[Utils.CharKey()]
  local done = selfRec and selfRec.weeklyQuestDone or {}

  for i, q in ipairs(list) do
    local row = acquireQuestRow(f.wqContent, f.wqRows, i)
    local mark = done[q.id] and "|cff40ff40[✓]|r" or "|cff808080[ ]|r"
    row.label:SetText(string.format("%s %s  |cff888888(%d)|r", mark, q.name or "?", q.id))
    row.del:SetScript("OnClick", function()
      ns.Config:RemoveWeeklyQuest(q.id)
      Settings:_refreshWeeklyQuests()
      if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
        ns.OverviewFrame:Refresh()
      end
    end)
    row:Show()
  end
  for i = #list + 1, #f.wqRows do f.wqRows[i]:Hide() end
  f.wqContent:SetHeight(math.max(10, #list * ROW_H))

  if #list == 0 then
    if not f.wqEmpty then
      f.wqEmpty = f.wqContent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      f.wqEmpty:SetPoint("TOPLEFT", 4, -4)
      f.wqEmpty:SetText("尚未追踪任何周任务。填入任务 ID 后点添加。")
    end
    f.wqEmpty:Show()
  elseif f.wqEmpty then
    f.wqEmpty:Hide()
  end
end

function Settings:Open()
  local f = self:_ensureFrame()
  ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
  self:_refreshCurrencies()
  self:_refreshWeeklyQuests()
  self:_refreshChars()
  f:Show()
  return true
end

function Settings:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then f:Hide() else self:Open() end
end
