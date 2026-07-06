local addonName, ns = ...

local Core = {}
ns.Core = Core

Core.modules = {}
Core.initOrder = {}
Core.initialized = false

function Core:RegisterModule(name, module)
  if self.modules[name] then
    error("RoleManager: duplicate module registration: " .. tostring(name))
  end
  self.modules[name] = module
  self.initOrder[#self.initOrder + 1] = name
  return module
end

function Core:GetModule(name)
  return self.modules[name]
end

-- pcall wrapper: a single failing callback must not break the addon.
function Core:SafeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, ...)
  if not ok then
    ns.Utils.Print("|cffff5555错误|r: " .. tostring(err))
  end
  return ok, err
end

-- Fixed init order. Modules absent at load time are simply skipped.
local INIT_SEQUENCE = {
  "Config",
  "Store",
  "Collector",
  "Commands",
  "OverviewFrame",
  "MinimapButton",
  "SettingsPanel",
}

function Core:Init()
  if self.initialized then return end
  self.initialized = true

  for _, name in ipairs(INIT_SEQUENCE) do
    local module = self.modules[name]
    if module and type(module.Init) == "function" then
      self:SafeCall(function() module:Init() end)
    end
  end

  ns.Utils.Print("v" .. ns.Constants.VERSION .. " 已加载，输入 /rm 查看角色汇总。")
end
