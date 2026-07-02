local addonName, ns = ...

local Events = {}
ns.Events = ns.Core:RegisterModule("Events", Events)

local C = ns.Constants
local Bus = ns.Bus

local chatEventLookup = {}

function Events:Init()
  self.frame = CreateFrame("Frame")

  for _, event in ipairs(C.CHAT_EVENTS) do
    chatEventLookup[event] = true
    self.frame:RegisterEvent(event)
  end
  for _, event in ipairs(C.LIFECYCLE_EVENTS) do
    self.frame:RegisterEvent(event)
  end

  self.frame:SetScript("OnEvent", function(_, event, ...)
    Events:OnEvent(event, ...)
  end)
end

-- Register an extra WoW event and route it to a handler. Kept for later
-- batches (e.g. channel restore) that need bespoke events.
function Events:Register(event, handler)
  if not self.frame then return end
  self.extra = self.extra or {}
  self.extra[event] = handler
  self.frame:RegisterEvent(event)
end

function Events:OnEvent(event, ...)
  if chatEventLookup[event] then
    -- Pack varargs so downstream parser sees the original CHAT_MSG_* args.
    Bus:Emit(C.TOPIC.MESSAGE_RAW, { event = event, args = { ... } })
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    Bus:Emit(C.TOPIC.COMBAT_ENTER)
  elseif event == "PLAYER_REGEN_ENABLED" then
    Bus:Emit(C.TOPIC.COMBAT_LEAVE)
  elseif event == "PLAYER_LOGIN" then
    Bus:Emit(C.TOPIC.PLAYER_LOGIN)
  elseif event == "PLAYER_ENTERING_WORLD" then
    Bus:Emit(C.TOPIC.ENTERING_WORLD, { ... })
  end

  if self.extra and self.extra[event] then
    ns.Core:SafeCall(self.extra[event], ...)
  end
end
