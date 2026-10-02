# 06b 一次性迁移工具包

> 开发文件（`dev/`），只服务于"1.x → 2.0.0 这一次迁移"，阶段结束随 `dev/` 归档；正式文档不得链接本目录。
> 规则的出处是 `dev/phase-06/component-loop.md`（键名对照表 §2.1、目标形态 §2.2、推导规则 §2.3、样板 §3.1、机器核对 3.2、Go 形态与 `/v2` 4.0–4.4）。脚本与清单不一致时以清单为准，并改脚本。

这里的脚本都：可以重复运行（做过的步骤跳过，第二次运行不产生任何改动）；逐项打印改了什么；出错时大声失败（非零退出码 + `❌` 开头的一行原因），不猜。

| 脚本 | 闭环步骤 | 一句话 |
|---|---|---|
| `env.sh` | §0.1、1.4、4.17 | 核对 brickkit v1.1.0 与 buf；打印组件的全部变量（`export` 行）、PATH 追加 `~/go/bin`、`TEST_PG_DSN` / `TEST_NATS_URL`（不打印值）；建好 `$S` |
| `docs-skel.sh` | 第 2 步 / C2 | `brickkit new` 骨架 → 八份文档骨架 + `CLAUDE.md`，旧文件留底 |
| `migrate-manifest.py` | 第 3 步 / C3、8.1 | 从最后一个 1.x tag 重写 `component.yaml`、删改 `assembly.yaml`（含去掉注释里的归档引用）、改代码里的旧键读法、写发布说明骨架；`--check` 跑 3.2 |
| `manifest-overrides.yaml` | 第 3 步 | 每个组件的人工输入（英文名称与描述、R27、P11、新键、`local`、`history_allow`） |
| `go-v2.sh` | 4.0–4.4、4.6 / C4 | 契约包统一成嵌套模块、`/v2`、契约包真实版本、升 SDK、（SDK ≥ v0.4.0 时）迁移入口改成一行，最后跑判据 |
| `migrate-entry.py` | 4.6 | 由 `go-v2.sh` 调用：迁移入口一行化、删 `Module.Migrations` 字段；也可单独 `--check` |
| `component-check.sh` | 4.5、4.9、5.1、5.2 | 只读核对：旧键 / 旧平台变量 grep、历史与归档引用扫描、文档小节数 / 互链 / 链接 / 占位符，每项 PASS/FAIL |
| `tests/run.sh` | — | 在 scratch 克隆上跑全部脚本并断言（含 C-1） |

组件目录默认 `$ROOT/components/<id>`；环境变量 `BE_COMP_DIR` 可以改（测试用它指向 scratch 里的克隆）。`BE_SCRATCH` 必填（当前会话的 scratchpad 目录），`$S=$BE_SCRATCH/06b/<repo>`。

## env.sh

```bash
export BE_SCRATCH=<会话 scratchpad>
eval "$(bash $ROOT/dev/phase-06/tools/env.sh mdm/customer)"
```

- 输出 `ROOT ID REPO UREPO C S SCHEMA ROLE SVC NET` 十个 `export` 行（取值规则同 component-loop §0.1），并 `mkdir -p $S`。`SCHEMA`/`ROLE` 取自 `registry/schemas.tsv`，不连库的组件为空。
- 另外三行（原样输出，eval 的那一刻才展开）：
  - `case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$PATH:$HOME/go/bin" ;; esac`——`~/go/bin`（buf、protoc-gen-go、grpcurl）**追加在末尾**，绝不放前面：`~/go/bin/brickkit` 是旧的 v0.4.6，放前面会遮住 `~/.local/bin` 的 v1.1.0（task-7 审查 Important 2：`make ship` 的 `brickkit release` 会交给旧 CLI）。已经在 PATH 里就不再加，eval 几次都只有一份。
  - `export TEST_PG_DSN="postgres://postgres:$( . <ROOT>/.env …; printf %s "$POSTGRES_PASSWORD" )@localhost:5432/brickkit_test_db?sslmode=disable"`——口令在 eval 时从 `.env` 读（子 shell 里 source，只取 `POSTGRES_PASSWORD`，别的 `.env` 变量不进当前 shell），**输出与会话记录里只有变量名**。总是覆盖已有的 `TEST_PG_DSN`（测试只连 `brickkit_test_db`）。
  - `export TEST_NATS_URL=nats://localhost:4222`。
  有了这三行，C1、4.17 不用再手工 `set -a; . .env`，`make test` 也不会因为没设 `TEST_PG_DSN` 全部 SKIP。
- 打印之前先核对（按追加 `~/go/bin` 之后的 PATH）：`brickkit version` 第一行恰好是 `BrickKit CLI v1.1.0`、`buf` 在；`.env`（`BE_DOTENV` 可换路径，测试用）存在、有 `POSTGRES_PASSWORD` 这个键、值非空且不含 URL 要转义的字符（只在子 shell 里判断，不打印）。任一不过：`❌` 一行写明 PATH 上的是哪个 brickkit、什么版本，退出码 2。stderr 另有一行 `ℹ️` 摘要（只有版本与键名）。
- 失败（没设 `BE_SCRATCH`、ID 不是 `<scope>/<name>`、组件目录里没有 `component.yaml`、上面的工具核对）只写 stderr、退出码 2，`eval "$(…)"` 不会吃进半截输出。`docs-skel.sh`、`go-v2.sh`、`component-check.sh` 都先调 `env.sh`，所以它们也会因为旧 brickkit / 没有 buf 而失败。
- `ROOT` 由脚本位置推出，不读环境变量。

## docs-skel.sh

```bash
bash $ROOT/dev/phase-06/tools/docs-skel.sh <id> [--force]
git -C $C rm -q docs/手册.md; (cd $C && brickkit skills update)     # 脚本不做这两步
```

- `rm -rf $S/skel && brickkit new <id> --path $S/skel`，核对骨架五个文件都在、`CLAUDE.md` 是 `@AGENTS.md`、`AGENTS.md` 有维护块（brickKit 行为变了就失败）。
- 留底到 `$S/old/`：`AGENTS.md README.md CLAUDE.md docs/手册.md component.yaml assembly.yaml Makefile Dockerfile`，**取自组件最后一个 1.x tag**（`git show <tag>:<文件>`），与工作区和会话都无关：换会话、清空 `$S` 后再跑，留底仍是旧版原文。
- 写出：`BRICKKIT.md`（骨架原样）；`AGENTS.md`、`README.md`（骨架 + 首行 `[English](X.md) · [中文](X.zh.md)`；README 的 `brickkit add <id>@0.1.0` 改成 `@2.0.0`）；三个 `.zh.md`（固定中文标题，`BRICKKIT.zh.md` 末节"不是外壳。"）；`docs/design.md` + `.zh.md`（component-loop 5.1 的十个小节：边界、拥有的数据、契约面、事件、依赖、同步调用图里的位置、分区与归档、数据范围、参考实现、未决问题）；`CLAUDE.md` 恰好 `@AGENTS.md`。
- `BRICKKIT*.md` 不写互链行（brickKit 文档规范：`BRICKKIT*.md` 不许有任何相对链接）；其余三对文件首行互链（规范要求每个语言版本都链到其它版本）。
- 覆盖规则：目标不存在、与将写出的内容相同、或与 tag 上的同名文件逐字相同（还没人动过）→ 写；否则（已填写过）跳过并提示 `--force`。判断不看 `$S`，所以换会话重跑不会把已填写的文档换回骨架。`CLAUDE.md` 总是写成 `@AGENTS.md`。
- 判据（测试里也是这些）：九个文件都在；每对文件 `##` 小节数相等（`AGENTS.md` 维护块里的不算）；在组件目录跑 `brickkit lint`：`✅ component.yaml`、0 个错误，警告**只有**占位符（`DOC_PLACEHOLDER`）与"文档还没提到某个 required 键 / 契约文件"（`DOC_OUT_OF_STEP`）两类——正是 C5 要填的。
- 已知限制：中文正文写的是 `<!-- TODO: 待填 -->` 而不是光秃秃的"待填"，好让 lint 把没填的中文小节也报出来；`brickkit skills update` 之后 `AGENTS.md` 与骨架不同了，再跑本脚本会跳过它（这是保护，不是 bug）。

## migrate-manifest.py

```bash
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id>            # 预览：两份文件全文 + diff + 代码改动，不写盘
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id> --write    # 写盘（手改过的文件拒绝覆盖，exit 3）；要 BE_SCRATCH
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id> --write --force   # 确认要丢掉手改时
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id> --check; echo "exit=$?"
```

**输入**：组件最后一个 1.x tag 上的 `component.yaml` / `assembly.yaml`（`git show <tag>:…`，与工作区无关，所以重复运行结果相同）+ `manifest-overrides.yaml` 的该组件条目。tag 按 `1.*` 与 `v1.*` 两种找，取版本号最大的（06a 之前的组件 tag 全部带 `v`，如 `v1.0.10`）。

**`component.yaml`（整份重写，§3.1 版式）**：
- 删除全部注释、`deployment.image`、`dependencies.resources`；补 `metadata.repository`（`https://github.com/brickKit/<repo>`）、`deployment.build`、`local`；`metadata.name`/`description` 取 overrides（英文，含中文字符就失败）；`version: 2.0.0`。
- 依赖全部改 `@2.0.0`（optional 保留），加 `deps_add`；ID 重复就失败。
- `configSchema`：旧 `resources` 有 `database` → `PG_HOST`、`PG_PORT`（`"5432"`）、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`（默认值 = 旧 `pgSchema` 默认值，必须等于 `registry/schemas.tsv`，否则失败）；有 `mq` → `NATS_URL`。共享键按固定名，其余驼峰键转大写下划线。`AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL`（P1）、`drop_default` 里的键（R27）、旧 required 键一律去掉 `default`；键名含 `PASSWORD`/`SECRET`/`SIGNING_KEY` 的标 `secret: true`；属性里的 `description` 删掉（§2.3.4）；整数默认值保持数字。没有 `default` 的键全部进 `required`（按属性顺序）。
- `deployment` 其余字段（端口、`extraPorts`、`labels`、`resources`）原样搬；`migration` 原样（或 `migration_command`）；`healthCheck` 原样，`start_period_seconds` 覆盖 `startPeriodSeconds`。
- 写盘前自检：生成文本解析回来必须等于推导结果；再跑一遍 3.2 检查，不过就不写、exit 1。

**`assembly.yaml`（文本级编辑，不经 YAML 往返）**：删 `version:`、`shell:`、`asset:`（连同块内容）；**去掉注释里的归档 / 历史引用**（见下）；`data.role`（只改 `data` 的直接子键）行的注释换成 `` # 登录角色，`PG_USER` 的值 ``（对齐保留）；overrides 的 `permissions_add` / `menus_add` / `edge_routes_add` 以 `  - { k: v, … }` 追加到对应列表最后一个条目之后（与 tag 版已有的键重复就失败）；其余（含注释）逐字保留。写盘前核对：解析结果 = 旧文件去掉那三个键、加上追加的条目。

**注释里的归档 / 历史引用（`--write` 自己清，task-7 摩擦 5）**：模式 `HIST_RE` = `§|决策 ?[0-9]|设计计划|设计书|阶段[一二三四五六0-9]|总纲|手册|铁律|Task ?[0-9]|docs/plans/|archive/`（与 `component-check.sh` 的 (b) 同一个，定义在本脚本里）。
- 先去掉含引用的括号：`# 客户主数据全员可见（设计书 §14.2.2：…）` → `# 客户主数据全员可见`；括号在开头时紧跟的"，"一起去掉；去掉后只剩标点的注释行删掉。
- 去掉括号仍有引用的：整行注释删掉它所在的**整块**（连续的 `#` 行，空行为界）；行尾注释删掉注释本身（值保留，`tier: backend   # 设计书 §3.5.1 …` → `tier: backend`），连同它下面几行的续行（`#` 列与它相差不超过 2 的整行注释）。
- 块标量（`|` / `>`）里的内容、引号里的 `#` 不是注释，不动；语义自检照旧（解析结果必须等于"旧文件去掉三个键、加上追加的条目"）。
- 输出只由 tag 原文 + overrides 决定，所以重跑仍是"未改动"，手改保护照常工作——**不要再手工清这些注释**（试点就是手清之后撞上了 exit 3）。删掉的注释里还成立的结论写进 `docs/design.md`；原文在 `docs-skel.sh` 留底的 `$S/old/assembly.yaml`。
- 选的是"脚本自己清"而不是"最后一次 `--write` 之后人工清、再 `--force`"：后者每次改 overrides 重跑都要重新手清一遍，而且 `--force` 会顺手吞掉别的手改。

**发布说明骨架（`--write`，component-loop 8.1）**：`$BE_SCRATCH/06b/<repo>/notes-2.0.0.md` **不存在时**写出，已存在就跳过（`⏭ … 已存在，不覆盖`），所以人补过的内容不会被冲掉；要重新生成就先删掉它。`--write` 没设 `BE_SCRATCH` 时在写任何文件之前 exit 2。内容：
- 第一行 `<id> 2.0.0`（tag 注释的标题）；`## 升级前必须做（破坏性变更）`：
  - 旧键 → 新键逐条（`` `pgSchema` → `PG_SCHEMA` ``，…，即 `--write` 打印的映射），`config/<repo>.yaml` 要按新键重写；不再读取平台注入的 `DATABASE_*` / `MQ_*`（按旧 `resources` 有哪种）；
  - 连库组件：`PG_*` 与 `NATS_URL` 改为组件自己声明，登录角色 `<role>`、`PG_SCHEMA` 默认值、角色要在 schema 上有 USAGE + CREATE；
  - 必填性变化，按 1.x 的真实情况写：`改为必填（1.x 可以不配）：…`（1.x 没默认值、也不在 required，如 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL`）、`` `X` 改为必填（1.x 默认为空 / 默认 `v`） ``（R27 的 `drop_default`）、`改为可选`；**不写"不再有默认值"**（task-7 审查 Minor 1）；
  - 表外新键：`新增配置键 X（必填）` / `（默认 v，不配也能跑）`；
  - Go：模块路径改 `/v2`；镜像由 `brickkit build` 构建、名称 `<repo>:2.0.0`。
- `## 新增`、`## 修复` 两节留空，由人补（新接口、新字段、新权限键、修掉的 bug）。发布说明会变成 tag 注释，推送后改不了：ship 前通读一遍，删掉不适用的条目。

**手改保护（`--write`）**：写盘前逐个核对两个文件。工作区文件**既不是** tag 原文、**也不是**本次会生成的内容、**也不是**本脚本上次在这个检出里写出的内容（sha1 记在组件仓库 git 目录的 `be-migrate-manifest/` 下，不进提交），就说明 C3 之后有人手改过：一个文件都不写（代码也不改），把会丢掉的改动以 diff 打到 stderr，exit 3；`--force` 才覆盖。"上次写出的内容"这一条让"改 overrides → 重跑 `--write`"照常可用（overrides 里删掉的条目会在 diff 里以 `-` 行列出）。

**代码**：把 SDK Config 读法里的旧键改成新键，逐处打印 `文件:行: "旧" → "新"`。认的写法：Go `.String|StringOr|MustString|Int|IntOr|Bool|BoolOr("<旧键>"`，Python `.string|string_or|must_string|int|int_or|bool|bool_or("<旧键>"`（单双引号），TS/JS `.string|stringOr|mustString|int|intOr|bool|boolOr("<旧键>"`；跳过 `gen/ node_modules/ dist/ .venv/ build/ vendor/`。代码的**字符串字面量与注释**里还出现的旧键名（报错文案、注释，例如 im-dingtalk 的 `panic("必填配置项 \"dingtalkAgentId\" …")`）只用 `ℹ️` 列出来，不改——要不要改由人判断（Review Focus 2）；同名的变量名不算。

**`--check`**（当前工作区，任一项不是"无"就 exit 1）：驼峰/非法键；保留名（`*_ENDPOINT`、`COMPONENT_ID`、`COMPONENT_VERSION`、`PORT`、`BRICKKIT_SERVED_MEMBERS*`）；无默认值却不在 required；required 却有默认值；required 里有未声明的键；密码/密钥未标 secret；残留字段（`dependencies.resources`、`deployment.image`）；依赖不是 `@2.0.0`；版本注释（`#.*x.y.z`）；端口与 `registry/ports.tsv` 不一致；`PG_SCHEMA` 与 `registry/schemas.tsv` 不一致；metadata（版本 `2.x`、`repository`、英文名称与描述）；`deployment.build` / `local.runCommand` 数组；`assembly.yaml`（无 `version`/`shell`/`asset`、`id` 一致、有 `data_scopes`、`data.role` = registry 的 role）；**代码里还有驼峰键读取**；**非测试代码读取了 `configSchema` 没声明的键**（新键写进代码却忘了声明，brickKit 不会注入它）。

**已知限制**：
- `--write` 丢掉 `component.yaml` 里的全部注释（本来就要删；理由写进 `BRICKKIT.md` / `docs/design.md`）。
- **C3 之后对两个文件的任何增量都写进 `manifest-overrides.yaml` 再重跑 `--write`**（新配置键 `add_properties`、新依赖 `deps_add`、新权限键 `permissions_add`、新菜单 `menus_add`、新网关路由 `edge_routes_add`），不要手改；手改过的文件 `--write` 会拒绝（exit 3）。overrides 表达不了的改动（例如删一个 tag 版已有的权限键）只能手改，之后不再跑 `--write`，或者每次都 `--force` 并重新手改。
- 在另一个检出（新克隆）里，"上次写出的内容"的记录不存在：工作区文件若已与本次生成结果不同（例如 overrides 又改了），会被当成手改拒绝——核对 diff 后加 `--force`。
- `assembly.yaml` 里不含 `HIST_RE` 的注释原样保留；写历史却没有命中模式的（"将来""本阶段""v1.0.6 修了…"）脚本认不出，由 C5 / 审查清理——清了就是手改，之后的 `--write` 要 `--force`（先读 diff）。
- `labels` 原样搬（bff-mobile 的 `prometheus.io/port` 也保留）。
- 代码读取的识别只看方法名：别的对象上的同名方法（如 `flag.String("name", …)`）会被当成配置读取报出来；SDK 之外的读法（`os.Getenv`）不在范围内，由 4.5 的 grep 与 `make module-check` 管。
- 只处理 `database`/`mq` 两种旧 resource；出现别的种类（对象存储）直接失败，要人工声明 `S3_URL`。

## manifest-overrides.yaml

每个组件一段，字段：`name`、`description`（英文，必填）、`tags`、`add_properties`、`required_add`、`drop_default`、`deps_add`、`start_period_seconds`、`migration_command`、`local`（必填：`language` + 数组 `runCommand`）、`permissions_add`、`menus_add`、`edge_routes_add`、`history_allow`（`component-check.sh` 用：`[{path: <glob>, text: <命中行里的一段原文>, why: <为什么必须留着>}]`，三个键都必填且非空）。写了别的字段脚本就失败。**本文件是 C3 之后所有清单增量的唯一入口**：改这里，再重跑 `--write`。初稿按 component-loop §2.2 写全 13 个组件：

- `infra/authz` `drop_default: [PERMISSION_CATALOG]`、`infra/iam-casdoor` `drop_default: [ENABLED_COMPONENTS]`（R27）。
- `erp/inventory` `add_properties: LOW_STOCK_THRESHOLD {type: string, default: "10"}`（plan-06b T10）。
- `infra/bff-mobile` `deps_add` 两个 optional（P11）、`start_period_seconds: 90`、`permissions_add` 三个新键（frontend-needs §2.11，标题初稿）。
- `mdm/product` `permissions_add: mdm.product.set_status`（frontend-needs §2.2 / R8，标题初稿）。
- `infra/print` `start_period_seconds: 120`，`migration_command` 与 `local.runCommand` 写成 T16 的目标形态（包名 `infra_print`）。
- Python / TS 的 `local.runCommand` 是初稿，T16 / T20 在 `make verify FOCUS=1` 真机确定后改这里再重跑 `--write`（手改保护允许这种重跑：工作区文件就是上次写出的内容）。

## component-check.sh

```bash
bash $ROOT/dev/phase-06/tools/component-check.sh <id>; echo "exit=$?"
```

只读，一条命令跑完清单里原来手工 grep 的几项；每项一行 `PASS` / `FAIL`，`FAIL` 下面逐处列出 `文件:行: 原文`（最多 40 处）；任一 `FAIL` 就 exit 1，用法错误 / overrides 写错 exit 2。范围是 `git ls-files -co --exclude-standard`（已跟踪 + 未跟踪但没被忽略：提交前就能查），跳过 `gen/ node_modules/ dist/ .venv/ build/ vendor/ .claude/` 与二进制文件。建议在第 4 步改完代码、第 5 步写完文档、提交之前各跑一次（C4 / C5 的判据之一：`exit=0`）。

| 检查项 | 出处 | 规则 |
|---|---|---|
| 4.5 无驼峰键读取 | 4.5 第一条 grep | Go `(String\|StringOr\|MustString\|Int\|IntOr\|Bool\|BoolOr)\("[a-z]`；Python / TS 对应的 `.string_or("x` / `.stringOr("x` 等（扩到三种语言） |
| 4.5 无旧平台变量 / 旧 API | 4.5 第二条 grep | `besdk.(Endpoint\|MustEndpoint)(`、`StorageEndpoint`、`STORAGE_ENDPOINT`、`DATABASE_`、`MQ_(HOST\|PORT\|USER\|PASSWORD)`；`*.go *.py *.ts *.js *.sh *.mk Makefile`（清单原文只查 Go / sh / Makefile） |
| 4.9 scripts/ | 4.9 | `scripts/` 下 `1-0-[0-9]+`（旧版本服务名）或 `DATABASE_` |
| 历史 / 归档引用 | 5.1"不写历史"；审查 Part 3 (c)-6 | `HIST_RE`（见 migrate-manifest.py 一节）扫除 `gen/`、`*.proto`、`migrations/*.sql`、`.claude/` 以外的**全部**文件的每一行，外加文件名本身（残留的 `docs/手册.md`）；`go.mod`、`buf.yaml`、`LICENSE`、`Makefile`、`Dockerfile` 都在范围里（试点人工 grep 漏掉的就是前三个）。确有理由留着的命中写进 overrides 的 `history_allow`：打印成 `ℹ️ … history_allow 放行（why）`，不算 FAIL；没用上的条目也用 `ℹ️` 列出 |
| en/zh `##` 小节数 | 5.2 第一行 | `BRICKKIT`、`AGENTS`、`README`、`docs/design` 四对，缺文件即 FAIL；代码块（```` ``` ```` / `~~~`）与 brickKit 维护块（`brickkit:managed:begin`…`end`）里的不计 |
| 首行互链 | 5.1 | `AGENTS` / `README` / `docs/design` 两种语言的第一行都含 `[English](X.md)` 与 `[中文](X.zh.md)`（`BRICKKIT*.md` 不许有相对链接，所以不查） |
| 没有 `../` 链接 | 5.1、`DOC_LINK_NOT_PORTABLE` | 全部组件 `*.md`：`](../…` 或引用式 `[x]: ../…` |
| 没有越界链接 | 5.2 第二行 | `](../dev/…`、`](../archive/…`、`archive/pre-v1`、`dev/phase-06` |
| BRICKKIT 无相对链接 | 5.2 第三行 | `BRICKKIT*.md` 里 `](` 后面不是 `http(s)://` 的链接（含引用式） |
| 没有占位符 | 6.2 `DOC_PLACEHOLDER` | 全部组件 `*.md`：`\bTODO\b`、`\bTBD\b`、`待填` |

不替代 `make docs-check ID=<id>`（`brickkit lint --strict`）与 `make docs-boundary`：那两个仍是 5.2 / 6.2 的最终判据；本脚本覆盖 lint 不查的部分（`go.mod` 等非文档文件里的历史、4.5 / 4.9），并且不用加入项目就能跑。

## go-v2.sh

```bash
bash $ROOT/dev/phase-06/tools/go-v2.sh <id> --sdk v0.4.0; echo "exit=$?"
# 契约改动并 buf generate 之后：
bash $ROOT/dev/phase-06/tools/go-v2.sh <id> --recheck; echo "exit=$?"
```

步骤（做过的跳过）：
1. **4.0 判形态**：`gen/<domain>/<name>/go.mod` 在 → 形态 A（或已拆过的 B）；不在 → 形态 B。`gen/` 下必须恰好一个契约包目录，否则失败。
2. **4.1 形态 B 拆嵌套模块**：`go mod init …/gen/<d>/<n>`、与根模块同版本的 grpc / protobuf、同一个 `go` 版本、`tidy`、`build`；根 `go.mod` 加 `require … v1.0.0` + `replace => ./gen/<d>/<n>`。Dockerfile 里 `COPY go.mod go.sum ./` → `RUN go mod download` → `COPY . .` 的写法改成 `COPY . .` → `RUN go mod download`。
3. **C-1 残留**：根 `go.mod` require 了自己的旧路径（`github.com/brickKit/<repo> v1.x.y`）→ 打印 `⚠️ 发现 C-1 残留` 并 `go mod edit -droprequire`。
4. **4.2**：`go mod edit -module …/v2`；把所有 `.go`（`gen/` 除外）里的 `"github.com/brickKit/<repo>/…"` 改成 `…/v2/…`，契约包 `…/<repo>/gen/…` 不改；非 Go 文件里还提到旧模块路径的（Makefile 的 import-scan 白名单等）只用 `ℹ️` 列出，按 4.7 人工改。
5. **4.3 契约包版本**：没有 `gen/<d>/<n>/v*` tag → `v1.0.0`（P3：形态 B 第一个 tag 一律 `v1.0.0`，即使同一轮契约有新增）；本地 `gen/<d>/<n>` 与最新 tag 一致（`git diff --quiet <tag> -- <dir>` 且无未跟踪文件）→ 那个版本；不一致 → 下一个 minor（`v1.0.6` → `v1.1.0`）。写进根 `go.mod` 的 require，replace 保持。
6. **4.4**：`go get be-sdk-go@<tag>`。
7. **4.6（be-sdk-go ≥ v0.4.0 才做；v0.4.0 删了 `Module.Migrations`，不做这步 `go build` 必然报 `unknown field Migrations`）**，由 `migrate-entry.py --apply` 完成：
   - 找含 `//go:embed *.sql` 的迁移嵌入包（13 个组件都是 `migrations/embed.go`，`package migrations`、`var FS embed.FS`）；没有就新建 `migrations/embed.go`（`migrations/` 下没有 `.sql` 就失败）。
   - `backend/cmd/migrate/main.go` 整份写成 `package main` + `import ("github.com/brickKit/be-sdk-go/migrate"; "<模块>/v2/migrations")` + `func main() { migrate.Main(migrations.FS) }`（gofmt 后的确切文本）。目录里还有别的非测试 `.go` 文件就失败。
   - `backend/module/module.go`：删 `besdk.Module{…}` 里单行的 `Migrations: x,`（连同紧挨在它上面、中间没有空行的注释行）；值是 `pkg.FS` 且包名不再用到 → 删那条 import；值是变量且只剩声明 → 删声明；然后 gofmt。`role := schema + "_rw"` 不动（外壳里 `SET LOCAL ROLE` 还要用）。`Migrations:` 不是单行写法就失败，不猜。
   - 嵌入包文件原来的注释（"给 Module.Migrations 用""迁移容器读磁盘"）不改，只用 `ℹ️` 提醒 C4 审查时改。
   - Dockerfile 不用改：`go build -o /out/migrate ./backend/cmd/migrate` + `COPY --from=build /out/migrate /app/migrate` 照旧，`.sql` 已嵌进二进制（`COPY migrations /app/migrations` 留着无害）。实测（mdm/customer 克隆，v0.4.0）：`docker build` 通过；镜像里 `./migrate` 无参数 → `用法：migrate up|down（收到 []）`、exit 2；`./migrate up` 不给 `PG_*` → `缺少数据库连接配置：PG_HOST, …`、exit 1。
8. `go mod tidy`（`lib/pq`、旧入口的 `source/file` 随之消失；golang-migrate 只剩 SDK 带进来的 indirect）、`go build ./...`、`go vet ./...`。

**判据**（每条 `PASS`/`FAIL`，任一 FAIL 就 exit 1）：BUILD_OK；`go.mod` 第一行 `module …/v2`；`go.mod` 不 require 自己的旧路径；契约包是嵌套模块且模块路径不带 `/v2`；根 `go.mod` require 的契约包版本 = 4.3 算出的版本（不是 `v0.0.0`）且有本地 replace；根 `go.mod` 里**除契约包外没有别的 replace**（例如为了先用上未发布的 SDK 指到本机 `tools/be-sdk-go`：本机全绿，`brickkit build` 时路径不在构建上下文里才失败）；`go list -m all` 里本仓库模块**恰好**两行（`…/v2` 与 `…/gen/<d>/<n> vX => ./gen/<d>/<n>`）；`go list -deps -test` 里本仓库模块只有这两个；import 全部带 `/v2`（契约包除外；没有不带子路径的裸导入 `"github.com/brickKit/<repo>"`，也没有 `…/v2/gen/…`；`//go:build ignore` 的文件也查）；Dockerfile 先 `COPY . .` 再 `go mod download`；Dockerfile 编译 `./backend/cmd/migrate` 并把二进制 `COPY --from` 进最终镜像；SDK ≥ v0.4.0 时 `cmd/migrate/main.go` 恰好是那一行入口、非 gen 代码里没有 `Migrations:` 字段（`--recheck` 按 `go.mod` 里的 SDK 版本判断要不要查这条）；给了 `--sdk` 时 be-sdk-go 版本一致。**gen/ 是当前 `.proto` 的生成结果**（task-7 审查 Minor 8；完整运行与 `--recheck` 都判）：`buf generate --template buf.gen.yaml -o <$S 下的临时目录>`，把生成的 `gen/**/*.pb.go` 与组件的 `gen/` 逐个比——只在 `gen/` 里有（删掉的 `.proto` 留下的、手工加的）、只在生成结果里有（忘了生成）、内容不同（改了 `.proto` 没重新生成、手改了生成物）都 FAIL 并点名文件；不写 `gen/`。本项目 11 个 Go 组件的 `buf.gen.yaml` 都只用本机插件（`local: protoc-gen-go` / `protoc-gen-go-grpc`，在 `~/go/bin`）、`buf.yaml` 没有 `deps`，所以离线可跑；`buf` / `buf.gen.yaml` 缺失也是 FAIL，不跳过。实测（T8，组件当前检出）：10 个一致，**`infra/workflow` 的 `gen/infra/workflow/v1/workflow_grpc.pb.go` 与 `.proto` 不一致**（`ListTasks` 的注释改过、没重新生成）——它的 Task 跑 `go-v2.sh` 会在这条 FAIL，先 `buf generate`（只是注释，按 4.0 升 patch）。
最后打印 `📌 第 8.3 步需要打的契约包 tag：gen/<d>/<n>/vX`，或"不需要"。

`--recheck` 只做 4.3 + tidy/build/vet + 判据：不拆模块、不改 import、不升 SDK、**不清 C-1 残留**（让判据报出来）。`--sdk` 可选（给了就核对版本）。契约改动的顺序：改 `.proto` → `buf generate` → `--recheck`（gen 判据 PASS、4.3 升到下一个 minor）；只改 `.proto` 就 `--recheck` 会在 gen 判据 FAIL。

**C-1 是什么、为什么判据抓得住**：形态 B（`gen/` 属于根模块）被当成形态 A 改 `/v2` 时，`go build` 先报 `no required module provides package …/gen/…`，`go mod tidy` 接着自己"修好"——`found … in github.com/brickKit/<repo> v1.x.y`，往 `go.mod` 加回自己上一个已发布版本，之后 `go build` 是绿的，v2 组件静默对着 v1 的生成代码编译。`tests/run.sh` 在 infra/notification 的克隆上照这个错误做法真做一遍（确认 `go build` 绿、`go.mod` 多出 `infra-notification v1.0.4`），然后 `--recheck` 必须 exit 1，且"require 旧路径""go list -m all""go list -deps""嵌套模块"四条判据都是 FAIL；再跑完整的 `go-v2.sh --sdk` 必须报出 C-1、删掉旧 require、拆出嵌套模块并全部 PASS。

**已知限制**：
- `gen/` 有变化一律升 **minor**（`v1.0.6` → `v1.1.0`）：脚本分不清"契约新增"和"只是重新生成"（component-loop 4.0 说后者升 patch），只是重新生成时会多升一档，要 patch 就手工 `go mod edit -require=…@v1.0.7` 后再 `--recheck`。
- `--sdk <tag>` 的 tag 还不存在时，在 4.4 的 `go get` 处 exit 2；此时 4.1–4.3（拆模块、`/v2`、import、契约包版本）**已经做完**，tag 出来后原样重跑即可（幂等）。tag 刚推送的一段时间里 proxy.golang.org / sum.golang.org 还会返回之前缓存的"查不到"（实测 v0.4.0 推送后十几分钟仍是 `404 … unknown revision`）：脚本会提示，确认远端有 tag 后临时 `GONOSUMDB=github.com/brickKit` 重跑（回落到 git 直取，go.sum 照常记录）。
- v0.4.0 还改了 `UserClient` / `SystemClient` 的签名：用到它们的组件（crm/opportunity、erp/sales、infra/iam-casdoor）第一次跑 `--sdk v0.4.0` 只有 BUILD 一条 FAIL（`not enough arguments in call to besdk.UserClient`），按 4.5 改完代码后重跑。其余 8 个 Go 组件实测直接全部 PASS。
- 只认 `gen/` 下一个契约包目录；Dockerfile 只改上面那一种写法（别的写法由判据报 FAIL，人工改）；minor 版本号只看本仓库已有的 `gen/*` tag（远端有而本地没 fetch 的 tag 不知道——跑之前 `git fetch --tags`）；需要访问 Go 模块代理（`go get` SDK）。

## tests/run.sh

```bash
BE_SCRATCH=<会话 scratchpad> bash dev/phase-06/tools/tests/run.sh      # 约 2 分钟；TEST_SDK（默认 v0.3.2，旧 API 路径）、TEST_SDK4（默认 v0.4.0，§4.6 路径）可换版本
```

在 `$BE_SCRATCH/06b-tools-test/` 里用 `git clone --no-hardlinks`（scratch 可能与仓库不在同一文件系统，`--local` 的硬链接会失败）克隆 13 个组件（带 tag），只在克隆上写，不碰 `components/` 下的子模块。"迁移前"的夹具克隆后**退回最后一个 1.x tag**（`clone`），所以组件迁移进度（HEAD 已是 2.0.0，例如 mdm/customer）不会让这些测试漂移；`component-check.sh` 的"迁移后"夹具停在子模块当前 HEAD（`clone_head`）。测试 shell 把 `~/go/bin` 追加进 PATH（buf generate 夹具要用）。覆盖：

- `env.sh`：没设 `BE_SCRATCH` / 非法 ID 报错；十个变量的取值；`BE_COMP_DIR`；不连库组件的空 `SCHEMA`。T8：PATH 行是追加且 eval 两次不重复、eval 后 `brickkit` 仍解析到 `~/.local/bin`、buf 可用；stdout + stderr 里没有口令的值（只在子 shell 里比对）；`TEST_PG_DSN` 指向 `brickkit_test_db` 且口令长度对；`~/go/bin` 放在前面（真 v0.4.6）、假 brickkit 报 v0.4.6、没有 buf、`.env` 没有 `POSTGRES_PASSWORD`、没有 `.env` 都 exit 2 并说明，且失败时 stdout 为空。
- `migrate-manifest.py` × 13：预览不写盘；旧清单 `--check` exit 1；`--write` 后 `--check` exit 0；重复 `--write` 无改动；13 个组件的依赖 / required / 默认值 / secret 与 §2.2 表逐项相等；customer / notification / print（Python）/ im-dingtalk 的代码改写；assembly.yaml 只删不加；`--check` 抓住驼峰键读取、未声明键读取、驼峰 schema 键、未标 secret、未进 required、版本注释。
- `docs-skel.sh`（mdm/customer）：九个文件、留底、小节数、固定中文标题、互链、BRICKKIT 无相对链接、幂等、不覆盖已填写的文件、`--force`、组件目录 `brickkit lint` 只剩两类预期警告。
- `go-v2.sh`：形态 A（mdm/customer，`v1.0.6`）、形态 B（infra/notification，拆出 `v1.0.0`、Dockerfile）、两者提交后重复运行 `git status --short` 为空、`--recheck` 在契约有变化时升到 `v1.1.0` 并报出要打的 tag、C-1 复现与捕获、Python 组件被拒绝。
- §4.6：真 v0.4.0 下的 mdm/customer（形态 A，已有嵌入包）与 im-dingtalk（形态 B，删掉嵌入包、由脚本新建）：exit 0、`main.go` 逐字等于一行入口、没有 `Migrations` 字段与 migrations import、`role` 保留、gofmt、`lib/pq` 消失、`go build ./... && go vet ./...`、两条判据 PASS、提交后重跑无改动；`main.go` 多一行或 Dockerfile 不拷 migrate 二进制 → `--recheck` FAIL；v0.3.2 的组件不做 §4.6。
- T8 `migrate-manifest.py`：13 个组件预览不写发布说明、`--write` 写出三节骨架、不出现"不再有默认值"、`assembly.yaml` 没有 `HIST_RE` 命中；customer 的四条旧键 → 新键、`改为必填（1.x 可以不配）`、角色 / NATS / `/v2` / `DATABASE_*`、新增 / 修复两节为空；authz 的 `PERMISSION_CATALOG`、inventory 的 `LOW_STOCK_THRESHOLD`、Python 组件不提 `/v2`；已存在不覆盖；没设 `BE_SCRATCH` exit 2；注释清理在真实组件上（opportunity 括号出处、iam-casdoor 续行、bff-mobile 整条行尾注释与跨行括号、finance 整块）与单元测试（块标量、引号里的 `#`、续行、确定性）；"只删不加"放宽为"加的行只能是 role 行或去掉注释后与某条删掉的行相同"。
- T8 `component-check.sh`：迁移后的 mdm/customer（当前 HEAD）十项全部 PASS 且不改工作区；试点漏掉的那个提交只在历史扫描 FAIL、点名 `go.mod` / `buf.yaml` / `LICENSE`；`history_allow` 放行（`ℹ️` + 理由）、缺 `why` exit 2、`migrate-manifest.py` 接受这个字段；迁移前的 mdm/product 在 4.5 / 历史 / 小节数 FAIL；Python 组件能跑；12 个逐项反例（驼峰读取、`DATABASE_`、`1-0-N`、未跟踪文件里的历史、文档里的 `Task 7`、小节数、首行、`../`、BRICKKIT 相对链接、`TODO`、`TBD`、`dev/phase-06`）各自 FAIL；代码块里的 `##` 不计。
- T8 `go-v2.sh`：改 `.proto` 并 `buf generate` 后 `--recheck` gen 判据 PASS、升 `v1.1.0`（原来的夹具是直接往 `*.pb.go` 追加一行，现在这本身就是 FAIL）；手改 `*.pb.go`、改了 `.proto` 没生成、`gen/` 里多一个 `*.pb.go` 都 FAIL 并点名；`--recheck` 不写 `gen/`；形态 A / B 与 §4.6 的完整运行里这条都 PASS。
- 修复轮：`--write` 遇到手改（assembly.yaml 追加一行、component.yaml 改版本）exit 3、两个文件都不写、diff 里列出会丢的行，`--force` 覆盖；overrides 的 `permissions_add` / `menus_add` / `edge_routes_add` 追加、只加不删、重复运行未改动、与 tag 版已有键重复时 exit 2、在 `*_add` 生成的文件上再手改也拒绝、改 overrides 后重跑照常；`--check` 对 assembly.yaml 的反向路径（残留 `shell`、缺 `data_scopes`）；`data.role` 只改 `data` 的直接子键（单元测试）；旧键名提示只看字符串与注释；docs-skel 换一个 `BE_SCRATCH`、清空 `$S` 之后重跑都不覆盖已填写的 `AGENTS.md` / `README.md`，留底取自 tag；go-v2 的多余 `replace` 与裸导入旧根包都 FAIL。
