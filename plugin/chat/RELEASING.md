# MyChat 发布流程（Releasing）

本文档说明如何把 `MyChat` 插件打包成可发布的 zip，以及发布到常见平台的步骤。
打包脚本：[package.sh](./package.sh)。

---

## 1. 版本号管理

版本号出现在两处，发布前**必须保持一致**（打包脚本会强制校验，不一致直接报错）：

| 位置 | 字段 |
|---|---|
| [MyChat/MyChat.toc](./MyChat/MyChat.toc) | `## Version:` |
| [MyChat/Constants.lua](./MyChat/Constants.lua) | `C.VERSION` |

发布新版本时，同时改这两处，遵循语义化版本 `主.次.修`（如 `0.1.0` → `0.2.0`）。

同时确认 `## Interface:` 与目标客户端匹配（当前 `120000` = 12.0.0）。若适配新小版本，一并更新。

---

## 2. 打包

在 `plugin/chat/` 目录下运行：

```bash
# 仅校验（不产出 zip）：检查版本一致性、.toc 引用文件是否齐全
./package.sh --check

# 正式打包 -> dist/MyChat-<version>.zip
./package.sh

# 指定输出目录
./package.sh --output /path/to/output
```

### 脚本做了什么

1. 读取 `.toc` 的 `Version` / `Interface`。
2. 校验 `Constants.lua` 的 `C.VERSION` 与 `.toc` 一致。
3. 校验 `.toc` 里引用的每个文件都真实存在。
4. 警告 `MyChat/` 下**未被 `.toc` 引用**的 `.lua`（这类文件不会被游戏加载）。
5. 打包为 `plugin/dist/MyChat-<version>.zip`（统一插件产出目录），**zip 顶层即 `MyChat/` 目录**，自动排除 `.DS_Store`、`__MACOSX`、`.git`、`*.swp`、`*.bak`、`.pkgmeta`。

### 产物结构（正确形态）

```text
MyChat-0.1.0.zip
└── MyChat/
    ├── MyChat.toc
    ├── *.lua
    ├── Data/Defaults.lua
    └── UI/*.lua
```

> 解压后直接把 `MyChat/` 放进 `Interface/AddOns/` 即可，无需多套一层目录。

---

## 3. 发布前检查清单

- [ ] 版本号已更新（`.toc` 与 `Constants.lua` 一致）。
- [ ] `## Interface:` 与目标客户端版本匹配。
- [ ] `./package.sh --check` 全部通过，无缺失文件、无未引用 lua 警告。
- [ ] 在游戏内 `/reload` 实测新版本无 Lua 报错（对照 dev_tasks 各任务测试用例）。
- [ ] 更新变更说明（见 §5 CHANGELOG）。
- [ ] `plugin/dist/` 里生成了 `MyChat-<version>.zip` 并已用 `unzip -l` 确认顶层是 `MyChat/`。

---

## 3.5 自动发布（GitHub Actions，推荐）

已配置工作流 `.github/workflows/mychat-release.yml`：**推带 `mychat-v` 前缀的 tag 即自动打包并发布 GitHub Release**，无需手动上传。

> 为什么不用 BigWigsMods/packager？它要求“仓库根即插件根”，不支持本仓库这种 monorepo
> 深层子目录（`plugin/chat/MyChat`）。因此改用本仓库自带的 `package.sh`（专为该子目录设计、
> 已验证）打包，再用成熟的 `softprops/action-gh-release` 上传，与 manager 的 `release.yml` 同一模式。

### 一次性准备
1. **仓库权限**：Settings → Actions → General → Workflow permissions 选 **Read and write**（否则无法创建 Release）。
2. GitHub Release 用自带的 `GITHUB_TOKEN`，**无需额外配置任何 secret**。

### 发布动作
```bash
# 前缀 tag，避免与 manager 的 v* tag 冲突
git tag -a mychat-v0.1.0 -m "MyChat 0.1.0"
git push origin mychat-v0.1.0
```
推送后到 GitHub **Actions** 标签页查看 `Release MyChat` 运行结果，完成后在 **Releases** 页可见附带的 `MyChat-0.1.0.zip`。

### 工作流做了什么
1. `checkout` 仓库。
2. 跑 `plugin/chat/package.sh --output plugin/dist`：内含发布前校验（版本一致、`.toc` 引用齐全），产出 `MyChat-<version>.zip` 到统一目录 `plugin/dist/`。
3. 上传 zip 为 artifact。
4. 用 `softprops/action-gh-release` 创建 GitHub Release 并附上 zip（自动生成 release notes）。

### 第三方平台（CurseForge / WoWInterface / Wago）
本工作流只发 GitHub Release。若要自动上传到第三方平台，可在工作流末尾**追加各平台的官方 upload action**（各自需要在 Settings → Secrets 配 API token，并在平台建项目拿 ID）。它们接收 `plugin/dist/*.zip` 即可。手动上传步骤见下方 §4。

---

## 4. 手动发布到各平台（备用）

无 CI 或临时补发时，用本地 `plugin/dist/` 的 zip 手动上传。

### 4.1 CurseForge
1. 登录 CurseForge，进入项目 → **Files → Upload File**。
2. 上传 `MyChat-<version>.zip`。
3. 填写版本号、发布类型（Release/Beta/Alpha）、支持的游戏版本（对应 `## Interface:`）。
4. 粘贴 CHANGELOG，发布。

### 4.2 WoWInterface
1. 项目页 → **Update AddOn** → 上传 zip。
2. 填写兼容版本与更新说明。

### 4.3 Wago Addons
1. 项目 → **Upload** → 选择 zip。
2. 选择 game flavor（Retail），填版本与说明。

### 4.4 GitHub Release（手动分发）
```bash
# 需已安装并登录 gh；tag 用前缀以匹配 CI 约定
gh release create mychat-v0.1.0 plugin/dist/MyChat-0.1.0.zip \
  --title "MyChat 0.1.0" \
  --notes "见 CHANGELOG"
```

> 各平台的 `## Interface:` 版本对应关系以平台上架时的选择为准；平台会依据它判断"是否过期"。

---

## 5. 变更说明（CHANGELOG）

建议每次发布在此追加一段（或单独维护 CHANGELOG.md）：

### 0.1.0
- 首个 MVP 版本。
- 原生聊天增强：时间戳、频道缩写、玩家名职业色。
- 关键词 / 自己名字高亮；重复消息折叠。
- 最近密语记录与 `/mychat reply` 快捷回复。
- 自动加入 / 恢复频道；CombatGuard 战斗安全延迟。
- 频道快速切换条（默认关闭）；可选镜像面板（默认关闭）。
- 设置面板与 `/mychat` 命令（debug / reset / safe / reply）。

---

## 6. 常见问题

**打包脚本报"版本不一致"？**
同步修改 `.toc` 的 `## Version:` 和 `Constants.lua` 的 `C.VERSION`。

**报"X 个 .toc 引用的文件不存在"？**
`.toc` 里列了某个 lua 但文件缺失/改名。核对 `.toc` 引用与实际文件名（注意大小写；`.toc` 用反斜杠 `\`，脚本会自动转换）。

**出现"未被 .toc 引用"警告？**
你新增了 lua 但忘了加进 `.toc` 的加载列表；游戏不会加载它。把文件名补进 `.toc` 相应位置（注意加载顺序）。

**Windows 上如何运行脚本？**
用 Git Bash / WSL 执行 `./package.sh`；或手动把 `MyChat/` 目录压成 zip（确保顶层是 `MyChat/` 且排除 `.DS_Store`）。
