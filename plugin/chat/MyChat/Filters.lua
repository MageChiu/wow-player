local addonName, ns = ...

local Filters = {}
ns.Filters = ns.Core:RegisterModule("Filters", Filters)

local C = ns.Constants
local Utils = ns.Utils

local GetTime = GetTime

local KEYWORD_COLOR = "ffffd200"  -- gold
local SELF_COLOR = "ff00ff00"     -- green

local function cfg(path, default)
  local Config = ns.Config
  if not Config then return default end
  local v = Config:Get(path)
  if v == nil then return default end
  return v
end

function Filters:Init()
  self.dupWindow = {}  -- fingerprint -> { count, expires }
  self.selfName = UnitName("player")
end

-- Escape Lua pattern magic so keywords match literally.
local function escapePattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Highlight configured keywords by wrapping each occurrence in color.
-- Case-insensitive; operates on display text.
function Filters:HighlightKeywords(text)
  if type(text) ~= "string" then return text end
  if not cfg("profile.highlightKeywords") then return text end
  local keywords = cfg("profile.highlightKeywords", {})
  for _, kw in ipairs(keywords) do
    if type(kw) == "string" and kw ~= "" then
      local pattern = escapePattern(kw)
      text = text:gsub(pattern, function(match)
        return Utils.ColorText(KEYWORD_COLOR, match)
      end)
    end
  end
  return text
end

-- Highlight the player's own name when it appears in a message.
function Filters:HighlightSelf(text)
  if type(text) ~= "string" then return text end
  if not cfg("profile.highlightSelfName", true) then return text end
  local name = self.selfName or UnitName("player")
  if not name or name == "" then return text end
  local pattern = escapePattern(name)
  return (text:gsub(pattern, function(match)
    return Utils.ColorText(SELF_COLOR, match)
  end))
end

-- Sliding-window duplicate detection keyed on author+plain text.
-- Returns isDuplicate, count. Default policy is collapse, never drop.
function Filters:IsDuplicate(message)
  if not cfg("profile.enableRepeatCollapse", true) then return false, 1 end
  if not message or type(message.textPlain) ~= "string" then return false, 1 end
  if message.messageClass == C.CLASS.SYSTEM then return false, 1 end

  local now = GetTime()
  local key = (message.author or "?") .. "\0" .. message.textPlain
  local entry = self.dupWindow[key]

  if entry and entry.expires > now then
    entry.count = entry.count + 1
    entry.expires = now + C.DUPLICATE_WINDOW_SECONDS
    return true, entry.count
  end

  self.dupWindow[key] = { count = 1, expires = now + C.DUPLICATE_WINDOW_SECONDS }
  self:_prune(now)
  return false, 1
end

function Filters:_prune(now)
  for key, entry in pairs(self.dupWindow) do
    if entry.expires <= now then
      self.dupWindow[key] = nil
    end
  end
end

-- Apply text-level enhancements and duplicate marking. Returns a possibly
-- modified display text plus flags for the enhancer.
function Filters:Apply(message)
  local text = message.textRaw
  local isDup, count = self:IsDuplicate(message)

  text = self:HighlightKeywords(text)
  text = self:HighlightSelf(text)

  if isDup and count > 1 then
    text = text .. string.format(" |cff888888(重复 x%d)|r", count)
  end

  message.displayText = text
  message.collapsed = isDup and count > 1 or false
  message.repeatCount = count
  return message
end
