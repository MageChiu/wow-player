local addonName, ns = ...

local Parser = {}
ns.Parser = ns.Core:RegisterModule("Parser", Parser)

local C = ns.Constants
local Bus = ns.Bus
local Utils = ns.Utils

local GetTime = GetTime

-- Channel names (localized) that we treat as trade/world when heard on a
-- numbered channel. Kept loose: substring match tolerates server prefixes.
local TRADE_HINTS = { "交易", "trade" }
local WORLD_HINTS = { "世界", "world", "大脚世界频道", "lfg" }

local function matchesAny(name, hints)
  if type(name) ~= "string" then return false end
  local lower = name:lower()
  for _, h in ipairs(hints) do
    if lower:find(h:lower(), 1, true) then return true end
  end
  return false
end

function Parser:Init()
  Bus:On(C.TOPIC.MESSAGE_RAW, function(payload)
    if not payload then return end
    local message = self:Normalize(payload.event, unpack(payload.args or {}))
    if message then
      Bus:Emit(C.TOPIC.MESSAGE_NORMALIZED, message)
    end
  end)
end

-- Decide channelType/messageClass from event + channel name.
function Parser:ClassifyChannel(event, channelName)
  if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
    return "whisper", C.CLASS.WHISPER
  elseif event == "CHAT_MSG_GUILD" then
    return "guild", C.CLASS.GUILD
  elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
    return "party", C.CLASS.PARTY
  elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
    return "raid", C.CLASS.RAID
  elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
    return "instance", C.CLASS.INSTANCE
  elseif event == "CHAT_MSG_SYSTEM" then
    return "system", C.CLASS.SYSTEM
  elseif event == "CHAT_MSG_CHANNEL" then
    if matchesAny(channelName, TRADE_HINTS) then
      return "channel", C.CLASS.TRADE
    elseif matchesAny(channelName, WORLD_HINTS) then
      return "channel", C.CLASS.WORLD
    end
    return "channel", C.CLASS.CHANNEL
  end
  return "unknown", C.CLASS.SYSTEM
end

-- CHAT_MSG_* argument layout (12.0.x): arg1 text, arg2 author,
-- arg9 channel index, arg9? channelName. We rely on the documented
-- positions: text=1, sender=2, channelName=9 (only for CHANNEL events).
function Parser:Normalize(event, ...)
  if type(event) ~= "string" then return nil end
  local args = { ... }
  local textRaw = args[1]
  local author = args[2]
  local channelName = args[9]

  local channelType, messageClass = self:ClassifyChannel(event, channelName)

  local playerName = UnitName("player")
  local isSelf = false
  if author and playerName then
    isSelf = (Utils.ShortName(author) == Utils.ShortName(playerName))
  end
  -- Outgoing whispers are always "self".
  if event == "CHAT_MSG_WHISPER_INFORM" then
    isSelf = true
  end

  local textPlain = textRaw
  if type(textPlain) == "string" then
    -- Strip color/link escapes for matching/dedup, keep textRaw for display.
    textPlain = textPlain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    textPlain = textPlain:gsub("|H.-|h(.-)|h", "%1")
  end

  local ts = GetTime()
  local message = {
    id = string.format("%s:%s:%d", tostring(event), tostring(author or "?"), math.floor(ts * 1000)),
    ts = ts,
    eventType = event,
    channelType = channelType,
    channelName = channelName,
    author = author and Utils.ShortName(author) or nil,
    authorFullName = author,
    isSelf = isSelf,
    textRaw = textRaw,
    textPlain = textPlain,
    messageClass = messageClass,
    priority = 0,
  }
  return message
end
