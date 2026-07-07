local addonName, ns = ...

local Core = {}
ns.Core = Core

Core.modules = {}
Core.initOrder = {}
Core.initialized = false

function Core:RegisterModule(name, module)
  if self.modules[name] then
    error("Sudoku: duplicate module registration: " .. tostring(name))
  end
  self.modules[name] = module
  self.initOrder[#self.initOrder + 1] = name
  return module
end

function Core:GetModule(name)
  return self.modules[name]
end

-- pcall 包裹：单个回调失败不拖垮整个插件。
function Core:SafeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, ...)
  if not ok then
    ns.Utils.Print("|cffff5555错误|r: " .. tostring(err))
  end
  return ok, err
end

-- 固定初始化顺序；加载时缺席的模块直接跳过（便于分批实现）。
local INIT_SEQUENCE = {
  "Config",
  "Generator",
  "Game",
  "Commands",
  "Board",
  "MinimapButton",
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

  ns.Utils.Print("v" .. ns.Constants.VERSION .. " 已加载，输入 /sudoku 开一局数独。")
end
