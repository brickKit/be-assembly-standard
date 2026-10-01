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
| 06e 部署矩阵 | `plan-06e.md` | 18 格矩阵 + 专项格的过程记录；local 文件与 debug 测试线；在 `docs/en/`、`docs/zh/` 两棵树里同时新增编号的部署文件夹（替代旧 `docs/ops/`） | 矩阵完成后；local 测试线完成后 |
| 06f 剩余功能与收尾 | `plan-06f.md` | 逐项功能测试记录；新的 tier1 断言；反馈信箱定稿；复盘；归档 `dev/` | 06f 完成后 |

## 跨子阶段待办（防遗忘）

做完一项就把 `[ ]` 改成 `[x]`，并写明在哪个提交完成。

- [x] **同步两份开发文件到 R29**：authz/iam 地址改为成员服务名（`infra-authz-<ver>` / `infra-iam-casdoor-<ver>`），不再用外壳服务名，也不再在 teardown 部署文件里覆盖。改动范围：`component-loop.md`（:260、附录 B）和 `dev/routing-tests/questions.md` 的标准答案。外壳拆成独立仓库时已一并完成（父仓库 `298d1a2`，裁定 R30）。
- [ ] **删除 06a 的 SDD 执行区**：`.superpowers/sdd/plan-06a/` 已被 git 忽略，里面有 ledger、各 Task 的审查报告和发布说明。写 `plan-06b.md` 时还要查阅，**`plan-06b.md` 写完并提交后再删**（`rm -rf .superpowers/sdd/plan-06a`）。要点已整理进 [`batches/06a.md`](batches/06a.md)，删除后不会丢失信息。
- [ ] **写 `plan-06b.md` 时以这些为准**：外壳的组装和发布步骤，以决策 0022（外壳独立成仓）和 `component-loop.md` §4 为准；`spec.md`、`plan-06a.md`、`batches/06a.md` 里仍写着"外壳是项目代码"，属于历史记录，不要照抄。06b 的其余输入见 `batches/06a.md` §6，以及外壳拆仓审查留下的事项：外壳的 `BRICKKIT.md` 不得引用本项目的 `registry/ports.tsv` 和 `make db-init`，必须在外壳发布 1.0.0 之前改掉。

- [ ] **SDK 注释里的旧文档路径**：be-sdk-go `connection.go`、be-sdk-python `connection.py` 的注释还写着 `docs/conventions/…`，06b 下次升 SDK 时顺手改成 `docs/en/01-conventions/…`。
- [ ] **阶段 06 结束时**：删掉 `docs/{en,zh}/02-decisions/README.md` 里"阶段 06 内决策可原地改写"那句说明（R33），之后推翻决策一律另起编号、旧文件标注 Superseded。

## 贯穿全阶段的规则

- 以最终目的为主：过渡状态下的临时问题不修。06a 和 06b 期间，`brickkit lint` 在项目根目录会因为 `components/` 下还没重建的旧 `component.yaml` 报错，这是预期之中的，不处理；单个组件的验证在组件仓库里跑 `brickkit lint --strict`。
- 所有测试都按 spec §10 的格式写过程记录。
- 未验证的疑问记入 [`to-verify.md`](to-verify.md)。只有在重建后的结构上验证成立的问题，才写进 `brickkit-feedback/phase-06.md`。
- 每次不得不去翻 brickKit 仓库才能继续时，在 `to-verify.md` 的知识缺口记录（V-04）里追加一行。这项记录从 06a Task 1 完成后开始。
- 新建或删除 GitHub 仓库之前先提醒用户；镜像不推送；测试用的版本只打本地 tag。
