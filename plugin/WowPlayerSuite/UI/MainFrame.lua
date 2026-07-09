local addonName, ns = ...

local MainFrame = {}
ns.MainFrame = ns.Core:RegisterModule("MainFrame", MainFrame)

local Utils = ns.Utils
local Const = ns.Constants

local FRAME_WIDTH = 560
local FRAME_HEIGHT = 400
local SIDEBAR_WIDTH = 150
local CARD_HEIGHT = 46
local HEADER_HEIGHT = 24
local MANAGE_ROW_HEIGHT = 30
local GROUP_GAP = 6
local CONTENT_WIDTH = FRAME_WIDTH - SIDEBAR_WIDTH - 60

-- 侧栏导航项。
local NAV = {
  { key = "overview", label = "概览" },
  { key = "manage",   label = "插件管理" },
}

function MainFrame:Init()
  self.currentNav = self.currentNav or "overview"
  -- 发现结果变化时，若窗口已开则刷新（插件后加载/自愿注册触发）。
  ns.Discovery:AddListener(function()
    if self.frame and self.frame:IsShown() then
      self:Refresh()
    end
  end)
end

-- ============================ 帧与控件 ============================

function MainFrame:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "WowPlayerSuiteMain", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText(Const.ADDON_TITLE)

  local ver = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  ver:SetPoint("LEFT", title, "RIGHT", 8, 0)
  ver:SetText("v" .. Const.VERSION)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 侧栏。
  local sidebar = CreateFrame("Frame", nil, f)
  sidebar:SetPoint("TOPLEFT", 10, -36)
  sidebar:SetPoint("BOTTOMLEFT", 10, 12)
  sidebar:SetWidth(SIDEBAR_WIDTH)
  f.navButtons = {}
  for i, item in ipairs(NAV) do
    local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    btn:SetSize(SIDEBAR_WIDTH, 24)
    btn:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
    btn:SetText(item.label)
    btn:SetScript("OnClick", function()
      MainFrame.currentNav = item.key
      MainFrame:Refresh()
    end)
    f.navButtons[item.key] = btn
  end

  -- 内容区滚动。
  local scroll = CreateFrame("ScrollFrame", "WowPlayerSuiteMainScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_WIDTH, 10)
  scroll:SetScrollChild(content)
  f.scroll = scroll
  f.content = content

  -- 各类行的复用池。
  f.headerRows = {}   -- 分类标题（概览）
  f.cardRows = {}     -- 插件卡片（概览）
  f.manageRows = {}   -- 启停行（插件管理）

  -- 空态提示。
  local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  empty:SetPoint("TOPLEFT", 4, -8)
  empty:SetWidth(CONTENT_WIDTH - 10)
  empty:SetJustifyH("LEFT")
  empty:SetText("尚未检测到已接入的插件。\n请确认相关插件已安装并启用。")
  f.emptyLabel = empty

  self.frame = f
  self:_highlightNav()
  return f
end

-- 侧栏当前页高亮（简单地锁住选中项）。
function MainFrame:_highlightNav()
  local f = self.frame
  if not f then return end
  for key, btn in pairs(f.navButtons) do
    if key == self.currentNav then
      btn:LockHighlight()
    else
      btn:UnlockHighlight()
    end
  end
end

-- --- 分类标题行 ---
local function acquireHeader(content, pool, i)
  local h = pool[i]
  if h then return h end
  h = CreateFrame("Frame", nil, content)
  h:SetSize(CONTENT_WIDTH, HEADER_HEIGHT)
  local fs = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("BOTTOMLEFT", 2, 4)
  fs:SetTextColor(1, 0.82, 0)
  h.label = fs
  local line = h:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", -4, 0)
  pool[i] = h
  return h
end

-- --- 插件卡片行（概览）---
local function acquireCard(content, pool, i)
  local row = pool[i]
  if row then return row end
  row = CreateFrame("Frame", nil, content, "BackdropTemplate")
  row:SetSize(CONTENT_WIDTH - 12, CARD_HEIGHT - 6)
  if row.SetBackdrop then
    row:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
  end

  local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  name:SetPoint("TOPLEFT", 8, -6)
  row.nameLabel = name

  local status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 8, 6)
  row.statusLabel = status

  local open = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  open:SetSize(76, 22)
  open:SetPoint("RIGHT", -8, 0)
  row.openButton = open

  pool[i] = row
  return row
end

-- --- 启停行（插件管理）---
local function acquireManageRow(content, pool, i)
  local row = pool[i]
  if row then return row end
  row = CreateFrame("Frame", nil, content)
  row:SetSize(CONTENT_WIDTH, MANAGE_ROW_HEIGHT)

  local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetPoint("LEFT", 2, 0)
  row.check = check

  local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  name:SetPoint("LEFT", check, "RIGHT", 4, 0)
  name:SetWidth(200)
  name:SetJustifyH("LEFT")
  row.nameLabel = name

  local status = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  status:SetPoint("RIGHT", -8, 0)
  row.statusLabel = status

  pool[i] = row
  return row
end

local function hideAll(pool)
  for _, r in ipairs(pool) do r:Hide() end
end

-- ============================ 概览页 ============================

local function pluginStatus(desc)
  local catName = desc.category and Const.CATEGORY[desc.category] or nil
  local tag = desc.bundled and "整包成员" or "已接入"
  local suffix = catName and (" |cff808080·|r " .. catName) or ""
  return "已启用 |cff808080·|r " .. tag .. suffix, "ff40ff40"
end

function MainFrame:_renderOverview(f)
  local list = ns.Discovery:GetOrdered()
  f.emptyLabel:SetShown(#list == 0)

  -- 按分类分组。
  local groups = {}
  for _, desc in ipairs(list) do
    local cat = desc.category or "__other"
    groups[cat] = groups[cat] or {}
    groups[cat][#groups[cat] + 1] = desc
  end

  local y = 0
  local hi, ci = 0, 0
  local seen = {}

  local function emit(catKey)
    local items = groups[catKey]
    if not items or #items == 0 then return end
    seen[catKey] = true

    hi = hi + 1
    local header = acquireHeader(f.content, f.headerRows, hi)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, -y)
    header.label:SetText(Const.CATEGORY[catKey] or catKey)
    header:Show()
    y = y + HEADER_HEIGHT

    for _, desc in ipairs(items) do
      ci = ci + 1
      local row = acquireCard(f.content, f.cardRows, ci)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 12, -y)

      local statusText, statusColor = pluginStatus(desc)
      local verText = desc.version and (" |cff808080v" .. desc.version .. "|r") or ""
      row.nameLabel:SetText((desc.title or "?") .. verText)
      row.statusLabel:SetText(Utils.ColorText(statusColor, statusText)
        .. (desc.slashCmd and ("  |cff808080" .. desc.slashCmd .. "|r") or ""))

      row.openButton:SetText(desc.openLabel or "打开")
      if type(desc.openSettings) == "function" then
        row.openButton:Enable()
        row.openButton:SetScript("OnClick", function()
          ns.Core:SafeCall(function()
            local ok = desc.openSettings()
            if ok == false then
              Utils.Print(tostring(desc.title) .. "：当前客户端不支持该操作。")
            end
          end)
        end)
      else
        row.openButton:Disable()
        row.openButton:SetScript("OnClick", nil)
      end
      row:Show()
      y = y + CARD_HEIGHT
    end
    y = y + GROUP_GAP
  end

  for _, catKey in ipairs(Const.CATEGORY_ORDER or {}) do emit(catKey) end
  for catKey in pairs(groups) do
    if not seen[catKey] then emit(catKey) end
  end

  f.content:SetHeight(math.max(10, y))
end

-- ============================ 插件管理页 ============================

local STATE_TEXT = {
  [0] = { "已禁用", "ffff5555" },
  [1] = { "部分启用", "ffffd100" },
  [2] = { "已启用", "ff40ff40" },
}

function MainFrame:_ensureReloadBar(f)
  if f.reloadBar then return f.reloadBar end
  local bar = CreateFrame("Frame", nil, f.content)
  bar:SetSize(CONTENT_WIDTH, 30)

  local info = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  info:SetPoint("LEFT", 2, 0)
  info:SetTextColor(1, 0.82, 0)
  info:SetText("改动将在重载界面后生效。")
  bar.info = info

  local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
  btn:SetSize(88, 22)
  btn:SetPoint("RIGHT", -8, 0)
  btn:SetText("立即重载")
  btn:SetScript("OnClick", function() ReloadUI() end)
  bar.button = btn

  f.reloadBar = bar
  return bar
end

function MainFrame:_renderManage(f)
  f.emptyLabel:Hide()
  local list = ns.Discovery:GetManageable()

  local y = 0
  -- 顶部提示：始终说明"需重载"；有待生效改动时给醒目重载按钮。
  local bar = self:_ensureReloadBar(f)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", 0, -y)
  if self.pendingReload then
    bar.info:SetText("|cffffd100有改动待生效，请重载界面。|r")
    bar.button:Enable()
  else
    bar.info:SetText("启用/禁用插件将在重载界面后生效。")
    bar.button:Disable()
  end
  bar:Show()
  y = y + 34

  for i, item in ipairs(list) do
    local row = acquireManageRow(f.content, f.manageRows, i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 2, -y)

    local catName = item.category and Const.CATEGORY[item.category] or ""
    row.nameLabel:SetText(item.title .. (catName ~= "" and ("  |cff808080" .. catName .. "|r") or ""))

    row.check:SetScript("OnClick", nil)  -- 先清，避免 SetChecked 触发旧回调
    if not item.installed then
      row.check:SetChecked(false)
      row.check:Disable()
      row.statusLabel:SetText(Utils.ColorText("ff808080", "未安装"))
    else
      row.check:Enable()
      row.check:SetChecked(item.state == 2 or item.state == 1)
      local st = STATE_TEXT[item.state] or STATE_TEXT[2]
      row.statusLabel:SetText(Utils.ColorText(st[2], st[1]))
      row.check:SetScript("OnClick", function(self)
        local enable = self:GetChecked() and true or false
        ns.Discovery:SetEnabled(item.addon, enable)
        MainFrame.pendingReload = true
        MainFrame:Refresh()
      end)
    end
    row:Show()
    y = y + MANAGE_ROW_HEIGHT
  end

  f.content:SetHeight(math.max(10, y))
end

-- ============================ 调度 ============================

function MainFrame:Refresh()
  local f = self.frame
  if not f then return end

  hideAll(f.headerRows)
  hideAll(f.cardRows)
  hideAll(f.manageRows)
  if f.reloadBar then f.reloadBar:Hide() end

  self:_highlightNav()

  if self.currentNav == "manage" then
    self:_renderManage(f)
  else
    self:_renderOverview(f)
  end
end

function MainFrame:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then
    f:Hide()
  else
    self:Refresh()
    f:Show()
  end
end

function MainFrame:Show()
  local f = self:_ensureFrame()
  self:Refresh()
  f:Show()
end
