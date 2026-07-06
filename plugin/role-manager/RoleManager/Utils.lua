local addonName, ns = ...

local U = {}
ns.Utils = U

local date = date
local time = time
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
  local title = ns.Constants and ns.Constants.ADDON_TITLE or "RoleManager"
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. title .. "|r: " .. tostring(msg))
end

-- 账号内角色的唯一键："角色名-服务器"。跨服角色名可能重名，必须带服务器。
function U.CharKey(name, realm)
  name = name or (UnitName and UnitName("player"))
  if not realm or realm == "" then
    realm = GetRealmName and GetRealmName() or "?"
  end
  return (name or "?") .. "-" .. (realm or "?")
end

-- 去掉全名里的服务器后缀，只留角色名。
function U.ShortName(fullName)
  if type(fullName) ~= "string" then return fullName end
  return fullName:match("^([^%-]+)") or fullName
end

-- 铜转为带图标的金/银/铜文本。WoW 内部一切金币都以铜为单位。
function U.FormatMoney(copper)
  copper = tonumber(copper) or 0
  local gold = floor(copper / 10000)
  local silver = floor((copper % 10000) / 100)
  local bronze = copper % 100
  local parts = {}
  if gold > 0 then
    parts[#parts + 1] = U.ColorText("ffffd700", U.GroupDigits(gold)) .. "|cffffd700g|r"
  end
  if silver > 0 or gold > 0 then
    parts[#parts + 1] = U.ColorText("ffc7c7cf", silver) .. "|cffc7c7cfs|r"
  end
  parts[#parts + 1] = U.ColorText("ffeda55f", bronze) .. "|cffeda55fc|r"
  return table.concat(parts, " ")
end

-- 千分位分组："1234567" -> "1,234,567"。仅用于金币的金部分。
function U.GroupDigits(n)
  local s = tostring(floor(tonumber(n) or 0))
  local left, num, right = s:match("^([^%d]*%d)(%d*)(.-)$")
  if not num then return s end
  return left .. num:reverse():gsub("(%d%d%d)", "%1,"):reverse() .. right
end

-- 相对时间描述，用于"更新于 X 前"。
function U.AgoText(epochSeconds)
  if type(epochSeconds) ~= "number" then return "未知" end
  local diff = (time and time() or 0) - epochSeconds
  if diff < 0 then diff = 0 end
  if diff < 60 then return "刚刚" end
  if diff < 3600 then return floor(diff / 60) .. " 分钟前" end
  if diff < 86400 then return floor(diff / 3600) .. " 小时前" end
  return floor(diff / 86400) .. " 天前"
end

-- 绝对时间戳文本。
function U.TimeText(epochSeconds)
  if type(epochSeconds) ~= "number" then return "?" end
  return date("%m-%d %H:%M", epochSeconds)
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
