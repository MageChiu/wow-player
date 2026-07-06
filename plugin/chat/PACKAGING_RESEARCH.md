# 插件自动打包发布调研（GitHub Actions + 多平台分发）

> 目标：让 `MyChat` 能在 GitHub 上自动打包发布，并同步分发到 CurseForge / WoWInterface / Wago。
> 本文是**调研 + 落地方案**，不改动插件代码。现有的本地脚本见 [package.sh](./package.sh) 与 [RELEASING.md](./RELEASING.md)。

---

## 0. 最终决策（实测后更新）

> **实测结论**：BigWigsMods/packager **不支持 monorepo 深层子目录**。它在“仓库根”查找 `.toc`
> （`release.sh` 用 `find *.toc -maxdepth 0`），且 `move-folders` 的源路径不能含 `/`（只能移动
> 仓库根下一级目录），因此无法直接打包 `plugin/chat/MyChat`。用 `-t plugin/chat/MyChat` 会报
> `No Git checkout found`，因为 `-t` 指的是**含 `.git` 的仓库根**，不是插件目录。
>
> **采用方案**：放弃 packager 作为 GitHub Actions 打包器，改用本仓库自带的 [package.sh](./package.sh)
> （专为该子目录设计、已验证）打包，再用 `softprops/action-gh-release` 上传 GitHub Release
> （与 manager 的 `release.yml` 同一成熟模式）。工作流见 `.github/workflows/mychat-release.yml`。
> 第三方平台（CurseForge/WoWInterface/Wago）后续如需自动上传，各自追加官方 upload action，
> 消费 `plugin/dist/*.zip` 即可。下文 §1–§8 为原始调研记录，保留备查。

---

## 1. 结论速览（原始调研，见 §0 最终决策）

WoW 插件社区的**事实标准**是 [BigWigsMods/packager](https://github.com/BigWigsMods/packager)：一个开源打包器，配合 GitHub Actions，在**打 git tag 时自动**完成打包并上传到四个目标：

- **GitHub Release**（附 zip）
- **CurseForge**
- **WoWInterface**
- **Wago Addons**

它解决了我们手写 `package.sh` 覆盖不到的几件事：从 git tag 推导版本、`@project-version@` 关键字替换、自动生成 changelog、多游戏版本（Retail/Classic）打包、按 alpha/beta/release 分渠道、一次上传多平台。

**关键适配点（本仓库特有）**：我们是 monorepo，插件在 `plugin/chat/MyChat` 子目录，而 packager 默认假设仓库根即插件目录。需要用下面 §5 的方案之一处理。

---

## 2. 两条路线对比

| 维度 | A. 保留自研 `package.sh` + GitHub Release | B. 采用 BigWigsMods/packager |
|---|---|---|
| GitHub 自动发布 | 需自己写 workflow 调脚本 + `gh release` | 官方 action 内置 |
| CurseForge/WoWI/Wago 上传 | ❌ 需自己实现各平台 API 调用 | ✅ 内置，配 token 即可 |
| 版本关键字替换 `@project-version@` | ❌ 无 | ✅ 有 |
| 自动 changelog（按 tag 间 commit） | ❌ 无 | ✅ 有 |
| 多游戏版本/多 flavor | ❌ 手工 | ✅ 支持 |
| 库依赖 embed（.pkgmeta externals） | ❌ 无 | ✅ 支持（我们暂无外部库，可不用） |
| monorepo 子目录 | 原生支持（脚本已按子目录写） | 需适配（§5） |
| 维护成本 | 平台 API 变了要自己跟 | 社区维护 |

**建议**：**采用 B（BigWigsMods/packager）作为对外发布主通道**，把自研 `package.sh` 降级为"本地快速打包/自测"工具（无需 token、离线可用）。两者不冲突，各司其职。

---

## 3. 需要在各平台准备什么

发布到某平台前，要先在该平台建项目拿到 ID，并在 GitHub 仓库配置对应 token（Secrets）。**GitHub Release 不需要任何额外 token**（用自带的 `GITHUB_TOKEN`）。

| 平台 | 需要的标识（写进 .toc） | 需要的 Secret | 从哪拿 |
|---|---|---|---|
| GitHub Release | 无 | 无（自带 `GITHUB_TOKEN`） | — |
| CurseForge | `## X-Curse-Project-ID:` | `CF_API_KEY` | CurseForge 项目页 About 框；token 在 legacy.curseforge.com/account/api-tokens |
| WoWInterface | `## X-WoWI-ID:` | `WOWI_API_TOKEN` | WoWInterface 项目页；token 在账户设置 |
| Wago Addons | `## X-Wago-ID:` | `WAGO_API_TOKEN` | Wago 项目页 Project ID；token 在 addons.wago.io/account/apikey |

> 只想先发 GitHub、暂不上第三方平台，也完全可行——不配那几个 Secret，packager 会自动跳过对应平台。

---

## 4. 版本号策略（重要变化）

packager 推荐 `.toc` 用**关键字**而非硬编码：

```
## Version: @project-version@
```

打 tag 构建时它会被替换成 tag 名（如 `v0.1.0`）；非 tag 构建替换成 commit 短哈希，便于区分开发版。

**对我们的影响**：当前 `.toc` 与 `Constants.lua` 都是硬编码 `0.1.0`。若改用关键字：
- `.toc` 的版本由 git tag 驱动，发布时不用手改。
- 但 `Constants.lua` 里的 `C.VERSION`（游戏内 `/mychat` 显示、诊断用）packager **默认不会替换**其中的关键字，除非把该文件也纳入替换（packager 默认对所有文本文件做替换，实际会替换 `.lua` 里的 `@project-version@`）。

**权衡**：保持硬编码更简单直观，代价是发布时要手动同步两处（我们的 `package.sh --check` 已能校验一致）。是否切换到 `@project-version@` 由你决定，见 §7 提问。

---

## 5. monorepo 子目录适配（本仓库关键问题）

packager 假设"仓库根 = 插件目录"。我们插件在 `plugin/chat/MyChat/`。三种解法：

- **方案 5-1（推荐·workflow 内指定目录）**：在 GitHub Actions 里用 `working-directory` 或 packager 的 `-t`（top dir）参数指向 `plugin/chat`，并让 `.pkgmeta` 的 `package-as: MyChat`、`move-folders` 把 `MyChat` 提到 zip 顶层。改动集中在 CI 配置，代码不动。
- **方案 5-2（独立发布仓库）**：把 `plugin/chat/MyChat` 通过 `git subtree` 推到一个专门的发布仓库（如 `MageChiu/MyChat`），在那个仓库跑标准 packager。最干净、最贴合社区习惯，但多维护一个仓库。
- **方案 5-3（tag 前缀 + 路径过滤）**：用带前缀的 tag（如 `mychat-v0.1.0`）触发，workflow 里 `cd plugin/chat`。适合一个 monorepo 发多个插件。

> 若未来 `plugin/` 下会有多个插件各自发布，**5-3** 最省心；若只发 MyChat 一个，**5-1** 最简单。

---

## 6. 推荐落地形态（方案 B + 5-1/5-3）

需要新增的文件（都在 `plugin/chat/` 内，不碰其它目录）：

1. **`.pkgmeta`**（打包元数据）
   ```yaml
   package-as: MyChat
   enable-toc-creation: no
   ignore:
     - README.md
     - RELEASING.md
     - PACKAGING_RESEARCH.md
     - wow_chat_plugin_dev_tasks.md
     - wow_chat_plugin_execution_plan.md
     - package.sh
     - dist
   ```
   > 说明：把仓库/目录里的文档、脚本排除，只让 `MyChat/` 进包。具体 `move-folders`/路径按最终选的子目录方案微调。

2. **`.toc` 增加平台 ID 头**（有账号后再填真实 ID）
   ```
   ## X-Curse-Project-ID: 0000
   ## X-WoWI-ID: 0000
   ## X-Wago-ID: 000000
   ```

3. **GitHub workflow**（仓库根 `.github/workflows/release.yml`，这是唯一需要放到 chat 目录外的文件，因为 Actions 只认仓库根的 `.github/`）：
   ```yaml
   name: Release MyChat
   on:
     push:
       tags:
         - 'mychat-v*'      # 用前缀 tag 只触发本插件（方案 5-3）
   jobs:
     release:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
           with:
             fetch-depth: 0   # packager 需要完整历史来生成 changelog
         - name: Package and release
           uses: BigWigsMods/packager@master
           with:
             args: -p ${{ '' }} # 见下
           env:
             CF_API_KEY: ${{ secrets.CF_API_KEY }}
             WOWI_API_TOKEN: ${{ secrets.WOWI_API_TOKEN }}
             WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
             GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
           # 用 -t 指向子目录，或先 cd plugin/chat
   ```
   > 注意：`.github/workflows/` 必须在**仓库根**，无法放进 `plugin/chat`。若你要求"只在 chat 目录内"，则这一步改为在 `RELEASING.md` 里写明"需在仓库根添加此 workflow"，由你决定何时加。

4. **发布动作**：
   ```bash
   git tag -a mychat-v0.1.0 -m "MyChat 0.1.0"
   git push origin mychat-v0.1.0
   ```
   推 tag 后 Actions 自动打包并发布到已配置的平台。

---

## 7. 与现有本地脚本的关系

- `package.sh` 保留：**本地自测/离线打包**，无需任何 token，`--check` 可做发布前校验。
- packager：**对外正式发布**，由 CI 在 tag 时执行、多平台分发。
- `RELEASING.md` 补充"自动发布"章节，说明 tag 触发流程与 Secrets 配置。

---

## 8. 待你决策的点

1. **是否引入 BigWigsMods/packager 自动发布**（推荐引入）。
2. **子目录方案**：5-1（workflow 指定目录，只发 MyChat）还是 5-3（前缀 tag，为将来多插件预留）。
3. **版本号**：保持硬编码（配合 `package.sh --check` 校验）还是改用 `@project-version@`（tag 驱动）。
4. **workflow 放置**：`.github/workflows/release.yml` 必须在仓库根——是否允许在 chat 目录外新增这一个文件？若不允许，则只在 `RELEASING.md` 写操作说明，由你手动添加。

---

## 参考来源
- BigWigsMods/packager（官方打包器 + action）
- Wowpedia：Using the BigWigs Packager with GitHub Actions
- CurseForge 支持文档：Preparing the PackageMeta File
- better-addons.com：Publishing & CI/CD（含 .pkgmeta、@project-version@、多平台配置详解）
