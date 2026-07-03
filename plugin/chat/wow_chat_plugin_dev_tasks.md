# WoW 聊天插件详细开发任务与计划

> 本文档是 [wow_chat_plugin_execution_plan.md](./wow_chat_plugin_execution_plan.md) 的**执行细化版**。
> 上游方案定义了目标、架构分层、目录结构、MVP 功能与粗粒度任务；本文档在其基础上补充：
> **里程碑分期、模块接口契约（函数签名）、文件级交付物、精确任务依赖图、逐任务的完成定义（DoD）与测试用例、WoW 12.0.x 安全 API 约束、验证方案与编码规范**，使每张任务卡可被 Agent 直接领取执行。
>
> **范围约束**：本文件及后续所有实现产物**仅**位于 `plugin/chat/` 目录内，不触碰仓库其他目录。

---

## 0. 文档关系与前置说明

| 项 | 上游 execution plan | 本文档 |
|---|---|---|
| 定位 | 架构方案（WHAT / WHY） | 开发计划（HOW / WHEN / DoD） |
| 任务粒度 | Task-01 ~ Task-14（目标级） | Milestone → Task → 子步骤 + 接口签名 + 测试用例 |
| 接口 | message 结构、配置模型 | 每个模块的公开函数签名与调用契约 |
| 验收 | 功能/稳定性/兼容性大项 | 逐任务 DoD + 手动测试脚本 |

> **待澄清**：自定义指令要求参考 `workers/01-整体架构师.md`，该文件在仓库中不存在。当前以 execution plan 作为权威架构依据。若有独立架构规范文档，请提供后我再对齐分层命名与约束。

---

## 1. 里程碑规划（Milestones）

按"可加载 → 可观测 → 可增强 → 可运营 → 可交互"的顺序推进，每个里程碑结束都应能在游戏内 reload 验证。

| 里程碑 | 名称 | 覆盖任务 | 出口标准（Exit Criteria） |
|---|---|---|---|
| **M0** | 骨架可加载 | T01, T02 | 插件加载无报错；SavedVariables 可持久化；`/mychat` 有响应 |
| **M1** | 事件贯通 | T03, T04 | 所有聊天事件被捕获并标准化为 message 对象；`/mychat debug` 可打印最近消息 |
| **M2** | 只读增强 | T05, T06 | 时间戳/频道缩写/职业色/关键词高亮在原生框可见；无高风险覆写 |
| **M3** | 消息运营 | T07, T08, T09 | 最近密语回复、重复折叠、频道分流可用且可配置 |
| **M4** | 频道与安全 | T10, T11, T12 | 自动加入/恢复频道；CombatGuard 生效；reset/debug 命令完备 |
| **M5** | 交互界面 | T13, T14 | 设置面板可切换开关；镜像面板可选开启 |

**依赖原则**：M0 是硬前置；M1 完成后 M2/M3 的部分任务可并行；安全层（T11）应在任何写 UI 的任务合入前就位。

---

## 2. 模块接口契约（公开 API 签名）

> 约定：所有模块挂载到单一命名空间 `ns`（通过 `.toc` 的 `... , ns = select(2, ...)` 传入）。模块间**只通过下列签名交互**，不得直接读写其他模块内部字段。所有回调必须 pcall 包裹（见 §6 安全约束）。

### 2.1 Core / Init
```lua
-- Init.lua
-- 由 ADDON_LOADED 触发，装配所有模块
function ns.Core:Init()                       -- 按固定顺序初始化各模块
function ns.Core:RegisterModule(name, module) -- 注册模块，重复名报错
function ns.Core:GetModule(name)              -- 取模块，缺失返回 nil
function ns.Core:SafeCall(fn, ...)            -- pcall 包裹并计入 Diagnostics
```

### 2.2 Config
```lua
function ns.Config:Init()                 -- 合并 Defaults 与 SavedVariables
function ns.Config:Get(path)              -- path 形如 "profile.showTimestamps"
function ns.Config:Set(path, value)       -- 写入并标记 dirty
function ns.Config:GetProfile()           -- 返回整个 profile 表（只读语义）
function ns.Config:ResetProfile()         -- 恢复默认，用于 /mychat reset
```

### 2.3 Events / MessageBus
```lua
-- Events.lua：登记 WoW 事件，转发给 MessageBus / CombatGuard
function ns.Events:Init()
function ns.Events:Register(event, handler)   -- 内部封装 frame:RegisterEvent

-- MessageBus.lua：进程内发布/订阅（解耦 Parser→Filters→Router→Render）
function ns.Bus:On(topic, handler)            -- topic: "message.raw" | "message.normalized" | "combat.enter" | "combat.leave"
function ns.Bus:Emit(topic, payload)          -- 同步派发，逐个 SafeCall
```

### 2.4 Parser
```lua
-- 输入为 CHAT_MSG_* 的原始可变参数，输出标准 message（见 execution plan §4.2）
function ns.Parser:Normalize(event, ...) -> message|nil
function ns.Parser:ClassifyChannel(event, channelName) -> channelType, messageClass
```

### 2.5 Filters
```lua
function ns.Filters:Init()
function ns.Filters:Apply(message) -> message   -- 挂关键词/自名高亮标记，返回可能被标记 collapsed 的 message
function ns.Filters:IsDuplicate(message) -> boolean, count
function ns.Filters:HighlightKeywords(text) -> text  -- 返回带颜色转义的文本
```

### 2.6 Router
```lua
function ns.Router:Init()
function ns.Router:Route(message) -> viewList   -- 返回逻辑视图标签集合 {"world","trade","party"} 等
```

### 2.7 NativeEnhancer
```lua
function ns.NativeEnhancer:Init()
-- 通过 ChatFrame_AddMessageEventFilter 注入，绝不覆写 AddMessage
function ns.NativeEnhancer:BuildPrefix(message) -> string  -- 时间戳+频道缩写
function ns.NativeEnhancer:ColorizeAuthor(message) -> string
function ns.NativeEnhancer:MessageFilter(chatFrame, event, ...) -> false|true, ...
```

### 2.8 WhisperIndex
```lua
function ns.WhisperIndex:Init()
function ns.WhisperIndex:Record(message)              -- 记录密语来往对象
function ns.WhisperIndex:GetLastTarget() -> name|nil
function ns.WhisperIndex:ReplyLast(text)              -- 打开/发送密语，需 CombatGuard 检查
```

### 2.9 CombatGuard
```lua
function ns.CombatGuard:Init()
function ns.CombatGuard:InCombat() -> boolean
function ns.CombatGuard:Run(fn)     -- 脱战直接执行；战斗中入队，PLAYER_REGEN_ENABLED 后执行
function ns.CombatGuard:FlushDeferred()
```

### 2.10 Diagnostics
```lua
function ns.Diagnostics:Init()
function ns.Diagnostics:Error(scope, err)   -- 计数并按阈值触发降级
function ns.Diagnostics:Dump() -> string    -- /mychat debug 输出
function ns.Diagnostics:ShouldDegrade() -> boolean
```

### 2.11 Commands
```lua
function ns.Commands:Init()   -- 注册 SLASH_MYCHAT1 = "/mychat"
-- 分发：<空>=开面板 | safe | reset | debug | reply <text>
```

### 2.12 UI（SettingsPanel / MirrorPanel）
```lua
function ns.SettingsPanel:Init()      -- 注册到 Settings（Interface Options）
function ns.MirrorPanel:Init()
function ns.MirrorPanel:Toggle()
function ns.MirrorPanel:Push(message) -- 仅镜像，不接管主框
```

---

## 3. 文件级交付物矩阵

| 文件 | 负责任务 | 关键交付 |
|---|---|---|
| `MyChat.toc` | T01 | Interface 号=12.0.x 对应值、SavedVariables=MyChatDB、文件加载顺序 |
| `Init.lua` | T01 | 入口、ADDON_LOADED 挂载、命名空间建立 |
| `Core.lua` | T01 | 模块注册表、初始化顺序、SafeCall |
| `Constants.lua` | T01 | 事件名、频道缩写表、职业色回退表 |
| `Utils.lua` | T01 | 字符串/颜色/时间工具函数 |
| `Data/Defaults.lua` | T02 | profile/runtime 默认结构（对齐 execution plan §7） |
| `Config.lua` | T02 | 深合并、Get/Set 路径解析、Reset |
| `Events.lua` | T03 | 事件注册与转发 |
| `MessageBus.lua` | T03 | On/Emit 发布订阅 |
| `Parser.lua` | T04 | Normalize / ClassifyChannel |
| `NativeEnhancer.lua` | T05 | AddMessageEventFilter 注入、前缀/职业色 |
| `Filters.lua` | T06, T08 | 关键词高亮、自名提醒、重复折叠 |
| `WhisperIndex.lua` | T07 | 密语索引、ReplyLast |
| `Router.lua` | T09 | 视图路由规则 |
| `CombatGuard.lua` | T11 | 战斗状态、延迟队列 |
| `Diagnostics.lua` | T12 | 错误计数、Dump、降级判定 |
| `Commands.lua` | T07, T10, T12 | 斜杠命令分发 |
| `UI/SettingsPanel.lua` | T13 | 开关面板 |
| `UI/MirrorPanel.lua` | T14 | 镜像视图 |

---

## 4. 任务卡（Agent 可执行 backlog）

> 每张卡含：依赖 / 交付文件 / 步骤 / DoD / 测试用例。测试用例以"游戏内可复现步骤"描述（无原生单测框架，采用手动 + 断言日志）。

### T01 · 插件骨架与命名空间
- **里程碑**：M0　**依赖**：无　**交付**：`MyChat.toc` `Init.lua` `Core.lua` `Constants.lua` `Utils.lua`
- **步骤**
  1. 写 `.toc`：`## Interface:` 填 12.0.x 对应版本号；按依赖顺序列出所有 lua；声明 `## SavedVariables: MyChatDB`。
  2. `Init.lua` 建立 `local addonName, ns = ...`，注册 `ADDON_LOADED` 后调用 `ns.Core:Init()`。
  3. `Core.lua` 实现模块注册表 + `SafeCall`（pcall + 错误转 Diagnostics 占位）。
  4. `Constants.lua` 定义事件常量、频道缩写映射、`RAID_CLASS_COLORS` 回退。
  5. `Utils.lua`：`Utils.Trim`、`Utils.ColorText(hex,text)`、`Utils.Now`、`Utils.SplitList`。
- **DoD**：游戏内 `/reload` 加载无 Lua 报错；`/mychat` 打印版本号；`MyChatDB` 在 SavedVariables 中生成。
- **测试**：① 全新账号首次登录无报错；② `_retail_` reload 后 `MyChatDB` 存在。

### T02 · 配置系统
- **里程碑**：M0　**依赖**：T01　**交付**：`Data/Defaults.lua` `Config.lua`
- **步骤**
  1. `Defaults.lua` 严格对齐 execution plan §7 的 `profile` / `runtime`。
  2. `Config:Init` 深合并（缺字段补默认，不覆盖已有用户值）。
  3. 实现点路径 `Get/Set`（`"profile.highlightKeywords"`）。
  4. `ResetProfile` 用 Defaults 深拷贝覆盖 profile，保留 runtime。
- **DoD**：改开关 → reload 后保留；新增默认字段对老存档自动补齐；`ResetProfile` 只重置 profile。
- **测试**：① 设 `showTimestamps=false` → reload 仍为 false；② 手动删存档某字段 → reload 后被补默认；③ reset 后 runtime.lastWhisperTargets 不丢。

### T03 · 事件总线
- **里程碑**：M1　**依赖**：T01　**交付**：`Events.lua` `MessageBus.lua`
- **步骤**
  1. `MessageBus`：`On/Emit`，Emit 内逐订阅 `Core:SafeCall`。
  2. `Events`：创建隐藏 frame，注册 execution plan §4.1 全部事件。
  3. 聊天类事件 → `Bus:Emit("message.raw", {event=, args={...}})`；战斗事件 → `Bus:Emit("combat.enter/leave")`。
- **DoD**：任一频道发言，`message.raw` 被触发；进出战斗触发 combat 主题。
- **测试**：① 世界频道发言→debug 日志出现 raw；② 进战斗→combat.enter 日志。

### T04 · 消息标准化
- **里程碑**：M1　**依赖**：T03　**交付**：`Parser.lua`
- **步骤**
  1. 订阅 `message.raw`，按 event 映射 CHAT_MSG 参数（arg1 文本、arg2 作者…）。
  2. 产出 execution plan §4.2 结构；`isSelf` 用 `UnitName("player")` 比对；`ts=GetTime()`；`id` 用 `ts..author..hash`。
  3. `ClassifyChannel` 判定 whisper/guild/party/raid/trade/system/world。
  4. 输出 `Bus:Emit("message.normalized", message)`。
- **DoD**：6 类频道均生成合法 message；system 无 author 不报错。
- **测试**：① 世界/交易/公会/队伍/密语/系统各发一条→字段完整；② 中文名/空格名正确解析。

### T05 · 原生聊天增强（时间戳/缩写/职业色）
- **里程碑**：M2　**依赖**：T04　**交付**：`NativeEnhancer.lua`
- **步骤**
  1. **仅**用 `ChatFrame_AddMessageEventFilter(event, filterFn)` 注入，禁止覆写 `AddMessage`。
  2. `BuildPrefix`：按配置拼 `[HH:MM]` + 频道缩写（Constants 映射）。
  3. `ColorizeAuthor`：`GetPlayerInfoByGUID` 取职业→`RAID_CLASS_COLORS`，失败回退默认色。
  4. filter 返回 `false, newMsg, ...` 改写显示文本，保留其余返回值。
- **DoD**：三项增强在原生框可见；关闭对应开关即消失；无 taint 报错；关插件后原生显示正常。
- **测试**：① 开时间戳→消息带 `[HH:MM]`；② 关缩写→显示原频道名；③ 不同职业玩家名颜色正确；④ 无 GUID 的系统消息不报错。

### T06 · 关键词与自名高亮
- **里程碑**：M2　**依赖**：T04, T05　**交付**：`Filters.lua`（高亮部分）
- **步骤**
  1. `HighlightKeywords`：遍历 `profile.highlightKeywords`，命中包裹颜色。
  2. `highlightSelfName` 命中玩家名时追加醒目前缀/色。
  3. 挂接到 NativeEnhancer filter 链（先高亮再输出）。
- **DoD**：命中关键词变色；自名被高亮；空关键词列表不报错；关闭开关无副作用。
- **测试**：① 关键词含"来T"→他人发"来T"变色；② 他人 @我的名字→高亮；③ 关键词设为空→正常显示。

### T07 · 最近密语索引与快捷回复
- **里程碑**：M3　**依赖**：T04　**交付**：`WhisperIndex.lua` `Commands.lua`（reply 分支）
- **步骤**
  1. 订阅 normalized，`CHAT_MSG_WHISPER`(收) 与 `CHAT_MSG_WHISPER_INFORM`(发) 都记录对象到 `runtime.lastWhisperTargets`（去重、限长）。
  2. `GetLastTarget` 返回最近对象；`ReplyLast(text)` 经 `CombatGuard:Run` 调 `ChatFrame_SendTell`/`SendChatMessage`。
  3. `/mychat reply <文本>` 发给最近对象；无对象时提示。
- **DoD**：收到密语后 `/mychat reply hi` 能回给对方；无历史时友好提示；战斗中延迟到脱战执行。
- **测试**：① A密语我→`/mychat reply 收到`→A收到；② 无密语历史→提示"无最近密语"；③ 战斗中 reply→脱战后发出。

### T08 · 重复消息折叠
- **里程碑**：M3　**依赖**：T04, T05　**交付**：`Filters.lua`（折叠部分）
- **步骤**
  1. 维护滑动窗口（如 8s）内 `author+textPlain` 指纹表。
  2. `IsDuplicate` 命中→窗口内累计计数，抑制重复输出，改显 `原文 (重复 xN)`。
  3. 窗口过期清理；默认折叠不删除。
- **DoD**：短时间刷屏折叠为计数；不同人同文本不误折；关开关恢复原样。
- **测试**：① 同人连发3条相同→显示"(重复 x3)"；② 两人发相同文本→不折叠；③ 间隔>窗口→独立显示。

### T09 · 频道分流
- **里程碑**：M3　**依赖**：T04　**交付**：`Router.lua`
- **步骤**
  1. `Route(message)` 依 messageClass 返回视图标签集合。
  2. `routeWorldTradeParty` 开启时按世界/交易/队伍归类，供 MirrorPanel/统计使用。
  3. **默认不破坏原生显示**，仅打标签（真正分屏留待 MirrorPanel）。
- **DoD**：规则可配置；关闭后无行为变化；标签正确。
- **测试**：① 交易频道消息→标签含 trade；② 关闭分流→Route 返回空或默认；③ 未知频道→归 other 不报错。

### T10 · 自动加入与恢复频道
- **里程碑**：M4　**依赖**：T02, T03　**交付**：`Events.lua`(扩展) `Commands.lua`(扩展) `Config.lua`(读)
- **步骤**
  1. `PLAYER_ENTERING_WORLD` 后延迟节流调用 `JoinChannelByName` 加入 `profile.autoJoinChannels`。
  2. 记录/恢复 `runtime.joinedChannels`；区分首次登录 / 切图 / reload。
  3. 加入失败重试（有限次 + 间隔），避免刷屏。
- **DoD**：登录/切图/reload 后世界频道在位；自定义频道恢复；重试有节流不刷屏。
- **测试**：① 登录后自动在世界频道；② 手动退频道再 reload→恢复；③ 快速切图多次→无重复加入风暴。

### T11 · CombatGuard 安全层
- **里程碑**：M4　**依赖**：T03　**交付**：`CombatGuard.lua`
- **步骤**
  1. 订阅 combat.enter/leave 维护 `inCombat`。
  2. `Run(fn)`：脱战直接跑；战斗中入 `DeferredQueue`。
  3. `PLAYER_REGEN_ENABLED` 触发 `FlushDeferred`，逐个 SafeCall。
  4. 所有写 UI / 发消息类操作必须经 `Run`。
- **DoD**：战斗中不执行重排/显隐/发送；脱战后队列执行；队列异常不阻塞后续。
- **测试**：① 战斗中触发 reply→不立即发；② 脱战→自动补发；③ 队列中一项报错→其余仍执行。

### T12 · 恢复与调试命令
- **里程碑**：M4　**依赖**：T02, T11　**交付**：`Commands.lua`(完善) `Diagnostics.lua`
- **步骤**
  1. `Diagnostics`：Error 计数、按 scope 归类、`ShouldDegrade` 阈值判定、`Dump` 汇总。
  2. `/mychat reset`→`Config:ResetProfile` + 提示 reload。
  3. `/mychat debug`→打印 Diagnostics.Dump（错误数、最近消息、模块状态）。
  4. `/mychat safe`→强制 `safeMode=true`，仅保留只读增强。
- **DoD**：reset 恢复默认；debug 输出可读诊断；safe 后高风险功能停用。
- **测试**：① reset 后开关回默认；② 制造一次 filter 报错→debug 显示计数；③ safe 模式下 MirrorPanel 不接管。

### T13 · 设置面板
- **里程碑**：M5　**依赖**：T02　**交付**：`UI/SettingsPanel.lua`
- **步骤**
  1. 用 12.0.x `Settings` API（`Settings.RegisterCanvasLayoutCategory` 或等价）注册面板。
  2. 为时间戳/缩写/职业色/高亮/自名/分流/折叠/镜像/安全模式加复选框，双向绑定 `Config`。
  3. 改动即时生效或提示 reload（结构类改动走 CombatGuard）。
- **DoD**：面板出现在设置内；勾选写入 Config 并持久化；战斗中不做危险结构改动。
- **测试**：① 面板可打开；② 取消时间戳→聊天框即时去掉时间戳；③ reload 后设置保留。

### T14 · 可选镜像面板
- **里程碑**：M5　**依赖**：T04, T09, T11　**交付**：`UI/MirrorPanel.lua`
- **步骤**
  1. 独立可移动 frame，**默认关闭**（`mirrorPanelEnabled=false`）。
  2. 订阅 normalized，`Push` 按 Router 标签着色展示，绝不接管主 ChatFrame。
  3. 创建/显隐经 CombatGuard；`Toggle` 由命令/面板触发。
- **DoD**：默认隐藏；开启后镜像消息流；关闭插件/关面板不影响原生聊天。
- **测试**：① 默认不显示；② 开启→新消息进入镜像；③ 战斗中开启请求→脱战后创建。

### T15 · 频道快速切换 / 发送条（当前优先）
- **里程碑**：M5　**依赖**：T02, T11, T13　**交付**：`UI/ChannelBar.lua`
- **定位**：核心基础功能。在聊天框附近提供一排可点击按钮，让玩家**快速切换到目标频道并发送消息**，优先覆盖**世界 / 小队 / 团队**三个高频场景（公会、密语作为附带按钮）。**只操作输入侧，绝不接管原生 EditBox 的渲染或消息流。**
- **交互模型（二选一，实现时以 A 为默认）**
  - **A（推荐·切换输入框）**：点击按钮 → 打开原生聊天输入框并切到对应频道类型，光标就位，玩家打字后回车发送。零 taint 风险，最贴近"增强而不接管"。
  - **B（可选·条内直发）**：条上带一个输入框，选中频道后输入回车，内部用 `SendChatMessage(text, chatType[, nil, channelId])` 直接发送（普通频道非受保护，安全）。作为 A 的增强，后置。
- **步骤**
  1. 独立可移动条状 frame，默认可关（新增开关 `profile.channelBarEnabled`，默认 `false`）。
  2. 频道类型映射：世界→已加入的编号频道(`CHANNEL`+channelId)、小队→`PARTY`、团队→`RAID`、公会→`GUILD`、密语→`WHISPER`(配合 T07 最近对象)。
  3. 切换实现：优先 `ChatEdit_GetActiveWindow()` 取/开输入框，`editBox:SetAttribute("chatType", ...)` + 必要时 `channelTarget`；**不覆写 `ChatEdit_*` 核心函数**。
  4. 频道可用性动态置灰：依 `IsInGroup()`/`IsInRaid()`/`IsInGuild()`；世界按钮依 T10 是否已加入对应编号频道。
  5. 创建/显隐/重排一律经 `CombatGuard:Run`；战斗中不新建或移动 frame。
  6. 与 T13 设置面板联动：加"启用频道切换条"复选框。
- **安全约束**：模型 A 不 hook `ChatEdit_OnEnterPressed`/`SendChatMessage`；模型 B 仅对普通频道用 `SendChatMessage`，不触碰受保护路径，避免 taint 与误发。
- **DoD**：默认隐藏；开启后点"小队/团队/世界"能切到对应频道且光标就位（或 B 模式直发成功）；无对应群体时按钮禁用；战斗中请求延迟到脱战；关闭后原生输入无残留影响。
- **测试**：① 组队后点"小队"→输入框进入小队频道待输入；② 不在团队时"团队"按钮置灰；③ 点"世界"→切到已加入的世界编号频道；④ 战斗中点按钮→脱战后条就位；⑤（B 模式）选"团队"输入回车→消息发到团队频道。

---

## 5. 任务依赖图

```text
T01 骨架 ──┬── T02 配置 ──┬── T10 频道恢复
           │              ├── T12 命令/诊断
           │              └── T13 设置面板 ── T15 频道切换条
           └── T03 事件总线 ──┬── T04 标准化 ──┬── T05 原生增强 ──┬── T06 关键词高亮
                              │                │                 └── T08 重复折叠
                              │                ├── T07 密语索引
                              │                ├── T09 频道分流 ── T14 镜像面板
                              │                └──────────────────┘
                              └── T11 CombatGuard ──> (T07 reply / T13 结构改动 / T14 创建 / T15 创建·切频道)

关键前置：T11 应在 T07(发送)、T13(结构)、T14(创建)、T15(创建/切频道) 合入前就位。
```

**并行批次建议**
- 批次1（串行）：T01 → T02、T03
- 批次2（并行）：T04、T13（面板可先接 mock config）
- 批次3（并行，依赖 T04）：T05、T07、T09、T11
- 批次4（依赖 T05）：T06、T08
- 批次5：T10、T12
- 批次6：T14、T15（UI 增强，依赖 T11/T13）

---

## 6. WoW 12.0.x 安全 API 约束（强制）

所有实现必须遵守，违反即视为不通过：

1. **禁止覆写核心方法**：不得 hook/替换 `ChatFrame:AddMessage`、`DEFAULT_CHAT_FRAME` 内部方法。增强一律走 `ChatFrame_AddMessageEventFilter`。
2. **避免 taint**：不在受保护路径调用受保护 API；发送消息、切频道等在用户触发或非战斗时执行。
3. **战斗保护**：任何 `Show/Hide/SetPoint/SetParent/重建 frame` 必须经 `CombatGuard:Run`；`InCombatLockdown()` 为真时不动受保护/结构。
4. **可降级**：每个增强都有开关；`safeMode` 或错误阈值触发时退回只读增强或原生显示。
5. **错误隔离**：所有事件回调、filter、命令处理用 `Core:SafeCall`（pcall）包裹，单点错误不扩散。
6. **节流**：频道加入、重试、重复检测使用时间窗口/计数，禁止无限循环或每帧重算。
7. **不删除消息**：过滤默认折叠或标记，不静默丢弃用户消息。

---

## 7. 验证方案

无原生 Lua 单测框架，采用**分层验证**：

- **静态检查**：加载顺序、变量引用（可选 `luacheck`），保证无全局泄漏（除命名空间与 SavedVariables）。
- **游戏内冒烟**（每里程碑必做）：`/reload` 无报错 + `/mychat debug` 输出健康。
- **功能脚本**（对照各任务"测试用例"逐条执行）。
- **稳定性**：进出副本/战斗、快速切图、多频道刷屏场景下无致命报错。
- **回归**：禁用插件后确认原生聊天完全正常。

**建议内建自检**：`/mychat debug` 输出应包含：加载模块数、各模块 init 状态、错误计数、最近 5 条 normalized 消息摘要、当前 inCombat 状态、已加入频道列表。

---

## 8. 编码规范

- 单一命名空间 `ns`，禁止新增全局（SavedVariables 除外）。
- 文件顶部 `local addonName, ns = ...`；`local` 优先，热路径缓存全局 API（`local GetTime = GetTime`）。
- 模块统一 `ns.XXX = {}` + `function ns.XXX:Init()`，由 `Core` 按序调用。
- 事件/回调必经 `SafeCall`；对外只暴露 §2 契约函数。
- 注释只写"为什么"（如安全约束、taint 规避原因），不写"做什么"。
- 字符串常量集中于 `Constants.lua`；魔法数（窗口时长、重试次数）具名化。

---

## 9. 交付物清单（本目录内）

完成后 `plugin/chat/` 应包含：
1. 本计划文档 + 上游 execution plan。
2. `MyChat/` 插件骨架及全部模块文件（§3 矩阵）。
3. 可加载、可 reload、可 `/mychat debug` 自检的 MVP v0.1。
4. 每任务对照 DoD 的验证记录（可追加到本文件末尾的"验证记录"章节）。

---

## 10. 风险登记（补充 execution plan §11）

| 风险 | 触发场景 | 缓解 | 归属任务 |
|---|---|---|---|
| Interface 号不匹配导致标"过期" | 12.0.x 小版本变动 | `.toc` 用当前实际版本号，或加载后校验 | T01 |
| AddMessageEventFilter 链冲突 | 与其他聊天插件共存 | filter 只改文本、保留原返回、不吞消息 | T05 |
| 频道加入过早失败 | 登录瞬间频道未就绪 | 延迟 + 有限重试 + 节流 | T10 |
| 战斗中设置面板改结构 | 用户战斗中调设置 | 结构类改动入 CombatGuard 队列 | T13 |
| 折叠误伤正常对话 | 窗口过长/指纹过宽 | 指纹含 author、窗口保守、可关 | T08 |
| 频道切换条误发/taint | 直发或 hook 核心链路 | 默认模型 A 只切输入框；直发仅限普通频道 | T15 |

---

## 12. 长远规划（暂缓，不纳入当前 MVP）

以下功能**已确认价值但暂不实现**，先记录以免遗漏。等 T01–T15 的 MVP 在游戏内验证通过后再评估优先级。
**优先级**：★ = 已选中、建议作为 MVP 后第一波；○ = 已选中、第二波；– = 备选待定。

### 12.1 显示与提醒
| 编号 | 功能 | 说明 | 复用模块 | 风险 | 优先级 |
|---|---|---|---|---|---|
| A1 | 链接复制 | 点聊天里的网址/链接弹只读 EditBox，玩家 Ctrl+C 复制（魔兽无法直写剪贴板） | NativeEnhancer | 低 | ★ |
| A2 | 职业图标 | 玩家名前加小职业图标，与现有职业色配套 | NativeEnhancer | 低 | ○ |
| B2 | 密语弹窗提醒 | 副本/战斗中收到密语时角落 toast 提醒，避免漏看 | Bus(normalized), CombatGuard | 中 | ○ |

### 12.2 过滤与历史
| 编号 | 功能 | 说明 | 复用模块 | 风险 | 优先级 |
|---|---|---|---|---|---|
| C1 | 广告 / 金币商人过滤 | 按常见刷屏广告模式（网址、"XX元="、重复）识别折叠，**默认关、防误伤** | Filters | 中 | ★ |
| D1 | 聊天历史持久化 | reload/重登后恢复最近 N 条聊天（魔兽默认清空），存 SavedVariables 并限量 | Config, Bus | 中 | ★ |

### 12.3 输入与效率
| 编号 | 功能 | 说明 | 复用模块 | 风险 | 优先级 |
|---|---|---|---|---|---|
| E2 | 快捷短语 | 预设常用语一键发送（如"集合了""稍等"），延续 T15 输入侧 | ChannelBar, CombatGuard | 中 | ★ |
| E3 | 最近频道粘滞 | 记住上次在各频道发言，回车默认回到该频道 | ChannelBar, Config | 中 | ○ |

### 12.4 其他备选（未选中，保留）
| 编号 | 功能 | 说明 | 复用模块 | 风险 | 优先级 |
|---|---|---|---|---|---|
| L1 | 小地图按钮 | LibDataBroker + LibDBIcon，左键开设置、右键切镜像面板，位置可拖拽、可隐藏 | T13 | 低 | – |
| L2 | 招募/组队消息半结构化识别 | 识别"来T/来奶/缺X"类招募，提取角色需求 | T04, T06 | 中 | – |
| L3 | 屏蔽 / 黑白名单 | 按玩家名或关键词过滤（Filters 已预留黑白名单接口） | T06 | 中 | – |
| L4 | 密语会话聚合 | 把同一人的密语聚合成会话流，不淹没在主聊天 | T07 | 中 | – |
| L5 | 频道条 B 模式（条内直发） | 在切换条上直接输入并发送，见 T15 交互模型 B | T15 | 中 | – |
| L6 | 跨角色配置同步 | profile 在多角色/多账号间同步 | T02 | 中 | – |
| A3 | 物品/成就链接增强 | 悬停预览、稀有度着色强化 | NativeEnhancer | 低 | – |
| A4 | 频道未读标记 | 非当前标签页有新消息时提示 | Router, Bus | 低 | – |
| B1 | 关键词声音/闪屏提醒 | 命中关键词或自己名字时声音+闪屏（现仅变色） | Bus, Filters | 中 | – |
| B3 | AFK 自动回复 | 挂机时自动回密语"稍后回复" | Bus, WhisperIndex | 中 | – |
| C2 | 跨频道去重 | 同消息在世界+交易重复刷时合并 | Filters | 中 | – |
| C3 | 单频道静音 | 临时屏蔽某个吵闹频道，不退频道 | Filters, Router | 中 | – |
| D2 | 密语日志 | 按角色记录密语往来可翻查 | WhisperIndex, Config | 中 | – |
| D3 | 聊天搜索 | 在历史里按关键词/人名搜索 | D1 | 中 | – |
| E1 | 玩家名 Tab 补全 | 密语/@时按 Tab 补全在线玩家名 | ChannelBar | 中 | – |

### 12.5 建议的实施波次（MVP 验证通过后）
- **第一波（★，高频基础）**：A1 链接复制、C1 广告过滤、D1 历史持久化、E2 快捷短语。
- **第二波（○）**：A2 职业图标、B2 密语弹窗、E3 频道粘滞。
- **备选（–）**：视反馈从 12.4 挑选。

**取舍原则**：当前只做"基础且高频"的能力（原生只读增强 + 频道快速切换/发送）。上述项均为"锦上添花"，不得为实现它们牺牲 MVP 的稳定性与"增强而不接管"边界。所有过滤类（C 系）默认关闭并以折叠代替删除。

---

## 13. 验证记录（实现时逐项回填）

> 格式：`[任务][日期] 结论 / 备注`

- [T01][2026-07-02] 代码完成 / 骨架、命名空间、Core.SafeCall、常量、工具函数、ADDON_LOADED 入口。待游戏内 /reload 验证。
- [T02][2026-07-02] 代码完成 / Defaults 对齐 §7；Config 深合并/点路径 Get·Set/ResetProfile。
- [T03][2026-07-02] 代码完成 / MessageBus On·Emit + recent 缓冲；Events 注册并转发 message.raw / combat / lifecycle。
- [T04][2026-07-02] 代码完成 / Parser Normalize + ClassifyChannel，textPlain 去转义，isSelf 含 WHISPER_INFORM。
- [T05][2026-07-02] 代码完成 / NativeEnhancer 仅用 AddMessageEventFilter，pcall 包裹，永不吞消息；集成 Parser+Filters。
- [T06+T08][2026-07-02] 代码完成 / Filters 关键词/自名高亮 + 滑动窗口折叠（追加"重复 xN"，不删除）。
- [T07][2026-07-02] 代码完成 / WhisperIndex 记录 runtime.lastWhisperTargets，ReplyLast 经 CombatGuard。
- [T09][2026-07-02] 代码完成 / Router 依 messageClass 出视图标签，关闭时空表不改行为。
- [T10][2026-07-02] 代码完成 / Channels 进入世界后节流 + 有限重试加入/恢复频道。
- [T11][2026-07-02] 代码完成 / CombatGuard inCombat + Run 入队 + 脱战 FlushDeferred。
- [T12][2026-07-02] 代码完成 / Diagnostics 计数·Dump·降级；Commands 分发 debug/reset/safe/reply。
- [T13][2026-07-02] 代码完成 / SettingsPanel 9 开关双向绑定，兼容新旧 Settings API。
- [T14][2026-07-02] 代码完成 / MirrorPanel 懒创建、默认关闭、经 CombatGuard，不接管原生框。
- [T15][2026-07-03] 代码完成 / ChannelBar 模型A：点按钮切原生输入框到 说/小队/团队/公会/世界(编号频道)/密语，仅设 chatType+SetFocus 不发送、玩家回车发；按 IsInGroup/IsInRaid/IsInGuild/世界频道存在动态置灰；创建/显隐经 CombatGuard；新增 profile.channelBarEnabled + 设置面板开关。已接入 Core/.toc/Defaults/SettingsPanel。

> 说明：本机无 lua/luac 工具链，未做静态编译校验；已按加载顺序与依赖链人工复核。IDE 报的"未定义全局"（GetTime/UnitName/CreateFrame/Settings 等）均为 WoW 运行时全局，属误报。下一步需在游戏客户端 /reload 逐条跑各任务"测试用例"。

