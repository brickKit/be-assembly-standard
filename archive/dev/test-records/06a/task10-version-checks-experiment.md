# Task 10 实验记录：brickKit v1 自己能拦住哪些版本漂移

## 目标

弄清 brickKit v1.0.0 对三种"版本号漂移"各自是否会在 `brickkit lint` 或 `brickkit up --dry-run` 阶段报错，据此决定 be-acceptance v0.4.0 里 `dependency-version-scan` gate 与 `bump-version` 要保留多少。

## 环境

- brickKit CLI v1.0.0（`brickkit --version` 不存在，版本以 common.md 为准）
- 实验目录（scratchpad，不在真实仓库）：`/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad/ver-exp`
- 项目：`brickkit init --yes --name verexp`；组件 `t/a`、`t/b`（b 依赖 `t/a@0.1.0`）、外壳 `t/s`（`brickkit new t/s --shell`，`shell.members: [t/a@0.1.0]`），`brickkit add --local --yes` 加入；`deploy.yaml` 里 `t/a` 自动嵌套在 `t/s.members` 下。
- `brickkit lint` 输出里有大量 "a placeholder (TODO) is still in the text" 条目（骨架文档的 TODO，每条 3 行，共 38 条，与版本无关），下文已滤掉这些条目，原始输出留在 scratchpad 的 `raw-lint-*.txt`。每次跑完 `brickkit lint` 的其余输出都与 baseline 逐字相同，下文只在 baseline 写一次完整版。
- 补充：骨架默认所有组件端口都是 8080，外壳内成员端口冲突会让 `up --dry-run` 直接报错（`two components on shell t/s@0.1.0 both want port 8080`），这与版本无关，实验里把 a 改成 8081、b 改成 8082。

## 步骤

### 0. baseline（三者一致，应当全绿）

```
$ brickkit lint
✅ brickkit.yaml
✅ deploy.yaml
✅ cross-file: brickkit.yaml ↔ deploy.yaml ↔ config/
✅ components/t/a/component.yaml
✅ components/t/b/component.yaml
✅ shell/t/s/component.yaml
⚠️ component.yaml depends on t/a, but "Dependencies" does not mention it
   File: components/t/b/BRICKKIT.md
   Line: 11
⚠️ the shell compiles in t/a, but "Shell declaration" does not list it
   File: shell/t/s/BRICKKIT.md
   Line: 25

📋 Checked 10 files: 0 with errors, 40 warnings
exit=0

$ brickkit up --dry-run
🚀 Starting project verexp (target: docker)
📋 Component state calculation:
   ✅ t/a@0.1.0  starting (t/b needs it)
   ✅ t/b@0.1.0  starting (top-level)
   ✅ t/s@0.1.0  starting (top-level)

📋 Start order (topological sort):
   1. t-s-0-1-0  no dependencies  (hosts t/a@0.1.0)
   2. t-b-0-1-0  ← depends on 1

Can start on their own: t-s-0-1-0 (no dependencies)
Longest dependency chain (2 levels): t-s-0-1-0 → t-b-0-1-0

Dependency graph:
   t/b@0.1.0 → t/a@0.1.0
📄 Generated: .brickkit/generated/compose.yaml

💡 --dry-run only generates the files and starts no component
   View it: cat .brickkit/generated/compose.yaml
exit=0
```

### 漂移 2（brickkit.yaml 与 component.yaml 不一致），缓存在场

做法：只把 `components/t/a/component.yaml` 的 version 改成 0.2.0，brickkit.yaml 仍 pin 0.1.0（这是我最先误当成"漂移 1"跑的那次）。

`brickkit lint`：与 baseline 逐字相同，exit=0。

```
$ brickkit up --dry-run
🚀 Starting project verexp (target: docker)
📋 Component state calculation:
   ✅ t/a@0.1.0  starting (t/b needs it)
   ✅ t/b@0.1.0  starting (top-level)
   ✅ t/s@0.1.0  starting (top-level)
   ……（其余输出与 baseline 逐字相同）
exit=0
```

原因：`.brickkit/manifests/t/a/0.1.0/` 缓存里还有旧版本的 manifest，brickkit.yaml 作为锁文件，按 pin 取缓存，没有任何报错。

### 漂移 2，缓存清空（`rm -rf .brickkit/manifests .brickkit/last-run`）

```
$ brickkit lint
……（同 baseline，多一行：）
ℹ️ configuration not checked (no manifest on disk yet — brickkit up or add fetches it): t/a@0.1.0

📋 Checked 10 files: 0 with errors, 40 warnings
exit=0

$ brickkit up --dry-run
🚀 Starting project verexp (target: docker)
❌ Error: the install source has this component, but not the version that was asked for
   Wanted version: t/a@0.1.0
   Install source local-dev (local): it has 0.2.0 here
   Suggestions:
   1. A local install source holds only one version per component directory — the version you asked for can only live in the .brickkit/manifests/ cache, and the cache can be deleted
   2. To keep components that depend on t/a@0.1.0 running, point their dependency at the version in the source and adapt them
   3. Or change the component.yaml in the install source back to 0.1.0 (and install the newer version from somewhere else)
exit=1
```

### 漂移 1（a 升到 0.2.0，brickkit.yaml 也 pin 0.2.0，b 仍依赖 `t/a@0.1.0`）

```
$ brickkit lint
……（同 baseline）exit=0

$ brickkit up --dry-run
🚀 Starting project verexp (target: docker)
⬆️ Version change detected:
   t/a: 0.1.0 → 0.2.0

❌ Error: required dependency missing
   Component: t/b@0.1.0
   Missing dependency: t/a@0.1.0
   Reason: t/a@0.1.0 is not declared in brickkit.yaml
   Suggestions:
   1. brickkit add t/b@0.1.0 writes its dependencies into the three files too
   2. Or add it on its own: brickkit add t/a@0.1.0
exit=1
```

### 漂移 3（外壳 `shell.members` 写 `t/a@0.1.0`，项目里 a 是 0.2.0，同时 b 已改成依赖 0.2.0 以隔离出漂移 3）

```
$ brickkit lint
……（同 baseline）exit=0

$ brickkit up --dry-run
🚀 Starting project verexp (target: docker)
⬆️ Version change detected:
   t/a: 0.1.0 → 0.2.0

📋 Component state calculation:
   ✅ t/a@0.2.0  starting (t/b needs it)
   ✅ t/b@0.1.0  starting (top-level)
   ✅ t/s@0.1.0  starting (top-level)

❌ Error: the member versions this run hosts in a shell differ from the ones its component.yaml says are compiled in
   File: deploy.yaml
   components[1].members[0]: shell t/s@0.1.0 contains t/a@0.1.0, but this run hosts t/a@0.2.0
   Suggestions:
   1. Upgrade t/s to a version whose component.yaml lists t/a@0.2.0 under shell.members
   2. Move the entry of t/a out of the members of t/s to the top level of the deploy file, so it runs on its own
   3. Keep both versions: add `- {id: t/a, version: 0.1.0, requiredBy: [t/s]}` to the components of brickkit.yaml, change the member entry under t/s to `- id: t/a@0.1.0`, and add `- id: t/a` at the top level of the deploy file so t/a@0.2.0 runs on its own
exit=1
```

### 额外探测：外壳自己的 `metadata.version` 与 `deployment.image` tag 不一致（现 gate 第④类）

做法：外壳 `t/s` version 0.1.0，`deployment.image: example.com/t-s:0.0.9`（去掉 build 块）。

```
$ brickkit lint
……（同 baseline）exit=0

$ brickkit up --dry-run
……（与 baseline 逐字相同的成功输出，含 Generated: .brickkit/generated/compose.yaml）
exit=0
```

### 额外探测：外壳 `go.mod` 的 require 版本

`go.mod` 是 Go 外壳的编译产物输入，不属于 brickkit 的任何一层文件（brickkit.yaml / deploy.yaml / config/ / component.yaml），v1 不读也不校验它，无需实验即可确定。

## 现象

| 漂移 | `brickkit lint` | `brickkit up --dry-run` | 报错提示是否告诉人下一步 |
|---|---|---|---|
| 1 依赖版本与项目版本不一致 | 不报（exit 0） | **拦下**，`required dependency missing`，exit 1 | 是，给出 `brickkit add` 两条建议 |
| 2 brickkit.yaml pin 与 component.yaml 不一致 | 不报（缓存清空时仅一条 ℹ️ 提示） | 缓存在场：不报，按 pin 用缓存；缓存清空：**拦下**，`install source has this component, but not the version that was asked for`，exit 1 | 是，三条建议 |
| 3 外壳 members 与项目版本不一致 | 不报（exit 0） | **拦下**，`the member versions this run hosts in a shell differ ...`，exit 1 | 是，三条建议，含"保留双版本"的具体写法 |
| 外壳 version vs image tag（探测） | 不报 | 不报 | 无 |
| 外壳 go.mod require 版本（探测） | 不检 | 不检 | 无 |

注意：三种漂移都只有 `up --dry-run` 拦得住，`lint` 一律放行；错误提示本身是可操作的。漂移 2 在缓存在场时不算"漂移"（brickkit.yaml 是锁文件，缓存即锁定内容）。

## 卡点与绕过

- 骨架默认端口都是 8080，外壳内成员端口冲突让 `up --dry-run` 一开始就失败，与版本漂移无关；手工把成员端口改成互不相同。
- 我第一次制造"漂移 1"时只改了 a 的 `component.yaml`，没改 brickkit.yaml，其实制造的是漂移 2 且被缓存掩盖，后来把三个漂移分别隔离重做。
- `brickkit --version` 不是有效 flag，没有查到更精确的 CLI 版本号。

## 结论

按 brief 第二步决策表：

1. 漂移 1、2、3 全部被 `brickkit up --dry-run` 拦下（lint 不拦），故 **`dependency-version-scan` 里的 ①（组件间依赖引用 vs 被依赖方真实版本）与 ②（brickkit.yaml 顶层 pin vs 组件真实版本）两类检查删除**。`make gates` 需要同时跑 `brickkit up --dry-run`（零启动成本）补上这层，该 Makefile 改动由控制器/对应任务落地，不在 be-acceptance 内。
2. **gate 本身不能整条删**：第③类（外壳 `go.mod` 锁定版本 vs 组件真实版本）与第④类（外壳 `metadata.version` vs `deployment.image` tag）v1 都拦不住（上面两个额外探测），这正是决策表"部分被拦下 → gate 只保留 v1 拦不住的几类"。保留这两类，改为 v1 布局：外壳在 `shell/be/<name>/`，go.mod require 带 `/vN` 模块路径后缀（v2+），版本值带 `v` 前缀而 brickkit 版本不带。gate 名字沿用 `dependency-version-scan`，避免波及 Makefile/文档里的引用。
3. `bump-version`：
   - 删除"改 `brickkit.yaml` 顶层 pin"（由 `brickkit upgrade` 取代）；
   - 删除"同步 `config:` 里 authzBundleUrl/iamJwksUrl 主机名字面量"（由 `$var:` 取代）；
   - 删除"改 AGENTS.md / AGENTS.zh.md 名册版本号"（由 CLI 维护块取代）；
   - 保留并改为 v1 路径：改下游组件 `component.yaml` 的 `dependencies.components` 版本、改外壳 `component.yaml` 的 `shell.members` 版本、改外壳 `go.mod` 的 require（带 `/vN` 路径后缀）；外壳存放于 `shell/be/<name>/`，并让级联把"外壳依赖其 members"计入反向依赖图。
4. 删除 `platform/`（v0.4 的平台断言，06f 按 v1 重写）；`closedloop/tier0_test.go` 的拆回改用 `brickkit up --ignore-shells`。

## 反馈候选

- `brickkit lint` 完全不检查版本号一致性（三种漂移全放行），只有 `up --dry-run` 才查；若 lint 能顺带检查"依赖版本在项目里是否存在 / 外壳 members 是否对得上 deploy.yaml"，就不必依赖 `--dry-run`（会生成 compose 文件，有副作用）。
- 缓存在场时 brickkit.yaml 与本地源码版本不一致不报错（漂移 2 缓存在场），不同机器（缓存有无）行为不同，可能造成"我这里能起、CI 起不来"。
- 外壳 `metadata.version` 与 `deployment.image` tag 不一致 v1 不校验。
