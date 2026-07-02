local addonName, ns = ...

local Bus = {}
ns.Bus = ns.Core:RegisterModule("Bus", Bus)

local Core = ns.Core

function Bus:Init()
  self.subscribers = {}
  self.recent = {}       -- ring buffer of recent raw events for /mychat debug
  self.recentMax = 5
end

function Bus:On(topic, handler)
  if type(topic) ~= "string" or type(handler) ~= "function" then return end
  local list = self.subscribers[topic]
  if not list then
    list = {}
    self.subscribers[topic] = list
  end
  list[#list + 1] = handler
end

-- Synchronous dispatch. Each handler is isolated via SafeCall so one
-- failing subscriber cannot break the chain.
function Bus:Emit(topic, payload)
  if ns.Constants.TOPIC.MESSAGE_RAW == topic then
    self:_recordRecent(payload)
  end
  local list = self.subscribers[topic]
  if not list then return end
  for i = 1, #list do
    local handler = list[i]
    Core:SafeCall(handler, payload)
  end
end

function Bus:_recordRecent(payload)
  local event = payload and payload.event or "?"
  local first = payload and payload.args and payload.args[1]
  local summary = string.format("[%s] %s", tostring(event), tostring(first or ""))
  local recent = self.recent
  recent[#recent + 1] = summary
  while #recent > self.recentMax do
    table.remove(recent, 1)
  end
end

function Bus:DebugRecent()
  local out = { "recent raw events:" }
  if not self.recent or #self.recent == 0 then
    out[#out + 1] = "  (none)"
    return out
  end
  for _, line in ipairs(self.recent) do
    out[#out + 1] = "  " .. line
  end
  return out
end
