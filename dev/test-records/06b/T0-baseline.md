# T0 基线记录（06b 起点）

## 目标
记录 06b 开始前的 lint / gates / 版本 / 子模块基线，之后"是不是本次引入的"都以此为准。

## 环境
- brickKit CLI v1.1.0；仓库 main，起点提交 fa7062f；工作区干净。
- 工具版本：be-ops v0.2.0、be-acceptance v0.4.4、be-sdk-go v0.3.2、be-sdk-python v0.4.3、be-sdk-ts v0.4.0。
- 子模块 23 个（14 组件 + 4 外壳 + 5 工具），`git submodule status` 每行都以空格开头（无 `+`）。

## 步骤
Step 1 前置检查：`brickkit version` 为 v1.1.0；`git status --short` 为空；`infra/scripts/component-lint.sh` 已删；Makefile 的 docs-check 为 `brickkit lint --strict $(ID)`；4 个外壳的 `AGENTS.zh.md` 中 `^## BrickKit` 计数均为 0。

Step 4 命令与结果：
- `brickkit lint --strict`：exit=1（`Checked=40 files; With errors=18 files; Warnings=143`）
- `make gates`：exit=0
- `make version-check`：exit=2（4 个外壳还没有任何 tag）
- `make docs-boundary docs-mirror registry-check`：全部通过（端口册与 schema 册自洽，62 个组件 + 带外容器/外壳自身）

### lint 原文分类
(a) `components/*` 旧清单（14 个，预期，06b 逐个消失）：
- 14 条错误：`dependencies.resources: unknown field`（每个组件一条，行号分别为 opportunity 84、finance 96、inventory 100、sales 136、frontend/standard 13、authz 54、bff-mobile 76、iam-casdoor 73、notification 43、print 35、workflow 41、im-dingtalk 55、customer 47、product 52）。
- 143 条警告，每个组件：`BRICKKIT.md is missing`；`AGENTS.md has no usable block maintained by brickkit`；AGENTS.md 缺 9 节（Use it in a project / Pitfalls / Documentation / Development / Design decisions / Code map / Build and test / Before changing code，另含其余旧节差异）。

(b) 4 个外壳 `members: []` 的 `MANIFEST_INVALID`（预期，各外壳 Task 之后消失）：
- `shell/be/go-backoffice`、`go-core`、`go-infra`、`py-render`：`shell.members: a shell must list at least one component compiled into it`。

(c) 项目自己的文档（`AGENTS*.md`、`README*.md`、`docs/`）：lint 输出里 `./ (docs)` 为 ✅，没有任何来自 components/ 与 shell/ 之外的错误或警告。类别 (c) 为零，本 Task 无需改文档。

lint 尾部原文：
```
{"time":"2026-10-02T03:11:29.476652727+02:00","level":"ERROR","message":"Command failed","command":"brickkit lint","elapsed_ms":102,"error_code":"LINT_FAILED","error":"LINT_FAILED: Error: the structure check did not pass; Checked=40 files; With errors=18 files; Warnings=143 (--strict: warnings count as failures)","exit_code":1}
exit=1
```

### make gates 原文
```
✓ 铁律六 import 扫描：0 条违规
✓ SystemClient 误用扫描：0 条违规
✓ 裸路由/裸 resolver 扫描：0 条违规
✓ 事件契约破坏性变更扫描：0 条违规
✓ data-scope-test-scan：0 条违规
✓ dependency-version-scan：0 条违规
⚠ config/vars.yaml:22：infra-authz-2-0-0 对应的组件不在 brickkit.yaml 里，无法核对版本（还没装上它时是预期状态）
⚠ config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里，无法核对版本（还没装上它时是预期状态）
✓ service-hostname-scan：0 条错误（2 条警告）
▸ brickkit up --dry-run（brickKit 自带的漂移检查：依赖/版本钉/外壳成员；不启动任何容器）
📋 The current project has no components
   Add all the components under components/ with brickkit add --local
   Or add one from an install source with brickkit add <component-id>
```

### make version-check 原文
```
✓ tools/be-ops：v0.2.0
✓ tools/be-acceptance：v0.4.4
✓ tools/be-sdk-go：v0.3.2
✓ components/mdm/customer：v1.0.10
✓ components/mdm/product：v1.0.11
✓ components/erp/inventory：v1.0.18
✓ components/erp/finance：v1.0.14
✓ components/erp/sales：v1.0.26
✓ tools/be-sdk-python：v0.4.3
✓ tools/be-sdk-ts：v0.4.0
✓ components/infra/authz：v1.0.8
✓ components/infra/iam-casdoor：v1.0.10
✓ components/infra/workflow：v1.0.4
✓ components/infra/notification：v1.0.4
✓ components/integration/im-dingtalk：v1.0.5
✓ components/infra/print：v1.0.8
✓ components/infra/bff-mobile：v1.0.22
✓ components/frontend/standard：v1.0.1
✓ components/crm/opportunity：v1.0.13
✗ shell/be/go-core：没有任何 tag（fatal: No names found, cannot describe anything.）
✗ shell/be/go-infra：没有任何 tag（fatal: No names found, cannot describe anything.）
✗ shell/be/go-backoffice：没有任何 tag（fatal: No names found, cannot describe anything.）
✗ shell/be/py-render：没有任何 tag（fatal: No names found, cannot describe anything.）

版本漂移检查未通过：给上面 ✗ 的仓库打新 tag 并 push
make: *** [Makefile:123: version-check] Error 1
```

## 现象
- gates 七项全部通过（含 service-hostname-scan 的 2 条警告：`infra-authz-2-0-0`、`infra-iam-casdoor-2-0-0` 还没装进 brickkit.yaml，无法核对，预期）；`brickkit up --dry-run` 报"项目没有组件"，但整体 exit=0。
- version-check 只在 4 个外壳处失败（外壳还没有 tag）；组件与工具版本均与子模块 tag 一致（组件 1.0.x 为旧版，06b 升到 2.0.0）。

## 卡点与绕过
无。06a 执行区 `.superpowers/sdd/plan-06a/` 由控制者在本提交验证后删除；`components/mdm/contracts/` 空目录已用 `rmdir` 删除（不在 git 里）。

## 结论
基线明确：lint 错误全部来自 14 个旧组件清单与 4 个空成员外壳，项目文档为零；gates 绿；version-check 只缺外壳 tag。

## 反馈候选
无。
