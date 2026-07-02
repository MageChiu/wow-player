# wow-addon-manager

魔兽世界插件管理器（Tauri + React + TypeScript + Rust + SQLite）。

> 架构与任务见 [`../docs`](../docs/README.md)。本 README 只讲如何运行当前工程。
> 当前进度：**A0–A9 全部完成**（骨架 / 平台适配 / 插件扫描 / SQLite / zip 安装器 / 配置快照 / Profile / Provider / 前端 UI / 集成测试与打包）。

## 环境要求

- Node.js ≥ 18（本机验证 v22）
- pnpm ≥ 10（`corepack` 启用即可）
- Rust ≥ 1.77（本机验证 1.89）
- Tauri CLI 2.x（`cargo tauri`）

## 常用命令

推荐用 `Makefile` 作为统一入口（本目录下执行 `make help` 查看全部目标）：

```bash
make install     # 安装前端依赖
make dev         # 完整桌面应用（Tauri 窗口 + 真实后端）
make fe          # 前端校验：typecheck + build
make be          # 后端校验：clippy(-D warnings) + test
make ci          # CI 门槛聚合：依赖 + 前端 + 后端（本地复现 CI）
make icon        # 从 src-tauri/icons/app-icon.svg 重新生成图标集
make bundle      # 打包当前平台桌面产物
make bundle-mac  # 打包 macOS 通用包（Intel + Apple Silicon）
make bundle-win  # 打包 Windows 安装包（在 Windows 上执行）
```

> GitHub Actions（[`.github/workflows`](../../.github/workflows)）复用同一批 `make` 目标：
> `ci.yml` 在 push/PR 时跑 `make ci`；`release.yml` 在打 `v*` tag 时于 macOS 与 Windows 上跑 `make bundle` 并上传产物到 Release。

底层原始命令（等价参考）：

```bash
# 安装前端依赖
pnpm install

# 仅前端开发（浏览器，mock 后端）
VITE_USE_MOCK=1 pnpm dev        # http://localhost:1420

# 完整桌面应用（Tauri 窗口 + 真实 Rust 后端）
pnpm tauri dev

# 前端类型检查 / 构建
pnpm typecheck
pnpm build

# 后端构建 / 测试 / lint
cd src-tauri
cargo build
cargo test
cargo clippy --all-targets -- -D warnings
```

## 目录结构

```text
wow-addon-manager/
  src/                     # 前端
    app/                   # App/router/providers
    pages/                 # 页面（A8）
    components/            # 组件（A8）
    services/              # Tauri command 封装（唯一后端入口）
    stores/                # 状态（A8）
    types/                 # domain/command/errors，与 Rust 一一对应
  src-tauri/
    src/
      commands/            # Tauri command（DTO 边界）
      app/                 # 全局状态与 bootstrap
      domain/              # 领域模型 + AppError
      services/            # 业务服务（A4-A7）
      platform/            # 平台适配（A1）
      infra/               # DB / 日志 等基础设施
      scanner/             # .toc 解析与扫描（A2）
      installer/           # 安装流水线（A4）
      providers/           # 插件源（A7）
      tests/fixtures/      # 测试夹具
```

## A0 已交付

- 可编译可启动的 Tauri 应用骨架。
- 前端 `health_check()` 调用后端并展示状态。
- 完整 domain 模型与 `AppError`（Rust）↔ `types/`（TS）双向对齐。
- SQLite 连接入口 + 基础日志 + 全局 AppState。
- 错误码→用户提示映射、mock/真实 command 切换开关。

## A1 已交付

- `PlatformAdapter` trait + Windows/macOS 适配器 + `current_adapter()` 工厂（唯一平台分支处）。
- WoW 目录识别：默认路径扫描、手动路径校验、flavor（`_retail_/_classic_/_classic_era_/_ptr_`）识别、`Interface/AddOns` 与 `WTF` 定位。
- 权限检测（可读/可写/原因），无效目录返回 `InvalidInstallationPath`。
- commands：`detect_installations` / `validate_installation_path` / `add_installation` / `list_installations` / `remove_installation`（安装暂存内存，A3 后转 DB）。
- 前端 `installationApi.ts`（mock + 真实）。
- 测试：7 单元测试 + 1 fixture 集成测试（`src/tests/fixtures/wow_retail_mock/`）。

## A2 已交付

- `TocParser`：解析 `##` 元数据行（key 忽略大小写、去空格、逗号拆数组、BOM/中文），多 `.toc` 同名优先 + flavor 后缀匹配。
- `AddonScanner`：遍历 `Interface/AddOns`，`.disabled` → `Disabled`，无 `.toc`/解析失败 → `Broken`（不中断扫描），跳过文件与隐藏目录，输出 `LocalAddon`。
- commands：`scan_addons`（扫描并持久化）/ `list_addons`（读 DB）。
- 前端 `addonApi.ts`（mock + 真实）。
- 测试：17 单元测试 + 1 fixture 集成测试（`src/tests/fixtures/toc_samples/`）。

## A3 已交付

- `migrations.rs`：基于 `PRAGMA user_version` 的幂等版本化迁移，建 8 张终态表 + 索引，启用外键。
- `Database`：`open` / `open_in_memory` 打开时自动迁移，新增 `with_transaction`；`codec.rs` 提供 enum / JSON 编解码。
- repositories：`Installation` / `Addon` / `Snapshot` / `Profile` / `Settings` / `InstallHistory` 的 CRUD，`installation` 读回时重算权限，`profile` 关联 `profile_addons`。
- AppState 的 installations / addons 由内存缓存改为 SQLite 持久化（删除、替换走事务）。
- 数据库路径来自 `PlatformAdapter.app_data_dir()`（不硬编码）。
- 测试：repository + 迁移单测 + 文件库持久化/幂等集成测试。

## A4 已交付

- `ZipService`：zip 校验与解压，含 zip-slip（路径逃逸）防护。
- `AddonFolderDetector`：识别三种压缩包结构（平铺多目录 / 版本前缀 / `Interface/AddOns` 嵌套），无 `.toc` 返回 `NoAddonFolderDetected`。
- `InstallPlanner` / `InstallExecutor` / `fs_ops`：生成 `InstallPlan`（actions / backup_path / warnings），执行时先备份旧目录再复制新目录，任一步失败自动回滚（恢复备份、清理半成品）。
- commands：`create_install_plan_from_zip` / `execute_install_plan` / `install_addon_from_zip` / `rollback_install`；成功后重扫写库并记 `install_history`，失败记 `failed`。
- 前端 `installerApi.ts`（mock + 真实）。
- 测试：13 installer 单测 + 6 端到端管线集成测试（标准 / 嵌套 / 多插件 / 无效 zip / 无 toc / 更新备份）。

## A5 已交付

- `ZipService::compress_dir`：目录压缩为 zip。
- `ConfigService`：`FullWtf` 快照创建（压缩 WTF → `snapshots/<inst>/<snap>/wtf.zip` + `metadata.json`，含 `addon_versions`）、恢复（校验 → 移动备份当前 WTF → 解压恢复 → 失败自动回滚）、删除（删目录）。
- commands：`create_config_snapshot` / `list_config_snapshots` / `restore_config_snapshot` / `delete_config_snapshot`；创建时落 `SnapshotRepository`，删除时同删文件与 DB 记录。
- 快照存储根来自 `PlatformAdapter.app_data_dir()/snapshots`，恢复备份放 `temp_dir()/wtf_backups`。
- 前端 `configApi.ts`（mock + 真实）。
- 测试：5 ConfigService 单测（含恢复回滚）+ 1 端到端集成测试（创建→落库→恢复→删除）。

## A6 已交付

- `ProfileService::apply_to_addons`：按目标插件集合启停 `AddOns` 目录（启用去 `.disabled`、禁用加 `.disabled`），只重命名不删除，目标已存在则告警跳过，返回 `ToggleOutcome{enabled,disabled}`。
- commands：`create_profile` / `list_profiles` / `update_profile` / `apply_profile` / `delete_profile`；应用 Profile 时可选先建当前 WTF 快照（回退用）→ 启用 Profile 内插件、禁用 Profile 外插件 → 重扫写库保持 DB 与磁盘一致。
- Profile 及其关联插件集合经 `ProfileRepository`（含 `profile_addons`）在事务中持久化。
- 前端 `profileApi.ts`（mock + 真实）。
- 测试：5 ProfileService 单测 + 2 端到端集成测试（启停目录并同步 DB / 空 Profile 禁用全部）。

## A8 已交付

- 应用外壳：`AppLayout`（侧边栏导航 + 客户端选择器）+ `HashRouter` 六路由；`main.tsx` 挂载 `RouterProvider`；全新 `styles.css` 布局体系（卡片/表格/徽标/弹窗/toast）。
- 全局状态：`stores/installationStore`（zustand，加载/检测/增删/选择客户端，供各页共享上下文）、`stores/toastStore`（操作日志/toast）。
- 页面：`DashboardPage`（客户端信息、插件数/可更新/异常统计、最近快照、扫描/检查更新/安装快捷入口）、`AddonListPage`（列表/搜索/状态过滤/详情弹窗/zip 安装计划预览→执行）、`AddonMarketPage`（Provider 选择、GitHub 搜索→版本列表→安装、手动 URL 下载安装）、`ConfigSnapshotsPage`（创建/恢复/删除/查看关联版本）、`ProfilesPage`（创建含插件多选/绑定快照/应用/删除）、`SettingsPage`（自动检测/添加/移除客户端目录）。
- 共享组件：`ErrorBanner`（按 `AppErrorCode` 映射提示与建议操作）、`Loading`、`EmptyState`、`Modal`、`ToastStack`、`PageHeader`；`dialogApi` 目录/zip 选择（mock 模式回退输入）。
- 前端仅经 `services/*Api.ts` 调用后端，不拼路径、不解析 `.toc`；`VITE_USE_MOCK=1` 切换 mock。
- 验证：`tsc --noEmit` + `pnpm build` 通过；浏览器 mock 模式逐页走查（检测客户端→扫描插件→创建并应用 Profile→市场搜索），交互与空/错/载状态均正常。

## A9 已交付

- 端到端黄金链路自动化测试 `tests/e2e_golden_path.rs`：真实模块走完「添加目录→扫描→安装中文名插件 zip→更新触发备份→建 WTF 快照→建 Profile→应用启停→恢复快照」，逐步断言 DB 与磁盘一致。
- 全量质量门槛全绿：`cargo clippy -D warnings`、`cargo test`（78 单元 + 16 集成）、`tsc --noEmit`、`pnpm build`。
- macOS 桌面打包成功：`wow-addon-manager.app` + `wow-addon-manager_0.1.0_aarch64.dmg`（约 5.8 MB），产物在 `src-tauri/target/release/bundle/`。
- 发布清单与跨平台测试矩阵见 [`../docs/发布清单.md`](../docs/发布清单.md)。

### 打包

```bash
pnpm tauri build      # 产物在 src-tauri/target/release/bundle/
```


## mock 开关

前端通过环境变量 `VITE_USE_MOCK=1` 切换到 mock service（无需后端），用于 A8 与后端并行开发。
