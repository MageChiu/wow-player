local addonName, ns = ...

local Channels = {}
ns.Channels = ns.Core:RegisterModule("Channels", Channels)

local C = ns.Constants
local Bus = ns.Bus

local C_Timer = C_Timer

function Channels:Init()
  self.attempts = {}   -- channelName -> retry count
  self.pending = false

  Bus:On(C.TOPIC.ENTERING_WORLD, function()
    -- Throttle: PLAYER_ENTERING_WORLD can fire rapidly on zone changes.
    if self.pending then return end
    self.pending = true
    C_Timer.After(C.CHANNEL_JOIN_RETRY_INTERVAL, function()
      self.pending = false
      Channels:JoinConfigured()
    end)
  end)
end

local function isJoined(channelName)
  -- GetChannelName returns id 0 when not in the channel.
  local id = GetChannelName(channelName)
  return type(id) == "number" and id > 0
end

function Channels:JoinConfigured()
  local Config = ns.Config
  if not Config then return end
  local channels = Config:Get("profile.autoJoinChannels") or {}
  for _, name in ipairs(channels) do
    if type(name) == "string" and name ~= "" then
      self:EnsureJoined(name)
    end
  end
end

-- Join a channel if not already present, with bounded retries. Retries only
-- while the channel is still missing, so success stops the loop early.
function Channels:EnsureJoined(name)
  if isJoined(name) then
    self:_remember(name)
    self.attempts[name] = nil
    return
  end

  local count = (self.attempts[name] or 0)
  if count >= C.CHANNEL_JOIN_RETRY_LIMIT then
    self.attempts[name] = nil
    return
  end
  self.attempts[name] = count + 1

  JoinChannelByName(name)

  C_Timer.After(C.CHANNEL_JOIN_RETRY_INTERVAL, function()
    if not isJoined(name) then
      Channels:EnsureJoined(name)
    else
      Channels:_remember(name)
      Channels.attempts[name] = nil
    end
  end)
end

function Channels:_remember(name)
  local runtime = ns.Config and ns.Config:GetRuntime()
  if not runtime then return end
  runtime.joinedChannels = runtime.joinedChannels or {}
  for _, existing in ipairs(runtime.joinedChannels) do
    if existing == name then return end
  end
  table.insert(runtime.joinedChannels, name)
end
