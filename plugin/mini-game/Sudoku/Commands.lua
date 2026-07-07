local addonName, ns = ...

local Commands = {}
ns.Commands = ns.Core:RegisterModule("Commands", Commands)

local Utils = ns.Utils
local Const = ns.Constants

function Commands:Init()
  SLASH_SUDOKU1 = "/sudoku"
  SLASH_SUDOKU2 = "/sdk"
  SlashCmdList["SUDOKU"] = function(msg)
    ns.Core:SafeCall(function() Commands:Dispatch(msg) end)
  end
end

local function help()
  Utils.Print("命令:")
  Utils.Print("  /sudoku            打开/关闭数独窗口")
  Utils.Print("  /sudoku new [难度] 开始新局（easy/medium/hard 或 简单/中等/困难）")
  Utils.Print("  /sudoku hint       给选中格一个提示")
  Utils.Print("  /sudoku check      检查当前填写")
  Utils.Print("  /sudoku minimap    切换小地图按钮")
  Utils.Print("  /sudoku stats      查看各难度战绩")
  Utils.Print("  /sudoku reset      还原设置")
end

-- 把中文/英文难度词归一为难度 key。
local function parseDifficulty(word)
  if not word or word == "" then return nil end
  word = word:lower()
  local alias = {
    easy = "easy", ["简单"] = "easy",
    medium = "medium", ["中等"] = "medium", mid = "medium",
    hard = "hard", ["困难"] = "hard", ["难"] = "hard",
  }
  return alias[word] or (Const.DIFFICULTY_BY_KEY[word] and word) or nil
end

local function printStats()
  Utils.Print("战绩:")
  for _, d in ipairs(Const.DIFFICULTY) do
    local s = ns.Config:GetStats(d.key)
    if s and (s.wins or 0) > 0 then
      Utils.Print(string.format("  %s: 完成 %d 局，最佳 %s",
        d.label, s.wins, s.bestSeconds and Utils.FormatClock(s.bestSeconds) or "-"))
    else
      Utils.Print(string.format("  %s: 暂无完成记录", d.label))
    end
  end
end

function Commands:Dispatch(msg)
  msg = Utils.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()
  rest = Utils.Trim(rest or "")

  if cmd == "" then
    if ns.Board then ns.Board:Toggle() end
  elseif cmd == "new" or cmd == "newgame" then
    local key = parseDifficulty(rest)
    if ns.Board then ns.Board:RequestNewGame(key) end
  elseif cmd == "hint" then
    if ns.Board then ns.Board:Show(); ns.Board:Hint() end
  elseif cmd == "check" then
    if ns.Board then ns.Board:Show(); ns.Board:Check() end
  elseif cmd == "minimap" then
    if ns.MinimapButton then ns.MinimapButton:Toggle() end
  elseif cmd == "stats" then
    printStats()
  elseif cmd == "reset" then
    ns.Config:ResetProfile()
    Utils.Print("已还原设置。")
  else
    help()
  end
end
