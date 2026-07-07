local addonName, ns = ...

local Overview = {}
ns.OverviewFrame = ns.Core:RegisterModule("OverviewFrame", Overview)

local Utils = ns.Utils
local Const = ns.Constants

-- 职业颜色（AARRGGBB），用于角色名着色。缺失职业回退白色。
local CLASS_COLOR = {
  WARRIOR = "ffc79c6e", PALADIN = "fff58cba", HUNTER = "ffabd473",
  ROGUE = "fffff569", PRIEST = "ffffffff", DEATHKNIGHT = "ffc41f3b",
  SHAMAN = "ff0070de", MAGE = "ff69ccf0", WARLOCK = "ff9482c9",
  MONK = "ff00ff96", DRUID = "ffff7d0a", DEMONHUNTER = "ffa330c9",
  EVOKER = "ff33937f",
}

-- 列布局：{ x 偏移, 宽度, 标题, key }。变长的"代币"列放最后，避免它
-- 过长时把前面的固定列挤歪。每个单元格设固定宽 + 关闭换行，超宽自动裁剪。
local COLUMNS = {
  { key = "name",   x = 8,   w = 118, title = "角色" },
  { key = "money",  x = 128, w = 118, title = "背包金币" },
  { key = "mythic", x = 248, w = 92,  title = "大秘境" },
  { key = "key",    x = 342, w = 118, title = "当前钥石" },
  { key = "raid",   x = 462, w = 74,  title = "团本" },
  { key = "vault",  x = 538, w = 46,  title = "宝库" },
  { key = "weekly", x = 586, w = 42,  title = "周常" },
  { key = "update", x = 630, w = 66,  title = "更新" },
  { key = "cur",    x = 698, w = 260, title = "代币" },
}

local ROW_HEIGHT = 18
local FRAME_WIDTH = 990
local FRAME_HEIGHT = 460

function Overview:Init()
  -- 懒创建，首次打开时才建帧。
end

local function classColor(rec)
  return CLASS_COLOR[rec.class or ""] or "ffffffff"
end

-- 拼一行角色的代币简述："名:数量  名:数量"，最多显示 N 种（超出显示 +k）。
local function currencyText(rec)
  if not rec.currencies then return "—" end
  local limit = tonumber(ns.Config:Get("profile.currencyDisplayLimit")) or 3
  local parts = {}
  for _, info in pairs(rec.currencies) do
    parts[#parts + 1] = string.format("%s:%d", info.name or "?", info.quantity or 0)
  end
  if #parts == 0 then return "—" end
  if #parts > limit then
    local shown = {}
    for i = 1, limit do shown[i] = parts[i] end
    return table.concat(shown, "  ") .. string.format("  +%d", #parts - limit)
  end
  return table.concat(parts, "  ")
end

function Overview:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "RoleManagerOverview", UIParent, "BackdropTemplate")
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
  title:SetText(Const.ADDON_TITLE .. " 角色汇总")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 战团银行金币行（账号共享，单独一行放顶部）。
  local warband = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  warband:SetPoint("TOPLEFT", 12, -34)
  warband:SetJustifyH("LEFT")
  f.warbandLine = warband

  -- 列头。用固定宽度 FontString 保证与数据行左边缘对齐。
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 8, -54)
  header:SetSize(FRAME_WIDTH - 16, ROW_HEIGHT)
  for _, col in ipairs(COLUMNS) do
    local fs = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("LEFT", col.x, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText("|cffffd100" .. col.title .. "|r")
  end

  -- 滚动区容纳角色行。
  local scroll = CreateFrame("ScrollFrame", "RoleManagerOverviewScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -74)
  scroll:SetPoint("BOTTOMRIGHT", -30, 34)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(FRAME_WIDTH - 40, 10)
  scroll:SetScrollChild(content)
  f.scroll = scroll
  f.content = content
  f.rows = {}

  -- 底部提示与按钮。
  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 12)
  hint:SetText("数据为各角色最后登录时的快照，非实时。")

  local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(90, 22)
  refresh:SetPoint("BOTTOMRIGHT", -34, 8)
  refresh:SetText("刷新本角色")
  refresh:SetScript("OnClick", function()
    ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
    Overview:Refresh()
  end)

  local config = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  config:SetSize(70, 22)
  config:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
  config:SetText("设置")
  config:SetScript("OnClick", function()
    if ns.SettingsPanel then ns.SettingsPanel:Open() end
  end)

  self.frame = f
  return f
end

-- 取一行帧（复用池）。每单元格固定宽 + 关闭换行，超宽自动裁剪，保证列对齐。
local function acquireRow(content, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, content)
  row:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", col.x, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    row.cells[col.key] = fs
  end
  rows[i] = row
  return row
end

function Overview:Refresh()
  local f = self.frame
  if not f then return end
  local Store = ns.Store

  -- 战团银行金币。
  local warband, warbandAt = Store:GetWarbandMoney()
  if warband then
    f.warbandLine:SetText(string.format(
      "战团银行金币: %s  |cff808080(更新于 %s)|r",
      Utils.FormatMoney(warband), Utils.AgoText(warbandAt)))
  else
    f.warbandLine:SetText("战团银行金币: |cff808080未采集（登录后打开一次银行）|r")
  end

  local chars = Store:GetCharacters()
  for i, rec in ipairs(chars) do
    local row = acquireRow(f.content, f.rows, i)
    local stale = Store:IsWeeklyStale(rec.updatedAt)
    local staleMark = stale and " |cffff5555*|r" or ""

    local name = Utils.ShortName(rec.name)
    row.cells.name:SetText(Utils.ColorText(classColor(rec), (name or "?")))
    row.cells.money:SetText(Utils.FormatMoney(rec.money or 0))
    row.cells.mythic:SetText(Store:MythicText(rec) .. staleMark)
    row.cells.key:SetText(Store:KeystoneText(rec))
    row.cells.raid:SetText(Store:RaidText(rec))
    row.cells.vault:SetText(Store:VaultText(rec))
    row.cells.weekly:SetText(Store:WeeklyQuestText(rec))
    row.cells.update:SetText("|cff808080" .. Utils.AgoText(rec.updatedAt) .. "|r")
    row.cells.cur:SetText(currencyText(rec))
    row:Show()
  end
  -- 隐藏多余的复用行。
  for i = #chars + 1, #f.rows do
    f.rows[i]:Hide()
  end
  f.content:SetHeight(math.max(10, #chars * ROW_HEIGHT))

  -- 金币合计追加到战团行后。
  if ns.Config:Get("profile.showGoldTotal") then
    local total = Store:GetGoldTotal()
    f.warbandLine:SetText(f.warbandLine:GetText() ..
      "    |cffffd100角色金币合计:|r " .. Utils.FormatMoney(total))
  end
end

function Overview:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then
    f:Hide()
  else
    ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
    self:Refresh()
    f:Show()
  end
end

function Overview:Show()
  local f = self:_ensureFrame()
  ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
  self:Refresh()
  f:Show()
end
