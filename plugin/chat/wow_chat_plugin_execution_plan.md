# WoW 聊天插件开发执行方案

## 1. 目标

产出一个面向 WoW 12.0.x 的稳定型聊天增强插件，遵循以下原则：

1. 不替换原生聊天系统，只做增强。
2. 战斗中不做高风险 UI 结构修改。
3. 所有增强能力可降级。
4. 最坏情况下可回退到原生聊天显示。
5. 方案内容可直接被 Agent 拆解执行。

## 2. 版本范围

本方案定义 **MVP v0.1**，优先实现以下 12 个功能：

1. 自动加入世界频道
2. 自动恢复自定义频道
3. 时间戳显示
4. 频道缩写
5. 玩家名职业色
6. 关键词高亮
7. 自己名字高亮提醒
8. 最近密语列表
9. 一键回复最近密语
10. 重复消息折叠
11. 世界 / 交易 / 队伍消息分流
12. 一键恢复默认聊天设置

## 3. 范围边界

### 3.1 本期包含

- 聊天事件监听与标准化
- 消息处理与轻量过滤
- 原生聊天框增强
- 辅助镜像视图（可选）
- 安全模式与恢复命令
- SavedVariables 配置持久化

### 3.2 本期不包含

- 完全替换默认 ChatFrame
- 战斗中隐藏 / 淡出聊天框
- 深度覆写 AddMessage
- 复杂招募结构化看板
- 高风险动态重排 / docking 系统

## 4. 架构设计

采用“增强而不接管”的五层架构：

### 4.1 Event Layer
负责监听：
- PLAYER_LOGIN
- PLAYER_ENTERING_WORLD
- PLAYER_REGEN_DISABLED
- PLAYER_REGEN_ENABLED
- CHAT_MSG_CHANNEL
- CHAT_MSG_WHISPER
- CHAT_MSG_GUILD
- CHAT_MSG_PARTY
- CHAT_MSG_RAID
- CHAT_MSG_INSTANCE_CHAT
- CHAT_MSG_SYSTEM

职责：
- 接收游戏事件
- 转发为内部消息对象
- 不直接修改高风险 UI

### 4.2 Normalize Layer
统一消息结构：

```lua
message = {
  id = string,
  ts = number,
  eventType = string,
  channelType = string,
  channelName = string,
  author = string,
  authorFullName = string,
  isSelf = boolean,
  textRaw = string,
  textPlain = string,
  messageClass = string,
  priority = number,
}
```

### 4.3 Process Layer
职责：
- 关键词匹配
- 重复消息折叠
- 频道标签路由
- 最近密语索引
- 高优先级标记

### 4.4 Render Layer
职责：
- 原生聊天增强
- 可选镜像视图
- 设置界面反馈

约束：
- 不直接替换 ChatFrame 核心实现
- 不在战斗中重建布局

### 4.5 Safety Layer
职责：
- CombatGuard：战斗中阻止高风险操作
- DeferredQueue：延迟非安全操作到脱战后执行
- Fallback：异常时退回原生增强模式
- Diagnostics：输出调试与恢复信息

## 5. 目录结构

建议项目结构如下：

```text
MyChat/
  MyChat.toc
  Init.lua
  Core.lua
  Config.lua
  Constants.lua
  Utils.lua
  Events.lua
  MessageBus.lua
  Parser.lua
  Filters.lua
  Router.lua
  NativeEnhancer.lua
  WhisperIndex.lua
  CombatGuard.lua
  Diagnostics.lua
  Commands.lua
  UI/
    SettingsPanel.lua
    MirrorPanel.lua
  Data/
    Defaults.lua
```

## 6. 模块职责

### 6.1 Init.lua
- 插件入口
- 初始化 SavedVariables
- 调用 Core:Init()

### 6.2 Core.lua
- 统一模块装配
- 初始化顺序管理
- 错误兜底

### 6.3 Config.lua
- 读取/写入配置
- 合并默认配置
- 提供 Get/Set API

### 6.4 Events.lua
- 注册所有 WoW 事件
- 将聊天事件转给 Parser
- 将战斗状态事件转给 CombatGuard

### 6.5 Parser.lua
- 将原始事件参数转为标准 message 对象
- 进行基础分类：whisper / guild / party / raid / trade / system

### 6.6 Filters.lua
- 重复消息折叠
- 关键词高亮
- 自己名字提醒
- 黑白名单预留接口

### 6.7 Router.lua
- 决定消息应该进入哪些逻辑视图
- 支持世界 / 交易 / 队伍消息分流

### 6.8 NativeEnhancer.lua
- 时间戳
- 频道缩写
- 玩家名职业色
- 原生聊天框安全增强

### 6.9 WhisperIndex.lua
- 维护最近密语联系人列表
- 提供 reply-to-last 能力

### 6.10 CombatGuard.lua
- 维护 inCombat 状态
- 拦截高风险操作
- 脱战后执行延迟队列

### 6.11 Diagnostics.lua
- 记录错误计数
- 生成调试信息
- 触发安全降级

### 6.12 Commands.lua
提供命令：
- `/mychat`
- `/mychat safe`
- `/mychat reset`
- `/mychat debug`
- `/mychat reply`

### 6.13 UI/SettingsPanel.lua
- 基础设置界面
- 开关：时间戳 / 缩写 / 高亮 / 分流 / 折叠

### 6.14 UI/MirrorPanel.lua
- 可选辅助消息面板
- 默认关闭
- 仅作为镜像视图，不接管主聊天框

## 7. 配置模型

```lua
MyChatDB = {
  profile = {
    autoJoinChannels = {"世界频道"},
    restoreCustomChannels = true,
    showTimestamps = true,
    abbreviateChannels = true,
    colorPlayerNamesByClass = true,
    highlightKeywords = {"来T", "来奶", "集合"},
    highlightSelfName = true,
    enableWhisperIndex = true,
    enableRepeatCollapse = true,
    routeWorldTradeParty = true,
    mirrorPanelEnabled = false,
    safeMode = true,
  },
  runtime = {
    lastWhisperTargets = {},
    joinedChannels = {},
  }
}
```

## 8. Agent 可执行任务拆解

以下任务定义为 Agent 可直接执行的 backlog。

## Task-01: 初始化插件骨架
**目标**：创建 TOC、入口文件、基础模块文件。  
**输入**：本方案第 5 节目录结构。  
**输出**：可加载的最小插件骨架。  
**完成标准**：登录游戏后插件可正常加载，无 Lua 报错。

## Task-02: 搭建配置系统
**目标**：实现默认配置、配置读取与写入。  
**输入**：本方案第 7 节配置模型。  
**输出**：Config.lua + Defaults.lua。  
**完成标准**：修改配置后 reload 仍可保留。

## Task-03: 搭建事件总线
**目标**：监听聊天与战斗事件并分发。  
**输入**：第 4.1 节事件列表。  
**输出**：Events.lua + MessageBus.lua。  
**完成标准**：收到聊天事件后能生成日志输出。

## Task-04: 实现消息标准化
**目标**：将不同聊天事件转为统一 message 对象。  
**输入**：第 4.2 节 message 结构。  
**输出**：Parser.lua。  
**完成标准**：各种频道消息都能生成标准对象。

## Task-05: 实现原生聊天增强
**目标**：实现时间戳、频道缩写、职业色。  
**输入**：MVP 功能 3/4/5。  
**输出**：NativeEnhancer.lua。  
**完成标准**：原生聊天框中可见增强效果；无直接覆写高风险核心方法。

## Task-06: 实现关键词高亮
**目标**：支持关键词列表和自己名字高亮。  
**输入**：MVP 功能 6/7。  
**输出**：Filters.lua。  
**完成标准**：命中关键字时显示特殊颜色或前缀提示。

## Task-07: 实现最近密语索引
**目标**：维护最近密语联系人并支持快捷回复。  
**输入**：MVP 功能 8/9。  
**输出**：WhisperIndex.lua + Commands.lua。  
**完成标准**：`/mychat reply` 可回复最近密语对象。

## Task-08: 实现重复消息折叠
**目标**：在短时间窗口内折叠重复消息。  
**输入**：MVP 功能 10。  
**输出**：Filters.lua 扩展。  
**完成标准**：重复消息被折叠为“重复 N 次”形式。

## Task-09: 实现频道分流
**目标**：支持世界 / 交易 / 队伍消息分流到逻辑视图。  
**输入**：MVP 功能 11。  
**输出**：Router.lua。  
**完成标准**：分流规则可配置，且默认不破坏原生显示。

## Task-10: 实现自动加入与恢复频道
**目标**：自动加入世界频道并恢复自定义频道。  
**输入**：MVP 功能 1/2。  
**输出**：Events.lua + Commands.lua + Config.lua。  
**完成标准**：登录、切图或 reload 后可恢复指定频道。

## Task-11: 实现 CombatGuard
**目标**：战斗中拦截高风险操作并支持脱战恢复。  
**输入**：第 4.5 节 Safety Layer。  
**输出**：CombatGuard.lua。  
**完成标准**：战斗中不做重排、重建、显隐类危险操作。

## Task-12: 实现恢复与调试命令
**目标**：支持一键恢复默认聊天设置和调试输出。  
**输入**：MVP 功能 12。  
**输出**：Commands.lua + Diagnostics.lua。  
**完成标准**：`/mychat reset` 与 `/mychat debug` 可工作。

## Task-13: 实现设置面板
**目标**：提供开关界面。  
**输入**：功能开关项。  
**输出**：UI/SettingsPanel.lua。  
**完成标准**：可在 UI 中修改主要功能开关。

## Task-14: 可选镜像面板
**目标**：实现不接管原生聊天的辅助视图。  
**输入**：第 6.14 节。  
**输出**：UI/MirrorPanel.lua。  
**完成标准**：默认关闭，开启后显示镜像消息流。

## 9. 开发顺序

推荐顺序：

1. Task-01 初始化骨架
2. Task-02 配置系统
3. Task-03 事件总线
4. Task-04 标准化
5. Task-05 原生聊天增强
6. Task-06 关键词高亮
7. Task-07 最近密语
8. Task-08 重复折叠
9. Task-09 频道分流
10. Task-10 自动加入频道
11. Task-11 CombatGuard
12. Task-12 恢复与调试
13. Task-13 设置面板
14. Task-14 镜像面板

## 10. 验收标准

### 10.1 功能验收
- 登录后自动加入世界频道
- reload 后恢复频道状态
- 聊天框显示时间戳与频道缩写
- 玩家名按职业着色
- 关键词与自己名字被高亮
- 可回复最近密语
- 重复消息可折叠
- 世界 / 交易 / 队伍消息可分流
- `/mychat reset` 可恢复默认设置

### 10.2 稳定性验收
- 战斗中无致命 Lua 报错
- 不直接覆盖高风险核心方法
- 脱战后延迟队列可恢复执行
- 关闭插件后原生聊天功能不受影响

### 10.3 兼容性验收
- 仅增强原生聊天，不接管核心链路
- 在常见 UI 组合下不导致聊天完全不可见
- 出错时自动退回安全模式

## 11. 风险与规避

### 风险 1：战斗中 UI 操作导致聊天失效
规避：
- 所有高风险 UI 操作必须经过 CombatGuard
- 战斗中只保留只读增强

### 风险 2：核心方法覆写导致 taint 扩散
规避：
- 避免直接覆写 AddMessage 等核心方法
- 优先采用安全增强和外围渲染

### 风险 3：频道恢复逻辑不稳定
规避：
- 加入频道动作做重试节流
- 区分首次登录、切图、reload

### 风险 4：过滤逻辑误伤消息
规避：
- 默认折叠而不是删除
- 提供白名单和快速关闭开关

## 12. Agent 执行说明

Agent 执行本方案时应遵守以下规则：

1. 优先按第 9 节顺序完成任务。
2. 每完成一个任务，更新对应模块的验收状态。
3. 若发现某实现需要战斗中修改聊天框结构，应改为脱战后延迟执行。
4. 若某功能需要直接替换原生核心方法，应停止并回退到外围增强方案。
5. 任何新增高级能力都不得破坏 MVP 稳定性。

## 13. 交付物

本方案最终交付内容应包括：

- 开发方案文档（本文件）
- 插件目录骨架
- Agent 任务清单
- 验收清单
- 风险规避说明

## 14. 推荐后续扩展

在 MVP 稳定后，再考虑：

- 招募消息半结构化识别
- 交易广告分类
- 多标签镜像视图
- 跨角色配置同步
- 战斗后消息摘要

