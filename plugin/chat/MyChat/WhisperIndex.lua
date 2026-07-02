local addonName, ns = ...

local WhisperIndex = {}
ns.WhisperIndex = ns.Core:RegisterModule("WhisperIndex", WhisperIndex)

local C = ns.Constants
local Bus = ns.Bus
local Utils = ns.Utils

function WhisperIndex:Init()
  local runtime = ns.Config and ns.Config:GetRuntime()
  self.targets = (runtime and runtime.lastWhisperTargets) or {}

  Bus:On(C.TOPIC.MESSAGE_NORMALIZED, function(message)
    if not message or message.messageClass ~= C.CLASS.WHISPER then return end
    if not (ns.Config and ns.Config:Get("profile.enableWhisperIndex")) then return end
    self:Record(message)
  end)
end

-- Record the whisper counterpart (the other player) at the front of the list,
-- deduped and length-capped.
function WhisperIndex:Record(message)
  -- For incoming whispers the author is the target to reply to.
  -- For outgoing (WHISPER_INFORM) the author IS us; arg for target is the
  -- normalized author too (game reports the recipient there).
  local name = message.author
  if not name or name == "" then return end
  name = Utils.ShortName(name)

  local list = self.targets
  for i = #list, 1, -1 do
    if list[i] == name then table.remove(list, i) end
  end
  table.insert(list, 1, name)
  while #list > C.WHISPER_HISTORY_LIMIT do
    table.remove(list)
  end
end

function WhisperIndex:GetLastTarget()
  return self.targets and self.targets[1] or nil
end

-- Send a whisper to the most recent target. Deferred through CombatGuard so
-- it never fires a protected send during combat lockdown.
function WhisperIndex:ReplyLast(text)
  local target = self:GetLastTarget()
  if not target then
    Utils.Print("无最近密语对象。")
    return false
  end
  if type(text) ~= "string" or Utils.Trim(text) == "" then
    Utils.Print("用法: /mychat reply <内容>")
    return false
  end

  local guard = ns.CombatGuard
  local send = function()
    SendChatMessage(text, "WHISPER", nil, target)
  end
  if guard then
    guard:Run(send)
  else
    ns.Core:SafeCall(send)
  end
  return true
end
