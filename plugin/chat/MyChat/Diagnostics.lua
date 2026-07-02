local addonName, ns = ...

local Diagnostics = {}
ns.Diagnostics = ns.Core:RegisterModule("Diagnostics", Diagnostics)

local C = ns.Constants
local Bus = ns.Bus

function Diagnostics:Init()
  self.errorCount = 0
  self.byScope = {}
  self.lastErrors = {}
  self.recentMessages = {}

  -- Keep a rolling summary of normalized messages for /mychat debug.
  if Bus then
    Bus:On(C.TOPIC.MESSAGE_NORMALIZED, function(message)
      if not message then return end
      local line = string.format("%s <%s> %s",
        C.CHANNEL_ABBREV[message.messageClass] or "?",
        tostring(message.author or "-"),
        tostring(message.textPlain or ""))
      local rm = self.recentMessages
      rm[#rm + 1] = line
      while #rm > 5 do table.remove(rm, 1) end
    end)
  end
end

function Diagnostics:Error(scope, err)
  self.errorCount = (self.errorCount or 0) + 1
  scope = scope or "?"
  self.byScope[scope] = (self.byScope[scope] or 0) + 1

  local le = self.lastErrors
  le[#le + 1] = string.format("[%s] %s", scope, tostring(err))
  while #le > 5 do table.remove(le, 1) end

  if self:ShouldDegrade() and ns.Config then
    -- Auto-degrade to safe mode when errors pile up.
    ns.Config:Set("profile.safeMode", true)
  end
end

function Diagnostics:ShouldDegrade()
  return (self.errorCount or 0) >= C.ERROR_DEGRADE_THRESHOLD
end

function Diagnostics:Dump()
  local lines = {}
  lines[#lines + 1] = "=== MyChat 诊断 ==="
  lines[#lines + 1] = "版本: " .. C.VERSION

  local Core = ns.Core
  lines[#lines + 1] = "模块: " .. table.concat(Core:ModuleStatus(), ", ")

  local guard = ns.CombatGuard
  if guard then
    lines[#lines + 1] = string.format("战斗中: %s | 延迟队列: %d",
      tostring(guard:InCombat()), guard:PendingCount())
  end

  local safeMode = ns.Config and ns.Config:Get("profile.safeMode")
  lines[#lines + 1] = "安全模式: " .. tostring(safeMode)

  lines[#lines + 1] = string.format("错误总数: %d (降级阈值 %d)",
    self.errorCount or 0, C.ERROR_DEGRADE_THRESHOLD)
  for scope, n in pairs(self.byScope) do
    lines[#lines + 1] = string.format("  %s: %d", scope, n)
  end

  if #self.lastErrors > 0 then
    lines[#lines + 1] = "最近错误:"
    for _, e in ipairs(self.lastErrors) do
      lines[#lines + 1] = "  " .. e
    end
  end

  local runtime = ns.Config and ns.Config:GetRuntime()
  if runtime and runtime.joinedChannels then
    lines[#lines + 1] = "已加入频道: " .. table.concat(runtime.joinedChannels, ", ")
  end

  if #self.recentMessages > 0 then
    lines[#lines + 1] = "最近消息:"
    for _, m in ipairs(self.recentMessages) do
      lines[#lines + 1] = "  " .. m
    end
  end

  return table.concat(lines, "\n")
end
