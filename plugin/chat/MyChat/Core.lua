local addonName, ns = ...

local Core = {}
ns.Core = Core

Core.modules = {}
Core.initOrder = {}
Core.initialized = false

function Core:RegisterModule(name, module)
  if self.modules[name] then
    error("MyChat: duplicate module registration: " .. tostring(name))
  end
  self.modules[name] = module
  self.initOrder[#self.initOrder + 1] = name
  return module
end

function Core:GetModule(name)
  return self.modules[name]
end

-- pcall wrapper: a single failing callback must not break the addon.
-- Errors are routed to Diagnostics when available.
function Core:SafeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, ...)
  if not ok then
    local diag = self.modules.Diagnostics
    if diag and diag.Error then
      diag:Error("SafeCall", err)
    else
      ns.Utils.Print("|cffff5555error|r: " .. tostring(err))
    end
  end
  return ok, err
end

-- Fixed init order. Modules absent at load time are simply skipped,
-- so batches can be implemented incrementally.
local INIT_SEQUENCE = {
  "Config",
  "Bus",
  "Diagnostics",
  "CombatGuard",
  "Events",
  "Parser",
  "Filters",
  "Router",
  "Channels",
  "NativeEnhancer",
  "WhisperIndex",
  "Commands",
  "SettingsPanel",
  "MirrorPanel",
  "ChannelBar",
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

  ns.Utils.Print("v" .. ns.Constants.VERSION .. " loaded. Type /mychat for options.")
end

-- Snapshot used by /mychat debug when Diagnostics is not yet present.
function Core:ModuleStatus()
  local lines = {}
  for _, name in ipairs(self.initOrder) do
    lines[#lines + 1] = name
  end
  return lines
end
