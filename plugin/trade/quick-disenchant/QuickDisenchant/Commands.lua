local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils

function Commands:Init()
  SLASH_QUICKDISENCHANT1 = "/qde"
  SLASH_QUICKDISENCHANT2 = "/quickdisenchant"
  SlashCmdList["QUICKDISENCHANT"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /qde                打开/关闭分解面板")
  Utils.Print("  /qde config         打开设置（品质分级/行为）")
  Utils.Print("  /qde scan           重新扫描背包")
  Utils.Print("  /qde minimap        切换小地图按钮")
  Utils.Print("  /qde never <ID>     把物品加入永不分解白名单")
  Utils.Print("  /qde unnever <ID>   从白名单移除")
  Utils.Print("  /qde neverlist      查看白名单")
  Utils.Print("  /qde reset          还原设置")
end

local function addNever(idStr)
  local id = tonumber(idStr)
  if not id then Utils.Print("请提供物品 ID，如 /qde never 12345"); return end
  ns.Config:SetNeverListed(id, true)
  Utils.Print("已把物品 " .. id .. " 加入永不分解白名单。")
  if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsShown() then ns.Panel:Refresh() end
end

local function removeNever(idStr)
  local id = tonumber(idStr)
  if not id then Utils.Print("请提供物品 ID。"); return end
  ns.Config:SetNeverListed(id, false)
  Utils.Print("已从白名单移除物品 " .. id .. "。")
  if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsShown() then ns.Panel:Refresh() end
end

local function listNever()
  local list = ns.Config:GetNeverList()
  local ids = {}
  for id in pairs(list) do ids[#ids + 1] = id end
  if #ids == 0 then Utils.Print("白名单为空。"); return end
  table.sort(ids)
  Utils.Print("永不分解白名单:")
  for _, id in ipairs(ids) do
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or nil
    Utils.Print(string.format("  %d%s", id, name and (" - " .. name) or ""))
  end
end

function Commands:Dispatch(msg)
  msg = Utils.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    if ns.Panel then ns.Panel:Toggle() end
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    if ns.SettingsPanel then ns.SettingsPanel:Toggle() end
  elseif cmd == "scan" or cmd == "refresh" then
    if ns.Panel then ns.Panel:Open() end
  elseif cmd == "minimap" then
    if ns.MinimapButton then ns.MinimapButton:Toggle() end
  elseif cmd == "never" then
    addNever(rest)
  elseif cmd == "unnever" then
    removeNever(rest)
  elseif cmd == "neverlist" then
    listNever()
  elseif cmd == "reset" then
    ns.Config:ResetProfile()
    Utils.Print("已还原设置，请 /reload 使全部生效。")
  else
    help()
  end
end
