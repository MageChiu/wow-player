local addonName, ns = ...

local Router = {}
ns.Router = ns.Core:RegisterModule("Router", Router)

local C = ns.Constants

-- messageClass -> logical view tags. A message may map to several views.
local CLASS_TO_VIEWS = {
  [C.CLASS.WORLD] = { "world" },
  [C.CLASS.TRADE] = { "trade" },
  [C.CLASS.CHANNEL] = { "channel" },
  [C.CLASS.PARTY] = { "party" },
  [C.CLASS.RAID] = { "party" },
  [C.CLASS.INSTANCE] = { "party" },
  [C.CLASS.GUILD] = { "guild" },
  [C.CLASS.WHISPER] = { "whisper" },
  [C.CLASS.SYSTEM] = { "system" },
}

function Router:Init()
  -- Stateless; nothing to initialize beyond registration.
end

-- Return the list of logical view tags for a message. When routing is
-- disabled this returns an empty list so no consumer changes behavior.
function Router:Route(message)
  if not message then return {} end
  if not (ns.Config and ns.Config:Get("profile.routeWorldTradeParty")) then
    return {}
  end
  local views = CLASS_TO_VIEWS[message.messageClass]
  if not views then return { "other" } end
  -- Return a copy so callers cannot mutate the shared table.
  local out = {}
  for i = 1, #views do out[i] = views[i] end
  return out
end
