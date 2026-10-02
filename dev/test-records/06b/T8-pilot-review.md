# 06b T8：试点审查与模板回灌

试点 mdm/customer 2.0.0 已发布（tag `2.0.0` + `v2.0.0` 在 `70eb317`，契约包仍 `gen/mdm/customer/v1.0.6`；父仓库 `42bc991`）。本文件记录试点审查的结论、控制者裁定（R38 起），以及回灌到清单和工具的改动。

## 审查

- 发布前审查与 T8 Step 1 合并成一次（opus）：对照 Review Focus 五条、component-loop §3，另外回答 T8 的三个问题。审查原文在控制者工作区（`.superpowers/sdd/plan-06b/task-7-review.md`，不入库），结论摘要如下。
- 第一轮结果：Spec ❌（组件里还有三处注释引用归档文档：`go.mod`、`buf.yaml`、`LICENSE`），另有组件 Makefile 的两条"静默成功"路径（`make test` 没设 DSN 时全部 SKIP 却显示 ok；`import-scan` / `module-check` 吞掉 `go list` 的失败）。三项都在发布前修掉（R19，避免刚发 2.0.0 就要 2.0.1），修复后重新构建、`make verify … FOCUS=1 FORCE_BUILD=1` 全部 PASS（带 token 一项 SKIP，待 T25）。
- 行为保持：repo.go 读写拆分逐函数对照，没有业务行为漂移；三处行为变化（非法游标 400、REST 读 `created_after/before`、新增 `q`）各有先红后绿的提交。
- `q`：游标编码 `rank|created_at|id` 与 `ORDER BY` 一致，翻页不重不漏；`lower()` 大小写不敏感；空 `q` 不过滤；用 `strpos` / `starts_with`，通配符按字面匹配。

### T8 的三个问题

1. **文档五件套 + design.md 值不值得照抄**：值得。BRICKKIT 的"失败关闭时各回什么状态码"一段对每个连 authz / iam 的组件都成立；AGENTS 两张代码地图粒度合适；design.md 十节齐全。照抄时注意：事实要能在代码里找到；AGENTS 与 design 不要重复；不写历史（包括 `go.mod` / `buf.yaml` / `LICENSE` 里的注释）。
2. **脚本的静默成功路径**：组件 Makefile 两处（已修，进模板）；所有入口都不核对 brickkit 版本（本机 `~/go/bin/brickkit` 是 v0.4.6，`ship.sh` 的 `brickkit release` 会跑旧 CLI）；`go-v2.sh --recheck` 不查 gen 是否最新；verify 的 KEEP / local off 失败路径不恢复 `deploy.local.yaml`（已修）；`config-fill.py` 把 `$var:X`（X 为空）当成已填。
3. **应该进脚本的人工步骤**：工具环境（PATH、版本、测试库 DSN）；种子数据（`make verify SEED=1`）；文档核对（`##` 计数、互链、越界链接）；4.5 / 4.9 的 grep；发布说明骨架；历史 / 归档引用扫描；OpenAPI 只增不改；db-init 输出进日志；V-01 的配置键命名门禁。

## 裁定

| # | 内容 |
|---|---|
| R38 | 预设 P1–P12 全部维持。试点没有推翻任何一条 |
| R39 | `make verify FOCUS=1` 把 `config/vars.yaml` 里含 `host.docker.internal` 的值换成 Docker host-gateway 的实际 IP，写进 `deploy.local.yaml` 的 `vars:`（本机进程与依赖容器都可达）；`deploy.local.yaml` 在所有退出路径上恢复。只对 Linux 原生 Docker 成立。是否是 brickKit 的问题记为 V-12，T18（第一个有容器依赖的 focus）再验 |
| R40 | `q` 不加索引：包含匹配本来就要扫描时间窗口内的行，前缀索引用不上；表是主数据量级，将来变大用 `pg_trgm`（写进 design.md） |
| R41 | `.proto` 里的旧注释不在本轮清理：改 `.proto` 注释会改 `gen/`、逼出一个没有实质变化的契约包 tag。留到下一次真实契约变更时一起改。历史引用扫描排除 `*.proto` |
| R42 | 旧键 → 新键对照写在发布说明（"升级前必须做（破坏性变更）"），不写进 BRICKKIT.md（文档不写历史）。component-loop 8.1 的模板随之改正 |
| R43 | mdm/customer 的组件 Makefile（发布前修复后的版本）是 Go 组件的模板：只有顶部 `ID` / `REPO` 是组件特有的；`contract-check` 对比上一个发布 tag（不是 `branch=main`）；`test` 没设 `TEST_PG_DSN` 时失败；扫描类目标先取 `go list` 输出、查退出码再过滤 |
| R44 | PATH 一律追加（`export PATH=$PATH:$HOME/go/bin`），并在 `env.sh`、`integrate.sh`、`verify-component.sh`、`ship.sh` 入口断言 `BrickKit CLI v1.1.0`。`~/go/bin/brickkit`（v0.4.6）是否删除由用户决定 |
| R45 | be-acceptance 新增两个常设门禁：`config-key-scan`（`configSchema` 键名必须大写下划线、不以 `_ENDPOINT` 结尾、不撞保留名；V-01 的结论）与 `openapi-additive-scan`（REST 契约对比上一个发布 tag 只增不改） |
| R46 | `q` 沿用列表的默认 90 天时间窗口（02-backend.md 的通用规则），不为搜索单独取消；06c 前端觉得别扭再议（写进 design.md 的未决问题） |
| R47 | 试点里人工做、而 12 个组件都要重复的步骤，全部进脚本（见下面的回灌）。之后的组件 Task 只在脚本不覆盖的地方用人工判断 |

## 回灌

| 线 | 范围 | 内容 |
|---|---|---|
| A | `dev/phase-06/tools/` | `env.sh` 追加 PATH、断言 brickkit / buf、提供测试库变量（不打印值）；新增 `component-check.sh`（旧键 grep、种子脚本 grep、历史引用扫描、文档对称检查）；`migrate-manifest.py --write` 写发布说明骨架、顺手清理 `assembly.yaml` 里引用归档文档的注释；`go-v2.sh --recheck` 查 gen 是否最新 |
| B1 | `tools/be-acceptance`、父仓库 `Makefile` 的 `gates` | R45 的两个门禁 → be-acceptance v0.4.6 |
| B2 | `infra/scripts/` | 入口版本断言（R44）；`make verify SEED=1`；integrate 的 db-init 输出进日志；`config-fill.py` 把空的 `$var:X` 报为缺值 |
| C | `dev/phase-06/component-loop.md` | 按 A / B1 / B2 的真实命令改写；修正审查指出的三处不符（7.10 / 附录 B 关于 `host.docker.internal` 的说法、8.1 模板、Step 6 的 `deploy.verify.yaml`）；1.4 的 PATH；R41–R43 写进对应小节 |

试点时已经顺带完成的工具改动：be-acceptance v0.4.5（import-scan 放行 SDK 子包）；`verify-component.sh` 的 FOCUS 修复（R39，随父仓库 `42bc991` 提交）。

## V 项

V-01、V-07、V-09 已验，结论写在 `dev/phase-06/to-verify.md`；V-06 组件半程已验；新增 V-12（focus 的 vars 共用问题）、V-13（`brickkit add` 重排注释）。

## mdm/customer 是否要补发 2.0.1

不需要。没有裁定推翻预设；审查发现的组件问题都在发布前修掉了。
