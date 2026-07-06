local addonName, ns = ...

local U = {}
ns.Utils = U

local floor = math.floor

function U.Print(msg)
  local title = ns.Constants and ns.Constants.ADDON_TITLE or "CombatCoach"
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. title .. "|r: " .. tostring(msg))
end

function U.ColorText(hex, text)
  if not hex or not text then return text end
  return "|c" .. hex .. tostring(text) .. "|r"
end

-- 大数字缩写：12345 -> 12.3k，1234567 -> 1.23M。用于 DPS/HPS 展示。
function U.Short(n)
  n = tonumber(n) or 0
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%d", floor(n + 0.5))
end

-- 秒数 -> "1:23" / "12s"。
function U.Duration(sec)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  local m = floor(sec / 60)
  local s = floor(sec % 60)
  if m > 0 then return string.format("%d:%02d", m, s) end
  return string.format("%ds", s)
end

-- 百分比文本，输入为 0~1 的比例。
function U.Pct(ratio, digits)
  ratio = tonumber(ratio) or 0
  return string.format("%." .. (digits or 0) .. "f%%", ratio * 100)
end

-- 安全除：分母为 0 时返回 0，避免 nan/inf 传到 UI。
function U.Div(a, b)
  a = tonumber(a) or 0
  b = tonumber(b) or 0
  if b == 0 then return 0 end
  return a / b
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
