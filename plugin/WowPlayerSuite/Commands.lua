local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils

function Commands:Init()
  SLASH_WOWPLAYERSUITE1 = "/wp"
  SLASH_WOWPLAYERSUITE2 = "/wowplayer"
  SlashCmdList["WOWPLAYERSUITE"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /wp            打开/关闭整合面板")
  Utils.Print("  /wp settings   打开整合面板")
  Utils.Print("  /wp list       在聊天框列出已接入插件")
  Utils.Print("  /wp minimap    切换小地图按钮")
  Utils.Print("  /wp help       显示此帮助")
end

local function listPlugins()
  local list = ns.Discovery:GetOrdered()
  if #list == 0 then
    Utils.Print("暂无已接入的插件。")
    return
  end
  Utils.Print("已接入插件:")
  for _, desc in ipairs(list) do
    Utils.Print(string.format("  %s %s", desc.title or "?", desc.version and ("v" .. desc.version) or ""))
  end
end

function Commands:Dispatch(msg)
  msg = Utils.Trim(msg or "")
  local cmd = (msg:match("^(%S*)") or ""):lower()

  if cmd == "" or cmd == "settings" or cmd == "options" then
    if ns.MainFrame then ns.MainFrame:Toggle() end
  elseif cmd == "list" then
    listPlugins()
  elseif cmd == "minimap" then
    if ns.MinimapButton then ns.MinimapButton:Toggle() end
  else
    help()
  end
end
