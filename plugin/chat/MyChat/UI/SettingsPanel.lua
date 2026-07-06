local addonName, ns = ...

local SettingsPanel = {}
ns.SettingsPanel = ns.Core:RegisterModule("SettingsPanel", SettingsPanel)

local C = ns.Constants

local function get(path) return ns.Config and ns.Config:Get(path) end
local function set(path, v) if ns.Config then ns.Config:Set(path, v) end end

-- After a setting changes, some modules must re-apply it immediately so the
-- user sees the effect without /reload.
local function applySideEffect(path)
  if path == "profile.mirrorPanelEnabled" or path == "profile.mirrorSystemMessages" then
    local mp = ns.MirrorPanel
    if mp and mp.ApplyVisibility then mp:ApplyVisibility() end
  elseif path == "profile.channelBarEnabled" then
    local cbar = ns.ChannelBar
    if cbar and cbar.ApplyVisibility then cbar:ApplyVisibility() end
  elseif path == "profile.abbreviateChannels"
      or path == "profile.channelBarAbbrevChars"
      or path == "profile.channelBarShowNumber"
      or path == "profile.channelAbbrevMap"
      or path == "profile.channelBarShowSay"
      or path == "profile.channelBarShowParty"
      or path == "profile.channelBarShowRaid"
      or path == "profile.channelBarShowGuild" then
    local cbar = ns.ChannelBar
    if cbar and cbar.Rebuild and cbar.frame then cbar:Rebuild() end
  end
end

-- Panel layout: ordered list of sections; each section has a title and a list
-- of controls. Control kinds: "check" (bool), "number" (numeric edit box),
-- "list" (comma-separated string list edit box).
local SECTIONS = {
  {
    title = "频道切换条",
    controls = {
      { kind = "check",  path = "profile.channelBarEnabled",   label = "启用频道切换条" },
      { kind = "check",  path = "profile.channelBarShowSay",   label = "显示「说」按钮" },
      { kind = "check",  path = "profile.channelBarShowParty", label = "显示「队」按钮" },
      { kind = "check",  path = "profile.channelBarShowRaid",  label = "显示「团」按钮" },
      { kind = "check",  path = "profile.channelBarShowGuild", label = "显示「会」按钮" },
      { kind = "check",  path = "profile.channelBarShowNumber", label = "频道按钮带编号前缀（如 6大脚）" },
      { kind = "check",  path = "profile.abbreviateChannels",  label = "频道按钮用短名（截取前几字）" },
      { kind = "number", path = "profile.channelBarAbbrevChars", label = "短名取字符数", min = 1, max = 8 },
      { kind = "map",    path = "profile.channelAbbrevMap", label = "频道短名映射（每行：频道名=显示名）" },
    },
  },
  {
    title = "高亮与关键词",
    controls = {
      { kind = "check", path = "profile.highlightSelfName", label = "高亮自己的名字" },
      { kind = "list",  path = "profile.highlightKeywords", label = "高亮关键词（逗号分隔）" },
    },
  },
  {
    title = "重复折叠",
    controls = {
      { kind = "check",  path = "profile.enableRepeatCollapse", label = "折叠短时间内的重复消息" },
      { kind = "number", path = "profile.dupWindowSeconds", label = "重复判定时间窗口（秒）", min = 1, max = 60 },
    },
  },
  {
    title = "密语",
    controls = {
      { kind = "check",  path = "profile.enableWhisperIndex", label = "记录最近密语对象" },
      { kind = "number", path = "profile.whisperHistoryLimit", label = "记住最近密语人数", min = 1, max = 50 },
    },
  },
  {
    title = "自动加入频道",
    controls = {
      { kind = "list", path = "profile.autoJoinChannels", label = "登录后自动加入（逗号分隔频道名）" },
    },
  },
  {
    title = "镜像面板",
    controls = {
      { kind = "check",  path = "profile.mirrorPanelEnabled",   label = "启用镜像面板" },
      { kind = "check",  path = "profile.mirrorSystemMessages", label = "镜像系统消息（默认关，避免噪音）" },
      { kind = "check",  path = "profile.routeWorldTradeParty", label = "按频道分色显示" },
      { kind = "number", path = "profile.mirrorMaxLines", label = "最多保留行数", min = 20, max = 500 },
    },
  },
  {
    title = "高级",
    controls = {
      { kind = "check", path = "profile.safeMode", label = "安全模式（仅只读增强，禁用自动加频道/密语发送）" },
    },
  },
}

-- Convert a stored value <-> a comma-separated display string for list edits.
local function listToText(v)
  if type(v) ~= "table" then return "" end
  return table.concat(v, ", ")
end

local function textToList(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for token in s:gmatch("[^,]+") do
    local t = token:gsub("^%s+", ""):gsub("%s+$", "")
    if t ~= "" then out[#out + 1] = t end
  end
  return out
end

-- Convert a { [key]=val } map <-> multi-line "key=val" text for map edits.
local function mapToText(v)
  if type(v) ~= "table" then return "" end
  local lines = {}
  for k, val in pairs(v) do
    lines[#lines + 1] = tostring(k) .. "=" .. tostring(val)
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

local function textToMap(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for line in s:gmatch("[^\n]+") do
    local k, val = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
    if k and k ~= "" and val and val ~= "" then
      out[k] = val
    end
  end
  return out
end

function SettingsPanel:Init()
  -- Outer frame registered with the Settings category; a scroll frame holds
  -- the actual controls so long lists never overflow the panel.
  local frame = CreateFrame("Frame")
  frame.name = C.ADDON_TITLE

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(C.ADDON_TITLE .. "  v" .. C.VERSION)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 16)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  self.controls = {}
  self:_buildControls(content)

  self.frame = frame
  self.content = content
  self:_register(frame)
end

-- Build every section + control into the scroll content frame.
function SettingsPanel:_buildControls(content)
  local y = -4
  local INDENT = 8

  for _, section in ipairs(SECTIONS) do
    local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", INDENT, y)
    header:SetText("|cffffd200" .. section.title .. "|r")
    y = y - 22

    for _, def in ipairs(section.controls) do
      y = self:_buildControl(content, def, INDENT + 8, y)
    end
    y = y - 10  -- gap between sections
  end

  content:SetHeight(-y + 8)
  content:SetWidth(560)
end

-- Build a single control at (x, y); returns the new y after it.
function SettingsPanel:_buildControl(content, def, x, y)
  if def.kind == "check" then
    local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetText(def.label)
    cb:SetChecked(get(def.path) and true or false)
    cb:SetScript("OnClick", function(self)
      local checked = self:GetChecked() and true or false
      set(def.path, checked)
      applySideEffect(def.path)
    end)
    self.controls[def.path] = { kind = "check", widget = cb }
    return y - 26
  end

  if def.kind == "number" then
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 4)
    label:SetText(def.label)

    local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    eb:SetSize(50, 20)
    eb:SetPoint("LEFT", label, "RIGHT", 12, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(4)
    eb:SetText(tostring(get(def.path) or ""))
    local commit = function(self)
      local n = tonumber(self:GetText())
      if n then
        if def.min and n < def.min then n = def.min end
        if def.max and n > def.max then n = def.max end
        set(def.path, n)
        self:SetText(tostring(n))
        applySideEffect(def.path)
      else
        self:SetText(tostring(get(def.path) or ""))
      end
      self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", commit)
    -- Also commit when the box loses focus (clicking elsewhere / closing the
    -- panel), so a typed value isn't silently discarded when Enter isn't hit.
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self)
      self:SetText(tostring(get(def.path) or ""))
      self:ClearFocus()
    end)
    self.controls[def.path] = { kind = "number", widget = eb, def = def }
    return y - 28
  end

  if def.kind == "list" then
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 4)
    label:SetText(def.label)

    local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    eb:SetSize(360, 20)
    eb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    eb:SetAutoFocus(false)
    eb:SetText(listToText(get(def.path)))
    local commit = function(self)
      set(def.path, textToList(self:GetText()))
      self:SetText(listToText(get(def.path)))
      self:ClearFocus()
      applySideEffect(def.path)
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self)
      self:SetText(listToText(get(def.path)))
      self:ClearFocus()
    end)
    self.controls[def.path] = { kind = "list", widget = eb }
    return y - 48
  end

  if def.kind == "map" then
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 4)
    label:SetText(def.label)

    -- Multi-line edit box inside a small scroll frame; one "频道名=显示名" per line.
    local box = CreateFrame("ScrollFrame", nil, content, "InputScrollFrameTemplate")
    box:SetSize(360, 70)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    local eb = box.EditBox
    eb:SetWidth(340)
    eb:SetMaxLetters(0)
    if box.CharCount then box.CharCount:Hide() end
    eb:SetText(mapToText(get(def.path)))
    local commit = function(self)
      set(def.path, textToMap(self:GetText()))
      self:SetText(mapToText(get(def.path)))
      self:ClearFocus()
      applySideEffect(def.path)
    end
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self)
      self:SetText(mapToText(get(def.path)))
      self:ClearFocus()
    end)
    self.controls[def.path] = { kind = "map", widget = eb }
    return y - 90
  end

  return y
end

-- Register the panel with the modern Settings API (12.0). Store the numeric
-- category id for OpenToCategory.
function SettingsPanel:_register(frame)
  local ok, err = pcall(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
      local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
      self.category = category
      self.categoryID = (category.GetID and category:GetID()) or category.ID or frame.name
      Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(frame)
    end
  end)
  self.registered = ok
  if not ok then
    local diag = ns.Core:GetModule("Diagnostics")
    if diag and diag.Error then diag:Error("SettingsPanel", err) end
  end
end

-- Refresh every control's displayed value from config (e.g. after reset).
function SettingsPanel:Refresh()
  if not self.controls then return end
  for path, ctl in pairs(self.controls) do
    if ctl.kind == "check" then
      ctl.widget:SetChecked(get(path) and true or false)
    elseif ctl.kind == "number" then
      ctl.widget:SetText(tostring(get(path) or ""))
    elseif ctl.kind == "list" then
      ctl.widget:SetText(listToText(get(path)))
    elseif ctl.kind == "map" then
      ctl.widget:SetText(mapToText(get(path)))
    end
  end
end

-- Returns true if the settings window was opened, false otherwise.
function SettingsPanel:Open()
  self:Refresh()
  local opened = false
  pcall(function()
    if Settings and Settings.OpenToCategory and self.categoryID then
      Settings.OpenToCategory(self.categoryID)
      opened = true
    elseif Settings and Settings.OpenToCategory and self.category then
      Settings.OpenToCategory(self.category)
      opened = true
    end
  end)
  return opened
end
