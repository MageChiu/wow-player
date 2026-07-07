local addonName, ns = ...

-- 棋盘 UI：9x9 格 + 数字键盘 + 笔记/擦除/提示/检查 + 难度 + 计时器。
-- 输入同时支持鼠标（点格选中、点数字键盘填入）与键盘（1-9 填、0/退格擦、
-- 方向键移动、N 切笔记、H 提示、ESC 关闭）。
local Board = {}
ns.Board = ns.Core:RegisterModule("Board", Board)

local Utils = ns.Utils
local Const = ns.Constants

-- 布局常量。格子之间的细缝/宫之间的粗缝由深色底透出，形成网格线。
local CELL = 30
local THIN = 1
local THICK = 3
local MARGIN = 4
local BOARD_INNER = 9 * CELL + 6 * THIN + 2 * THICK   -- 288
local BOARD_SIZE = BOARD_INNER + 2 * MARGIN            -- 296

local FRAME_W = BOARD_SIZE + 24
local FRAME_H = BOARD_SIZE + 210

-- 颜色。
local COLOR = {
  boardBg   = { 0.15, 0.15, 0.17, 1 },     -- 网格线（缝隙透出的底）
  cellGiven = { 0.20, 0.20, 0.23, 1 },     -- 题目已知格底
  cellEmpty = { 0.10, 0.10, 0.12, 1 },     -- 可填格底
  selected  = { 0.30, 0.45, 0.65, 1 },     -- 选中格
  peer      = { 0.16, 0.20, 0.26, 1 },     -- 同行/列/宫
  sameDigit = { 0.24, 0.34, 0.30, 1 },     -- 同数字
  txtGiven  = { 0.95, 0.95, 0.95 },        -- 已知数字
  txtUser   = { 0.45, 0.75, 1.00 },        -- 玩家填入
  txtWrong  = { 1.00, 0.35, 0.35 },        -- 冲突/填错
  txtNote   = { 0.65, 0.65, 0.70 },
}

-- 计算第 i 行/列（1..9）相对棋盘内容左上角的像素偏移。
local function offset(i)
  local o = 0
  for k = 1, i - 1 do
    o = o + CELL + ((k % 3 == 0) and THICK or THIN)
  end
  return o
end

function Board:Init()
  -- 懒创建：首次打开时才建帧。
  self:_registerPopup()
end

-- 构建单个格子（Button）。索引为线性下标。
local function buildCell(parent, index)
  local r, c = Utils.RowCol(index)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(CELL, CELL)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", MARGIN + offset(c), -(MARGIN + offset(r)))

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(unpack(COLOR.cellEmpty))
  btn.bg = bg

  local text = btn:CreateFontString(nil, "OVERLAY")
  text:SetFont(STANDARD_TEXT_FONT, 16, "")
  text:SetPoint("CENTER")
  btn.text = text

  -- 3x3 铅笔笔记。
  btn.noteFS = {}
  for d = 1, 9 do
    local nr = math.floor((d - 1) / 3)
    local nc = (d - 1) % 3
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 8, "")
    fs:SetTextColor(unpack(COLOR.txtNote))
    fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 3 + nc * 9, -(2 + nr * 9))
    fs:SetText(d)
    fs:Hide()
    btn.noteFS[d] = fs
  end

  btn:RegisterForClicks("LeftButtonUp")
  btn:SetScript("OnClick", function()
    ns.Game:Select(index)
    Board:Refresh()
  end)

  return btn
end

function Board:_ensureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "SudokuBoard", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_W, FRAME_H)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("数独 Sudoku")

  local ver = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  ver:SetPoint("LEFT", title, "RIGHT", 8, 0)
  ver:SetText("v" .. Const.VERSION)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- 信息行：难度 / 计时 / 剩余。
  local info = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 14, -36)
  info:SetJustifyH("LEFT")
  f.info = info

  -- 棋盘容器（深色底作网格线）。
  local board = CreateFrame("Frame", nil, f)
  board:SetSize(BOARD_SIZE, BOARD_SIZE)
  board:SetPoint("TOP", 0, -54)
  local bbg = board:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(unpack(COLOR.boardBg))
  f.board = board

  f.cells = {}
  for i = 1, 81 do
    f.cells[i] = buildCell(board, i)
  end

  -- 胜利横幅。
  local wonBanner = board:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  wonBanner:SetPoint("CENTER")
  wonBanner:SetText("|cff40ff40完成!|r")
  wonBanner:Hide()
  f.wonBanner = wonBanner

  -- 数字键盘（1-9）。
  local padY = -(54 + BOARD_SIZE + 8)
  local padW = BOARD_SIZE
  local btnW = math.floor((padW - 8 * 2) / 9)
  f.numButtons = {}
  for d = 1, 9 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(btnW, 26)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (d - 1) * (btnW + 2), padY)
    b:SetText(d)
    b:SetScript("OnClick", function() Board:InputDigit(d) end)
    f.numButtons[d] = b
  end

  -- 操作行：笔记 / 擦除 / 提示 / 检查。
  local actY = padY - 32
  local aW = math.floor((BOARD_SIZE - 3 * 6) / 4)
  local notesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  notesBtn:SetSize(aW, 24)
  notesBtn:SetPoint("TOPLEFT", 12, actY)
  notesBtn:SetScript("OnClick", function() Board:ToggleNotesMode() end)
  f.notesBtn = notesBtn

  local eraseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  eraseBtn:SetSize(aW, 24)
  eraseBtn:SetPoint("LEFT", notesBtn, "RIGHT", 6, 0)
  eraseBtn:SetText("擦除")
  eraseBtn:SetScript("OnClick", function() Board:Erase() end)

  local hintBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  hintBtn:SetSize(aW, 24)
  hintBtn:SetPoint("LEFT", eraseBtn, "RIGHT", 6, 0)
  hintBtn:SetText("提示")
  hintBtn:SetScript("OnClick", function() Board:Hint() end)

  local checkBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  checkBtn:SetSize(aW, 24)
  checkBtn:SetPoint("LEFT", hintBtn, "RIGHT", 6, 0)
  checkBtn:SetText("检查")
  checkBtn:SetScript("OnClick", function() Board:Check() end)

  -- 难度行 + 新游戏。
  local diffY = actY - 30
  local dLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  dLabel:SetPoint("TOPLEFT", 14, diffY)
  dLabel:SetText("难度:")
  f.diffButtons = {}
  local prevAnchor = dLabel
  for _, d in ipairs(Const.DIFFICULTY) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(40, 22)
    b:SetPoint("LEFT", prevAnchor, "RIGHT", 4, 0)
    b:SetText(d.label)
    b:SetScript("OnClick", function() Board:RequestNewGame(d.key) end)
    f.diffButtons[d.key] = b
    prevAnchor = b
  end

  local newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  newBtn:SetSize(64, 22)
  newBtn:SetPoint("TOPRIGHT", -12, diffY)
  newBtn:SetText("新游戏")
  newBtn:SetScript("OnClick", function() Board:RequestNewGame() end)

  -- 统计行。
  local stats = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  stats:SetPoint("BOTTOMLEFT", 14, 10)
  stats:SetJustifyH("LEFT")
  f.stats = stats

  -- 键盘输入：默认放行，仅在我们处理时消费，避免影响聊天/移动。
  f:EnableKeyboard(true)
  f:SetPropagateKeyboardInput(true)
  f:SetScript("OnKeyDown", function(self, key)
    local handled = Board:OnKey(key)
    self:SetPropagateKeyboardInput(not handled)
  end)

  -- 计时器刷新（节流）。
  f.tick = 0
  f:SetScript("OnUpdate", function(self, elapsed)
    self.tick = self.tick + elapsed
    if self.tick < 0.5 then return end
    self.tick = 0
    Board:_updateInfo()
    -- 检查高亮到期后清除。
    if Board._flashUntil and GetTime() > Board._flashUntil then
      Board._flashUntil = nil
      Board._flash = nil
      Board:Refresh()
    end
  end)

  self.frame = f
  return f
end

-- 更新信息行与统计（不重绘整盘）。
function Board:_updateInfo()
  local f = self.frame
  if not f then return end
  if not ns.Game:HasGame() then
    f.info:SetText("点击下方难度开始一局。")
    return
  end
  local diff = Const.DIFFICULTY_BY_KEY[ns.Game:GetDifficulty()]
  local remain = ns.Game:RemainingCount()
  f.info:SetText(string.format("%s   |cffffd100%s|r   剩余 %d",
    diff and diff.label or "?", Utils.FormatClock(ns.Game:GetElapsed()), remain))
end

-- 全量重绘：格子底色、数字、笔记、键盘状态、难度高亮、统计。
function Board:Refresh()
  local f = self:_ensureFrame()
  local hasGame = ns.Game:HasGame()

  local sel = ns.Game:GetSelected()
  local selVal = sel and ns.Game:GetValue(sel) or 0
  local selR, selC, selB
  if sel then
    selR, selC = Utils.RowCol(sel)
    selB = math.floor((selR - 1) / 3) * 3 + math.floor((selC - 1) / 3)
  end

  for i = 1, 81 do
    local cell = f.cells[i]
    local v = hasGame and ns.Game:GetValue(i) or 0

    -- 底色优先级：选中 > 同数 > 同行列宫 > 题目/空。
    local bg = ns.Game:IsGiven(i) and COLOR.cellGiven or COLOR.cellEmpty
    if sel then
      local r, c = Utils.RowCol(i)
      local b = math.floor((r - 1) / 3) * 3 + math.floor((c - 1) / 3)
      if i == sel then
        bg = COLOR.selected
      elseif selVal ~= 0 and v == selVal then
        bg = COLOR.sameDigit
      elseif r == selR or c == selC or b == selB then
        bg = COLOR.peer
      end
    end
    cell.bg:SetColorTexture(unpack(bg))

    -- 数字与笔记。
    if v ~= 0 then
      cell.text:SetText(v)
      local color = COLOR.txtGiven
      if not ns.Game:IsGiven(i) then
        local wrong = ns.Game:IsConflict(i)
          or (ns.Config:Get("profile.showMistakes") and ns.Game:IsWrong(i))
          or (self._flash and self._flash[i])
        color = wrong and COLOR.txtWrong or COLOR.txtUser
      elseif self._flash and self._flash[i] then
        color = COLOR.txtWrong
      end
      cell.text:SetTextColor(unpack(color))
      for d = 1, 9 do cell.noteFS[d]:Hide() end
    else
      cell.text:SetText("")
      local notes = hasGame and ns.Game:GetNotes(i) or nil
      for d = 1, 9 do
        if notes and notes[d] then cell.noteFS[d]:Show() else cell.noteFS[d]:Hide() end
      end
    end
  end

  -- 键盘按钮：数字用满 9 个则置灰。
  for d = 1, 9 do
    local b = f.numButtons[d]
    if hasGame and ns.Game:DigitCount(d) >= 9 then
      b:Disable()
    else
      b:Enable()
    end
  end

  -- 笔记模式按钮文案。
  f.notesBtn:SetText(self._notesMode and "笔记:开" or "笔记:关")

  -- 难度按钮高亮当前难度。
  local cur = hasGame and ns.Game:GetDifficulty() or ns.Config:Get("profile.difficulty")
  for key, b in pairs(f.diffButtons) do
    if key == cur then b:LockHighlight() else b:UnlockHighlight() end
  end

  -- 胜利横幅。
  f.wonBanner:SetShown(hasGame and ns.Game:IsWon())

  -- 统计行。
  local s = ns.Config:GetStats(cur)
  if s and (s.wins or 0) > 0 then
    f.stats:SetText(string.format("%s 已完成 %d 局，最佳 %s",
      (Const.DIFFICULTY_BY_KEY[cur] and Const.DIFFICULTY_BY_KEY[cur].label or "?"),
      s.wins, s.bestSeconds and Utils.FormatClock(s.bestSeconds) or "-"))
  else
    f.stats:SetText("")
  end

  self:_updateInfo()
end

-- 输入一个数字（键盘或点数字键盘均走这里）。
function Board:InputDigit(d)
  if not ns.Game:HasGame() then return end
  local idx = ns.Game:GetSelected()
  if not idx or ns.Game:IsGiven(idx) then return end
  if self._notesMode then
    ns.Game:ToggleNote(idx, d)
  elseif ns.Game:GetValue(idx) == d then
    ns.Game:Clear(idx)          -- 再按一次相同数字＝擦除。
  else
    ns.Game:SetValue(idx, d)
  end
  self:Refresh()
end

function Board:Erase()
  local idx = ns.Game:GetSelected()
  if idx and not ns.Game:IsGiven(idx) then
    ns.Game:Clear(idx)
    self:Refresh()
  end
end

function Board:Hint()
  local target = ns.Game:Hint(ns.Game:GetSelected())
  if target then
    ns.Game:Select(target)
    self:Refresh()
  end
end

-- 检查：标出所有填错的格子（红色闪 3 秒）。
function Board:Check()
  local mistakes = ns.Game:FindMistakes()
  if #mistakes == 0 then
    Utils.Print("目前没有发现错误。")
    self._flash = nil
    self._flashUntil = nil
  else
    self._flash = {}
    for _, i in ipairs(mistakes) do self._flash[i] = true end
    self._flashUntil = (GetTime and GetTime() or 0) + 3
    Utils.Print(string.format("发现 %d 处错误，已标红。", #mistakes))
  end
  self:Refresh()
end

function Board:ToggleNotesMode()
  self._notesMode = not self._notesMode
  self:Refresh()
end

function Board:MoveSelection(dr, dc)
  local idx = ns.Game:GetSelected() or 1
  local r, c = Utils.RowCol(idx)
  r = math.min(9, math.max(1, r + dr))
  c = math.min(9, math.max(1, c + dc))
  ns.Game:Select(Utils.Index(r, c))
  self:Refresh()
end

-- 键盘分发。返回 true 表示"已消费"（阻止透传到动作条/移动）。
function Board:OnKey(key)
  if not self.frame or not self.frame:IsShown() then return false end

  if key == "ESCAPE" then
    self:Hide()
    return true
  end

  local d = tonumber(key)
  if d and d >= 1 and d <= 9 then
    if ns.Game:HasGame() and ns.Game:GetSelected() then
      self:InputDigit(d)
      return true
    end
    return false
  end

  if key == "0" or key == "BACKSPACE" or key == "DELETE" then
    if ns.Game:GetSelected() then self:Erase(); return true end
    return false
  end

  if not ns.Game:GetSelected() then return false end
  if key == "UP" then self:MoveSelection(-1, 0); return true end
  if key == "DOWN" then self:MoveSelection(1, 0); return true end
  if key == "LEFT" then self:MoveSelection(0, -1); return true end
  if key == "RIGHT" then self:MoveSelection(0, 1); return true end
  if key == "N" then self:ToggleNotesMode(); return true end
  if key == "H" then self:Hint(); return true end

  return false
end

-- 新游戏：进行中且未完成时弹确认，避免误丢进度。
function Board:RequestNewGame(difficultyKey)
  if ns.Game:HasGame() and not ns.Game:IsWon() and ns.Game:RemainingCount() > 0 then
    Board._pendingDiff = difficultyKey
    StaticPopup_Show("SUDOKU_NEW_GAME_CONFIRM")
  else
    self:StartNewGame(difficultyKey)
  end
end

function Board:StartNewGame(difficultyKey)
  self._flash = nil
  self._flashUntil = nil
  ns.Game:NewGame(difficultyKey)
  self:Show()
  self:Refresh()
end

-- 供 Game 胜利时回调。
function Board:OnWin()
  self:Refresh()
end

function Board:Toggle()
  local f = self:_ensureFrame()
  if f:IsShown() then
    f:Hide()
  else
    self:Refresh()
    f:Show()
  end
end

function Board:Show()
  local f = self:_ensureFrame()
  self:Refresh()
  f:Show()
end

function Board:Hide()
  if self.frame then self.frame:Hide() end
end

-- 确认弹窗（延迟注册到 Init，确保 StaticPopupDialogs 存在）。
function Board:_registerPopup()
  if StaticPopupDialogs and not StaticPopupDialogs["SUDOKU_NEW_GAME_CONFIRM"] then
    StaticPopupDialogs["SUDOKU_NEW_GAME_CONFIRM"] = {
      text = "当前对局尚未完成，开始新游戏将放弃进度。确定吗？",
      button1 = "开始新局",
      button2 = "取消",
      OnAccept = function() Board:StartNewGame(Board._pendingDiff) end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end
end
