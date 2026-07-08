local addonName, ns = ...

local Meter = {}
ns.MeterFrame = ns.Core:RegisterModule("MeterFrame", Meter)

local Utils = ns.Utils
local Const = ns.Constants
local Div = Utils.Div

local FRAME_WIDTH = 320
local FRAME_HEIGHT = 340
local ROW_H = 18
local MAX_ROWS = 12
local REFRESH_INTERVAL = 0.5

-- 展示视图：当前战斗 / 总计 / 历史某场。用一个游标描述当前看的是哪个。
-- view = { kind = "current"|"overall"|"history", index = <n> }
Meter.view = { kind = "current" }

-- 数据口径：伤害 or 治疗。默认伤害，可切换。
Meter.mode = "damage"

function Meter:Init()
  -- 懒创建，首次打开时才建帧。
end

-- 取当前视图对应的段对象。
local function resolveSegment(view)
  local S = ns.Segment
  if view.kind == "overall" then return S.overall end
  if view.kind == "history" then return S.history[view.index or 1] end
  -- current：优先进行中的段，否则回退最近一场历史，避免脱战后一片空白。
  return S.current or S.history[1]
end

-- 段标题文本。
local function segmentTitle(seg, view)
  if not seg then return "（无数据）" end
  if view.kind == "overall" then return "总计" end
  local who = seg.bossName
    or (seg.source == Const.SEGMENT_SOURCE.ENCOUNTER and "首领战" or "战斗")
  return who
end

-- 从段里取"按口径排序的技能条目"与合计。返回 list（降序）, total。
local function buildRows(seg, mode)
  if not seg then return {}, 0 end
  local src = (mode == "heal") and seg.healBySpell or seg.dmgBySpell
  local total = (mode == "heal") and seg.healDone or seg.damageDone
  local list = {}
  for spellId, b in pairs(src) do
    list[#list + 1] = { spellId = spellId, name = b.name, amount = b.amount }
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  return list, total
end

function Meter:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "CombatCoachMeter", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText(Const.ADDON_TITLE)
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() Meter:Toggle() end)

  -- 主指标行（实时 DPS/HPS + 时长）。
  local headline = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headline:SetPoint("TOPLEFT", 12, -28)
  headline:SetJustifyH("LEFT")
  f.headline = headline

  -- 段名 + 提示行。
  local subline = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  subline:SetPoint("TOPLEFT", 12, -44)
  subline:SetJustifyH("LEFT")
  f.subline = subline

  -- 顶部按钮：伤害/治疗切换、分段切换、分析。
  local dmgBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  dmgBtn:SetSize(52, 20)
  dmgBtn:SetPoint("TOPLEFT", 12, -62)
  dmgBtn:SetText("伤害")
  dmgBtn:SetScript("OnClick", function() Meter:SetMode("damage") end)
  f.dmgBtn = dmgBtn

  local healBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  healBtn:SetSize(52, 20)
  healBtn:SetPoint("LEFT", dmgBtn, "RIGHT", 2, 0)
  healBtn:SetText("治疗")
  healBtn:SetScript("OnClick", function() Meter:SetMode("heal") end)
  f.healBtn = healBtn

  local segBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  segBtn:SetSize(64, 20)
  segBtn:SetPoint("LEFT", healBtn, "RIGHT", 2, 0)
  segBtn:SetText("分段▾")
  segBtn:SetScript("OnClick", function() Meter:CycleSegment() end)
  f.segBtn = segBtn

  local anaBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  anaBtn:SetSize(52, 20)
  anaBtn:SetPoint("LEFT", segBtn, "RIGHT", 2, 0)
  anaBtn:SetText("分析")
  anaBtn:SetScript("OnClick", function() Meter:AnalyzeCurrent() end)
  f.anaBtn = anaBtn

  -- 技能条区域（行池）。
  local rowHost = CreateFrame("Frame", nil, f)
  rowHost:SetPoint("TOPLEFT", 12, -88)
  rowHost:SetPoint("BOTTOMRIGHT", -12, 30)
  f.rowHost = rowHost
  f.rows = {}

  -- 底部提示。
  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 10)
  hint:SetText("窗口开启即采集，关闭即停止。")
  f.hint = hint

  self.frame = f
  return f
end

-- 取/建一行（技能条：名称 + 数值 + 占比背景条）。
local function acquireRow(host, rows, i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, host)
  row:SetSize(FRAME_WIDTH - 24, ROW_H - 2)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

  local bar = row:CreateTexture(nil, "BACKGROUND")
  bar:SetPoint("LEFT")
  bar:SetHeight(ROW_H - 2)
  bar:SetColorTexture(0.2, 0.4, 0.8, 0.5)
  row.bar = bar

  local left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  left:SetPoint("LEFT", 4, 0)
  left:SetJustifyH("LEFT")
  row.left = left

  local right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  right:SetPoint("RIGHT", -4, 0)
  right:SetJustifyH("RIGHT")
  row.right = right

  rows[i] = row
  return row
end

function Meter:Refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end

  local seg = resolveSegment(self.view)
  local dur = ns.Segment:LiveDuration(seg)

  -- 主指标：按口径显示 DPS 或 HPS。
  if seg then
    local perf, label
    if self.mode == "heal" then
      perf = Utils.Short(Div(seg.healDone, dur)); label = "HPS"
    else
      perf = Utils.Short(Div(seg.damageDone, dur)); label = "DPS"
    end
    f.headline:SetText(string.format("%s %s   时长 %s", label, perf, Utils.Duration(dur)))
  else
    f.headline:SetText("等待战斗数据…")
  end

  -- 段名 + 自检提示。
  local sub = segmentTitle(seg, self.view)
  if seg and seg.zeroCollected then
    sub = sub .. "  |cffff5555⚠ 本段未采集到你的任何伤害/治疗，可能异常，/cc debug|r"
  elseif not ns.Segment:IsRecording() then
    sub = sub .. "  |cff808080(未采集)|r"
  end
  f.subline:SetText(sub)

  -- 技能条。
  local list, total = buildRows(seg, self.mode)
  local maxAmount = list[1] and list[1].amount or 0
  local shown = math.min(#list, MAX_ROWS)
  for i = 1, shown do
    local e = list[i]
    local row = acquireRow(f.rowHost, f.rows, i)
    local pct = Div(e.amount, total)
    local frac = Div(e.amount, maxAmount)
    local w = math.max(1, (FRAME_WIDTH - 24) * frac)
    row.bar:SetWidth(w)
    row.left:SetText(string.format("%d. %s", i, e.name or ("#" .. tostring(e.spellId))))
    row.right:SetText(string.format("%s  %s", Utils.Short(e.amount), Utils.Pct(pct, 0)))
    row:Show()
  end
  for i = shown + 1, #f.rows do f.rows[i]:Hide() end

  if shown == 0 then
    -- 没有任何条目时给一句占位，避免"空白像坏了"。
    local row = acquireRow(f.rowHost, f.rows, 1)
    row.bar:SetWidth(1)
    row.left:SetText(ns.Segment:IsRecording() and "|cff808080开打后这里实时显示技能占比…|r" or "|cff808080已停止采集|r")
    row.right:SetText("")
    row:Show()
  end
end

-- 定时刷新驱动。
local function onUpdate(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < REFRESH_INTERVAL then return end
  self._acc = 0
  ns.Core:SafeCall(function() Meter:Refresh() end)
end

function Meter:SetMode(mode)
  self.mode = (mode == "heal") and "heal" or "damage"
  self:Refresh()
end

-- 在 当前战斗 → 总计 → 历史各场 之间循环。
function Meter:CycleSegment()
  local v = self.view
  local histN = #ns.Segment.history
  if v.kind == "current" then
    self.view = { kind = "overall" }
  elseif v.kind == "overall" then
    if histN > 0 then self.view = { kind = "history", index = 1 }
    else self.view = { kind = "current" } end
  elseif v.kind == "history" then
    if (v.index or 1) < histN then
      self.view = { kind = "history", index = (v.index or 1) + 1 }
    else
      self.view = { kind = "current" }
    end
  end
  self:Refresh()
end

-- 段结束时被 CombatLog 调用：若当前正看"当前战斗"，刷新以显示收尾结果。
function Meter:OnSegmentEnd()
  if self.frame and self.frame:IsShown() then self:Refresh() end
end

-- 分析当前查看的段：交给 Analyzer，结果在分析视图（ReportFrame）展示。
function Meter:AnalyzeCurrent()
  local seg = resolveSegment(self.view)
  if not seg then
    Utils.Print("当前没有可分析的战斗数据。")
    return
  end
  local dur = ns.Segment:LiveDuration(seg)
  local report = ns.Metrics:Build(seg, dur)
  if not report then
    Utils.Print("数据不足，无法分析。")
    return
  end
  report.suggestions = ns.Analyzer:Analyze(report)
  if ns.ReportFrame then ns.ReportFrame:ShowReport(report) end
end

function Meter:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then
    f:Hide()
    f:SetScript("OnUpdate", nil)
    ns.CombatLog:SetRecording(false)
  else
    ns.CombatLog:SetRecording(true)
    self.view = { kind = "current" }
    f:SetScript("OnUpdate", onUpdate)
    f:Show()
    self:Refresh()
  end
end

function Meter:IsShown()
  return self.frame and self.frame:IsShown()
end
