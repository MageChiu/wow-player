local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils

function Commands:Init()
  SLASH_COMBATCOACH1 = "/cc"
  SLASH_COMBATCOACH2 = "/combatcoach"
  SlashCmdList["COMBATCOACH"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /cc            打开/关闭实时计量窗口（窗口开=采集，关=停止）")
  Utils.Print("  /cc analyze    分析当前查看的分段，弹出分析视图")
  Utils.Print("  /cc reset      清空本次采集的所有分段数据")
  Utils.Print("  /cc debug      打印采集诊断（定位为何没有数据）")
end

function Commands:Dispatch(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = (msg:match("^(%S*)") or ""):lower()

  if cmd == "" then
    if ns.MeterFrame then ns.MeterFrame:Toggle() end
  elseif cmd == "analyze" or cmd == "analysis" then
    if ns.MeterFrame then ns.MeterFrame:AnalyzeCurrent() end
  elseif cmd == "reset" or cmd == "clear" or cmd == "wipe" then
    ns.Segment:ResetAll()
    if ns.MeterFrame and ns.MeterFrame:IsShown() then ns.MeterFrame:Refresh() end
    Utils.Print("已清空采集数据。")
  elseif cmd == "debug" or cmd == "diag" then
    if ns.CombatLog and ns.CombatLog.DebugText then
      for _, line in ipairs(ns.CombatLog:DebugText()) do
        Utils.Print(line)
      end
    else
      Utils.Print("诊断不可用。")
    end
  else
    help()
  end
end
