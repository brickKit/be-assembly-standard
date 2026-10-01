# 阶段 06 总计划

> **For agentic workers:** 本文件只是路线图。每个子阶段都有一份单独的详细计划（`plan-06x.md`），执行时以详细计划为准。REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement each sub-plan task-by-task.

**Goal:** 按 brickKit v1.0.0 的命令和规范从头重建整个项目，然后在重建后的项目上大规模验证 brickKit，并把验证中发现的问题整理成反馈交给 brickKit。

**Spec:** [`spec.md`](spec.md)

**为什么拆成多份计划：** 每个子阶段的具体做法都依赖上一个子阶段的实际产出，例如 SDK 新接口的签名、外壳 ID、前端需求盘点的结果。06b 及以后的详细计划，在上一个子阶段的检查点通过后再写，写的时候以真实产出为依据，不提前猜测。

## 子阶段与检查点

| 子阶段 | 详细计划 | 主要交付物 | 检查点（停下汇报） |
|---|---|---|---|
| 06a 地基 | [`plan-06a.md`](plan-06a.md) | 归档旧文件；CLI 重新生成项目三层文件和 skill；SDK 三件套适配 v1 并新增 shell 包；be-ops、be-acceptance、Makefile、脚本按 v1 重写；4 个外壳骨架；项目级正式文档；前端需求盘点；AI 路由题库；单组件闭环清单 | 06a 完成后 |
| 06b 组件迁移 | `plan-06b.md`（06a 通过后再写） | 14 个后端组件中的 13 个按批次 B1–B6 重建、升到 2.0.0 并发布；4 个外壳组装成员后发布 1.0.0 | mdm/customer 完成后；之后每个批次结束 |
| 06c 前端 | `plan-06c.md` | 视觉方向选定；frontend/standard 升 2.0.0；功能补全；i18n；菜单汇总；FE-1 到 FE-4 测试 | 视觉方向选定后；06c 完成后 |
| 06d AI 路由测试 | `plan-06d.md` | 三档模型的考试结果；根据错题修改文档；回归 | 06d 完成后 |
| 06e 部署矩阵 | `plan-06e.md` | 18 格矩阵 + 专项格的过程记录；local 文件与 debug 测试线；重写 `docs/ops/` | 矩阵完成后；local 测试线完成后 |
| 06f 剩余功能与收尾 | `plan-06f.md` | 逐项功能测试记录；新的 tier1 断言；反馈信箱定稿；复盘；归档 `dev/` | 06f 完成后 |

## 贯穿全阶段的规则

- 以最终目的为主：过渡状态下的临时问题不修。06a 和 06b 期间，`brickkit lint` 在项目根目录会因为 `components/` 下还没重建的旧 `component.yaml` 报错，这是预期之中的，不处理；单个组件的验证在组件仓库里跑 `brickkit lint --strict`。
- 所有测试都按 spec §10 的格式写过程记录。
- 未验证的疑问记入 [`to-verify.md`](to-verify.md)。只有在重建后的结构上验证成立的问题，才写进 `brickkit-feedback/phase-06.md`。
- 每次不得不去翻 brickKit 仓库才能继续时，在 `to-verify.md` 的知识缺口记录（V-04）里追加一行。这项记录从 06a Task 1 完成后开始。
- 新建或删除 GitHub 仓库之前先提醒用户；镜像不推送；测试用的版本只打本地 tag。
