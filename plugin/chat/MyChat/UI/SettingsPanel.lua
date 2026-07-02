local addonName, ns = ...

local SettingsPanel = {}
ns.SettingsPanel = ns.Core:RegisterModule("SettingsPanel", SettingsPanel)

local C = ns.Constants

-- Checkbox definitions: config path + label. Order controls layout.
local TOGGLES = {
  { path = "profile.showTimestamps", label = "显示时间戳" },
  { path = "profile.abbreviateChannels", label = "频道缩写" },
  { path = "profile.colorPlayerNamesByClass", label = "玩家名职业色" },
  { path = "profile.highlightSelfName", label = "高亮自己的名字" },
  { path = "profile.enableWhisperIndex", label = "记录最近密语" },
  { path = "profile.enableRepeatCollapse", label = "折叠重复消息" },
  { path = "profile.routeWorldTradeParty", label = "世界/交易/队伍分流" },
  { path = "profile.mirrorPanelEnabled", label = "启用镜像面板" },
  { path = "profile.channelBarEnabled", label = "启用频道切换条" },
  { path = "profile.safeMode", label = "安全模式（仅只读增强）" },
}

local function get(path) return ns.Config and ns.Config:Get(path) end
local function set(path, v) if ns.Config then ns.Config:Set(path, v) end end

function SettingsPanel:Init()
  local frame = CreateFrame("Frame")
  frame.name = C.ADDON_TITLE

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(C.ADDON_TITLE .. "  v" .. C.VERSION)

  local anchor = title
  self.checks = {}
  for _, def in ipairs(TOGGLES) do
    local cb = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    cb.Text:SetText(def.label)
    cb:SetChecked(get(def.path) and true or false)
    cb:SetScript("OnClick", function(self)
      local checked = self:GetChecked() and true or false
      set(def.path, checked)
      -- Toggling a panel/bar touches frame structure -> apply via guard.
      if def.path == "profile.mirrorPanelEnabled" then
        local mp = ns.MirrorPanel
        if mp and mp.ApplyVisibility then mp:ApplyVisibility() end
      elseif def.path == "profile.channelBarEnabled" then
        local cbar = ns.ChannelBar
        if cbar and cbar.ApplyVisibility then cbar:ApplyVisibility() end
      end
    end)
    self.checks[def.path] = cb
    anchor = cb
  end

  self.frame = frame
  self:_register(frame)
end

-- Support both the modern Settings API and the legacy panel registration.
function SettingsPanel:_register(frame)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
    category.ID = frame.name
    Settings.RegisterAddOnCategory(category)
    self.category = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(frame)
  end
end

-- Refresh checkbox states from config (e.g. after /mychat reset).
function SettingsPanel:Refresh()
  if not self.checks then return end
  for path, cb in pairs(self.checks) do
    cb:SetChecked(get(path) and true or false)
  end
end

function SettingsPanel:Open()
  self:Refresh()
  if Settings and Settings.OpenToCategory and self.category then
    Settings.OpenToCategory(self.category.ID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(self.frame)
    InterfaceOptionsFrame_OpenToCategory(self.frame)
  end
end
