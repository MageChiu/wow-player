local addonName, ns = ...

local NativeEnhancer = {}
ns.NativeEnhancer = ns.Core:RegisterModule("NativeEnhancer", NativeEnhancer)

local C = ns.Constants
local Utils = ns.Utils

local date = date

-- Events whose native display we augment via AddMessageEventFilter.
-- We intentionally exclude CHAT_MSG_SYSTEM from author coloring.
local FILTERED_EVENTS = C.CHAT_EVENTS

local function cfg(path, default)
  local Config = ns.Config
  if not Config then return default end
  local v = Config:Get(path)
  if v == nil then return default end
  return v
end

function NativeEnhancer:Init()
  local filter = function(chatFrame, event, ...)
    return NativeEnhancer:MessageFilter(chatFrame, event, ...)
  end
  for _, event in ipairs(FILTERED_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, filter)
  end
end

-- Timestamp + channel abbreviation prefix.
function NativeEnhancer:BuildPrefix(message)
  local parts = {}
  if cfg("profile.showTimestamps", true) then
    parts[#parts + 1] = "|cff808080[" .. date("%H:%M") .. "]|r"
  end
  if cfg("profile.abbreviateChannels", true) then
    local abbrev = C.CHANNEL_ABBREV[message.messageClass]
    if abbrev then
      parts[#parts + 1] = "|cff8080ff[" .. abbrev .. "]|r"
    end
  end
  if #parts == 0 then return "" end
  return table.concat(parts, "") .. " "
end

-- Return a class-colored sender name, or nil to leave untouched.
-- guid is CHAT_MSG arg12. Falls back gracefully when unavailable.
function NativeEnhancer:ColorizeAuthor(author, guid)
  if not cfg("profile.colorPlayerNamesByClass", true) then return nil end
  if not author or author == "" or not guid or guid == "" then return nil end
  local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
  if not ok or not classFile then return nil end
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if not color then return nil end
  return Utils.ColorText(color.colorStr or C.DEFAULT_AUTHOR_COLOR, author)
end

-- AddMessageEventFilter callback. Never blocks messages; only rewrites the
-- text and (optionally) the sender arg. Returns false + modified args so the
-- native chat system still formats and displays the line.
function NativeEnhancer:MessageFilter(chatFrame, event, ...)
  local ok, result, newMsg, newAuthor = pcall(function(...)
    local args = { ... }
    local msg = args[1]
    local author = args[2]
    local guid = args[12]

    local Parser = ns.Parser
    if not Parser then return false end
    local message = Parser:Normalize(event, ...)
    if not message then return false end

    local text = msg
    local Filters = ns.Filters
    if Filters then
      message.textRaw = msg
      Filters:Apply(message)
      text = message.displayText or msg
    end

    local prefix = self:BuildPrefix(message)
    local finalMsg = prefix .. (text or "")

    local coloredAuthor = self:ColorizeAuthor(author, guid)
    return true, finalMsg, coloredAuthor or author
  end, ...)

  -- On any error, do nothing (native display unaffected).
  if not ok or not result then
    local diag = ns.Core:GetModule("Diagnostics")
    if diag and diag.Error and not ok then diag:Error("NativeEnhancer", result) end
    return false
  end

  -- Rebuild the arg list with rewritten text/author, preserve the rest.
  local args = { ... }
  args[1] = newMsg
  args[2] = newAuthor
  return false, unpack(args)
end
