local addonName, ns = ...

local U = {}
ns.Utils = U

local strtrim = strtrim
local floor = math.floor

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
  local title = ns.Constants and ns.Constants.ADDON_TITLE or "Sudoku"
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

-- 秒数格式化为 mm:ss（超过 60 分钟显示 h:mm:ss）。
function U.FormatClock(seconds)
  seconds = floor(tonumber(seconds) or 0)
  if seconds < 0 then seconds = 0 end
  local h = floor(seconds / 3600)
  local m = floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

-- (row, col) <-> 线性下标（1..81）互转。行列均 1 起。
function U.Index(row, col)
  return (row - 1) * 9 + col
end

function U.RowCol(index)
  local r = floor((index - 1) / 9) + 1
  local c = (index - 1) % 9 + 1
  return r, c
end
