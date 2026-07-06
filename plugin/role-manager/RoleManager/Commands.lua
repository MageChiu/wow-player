local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils

function Commands:Init()
  SLASH_ROLEMANAGER1 = "/rm"
  SLASH_ROLEMANAGER2 = "/rolemanager"
  SlashCmdList["ROLEMANAGER"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /rm                打开/关闭角色汇总窗口")
  Utils.Print("  /rm config         打开设置（勾选货币/隐藏角色）")
  Utils.Print("  /rm text           在聊天框打印文本汇总")
  Utils.Print("  /rm scan           刷新当前角色数据")
  Utils.Print("  /rm minimap        切换小地图按钮")
  Utils.Print("  /rm addcur <ID>    手动添加追踪货币")
  Utils.Print("  /rm delcur <ID>    移除追踪货币")
  Utils.Print("  /rm curlist        列出当前追踪的货币")
  Utils.Print("  /rm addquest <ID>  添加每周任务追踪")
  Utils.Print("  /rm reset          还原设置（保留角色缓存）")
  Utils.Print("  /rm wipe           清空所有角色缓存")
end

-- 文本汇总：把各角色关键数据打印到聊天框。
local function printText()
  local Store = ns.Store
  Utils.Print("===== 角色汇总 =====")
  local warband, warbandAt = Store:GetWarbandMoney()
  if warband then
    Utils.Print("战团银行金币: " .. Utils.FormatMoney(warband) ..
      " |cff808080(" .. Utils.AgoText(warbandAt) .. ")|r")
  end
  Utils.Print("角色金币合计: " .. Utils.FormatMoney(Store:GetGoldTotal()))

  local chars = Store:GetCharacters()
  if #chars == 0 then
    Utils.Print("暂无角色数据，登录各角色一次即可记录。")
    return
  end
  for _, rec in ipairs(chars) do
    local name = Utils.ShortName(rec.name) or "?"
    Utils.Print(string.format("%s-%s | 金:%s | 秘:%s | 钥:%s | 团:%s | 库:%s | 周:%s | %s",
      name, rec.realm or "?",
      Utils.FormatMoney(rec.money or 0),
      Store:MythicText(rec),
      Store:KeystoneText(rec),
      Store:RaidText(rec),
      Store:VaultText(rec),
      Store:WeeklyQuestText(rec),
      Utils.AgoText(rec.updatedAt)))
    -- 代币逐个列出。
    if rec.currencies and next(rec.currencies) then
      local parts = {}
      for _, info in pairs(rec.currencies) do
        parts[#parts + 1] = string.format("%s:%d", info.name or "?", info.quantity or 0)
      end
      Utils.Print("    代币: " .. table.concat(parts, "  "))
    end
  end
end

local function addCurrency(idStr)
  local id = tonumber(idStr)
  if not id then Utils.Print("请提供货币 ID，如 /rm addcur 3008"); return end
  local list = ns.Config:Get("profile.trackedCurrencies") or {}
  for _, v in ipairs(list) do
    if v == id then Utils.Print("该货币已在追踪列表中。"); return end
  end
  list[#list + 1] = id
  ns.Config:Set("profile.trackedCurrencies", list)
  ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
  local name = "?"
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if ok and type(info) == "table" and info.name then name = info.name end
  end
  Utils.Print(string.format("已追踪货币 %d（%s）。", id, name))
end

local function delCurrency(idStr)
  local id = tonumber(idStr)
  if not id then Utils.Print("请提供货币 ID。"); return end
  local list = ns.Config:Get("profile.trackedCurrencies") or {}
  for i, v in ipairs(list) do
    if v == id then
      table.remove(list, i)
      ns.Config:Set("profile.trackedCurrencies", list)
      Utils.Print("已移除货币 " .. id .. "。")
      return
    end
  end
  Utils.Print("追踪列表中没有货币 " .. id .. "。")
end

local function listCurrencies()
  local list = ns.Config:Get("profile.trackedCurrencies") or {}
  if #list == 0 then Utils.Print("当前未追踪任何货币。用 /rm addcur <ID> 添加。"); return end
  Utils.Print("追踪的货币:")
  for _, id in ipairs(list) do
    local name = "?"
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
      local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
      if ok and type(info) == "table" and info.name then name = info.name end
    end
    Utils.Print(string.format("  %d - %s", id, name))
  end
end

local function addQuest(idStr)
  local id = tonumber(idStr)
  if not id then Utils.Print("请提供任务 ID，如 /rm addquest 82946"); return end
  local quests = ns.Config:Get("profile.weeklyQuests") or {}
  quests[id] = true
  ns.Config:Set("profile.weeklyQuests", quests)
  ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
  Utils.Print("已追踪每周任务 " .. id .. "。")
end

function Commands:Dispatch(msg)
  msg = Utils.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    if ns.OverviewFrame then ns.OverviewFrame:Toggle() end
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    if ns.SettingsPanel then ns.SettingsPanel:Toggle() end
  elseif cmd == "text" or cmd == "print" then
    printText()
  elseif cmd == "scan" or cmd == "refresh" then
    ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
    if ns.OverviewFrame and ns.OverviewFrame.frame and ns.OverviewFrame.frame:IsShown() then
      ns.OverviewFrame:Refresh()
    end
    Utils.Print("已刷新当前角色数据。")
  elseif cmd == "minimap" then
    if ns.MinimapButton then ns.MinimapButton:Toggle() end
  elseif cmd == "addcur" then
    addCurrency(rest)
  elseif cmd == "delcur" then
    delCurrency(rest)
  elseif cmd == "curlist" then
    listCurrencies()
  elseif cmd == "addquest" then
    addQuest(rest)
  elseif cmd == "reset" then
    ns.Config:ResetProfile()
    Utils.Print("已还原设置，请 /reload 使全部生效。")
  elseif cmd == "wipe" then
    ns.Config:WipeChars()
    ns.Core:SafeCall(function() ns.Collector:CollectSelf() end)
    Utils.Print("已清空角色缓存，仅保留当前角色。")
  elseif cmd == "help" then
    help()
  else
    help()
  end
end
