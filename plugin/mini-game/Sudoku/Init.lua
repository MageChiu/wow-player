local addonName, ns = ...

local Core = ns.Core

-- 引导：等自己的 SavedVariables 加载完，再初始化所有模块。
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(self, event, loadedAddon)
  if event == "ADDON_LOADED" and loadedAddon == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    Core:Init()
  end
end)
