local addonName, ns = ...

-- 发现层：整合包主动"发现并适配"已安装的插件，插件本身零改动。
--
-- 为什么不是让插件来注册（bridge）？因为整合包的价值在于能管理那些
-- "不知道 Hub 存在"的插件——包括第三方/社区插件。若接入前提是每个插件
-- 都加一段 bridge，社区插件就无法纳入。故这里反过来：由 Hub 依据一张
-- 内置适配表去发现插件，用其早已注册的全局入口（SlashCmdList）驱动。
--
-- 同时保留一个可选的自愿注册 API（WowPlayerSuiteAPI:Register），供愿意
-- 深度集成的插件上报更丰富的能力；但它不是接入的必要条件。
local Discovery = {}
ns.Discovery = ns.Core:RegisterModule("Discovery", Discovery)

local Utils = ns.Utils
local API_GLOBAL = ns.Constants.API_GLOBAL

-- C_AddOns 兼容封装（12.0 用 C_AddOns.*，旧接口用全局同名函数）。
local function isLoaded(addon)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) end
  if IsAddOnLoaded then return IsAddOnLoaded(addon) end
  return false
end

local function metadata(addon, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(addon, field) end
  if GetAddOnMetadata then return GetAddOnMetadata(addon, field) end
  return nil
end

-- 内置适配表：Hub 认识的插件的接入知识。这是"运行时管理"的单一清单。
--   addon:    插件文件夹名（= .toc 名，用于 C_AddOns 查询与加载检测）
--   slash:    该插件在 SlashCmdList 里的键名（大写），用于驱动其命令
--   settings: 传给命令的参数，用来打开其设置面板（如 "config"）
--   bundled:  是否为官方整包成员（true=随整合包一起发布；false/nil=仅
--             管理的第三方/社区插件，用户自行单独安装）。
--             整包成员须与 package-suite.sh 的 PLUGINS 列表保持一致，
--             详见 plugin/插件接入与打包规范.md。
--
-- 新增社区插件：在此加一行、bundled 省略或置 false，不改那个插件本身。
-- 新增整包成员：在此加一行 bundled=true，并同步 package-suite.sh。
local KNOWN = {
  { addon = "MyChat",          slash = "MYCHAT",          settings = "config", displaySlash = "/mychat", bundled = true },
  { addon = "RoleManager",     slash = "ROLEMANAGER",     settings = "config", displaySlash = "/rm",     bundled = true },
  { addon = "CombatCoach",     slash = "COMBATCOACH",     settings = "config", displaySlash = "/cc",     bundled = true },
  { addon = "QuickDisenchant", slash = "QUICKDISENCHANT", settings = "config", displaySlash = "/qde",    bundled = true },
}

-- 供 UI 订阅"发现结果变化"的回调（后加载的插件会触发刷新）。
Discovery.listeners = {}
-- 自愿注册进来的描述符，键为 title。合并时优先于发现结果。
Discovery.registered = {}

function Discovery:AddListener(fn)
  if type(fn) == "function" then
    self.listeners[#self.listeners + 1] = fn
  end
end

function Discovery:_notify()
  for _, fn in ipairs(self.listeners) do
    ns.Core:SafeCall(fn)
  end
end

-- 用 SlashCmdList 入口打开某插件的设置。返回是否成功触发。
local function makeOpenSettings(slashKey, arg)
  return function()
    local handler = SlashCmdList and SlashCmdList[slashKey]
    if type(handler) ~= "function" then return false end
    handler(arg or "")
    return true
  end
end

-- 计算当前可见的插件条目列表（发现 + 自愿注册合并）。
function Discovery:GetOrdered()
  local byTitle = {}
  local order = {}

  -- 1) 内置适配表里的、且当前已加载的插件。
  for _, def in ipairs(KNOWN) do
    if isLoaded(def.addon) then
      local title = metadata(def.addon, "Title") or def.addon
      local entry = {
        title = title,
        addon = def.addon,
        version = metadata(def.addon, "Version"),
        slashCmd = def.displaySlash,
        bundled = def.bundled and true or false,
        source = "discovered",
      }
      -- 有对应命令入口才提供"打开设置"。
      if SlashCmdList and type(SlashCmdList[def.slash]) == "function" then
        entry.openSettings = makeOpenSettings(def.slash, def.settings)
      end
      byTitle[title] = entry
      order[#order + 1] = title
    end
  end

  -- 2) 自愿注册的描述符：覆盖/补充发现结果（深度集成优先）。
  for title, desc in pairs(self.registered) do
    local entry = byTitle[title]
    if not entry then
      entry = { title = title, source = "registered" }
      byTitle[title] = entry
      order[#order + 1] = title
    else
      entry.source = "discovered+registered"
    end
    entry.version = desc.version or entry.version
    entry.slashCmd = desc.slashCmd or entry.slashCmd
    if type(desc.openSettings) == "function" then entry.openSettings = desc.openSettings end
    if type(desc.setMinimapShown) == "function" then entry.setMinimapShown = desc.setMinimapShown end
    if type(desc.getMinimapShown) == "function" then entry.getMinimapShown = desc.getMinimapShown end
  end

  -- 稳定排序：按 KNOWN 的次序，未列出的排后面。
  local rank = {}
  for i, def in ipairs(KNOWN) do
    local t = metadata(def.addon, "Title") or def.addon
    rank[t] = i
  end
  local list = {}
  for _, title in ipairs(order) do
    if byTitle[title] then
      list[#list + 1] = byTitle[title]
      byTitle[title] = nil  -- 防重复
    end
  end
  table.sort(list, function(a, b)
    local ra = rank[a.title] or math.huge
    local rb = rank[b.title] or math.huge
    if ra ~= rb then return ra < rb end
    return tostring(a.title) < tostring(b.title)
  end)
  return list
end

-- 自愿注册：安装全局 API，供插件（含社区插件）可选地上报更丰富能力。
local function installAPI()
  local api = _G[API_GLOBAL]
  if type(api) ~= "table" then
    api = { _pending = {} }
    _G[API_GLOBAL] = api
  end

  function api.Register(_, descriptor)
    ns.Core:SafeCall(function()
      if type(descriptor) == "table" and type(descriptor.title) == "string" and descriptor.title ~= "" then
        Discovery.registered[descriptor.title] = descriptor
        Discovery:_notify()
      end
    end)
  end

  -- 排空 Hub 加载前积压的自愿注册。
  if type(api._pending) == "table" then
    for _, descriptor in ipairs(api._pending) do
      api:Register(descriptor)
    end
    api._pending = {}
  end
end

function Discovery:Init()
  installAPI()

  -- 监听后续插件加载：某些插件可能晚于 Hub 加载，加载后刷新列表。
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("ADDON_LOADED")
  watcher:SetScript("OnEvent", function(_, _, loaded)
    for _, def in ipairs(KNOWN) do
      if loaded == def.addon then
        Discovery:_notify()
        return
      end
    end
  end)
end
