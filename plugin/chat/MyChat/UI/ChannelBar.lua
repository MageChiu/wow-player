local addonName, ns = ...

local ChannelBar = {}
ns.ChannelBar = ns.Core:RegisterModule("ChannelBar", ChannelBar)

local C = ns.Constants

-- Button definitions. chatType maps to the native edit box attribute.
-- available() decides whether the button is clickable in the current context.
-- world is a numbered channel, so it needs a channel index resolved at click.
local BUTTONS = {
  { key = "say",     label = "说",   chatType = "SAY",   color = "ffffffff", available = function() return true end },
  { key = "party",   label = "小队", chatType = "PARTY", color = "ffaaaaff", available = function() return IsInGroup() end },
  { key = "raid",    label = "团队", chatType = "RAID",  color = "ffff7f3f", available = function() return IsInRaid() end },
  { key = "guild",   label = "公会", chatType = "GUILD", color = "ff40ff40", available = function() return IsInGuild() end },
  { key = "world",   label = "世界", chatType = "WORLD", color = "ff40c0f0", available = function() return ChannelBar:_worldChannelId() ~= nil end },
  { key = "whisper", label = "密语", chatType = "WHISPER", color = "fff080f0", available = function()
      return ns.WhisperIndex ~= nil and ns.WhisperIndex:GetLastTarget() ~= nil
    end },
}

local BUTTON_WIDTH = 46
local BUTTON_HEIGHT = 20
local BUTTON_GAP = 2
local PADDING = 6

function ChannelBar:Init()
  -- Re-evaluate button availability when group/guild state changes.
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
  watcher:RegisterEvent("PLAYER_GUILD_UPDATE")
  watcher:RegisterEvent("CHANNEL_UI_UPDATE")
  watcher:SetScript("OnEvent", function()
    ns.Core:SafeCall(function() ChannelBar:RefreshButtons() end)
  end)
  self.watcher = watcher

  self:ApplyVisibility()
end

-- Resolve the first joined channel that classifies as world, so the world
-- button targets an actual numbered channel. Returns id, name or nil.
function ChannelBar:_worldChannelId()
  local Parser = ns.Parser
  if not Parser then return nil end
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    if type(id) == "number" and type(name) == "string" then
      local _, class = Parser:ClassifyChannel("CHAT_MSG_CHANNEL", name)
      if class == C.CLASS.WORLD then
        return id, name
      end
    end
  end
  return nil
end

function ChannelBar:_ensureFrame()
  if self.frame then return self.frame end

  local width = PADDING * 2 + (#BUTTONS * BUTTON_WIDTH) + (#BUTTONS - 1) * BUTTON_GAP
  local f = CreateFrame("Frame", "MyChatChannelBar", UIParent, "BackdropTemplate")
  f:SetSize(width, BUTTON_HEIGHT + PADDING * 2)
  -- Default anchor: just above the primary chat frame's edit box area.
  f:SetPoint("BOTTOMLEFT", ChatFrame1 or UIParent, "TOPLEFT", 0, 4)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
  end

  self.buttons = {}
  local x = PADDING
  for _, def in ipairs(BUTTONS) do
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetPoint("LEFT", f, "LEFT", x, 0)
    btn:SetText(def.label)
    btn:SetScript("OnClick", function()
      ns.Core:SafeCall(function() ChannelBar:_activate(def) end)
    end)
    self.buttons[def.key] = { frame = btn, def = def }
    x = x + BUTTON_WIDTH + BUTTON_GAP
  end

  self.frame = f
  self:RefreshButtons()
  return f
end

-- Open the native chat edit box on the target channel. We only set the input
-- context; the player types and presses Enter to send (no taint, no misfire).
function ChannelBar:_activate(def)
  local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or ChatEdit_GetActiveWindow()
  if not editBox then
    editBox = ChatEdit_GetLastActiveWindow and ChatEdit_GetLastActiveWindow()
  end
  if not editBox then return end

  if def.chatType == "WORLD" then
    local id = self:_worldChannelId()
    if not id then return end
    editBox:SetAttribute("chatType", "CHANNEL")
    editBox:SetAttribute("channelTarget", id)
  elseif def.chatType == "WHISPER" then
    local target = ns.WhisperIndex and ns.WhisperIndex:GetLastTarget()
    if not target then return end
    editBox:SetAttribute("chatType", "WHISPER")
    editBox:SetAttribute("tellTarget", target)
  else
    editBox:SetAttribute("chatType", def.chatType)
  end

  ChatEdit_UpdateHeader(editBox)
  editBox:Show()
  editBox:SetFocus()
end

-- Enable/disable buttons based on current context. Never hides them so the
-- layout stays stable; disabled buttons are greyed out.
function ChannelBar:RefreshButtons()
  if not self.buttons then return end
  for _, entry in pairs(self.buttons) do
    local ok = false
    ns.Core:SafeCall(function() ok = entry.def.available() and true or false end)
    if ok then entry.frame:Enable() else entry.frame:Disable() end
  end
end

-- Show/hide per config; frame creation and toggling go through CombatGuard
-- because they touch frame structure.
function ChannelBar:ApplyVisibility()
  local enabled = ns.Config and ns.Config:Get("profile.channelBarEnabled")
  if not enabled and not self.frame then return end
  local guard = ns.CombatGuard
  local apply = function()
    local f = self:_ensureFrame()
    if enabled then
      f:Show()
      self:RefreshButtons()
    else
      f:Hide()
    end
  end
  if guard then guard:Run(apply) else ns.Core:SafeCall(apply) end
end

function ChannelBar:Toggle()
  if not ns.Config then return end
  local now = ns.Config:Get("profile.channelBarEnabled")
  ns.Config:Set("profile.channelBarEnabled", not now)
  self:ApplyVisibility()
end
