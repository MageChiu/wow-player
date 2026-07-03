local addonName, ns = ...

local Core = ns.Core

-- Bootstrap: wait for our SavedVariables to load, then init all modules.
-- Slash command registration lives in the Commands module (see Commands.lua);
-- do NOT register /mychat here or it will double-register the handler.
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, event, loadedAddon)
  if event == "ADDON_LOADED" and loadedAddon == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    Core:Init()
  end
end)
