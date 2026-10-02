# 06b 一次性迁移工具包

> 开发文件（`dev/`），只服务于"1.x → 2.0.0 这一次迁移"，阶段结束随 `dev/` 归档；正式文档不得链接本目录。
> 规则的出处是 `dev/phase-06/component-loop.md`（键名对照表 §2.1、目标形态 §2.2、推导规则 §2.3、样板 §3.1、机器核对 3.2、Go 形态与 `/v2` 4.0–4.4）。脚本与清单不一致时以清单为准，并改脚本。

四个脚本都：可以重复运行（做过的步骤跳过，第二次运行不产生任何改动）；逐项打印改了什么；出错时大声失败（非零退出码 + `❌` 开头的一行原因），不猜。

| 脚本 | 闭环步骤 | 一句话 |
|---|---|---|
| `env.sh` | §0.1 | 打印组件的全部变量（`export` 行），建好 `$S` |
| `docs-skel.sh` | 第 2 步 / C2 | `brickkit new` 骨架 → 八份文档骨架 + `CLAUDE.md`，旧文件留底 |
| `migrate-manifest.py` | 第 3 步 / C3 | 从最后一个 1.x tag 重写 `component.yaml`、删改 `assembly.yaml`、改代码里的旧键读法；`--check` 跑 3.2 |
| `manifest-overrides.yaml` | 第 3 步 | 每个组件的人工输入（英文名称与描述、R27、P11、新键、`local`） |
| `go-v2.sh` | 4.0–4.4 / C4 | 契约包统一成嵌套模块、`/v2`、契约包真实版本、升 SDK，最后跑 4.4 判据 |
| `tests/run.sh` | — | 在 scratch 克隆上跑全部脚本并断言（含 C-1） |

组件目录默认 `$ROOT/components/<id>`；环境变量 `BE_COMP_DIR` 可以改（测试用它指向 scratch 里的克隆）。`BE_SCRATCH` 必填（当前会话的 scratchpad 目录），`$S=$BE_SCRATCH/06b/<repo>`。

## env.sh

```bash
export BE_SCRATCH=<会话 scratchpad>
eval "$(bash $ROOT/dev/phase-06/tools/env.sh mdm/customer)"
```

- 输出 `ROOT ID REPO UREPO C S SCHEMA ROLE SVC NET` 十个 `export` 行（取值规则同 component-loop §0.1），并 `mkdir -p $S`。`SCHEMA`/`ROLE` 取自 `registry/schemas.tsv`，不连库的组件为空。
- 失败（没设 `BE_SCRATCH`、ID 不是 `<scope>/<name>`、组件目录里没有 `component.yaml`）只写 stderr、退出码 2，`eval "$(…)"` 不会吃进半截输出。
- `ROOT` 由脚本位置推出，不读环境变量。

## docs-skel.sh

```bash
bash $ROOT/dev/phase-06/tools/docs-skel.sh <id> [--force]
git -C $C rm -q docs/手册.md; (cd $C && brickkit skills update)     # 脚本不做这两步
```

- `rm -rf $S/skel && brickkit new <id> --path $S/skel`，核对骨架五个文件都在、`CLAUDE.md` 是 `@AGENTS.md`、`AGENTS.md` 有维护块（brickKit 行为变了就失败）。
- 留底到 `$S/old/`：`AGENTS.md README.md CLAUDE.md docs/手册.md component.yaml assembly.yaml Makefile Dockerfile`。**只留第一次的**：`$S/old/` 里已有同名文件就不覆盖，所以第二次运行不会把骨架当成"旧文件"。
- 写出：`BRICKKIT.md`（骨架原样）；`AGENTS.md`、`README.md`（骨架 + 首行 `[English](X.md) · [中文](X.zh.md)`；README 的 `brickkit add <id>@0.1.0` 改成 `@2.0.0`）；三个 `.zh.md`（固定中文标题，`BRICKKIT.zh.md` 末节"不是外壳。"）；`docs/design.md` + `.zh.md`（component-loop 5.1 的十个小节：边界、拥有的数据、契约面、事件、依赖、同步调用图里的位置、分区与归档、数据范围、参考实现、未决问题）；`CLAUDE.md` 恰好 `@AGENTS.md`。
- `BRICKKIT*.md` 不写互链行（brickKit 文档规范：`BRICKKIT*.md` 不许有任何相对链接）；其余三对文件首行互链（规范要求每个语言版本都链到其它版本）。
- 覆盖规则：目标不存在、与将写出的内容相同、或与留底的旧文件相同（还没人动过）→ 写；否则（已填写过）跳过并提示 `--force`。`CLAUDE.md` 总是写成 `@AGENTS.md`。
- 判据（测试里也是这些）：九个文件都在；每对文件 `##` 小节数相等（`AGENTS.md` 维护块里的不算）；在组件目录跑 `brickkit lint`：`✅ component.yaml`、0 个错误，警告**只有**占位符（`DOC_PLACEHOLDER`）与"文档还没提到某个 required 键 / 契约文件"（`DOC_OUT_OF_STEP`）两类——正是 C5 要填的。
- 已知限制：中文正文写的是 `<!-- TODO: 待填 -->` 而不是光秃秃的"待填"，好让 lint 把没填的中文小节也报出来；`brickkit skills update` 之后 `AGENTS.md` 与骨架不同了，再跑本脚本会跳过它（这是保护，不是 bug）。

## migrate-manifest.py

```bash
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id>            # 预览：两份文件全文 + diff + 代码改动，不写盘
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id> --write    # 写盘
python3 $ROOT/dev/phase-06/tools/migrate-manifest.py <id> --check; echo "exit=$?"
```

**输入**：组件最后一个 1.x tag 上的 `component.yaml` / `assembly.yaml`（`git show <tag>:…`，与工作区无关，所以重复运行结果相同）+ `manifest-overrides.yaml` 的该组件条目。tag 按 `1.*` 与 `v1.*` 两种找，取版本号最大的（06a 之前的组件 tag 全部带 `v`，如 `v1.0.10`）。

**`component.yaml`（整份重写，§3.1 版式）**：
- 删除全部注释、`deployment.image`、`dependencies.resources`；补 `metadata.repository`（`https://github.com/brickKit/<repo>`）、`deployment.build`、`local`；`metadata.name`/`description` 取 overrides（英文，含中文字符就失败）；`version: 2.0.0`。
- 依赖全部改 `@2.0.0`（optional 保留），加 `deps_add`；ID 重复就失败。
- `configSchema`：旧 `resources` 有 `database` → `PG_HOST`、`PG_PORT`（`"5432"`）、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`（默认值 = 旧 `pgSchema` 默认值，必须等于 `registry/schemas.tsv`，否则失败）；有 `mq` → `NATS_URL`。共享键按固定名，其余驼峰键转大写下划线。`AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL`（P1）、`drop_default` 里的键（R27）、旧 required 键一律去掉 `default`；键名含 `PASSWORD`/`SECRET`/`SIGNING_KEY` 的标 `secret: true`；属性里的 `description` 删掉（§2.3.4）；整数默认值保持数字。没有 `default` 的键全部进 `required`（按属性顺序）。
- `deployment` 其余字段（端口、`extraPorts`、`labels`、`resources`）原样搬；`migration` 原样（或 `migration_command`）；`healthCheck` 原样，`start_period_seconds` 覆盖 `startPeriodSeconds`。
- 写盘前自检：生成文本解析回来必须等于推导结果；再跑一遍 3.2 检查，不过就不写、exit 1。

**`assembly.yaml`（文本级编辑，不经 YAML 往返）**：删 `version:`、`shell:`、`asset:`（连同块内容）；`data.role` 行的注释换成 `` # 登录角色，`PG_USER` 的值 ``（对齐保留）；其余（含注释）逐字保留。写盘前核对：解析结果 = 旧文件去掉那三个键。

**代码**：把 SDK Config 读法里的旧键改成新键，逐处打印 `文件:行: "旧" → "新"`。认的写法：Go `.String|StringOr|MustString|Int|IntOr|Bool|BoolOr("<旧键>"`，Python `.string|string_or|must_string|int|int_or|bool|bool_or("<旧键>"`（单双引号），TS/JS `.string|stringOr|mustString|int|intOr|bool|boolOr("<旧键>"`；跳过 `gen/ node_modules/ dist/ .venv/ build/ vendor/`。代码里**不是读取**的旧键名（报错文案、注释，例如 im-dingtalk 的 `panic("必填配置项 \"dingtalkAgentId\" …")`）只用 `ℹ️` 列出来，不改——要不要改由人判断（Review Focus 2）。

**`--check`**（当前工作区，任一项不是"无"就 exit 1）：驼峰/非法键；保留名（`*_ENDPOINT`、`COMPONENT_ID`、`COMPONENT_VERSION`、`PORT`、`BRICKKIT_SERVED_MEMBERS*`）；无默认值却不在 required；required 却有默认值；required 里有未声明的键；密码/密钥未标 secret；残留字段（`dependencies.resources`、`deployment.image`）；依赖不是 `@2.0.0`；版本注释（`#.*x.y.z`）；端口与 `registry/ports.tsv` 不一致；`PG_SCHEMA` 与 `registry/schemas.tsv` 不一致；metadata（版本 `2.x`、`repository`、英文名称与描述）；`deployment.build` / `local.runCommand` 数组；`assembly.yaml`（无 `version`/`shell`/`asset`、`id` 一致、有 `data_scopes`、`data.role` = registry 的 role）；**代码里还有驼峰键读取**；**非测试代码读取了 `configSchema` 没声明的键**（新键写进代码却忘了声明，brickKit 不会注入它）。

**已知限制**：
- `--write` 丢掉 `component.yaml` 里的全部注释（本来就要删；理由写进 `BRICKKIT.md` / `docs/design.md`）。`--write` 每次都按 tag 整份重写：在 C3 之后手改过 `component.yaml`（例如加新配置键）再跑 `--write` 会被覆盖——改动应该写进 `manifest-overrides.yaml`（`add_properties` 等）再重跑，或者之后不再跑 `--write`。
- `assembly.yaml` 里其它注释（含引用归档文档、写历史的那些）原样保留，由 C5 / 审查按文档规则清理；新权限键（§1.2）由人追加。
- `labels` 原样搬（bff-mobile 的 `prometheus.io/port` 也保留）。
- 代码读取的识别只看方法名：别的对象上的同名方法（如 `flag.String("name", …)`）会被当成配置读取报出来；SDK 之外的读法（`os.Getenv`）不在范围内，由 4.5 的 grep 与 `make module-check` 管。
- 只处理 `database`/`mq` 两种旧 resource；出现别的种类（对象存储）直接失败，要人工声明 `S3_URL`。

## manifest-overrides.yaml

每个组件一段，字段：`name`、`description`（英文，必填）、`tags`、`add_properties`、`required_add`、`drop_default`、`deps_add`、`start_period_seconds`、`migration_command`、`local`（必填：`language` + 数组 `runCommand`）。写了别的字段脚本就失败。初稿按 component-loop §2.2 写全 13 个组件：

- `infra/authz` `drop_default: [PERMISSION_CATALOG]`、`infra/iam-casdoor` `drop_default: [ENABLED_COMPONENTS]`（R27）。
- `erp/inventory` `add_properties: LOW_STOCK_THRESHOLD {type: string, default: "10"}`（plan-06b T10）。
- `infra/bff-mobile` `deps_add` 两个 optional（P11）、`start_period_seconds: 90`。
- `infra/print` `start_period_seconds: 120`，`migration_command` 与 `local.runCommand` 写成 T16 的目标形态（包名 `infra_print`）。
- Python / TS 的 `local.runCommand` 是初稿，T16 / T20 在 `make verify FOCUS=1` 真机确定后改这里再重跑 `--write`。

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
6. **4.4**：`go get be-sdk-go@<tag>`、`go mod tidy`、`go build ./...`、`go vet ./...`。

**判据**（每条 `PASS`/`FAIL`，任一 FAIL 就 exit 1）：BUILD_OK；`go.mod` 第一行 `module …/v2`；`go.mod` 不 require 自己的旧路径；契约包是嵌套模块且模块路径不带 `/v2`；根 `go.mod` require 的契约包版本 = 4.3 算出的版本（不是 `v0.0.0`）且有本地 replace；`go list -m all` 里本仓库模块**恰好**两行（`…/v2` 与 `…/gen/<d>/<n> vX => ./gen/<d>/<n>`）；`go list -deps -test` 里本仓库模块只有这两个；import 全部带 `/v2`（契约包除外，且没有 `…/v2/gen/…`）；Dockerfile 先 `COPY . .` 再 `go mod download`；给了 `--sdk` 时 be-sdk-go 版本一致。最后打印 `📌 第 8.3 步需要打的契约包 tag：gen/<d>/<n>/vX`，或"不需要"。

`--recheck` 只做 4.3 + tidy/build/vet + 判据：不拆模块、不改 import、不升 SDK、**不清 C-1 残留**（让判据报出来）。`--sdk` 可选（给了就核对版本）。

**C-1 是什么、为什么判据抓得住**：形态 B（`gen/` 属于根模块）被当成形态 A 改 `/v2` 时，`go build` 先报 `no required module provides package …/gen/…`，`go mod tidy` 接着自己"修好"——`found … in github.com/brickKit/<repo> v1.x.y`，往 `go.mod` 加回自己上一个已发布版本，之后 `go build` 是绿的，v2 组件静默对着 v1 的生成代码编译。`tests/run.sh` 在 infra/notification 的克隆上照这个错误做法真做一遍（确认 `go build` 绿、`go.mod` 多出 `infra-notification v1.0.4`），然后 `--recheck` 必须 exit 1，且"require 旧路径""go list -m all""go list -deps""嵌套模块"四条判据都是 FAIL；再跑完整的 `go-v2.sh --sdk` 必须报出 C-1、删掉旧 require、拆出嵌套模块并全部 PASS。

**已知限制**：只认 `gen/` 下一个契约包目录；Dockerfile 只改上面那一种写法（别的写法由判据报 FAIL，人工改）；minor 版本号只看本仓库已有的 `gen/*` tag（远端有而本地没 fetch 的 tag 不知道——跑之前 `git fetch --tags`）；需要访问 Go 模块代理（`go get` SDK）。

## tests/run.sh

```bash
BE_SCRATCH=<会话 scratchpad> bash dev/phase-06/tools/tests/run.sh      # 约 40 秒；TEST_SDK=v0.4.0 换 SDK
```

在 `$BE_SCRATCH/06b-tools-test/` 里用 `git clone --no-hardlinks`（scratch 可能与仓库不在同一文件系统，`--local` 的硬链接会失败）克隆 13 个组件（带 tag），只在克隆上写，不碰 `components/` 下的子模块。覆盖：

- `env.sh`：没设 `BE_SCRATCH` / 非法 ID 报错；十个变量的取值；`BE_COMP_DIR`；不连库组件的空 `SCHEMA`。
- `migrate-manifest.py` × 13：预览不写盘；旧清单 `--check` exit 1；`--write` 后 `--check` exit 0；重复 `--write` 无改动；13 个组件的依赖 / required / 默认值 / secret 与 §2.2 表逐项相等；customer / notification / print（Python）/ im-dingtalk 的代码改写；assembly.yaml 只删不加；`--check` 抓住驼峰键读取、未声明键读取、驼峰 schema 键、未标 secret、未进 required、版本注释。
- `docs-skel.sh`（mdm/customer）：九个文件、留底、小节数、固定中文标题、互链、BRICKKIT 无相对链接、幂等、不覆盖已填写的文件、`--force`、组件目录 `brickkit lint` 只剩两类预期警告。
- `go-v2.sh`：形态 A（mdm/customer，`v1.0.6`）、形态 B（infra/notification，拆出 `v1.0.0`、Dockerfile）、两者提交后重复运行 `git status --short` 为空、`--recheck` 在契约有变化时升到 `v1.1.0` 并报出要打的 tag、C-1 复现与捕获、Python 组件被拒绝。
