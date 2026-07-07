local addonName, ns = ...

local MainFrame = {}
ns.MainFrame = ns.Core:RegisterModule("MainFrame", MainFrame)

local Utils = ns.Utils
local Const = ns.Constants

local FRAME_WIDTH = 560
local FRAME_HEIGHT = 380
local SIDEBAR_WIDTH = 150
local ROW_HEIGHT = 46
local CONTENT_WIDTH = FRAME_WIDTH - SIDEBAR_WIDTH - 60

-- 侧栏导航项。后续批次（插件管理/备份迁移）在此追加即可。
local NAV = {
  { key = "overview", label = "概览" },
}

function MainFrame:Init()
  -- 懒创建：首次打开时才建帧。
  -- 订阅注册表变化：插件"后注册"时若窗口已开，刷新列表。
  ns.Discovery:AddListener(function()
    if self.frame and self.frame:IsShown() then
      self:Refresh()
    end
  end)
end

-- 概览页每个插件的状态文案与颜色。版本由 Discovery 从各插件 toc 实时读取。
local function pluginStatus(desc)
  local tag = desc.bundled and "整包成员" or "已接入"
  return "已启用 |cff808080·|r " .. tag, "ff40ff40"
end

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
  f.rows = {}

  -- 空态提示。
  local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  empty:SetPoint("TOPLEFT", 4, -8)
  empty:SetWidth(FRAME_WIDTH - SIDEBAR_WIDTH - 70)
  empty:SetJustifyH("LEFT")
  empty:SetText("尚未检测到已接入的插件。\n请确认 MyChat / RoleManager 等插件已安装并启用。")
  f.emptyLabel = empty

  self.frame = f
  self.currentNav = self.currentNav or "overview"
  return f
end

-- 取一行插件卡片（复用池）。
local function acquireRow(content, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, content, "BackdropTemplate")
  row:SetSize(CONTENT_WIDTH, ROW_HEIGHT - 6)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
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
  open:SetText("打开设置")
  row.openButton = open

  rows[i] = row
  return row
end

function MainFrame:Refresh()
  local f = self.frame
  if not f then return end

  local list = ns.Discovery:GetOrdered()
  f.emptyLabel:SetShown(#list == 0)

  for i, desc in ipairs(list) do
    local row = acquireRow(f.content, f.rows, i)
    local statusText, statusColor = pluginStatus(desc)

    local verText = desc.version and (" |cff808080v" .. desc.version .. "|r") or ""
    row.nameLabel:SetText((desc.title or "?") .. verText)
    row.statusLabel:SetText(Utils.ColorText(statusColor, statusText)
      .. (desc.slashCmd and ("  |cff808080" .. desc.slashCmd .. "|r") or ""))

    -- 有 openSettings 才启用按钮。
    if type(desc.openSettings) == "function" then
      row.openButton:Enable()
      row.openButton:SetScript("OnClick", function()
        ns.Core:SafeCall(function()
          local ok = desc.openSettings()
          if ok == false then
            Utils.Print(tostring(desc.title) .. "：当前客户端不支持打开该设置面板。")
          end
        end)
      end)
    else
      row.openButton:Disable()
      row.openButton:SetScript("OnClick", nil)
    end
    row:Show()
  end
  for i = #list + 1, #f.rows do
    f.rows[i]:Hide()
  end
  f.content:SetHeight(math.max(10, #list * ROW_HEIGHT))
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
