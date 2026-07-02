# manager 文档索引

魔兽世界插件管理器（`wow-addon-manager`）的设计、任务与规范文档。**所有 manager 相关的代码与文档都集中在 `manager/` 内部**，不外溢到仓库根或其它子项目。

## 文档清单

| 文档 | 用途 | 读者 |
|---|---|---|
| [设计规划](../wow-addon-manager-agent-dev-plan.md) | 架构权威来源：分层、领域模型、Command API、SQLite Schema、安装流水线、Agent 任务卡 | 全体 |
| [开发任务](./开发任务.md) | 把设计规划转成可执行任务（A0–A9）：任务卡、依赖图、里程碑、验收 checklist | 开发者 / Agent |
| [开发规范](./开发规范.md) | 编码、模块边界、错误模型、DB、测试、Git、日志、提交自检 | 开发者 / Agent |
| [发布清单](./发布清单.md) | 发布前质量门槛、端到端黄金链路、打包产物、跨平台测试矩阵、已知限制 | 发布负责人 |

## 建议阅读顺序

1. **设计规划** —— 理解终态架构与模块边界。
2. **开发规范** —— 掌握必须遵守的硬约束。
3. **开发任务** —— 按批次领取任务并执行。

## 目录约定

```text
manager/
  wow-addon-manager-agent-dev-plan.md   # 设计规划（架构权威来源）
  docs/                                 # 文档（本目录）
    README.md
    开发任务.md
    开发规范.md
  wow-addon-manager/                    # Tauri 工程（由任务 T-A0 创建）
    src/                                # 前端
    src-tauri/src/                      # 后端
```

## 执行批次速览

```text
第 1 批： A0 项目骨架                       （阻塞全部）
第 2 批： A1 平台 ‖ A2 扫描 ‖ A3 DB ‖ A8 前端(mock)
第 3 批： A4 安装器 ‖ A5 快照 ‖ A6 Profile ‖ A7 Provider
第 4 批： A9 集成测试与打包
```

里程碑与最小可验收链路见 [开发任务 §3](./开发任务.md)。
