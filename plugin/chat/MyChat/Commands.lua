local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils

function Commands:Init()
  SLASH_MYCHAT1 = "/mychat"
  SlashCmdList["MYCHAT"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /mychat            打开设置")
  Utils.Print("  /mychat debug      输出诊断信息")
  Utils.Print("  /mychat reset      恢复默认设置")
  Utils.Print("  /mychat safe       开启安全模式")
  Utils.Print("  /mychat reply <内容>  回复最近密语")
end

function Commands:Dispatch(msg)
  msg = Utils.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    local panel = ns.SettingsPanel
    if panel and panel.Open then
      panel:Open()
    else
      help()
    end
  elseif cmd == "debug" then
    local diag = ns.Diagnostics
    if diag and diag.Dump then
      Utils.Print(diag:Dump())
    else
      Utils.Print("诊断模块未加载。")
    end
  elseif cmd == "reset" then
    if ns.Config then
      ns.Config:ResetProfile()
      Utils.Print("已恢复默认设置，请 /reload 使全部生效。")
    end
  elseif cmd == "safe" then
    if ns.Config then
      ns.Config:Set("profile.safeMode", true)
      Utils.Print("已开启安全模式，仅保留只读增强。")
    end
  elseif cmd == "reply" then
    local wi = ns.WhisperIndex
    if wi and wi.ReplyLast then
      wi:ReplyLast(rest)
    else
      Utils.Print("密语索引未启用。")
    end
  else
    help()
  end
end
