local addonName, ns = ...

local Core = ns.Core
local Utils = ns.Utils

-- Minimal slash handler for the skeleton. The full Commands module (T12)
-- will take over dispatch once present; until then this covers the
-- version/help/debug needs of batch 1.
local function HandleSlash(msg)
  local commands = Core:GetModule("Commands")
  if commands and commands.Dispatch then
    Core:SafeCall(function() commands:Dispatch(msg) end)
    return
  end

  msg = Utils.Trim(msg or ""):lower()
  if msg == "debug" then
    local diag = Core:GetModule("Diagnostics")
    if diag and diag.Dump then
      Utils.Print(diag:Dump())
    else
      Utils.Print("modules: " .. table.concat(Core:ModuleStatus(), ", "))
    end
    local bus = Core:GetModule("Bus")
    if bus and bus.DebugRecent then
      for _, line in ipairs(bus:DebugRecent()) do
        Utils.Print(line)
      end
    end
  else
    Utils.Print("v" .. ns.Constants.VERSION)
    Utils.Print("usage: /mychat [debug|reset|safe|reply <text>]")
  end
end

local function RegisterSlash()
  SLASH_MYCHAT1 = "/mychat"
  SlashCmdList["MYCHAT"] = HandleSlash
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, event, loadedAddon)
  if event == "ADDON_LOADED" and loadedAddon == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    RegisterSlash()
    Core:Init()
  end
end)
