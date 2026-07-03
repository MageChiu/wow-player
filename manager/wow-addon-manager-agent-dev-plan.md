# 魔兽世界插件管理系统：Agent 并行开发技术设计文档

版本：v0.1  
目标平台：macOS + Windows 11  
推荐技术栈：Tauri + React + TypeScript + Rust + SQLite

---

## 1. 项目目标

设计并实现一个支持 **macOS + Windows 11** 的魔兽世界插件管理系统，核心能力包括：

1. 自动或手动识别本地 World of Warcraft 客户端目录。
2. 扫描本地插件目录并解析 `.toc` 元数据。
3. 支持插件安装、更新、卸载、回滚。
4. 支持配置备份、恢复、快照管理。
5. 支持多套 Profile 管理。
6. 支持多插件源 Provider 扩展。
7. 支持跨平台路径、权限、目录识别。
8. 提供桌面端 UI，用户无需手动操作 `AddOns` / `WTF` 目录。

核心策略：

> 终态架构一次设计，模块边界清晰拆分，通过多个 agent 并行实现。

---

## 2. 技术栈

```text
Desktop Framework: Tauri
Frontend: React + TypeScript
Backend Core: Rust
Database: SQLite
State Management: Zustand / Jotai
Build: pnpm + Vite
Package: Tauri bundler
```

选择原则：

- Tauri 负责跨平台桌面能力。
- Rust 负责文件系统、下载、解压、回滚、数据库。
- React 负责 UI 展示和交互。
- SQLite 负责本地状态持久化。
- 前端不直接操作本地文件，所有文件操作必须经过 Rust command。

---

## 3. 总体架构

```text
┌──────────────────────────────────────┐
│ UI Layer                              │
│ React / TypeScript                    │
│ Dashboard / Addons / Profiles / Config│
└───────────────────┬──────────────────┘
                    │ invoke()
┌───────────────────▼──────────────────┐
│ Command Layer                         │
│ Tauri Commands                        │
│ DTO validation / API boundary         │
└───────────────────┬──────────────────┘
                    │
┌───────────────────▼──────────────────┐
│ Application Service Layer             │
│ AddonService / ConfigService          │
│ ProfileService / InstallationService  │
└───────────────────┬──────────────────┘
                    │
┌───────────────────▼──────────────────┐
│ Domain Layer                          │
│ Addon / Provider / Profile / Snapshot │
│ InstallPlan / InstallResult           │
└───────────────────┬──────────────────┘
                    │
┌───────────────────▼──────────────────┐
│ Infrastructure Layer                  │
│ SQLite / FileSystem / Zip / HTTP      │
│ Checksum / Logger / Migration         │
└───────────────────┬──────────────────┘
                    │
┌───────────────────▼──────────────────┐
│ Platform Adapter Layer                │
│ Windows Adapter / macOS Adapter       │
│ Path / Permission / System Integration│
└──────────────────────────────────────┘
```

---

## 4. 核心设计原则

1. **前端不拼接本地路径**
   - 所有路径由 Rust 后端解析。
   - 前端只展示后端返回的路径。

2. **安装前必须生成安装计划**
   - 不允许直接解压覆盖 `AddOns`。
   - 必须先解压到临时目录，识别插件目录，再执行替换。

3. **任何破坏性操作前必须备份**
   - 插件更新前备份旧插件目录。
   - `WTF` 恢复前备份当前 `WTF`。
   - Profile 应用前生成快照。

4. **所有平台差异集中在 Platform Adapter**
   - 业务层不能散落 `if windows / if macos` 判断。

5. **Provider 可插拔**
   - LocalZip、GitHub、Wago、CurseForge 等统一实现同一接口。

6. **数据库 schema 从一开始面向终态设计**
   - 不做临时表。
   - 支持后续 migration。

7. **错误模型必须结构化**
   - 前端根据错误码展示可操作提示。
   - 后端记录详细日志。

---

## 5. 项目目录结构

```text
wow-addon-manager/
  package.json
  pnpm-lock.yaml
  index.html
  vite.config.ts
  tsconfig.json

  src/
    app/
      App.tsx
      router.tsx
      providers.tsx

    pages/
      DashboardPage.tsx
      AddonListPage.tsx
      AddonMarketPage.tsx
      ConfigSnapshotsPage.tsx
      ProfilesPage.tsx
      SettingsPage.tsx

    components/
      layout/
      addon/
      config/
      profile/
      common/

    services/
      tauriClient.ts
      addonApi.ts
      configApi.ts
      profileApi.ts
      installationApi.ts

    stores/
      addonStore.ts
      installationStore.ts
      profileStore.ts
      configStore.ts

    types/
      domain.ts
      command.ts
      errors.ts

  src-tauri/
    Cargo.toml
    tauri.conf.json

    src/
      main.rs
      lib.rs

      commands/
        mod.rs
        installation_commands.rs
        addon_commands.rs
        config_commands.rs
        profile_commands.rs
        provider_commands.rs
        settings_commands.rs

      app/
        mod.rs
        state.rs
        bootstrap.rs

      domain/
        mod.rs
        addon.rs
        installation.rs
        provider.rs
        profile.rs
        snapshot.rs
        install.rs
        errors.rs

      services/
        mod.rs
        addon_service.rs
        installation_service.rs
        config_service.rs
        profile_service.rs
        provider_service.rs
        update_service.rs

      platform/
        mod.rs
        adapter.rs
        windows.rs
        macos.rs

      infra/
        mod.rs
        db/
          mod.rs
          connection.rs
          migrations.rs
          repositories/
            addon_repository.rs
            installation_repository.rs
            profile_repository.rs
            snapshot_repository.rs
            settings_repository.rs

        fs/
          mod.rs
          file_system.rs
          path_utils.rs
          permission.rs

        archive/
          mod.rs
          zip_service.rs

        http/
          mod.rs
          http_client.rs

        checksum/
          mod.rs
          checksum_service.rs

        logging/
          mod.rs
          logger.rs

      scanner/
        mod.rs
        addon_scanner.rs
        toc_parser.rs
        addon_folder_detector.rs

      installer/
        mod.rs
        install_planner.rs
        install_executor.rs
        rollback_manager.rs

      providers/
        mod.rs
        provider_trait.rs
        local_zip_provider.rs
        github_release_provider.rs
        wago_provider.rs
        curseforge_provider.rs

      tests/
        fixtures/
          wow_retail_mock/
          addon_zips/
          toc_samples/
```

---

## 6. 领域模型设计

### 6.1 GameFlavor

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameFlavor {
    Retail,
    Classic,
    ClassicEra,
    Ptr,
    Unknown,
}
```

### 6.2 WowInstallation

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WowInstallation {
    pub id: String,
    pub display_name: String,
    pub root_path: String,
    pub flavor: GameFlavor,
    pub addon_path: String,
    pub wtf_path: String,
    pub is_valid: bool,
    pub permission: PermissionCheckResult,
    pub created_at: i64,
    pub updated_at: i64,
}
```

### 6.3 PermissionCheckResult

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionCheckResult {
    pub readable: bool,
    pub writable: bool,
    pub reason: Option<String>,
}
```

### 6.4 LocalAddon

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalAddon {
    pub id: String,
    pub installation_id: String,
    pub folder_name: String,
    pub normalized_folder_name: String,
    pub title: Option<String>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub interface_version: Option<String>,
    pub notes: Option<String>,
    pub dependencies: Vec<String>,
    pub optional_dependencies: Vec<String>,
    pub saved_variables: Vec<String>,
    pub saved_variables_per_character: Vec<String>,
    pub provider: Option<AddonProviderKind>,
    pub remote_id: Option<String>,
    pub source_url: Option<String>,
    pub status: AddonStatus,
    pub installed_at: i64,
    pub updated_at: i64,
}
```

### 6.5 AddonStatus

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AddonStatus {
    Installed,
    Disabled,
    MissingDependency,
    UpdateAvailable,
    Broken,
    Unknown,
}
```

### 6.6 AddonProviderKind

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AddonProviderKind {
    LocalZip,
    GithubRelease,
    Wago,
    CurseForge,
    ManualUrl,
}
```

### 6.7 RemoteAddon

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteAddon {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    pub title: String,
    pub summary: Option<String>,
    pub author: Option<String>,
    pub latest_version: Option<String>,
    pub game_flavors: Vec<GameFlavor>,
    pub homepage_url: Option<String>,
    pub source_url: Option<String>,
    pub download_count: Option<i64>,
    pub updated_at: Option<i64>,
}
```

### 6.8 AddonFile

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddonFile {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    pub file_id: String,
    pub file_name: String,
    pub version: Option<String>,
    pub download_url: String,
    pub checksum: Option<String>,
    pub game_flavor: GameFlavor,
    pub released_at: Option<i64>,
}
```

### 6.9 InstallPlan

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallPlan {
    pub id: String,
    pub installation_id: String,
    pub source: InstallSource,
    pub temp_extract_path: String,
    pub detected_addon_folders: Vec<DetectedAddonFolder>,
    pub target_addon_path: String,
    pub backup_path: Option<String>,
    pub actions: Vec<InstallAction>,
    pub warnings: Vec<String>,
}
```

### 6.10 InstallSource

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InstallSource {
    LocalZip {
        file_path: String,
    },
    Provider {
        provider: AddonProviderKind,
        remote_id: String,
        file_id: Option<String>,
    },
    ManualUrl {
        url: String,
    },
}
```

### 6.11 InstallAction

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InstallAction {
    BackupExistingFolder,
    RemoveExistingFolder,
    CopyNewFolder,
    UpdateDatabase,
}
```

### 6.12 InstallResult

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallResult {
    pub success: bool,
    pub installed_addons: Vec<LocalAddon>,
    pub backup_path: Option<String>,
    pub rollback_available: bool,
    pub message: Option<String>,
}
```

### 6.13 ConfigSnapshot

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigSnapshot {
    pub id: String,
    pub installation_id: String,
    pub name: String,
    pub scope: SnapshotScope,
    pub target: Option<String>,
    pub file_path: String,
    pub size_bytes: i64,
    pub addon_versions: HashMap<String, String>,
    pub description: Option<String>,
    pub created_at: i64,
}
```

### 6.14 SnapshotScope

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SnapshotScope {
    FullWtf,
    Account,
    Character,
    Addon,
}
```

### 6.15 Profile

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub id: String,
    pub installation_id: String,
    pub name: String,
    pub description: Option<String>,
    pub addon_folder_names: Vec<String>,
    pub snapshot_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}
```

---

## 7. Tauri Command API 设计

### 7.1 Installation Commands

```ts
export async function detectInstallations(): Promise<WowInstallation[]>;

export async function validateInstallationPath(input: {
  rootPath: string;
}): Promise<WowInstallation>;

export async function addInstallation(input: {
  rootPath: string;
  displayName?: string;
}): Promise<WowInstallation>;

export async function listInstallations(): Promise<WowInstallation[]>;

export async function removeInstallation(input: {
  installationId: string;
}): Promise<void>;
```

### 7.2 Addon Commands

```ts
export async function scanAddons(input: {
  installationId: string;
}): Promise<LocalAddon[]>;

export async function listAddons(input: {
  installationId: string;
}): Promise<LocalAddon[]>;

export async function disableAddon(input: {
  installationId: string;
  folderName: string;
}): Promise<LocalAddon>;

export async function enableAddon(input: {
  installationId: string;
  folderName: string;
}): Promise<LocalAddon>;

export async function uninstallAddon(input: {
  installationId: string;
  folderName: string;
  createBackup: boolean;
}): Promise<void>;
```

### 7.3 Installer Commands

```ts
export async function createInstallPlanFromZip(input: {
  installationId: string;
  zipPath: string;
}): Promise<InstallPlan>;

export async function executeInstallPlan(input: {
  planId: string;
}): Promise<InstallResult>;

export async function installAddonFromZip(input: {
  installationId: string;
  zipPath: string;
}): Promise<InstallResult>;

export async function installAddonFromProvider(input: {
  installationId: string;
  provider: AddonProviderKind;
  remoteId: string;
  fileId?: string;
}): Promise<InstallResult>;

export async function rollbackInstall(input: {
  installationId: string;
  rollbackId: string;
}): Promise<void>;
```

### 7.4 Config Commands

```ts
export async function createConfigSnapshot(input: {
  installationId: string;
  name: string;
  scope: SnapshotScope;
  target?: string;
  description?: string;
}): Promise<ConfigSnapshot>;

export async function listConfigSnapshots(input: {
  installationId: string;
}): Promise<ConfigSnapshot[]>;

export async function restoreConfigSnapshot(input: {
  snapshotId: string;
  createBackupBeforeRestore: boolean;
}): Promise<RestoreResult>;

export async function deleteConfigSnapshot(input: {
  snapshotId: string;
}): Promise<void>;
```

### 7.5 Profile Commands

```ts
export async function createProfile(input: {
  installationId: string;
  name: string;
  description?: string;
  addonFolderNames: string[];
  snapshotId?: string;
}): Promise<Profile>;

export async function listProfiles(input: {
  installationId: string;
}): Promise<Profile[]>;

export async function updateProfile(input: {
  profileId: string;
  name?: string;
  description?: string;
  addonFolderNames?: string[];
  snapshotId?: string;
}): Promise<Profile>;

export async function applyProfile(input: {
  profileId: string;
  createSnapshotBeforeApply: boolean;
}): Promise<ApplyProfileResult>;

export async function deleteProfile(input: {
  profileId: string;
}): Promise<void>;
```

### 7.6 Provider Commands

```ts
export async function searchRemoteAddons(input: {
  provider: AddonProviderKind;
  keyword: string;
  gameFlavor?: GameFlavor;
}): Promise<RemoteAddon[]>;

export async function getRemoteAddonFiles(input: {
  provider: AddonProviderKind;
  remoteId: string;
  gameFlavor?: GameFlavor;
}): Promise<AddonFile[]>;

export async function checkAddonUpdates(input: {
  installationId: string;
}): Promise<AddonUpdateInfo[]>;
```

---

## 8. 错误模型设计

所有后端错误统一返回结构化错误。

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppError {
    pub code: AppErrorCode,
    pub message: String,
    pub detail: Option<String>,
    pub recoverable: bool,
}
```

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AppErrorCode {
    InvalidInstallationPath,
    InstallationNotFound,
    AddonPathNotFound,
    WtfPathNotFound,
    PermissionDenied,
    TocParseError,
    InvalidZipFile,
    NoAddonFolderDetected,
    MultipleAddonFoldersDetected,
    InstallPlanNotFound,
    InstallFailed,
    RollbackFailed,
    SnapshotCreateFailed,
    SnapshotRestoreFailed,
    DatabaseError,
    ProviderError,
    NetworkError,
    UnsupportedPlatform,
    Unknown,
}
```

前端展示策略：

| 错误码 | 用户提示 | 建议操作 |
|---|---|---|
| `permission_denied` | 当前目录不可写 | 选择其他目录或以管理员权限运行 |
| `invalid_zip_file` | 插件压缩包无效 | 重新选择 zip 文件 |
| `no_addon_folder_detected` | 未识别到插件目录 | 检查压缩包结构 |
| `snapshot_restore_failed` | 配置恢复失败 | 使用自动备份回滚 |
| `provider_error` | 插件源请求失败 | 稍后重试或切换插件源 |

---

## 9. SQLite Schema 设计

### 9.1 installations

```sql
CREATE TABLE IF NOT EXISTS installations (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  root_path TEXT NOT NULL,
  flavor TEXT NOT NULL,
  addon_path TEXT NOT NULL,
  wtf_path TEXT NOT NULL,
  is_valid INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

### 9.2 addons

```sql
CREATE TABLE IF NOT EXISTS addons (
  id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  folder_name TEXT NOT NULL,
  normalized_folder_name TEXT NOT NULL,
  title TEXT,
  version TEXT,
  author TEXT,
  interface_version TEXT,
  notes TEXT,
  dependencies_json TEXT NOT NULL DEFAULT '[]',
  optional_dependencies_json TEXT NOT NULL DEFAULT '[]',
  saved_variables_json TEXT NOT NULL DEFAULT '[]',
  saved_variables_per_character_json TEXT NOT NULL DEFAULT '[]',
  provider TEXT,
  remote_id TEXT,
  source_url TEXT,
  status TEXT NOT NULL,
  installed_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  UNIQUE(installation_id, normalized_folder_name),
  FOREIGN KEY(installation_id) REFERENCES installations(id)
);
```

### 9.3 addon_sources

```sql
CREATE TABLE IF NOT EXISTS addon_sources (
  id TEXT PRIMARY KEY,
  addon_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  remote_id TEXT,
  source_url TEXT,
  last_checked_at INTEGER,
  latest_version TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',

  FOREIGN KEY(addon_id) REFERENCES addons(id)
);
```

### 9.4 config_snapshots

```sql
CREATE TABLE IF NOT EXISTS config_snapshots (
  id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  name TEXT NOT NULL,
  scope TEXT NOT NULL,
  target TEXT,
  file_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  addon_versions_json TEXT NOT NULL DEFAULT '{}',
  description TEXT,
  created_at INTEGER NOT NULL,

  FOREIGN KEY(installation_id) REFERENCES installations(id)
);
```

### 9.5 profiles

```sql
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  snapshot_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  FOREIGN KEY(installation_id) REFERENCES installations(id),
  FOREIGN KEY(snapshot_id) REFERENCES config_snapshots(id)
);
```

### 9.6 profile_addons

```sql
CREATE TABLE IF NOT EXISTS profile_addons (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  folder_name TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,

  UNIQUE(profile_id, folder_name),
  FOREIGN KEY(profile_id) REFERENCES profiles(id)
);
```

### 9.7 install_history

```sql
CREATE TABLE IF NOT EXISTS install_history (
  id TEXT PRIMARY KEY,
  installation_id TEXT NOT NULL,
  addon_folder_names_json TEXT NOT NULL DEFAULT '[]',
  source_type TEXT NOT NULL,
  source_ref TEXT,
  backup_path TEXT,
  status TEXT NOT NULL,
  error_message TEXT,
  created_at INTEGER NOT NULL,

  FOREIGN KEY(installation_id) REFERENCES installations(id)
);
```

### 9.8 settings

```sql
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

---

## 10. Platform Adapter 设计

### 10.1 Trait

```rust
pub trait PlatformAdapter: Send + Sync {
    fn platform_name(&self) -> &'static str;

    fn detect_wow_installations(&self) -> Result<Vec<WowInstallation>, AppError>;

    fn validate_installation_path(&self, root_path: &Path) -> Result<WowInstallation, AppError>;

    fn app_data_dir(&self) -> Result<PathBuf, AppError>;

    fn cache_dir(&self) -> Result<PathBuf, AppError>;

    fn temp_dir(&self) -> Result<PathBuf, AppError>;

    fn check_permission(&self, path: &Path) -> Result<PermissionCheckResult, AppError>;

    fn reveal_in_file_manager(&self, path: &Path) -> Result<(), AppError>;
}
```

### 10.2 Windows 默认扫描路径

```text
C:\Program Files (x86)\World of Warcraft
C:\Program Files\World of Warcraft
D:\Games\World of Warcraft
D:\World of Warcraft
```

还应支持用户手动选择目录。

### 10.3 macOS 默认扫描路径

```text
/Applications/World of Warcraft
~/Applications/World of Warcraft
```

还应支持用户手动选择目录。

### 10.4 WoW 子目录识别

```text
_retail_       -> Retail
_classic_      -> Classic
_classic_era_  -> ClassicEra
_ptr_          -> Ptr
```

每个 flavor 需要检查：

```text
<root>/<flavor_dir>/Interface/AddOns
<root>/<flavor_dir>/WTF
```

---

## 11. `.toc` 解析设计

### 11.1 输入示例

```text
Interface/AddOns/WeakAuras/WeakAuras.toc
```

### 11.2 需要解析的字段

```text
## Interface:
## Title:
## Version:
## Author:
## Notes:
## Dependencies:
## OptionalDeps:
## SavedVariables:
## SavedVariablesPerCharacter:
```

### 11.3 输出结构

```rust
pub struct TocMetadata {
    pub interface_version: Option<String>,
    pub title: Option<String>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub notes: Option<String>,
    pub dependencies: Vec<String>,
    pub optional_dependencies: Vec<String>,
    pub saved_variables: Vec<String>,
    pub saved_variables_per_character: Vec<String>,
}
```

### 11.4 解析规则

1. 只解析以 `##` 开头的元数据行。
2. key 忽略大小写。
3. value 去除首尾空格。
4. 逗号分隔字段需要拆成数组。
5. 如果目录中多个 `.toc`，优先选择与目录名相同的 `.toc`。
6. 如果没有同名 `.toc`，选择第一个可解析 `.toc`。
7. 解析失败不能导致整个扫描中断，应标记该插件为 `broken`。

---

## 12. 安装流水线设计

### 12.1 标准流程

```text
输入 zip / provider file
  ↓
准备工作目录
  ↓
下载或复制 zip 到缓存
  ↓
校验 zip
  ↓
解压到临时目录
  ↓
识别插件目录
  ↓
解析每个插件目录的 .toc
  ↓
生成 InstallPlan
  ↓
创建安装前备份
  ↓
移动旧插件目录到备份区
  ↓
复制新插件目录到 AddOns
  ↓
重新扫描 AddOns
  ↓
写入数据库
  ↓
记录 install_history
  ↓
清理临时目录
```

### 12.2 回滚流程

```text
安装失败
  ↓
停止后续动作
  ↓
删除已复制的新目录
  ↓
从 backup_path 恢复旧插件目录
  ↓
恢复数据库到安装前状态
  ↓
记录 install_history status = failed
  ↓
返回结构化错误
```

### 12.3 zip 插件目录识别规则

支持以下结构：

```text
WeakAuras/
WeakAurasOptions/
WeakAurasTemplates/
```

```text
addon-name-version/
  WeakAuras/
  WeakAurasOptions/
```

```text
addon-name-version/
  Interface/
    AddOns/
      WeakAuras/
```

识别策略：

1. 从解压根目录开始递归查找包含 `.toc` 的目录。
2. 找到 `.toc` 的目录视为候选插件目录。
3. 如果目录中 `.toc` 与目录名相同，优先级更高。
4. 如果候选目录嵌套在 `Interface/AddOns` 下，裁剪到 `AddOns` 下一级目录。
5. 多插件包允许返回多个候选目录。
6. 如果没有候选目录，返回 `NoAddonFolderDetected`。

---

## 13. 配置备份与恢复设计

### 13.1 备份范围

```text
FullWtf:
  <flavor>/WTF

Account:
  <flavor>/WTF/Account/<account>

Character:
  <flavor>/WTF/Account/<account>/<server>/<character>

Addon:
  SavedVariables 中与插件相关的 lua 文件
```

第一阶段实现建议：

```text
FullWtf
Addon
```

但模型保留 `Account` / `Character`。

### 13.2 快照存储结构

```text
<ApplicationSupport>/snapshots/
  <installation_id>/
    <snapshot_id>/
      metadata.json
      wtf.zip
```

metadata 示例：

```json
{
  "id": "snapshot_xxx",
  "installation_id": "inst_xxx",
  "name": "更新 WeakAuras 前自动备份",
  "scope": "full_wtf",
  "created_at": 1782982396,
  "addon_versions": {
    "WeakAuras": "5.12.0",
    "Details": "11.0.2"
  }
}
```

### 13.3 恢复安全策略

1. 恢复前必须创建当前 `WTF` 的临时快照。
2. 恢复前校验快照文件存在且可读。
3. 恢复不能直接覆盖，应先移动当前 `WTF` 到临时备份。
4. 恢复成功后保留临时备份一段时间。
5. 恢复失败必须把临时备份移回原位置。

---

## 14. Provider 设计

### 14.1 Provider Trait

```rust
#[async_trait]
pub trait AddonProvider: Send + Sync {
    fn kind(&self) -> AddonProviderKind;

    async fn search(
        &self,
        keyword: String,
        game_flavor: Option<GameFlavor>,
    ) -> Result<Vec<RemoteAddon>, AppError>;

    async fn get_files(
        &self,
        remote_id: String,
        game_flavor: Option<GameFlavor>,
    ) -> Result<Vec<AddonFile>, AppError>;

    async fn download(
        &self,
        file: AddonFile,
        target_dir: PathBuf,
    ) -> Result<PathBuf, AppError>;
}
```

### 14.2 第一批 Provider

| Provider | 用途 | 是否必须 |
|---|---|---|
| LocalZipProvider | 本地 zip 安装 | 必须 |
| ManualUrlProvider | URL 下载 zip | 建议 |
| GitHubReleaseProvider | GitHub release 安装 | 建议 |
| WagoProvider | 后续扩展 | 可延后 |
| CurseForgeProvider | 后续扩展 | 可延后 |

### 14.3 Provider 不负责的事情

Provider 只负责：

- 搜索。
- 获取文件列表。
- 下载文件。

Provider 不负责：

- 解压。
- 判断插件目录。
- 安装。
- 更新数据库。
- 创建备份。
- 回滚。

这些属于 Installer 和 Service 层。

---

## 15. 前端页面设计

### 15.1 Dashboard

展示：

- 当前客户端。
- 插件数量。
- 可更新数量。
- 最近配置快照。
- 最近安装历史。
- 快捷操作：扫描插件、安装 zip、创建快照、检查更新。

### 15.2 AddonListPage

功能：

- 插件列表。
- 搜索。
- 状态过滤。
- 启用/禁用。
- 卸载。
- 查看详情。
- 检查更新。

字段：

| 字段 | 来源 | 说明 |
|---|---|---|
| 插件名 | `.toc Title` | 展示名 |
| 目录名 | `folder_name` | 实际目录 |
| 当前版本 | `.toc Version` | 本地版本 |
| 来源 | `provider` | 插件源 |
| 状态 | `status` | 是否正常 |

### 15.3 AddonMarketPage

功能：

- 选择 Provider。
- 搜索远程插件。
- 查看插件详情。
- 选择文件版本。
- 安装。

第一阶段可以隐藏或仅支持 GitHub / URL。

### 15.4 ConfigSnapshotsPage

功能：

- 创建快照。
- 查看快照。
- 恢复快照。
- 删除快照。
- 查看快照关联插件版本。

### 15.5 ProfilesPage

功能：

- 创建 Profile。
- 选择插件组合。
- 绑定配置快照。
- 应用 Profile。
- 删除 Profile。

### 15.6 SettingsPage

功能：

- 管理 WoW 客户端目录。
- 设置下载缓存目录。
- 设置备份保留策略。
- 设置默认 Provider。
- 查看日志路径。

---

## 16. 测试策略

### 16.1 单元测试

必须覆盖：

1. `.toc` 解析。
2. 插件目录识别。
3. zip 结构识别。
4. path utils。
5. Provider trait mock。
6. SQLite repository。
7. InstallPlan 生成。

### 16.2 集成测试

必须覆盖：

1. mock WoW 目录扫描。
2. mock `AddOns` 插件扫描。
3. zip 安装成功。
4. zip 安装失败回滚。
5. `WTF` 快照创建。
6. `WTF` 快照恢复。
7. Profile 创建和应用。

### 16.3 跨平台测试

| 测试项 | Windows 11 | macOS |
|---|---|---|
| 手动选择目录 | 必测 | 必测 |
| 默认路径扫描 | 必测 | 必测 |
| AddOns 写入权限 | 必测 | 必测 |
| WTF 备份恢复 | 必测 | 必测 |
| zip 解压中文路径 | 必测 | 必测 |
| 应用打包安装 | 必测 | 必测 |

---

# 17. Agent 任务拆解

下面的任务卡可以直接分配给不同 agent 执行。

---

## Agent A0：项目骨架与基础契约

### 目标

创建 Tauri + React + TypeScript + Rust 项目骨架，并建立基础模块、类型、错误模型和 command 框架。

### 输入

- 本技术设计文档。
- 技术栈：Tauri + React + TypeScript + Rust + SQLite。
- 不实现完整业务，只搭建可编译骨架。

### 工作范围

1. 初始化项目结构。
2. 创建前端目录结构。
3. 创建 Rust 模块结构。
4. 定义 domain models。
5. 定义 `AppError` / `AppErrorCode`。
6. 创建基础 Tauri command。
7. 实现健康检查 command。
8. 配置基础日志。
9. 配置 SQLite 连接初始化入口，但不要求完整 schema。

### 不做

- 不实现插件扫描。
- 不实现安装逻辑。
- 不实现 UI 细节。
- 不接外部 Provider。

### 产出

- 可启动的 Tauri app。
- 前端能调用 `healthCheck()`。
- Rust domain 类型编译通过。
- 基础错误模型可序列化给前端。

### 验收标准

```text
pnpm install
pnpm tauri dev
```

能启动应用，并在前端展示 health check 成功。

### 推荐 Agent Prompt

```text
你负责实现魔兽世界插件管理器的项目骨架。请创建 Tauri + React + TypeScript + Rust 项目结构，按照技术设计文档建立 src 和 src-tauri/src 下的模块目录。定义核心 domain models、AppError、AppErrorCode，并实现一个 health_check Tauri command。不要实现业务逻辑。要求项目可编译、前端可调用 health_check 并显示结果。
```

---

## Agent A1：Platform Adapter 与客户端目录识别

### 依赖

- A0 完成。

### 目标

实现 Windows/macOS 平台适配层，支持自动检测和手动校验 WoW 安装目录。

### 工作范围

1. 实现 `PlatformAdapter` trait。
2. 实现 `WindowsPlatformAdapter`。
3. 实现 `MacPlatformAdapter`。
4. 实现默认路径扫描。
5. 实现手动路径校验。
6. 识别 `_retail_`、`_classic_`、`_classic_era_`、`_ptr_`。
7. 生成 `WowInstallation`。
8. 实现权限检测。
9. 实现对应 Tauri commands：
   - `detect_installations`
   - `validate_installation_path`
   - `add_installation`
   - `list_installations`

### 不做

- 不扫描插件。
- 不写安装器。
- 不做 UI 完整页面。

### 产出

- 可返回本地 WoW installation 列表。
- 可校验用户传入目录。
- 可识别 `AddOns` / `WTF` 路径。

### 验收标准

1. 给定 mock WoW 目录，能识别 installation。
2. 无效目录返回 `InvalidInstallationPath`。
3. 无权限目录返回 `PermissionDenied` 或 `permission.writable=false`。
4. macOS/Windows 路径逻辑不散落到业务层。

### 推荐 Agent Prompt

```text
你负责实现 Platform Adapter 和 WoW 客户端目录识别。基于现有 Tauri 项目骨架，实现 PlatformAdapter trait、WindowsPlatformAdapter、MacPlatformAdapter。支持默认路径扫描和手动路径校验，识别 _retail_、_classic_、_classic_era_、_ptr_，生成 WowInstallation。实现 detect_installations 和 validate_installation_path commands。请添加 mock 目录测试。
```

---

## Agent A2：`.toc` 解析与插件扫描

### 依赖

- A0 完成。
- A1 最好完成，但可用 mock installation 并行开发。

### 目标

实现 `AddOns` 目录扫描和 `.toc` 元数据解析。

### 工作范围

1. 实现 `TocParser`。
2. 实现 `AddonScanner`。
3. 遍历 `Interface/AddOns`。
4. 解析 `.toc` 字段。
5. 处理多个 `.toc` 文件优先级。
6. 处理解析失败的插件。
7. 输出 `LocalAddon`。
8. 实现 command：
   - `scan_addons`
   - `list_addons`

### 不做

- 不接 Provider。
- 不判断远程更新。
- 不做安装。

### 产出

- 给定 `AddOns` 目录，返回插件列表。
- 支持依赖、SavedVariables 字段解析。

### 验收标准

1. 能解析标准 `.toc`。
2. 能解析缺字段 `.toc`。
3. 能处理中文、空格、大小写差异。
4. 插件目录无 `.toc` 时不崩溃。
5. 多插件目录扫描失败不影响其他插件。

### 推荐 Agent Prompt

```text
你负责实现魔兽插件扫描和 .toc 解析。请实现 TocParser、AddonScanner，并提供 scan_addons command。扫描 Interface/AddOns 下的插件目录，优先解析与目录同名的 .toc 文件，提取 Interface、Title、Version、Author、Notes、Dependencies、OptionalDeps、SavedVariables、SavedVariablesPerCharacter。解析失败的插件标记为 broken，不要中断整个扫描。请添加 toc parser 单元测试和 mock AddOns 集成测试。
```

---

## Agent A3：SQLite Schema 与 Repository

### 依赖

- A0 完成。

### 目标

实现 SQLite 数据层、schema migration 和 repository。

### 工作范围

1. 创建 SQLite connection。
2. 实现 migration runner。
3. 创建 schema：
   - `installations`
   - `addons`
   - `addon_sources`
   - `config_snapshots`
   - `profiles`
   - `profile_addons`
   - `install_history`
   - `settings`
4. 实现 repositories：
   - `InstallationRepository`
   - `AddonRepository`
   - `SnapshotRepository`
   - `ProfileRepository`
   - `SettingsRepository`
5. 支持 JSON 字段序列化/反序列化。
6. 支持基础 CRUD。

### 不做

- 不做业务编排。
- 不做 UI。
- 不做安装逻辑。

### 产出

- 数据库自动初始化。
- repository 单元测试。
- command/service 可调用 repository。

### 验收标准

1. 首次启动自动创建数据库。
2. 重复启动不会重复执行错误 migration。
3. CRUD 测试通过。
4. JSON 字段读写正常。
5. 数据库路径位于 app data dir。

### 推荐 Agent Prompt

```text
你负责实现 SQLite 数据层。请根据技术设计文档实现 migrations、connection、repositories。需要创建 installations、addons、addon_sources、config_snapshots、profiles、profile_addons、install_history、settings 表。实现基础 CRUD，并处理 JSON 字段序列化。数据库文件应放在 PlatformAdapter 返回的 app_data_dir 下。请添加 repository 单元测试。
```

---

## Agent A4：安装计划、zip 识别与安全安装器

### 依赖

- A0 完成。
- A2 可并行，但最终要集成 `TocParser`。
- A3 可并行，但最终要写入 `install_history` / `addons`。

### 目标

实现插件 zip 安装流水线，包括安装计划、备份、替换和回滚。

### 工作范围

1. 实现 `ZipService`。
2. 实现 `AddonFolderDetector`。
3. 实现 `InstallPlanner`。
4. 实现 `InstallExecutor`。
5. 实现 `RollbackManager`。
6. 支持本地 zip 安装。
7. 识别多种 zip 结构。
8. 安装前备份旧插件目录。
9. 失败时回滚。
10. 实现 commands：
    - `create_install_plan_from_zip`
    - `execute_install_plan`
    - `install_addon_from_zip`
    - `rollback_install`

### 不做

- 不接远程 Provider。
- 不做复杂 UI。
- 不实现 CurseForge/Wago。

### 产出

- 可从本地 zip 安装插件。
- 安装失败不会破坏旧插件。
- 支持多目录插件包。

### 验收标准

1. 标准 zip 可安装。
2. `Interface/AddOns` 嵌套 zip 可安装。
3. 多插件目录 zip 可安装。
4. 无 `.toc` zip 返回 `NoAddonFolderDetected`。
5. 更新已有插件前会备份。
6. 安装失败可恢复旧目录。
7. `install_history` 有记录。

### 推荐 Agent Prompt

```text
你负责实现插件安装流水线。请实现 ZipService、AddonFolderDetector、InstallPlanner、InstallExecutor、RollbackManager。支持从本地 zip 安装插件，先解压到临时目录，再识别包含 .toc 的插件目录，生成 InstallPlan，执行时备份旧目录、复制新目录、失败自动回滚。实现 create_install_plan_from_zip、execute_install_plan、install_addon_from_zip、rollback_install commands。请添加 zip fixture 测试，包括标准结构、多插件结构、Interface/AddOns 嵌套结构和无效 zip。
```

---

## Agent A5：配置快照、WTF 备份与恢复

### 依赖

- A0 完成。
- A1 完成。
- A3 完成。

### 目标

实现 `WTF` 配置快照创建、恢复、删除和元数据管理。

### 工作范围

1. 实现 `ConfigService`。
2. 支持 `FullWtf` 快照。
3. 支持 `Addon` 范围快照，第一版可简化。
4. 快照压缩为 zip。
5. 写入 `metadata.json`。
6. 保存数据库记录。
7. 恢复前自动备份当前 `WTF`。
8. 恢复失败自动回滚。
9. 实现 commands：
   - `create_config_snapshot`
   - `list_config_snapshots`
   - `restore_config_snapshot`
   - `delete_config_snapshot`

### 不做

- 不做复杂 Lua diff。
- 不做云同步。
- 不做账号/角色级别复杂选择，模型保留即可。

### 产出

- 可备份 `WTF`。
- 可恢复 `WTF`。
- 可删除快照。

### 验收标准

1. `WTF` 存在时可创建 `FullWtf` 快照。
2. 快照包含 `metadata.json`。
3. 数据库记录正确。
4. 恢复前自动创建当前 `WTF` 备份。
5. 恢复失败不破坏当前 `WTF`。
6. 删除快照同时删除文件和数据库记录。

### 推荐 Agent Prompt

```text
你负责实现配置快照和 WTF 备份恢复。请实现 ConfigService，支持 FullWtf 快照创建、压缩存储、metadata.json、数据库记录、列表查询、恢复和删除。恢复前必须自动备份当前 WTF，恢复失败必须回滚。实现 create_config_snapshot、list_config_snapshots、restore_config_snapshot、delete_config_snapshot commands。请添加 mock WTF 目录测试。
```

---

## Agent A6：Profile 管理与应用

### 依赖

- A0 完成。
- A2 完成。
- A3 完成。
- A5 最好完成。

### 目标

实现 Profile 创建、编辑、删除、应用。

### 工作范围

1. 实现 `ProfileService`。
2. Profile 记录插件组合。
3. Profile 可绑定 `ConfigSnapshot`。
4. 应用 Profile 时：
   - 可选创建当前快照。
   - 启用 Profile 内插件。
   - 禁用 Profile 外插件。
5. 插件启停采用目录重命名策略：
   - 启用：`Addon.disabled` -> `Addon`
   - 禁用：`Addon` -> `Addon.disabled`
6. 实现 commands：
   - `create_profile`
   - `list_profiles`
   - `update_profile`
   - `apply_profile`
   - `delete_profile`

### 不做

- 不做游戏内配置热切换。
- 不编辑 Lua SavedVariables。
- 不做复杂冲突合并。

### 产出

- 用户可创建插件组合。
- 用户可一键应用 Profile。

### 验收标准

1. Profile 可持久化。
2. 应用 Profile 前可创建快照。
3. 应用后插件目录启停符合预期。
4. `.disabled` 状态能被 scanner 正确识别。
5. 应用失败有错误返回，不破坏已有目录。

### 推荐 Agent Prompt

```text
你负责实现 Profile 管理。Profile 包含一组插件 folder_name，可选绑定 config snapshot。请实现 ProfileService 和 create/list/update/apply/delete profile commands。应用 Profile 时，可选创建当前 WTF 快照，然后启用 Profile 内插件、禁用 Profile 外插件。插件禁用通过目录重命名为 .disabled 实现。请确保失败不会破坏插件目录，并添加集成测试。
```

---

## Agent A7：Provider 框架与 LocalZip/GitHub Provider

### 依赖

- A0 完成。
- A4 完成后可集成安装。

### 目标

实现 Provider 抽象，并先支持 `LocalZipProvider` 和 `GitHubReleaseProvider`。

### 工作范围

1. 实现 `AddonProvider` trait。
2. 实现 `ProviderService`。
3. 实现 `LocalZipProvider`。
4. 实现 `ManualUrlProvider`。
5. 实现 `GitHubReleaseProvider`。
6. 实现 commands：
   - `search_remote_addons`
   - `get_remote_addon_files`
   - `install_addon_from_provider`
   - `check_addon_updates`

### 不做

- 不实现 Wago。
- 不实现 CurseForge。
- 不做复杂搜索排名。
- 不做 API Key 管理。

### 产出

- Provider 框架可扩展。
- GitHub release 可作为插件来源。
- Installer 不依赖具体 Provider。

### 验收标准

1. Provider trait 可插拔。
2. LocalZipProvider 可返回本地文件。
3. ManualUrlProvider 可下载 zip。
4. GitHubReleaseProvider 能获取 release asset。
5. 下载后交给 Installer 执行安装。
6. Provider 错误统一转 `AppError`。

### 推荐 Agent Prompt

```text
你负责实现插件源 Provider 框架。请实现 AddonProvider trait、ProviderService、LocalZipProvider、ManualUrlProvider、GitHubReleaseProvider。Provider 只负责搜索、获取文件列表、下载文件，不负责安装。下载完成后交给现有 Installer。实现 search_remote_addons、get_remote_addon_files、install_addon_from_provider、check_addon_updates commands。暂不实现 Wago 和 CurseForge，但保留枚举和接口。
```

---

## Agent A8：前端 UI 与交互集成

### 依赖

- A0 完成。
- 可与 A1-A7 并行，用 mock API 先开发。

### 目标

实现桌面端 UI，接入 Tauri commands。

### 工作范围

1. 实现应用布局。
2. 实现 Dashboard。
3. 实现客户端目录管理。
4. 实现插件列表。
5. 实现 zip 安装弹窗。
6. 实现配置快照页面。
7. 实现 Profile 页面。
8. 实现设置页。
9. 实现统一错误提示。
10. 实现操作日志展示。

### 不做

- 不直接操作文件。
- 不在前端拼路径。
- 不在前端解析 `.toc`。
- 不把业务规则写进 UI。

### 产出

- 可用桌面端 UI。
- 通过 services 调用 Tauri commands。
- mock 和真实 command 均可切换。

### 验收标准

1. 首屏能展示 installation 状态。
2. 可手动添加 WoW 目录。
3. 可扫描并展示插件。
4. 可选择 zip 并安装。
5. 可创建和恢复快照。
6. 可创建和应用 Profile。
7. 错误展示友好，包含建议操作。

### 推荐 Agent Prompt

```text
你负责实现前端 UI。请基于 React + TypeScript 实现 Dashboard、AddonList、AddonMarket、ConfigSnapshots、Profiles、Settings 页面。前端只能通过 services 调用 Tauri commands，不能直接拼本地路径或处理文件系统逻辑。请实现统一错误提示、加载态、空状态和操作日志。可以先用 mock API 开发，再接入真实 command。
```

---

## Agent A9：集成测试、端到端验收与打包

### 依赖

- A1-A8 完成。

### 目标

完成跨模块集成、端到端链路验证和桌面端打包。

### 工作范围

1. 整合所有 commands。
2. 补充端到端测试。
3. 验证 mock WoW 目录完整链路。
4. 验证 zip 安装完整链路。
5. 验证 `WTF` 备份恢复完整链路。
6. 验证 Profile 应用完整链路。
7. 验证 Windows 11 打包。
8. 验证 macOS 打包。
9. 整理 release checklist。

### 产出

- 可打包应用。
- 基础 E2E 测试。
- Release checklist。

### 验收标准

完整链路必须通过：

```text
添加 WoW 目录
  ↓
扫描插件
  ↓
安装 zip 插件
  ↓
创建 WTF 快照
  ↓
创建 Profile
  ↓
应用 Profile
  ↓
恢复快照
```

### 推荐 Agent Prompt

```text
你负责项目集成测试和打包验收。请整合已有模块，补充端到端测试，验证添加 WoW 目录、扫描插件、安装 zip、创建 WTF 快照、创建 Profile、应用 Profile、恢复快照的完整链路。请修复集成问题，并提供 Windows 11 和 macOS 打包 checklist。
```

---

# 18. 推荐执行顺序

## 18.1 第一批

```text
A0 项目骨架
```

A0 必须先完成。

## 18.2 第二批，可并行

```text
A1 Platform Adapter
A2 插件扫描
A3 SQLite Repository
A8 前端 UI mock
```

这些模块边界清楚，可以并行。

## 18.3 第三批，可并行

```text
A4 安装器
A5 配置快照
A6 Profile
A7 Provider 框架
```

其中：

- A4 依赖 A2 的 `.toc` 解析能力。
- A5 依赖 A1 的路径识别。
- A6 依赖 A2/A3。
- A7 可先独立实现 trait 和 mock provider。

## 18.4 第四批

```text
A9 集成测试与打包
```

---

# 19. 任务依赖图

```text
A0
├── A1 Platform Adapter
├── A2 Scanner / Toc Parser
├── A3 SQLite / Repository
└── A8 Frontend Mock

A1 + A3 ──> A5 Config Snapshot

A2 + A3 ──> A6 Profile

A2 + A3 ──> A4 Installer

A4 ───────> A7 Provider Install Integration

A1 + A2 + A3 + A4 + A5 + A6 + A7 + A8 ──> A9 Integration
```

---

# 20. 跨 Agent 协作约束

所有 agent 必须遵守以下约束：

1. **不得修改公共接口而不更新类型定义**
   - Rust domain model 和 TypeScript type 必须同步。

2. **不得绕过 AppError**
   - 所有错误统一映射为 `AppError`。

3. **不得在前端做路径拼接**
   - 路径由后端返回。

4. **不得直接覆盖用户目录**
   - 所有安装、恢复必须支持备份和回滚。

5. **不得把 Provider 逻辑写进 Installer**
   - Provider 下载，Installer 安装。

6. **不得把平台判断散落在业务层**
   - 必须走 Platform Adapter。

7. **必须添加测试 fixture**
   - 所有文件系统相关模块都要有 mock 目录测试。

8. **破坏性操作必须记录 install_history 或 snapshot metadata**
   - 方便用户追踪和恢复。

---

# 21. 最小可验收产品链路

虽然架构按终态设计，但第一条必须打通的完整链路是：

```text
启动应用
  ↓
手动选择 WoW 目录
  ↓
后端校验目录
  ↓
扫描 AddOns
  ↓
展示插件列表
  ↓
选择本地 zip
  ↓
生成 InstallPlan
  ↓
执行安装
  ↓
安装前备份旧插件
  ↓
安装成功后刷新列表
  ↓
创建 WTF 快照
  ↓
创建 Profile
  ↓
应用 Profile
  ↓
恢复 WTF 快照
```

这条链路通过后，再扩展 Wago、CurseForge、云同步、复杂配置 diff。

---

# 22. 暂不实现但预留接口的能力

以下能力先预留模型和接口，不要求第一轮 agent 实现完整逻辑：

1. CurseForge Provider。
2. Wago Provider。
3. 云同步。
4. 账号体系。
5. 多设备配置同步。
6. 插件评分、评论、截图。
7. SavedVariables Lua 结构化 diff。
8. 插件依赖自动补全。
9. 应用自动更新。
10. 插件配置冲突合并。

---

# 23. 最终交付物清单

完成以上任务后，项目应具备：

1. 可运行 Tauri 桌面端应用。
2. 可识别 macOS / Windows 11 WoW 目录。
3. 可扫描本地 AddOns。
4. 可解析 `.toc`。
5. 可从 zip 安装插件。
6. 安装失败可回滚。
7. 可创建和恢复 WTF 快照。
8. 可创建和应用 Profile。
9. 有 SQLite 本地数据库。
10. 有结构化错误模型。
11. 有基础前端 UI。
12. 有单元测试和集成测试。
13. 有打包检查清单。

---

# 24. 给主控 Agent 的总控 Prompt

```text
你是这个项目的主控工程 Agent。目标是基于本文档实现一个支持 macOS 和 Windows 11 的魔兽世界插件管理系统。请严格遵守本文档中的架构分层、模块边界、错误模型和安全约束。

开发策略：
1. 先完成 A0 项目骨架。
2. 再并行推进 A1、A2、A3、A8。
3. 然后并行推进 A4、A5、A6、A7。
4. 最后由 A9 进行集成测试和打包验收。

重要约束：
- 前端不得拼接本地路径。
- 破坏性操作前必须备份。
- 安装插件不得直接覆盖 AddOns。
- Provider 只负责搜索、获取文件、下载，不负责安装。
- 平台差异必须封装在 Platform Adapter。
- 所有错误必须统一映射为 AppError。
- 每个模块必须提供测试或 fixture。

最终必须打通以下链路：
启动应用 -> 手动选择 WoW 目录 -> 扫描 AddOns -> 展示插件列表 -> 选择本地 zip -> 生成 InstallPlan -> 执行安装 -> 安装前备份旧插件 -> 安装成功后刷新列表 -> 创建 WTF 快照 -> 创建 Profile -> 应用 Profile -> 恢复 WTF 快照。
```
