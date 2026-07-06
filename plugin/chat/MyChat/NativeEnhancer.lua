local addonName, ns = ...

local NativeEnhancer = {}
ns.NativeEnhancer = ns.Core:RegisterModule("NativeEnhancer", NativeEnhancer)

local C = ns.Constants

-- Events whose native display we augment via AddMessageEventFilter.
local FILTERED_EVENTS = C.CHAT_EVENTS

function NativeEnhancer:Init()
  local filter = function(chatFrame, event, ...)
    return NativeEnhancer:MessageFilter(chatFrame, event, ...)
  end
  for _, event in ipairs(FILTERED_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, filter)
  end

  self:EnableArrowHistory()
end

-- Let Up/Down arrows browse the native sent-message history on every chat edit
-- box (Blizzard default requires Alt+Up/Down). AltArrowKeyMode gets reset back
-- to the default by the game at various times (notably entering a PvP
-- battleground / arena, which rebuilds chat state). Setting it once at login is
-- therefore not enough. The robust fix used by mature chat addons is to hook
-- each edit box's OnEditFocusGained and re-apply it every time the box opens,
-- so no matter when the game resets it, the next time you start typing it is
-- forced back off. Pure native tweak: no taint, no message interception.
function NativeEnhancer:EnableArrowHistory()
  local function harden(edit)
    if not edit or not edit.SetAltArrowKeyMode then return end
    edit:SetAltArrowKeyMode(false)
    if not edit.__myChatArrowHooked then
      edit.__myChatArrowHooked = true
      -- Re-apply on every focus gain; also cover OnShow for good measure.
      edit:HookScript("OnEditFocusGained", function(box)
        box:SetAltArrowKeyMode(false)
      end)
      edit:HookScript("OnShow", function(box)
        box:SetAltArrowKeyMode(false)
      end)
    end
  end

  local apply = function()
    local n = (NUM_CHAT_WINDOWS or 10)
    for i = 1, n do
      harden(_G["ChatFrame" .. i .. "EditBox"])
    end
  end
  apply()

  -- Reapply on login/reload and each world entry (zoning, entering BG/arena).
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function()
    ns.Core:SafeCall(apply)
  end)
  self.arrowHistoryFrame = f
end

-- AddMessageEventFilter callback. Never blocks messages; only rewrites the
-- message TEXT (keyword/self highlight, dedup marker). It must NOT touch the
-- sender argument: wrapping the author in color codes corrupts the channel
-- hyperlink (|Hplayer:...|h) and makes WoW print raw escape codes.
-- Player-name class coloring is left to the 12.0 native chat system.
function NativeEnhancer:MessageFilter(chatFrame, event, ...)
  local ok, result, newMsg = pcall(function(...)
    local args = { ... }
    local msg = args[1]

    local Parser = ns.Parser
    if not Parser then return false end
    local message = Parser:Normalize(event, ...)
    if not message then return false end

    local Filters = ns.Filters
    if not Filters then return false end
    message.textRaw = msg
    Filters:Apply(message)
    local text = message.displayText or msg
    if text == msg then
      -- Nothing changed; leave the line untouched.
      return false
    end
    return true, text
  end, ...)

  -- On any error or no-op, do nothing (native display unaffected).
  if not ok or not result then
    local diag = ns.Core:GetModule("Diagnostics")
    if diag and diag.Error and not ok then diag:Error("NativeEnhancer", result) end
    return false
  end

  -- Rewrite only the message text; preserve every other arg (incl. sender).
  local args = { ... }
  args[1] = newMsg
  return false, unpack(args)
end
