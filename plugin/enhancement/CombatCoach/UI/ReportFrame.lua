local addonName, ns = ...

local Report = {}
ns.ReportFrame = ns.Core:RegisterModule("ReportFrame", Report)

local Utils = ns.Utils
local Const = ns.Constants

local FRAME_WIDTH = 420
local FRAME_HEIGHT = 380
local LINE_H = 16

function Report:Init()
  -- 懒创建，首次展示时才建帧。
end

local function roleLabel(role)
  return ({
    [Const.ROLE.TANK] = "坦克",
    [Const.ROLE.HEALER] = "治疗",
    [Const.ROLE.DAMAGER] = "输出",
  })[role] or "未知"
end

-- 顶部主指标一行：按角色选最相关的核心数值。只用一定存在的可观测指标。
local function headlineText(report)
  local m = report.metrics or {}
  if report.role == Const.ROLE.HEALER then
    return string.format("HPS %s   过量 %s   %s",
      Utils.Short(m.hps or 0), Utils.Pct(m.overhealPct or 0), roleLabel(report.role))
  elseif report.role == Const.ROLE.TANK then
    return string.format("DTPS %s   DPS %s   %s",
      Utils.Short(m.dtps or 0), Utils.Short(m.dps or 0), roleLabel(report.role))
  else
    return string.format("DPS %s   %s",
      Utils.Short(m.dps or 0), roleLabel(report.role))
  end
end

function Report:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "CombatCoachReport", UIParent, "BackdropTemplate")
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
  title:SetText(Const.ADDON_TITLE .. " 分析")
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 主指标大字。
  local headline = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  headline:SetPoint("TOPLEFT", 14, -38)
  headline:SetJustifyH("LEFT")
  f.headline = headline

  -- 副信息（对象/时长/结果）。
  local sub = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", 14, -58)
  sub:SetJustifyH("LEFT")
  f.sub = sub

  -- 分隔标题。
  local secTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  secTitle:SetPoint("TOPLEFT", 14, -78)
  secTitle:SetText("|cffffd100改进点|r")
  f.secTitle = secTitle

  -- 滚动区容纳改进点行。
  local scroll = CreateFrame("ScrollFrame", "CombatCoachReportScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -98)
  scroll:SetPoint("BOTTOMRIGHT", -30, 40)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(FRAME_WIDTH - 46, 10)
  scroll:SetScrollChild(content)
  f.scroll = scroll
  f.content = content
  f.rows = {}

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 12)
  hint:SetText("仅分析日志范围内的自己，非团队排名。")

  self.frame = f
  return f
end

-- 取一行（复用池）。每行一个可换行的 FontString。
local function acquireRow(content, rows, i)
  local row = rows[i]
  if row then return row end
  row = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row:SetPoint("TOPLEFT", 2, -(i - 1) * (LINE_H * 2 + 4))
  row:SetWidth(FRAME_WIDTH - 56)
  row:SetJustifyH("LEFT")
  rows[i] = row
  return row
end

function Report:Render(report)
  local f = self:_ensureFrame()
  if not report then
    f.headline:SetText("暂无战斗数据")
    f.sub:SetText("")
    for _, row in ipairs(f.rows) do row:Hide() end
    f.content:SetHeight(10)
    return
  end

  f.headline:SetText(headlineText(report))

  local who = report.bossName or (report.source == Const.SEGMENT_SOURCE.ENCOUNTER
    and "首领战" or "普通战斗")
  local result = ""
  if report.kill == true then result = " · |cff40ff40击杀|r"
  elseif report.kill == false then result = " · |cffff5555团灭/失败|r" end
  f.sub:SetText(string.format("%s · 时长 %s · %s%s",
    who, Utils.Duration(report.duration or 0),
    report.className or "?", result))

  local sugs = report.suggestions or {}
  local y = 0

  -- 零采集自检优先提示：避免用户把"采集异常"误当成"分析说我啥也没做"。
  if report.zeroCollected then
    local row = acquireRow(f.content, f.rows, 1)
    row:SetText("|cffff5555本段未采集到你的任何伤害/治疗，可能异常。输入 /cc debug 查看。|r")
    row:Show()
    y = 1
  elseif #sugs == 0 then
    local row = acquireRow(f.content, f.rows, 1)
    row:SetText("|cff40ff40没有发现明显问题，保持！|r")
    row:Show()
    y = 1
  else
    for i, s in ipairs(sugs) do
      local row = acquireRow(f.content, f.rows, i)
      local color = Const.SEVERITY_COLOR[s.severity or 1] or "ffffffff"
      local bullet = Utils.ColorText(color, "● ")
      row:SetText(bullet .. Utils.ColorText(color, s.text or ""))
      row:Show()
      y = i
    end
  end

  -- 本段实测占比：治疗看治疗构成，其余看输出构成。名字与数值都来自实战日志，
  -- 永远是当前赛季实时数据，也是"如实呈现"的核心。
  local m = report.metrics or {}
  local top = (report.role == Const.ROLE.HEALER) and m.topHeal or m.topDamage
  local topLabel = (report.role == Const.ROLE.HEALER) and "本段治疗占比" or "本段输出占比"
  if type(top) == "table" and #top > 0 then
    y = y + 1
    local head = acquireRow(f.content, f.rows, y)
    head:SetText("|cffffd100" .. topLabel .. "|r")
    head:Show()
    for _, e in ipairs(top) do
      y = y + 1
      local row = acquireRow(f.content, f.rows, y)
      row:SetText(string.format("%s  |cff40ff40%s|r  |cff808080(%s)|r",
        e.name or ("法术#" .. tostring(e.spellId)),
        Utils.Pct(e.pct or 0, 1),
        Utils.Short(e.amount or 0)))
      row:Show()
    end
  end

  for i = y + 1, #f.rows do f.rows[i]:Hide() end
  f.content:SetHeight(math.max(10, y * (LINE_H * 2 + 4)))
end

-- 由计量窗口的「分析」按钮调用：渲染指定段的分析并显示。
function Report:ShowReport(report)
  self:Render(report)
  self.frame:Show()
end

function Report:Hide()
  if self.frame then self.frame:Hide() end
end
