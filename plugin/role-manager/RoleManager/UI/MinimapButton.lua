local addonName, ns = ...

-- 注意：不能把本模块表命名为局部 `Minimap`，否则会遮蔽游戏全局的
-- Minimap 框架，导致 CreateFrame(..., Minimap) 收到普通 table 而报
-- "Wrong object type for function"。故模块表用 MB，全局框架保持 Minimap。
local MB = {}
ns.MinimapButton = ns.Core:RegisterModule("MinimapButton", MB)

local Utils = ns.Utils
local Const = ns.Constants

local function updatePosition(btn, angle)
  local rad = math.rad(angle or 210)
  -- 半径取小地图自身半径 + 外扩，使按钮落在小地图圆环外侧而非内部。
  local mw = (Minimap.GetWidth and Minimap:GetWidth()) or 140
  local radius = mw / 2 + 8
  btn:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(rad), radius * math.sin(rad))
end

-- atan2 在不同客户端 Lua 版本里位置不一（全局 / math.atan2 / math.atan(y,x)）。
local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- 悬浮提示：账号下各角色关键数据的速览。
local function showTooltip(btn)
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:AddLine(Const.ADDON_TITLE, 1, 0.82, 0)

  local Store = ns.Store
  local warband = Store:GetWarbandMoney()
  if warband then
    GameTooltip:AddLine("战团银行: " .. Utils.FormatMoney(warband), 1, 1, 1)
  end
  GameTooltip:AddLine(" ")

  local chars = Store:GetCharacters()
  if #chars == 0 then
    GameTooltip:AddLine("暂无角色数据，登录各角色一次即可记录。", 0.6, 0.6, 0.6)
  end
  for _, rec in ipairs(chars) do
    local name = Utils.ShortName(rec.name) or "?"
    local left = name
    local right = string.format("%s  秘:%s  团:%s  库:%s",
      Utils.FormatMoney(rec.money or 0),
      Store:MythicText(rec),
      Store:RaidText(rec),
      Store:VaultText(rec))
    GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.8, 0.8, 0.8)
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("左键: 打开汇总窗口", 0.4, 0.8, 1)
  GameTooltip:AddLine("右键: 刷新本角色", 0.4, 0.8, 1)
  GameTooltip:AddLine("数据为最后登录快照，非实时。", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function MB:Init()
  if not ns.Config:Get("profile.showMinimapButton") then return end
  self:_ensureButton()
end

function MB:_ensureButton()
  if self.button then return self.button end

  local btn = CreateFrame("Button", "RoleManagerMinimapButton", Minimap)
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
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetPoint("CENTER", -1, 1)

  btn:SetScript("OnEnter", function(self) ns.Core:SafeCall(function() showTooltip(self) end) end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
      if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
        ns.OverviewFrame:Refresh()
      end
      Utils.Print("已刷新本角色数据。")
    else
      if ns.OverviewFrame then ns.OverviewFrame:Toggle() end
    end
  end)

  -- 拖动沿小地图边缘移动。
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
