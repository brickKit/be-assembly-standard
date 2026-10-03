# brickKit v1.4.1 复测记录（第四轮回复 F06-015 + FR06-030）

## 目标

1. 项目级采纳 brickKit v1.4.1：`skills update`、`require-brickkit.sh` 要求 v1.4.1。
2. 按 `brickkit-feedback/replies/phase-06.md` 的"第四轮回复"里每条的"复测"，自己复现。项目规则："已修复"要自己复现才算关闭。

## 环境

- `brickkit version`：`BrickKit CLI v1.4.1`；brickKit 源码 HEAD `636609b6`（tag v1.4.1，比 v1.4.0 多 `7fd33dc7`、`636609b6` 两个提交）
- 日期 2026-10-04
- scratch：会话 scratchpad 下 `r141/`。外壳用例是三个全新 `brickkit init` 的项目（`sha`、`shb`、`shc`），组件和外壳从 v1.4.0 复测的 `r14/bk140-sh/` 复制：组件 `demo/pub`、`demo/pub2`、`demo/solo`、`demo/other`，外壳 `demo/sh`（`[pub, pub2]`）、`demo/sh2`（`[pub, solo]`）、`demo/ash`（`[pub2]`）。发版用例是 `r14/rel/chk` 与 `remote.git`（本地 bare 远端）的副本，`origin` 改指新副本。
- 全程没有起任何容器，没有碰真实项目的部署文件。复测期间后台另有 be-acceptance 的自测在跑，互不相干。

## 项目级采纳（改了什么）

| 文件 | 改动 |
|---|---|
| `infra/scripts/lib/require-brickkit.sh` | 要求的版本 `v1.4.0` → `v1.4.1` |
| `infra/scripts/tests/test_require_brickkit.sh` | 放行的版本改成 v1.4.1；新增一条"上一个要求的版本 v1.4.0 → 拒绝" |
| `infra/scripts/tests/test_ship_dryrun.sh` | 假 brickkit 默认报的版本 `v1.4.0` → `v1.4.1` |
| `.claude/skills/brickkit-component/SKILL.md`、`.claude/skills/brickkit-troubleshoot/SKILL.md` | `brickkit skills update` 写的（FR06-030 改了这两个 skill） |
| `docs/en/04-foundations/02-languages-and-component-protocol.md` 及中文镜像 | "发布前跑一致性套件"一段补一句：v1.4.1 起检查改了组件目录或当前提交也会停下 |

为什么必须改：本机的 CLI 已经是 v1.4.1，而 `require-brickkit.sh` 按整行精确匹配，还写着 v1.4.0 时每个会调 brickkit 的 `make` 入口都以 2 退出。

采纳后跑过的检查：

| 检查 | 结果 |
|---|---|
| `bash infra/scripts/lib/require-brickkit.sh` | 退出 0 |
| `bash infra/scripts/tests/test_require_brickkit.sh` | 6 条全 ok，`PASS` |
| `bash infra/scripts/tests/test_ship_dryrun.sh` | `全部通过`（v1.4.0 那轮因 be-acceptance 的 `go.mod` 不整洁而失败，这次没有再出现） |
| `make docs-mirror`、`make docs-boundary` | 退出 0 |
| `brickkit lint --all --strict` | 退出 1，40 个文件、5 个有错误、10 条警告；与 v1.4.0 那轮的全量输出逐行对比，只有报错里文档链接的版本号从 v1.4.0 变成 v1.4.1 |

**没有跑**：`make gates`。`tools/be-acceptance` 当时检出在 `stage-b` 上并且正跑着自测，不是父仓库钉住的提交；这次改动只涉及一个版本常量、两个 skill 文件和一句文档。

## 逐条复测

### F06-015 `add` 新外壳时的提示 → 通过

项目 `sha`：`add demo/pub`，`add demo/sh`（`pub` 被挪进 `sh`，`pub2` 嵌进去），然后：

```text
$ brickkit add demo/sh2
➕ Adding demo/sh2@0.1.0
   ✅ demo/sh2@0.1.0
   ✅ demo/solo@0.1.0 (in shell demo/sh2)
📝 Written: brickkit.yaml, deploy.yaml
ℹ️  demo/pub@0.1.0 is nested under shell demo/sh, so shell demo/sh2 does not host it (a version can be in only one shell)

$ brickkit add demo/ash
➕ Adding demo/ash@0.1.0
   ✅ demo/ash@0.1.0
📝 Written: brickkit.yaml, deploy.yaml
ℹ️  demo/pub2@0.1.0 is nested under shell demo/sh, so shell demo/ash does not host it (a version can be in only one shell)
```

`deploy.yaml`：`pub`、`pub2` 仍在 `demo/sh` 下，`solo` 在 `demo/sh2` 下，`demo/ash` 没有成员。ID 排在旧外壳前（`ash`）和后（`sh2`）两种顺序都有提示。之后 `brickkit up --dry-run` 退出 0。

回复里列的行为变化：

| 回复表里的情况 | 复测 |
|---|---|
| 成员已嵌在另一个外壳下：不动，打印提示 | 通过（上面） |
| 成员在顶层（从旧外壳里移出来的）：挪进这次加的外壳 | 通过。项目 `shb`：把 `pub` 手工移回顶层，`add demo/other` 后 `pub` 仍在顶层；`add demo/sh2` 打印 `🔗 demo/pub moved into shell demo/sh2`，`deploy.yaml` 里 `pub` 在 `demo/sh2` 下 |
| 成员这次才跟着新外壳加进来，旧外壳也编进同一个版本 | **没有复测**：要先让旧外壳在项目里而它的成员不在，没有造出这个状态 |
| 一次 `add` 加进两个这样的外壳 | **没有复现出入口**：`brickkit add demo/sh demo/sh2` 被拒绝（`INVALID_ARGUMENT`，`accepts at most 1 arg(s), received 2`）。这一行指的可能是别的进入方式，没有再查 |

对本项目的影响：没有。四个外壳的 `shell.members` 里没有任何成员同时出现在两个外壳中（2026-10-04 核对）。

### FR06-030 检查跑完之后再核对一次 → 通过

组件 `bk140/chk`，`release.checks` 是 `[make, conformance]` 和 `[./scripts/second.sh]`，每个用例换一版 `second.sh` 并提交、推送后再发版。

| 用例 | `second.sh` 做什么 | 结果 |
|---|---|---|
| A | 往已跟踪的 `README.md` 追加一行 | 退出 1，`RELEASE_BLOCKED`，`the release checks left uncommitted changes in bk140/chk@0.1.3`，`Changed: M README.md`；本地和远端都没有 `0.1.3` |
| B | 留下未跟踪、没被忽略的 `coverage.out` | 退出 1，`RELEASE_BLOCKED`，`Changed: ?? coverage.out`；没有 tag |
| C | 自己 `git commit` 一次 | 退出 1，`RELEASE_BLOCKED`，`the current commit changed while the release checks of bk140/chk@0.1.3 ran`，列出检查开始时的提交和当前提交；没有 tag |
| D | 只读，什么都不改 | 退出 0，`✅ Release checks passed` 之后 `✅ Released bk140/chk@0.1.3`；tag 是带说明的注解 tag，指向 HEAD，远端有一行 |
| E | 会改文件，但带 `--skip-checks`（版本 0.1.4） | 退出 0，`⚠️ Release checks … skipped (--skip-checks)`，照常打 tag；检查没跑，文件也没被改 |

用例 A 的完整输出：

```text
🧪 Release check of bk140/chk@0.1.3: make conformance
conformance: running suite
conformance: PASS
🧪 Release check of bk140/chk@0.1.3: ./scripts/second.sh
second: rewrites a tracked file
❌ Error: the release checks left uncommitted changes in bk140/chk@0.1.3
   Directory: .
   Changed: M README.md
   Suggestion: Nothing was tagged: a tag holds a commit, and the checks ran against files that are not in it. …
```

`✅ Release checks passed` 只在用例 D 出现，改了文件的检查不会被说成通过，和回复一致。

**没有复测**：`release --local` 的"一个组件的检查改了文件，所有组件都不打 tag"；`publish` 不核对。

## 对 3.0.0 的影响（记给后面的任务）

- 组件的发版检查不能改写已跟踪的文件：不要设 `GOFLAGS=-mod=mod`（`go.mod` 需要更新时让构建直接失败）。
- 检查留下的东西（覆盖率报告、构建产物、一致性套件的报告目录）必须写进组件的 `.gitignore`，否则 `release` 被拦下。
- `ship.sh` 不需要自己在 `brickkit release` 之后再核对工作区（v1.4.0 那轮的建议第 4 条作废）。
- 待验证清单的 V-18 关闭。

## 新发现的问题

没有。
