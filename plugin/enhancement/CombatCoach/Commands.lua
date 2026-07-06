local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils
local Const = ns.Constants

function Commands:Init()
  SLASH_COMBATCOACH1 = "/cc"
  SLASH_COMBATCOACH2 = "/combatcoach"
  SlashCmdList["COMBATCOACH"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /cc            打开/关闭最近一场战斗复盘")
  Utils.Print("  /cc last       在聊天框打印最近一场摘要")
  Utils.Print("  /cc history    列出最近的战斗记录")
  Utils.Print("  /cc show <N>   打开列表中第 N 场的复盘")
  Utils.Print("  /cc auto       切换战斗结束自动弹窗")
  Utils.Print("  /cc boss       切换仅首领战分析")
  Utils.Print("  /cc wipe       清空历史记录")
  Utils.Print("  /cc reset      还原设置（保留历史）")
end

-- 把一份报告的摘要 + 改进点打印到聊天框。
local function printReport(report)
  if not report then
    Utils.Print("暂无战斗数据。打一场架后再看。")
    return
  end
  local m = report.metrics or {}
  Utils.Print("===== 最近战斗复盘 =====")
  Utils.Print(string.format("对象:%s 时长:%s DPS:%s HPS:%s DTPS:%s",
    report.bossName or "战斗",
    Utils.Duration(report.duration or 0),
    Utils.Short(m.dps or 0), Utils.Short(m.hps or 0), Utils.Short(m.dtps or 0)))
  local sugs = report.suggestions or {}
  if #sugs == 0 then
    Utils.Print("没有发现明显问题，保持！")
    return
  end
  for _, s in ipairs(sugs) do
    local color = Const.SEVERITY_COLOR[s.severity or 1] or "ffffffff"
    Utils.Print(Utils.ColorText(color, "● " .. (s.text or "")))
  end
end

local function printHistory()
  local hist = ns.Store:GetHistory()
  if #hist == 0 then
    Utils.Print("暂无历史记录。")
    return
  end
  Utils.Print("最近战斗（新→旧）:")
  for i, report in ipairs(hist) do
    Utils.Print("  " .. ns.Store:SummaryLine(report, i))
  end
  Utils.Print("用 /cc show <N> 查看某场详情。")
end

function Commands:Dispatch(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    if ns.ReportFrame then ns.ReportFrame:Toggle() end
  elseif cmd == "last" or cmd == "print" then
    printReport(ns.Store:GetLast())
  elseif cmd == "history" or cmd == "list" then
    printHistory()
  elseif cmd == "show" then
    local report = ns.Store:GetAt(tonumber(rest))
    if report and ns.ReportFrame then
      ns.ReportFrame:ShowReport(report)
    else
      Utils.Print("没有第 " .. tostring(rest) .. " 场记录。用 /cc history 查看。")
    end
  elseif cmd == "auto" then
    local v = not ns.Config:Get("profile.autoShowReport")
    ns.Config:Set("profile.autoShowReport", v)
    Utils.Print("战斗结束自动弹窗: " .. (v and "开" or "关"))
  elseif cmd == "boss" then
    local v = not ns.Config:Get("profile.onlyBossFights")
    ns.Config:Set("profile.onlyBossFights", v)
    Utils.Print("仅首领战分析: " .. (v and "开" or "关"))
  elseif cmd == "wipe" then
    ns.Config:WipeHistory()
    Utils.Print("已清空历史记录。")
  elseif cmd == "reset" then
    ns.Config:ResetProfile()
    Utils.Print("已还原设置，请 /reload 使全部生效。")
  else
    help()
  end
end
