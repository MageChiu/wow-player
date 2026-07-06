# CombatCoach 安装与使用手册

> 本插件用于 WoW 12.0.x 的**战斗复盘**：一场战斗结束后，自动给出你在这场里的核心数据（输出/治疗/减伤）以及**少而准的可执行改进点**。
> 它遵循"专一"原则——只做"战斗后复盘 + 建议"这一件事，**不做**实时伤害表、威胁值监控、团队排名（那些交给 Details!/Skada）。
> 支持坦克（T）/输出（DPS）/治疗三种角色，通过可扩展的专精数据表适配不同职业。

---

## 1. 它能做什么 / 不能做什么

先把边界说清楚，避免误解。数据全部来自游戏的**战斗日志**（Combat Log），这决定了几条硬限制：

**能做**
- 统计**你自己**（含宠物）在一场战斗里的伤害、治疗、承受伤害、施法、Buff/Debuff 覆盖、死亡。
- 战斗结束后算出 DPS / HPS / DTPS、活跃时间、过量治疗%、维持类覆盖率、主要 CD 使用次数。
- 按你的角色（T/DPS/治疗）给出高置信度的改进点，并按严重度红/黄/灰排序。

**不能做**（这是 WoW 插件的硬限制，非缺陷）
- 拿不到别人精确的能量/怒气/法力和技能冷却剩余。
- 只对"日志范围内"的单位负责——出视野/切目标丢失的数据无法统计。
- 不是团队 DPS 排名工具，也不替代专业的 Details! / WarcraftLogs。

---

## 2. 安装

插件本体位于本目录的 `CombatCoach/` 文件夹（与 `CombatCoach.toc` 同级）。

### 2.1 找到魔兽的插件目录

把 `CombatCoach` 整个文件夹复制到对应版本的 `Interface\AddOns\` 下：

| 版本 | 目标路径 |
|---|---|
| 正式服（Retail） | `World of Warcraft\_retail_\Interface\AddOns\` |
| 测试服（PTR） | `World of Warcraft\_ptr_\Interface\AddOns\` |

- **Windows** 示例：`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CombatCoach\`
- **macOS** 示例：`/Applications/World of Warcraft/_retail_/Interface/AddOns/CombatCoach/`

### 2.2 目录结构应如下

```text
Interface/AddOns/CombatCoach/
  CombatCoach.toc     <- 插件清单
  Init.lua
  Core.lua
  Constants.lua
  Utils.lua
  Config.lua
  Segment.lua
  CombatLog.lua
  Metrics.lua
  Analyzer.lua
  Store.lua
  Commands.lua
  Data/Defaults.lua
  Data/SpecProfiles.lua
  UI/ReportFrame.lua
```

> 关键：`CombatCoach.toc` 必须直接位于 `AddOns\CombatCoach\` 下，不要多套一层文件夹（不要出现 `AddOns\CombatCoach\CombatCoach\CombatCoach.toc`）。

### 2.3 在游戏中启用

1. 启动游戏，进入**角色选择界面**。
2. 左下角点击 **「插件」（AddOns）** 按钮。
3. 勾选 **CombatCoach**。
4. 若提示版本不符，勾选左下角 **「加载过期插件」**。
5. 进入游戏。加载成功后聊天框会打印：
   `CombatCoach: v0.1.0 已加载，输入 /cc 查看战斗复盘。`

### 2.4 版本说明

- 插件 `## Interface:` 标记为 `120007, 120005, 120000`（覆盖 12.0.7 / 12.0.5 / 12.0.0）。若为 12.0.x 其他小版本提示"过期"，勾选「加载过期插件」即可；确认可用后可自行把 `.toc` 首行改成你客户端的实际 Interface 号（游戏内 `/dump (select(4, GetBuildInfo()))` 可查）。

---

## 3. 快速上手（30 秒）

1. 进游戏后打一场架（打怪或首领战均可）。
2. **战斗结束会自动弹出复盘窗口**：顶部是核心指标大字，下面是本场的改进点（红=明显问题，黄=建议，灰=提示）。
3. 想再看最近一场：输入 `/cc`。
4. 想看历史：`/cc history` 列出最近的战斗，再 `/cc show <编号>` 看某一场。
5. 不喜欢自动弹窗：`/cc auto` 关掉，之后只用 `/cc` 手动看。

> 太短的战斗（默认 <5 秒）不会生成报告，避免路上蹭怪刷屏。

---

## 4. 命令一览（`/cc`）

| 命令 | 作用 |
|---|---|
| `/cc` | 打开/关闭最近一场战斗复盘窗口 |
| `/cc last` | 在聊天框打印最近一场的摘要 + 改进点 |
| `/cc history` | 列出最近的战斗记录（新→旧，带编号） |
| `/cc show <N>` | 打开列表中第 N 场的复盘窗口 |
| `/cc auto` | 切换"战斗结束自动弹窗"（开/关） |
| `/cc boss` | 切换"仅首领战分析"（开则忽略普通打怪） |
| `/cc wipe` | 清空所有历史记录 |
| `/cc reset` | 还原设置（保留历史），随后 `/reload` 生效 |

> `/combatcoach` 是 `/cc` 的完整别名，两者等价。

---

## 5. 报告怎么看

一份报告分三块：

### 5.1 顶部主指标（按角色显示最相关的）
| 角色 | 主指标 | 含义 |
|---|---|---|
| 输出 DPS | `DPS xxx  活跃 xx%` | 每秒伤害 + 活跃时间占比 |
| 治疗 | `HPS xxx  过量 xx%` | 每秒有效治疗 + 过量治疗占比 |
| 坦克 T | `DTPS xxx  减伤 xx%` | 每秒承受伤害 + 主动减伤覆盖率 |

### 5.2 副信息
对象（首领名/普通战斗）、时长、职业、结果（击杀/团灭）。

### 5.3 改进点列表（核心价值）
每条一行，按严重度排序和着色：

- 🔴 **红（明显问题）**：如本场阵亡。
- 🟡 **黄（建议改进）**：如活跃时间偏低、主 CD 整场没用、维持 DoT 覆盖率不足、过量治疗过高、坦克减伤没铺满。
- ⚪ **灰（提示）**：如"当前专精暂无细化模型，只做了通用分析"。

没有明显问题时会显示"这一场没有发现明显问题，保持！"。

---

## 6. 各角色的分析指标

初版只做**高置信度、跨专精都成立、不易误判**的少数指标，宁缺毋滥。

### 输出（DPS）
- **活跃时间%**：低于阈值（默认 95%）说明有施法空档（站桩/走位空转）。
- **主要 CD 使用次数**：整场一次没用会提示。
- **维持类 DoT/Debuff 覆盖率**：低于阈值（默认 90%）说明掉了没续。

### 治疗
- **过量治疗%**：高于阈值（默认 40%）说明存在过量施放，是治疗最可执行的信号。
- **主要团队 CD 使用**：整场没放会提示。
- **活跃时间%**：读条治疗的空档。

### 坦克（T）
- **主动减伤覆盖率**：坦克的核心 KPI，低于阈值（默认 55%）提示减伤没铺满。
- **承受伤害 DTPS**：展示用。
- **死亡**：任何角色阵亡都会红色提示。

> 阈值集中在 `Data/Defaults.lua` 的 `profile.thresholds`，可按体验微调。

---

## 7. 职业/专精适配（进阶）

职业差异不写死在逻辑里，而是集中在一张数据表 [Data/SpecProfiles.lua](./CombatCoach/Data/SpecProfiles.lua)。分析逻辑是通用的，只是"喂"进不同专精的关注点。

- **已内置样例专精**：鲜血DK、守护德、兽王猎、元素萨、毁灭术、恢复德、织雾武僧。
- **未收录的专精不会报错**：自动退化为通用分析（DPS/HPS/活跃时间/死亡），并给一条灰色提示。
- **想让自己的专精更准**：在该表里加一行即可，无需改任何逻辑代码：

```lua
-- specID 用游戏内 /dump GetSpecializationInfo(GetSpecialization()) 查
[断兽守护专精ID] = {
  role = ROLE.TANK,          -- TANK / DAMAGER / HEALER
  resource = "怒气",          -- 仅用于文案
  mitigation = { [减伤BuffID] = "减伤名" },  -- 坦克主动减伤，算覆盖率
  majorCDs   = { [技能ID] = "爆发/防御CD名" },-- 统计使用次数
  maintain   = { [DoTID]  = "维持技能名" },   -- 需高覆盖率的 DoT/Buff
}
```

---

## 8. 常见问题（FAQ）

**Q：战斗结束没有弹窗？**
- 战斗时长可能低于最短阈值（默认 5 秒），或你开了 `/cc boss` 只看首领战。
- 检查是否用 `/cc auto` 关过自动弹窗；随时可 `/cc` 手动打开最近一场。

**Q：改进点很少，只有一条灰色提示？**
- 说明你当前专精还没收录到 `SpecProfiles`，只跑了通用分析。按第 7 节补一行即可获得针对性建议。

**Q：数字和 Details! 对不上？**
- 本插件只统计"日志范围内的你自己"，且吸收/多段伤害用了近似算法，定位是**趋势与手法复盘**，不是精确到个位的伤害表。要精确数字请用 Details!。

**Q：插件显示"已过期"无法加载？**
- 插件列表勾选「加载过期插件」，或把 `.toc` 首行 `## Interface:` 改为你客户端的实际版本号。

**Q：设置会保存吗？**
- 会，存于 `SavedVariables\CombatCoachDB`。`/cc reset` 只还原设置、保留历史；`/cc wipe` 只清历史、保留设置。

**Q：会影响游戏性能吗？**
- 战斗日志高频事件里只做数值累加，聚合与分析延到战斗结束后一次性完成，正常使用无明显开销。

---

## 9. 卸载

- 临时停用：角色选择界面的插件列表取消勾选 CombatCoach。
- 彻底删除：删除 `Interface\AddOns\CombatCoach\` 文件夹。存档 `WTF\...\SavedVariables\CombatCoachDB.lua` 可一并删除以清除历史与配置。

---

## 10. 打包与发布（开发者）

本目录提供 `package.sh`：

```bash
./package.sh --check    # 只校验（.toc 引用完整性、版本一致）
./package.sh            # 打包到 plugin/dist/CombatCoach-<版本>.zip
```

产出的 zip 解压后顶层即为 `CombatCoach/`，可直接放进 `Interface/AddOns/`。
