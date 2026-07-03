local addonName, ns = ...

local MirrorPanel = {}
ns.MirrorPanel = ns.Core:RegisterModule("MirrorPanel", MirrorPanel)

local C = ns.Constants
local Bus = ns.Bus

local MAX_LINES = 100

-- Per-view tint applied to mirrored lines.
local VIEW_COLOR = {
  world = "ff40c0f0",
  trade = "fff0c040",
  channel = "ffc0c0c0",
  party = "ff40f040",
  guild = "ff40f0a0",
  whisper = "fff080f0",
  system = "ff909090",
  other = "ffffffff",
}

function MirrorPanel:Init()
  -- Frame is created lazily on first enable to avoid cost when unused.
  Bus:On(C.TOPIC.MESSAGE_NORMALIZED, function(message)
    self:Push(message)
  end)
  -- Apply initial visibility from saved config (deferred if in combat).
  self:ApplyVisibility()
end

function MirrorPanel:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "MyChatMirrorPanel", UIParent, "BackdropTemplate")
  f:SetSize(360, 220)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText(C.ADDON_TITLE .. " 镜像")

  local sf = CreateFrame("ScrollingMessageFrame", nil, f)
  sf:SetPoint("TOPLEFT", 10, -28)
  sf:SetPoint("BOTTOMRIGHT", -10, 10)
  sf:SetFontObject(ChatFontNormal)
  sf:SetJustifyH("LEFT")
  sf:SetMaxLines(MAX_LINES)
  sf:SetFading(false)
  sf:SetInsertMode("BOTTOM")
  f.messages = sf

  self.frame = f
  return f
end

-- Show/hide the panel per config, always through CombatGuard since it
-- creates and toggles frame structure.
function MirrorPanel:ApplyVisibility()
  local enabled = ns.Config and ns.Config:Get("profile.mirrorPanelEnabled")
  -- Nothing to do if disabled and the frame was never created.
  if not enabled and not self.frame then return end
  local guard = ns.CombatGuard
  local apply = function()
    local f = self:_ensureFrame()
    if enabled then f:Show() else f:Hide() end
  end
  if guard then guard:Run(apply) else ns.Core:SafeCall(apply) end
end

function MirrorPanel:Toggle()
  if not ns.Config then return end
  local now = ns.Config:Get("profile.mirrorPanelEnabled")
  ns.Config:Set("profile.mirrorPanelEnabled", not now)
  self:ApplyVisibility()
end

-- Mirror a normalized message. Never touches the native ChatFrame.
function MirrorPanel:Push(message)
  if not (ns.Config and ns.Config:Get("profile.mirrorPanelEnabled")) then return end
  if not self.frame or not self.frame:IsShown() then return end
  if not message then return end

  local Router = ns.Router
  local views = Router and Router:Route(message) or {}
  local view = views[1] or "other"
  local color = VIEW_COLOR[view] or VIEW_COLOR.other

  local author = message.author and ("<" .. message.author .. "> ") or ""
  local text = message.textPlain or message.textRaw or ""
  self.frame.messages:AddMessage("|c" .. color .. author .. text .. "|r")
end
