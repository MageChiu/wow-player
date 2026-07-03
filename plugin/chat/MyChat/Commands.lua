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
  Utils.Print("  /mychat            显示此帮助")
  Utils.Print("  /mychat config     打开设置面板")
  Utils.Print("  /mychat bar        切换频道切换条显示")
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
    -- 空命令始终打印帮助，保证 /mychat 一定有可见反馈。
    help()
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    local panel = ns.SettingsPanel
    if panel and panel.Open then
      local opened = panel:Open()
      if opened == false then
        Utils.Print("无法打开设置面板（当前客户端不支持），请用命令调整，如 /mychat bar。")
      end
    else
      Utils.Print("设置面板未加载。")
    end
  elseif cmd == "bar" then
    local cbar = ns.ChannelBar
    if cbar and cbar.Toggle then
      cbar:Toggle()
      local on = ns.Config and ns.Config:Get("profile.channelBarEnabled")
      Utils.Print("频道切换条已" .. (on and "开启" or "关闭") .. "。")
    else
      Utils.Print("频道切换条未加载。")
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
