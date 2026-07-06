local addonName, ns = ...

local U = {}
ns.Utils = U

local strtrim = strtrim

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
  local title = ns.Constants and ns.Constants.ADDON_TITLE or "QuickDisenchant"
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. title .. "|r: " .. tostring(msg))
end

-- 品质颜色（用于列表文本着色）。取自 ITEM_QUALITY_COLORS，取不到则回退。
function U.QualityHex(quality)
  local colors = ITEM_QUALITY_COLORS
  if colors and colors[quality] and colors[quality].hex then
    -- .hex 形如 "|cffxxxxxx"，剥掉前缀只留 8 位。
    return colors[quality].hex:gsub("|c", "")
  end
  return "ffffffff"
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
