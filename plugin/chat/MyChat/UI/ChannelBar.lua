local addonName, ns = ...

local ChannelBar = {}
ns.ChannelBar = ns.Core:RegisterModule("ChannelBar", ChannelBar)

-- Fixed base targets (whisper removed — it is not a channel). Each carries the
-- config key that controls whether its button is shown.
local BASE_BUTTONS = {
  { key = "say",   label = "说", chatType = "SAY",   show = "profile.channelBarShowSay",   available = function() return true end },
  { key = "party", label = "队", chatType = "PARTY", show = "profile.channelBarShowParty", available = function() return IsInGroup() end },
  { key = "raid",  label = "团", chatType = "RAID",  show = "profile.channelBarShowRaid",  available = function() return IsInRaid() end },
  { key = "guild", label = "会", chatType = "GUILD", show = "profile.channelBarShowGuild", available = function() return IsInGuild() end },
}

local BUTTON_HEIGHT = 20
local BUTTON_MIN_WIDTH = 22
local BUTTON_PAD_X = 10       -- extra width added around the label text
local BUTTON_GAP = 2
local ROW_GAP = 2
local PADDING = 6
local MAX_ROW_WIDTH = 420     -- wrap to a new row past this width

-- Default number of leading characters used as a channel's short label.
-- Overridden per-config by "channelBarAbbrevChars".
local ABBREV_CHARS = 3

local function abbrevChars()
  local n = tonumber(ns.Config and ns.Config:Get("profile.channelBarAbbrevChars"))
  if n and n >= 1 then return math.floor(n) end
  return ABBREV_CHARS
end

-- Community/Club channels come back from GetChannelList as an internal routing
-- token, e.g. "Community:876127095:1" (Community:<clubId>:<streamId>), NOT a
-- human name. Blizzard's own chat resolves these with the global
-- ChatFrame_ResolveChannelName, which returns the community's short NAME (for
-- the General stream it returns just the community name, e.g. "漫天星辰"; for
-- sub-streams "社区名 - 子频道名"). That is what the native chat + other bars
-- show, so we use it too. We fall back to C_Club (club name, NOT stream name)
-- and finally a "社区" placeholder when nothing resolves yet.
local function communityName(name)
  if type(name) ~= "string" then return nil end
  local clubId = name:match("^Community:(%d+):%d+$")
  if not clubId then return nil end

  -- Preferred: Blizzard's resolver. Non-community input is returned as-is and
  -- an unfound community yields " - ", so guard against those.
  if type(ChatFrame_ResolveChannelName) == "function" then
    local ok, resolved = pcall(ChatFrame_ResolveChannelName, name)
    if ok and type(resolved) == "string" then
      resolved = resolved:gsub("^%s+", ""):gsub("%s+$", "")
      -- Reject the "not found" sentinel (" - ") and any leftover raw token.
      if resolved ~= "" and resolved ~= "-" and not resolved:find("^Community:") then
        return resolved
      end
    end
  end

  -- Fallback: the club's own name (never the stream name — that would show
  -- "综合" instead of the community name).
  if C_Club then
    local ok, clubInfo = pcall(C_Club.GetClubInfo, clubId)
    if ok and type(clubInfo) == "table" then
      if clubInfo.shortName and clubInfo.shortName ~= "" then return clubInfo.shortName end
      if clubInfo.name and clubInfo.name ~= "" then return clubInfo.name end
    end
  end

  return "社区"  -- placeholder until club data is available
end

-- Strip a channel's trailing " - <city/zone>" suffix and surrounding space,
-- yielding the meaningful base name. Community channels are resolved to their
-- community name first. Returns nil for empty/invalid input.
local function baseName(name)
  if type(name) ~= "string" or name == "" then return nil end
  local community = communityName(name)
  if community then return community end
  local base = name:match("^(.-)%s*[%-—]%s*.+$") or name
  base = base:gsub("^%s+", ""):gsub("%s+$", "")
  if base == "" then base = name end
  return base
end

-- Look up a user-defined short name for a channel. The map is keyed by channel
-- name but we also allow substring matches (e.g. "交易" hits "交易 - 城市"), so
-- users don't have to type the exact localized full name.
local function mappedName(name)
  if type(name) ~= "string" then return nil end
  local map = ns.Config and ns.Config:Get("profile.channelAbbrevMap")
  if type(map) ~= "table" then return nil end
  if map[name] then return map[name] end
  for key, val in pairs(map) do
    if type(key) == "string" and key ~= "" and name:find(key, 1, true) then
      return val
    end
  end
  return nil
end

-- Produce a short label from the channel name itself (no hardcoded map).
-- Takes the first few UTF-8 chars of the base name. A user-defined mapping
-- (channelAbbrevMap) takes priority when it matches.
local function abbreviate(name, id)
  local mapped = mappedName(name)
  if mapped and mapped ~= "" then return mapped end

  local base = baseName(name)
  if not base then return tostring(id) end

  local limit = abbrevChars()
  local chars, count = {}, 0
  for ch in base:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    count = count + 1
    chars[#chars + 1] = ch
    if count >= limit then break end
  end
  if count > 0 then return table.concat(chars) end
  return tostring(id)
end

-- The channel-button label text.
--   abbreviateChannels on  -> short name (mapped or first N chars)
--   abbreviateChannels off -> full base name
--   channelBarShowNumber   -> prepend the channel number (e.g. "6大脚")
local function channelLabel(name, id)
  local doAbbrev = ns.Config and ns.Config:Get("profile.abbreviateChannels")
  if doAbbrev == nil then doAbbrev = true end
  local text = doAbbrev and abbreviate(name, id) or (baseName(name) or tostring(id))

  local showNum = ns.Config and ns.Config:Get("profile.channelBarShowNumber")
  if showNum then
    return id .. text
  end
  return text
end

function ChannelBar:Init()
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
  watcher:RegisterEvent("PLAYER_GUILD_UPDATE")
  watcher:RegisterEvent("CHANNEL_UI_UPDATE")   -- channels joined/left
  watcher:RegisterEvent("CHANNEL_LEFT")
  -- Club/community data arrives asynchronously; rebuild once it loads so the
  -- "社区" placeholder is replaced by the real stream/club name.
  pcall(function() watcher:RegisterEvent("CLUB_STREAMS_LOADED") end)
  pcall(function() watcher:RegisterEvent("CLUB_ADDED") end)
  pcall(function() watcher:RegisterEvent("INITIAL_CLUBS_LOADED") end)
  watcher:SetScript("OnEvent", function()
    ns.Core:SafeCall(function() ChannelBar:Rebuild() end)
  end)
  self.watcher = watcher

  self:ApplyVisibility()
end

-- Build the ordered list of button definitions: fixed base + one per joined
-- numbered channel (dynamic).
function ChannelBar:_collectDefs()
  local defs = {}
  for _, b in ipairs(BASE_BUTTONS) do
    -- Honor per-button visibility config (default shown when unset).
    local show = not b.show or ns.Config == nil or ns.Config:Get(b.show) ~= false
    if show then defs[#defs + 1] = b end
  end

  local list = { GetChannelList() }
  -- GetChannelList returns (index, name, disabled) triples. IMPORTANT: the
  -- first value is the channel INDEX (join order), which is NOT necessarily
  -- the number used by "/N" to send. The correct send number must be looked
  -- up by name via GetChannelName(name), which returns the real channel id.
  for i = 1, #list, 3 do
    local name = list[i + 1]
    if type(name) == "string" and name ~= "" then
      local realId = GetChannelName(name)   -- authoritative send number
      if type(realId) == "number" and realId > 0 then
        defs[#defs + 1] = {
          key = "chan" .. realId,
          label = channelLabel(name, realId),
          chatType = "CHANNEL",
          channelId = realId,
          channelName = name,
          available = function() return true end,
        }
      end
    end
  end
  return defs
end

local function makeBar()
  local f = CreateFrame("Frame", "MyChatChannelBar", UIParent, "BackdropTemplate")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local rt = ns.Config and ns.Config:GetRuntime()
    if rt then
      local point, _, relPoint, x, y = self:GetPoint()
      rt.channelBarPos = { point = point, relPoint = relPoint, x = x, y = y }
    end
  end)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
  end
  return f
end

local function anchorBar(f)
  f:ClearAllPoints()
  local pos = ns.Config and ns.Config:GetRuntime() and ns.Config:GetRuntime().channelBarPos
  if pos then
    f:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "TOPLEFT", pos.x or 0, pos.y or 0)
  elseif ChatFrame1 then
    f:SetPoint("TOPLEFT", ChatFrame1, "BOTTOMLEFT", 0, -6)
  else
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
  end
end

function ChannelBar:_ensureFrame()
  if not self.frame then
    self.frame = makeBar()
    anchorBar(self.frame)
  end
  self:Rebuild()
  return self.frame
end

-- (Re)create all buttons with a compact, wrapping layout.
function ChannelBar:Rebuild()
  local f = self.frame
  if not f then return end

  -- Release old buttons.
  if self.buttons then
    for _, entry in ipairs(self.buttons) do
      entry.frame:Hide()
      entry.frame:SetParent(nil)
    end
  end
  self.buttons = {}

  local defs = self:_collectDefs()
  local x, y = PADDING, -PADDING
  local rowWidth, maxRowWidth, rows = 0, 0, 1

  for _, def in ipairs(defs) do
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetText(def.label)
    local w = math.max(BUTTON_MIN_WIDTH, (btn:GetTextWidth() or 0) + BUTTON_PAD_X)
    btn:SetSize(w, BUTTON_HEIGHT)

    -- Wrap to next row if this button would exceed the max row width.
    if rowWidth > 0 and (rowWidth + w + BUTTON_GAP) > MAX_ROW_WIDTH then
      rows = rows + 1
      x = PADDING
      y = y - (BUTTON_HEIGHT + ROW_GAP)
      rowWidth = 0
    end

    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    btn:SetScript("OnClick", function()
      ns.Core:SafeCall(function() ChannelBar:_activate(def) end)
    end)

    self.buttons[#self.buttons + 1] = { frame = btn, def = def }
    x = x + w + BUTTON_GAP
    rowWidth = rowWidth + w + BUTTON_GAP
    if rowWidth > maxRowWidth then maxRowWidth = rowWidth end
  end

  local totalWidth = math.max(maxRowWidth + PADDING, PADDING * 2 + BUTTON_MIN_WIDTH)
  local totalHeight = PADDING * 2 + rows * BUTTON_HEIGHT + (rows - 1) * ROW_GAP
  f:SetSize(totalWidth, totalHeight)

  self:RefreshButtons()
end

-- Open the native chat edit box on the target channel. We only set the input
-- context; the player types and presses Enter to send (no taint, no misfire).
function ChannelBar:_activate(def)
  local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or ChatEdit_GetActiveWindow()
  if not editBox then
    editBox = ChatEdit_GetLastActiveWindow and ChatEdit_GetLastActiveWindow()
  end
  if not editBox then return end

  -- Let Up/Down arrows browse sent-message history directly (not Alt+arrow).
  -- Must run for BOTH channel and base-target paths, so set it up front.
  if editBox.SetAltArrowKeyMode then
    editBox:SetAltArrowKeyMode(false)
  end

  if def.chatType == "CHANNEL" then
    -- Channel numbers are NOT stable (they shift when you join/leave channels
    -- or switch characters). Resolve the CURRENT number from the channel name
    -- at click time instead of trusting the id captured when the bar was built.
    local id = def.channelName and GetChannelName(def.channelName) or def.channelId
    if not id or id == 0 then
      -- Fall back to a fresh rebuild; the channel may have moved or dropped.
      self:Rebuild()
      return
    end
    editBox:SetText("/" .. id .. " ")
    editBox:Show()
    editBox:SetFocus()
    if editBox.SetCursorPosition then
      editBox:SetCursorPosition(editBox:GetNumLetters())
    end
    return
  end

  editBox:SetAttribute("chatType", def.chatType)
  ChatEdit_UpdateHeader(editBox)
  editBox:Show()
  editBox:SetFocus()
end

-- Enable/disable base buttons by context. Dynamic channel buttons are always
-- enabled (they only exist while joined).
function ChannelBar:RefreshButtons()
  if not self.buttons then return end
  for _, entry in ipairs(self.buttons) do
    local ok = true
    ns.Core:SafeCall(function() ok = entry.def.available() and true or false end)
    if ok then entry.frame:Enable() else entry.frame:Disable() end
  end
end

-- Show/hide per config; frame creation/toggling go through CombatGuard.
function ChannelBar:ApplyVisibility()
  local enabled = ns.Config and ns.Config:Get("profile.channelBarEnabled")
  if not enabled and not self.frame then return end
  local guard = ns.CombatGuard
  local apply = function()
    local f = self:_ensureFrame()
    if enabled then f:Show() else f:Hide() end
  end
  if guard then guard:Run(apply) else ns.Core:SafeCall(apply) end
end

function ChannelBar:Toggle()
  if not ns.Config then return end
  local now = ns.Config:Get("profile.channelBarEnabled")
  ns.Config:Set("profile.channelBarEnabled", not now)
  self:ApplyVisibility()
end
