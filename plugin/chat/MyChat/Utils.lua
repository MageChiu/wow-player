local addonName, ns = ...

local U = {}
ns.Utils = U

local GetTime = GetTime
local date = date
local strtrim = strtrim
local tinsert = table.insert

function U.Now()
  return GetTime()
end

function U.Clock()
  return date("%H:%M")
end

function U.Trim(s)
  if type(s) ~= "string" then return s end
  if strtrim then return strtrim(s) end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Wrap text in a WoW color escape. hex is "AARRGGBB".
function U.ColorText(hex, text)
  if not hex or not text then return text end
  return "|c" .. hex .. text .. "|r"
end

-- Split a comma/space separated string into a trimmed list.
function U.SplitList(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for token in s:gmatch("[^,%s]+") do
    tinsert(out, token)
  end
  return out
end

-- Deep copy plain tables (no metatables, no cycles). Used by Config reset.
function U.DeepCopy(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do
    out[k] = U.DeepCopy(v)
  end
  return out
end

-- Fill missing keys in dst from defaults, recursing into tables.
-- Existing user values are never overwritten.
function U.DeepMergeDefaults(dst, defaults)
  if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      U.DeepMergeDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

function U.Print(msg)
  local prefix = "|cff66ccff" .. (ns.Constants and ns.Constants.ADDON_TITLE or "MyChat") .. "|r: "
  DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
end

-- Strip realm suffix from a full player name.
function U.ShortName(fullName)
  if type(fullName) ~= "string" then return fullName end
  local short = fullName:match("^([^%-]+)")
  return short or fullName
end
