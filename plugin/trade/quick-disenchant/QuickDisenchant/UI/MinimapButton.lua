local addonName, ns = ...

-- 模块表用 MB，避免遮蔽全局 Minimap 框架（见 RoleManager 同名注释）。
local MB = {}
ns.MinimapButton = ns.Core:RegisterModule("MinimapButton", MB)

local Utils = ns.Utils
local Const = ns.Constants

local function updatePosition(btn, angle)
  local rad = math.rad(angle or 200)
  local mw = (Minimap.GetWidth and Minimap:GetWidth()) or 140
  local radius = mw / 2 + 8
  btn:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(rad), radius * math.sin(rad))
end

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local function showTooltip(btn)
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:AddLine(Const.ADDON_TITLE, 1, 0.82, 0)
  GameTooltip:AddLine("左键: 打开分解面板", 0.4, 0.8, 1)
  GameTooltip:AddLine("右键: 打开设置", 0.4, 0.8, 1)
  GameTooltip:Show()
end

function MB:Init()
  if not ns.Config:Get("profile.showMinimapButton") then return end
  self:_ensureButton()
end

function MB:_ensureButton()
  if self.button then return self.button end

  local btn = CreateFrame("Button", "QuickDisenchantMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(54, 54)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant")
  icon:SetPoint("CENTER", -1, 1)

  btn:SetScript("OnEnter", function(self) ns.Core:SafeCall(function() showTooltip(self) end) end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      if ns.SettingsPanel then ns.SettingsPanel:Toggle() end
    else
      if ns.Panel then ns.Panel:Toggle() end
    end
  end)

  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(s)
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      local angle = math.deg(atan2(py - my, px - mx))
      updatePosition(s, angle)
      ns.Config:Set("profile.minimapButtonAngle", angle)
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  updatePosition(btn, ns.Config:Get("profile.minimapButtonAngle"))
  self.button = btn
  return btn
end

function MB:Toggle()
  local show = not ns.Config:Get("profile.showMinimapButton")
  ns.Config:Set("profile.showMinimapButton", show)
  local btn = self:_ensureButton()
  if show then btn:Show() else btn:Hide() end
end
