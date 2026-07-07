local addonName, ns = ...

local U = {}
ns.Utils = U

local strtrim = strtrim
local floor = math.floor
local time = time

function U.Trim(s)
  if type(s) ~= "string" then return s end
  if strtrim then return strtrim(s) end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.ColorText(hex, text)
  if not hex or not text then return text end
  return "|c" .. hex .. tostring(text) .. "|r"
end

function U.Print(msg)
  local title = ns.Constants and ns.Constants.ADDON_TITLE or "WowPlayerSuite"
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. title .. "|r: " .. tostring(msg))
end

-- atan2 在不同客户端 Lua 版本里位置不一（全局 / math.atan2 / math.atan(y,x)）。
function U.Atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

function U.DeepCopy(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do
    out[k] = U.DeepCopy(v)
  end
  return out
end

-- 用 defaults 补齐 dst 缺失键，不覆盖已有用户值。
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

function U.AgoText(epochSeconds)
  if type(epochSeconds) ~= "number" then return "未知" end
  local diff = (time and time() or 0) - epochSeconds
  if diff < 0 then diff = 0 end
  if diff < 60 then return "刚刚" end
  if diff < 3600 then return floor(diff / 60) .. " 分钟前" end
  if diff < 86400 then return floor(diff / 3600) .. " 小时前" end
  return floor(diff / 86400) .. " 天前"
end
