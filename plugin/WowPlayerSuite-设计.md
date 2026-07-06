# WowPlayerSuite 整合包设计

> 状态：**设计（Design）阶段产出，待用户确认后进入实现**。遵循 [开发协作规范](chat/开发协作规范.md)：先聊清楚、达成一致再动手。
>
> 本文只描述"整合包（Hub）"这一层的设计，不改变任何现有插件的运行逻辑。

---

## 1. 目标与非目标

### 目标
- 提供一个可选的中枢插件 **WowPlayerSuite**（命令 `/wp`），在游戏内统一：
  1. **统一设置入口**：一个窗口，侧栏列出已接入的插件，点进去打开各插件自己的设置。
  2. **统一入口按钮/命令**：一个 `/wp` 命令 + 一个小地图按钮。
  3. **插件启停管理**：勾选启用/禁用子插件（受 WoW 限制，需 `/reload` 生效）。
  4. **整包打包/升级**：一个总打包脚本产出含全部插件的 zip，一个套件版本号；可选做"版本落后提示"。

### 非目标（明确不做）
- **不做共享配置层**：不存在 `WowPlayerSuiteDB` 保管的"公共值"。唯一真相源永远在各插件自己的 DB（`MyChatDB`/`RoleManagerDB`/`CombatCoachDB`）。Hub 只是各插件配置的"遥控器/编辑器"——读它们的、写它们的，不留副本。
- **不做游戏内自动下载更新**：WoW 插件无法自更新，升级靠重新安装整包。
- **不合并成单体**：三个插件仍可各自独立安装、独立使用。

### 贯穿原则（与现有规范一致）
- **可选依赖，独立零影响**：拿掉 Hub，任何子插件的读写路径一个字节都不改，行为和今天完全一致。
- **增强而不接管**：Hub 是被动的聚合器，插件不"迎合"Hub，只被动暴露可被调用的能力。
- **错误隔离**：Hub 侧所有对插件回调的调用用 `pcall` 包裹，单个插件出错不拖垮整个窗口。

---

## 2. 架构总览

```
Interface/AddOns/
├── WowPlayerSuite/     ← 新增。中枢：注册表 + 统一窗口 + /wp + 小地图按钮 + 启停
├── MyChat/             ← 现有，加一段"存在 Hub 就上报自己"的注册代码
├── RoleManager/        ← 同上
└── CombatCoach/        ← 同上（目前仅 toc + Constants，接入代码随实现一并加）
```

- 子插件与 Hub **谁先加载都不能出错**。靠一个不依赖加载顺序的全局注册表（下节）解决。
- `.toc` 里 Hub 对子插件用 `## OptionalDeps`，子插件对 Hub **不写任何依赖**（保持独立可发）。

---

## 3. 注册协议

### 3.1 全局握手对象

Hub 与子插件之间只通过一个全局表通信。为避免加载顺序问题，**任何一方先创建它都可以**：

```lua
-- 约定的全局命名空间。Hub 与子插件都用这一段"若无则建"的守卫。
WowPlayerSuiteAPI = WowPlayerSuiteAPI or {
  _pending = {},          -- Hub 尚未加载时，子插件先把注册信息塞这里
  _registered = {},       -- 已被 Hub 接收的插件描述符（title -> descriptor）
}
```

- **子插件调用** `WowPlayerSuiteAPI:Register(descriptor)`：把自己的描述符登记进去。
- **Hub 加载后** 提供真正的 `Register` 实现，并把 `_pending` 里已有的补登记。
- 因此子插件**不需要判断 Hub 在不在**，只管调 `Register`；Hub 在就即时接收，不在就进 `_pending` 等 Hub 来收。

> 也可选更简单的写法：子插件用 `if WowPlayerSuite then WowPlayerSuite:Register(...) end` 直接判断（见 4.1）。两种都可，握手对象方式对加载顺序更鲁棒。**本设计采用握手对象方式作为主方案。**

### 3.2 插件描述符（descriptor）

子插件注册时提交的表。所有字段除 `title` 外均可选——Hub 对缺失字段降级处理（对应能力不显示即可）。

```lua
{
  title       = "MyChat",              -- [必填] 显示名，也用作唯一键
  version     = "0.1.1",               -- [可选] 展示用，取自各自 Constants.VERSION
  slashCmd    = "/mychat",             -- [可选] 展示"独立命令"提示

  -- [可选] 打开该插件自己的设置面板。Hub 侧栏点击时调用。
  -- 各插件内部差异（MyChat 用 Open()、RoleManager 用 Toggle()）被这个闭包吸收。
  openSettings = function() ... end,

  -- [可选] 小地图按钮受控能力。仅有小地图按钮的插件提供。
  -- show=false 时隐藏自己的按钮（写入插件自己的配置并即时生效）。
  setMinimapShown = function(show) ... end,
  getMinimapShown = function() return true/false end,

  -- [可选] 配置导入导出（A 档能力，用于备份/迁移）。
  -- exportConfig 返回一个可序列化的 table（插件自己的 profile 快照）。
  -- importConfig 接收同结构 table，写回插件自己的配置。
  exportConfig = function() return table end,
  importConfig = function(tbl) ... end,
}
```

### 3.3 Hub 侧接收契约

```lua
function WowPlayerSuite:Register(descriptor)
  -- 1. 校验 title 非空、未重复
  -- 2. 存入 _registered[title]
  -- 3. 若设置窗口已打开，刷新侧栏
  -- 4. 全程 pcall 包裹，单插件描述符异常不影响其他插件
end
```

- **调用方向**：永远是子插件 → Hub 单向登记；Hub → 子插件只通过描述符里的回调。子插件从不反向依赖 Hub 的内部结构。
- **能力探测**：Hub 渲染某项 UI 前先判断对应回调是否存在（如无 `setMinimapShown` 就不显示"小地图按钮"开关）。

---

## 4. 上报代码形态（子插件侧）

### 4.1 放置位置

每个子插件在 **Init 序列的末尾**（所有模块初始化完成、`ns.Config` 等已就绪后）加一段上报。以 MyChat 为例，挂在其 [Core:Init](chat/MyChat/Core.lua#L59-L71) 尾部或新增一个 `SuiteBridge` 模块（更符合现有"每功能一模块"的组织方式，推荐后者）。

### 4.2 上报代码（MyChat 示例）

新增 `MyChat/SuiteBridge.lua`，并加入 `.toc` 的 Init 序列尾部：

```lua
local addonName, ns = ...

local Bridge = {}
ns.SuiteBridge = ns.Core:RegisterModule("SuiteBridge", Bridge)

function Bridge:Init()
  -- 握手对象若无则建：不依赖 Hub 是否已加载。
  WowPlayerSuiteAPI = WowPlayerSuiteAPI or { _pending = {}, _registered = {} }

  local descriptor = {
    title    = ns.Constants.ADDON_TITLE,          -- "MyChat"
    version  = ns.Constants.VERSION,              -- "0.1.1"
    slashCmd = "/mychat",

    openSettings = function()
      -- 吸收 MyChat 自己的差异：SettingsPanel:Open() 不支持时返回 false。
      local panel = ns.SettingsPanel
      if panel and panel.Open then return panel:Open() end
    end,
    -- MyChat 无小地图按钮，故不提供 setMinimapShown。
  }

  -- 有真正的 Register（Hub 已加载）就直接登记；否则进 _pending 等 Hub 来收。
  if WowPlayerSuiteAPI.Register then
    WowPlayerSuiteAPI:Register(descriptor)
  else
    WowPlayerSuiteAPI._pending[#WowPlayerSuiteAPI._pending + 1] = descriptor
  end
end
```

### 4.3 关键性质（为什么"零影响"）

- **没装 Hub**：`WowPlayerSuiteAPI` 只是个装了描述符的空壳表，没有任何东西来消费它。MyChat 其余模块照常读写 `MyChatDB`，行为和今天完全一致。
- **这段代码本身无副作用**：只做"登记描述符"，不改任何配置、不动任何 UI。
- **对 RoleManager**：同形，但 `openSettings` 内部改调 `ns.SettingsPanel:Toggle()`，并额外提供 `setMinimapShown`/`getMinimapShown`（包住其现有的 [MinimapButton:Toggle](role-manager/RoleManager/UI/MinimapButton.lua#L119-L124)，做成幂等的 SetShown）。

### 4.4 小地图按钮"统一收纳"如何落地

- RoleManager 提供 `setMinimapShown(false)` → 内部把 `profile.showMinimapButton` 设为 false 并隐藏按钮（复用已有逻辑）。
- Hub 提供"只显示 Hub 一个总按钮，收起子插件按钮"的开关：勾选时 Hub 遍历已注册插件，对有 `setMinimapShown` 的调用 `setMinimapShown(false)`。
- 逻辑全在 Hub 侧；插件只被动提供开关。没装 Hub 时该逻辑不存在，插件按钮各显各的。

---

## 5. Hub 窗口结构

### 5.1 命令与入口
- `/wp`：打开/关闭统一窗口。
- `/wp settings` 或直接 `/wp`：主窗口。
- 小地图按钮：左键开窗口，tooltip 列出已接入插件及版本。
- 各子插件的 `/mychat`、`/rm` 等**保留不变**，作为独立入口。

### 5.2 窗口布局

```
┌─────────────────────────────────────────────┐
│  WowPlayerSuite            v0.3.0        [x]  │  ← 标题栏：套件版本
├───────────────┬─────────────────────────────┤
│ 侧栏(插件列表) │  内容区(随选中项切换)         │
│               │                             │
│ ● 概览         │  [概览页]                    │
│ ─────────────  │   已接入插件 3 个            │
│ ☑ MyChat 0.1.1 │   ┌─────────────────────┐   │
│ ☑ RoleManager  │   │ MyChat      0.1.1 ✅ │   │
│ ☐ CombatCoach  │   │ RoleManager 0.1.2 ✅ │   │
│ ─────────────  │   │ CombatCoach  未启用   │   │
│ ⚙ 插件管理     │   └─────────────────────┘   │
│ ⚙ 备份/迁移    │   [打开设置] 按钮跳到该插件   │
│               │                             │
└───────────────┴─────────────────────────────┘
```

### 5.3 三个功能页

**A. 概览页（默认）**
- 列出所有已注册插件：名称、版本、状态（已启用✅ / 已安装未启用 / 未安装）。
- 每个插件一个"打开设置"按钮 → 调该插件描述符的 `openSettings()`。
- 显示套件总版本；若配置了"最新版本号"，落后时给一行黄色提示（可选能力）。

**B. 插件管理页（启停）**
- 每个子插件一个复选框，读写 `C_AddOns.GetAddOnEnableState` / `EnableAddOn` / `DisableAddOn`。
- **重要交互**：改动后不会立即生效，必须提示"需要重载界面"，提供 `[立即重载]` 按钮调 `ReloadUI()`。这是 WoW 硬限制，UI 上必须讲清，避免"我关了怎么还在"的困惑。
- 与"功能开关"区分：插件内部的功能开关（如 MyChat 的频道条）走各插件设置页，即时生效；此页只管"整个插件的启停"。

**C. 备份/迁移页（A 档能力，可选先做）**
- "导出全部配置"：遍历有 `exportConfig` 的插件，收集成一个 table，序列化成字符串给用户复制。
- "导入配置"：解析字符串，对每个插件调 `importConfig(tbl)` 写回其自己的配置。
- 明确提示：导入会覆盖对应插件的当前设置，建议先 `/reload`。
- **无同步副作用**：这是一次性"推"（用户明确按下），不留副本、不持续绑定，故不存在真相源冲突问题。

### 5.4 渲染与容错
- 侧栏与内容区由 `_registered` 动态生成；插件"后注册"时刷新。
- 所有对 `openSettings`/`exportConfig` 等回调的调用用 `pcall` 包裹，异常插件在列表里标红但不影响其他项。
- 面板本身在不支持的客户端要能降级（参考 MyChat `SettingsPanel:Open()` 返回 false 的处理）。

---

## 6. 打包与版本

- **各插件保留自己的 [package.sh](chat/package.sh)**：仍可单发 `MyChat-x.y.z.zip` 等，独立发布不受影响。
- **新增总打包脚本** `plugin/package-suite.sh`：产出 `WowPlayerSuite-<套件版本>.zip`，解压后为并列的 4 个文件夹（Hub + 三插件），一次装齐。
- **套件版本号**：独立于各插件版本，记录"本次整包内各插件分别是哪个版本"（可在 Hub 的 Constants 里维护一张清单，供概览页展示）。
- **升级方式**：重新下载整包覆盖。可选：Hub 内配置一个"已知最新版本号"，落后时概览页提示（不自动下载）。
- 遵循现有规范：`.toc` 的 `## Version` 与 `Constants.lua` 的 `C.VERSION` 必须一致（打包脚本校验），打包 ≠ 涨号。

---

## 7. 实现范围与阶段建议（待确认）

按依赖与收益排序，建议分批，每批可独立验证：

1. **批次一（最小可用）**：Hub 骨架 + 握手注册表 + `/wp` + 概览页 + 三插件各加 `SuiteBridge` 上报 + 统一"打开设置"。→ 验证"注册协议 + 统一入口"跑通。
2. **批次二**：小地图按钮统一（Hub 总按钮 + 收纳子插件按钮）。
3. **批次三**：插件管理页（启停 + reload 提示）。
4. **批次四**：总打包脚本 + 套件版本清单；可选版本落后提示。
5. **批次五（可选）**：备份/迁移页（导入导出）。

> 每批遵循规范：设计确认 → 实现 → 打包 → 用户实测通过才算完成。

---

## 8. 待用户确认的点

1. Hub 命名 **WowPlayerSuite** / 命令 `/wp` —— 是否确认。
2. 注册方式采用 **握手对象 `WowPlayerSuiteAPI`**（对加载顺序更鲁棒），还是简单的 `if WowPlayerSuite then` 直接判断。
3. 上报代码放在 **独立 `SuiteBridge.lua` 模块**（推荐）还是塞进各插件 Core:Init 尾部。
4. 批次顺序是否认可，第一批先做到哪。
5. 备份/迁移（A 档）是否纳入首期，还是留到最后按需再做。
