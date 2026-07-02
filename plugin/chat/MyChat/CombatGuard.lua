local addonName, ns = ...

local CombatGuard = {}
ns.CombatGuard = ns.Core:RegisterModule("CombatGuard", CombatGuard)

local C = ns.Constants
local Bus = ns.Bus
local Core = ns.Core

function CombatGuard:Init()
  self.inCombat = InCombatLockdown() and true or false
  self.deferred = {}

  Bus:On(C.TOPIC.COMBAT_ENTER, function()
    self.inCombat = true
  end)
  Bus:On(C.TOPIC.COMBAT_LEAVE, function()
    self.inCombat = false
    self:FlushDeferred()
  end)
end

function CombatGuard:InCombat()
  -- Trust the live API over cached flag when available.
  if InCombatLockdown() then return true end
  return self.inCombat
end

-- Run fn now if out of combat, otherwise queue it until PLAYER_REGEN_ENABLED.
-- All UI-structure and message-send operations must go through this.
function CombatGuard:Run(fn)
  if type(fn) ~= "function" then return end
  if self:InCombat() then
    self.deferred[#self.deferred + 1] = fn
    return false
  end
  Core:SafeCall(fn)
  return true
end

function CombatGuard:FlushDeferred()
  if not self.deferred or #self.deferred == 0 then return end
  local queue = self.deferred
  self.deferred = {}
  for i = 1, #queue do
    Core:SafeCall(queue[i])
  end
end

function CombatGuard:PendingCount()
  return self.deferred and #self.deferred or 0
end
