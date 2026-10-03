# brickKit v1.4.0 复测记录（第三轮回复 F06-011～014 + FR06-028）

## 目标

1. 项目级采纳 brickKit v1.4.0：`skills update`、`require-brickkit.sh` 要求 v1.4.0，`make gates` 照旧通过。
2. 按 `brickkit-feedback/replies/phase-06.md` 的"第三轮回复"（F06-011～014）与"FR06-028 发版前检查"每条的"复测"，在真机上自己复现。项目规则："已修复"要自己复现才算关闭。
3. 读 brickKit 的 release 源码，回答本项目的 `make ship`（`infra/scripts/ship.sh`）能不能整个交给 `brickkit release` + `release.checks`；本轮不改 `ship.sh`，只给建议。

## 环境

- `brickkit version`：`BrickKit CLI v1.4.0`，`Supported Manifest version: brickkit/v1`，targets docker / podman / k8s；brickKit 源码 HEAD `ecbf0082`（tag v1.4.0）
- Docker 29、Compose v2；基础资源 be-postgres / be-nats / be-casdoor / be-rustfs / be-traefik 一直在跑
- 日期 2026-10-03；真实项目 `/home/zhijie/Desktop/github/be-assembly-standard`，起停组件经 `infra/scripts/project-lock.sh`
- scratch：会话 scratchpad 下 `r14/`：`bk140-ph/`（占位词）、`bk140-sh/`（外壳挪成员）、`rel/`（release：`chk/` 独立组件仓库 + `remote.git` 本地 bare 远端；`bk140-loc/` 两个组件的项目 + `remotes/*.git`）。全部 scratch 都没有起容器；真实项目的组件容器最后 `brickkit down`，本地模式关掉、`deploy.local.yaml` 删掉（复测前就没有）

## 项目级采纳（改了什么）

| 文件 | 改动 |
|---|---|
| `.claude/skills/brickkit-*` | `brickkit skills update` 写了 3 个：component（新增 `release.checks` 一段）、deploy（`mode: local` 也写 `local-debug.<…>.env`；`$endpoint:` 示例改成 `IAM_JWKS_URL`）、troubleshoot（新增 `RELEASE_CHECK_FAILED` 一行）；assemble、plan-change 已是最新。`brickkit skills status` 5 个全部 `up to date`。`AGENTS.md`、`AGENTS.zh.md` 与更新前的备份 `cmp` 逐字节相同（维护块已是当前内容，我们自己的小节一个字没动） |
| `infra/scripts/lib/require-brickkit.sh` | 要求版本改成 `BrickKit CLI v1.4.0`（声明了 `release:` 的 `component.yaml` 旧 CLI 会当未知字段拒绝） |
| `infra/scripts/tests/test_require_brickkit.sh` | 版本号跟着改；新增一例"上一个要求的版本 v1.3.1 → 拒绝"。5/5 ok |
| `infra/scripts/tests/test_verify_deploy.py`、`test_config_fill.py`、`test_ship_dryrun.sh` | 假 brickkit 的默认版本 `FAKE_BK_VERSION:-v1.3.1` → `v1.4.0`（不改的话这三个测试会被版本核对拦下） |

脚本测试：`test_require_brickkit.sh` PASS；`test_verify_deploy.py` 31/31、`test_config_fill.py` 25/25、`test_teardown_sync.py` 8/8、`test_docs_boundary.py` / `test_docs_mirror.py` rc=0；`test_db_pw` / `test_dev_env` / `test_project_lock` / `test_seed_net` PASS。

`test_ship_dryrun.sh` 在当前工作区 **FAIL**，与本轮改动无关：它 clone 的是工作区里 `tools/be-acceptance` 的 HEAD `8587256`（另一条线的提交，父仓库还没钉住，父仓库钉的是 `6e73b4d`），该提交的 `go.mod` 不整洁（`nats.go`、`prometheus/common` 已被直接 import 却仍标 `// indirect`），测试设的 `GOFLAGS=-mod=mod` 下 `go build` 会改写 `go.mod`，之后 ship 的"门禁仓库工作区必须干净"把后续用例全部拦下（`FAIL B / C / C2 / G / H …：门禁仓库 … 工作区不干净（ M go.mod;）`）。对照：scratch 里把 `infra/scripts` 复制出来、`tools/be-acceptance` 换成钉住的 `6e73b4d`，同一个测试 `全部通过`。要 be-acceptance 那条线在 `8587256` 之后补一次 `go mod tidy`。

`make gates`：exit 0（6 个 be-acceptance 门禁 + config-key-scan + openapi-additive-scan + docs-boundary + docs-mirror + `brickkit up --dry-run`）。

## lint 现状（`brickkit lint --all --strict`，全量输出，未截断）

exit 1，40 个文件，5 个有错误，**10 条警告**（v1.3.1 是 11 条）。少的那一条就是 `docs/zh/04-foundations/07-tenancy.md:92` 的 `DOC_PLACEHOLDER (后补)`。剩下的全部是 v1.3.1 记录里已列的老原因：`❌ [MANIFEST_INVALID]` ×5（`components/frontend/standard` 还是 1.x 清单、4 个外壳 `shell.members: []`），`⚠️` ×10 都在 `components/frontend/standard`（缺 BRICKKIT.md、AGENTS 缺 8 个小节、没有维护块）。项目级文件全部 ✅。

## 逐条复测

### F06-011 中文占位词按字面子串匹配 → 通过

- 真实项目：`docs/zh/04-foundations/07-tenancy.md` 第 92 行不再报（上一节）。
- scratch `bk140-ph`（`docs/en/a.md` + `docs/zh/a.md`）。下面四行**都不报**：
  ```
  事后补上，就是每个组件一次大版本。
  以后补充别的说明。
  期待补充更多例子。
  等待填写的表单由前端处理。
  ```
  逐行追加后：
  ```
  这一节（待补）       → ⚠️ [DOC_PLACEHOLDER] a placeholder (待补) is still in the text  File: docs/zh/a.md  Line: 9
  示例【待补】         → (待补)   Line: 10
  待补充：迁移步骤      → (待补充) Line: 11
  后补（单独一行）      → (后补)   Line: 12
  ```
  `BRICKKIT_LANG=zh` 时是 `⚠️ [DOC_PLACEHOLDER] 正文里还留着占位（待补）`。
- 规则的另一面（与文档一致，记一笔，不算缺陷）：前面紧挨汉字的写法照规则不报——`本节内容待补充。`、`这里待填写。`、`相关说明后补。` 三行都没报，`示例：待补`（前面是冒号）报。`brickkit docs 06-architecture/09-error-codes` 的 `DOC_PLACEHOLDER` 一节写明了："a Chinese one with another Chinese character right next to it is part of an ordinary sentence, not a placeholder"。项目自己写中文文档时，占位要用 `（待补）` / `待补充：` 这类独立写法，lint 才拦得住。
- 结论：通过。

### F06-012 `add` 外壳时挪成员（改的是文档）→ 文档与行为基本一致；"一个版本已在别的外壳下面时给一条提示"不成立（新缺陷 F06-015）

- 文档：`brickkit docs 04-shell/04-members-management` 现在写"A member that was already in the project … is **moved under the shell too**"，以及回复列的四条（只有 `add` 外壳本身才挪；外壳已在项目里后不再挪；已嵌在别的外壳下的不动、给一条提示；只写 `deploy.yaml` 与 `deploy.local.yaml`，`-f` 的其他文件列为没改）。
- scratch `bk140-sh`：组件 `demo/pub`、`demo/pub2`、`demo/solo`、`demo/other`，外壳 `demo/sh`（`[pub, pub2]`）、`demo/sh2`（`[pub, solo]`）、`demo/ash`（`[pub2]`），另放一份 `deploy.prod.yaml`，`brickkit local on`。
  1. `add demo/pub` → 顶层；`add demo/sh`：
     ```
     ➕ Adding demo/sh@0.1.0
        ✅ demo/sh@0.1.0
        ✅ demo/pub2@0.1.0 (in shell demo/sh)
        🔗 demo/pub moved into shell demo/sh
     📝 Written: brickkit.yaml, deploy.yaml, deploy.local.yaml
     ℹ️  Not changed: deploy.prod.yaml; when you deploy those environments with -f, carry the change over yourself
     ```
     `deploy.yaml` 与 `deploy.local.yaml` 里 `pub`、`pub2` 都在 `demo/sh` 的 `members:` 下；`deploy.prod.yaml` 不变。→ 与文档一致。
  2. 把 `demo/pub` 手动移回顶层，再 `add demo/other`：`pub` 留在顶层；再 `add demo/sh`：`✅ demo/sh@0.1.0 is already in the project; none of the three files needs a change`，`pub` 仍在顶层。→ 与文档一致（顺带看到 `add` 把顶层条目按 ID 排了序，`pub` 被排到 `sh` 前面，diff 会多几行）。
  3. **已嵌在别的外壳下**：`pub` 在 `demo/sh` 下时 `add demo/sh2`（也编进 `pub`）：
     ```
     ➕ Adding demo/sh2@0.1.0
        ✅ demo/sh2@0.1.0
        ✅ demo/solo@0.1.0 (in shell demo/sh2)
     📝 Written: brickkit.yaml, deploy.yaml, deploy.local.yaml
     ℹ️  Not changed: deploy.prod.yaml; …
     ```
     `pub` 留在 `demo/sh` 下（对），但**没有任何提示**。换成 ID 排在前面的外壳 `demo/ash`（编进已在 `demo/sh` 下的 `pub2`）再试一次，同样没有提示。
     源码 `internal/install/add.go`：`nestExisting` 对每个已声明的组件先 `hostOf(ref)`——按 `shellIDs` 顺序返回**第一个**编进它的外壳；`shellIDs` 来自 `graph.Nodes`，而 `internal/cli/add.go:114-132` 解析时先放项目里已有的组件、后放这次的目标，所以已在项目里的外壳总排在前面。于是 `hostOf` 返回的就是成员现在所在的旧外壳，`!fresh[shell]` 成立直接 `continue`，走不到 `default:` 分支里的 `InstallNoteMemberUnderOtherShell`。这条提示在"已嵌在别的外壳下、再加一个新外壳"的场景里到不了；`internal/install` 的测试里也没有覆盖它的用例。
- 结论：挪 / 不挪的行为与新文档一致；提示缺失写成 F06-015。

### F06-013 `mode: local` 也写 `local-debug.<服务名>.env` → 通过（真实项目）

- 步骤（`project-lock.sh` 里一个脚本跑完）：`brickkit up --focus erp/sales`（后台、`setsid`）→ 等 `listening on port` → 看文件 → `set -a && source <文件> && set +a` 后在组件目录手动跑迁移 → 停 focus 进程 → `up --all --dry-run` → `up --all` → `brickkit down` → `local off`、删 `deploy.local.yaml`。
- 复测前 `.brickkit/generated/` 下没有任何 `local-debug.*`。focus 之后：
  ```
  -rw------- 1 zhijie zhijie 1641 Oct  3 16:08 .brickkit/generated/local-debug.erp-sales-2-0-0.env
  # Component: erp/sales@2.0.0 (mode: local)
  # These are all the variables brickkit up starts this process with (listening on port 8084);
  # brickkit itself doesn't read this file. To run a one-off command with the same variables, such as
  # the component's migration: `set -a && source <this file> && set +a`, then run the command
  ```
  权限 600；22 个键（只看键名与非密钥值）：`PG_HOST=localhost`、`PG_PORT=5432`、`PG_DATABASE=brickkit_db`、`PG_SCHEMA=erp_sales`、`NATS_URL=nats://localhost:4222`。focus 输出里没有"去 IDE 里启动"那段（`grep -c IDE` = 0），迁移提示照旧：`2. Use the environment variables from local-debug.erp-sales-2-0-0.env`。宿主机 `http://localhost:8084/healthz` → 200。
- 手动迁移：`source` 之后 `go run ./backend/cmd/migrate up` → rc=0，`{"msg":"迁移结束","direction":"up","schema":"erp_sales","outcome":"ok","version":5,"dirty":false}`（已是最新版本，空跑一次）。
- 停掉 focus 进程后文件还在（组件在 `deploy.local.yaml` 里仍是 `mode: local`）；`brickkit up --all --dry-run` 打印 `🎯 Focus cleared: every component runs`，文件**已被删掉**（dry-run 也删）；`brickkit up --all` exit 0，`✅ All components started (13)`，13 个 `healthy`，`.brickkit/generated/` 下没有 `local-debug.*`。`brickkit down` rc=0，之后没有组件容器。
- 记一笔（不算缺陷）：迁移提示第 1 条是 `Run the component's migration command by hand on this machine: ./migrate up`，这是镜像里的命令；本机源码里没有 `./migrate`，本项目 Go 组件本机的等价写法是 `go run ./backend/cmd/migrate up`。brickKit 只知道 `migration.command`，这一步只能由组件文档补。
- 结论：通过。

### F06-014 deploy skill 的 `$endpoint:` 示例 → 通过

`skills update` 后 `.claude/skills/brickkit-deploy/SKILL.md:97` 是 `IAM_JWKS_URL: $endpoint:infra/iam/.well-known/jwks.json   # another component's address (+ optional path)`；brickKit 源码里中文 skill（`internal/skills/assets/zh/…/brickkit-deploy/SKILL.md:87`）同样改了。

### FR06-028 `release.checks` → 通过（scratch，远端是本地 bare 仓库）

- 组件：`brickkit new bk140/chk --path chk`，独立 Git 仓库，`origin` 指向 `rel/remote.git`。`component.yaml` 加：
  ```yaml
  release:
    checks:
      - [make, conformance]        # 环境变量 CONF=ok 才通过；每次运行往 marker.log 记一行
      - [./scripts/second.sh]
  ```
  `brickkit lint` 不报错。
- **失败 → 不打 tag**（`CONF` 未设）：
  ```
  🧪 Release check of bk140/chk@0.1.0: make conformance
  conformance: running suite
  conformance: FAIL (CONF=)
  make: *** [Makefile:4: conformance] Error 3
  ❌ Error: a release check of bk140/chk@0.1.0 failed: make conformance exited with code 2
     Directory: .
     Suggestions:
     1. Its output is above. Nothing was tagged or uploaded; fix what it reports, commit, and release again
     2. To release without running the checks: --skip-checks (the output says they were skipped)
  ```
  rc=1，日志 `"error_code":"RELEASE_CHECK_FAILED"`；`git tag` 空，`git ls-remote --tags origin` 空；marker 只有 `conformance`（第二条没跑）。
- **通过 → 打 tag**（`CONF=ok`）：两条依次跑，`✅ Release checks passed: bk140/chk@0.1.0`、`✅ Released bk140/chk@0.1.0: tag 0.1.0 pushed`、`📝 Release notes written into the tag`；`git cat-file -t 0.1.0` = `tag`，远端有 `refs/tags/0.1.0` 与 `^{}`，tag 说明原样（`## 0.1.0` 标题保留）。
- **`--skip-checks`**（0.1.1，`CONF` 未设）：`⚠️  Release checks of bk140/chk@0.1.1 skipped (--skip-checks)`，然后 `tag 0.1.1 pushed`；marker 为空（一条都没跑）。
- **跑不起来**（0.1.2，`second.sh` 去掉执行位）：`❌ Error: a release check of bk140/chk@0.1.2 could not be run: ./scripts/second.sh … Reason: fork/exec scripts/second.sh: permission denied`，建议"each item is one argument … no shell is involved"；远端没有 0.1.2。
- **实时输出**：检查脚本 `echo start; sleep 3; echo end; exit 1`，逐行打时间戳：`57.33 second: start` → `00.29 second: end` → `00.30 ❌ Error …`——输出不攒着。
- **清单校验**：`- make conformance`（字符串）→ `❌ [MANIFEST_INVALID] release.checks[0]: must be an array — one command, with its arguments as items, for example [make, test]; got scalar`；`- []` → `release.checks[0]: an empty command …`。
- **`--local` 全有或全无**（scratch 项目 `bk140-loc`，`components/bk140/{a,b}` 各自是带 bare 远端的仓库，检查读 `CONF_A` / `CONF_B`）：
  - `add --local` 与 `up --dry-run` 之后 marker 为空——`add` / `up` 不执行检查。
  - `CONF_A=ok`、`CONF_B` 未设：a 的检查通过、b 的失败，`RELEASE_CHECK_FAILED`；**a 和 b 本地、远端都没有 tag**。
  - b 有未提交改动：`❌ Error: bk140/b@0.1.0 has uncommitted changes`，marker 为空——平台检查全部先过、才跑组件自己的检查。
  - 都设 ok：两个检查都跑完才开始打 tag（`✅ Released bk140/a@0.1.0` / `b@0.1.0`，`✅ 2 components released`）；重跑：两个都 `⏭️ … is already released`，检查不跑。
  - a 升到 0.1.1 后 `release --local --skip-checks`：b 跳过，a 给 `⚠️ Release checks of bk140/a@0.1.1 skipped (--skip-checks)` 后发布。
- 文档：`brickkit docs 03-component-guide/07-release-workflow` 有 "Your own checks: `release.checks`"（中文"你自己的检查"），`06-architecture/09-error-codes` 有 `RELEASE_CHECK_FAILED`，`11-reference/01-component-yaml-schema` 有 `release.checks` 行。
- 记一笔（设计上的空档，不是缺陷，放进待验证清单 V-18）：工作区是否干净只在检查**之前**查一次，检查之后不再查（`runRelease`：`Check()` → `runReleaseChecks` → `Publish()`，`Publish` 在 `t.remote` 已设时不重查）。一个会改已跟踪文件的检查（脚本往 `README.md` 追加一行）照样 `✅ Released bk140/chk@0.1.2`，发布后 `git status` 是 ` M README.md`——检查过的树和打 tag 的提交不是同一个。Go 组件里最现实的情形是 `GOFLAGS=-mod=mod` 下 `go build` / `go test` 改写 `go.mod`（本轮 `test_ship_dryrun.sh` 就踩到了同一件事）。
- 结论：通过。`publish` 没有市场可测，未验。

## ship.sh 能不能交给 `brickkit release`（读源码的结论与建议）

源码：`internal/cli/release.go`、`internal/release/release.go`、`internal/release/checks.go`（v1.4.0，`ecbf0082`）。

| `brickkit release` 做什么 | 对 ship.sh 意味着什么 |
|---|---|
| 一次只打**一个** tag：`source.VersionTag(id, version, subpath)`，组件在仓库根时是 `<版本>`；没有任何开关或钩子再打别的 tag | Go 的 `v<版本>` 与契约子模块的 `gen/<domain>/<name>/vX` 它都打不了，只能留在 ship.sh |
| 有说明时 `git tag -a <tag> --cleanup=verbatim -m <说明去掉末尾换行>`；没说明时打轻量 tag | 与 ship 自己打 v / gen tag 的 `-a --cleanup=verbatim -F` 一致（只差末尾换行） |
| 顺序：清单校验 → 组件目录干净 → 分支有上游且 `@{u}..HEAD` 为 0 → tag 本地远端都不存在（已在 HEAD 上 → "already released" 报错）→ `release.checks` → 打 tag → 推送，推送失败删本地 tag | main 必须先推上去，release 才肯打 tag——ship 第 1 步先推 main 的做法不能省 |
| `release.checks`：argv、不经 shell、在组件目录下、环境变量用调用方的、标准输入不接、输出实时；第一条非零就 `RELEASE_CHECK_FAILED`；`--skip-checks` 打一行 ⚠️；`add` / `fetch` / `up` 不跑 | ship 已经调用 `brickkit release --notes-file`，组件一旦声明了检查，ship 自动就跑；ship 绝不能传 `--skip-checks` |
| 没有 `--dry-run` | `ship --dry-run` 跑不到 `release.checks` |
| `--local`：一次发项目本地源里的全部组件，不收说明 | 不适合 ship（按组件发、要说明、要 Go tag） |

**建议：不整体交出去，`brickkit release` 只负责它那一个裸 tag（加组件自己的检查），Go 的 tag 和项目级门禁仍由 ship.sh 做。** 具体：

1. **项目级门禁留在 ship 第 1 步，不写进 `release.checks`。** openapi-additive-scan / config-key-scan 用的是父仓库钉住的 be-acceptance、`--root` 是组件目录往上三层，还要先核对远端发布 tag 当基线。写进组件的 `component.yaml` 就等于把"必须嵌在本项目 `components/<scope>/<name>/` 里"写进组件清单：从组件自己的仓库单独 clone 出来发版时这条检查必然失败，只能 `--skip-checks`，违背"组件能独立运行和发布"。它们也必须在推 main、打任何 tag 之前拦住。
2. **组件自己的检查写进 3.0.0 组件的 `release.checks`。** 只放不依赖本项目、不需要容器和数据库的：单元测试、`contract-check`（buf breaking）、`import-scan`、`module-check`、`dag-check`。建议每个组件的 Makefile 出一个 `release-check` 目标、清单里写 `[[make, release-check]]`。不能直接用现在的 `make all`：`check-version` 要求 HEAD 上已有 tag（检查跑的时候 tag 还没打）、`test` / `migrate-idempotent` 要数据库、`docs-check` 调的是项目根的 `make docs-check`。这样谁直接敲 `brickkit release` 都过同一组检查，ship 什么都不用改就能拿到。一致性套件（要对运行中的容器跑）需要先起容器，不适合放进 `release.checks`，留在 ship / verify 流程里。
3. **改 ship 的顺序：先 `brickkit release`，再打 `gen/…` tag。** 现在第 2 步推契约包 tag、第 3 步才 `brickkit release`；一旦组件有了 `release.checks`，检查在第 3 步失败时契约包 tag 已经推出去了（Go 代理会缓存，不能撤）。建议改成：1 门禁 + 推 main → 2 `brickkit release`（检查 + 裸 tag）→ 3 契约包 tag → 4 v tag → 5 拉取探针。契约包 tag 只要在 v tag 被拉取（探针）之前存在就行，排在裸 tag 之后不影响 Go。
4. **检查之后 ship 自己再查一次工作区。** brickKit 只在检查前查干净（上一节 V-18）。ship 在第 2 步之后加一行 `git status --porcelain` 必须为空，防止"检查改了 `go.mod` 才过、tag 打在没改的提交上"；组件的检查也不要设 `GOFLAGS=-mod=mod`。
5. `ship --dry-run` 照旧不调 `brickkit release`，可以多打印一行该组件声明的 `release.checks`，让人知道真跑时会多跑什么；`test_ship_dryrun.sh` 的假 brickkit 加一条断言：参数里永远没有 `--skip-checks`。
6. 用到 `release:` 的 `component.yaml`，v1.4.0 之前的 CLI 会当未知字段拒绝（回复里说的）：本项目已经要求 v1.4.0；外部项目要用我们的 3.0.0 组件也得 ≥ v1.4.0，写进组件 BRICKKIT.md 的"部署前准备"。

回复里"`make ship` 可以改成直接调 `brickkit release`"：ship 本来就在调；能交出去的只是"发版前跑组件自己的检查"这一件，裸 tag 之外的三样（项目门禁、契约包 tag、v tag）brickKit 不做，也不应该做（都是本项目 / Go 生态的规则）。本项目没有 pre-push 钩子，不涉及。

## 新发现的问题

| 编号 | 一句话 | 证据 |
|---|---|---|
| F06-015 | `add` 一个新外壳、它编进的版本已嵌在另一个外壳下时，文档承诺的"stays there, with a note"只做到了前半句：成员不动，但提示从来不打印 | 上文 F06-012 第 3 步（`demo/sh2`、`demo/ash` 两种 ID 顺序都没有提示）；源码 `internal/install/add.go` 的 `nestExisting` 先 `hostOf` 取第一个外壳，而已在项目里的外壳在解析顺序里总排在前面，`default:` 分支到不了 |

## 没有复测的

- `brickkit publish` 跑同一组检查：没有市场可测。
- 旧版 CLI 拒绝 `release:` 字段：没装旧版 CLI 做对照（`~/go/bin` 里的 v0.4.6 太旧，不能说明问题）。
- F06-012 的"外壳在项目里之后，再加一个它编进的组件，从一开始就嵌进去"：只有先 `remove` 成员才造得出这个场景，`remove` 因组件目录有未推送提交拦下（要 `--force`），没继续。
