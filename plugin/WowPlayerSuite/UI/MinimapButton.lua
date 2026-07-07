local addonName, ns = ...

-- 注意：不能把本模块表命名为局部 `Minimap`，否则会遮蔽游戏全局的
-- Minimap 框架，导致 CreateFrame(..., Minimap) 报 "Wrong object type"。
-- 故模块表用 MB，全局框架保持 Minimap。
local MB = {}
ns.MinimapButton = ns.Core:RegisterModule("MinimapButton", MB)

local Utils = ns.Utils
local Const = ns.Constants

-- 按钮落在小地图圆环外侧：半径 = 小地图半径 + 外扩，绝不压地图内部。
local function updatePosition(btn, angle)
  local rad = math.rad(angle or 195)
  local mw = (Minimap.GetWidth and Minimap:GetWidth()) or 140
  local radius = mw / 2 + 8
  btn:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(rad), radius * math.sin(rad))
end

local function showTooltip(btn)
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:AddLine(Const.ADDON_TITLE, 1, 0.82, 0)

  local list = ns.Discovery:GetOrdered()
  if #list == 0 then
    GameTooltip:AddLine("暂无已接入的插件。", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddLine("已接入插件:", 0.8, 0.8, 0.8)
    for _, desc in ipairs(list) do
      local right = desc.version and ("v" .. desc.version) or ""
      GameTooltip:AddDoubleLine("  " .. (desc.title or "?"), right, 1, 1, 1, 0.7, 0.7, 0.7)
    end
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("左键: 打开整合面板", 0.4, 0.8, 1)
  GameTooltip:AddLine("拖动: 沿小地图边缘移动", 0.4, 0.8, 1)
  GameTooltip:Show()
end

function MB:Init()
  if not ns.Config:Get("profile.showMinimapButton") then return end
  self:_ensureButton()
end

function MB:_ensureButton()
  if self.button then return self.button end

  local btn = CreateFrame("Button", "WowPlayerSuiteMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(54, 54)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
  icon:SetPoint("CENTER", -1, 1)

  btn:SetScript("OnEnter", function(self) ns.Core:SafeCall(function() showTooltip(self) end) end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function()
    if ns.MainFrame then ns.MainFrame:Toggle() end
  end)

  -- 拖动沿小地图边缘移动，记住角度。
  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(s)
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      local angle = math.deg(Utils.Atan2(py - my, px - mx))
      updatePosition(s, angle)
      ns.Config:Set("profile.minimapButtonAngle", angle)
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  updatePosition(btn, ns.Config:Get("profile.minimapButtonAngle"))
  self.button = btn
  return btn
end

-- 幂等显隐：写入配置并即时反映到按钮。
function MB:SetShown(show)
  ns.Config:Set("profile.showMinimapButton", show and true or false)
  if show then
    local btn = self:_ensureButton()
    btn:Show()
  elseif self.button then
    self.button:Hide()
  end
end

function MB:Toggle()
  local show = not ns.Config:Get("profile.showMinimapButton")
  self:SetShown(show)
  Utils.Print("小地图按钮已" .. (show and "显示" or "隐藏") .. "。")
end
