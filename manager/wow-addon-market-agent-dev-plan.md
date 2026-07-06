# 魔兽世界插件管理系统：Addon Market 插件市场 Agent 开发文档

版本：v0.1  
适用项目：WoW Addon Manager  
目标平台：macOS + Windows 11  
推荐技术栈：Tauri + React + TypeScript + Rust + SQLite  
本文定位：作为既有插件管理系统技术方案的补充文档，指导 agent 实现插件市场能力。

---

## 1. 背景与目标

当前 WoW Addon Manager 已规划以下基础能力：

1. 识别本地 WoW 客户端目录。
2. 扫描 `Interface/AddOns`。
3. 解析 `.toc`。
4. 从 zip / URL / Provider 安装插件。
5. 安装前备份、失败回滚。
6. 管理 `WTF` 配置快照。
7. 管理插件 Profile。
8. 支持 macOS 和 Windows 11。

现在需要在此基础上新增 **Addon Market 插件市场**。

插件市场的目标不是简单接入某一个插件源，而是实现：

> 多插件源聚合搜索 + 统一展示 + 去重排序 + 本地安装状态匹配 + 来源绑定 + 安装入口。

---

## 2. 插件市场定位

插件市场不是某个 Provider，也不是 CurseForge / Wago / GitHub 的页面代理。

正确定位：

```text
Addon Market = Provider 之上的产品聚合层
```

整体关系：

```text
AddonMarket UI
  ↓
MarketService
  ↓
ProviderRegistry
  ↓
Providers
  ├── LocalZipProvider
  ├── ManualUrlProvider
  ├── GitHubReleaseProvider
  ├── WagoProvider
  ├── CurseForgeProvider
  ├── WowInterfaceProvider
  └── TukuiProvider
  ↓
Installer
  ↓
Scanner / Database / ConfigSnapshot / Rollback
```

核心原则：

1. **Provider 只负责搜索、获取文件列表、下载文件。**
2. **MarketService 负责聚合、去重、排序、匹配本地状态、来源绑定。**
3. **Installer 负责安装、备份、回滚。**
4. **AddonMarket UI 只负责展示和交互。**
5. **市场层不直接操作本地文件系统。**
6. **市场层不解压 zip。**
7. **市场层不直接写入 `AddOns`。**

---

## 3. 新增模块结构

在原项目基础上新增以下模块。

### 3.1 Rust 后端新增目录

```text
src-tauri/src/
  market/
    mod.rs
    market_service.rs
    market_models.rs
    market_ranker.rs
    market_deduper.rs
    market_cache.rs
    provider_registry.rs
    source_binding_service.rs
    recommendation_service.rs
```

### 3.2 Command 新增文件

```text
src-tauri/src/commands/
  market_commands.rs
```

### 3.3 Repository 新增文件

```text
src-tauri/src/infra/db/repositories/
  market_cache_repository.rs
  addon_source_binding_repository.rs
  market_recommendation_repository.rs
```

### 3.4 前端新增文件

```text
src/
  pages/
    AddonMarketPage.tsx
    MarketAddonDetailPage.tsx

  components/
    market/
      MarketSearchBar.tsx
      MarketFilterPanel.tsx
      MarketAddonCard.tsx
      MarketAddonSourceList.tsx
      MarketAddonDetail.tsx
      MarketInstallDialog.tsx
      ProviderBadge.tsx
      InstalledStateBadge.tsx

  services/
    marketApi.ts

  stores/
    marketStore.ts

  types/
    market.ts
```

---

## 4. 模块职责

## 4.1 MarketService

`MarketService` 是插件市场核心编排层。

负责：

1. 接收市场搜索请求。
2. 并发调用多个 Provider。
3. 将不同 Provider 的 `RemoteAddon` 转换为统一的 `MarketAddon`。
4. 对搜索结果进行去重。
5. 对搜索结果进行排序。
6. 匹配本地已安装状态。
7. 读取和写入市场缓存。
8. 管理本地插件与远程来源的绑定关系。
9. 调用 Provider + Installer 完成市场安装。

不负责：

1. 不实现具体 Provider。
2. 不直接操作文件系统。
3. 不解压 zip。
4. 不直接修改 `AddOns`。
5. 不直接实现 UI 逻辑。
6. 不绕过 Installer 的备份和回滚机制。

---

## 4.2 ProviderRegistry

`ProviderRegistry` 负责管理所有可用 Provider。

负责：

1. 注册 Provider。
2. 根据 `AddonProviderKind` 获取 Provider 实例。
3. 返回当前启用的 Provider 列表。
4. 返回当前可搜索的 Provider 列表。
5. 隔离 Provider 初始化差异。
6. 处理 Provider 不可用状态。

示意接口：

```rust
pub struct ProviderRegistry {
    providers: HashMap<AddonProviderKind, Arc<dyn AddonProvider>>,
}

impl ProviderRegistry {
    pub fn get(&self, kind: &AddonProviderKind) -> Option<Arc<dyn AddonProvider>>;

    pub fn list_enabled(&self) -> Vec<AddonProviderKind>;

    pub fn list_searchable(&self) -> Vec<AddonProviderKind>;
}
```

---

## 4.3 MarketRanker

`MarketRanker` 负责计算市场搜索结果排序分。

排序不应只依赖下载量，而应该综合：

1. 搜索匹配度。
2. 来源可信度。
3. 更新时间。
4. 下载量 / 热度。
5. 当前游戏版本兼容性。
6. 用户是否已绑定该来源。
7. 本地是否已安装。

推荐分数模型：

```text
score =
  match_score * 0.35
+ trust_score * 0.25
+ freshness_score * 0.15
+ popularity_score * 0.15
+ compatibility_score * 0.10
```

---

## 4.4 MarketDeduper

`MarketDeduper` 负责合并不同 Provider 中可能重复的插件。

例如：

```text
CurseForge: WeakAuras
Wago: WeakAuras
GitHub: WeakAuras/WeakAuras2
```

市场层应尽量合并为一个 `MarketAddon`，并在 `sources` 字段中展示多个来源。

去重依据：

1. 标准化插件名。
2. `.toc Title`。
3. 目录名。
4. 作者名。
5. Provider 返回的 slug。
6. 用户已有绑定关系。
7. 已安装插件的 `remote_id` / `source_url`。

去重原则：

> 第一版宁可少合并，也不要错误合并。

---

## 4.5 MarketCache

`MarketCache` 负责缓存市场搜索结果。

目标：

1. 避免每次搜索都请求多个外部源。
2. 降低 Provider 请求失败对用户体验的影响。
3. 支持离线或半离线展示历史结果。

缓存策略：

```text
默认 TTL：30 分钟
强制刷新：用户点击刷新时绕过缓存
Provider 失败：允许返回其他 Provider 结果 + 失败警告
```

---

## 4.6 SourceBindingService

`SourceBindingService` 负责管理本地插件与远程来源的绑定关系。

典型场景：

1. 用户从 GitHub 安装了某插件，后续更新默认继续使用 GitHub。
2. 用户手动把本地插件绑定到 CurseForge 某个 `remote_id`。
3. 用户将某个来源设置为 `pinned`，避免自动切换来源。
4. 搜索结果中识别某个插件已经安装。

约束：

1. 一个本地插件可以绑定多个来源。
2. 同一时间只能有一个 pinned 来源。
3. 新 pinned 来源写入时，必须取消其他 pinned 来源。

---

## 5. 核心领域模型

## 5.1 MarketAddon

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketAddon {
    pub id: String,
    pub canonical_name: String,
    pub title: String,
    pub summary: Option<String>,
    pub authors: Vec<String>,
    pub categories: Vec<String>,
    pub game_flavors: Vec<GameFlavor>,
    pub sources: Vec<AddonSourceCandidate>,
    pub installed_state: Option<InstalledAddonState>,
    pub score: f64,
    pub badges: Vec<String>,
}
```

字段说明：

| 字段 | 含义 |
|---|---|
| `id` | 市场聚合 ID，不等同于 Provider remote_id |
| `canonical_name` | 标准化名称，用于去重 |
| `title` | 展示标题 |
| `summary` | 插件简介 |
| `authors` | 作者列表 |
| `categories` | 分类 |
| `game_flavors` | 支持的游戏版本 |
| `sources` | 可用来源列表 |
| `installed_state` | 本地安装状态 |
| `score` | 市场排序分 |
| `badges` | 展示标签，如 Recommended / Installed / Pinned |

---

## 5.2 AddonSourceCandidate

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddonSourceCandidate {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    pub source_url: Option<String>,
    pub latest_version: Option<String>,
    pub latest_file_id: Option<String>,
    pub updated_at: Option<i64>,
    pub download_count: Option<i64>,
    pub trust_score: f64,
    pub match_score: f64,
    pub compatibility_score: f64,
    pub is_pinned: bool,
    pub is_official: bool,
}
```

---

## 5.3 InstalledAddonState

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledAddonState {
    pub installation_id: String,
    pub local_addon_id: String,
    pub folder_name: String,
    pub installed_version: Option<String>,
    pub installed_provider: Option<AddonProviderKind>,
    pub remote_id: Option<String>,
    pub update_available: bool,
    pub pinned_source: bool,
}
```

---

## 5.4 MarketAddonDetail

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketAddonDetail {
    pub addon: MarketAddon,
    pub description: Option<String>,
    pub changelog: Option<String>,
    pub files: Vec<AddonFile>,
    pub dependencies: Vec<MarketDependency>,
    pub screenshots: Vec<String>,
    pub homepage_url: Option<String>,
    pub license: Option<String>,
}
```

---

## 5.5 MarketDependency

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketDependency {
    pub name: String,
    pub provider: Option<AddonProviderKind>,
    pub remote_id: Option<String>,
    pub required: bool,
    pub installed: bool,
}
```

---

## 5.6 MarketSearchInput

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketSearchInput {
    pub keyword: String,
    pub installation_id: Option<String>,
    pub game_flavor: Option<GameFlavor>,
    pub providers: Option<Vec<AddonProviderKind>>,
    pub category: Option<String>,
    pub installed_only: Option<bool>,
    pub page: Option<u32>,
    pub page_size: Option<u32>,
    pub force_refresh: Option<bool>,
}
```

---

## 5.7 MarketSearchResult

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketSearchResult {
    pub items: Vec<MarketAddon>,
    pub total: usize,
    pub page: u32,
    pub page_size: u32,
    pub provider_errors: Vec<ProviderSearchError>,
    pub from_cache: bool,
}
```

---

## 5.8 ProviderSearchError

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderSearchError {
    pub provider: AddonProviderKind,
    pub code: AppErrorCode,
    pub message: String,
}
```

---

## 6. Tauri Command API

新增以下 commands。

---

## 6.1 search_market_addons

TypeScript API：

```ts
export async function searchMarketAddons(input: {
  keyword: string;
  installationId?: string;
  gameFlavor?: GameFlavor;
  providers?: AddonProviderKind[];
  category?: string;
  installedOnly?: boolean;
  page?: number;
  pageSize?: number;
  forceRefresh?: boolean;
}): Promise<MarketSearchResult>;
```

Rust Command：

```rust
#[tauri::command]
pub async fn search_market_addons(
    input: MarketSearchInput,
    state: State<'_, AppState>,
) -> Result<MarketSearchResult, AppError> {
    state.market_service.search(input).await
}
```

行为要求：

1. `keyword` 为空时，可以返回推荐插件或热门插件。
2. 如果指定 `providers`，只搜索指定 Provider。
3. 如果未指定 `providers`，搜索所有启用 Provider。
4. 单个 Provider 失败不能导致整个搜索失败。
5. 返回值必须包含 `provider_errors`。
6. 如果使用缓存，`from_cache = true`。

---

## 6.2 get_market_addon_detail

```ts
export async function getMarketAddonDetail(input: {
  marketAddonId: string;
  provider?: AddonProviderKind;
  remoteId?: string;
  installationId?: string;
}): Promise<MarketAddonDetail>;
```

行为要求：

1. 如果传入 `provider + remoteId`，优先从指定 Provider 获取详情。
2. 如果只传入 `marketAddonId`，从缓存或 source candidates 中选择最佳来源。
3. 详情页需要包含文件列表。
4. 如果 Provider 不支持详情接口，返回已有基础信息即可。

---

## 6.3 install_market_addon

```ts
export async function installMarketAddon(input: {
  installationId: string;
  marketAddonId: string;
  provider: AddonProviderKind;
  remoteId: string;
  fileId?: string;
  createSnapshotBeforeInstall?: boolean;
  pinSource?: boolean;
}): Promise<InstallResult>;
```

行为要求：

1. 根据 provider 获取 `AddonFile`。
2. 调用 Provider 下载文件。
3. 调用 Installer 创建安装计划。
4. 如果 `createSnapshotBeforeInstall = true`，调用 ConfigService 创建配置快照。
5. 调用 Installer 执行安装。
6. 安装成功后写入 `addon_source_bindings`。
7. 如果 `pinSource = true`，后续更新优先使用该来源。
8. 安装失败必须返回 Installer 的结构化错误。

---

## 6.4 bind_addon_source

```ts
export async function bindAddonSource(input: {
  installationId: string;
  localAddonId: string;
  provider: AddonProviderKind;
  remoteId: string;
  sourceUrl?: string;
  pinned: boolean;
  confidence?: number;
}): Promise<void>;
```

行为要求：

1. 允许用户手动绑定本地插件到远程来源。
2. 一个本地插件可以有多个绑定来源。
3. 同一时间只能有一个 pinned 来源。
4. 新 pinned 来源写入时，需要取消其他 pinned 来源。

---

## 6.5 get_recommended_addons

```ts
export async function getRecommendedAddons(input: {
  installationId?: string;
  gameFlavor: GameFlavor;
  scenario?: "raid" | "mythic_plus" | "pvp" | "leveling" | "economy" | "ui" | "general";
  limit?: number;
}): Promise<MarketAddon[]>;
```

行为要求：

1. 第一版可使用内置推荐清单。
2. 推荐结果仍需匹配本地安装状态。
3. 推荐结果仍需包含来源候选。
4. 后续可以接远程推荐或社区推荐。

---

## 7. 数据库设计

在原有 schema 基础上新增以下表。

---

## 7.1 market_cache

```sql
CREATE TABLE IF NOT EXISTS market_cache (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  query TEXT NOT NULL,
  game_flavor TEXT,
  category TEXT,
  result_json TEXT NOT NULL,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_market_cache_query
ON market_cache(provider, query, game_flavor, category);
```

说明：

- 用于缓存 Provider 搜索结果。
- `result_json` 存储标准化后的 `RemoteAddon[]` 或 `MarketAddon[]`。
- 缓存过期后自动刷新。

---

## 7.2 addon_source_bindings

```sql
CREATE TABLE IF NOT EXISTS addon_source_bindings (
  id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  addon_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  remote_id TEXT NOT NULL,
  source_url TEXT,
  pinned INTEGER NOT NULL DEFAULT 0,
  confidence REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  UNIQUE(installation_id, addon_id, provider, remote_id),
  FOREIGN KEY(installation_id) REFERENCES installations(id),
  FOREIGN KEY(addon_id) REFERENCES addons(id)
);

CREATE INDEX IF NOT EXISTS idx_addon_source_bindings_addon
ON addon_source_bindings(installation_id, addon_id);

CREATE INDEX IF NOT EXISTS idx_addon_source_bindings_remote
ON addon_source_bindings(provider, remote_id);
```

说明：

- 记录本地插件和远程来源之间的绑定。
- `pinned = 1` 表示用户固定使用该来源。
- `confidence` 表示系统自动匹配置信度。

---

## 7.3 market_recommendations

```sql
CREATE TABLE IF NOT EXISTS market_recommendations (
  id TEXT PRIMARY KEY,
  scenario TEXT NOT NULL,
  game_flavor TEXT NOT NULL,
  provider TEXT,
  remote_id TEXT,
  title TEXT NOT NULL,
  reason TEXT,
  priority INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_market_recommendations_scenario
ON market_recommendations(scenario, game_flavor, priority);
```

说明：

- 用于存储内置推荐插件。
- 第一版可在 migration 中写入默认数据。
- 后续可支持远程更新推荐清单。

---

## 8. 市场搜索流程

```text
用户输入关键词
  ↓
AddonMarketPage 调用 searchMarketAddons()
  ↓
MarketService 检查 market_cache
  ↓
如果缓存可用且 forceRefresh=false，返回缓存结果
  ↓
如果缓存不可用，并发调用多个 Provider.search()
  ↓
收集每个 Provider 的 RemoteAddon[]
  ↓
记录失败 Provider 到 provider_errors
  ↓
标准化 RemoteAddon -> AddonSourceCandidate
  ↓
MarketDeduper 合并重复插件
  ↓
读取本地 addons 和 addon_source_bindings
  ↓
匹配 InstalledAddonState
  ↓
MarketRanker 计算 score
  ↓
排序、分页
  ↓
写入 market_cache
  ↓
返回 MarketSearchResult
```

---

## 9. 市场安装流程

```text
用户点击安装
  ↓
选择来源 provider 和版本 fileId
  ↓
AddonMarketPage 调用 installMarketAddon()
  ↓
MarketService 调 Provider.get_files()
  ↓
选择目标 AddonFile
  ↓
Provider.download()
  ↓
Installer.createInstallPlan()
  ↓
如果 createSnapshotBeforeInstall=true，调用 ConfigService 创建快照
  ↓
Installer.executeInstallPlan()
  ↓
安装成功后 Scanner 重新扫描本地插件
  ↓
写入 addon_source_bindings
  ↓
如果 pinSource=true，将该来源设为 pinned
  ↓
返回 InstallResult
```

---

## 10. 市场更新流程

```text
用户点击检查更新
  ↓
读取本地 addons
  ↓
读取 addon_source_bindings
  ↓
优先选择 pinned 来源
  ↓
如果无 pinned 来源，使用 confidence 最高来源
  ↓
Provider.get_files()
  ↓
比较远程版本、发布时间、Interface 版本
  ↓
生成 AddonUpdateInfo
  ↓
用户确认更新
  ↓
走 installMarketAddon / installAddonFromProvider 流程
```

更新优先级：

```text
pinned source
  >
confidence 最高来源
  >
addons.provider / addons.remote_id
  >
市场搜索自动匹配
```

---

## 11. 去重规则

`MarketDeduper` 的目标是把多个 Provider 中的同一插件合并成一个 `MarketAddon`。

### 11.1 标准化名称

```text
normalize(name):
  - 转小写
  - 去除空格
  - 去除横线、下划线
  - 去除常见后缀：classic、retail、wow、addon
  - 去除颜色标记、HTML 标签
```

### 11.2 合并规则

两个候选插件满足以下任意条件，可以认为可能相同：

1. `normalized_title` 完全相同。
2. `normalized_folder_name` 完全相同。
3. `source_url` 指向同一 GitHub repo。
4. 本地已绑定同一个 `addon_id`。
5. 作者相同且名称高度相似。
6. Provider metadata 中存在相同 project slug。

### 11.3 不应合并的情况

以下情况不要自动合并：

1. 名称相似但作者不同。
2. 一个是主插件，一个是插件包扩展。
3. 一个是 Retail，一个是 Classic 独立分支。
4. 一个是插件本体，一个是配置包。
5. 用户手动取消过合并关系。

第一版可以不做“取消合并关系”，但去重逻辑应保守。

---

## 12. 排序规则

`MarketRanker` 应输出 `score: f64`。

### 12.1 match_score

来源：

1. keyword 与 title 精确匹配。
2. keyword 与 canonical_name 匹配。
3. keyword 与 author 匹配。
4. keyword 与 summary 匹配。

建议：

```text
精确匹配 title：1.0
title 前缀匹配：0.85
title 包含：0.7
author 匹配：0.5
summary 匹配：0.3
```

### 12.2 trust_score

建议默认值：

```text
pinned source: 1.0
official/source_url verified: 0.9
curseforge: 0.85
wago: 0.85
github_release: 0.75
wowinterface: 0.65
tukui: 0.75
manual_url: 0.4
local_zip: 0.3
unknown: 0.2
```

说明：

- 这里不是评价平台质量，而是用于自动排序。
- 用户 pinned 来源必须优先。

### 12.3 freshness_score

根据更新时间计算：

```text
30 天内：1.0
90 天内：0.8
180 天内：0.6
365 天内：0.4
超过 365 天：0.2
未知：0.3
```

### 12.4 popularity_score

根据下载量、收藏量、使用量等 Provider metadata 计算。

第一版可以简单归一化：

```text
download_count 缺失：0.3
download_count 已知：log(download_count + 1) 归一化
```

### 12.5 compatibility_score

```text
明确支持当前 GameFlavor：1.0
未声明但可能兼容：0.6
明确不支持：0.0
未知：0.4
```

---

## 13. 本地已安装状态匹配

MarketService 需要根据 `installation_id` 匹配本地插件状态。

匹配来源：

1. `addons` 表。
2. `addon_source_bindings` 表。
3. `.toc Title`。
4. `folder_name`。
5. `remote_id`。
6. `source_url`。

UI 展示状态：

```text
未安装
已安装
已安装，可更新
已安装，来源未绑定
已固定来源
不兼容当前版本
```

---

## 14. 插件市场 UI 设计

## 14.1 AddonMarketPage

页面布局：

```text
顶部：搜索框 + 当前游戏版本选择
左侧：过滤器
中间：插件卡片列表
右侧/弹窗：插件详情
```

过滤器：

```text
Provider:
  - 全部
  - CurseForge
  - Wago
  - GitHub
  - WowInterface
  - Tukui

GameFlavor:
  - Retail
  - Classic
  - Classic Era
  - PTR

状态:
  - 全部
  - 未安装
  - 已安装
  - 可更新
  - 来源已绑定

排序:
  - 相关度
  - 最近更新
  - 下载量
  - 推荐度
```

---

## 14.2 MarketAddonCard

展示字段：

```text
插件名
简介
来源 badges
支持版本
更新时间
下载量
本地状态
安装 / 更新 / 查看详情按钮
```

按钮逻辑：

| 状态 | 主按钮 |
|---|---|
| 未安装 | 安装 |
| 已安装 | 查看 |
| 可更新 | 更新 |
| 不兼容 | 禁用按钮 |
| 来源未绑定 | 绑定来源 |

---

## 14.3 MarketAddonDetail

详情页展示：

1. 插件标题。
2. 简介。
3. 来源列表。
4. 文件版本列表。
5. 支持游戏版本。
6. 本地安装状态。
7. 依赖关系。
8. 更新日志。
9. 安装历史入口。
10. 来源绑定设置。

来源列表示例：

```text
来源：
- Wago：最新 1.2.3，更新时间 2026-07-01，推荐
- CurseForge：最新 1.2.2，更新时间 2026-06-30
- GitHub：最新 v1.2.3，更新时间 2026-07-01
```

---

## 14.4 MarketInstallDialog

安装弹窗需要让用户确认：

```text
安装来源
安装版本
目标 WoW 客户端
是否安装前创建配置快照
是否固定该来源用于后续更新
```

默认值：

```text
createSnapshotBeforeInstall = true
pinSource = true
```

---

## 15. Provider 失败处理

市场搜索需要支持部分失败。

例如：

```text
Wago 搜索成功
GitHub 搜索成功
CurseForge 搜索失败
```

不应整体失败，而应返回：

```json
{
  "items": [],
  "provider_errors": [
    {
      "provider": "curseforge",
      "code": "provider_error",
      "message": "CurseForge provider request failed"
    }
  ],
  "from_cache": false
}
```

UI 展示：

```text
部分来源暂时不可用：CurseForge。已展示其他来源结果。
```

---

## 16. 安全与合规约束

1. 不绕过 Provider 官方下载机制。
2. 不抓取需要登录或授权的私有内容。
3. 不伪装客户端身份绕过平台限制。
4. 不静默替换用户插件目录。
5. 不自动切换插件来源，除非用户确认。
6. 来源绑定必须可见、可修改。
7. 安装和更新前必须复用 Installer 的备份与回滚能力。
8. 市场缓存中不要存储用户隐私数据。
9. Manual URL 安装必须提示来源风险。
10. 不允许市场层直接写入 `AddOns`。

---

## 17. 与现有模块的集成点

## 17.1 与 ProviderService

MarketService 依赖 ProviderRegistry，但不直接依赖具体 Provider。

```text
MarketService
  ↓
ProviderRegistry
  ↓
AddonProvider trait
```

---

## 17.2 与 Installer

MarketService 安装插件时调用 Installer。

```text
MarketService.install_market_addon()
  ↓
Provider.download()
  ↓
Installer.create_install_plan()
  ↓
Installer.execute_install_plan()
```

---

## 17.3 与 Scanner

安装成功后需要重新扫描。

```text
Installer.execute_install_plan()
  ↓
AddonScanner.scan()
  ↓
AddonRepository.upsert()
```

---

## 17.4 与 ConfigService

如果用户选择安装前创建快照：

```text
MarketService.install_market_addon()
  ↓
ConfigService.create_config_snapshot()
  ↓
Installer.execute_install_plan()
```

---

## 17.5 与 UpdateService

`UpdateService` 应优先使用 `addon_source_bindings`。

更新优先级：

```text
pinned source
  >
confidence 最高来源
  >
addons.provider / addons.remote_id
  >
市场搜索自动匹配
```

---

# 18. Agent 任务拆解

## Agent A10：Addon Market 后端聚合层

### 目标

实现插件市场后端聚合层，包括 MarketService、ProviderRegistry、搜索聚合、去重排序、来源绑定、市场缓存和安装入口。

### 依赖

- A0 项目骨架完成。
- A3 SQLite Repository 完成。
- A7 Provider 框架完成。
- A4 Installer 完成后，才能完成 `install_market_addon` 集成。
- A2 Scanner 完成后，才能完成本地已安装状态匹配。

### 工作范围

1. 新增 `market/` 模块。
2. 实现 `MarketService`。
3. 实现 `ProviderRegistry`。
4. 实现 `MarketRanker`。
5. 实现 `MarketDeduper`。
6. 实现 `MarketCache`。
7. 实现 `SourceBindingService`。
8. 新增数据库表：
   - `market_cache`
   - `addon_source_bindings`
   - `market_recommendations`
9. 新增 Repository：
   - `MarketCacheRepository`
   - `AddonSourceBindingRepository`
   - `MarketRecommendationRepository`
10. 新增 commands：
    - `search_market_addons`
    - `get_market_addon_detail`
    - `install_market_addon`
    - `bind_addon_source`
    - `get_recommended_addons`
11. 支持 Provider 部分失败。
12. 支持本地已安装状态匹配。
13. 支持搜索缓存。
14. 支持来源 pinned。

### 不做

1. 不实现具体 Provider 的外部 API。
2. 不直接解压或安装插件。
3. 不直接操作 `AddOns` 目录。
4. 不直接实现复杂推荐算法。
5. 不做评论系统。
6. 不做截图系统。
7. 不实现云端市场服务。

### 验收标准

1. 可以同时搜索多个 Provider。
2. 某个 Provider 失败时，其他 Provider 结果仍然返回。
3. 搜索结果统一转换为 `MarketAddon`。
4. 重复插件会被合并到同一个 `MarketAddon.sources`。
5. 搜索结果包含 `score`。
6. 搜索结果能标记本地已安装状态。
7. 能把本地插件绑定到远程来源。
8. 同一插件只能有一个 pinned 来源。
9. `install_market_addon` 能调用 Provider + Installer 完成安装。
10. 市场搜索结果可以写入和读取缓存。
11. 有单元测试覆盖 ranker、deduper、cache、source binding。
12. 有集成测试覆盖多 Provider 搜索和部分失败场景。

### 推荐 Agent Prompt

```text
你负责实现魔兽世界插件管理器的 Addon Market 后端聚合层。请基于现有 Provider、Installer、Scanner、SQLite Repository 架构新增 market 模块。

目标：
实现 MarketService、ProviderRegistry、MarketRanker、MarketDeduper、MarketCache、SourceBindingService，并新增 market commands。

必须实现的 commands：
1. search_market_addons
2. get_market_addon_detail
3. install_market_addon
4. bind_addon_source
5. get_recommended_addons

设计约束：
- MarketService 不实现具体 Provider。
- MarketService 不直接操作 AddOns 目录。
- MarketService 不解压 zip。
- Provider 只负责 search/get_files/download。
- Installer 负责安装、备份、回滚。
- 单个 Provider 失败不能导致整个市场搜索失败。
- 搜索结果必须返回 provider_errors。
- 搜索结果需要统一转换为 MarketAddon。
- 相同插件需要尽量合并到同一个 MarketAddon.sources。
- 本地已安装状态需要通过 addons 和 addon_source_bindings 匹配。
- 用户 pinned 来源必须优先。
- 新增 market_cache、addon_source_bindings、market_recommendations 三张表及 repository。
- 所有错误必须转换为 AppError。
- 必须添加单元测试和集成测试。

请优先完成：
1. 数据模型
2. 数据库表和 Repository
3. ProviderRegistry
4. MarketService.search
5. MarketDeduper
6. MarketRanker
7. SourceBindingService
8. install_market_addon 与 Installer 集成
```

---

## Agent A11：Addon Market 前端页面

### 目标

实现插件市场前端 UI，包括搜索、筛选、结果展示、详情页、安装弹窗和来源绑定。

### 依赖

- A8 前端基础框架完成。
- A10 Market Commands 完成后接入真实 API。
- A10 未完成前可以使用 mock API。

### 工作范围

1. 新增 `AddonMarketPage`。
2. 新增 `MarketAddonDetailPage` 或详情弹窗。
3. 新增市场相关组件：
   - `MarketSearchBar`
   - `MarketFilterPanel`
   - `MarketAddonCard`
   - `MarketAddonSourceList`
   - `MarketAddonDetail`
   - `MarketInstallDialog`
   - `ProviderBadge`
   - `InstalledStateBadge`
4. 新增 `marketApi.ts`。
5. 新增 `marketStore.ts`。
6. 支持搜索关键词。
7. 支持 Provider 筛选。
8. 支持 GameFlavor 筛选。
9. 支持状态筛选。
10. 支持安装按钮。
11. 支持来源选择。
12. 支持 pinned 来源。
13. 支持 Provider 部分失败提示。
14. 支持 loading / empty / error 状态。

### 不做

1. 不直接调用 Provider。
2. 不直接操作文件系统。
3. 不在前端拼接本地路径。
4. 不在前端实现复杂去重排序。
5. 不在前端保存市场缓存。

### 验收标准

1. 用户可以搜索插件。
2. 用户可以按 Provider / GameFlavor / 状态筛选。
3. 搜索结果以卡片形式展示。
4. 已安装插件有明显状态标记。
5. Provider 部分失败时有非阻断提示。
6. 用户可以打开插件详情。
7. 用户可以选择来源和版本安装。
8. 用户可以选择是否安装前创建快照。
9. 用户可以选择是否固定来源。
10. 所有操作通过 `marketApi.ts` 调用 Tauri command。
11. 前端不直接拼接本地路径。

### 推荐 Agent Prompt

```text
你负责实现 Addon Market 前端页面。请基于 React + TypeScript 新增 AddonMarketPage、MarketAddonDetailPage 或详情弹窗，以及市场相关组件。

必须支持：
- 关键词搜索
- Provider 筛选
- GameFlavor 筛选
- 安装状态筛选
- 插件卡片列表
- 插件详情
- 来源列表
- 安装弹窗
- pinned 来源设置
- Provider 部分失败提示
- loading / empty / error 状态

约束：
- 前端只能通过 marketApi.ts 调用 Tauri commands。
- 前端不能直接操作文件系统。
- 前端不能拼接本地路径。
- 前端不实现复杂去重排序，去重排序由 MarketService 完成。
- A10 未完成前可以使用 mock API，但必须保留真实 API 接入点。
```

---

# 19. 对原有 Agent 任务的修改

## 19.1 修改 A3 SQLite Repository

A3 增加三张表：

```text
market_cache
addon_source_bindings
market_recommendations
```

并增加 repository：

```text
MarketCacheRepository
AddonSourceBindingRepository
MarketRecommendationRepository
```

---

## 19.2 修改 A7 Provider 框架

A7 需要确保 Provider trait 支持市场层需要的信息。

Provider 输出的 `RemoteAddon` 至少包含：

```text
provider
remote_id
title
summary
author
latest_version
game_flavors
homepage_url
source_url
download_count
updated_at
categories
```

如果某 Provider 无法提供某字段，允许为空。

---

## 19.3 修改 A8 前端 UI

A8 可以先保留 `AddonMarketPage` 路由入口，但具体市场页面交给 A11。

---

## 19.4 修改 A9 集成测试

A9 增加市场链路验收：

```text
打开插件市场
  ↓
搜索插件
  ↓
返回多个 Provider 聚合结果
  ↓
打开插件详情
  ↓
选择来源安装
  ↓
安装成功
  ↓
刷新本地插件列表
  ↓
插件显示已安装
  ↓
来源绑定成功
```

---

# 20. 插件市场最小可验收链路

第一轮必须打通以下链路：

```text
打开 AddonMarketPage
  ↓
输入关键词
  ↓
MarketService 并发搜索 Provider
  ↓
返回 MarketAddon 列表
  ↓
展示插件卡片
  ↓
打开插件详情
  ↓
选择来源和版本
  ↓
点击安装
  ↓
Provider 下载文件
  ↓
Installer 安装插件
  ↓
安装成功后扫描本地插件
  ↓
写入 addon_source_bindings
  ↓
市场页面显示已安装
```

---

# 21. 建议开发顺序

```text
第一步：A3 增加市场相关表和 repository
第二步：A10 实现 Market Models
第三步：A10 实现 ProviderRegistry
第四步：A10 实现 MarketService.search
第五步：A10 实现 MarketDeduper / MarketRanker
第六步：A10 实现 SourceBindingService
第七步：A10 实现 install_market_addon
第八步：A11 实现前端市场页面
第九步：A9 增加市场端到端测试
```

---

# 22. 插件市场第一版不做的能力

第一版不要做这些：

1. 评论系统。
2. 评分系统。
3. 插件截图抓取。
4. 社区推荐。
5. 云端账号。
6. 多设备同步。
7. 自动合并来源人工审核。
8. 复杂插件依赖自动安装。
9. 付费插件或私有插件。
10. 绕过平台限制的下载逻辑。

但需要预留：

1. `screenshots` 字段。
2. `license` 字段。
3. `dependencies` 字段。
4. `market_recommendations` 表。
5. `source binding` 机制。

---

# 23. 最终架构效果

新增插件市场后的完整架构应为：

```text
Frontend
  ├── Dashboard
  ├── AddonList
  ├── AddonMarket
  ├── ConfigSnapshots
  ├── Profiles
  └── Settings

Tauri Commands
  ├── installation_commands
  ├── addon_commands
  ├── installer_commands
  ├── config_commands
  ├── profile_commands
  ├── provider_commands
  └── market_commands

Services
  ├── InstallationService
  ├── AddonService
  ├── InstallerService
  ├── ConfigService
  ├── ProfileService
  ├── ProviderService
  └── MarketService

Market Layer
  ├── ProviderRegistry
  ├── MarketDeduper
  ├── MarketRanker
  ├── MarketCache
  ├── SourceBindingService
  └── RecommendationService

Provider Layer
  ├── LocalZipProvider
  ├── ManualUrlProvider
  ├── GitHubReleaseProvider
  ├── WagoProvider
  ├── CurseForgeProvider
  ├── WowInterfaceProvider
  └── TukuiProvider

Infrastructure
  ├── SQLite
  ├── FileSystem
  ├── Zip
  ├── HTTP
  ├── Logger
  └── PlatformAdapter
```

---

# 24. 给主控 Agent 的追加总控 Prompt

```text
现在需要在已有 WoW Addon Manager 技术方案上新增 Addon Market 插件市场能力。

请把 Addon Market 设计为 Provider 之上的聚合层，而不是某个具体插件源。市场层负责多 Provider 搜索聚合、去重、排序、本地安装状态匹配、来源绑定、缓存和安装入口。市场层不得直接操作文件系统，不得解压 zip，不得直接写 AddOns，安装必须走 Installer。

新增模块：
- market/market_service.rs
- market/provider_registry.rs
- market/market_ranker.rs
- market/market_deduper.rs
- market/market_cache.rs
- market/source_binding_service.rs
- commands/market_commands.rs

新增表：
- market_cache
- addon_source_bindings
- market_recommendations

新增 commands：
- search_market_addons
- get_market_addon_detail
- install_market_addon
- bind_addon_source
- get_recommended_addons

必须支持：
- 多 Provider 并发搜索
- Provider 部分失败但整体返回
- 统一 MarketAddon 模型
- 搜索结果去重
- 搜索结果排序
- 本地已安装状态匹配
- 用户 pinned 来源
- 搜索缓存
- 通过 Provider + Installer 安装插件

请拆分为两个 agent：
A10 实现后端市场聚合层。
A11 实现前端插件市场页面。

最终必须打通：
打开插件市场 -> 搜索插件 -> 返回多个 Provider 聚合结果 -> 打开详情 -> 选择来源安装 -> 安装成功 -> 本地插件列表刷新 -> 来源绑定成功。
```

---

# 25. 结论

增加插件市场后，系统不应该变成“某个插件源客户端”，而应该成为：

> 统一的 WoW 插件市场聚合器 + 本地插件安全安装器 + 配置保护工具。

关键收益：

1. 新增 Provider 不影响 UI 和 Installer。
2. 插件市场可聚合多个来源。
3. 本地插件可以绑定来源，后续更新更稳定。
4. 安装仍然复用原有备份和回滚机制。
5. 后续可以自然扩展推荐、分类、排行榜和社区能力。
