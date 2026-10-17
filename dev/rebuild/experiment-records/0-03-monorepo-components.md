# 0-03 一个仓库放多个组件（探针）

> **2026-10-17 BrickKit v1.5.0 复测（FRR-003）**：安装源可以写成一个仓库（`repo:`），`brickkit add` 一条命令写好三层，同一仓库里的依赖也一起解析；第 1 节的“只能手写三层”已不成立。见第 9 节。

## 1. 结论

**通过，但 `brickkit add` 加不进子目录里的组件**。两个组件放在同一个仓库的子目录里，各自 `brickkit release` 得到带前缀的标签（`test-probe-go/0.1.0`、`test-probe-py/0.1.0`），Go 用的子目录模块标签（`probes/go/v0.1.0`）可以并存；使用方在 `brickkit.yaml` 的条目上写 `source.repo` 与 `source.path` 就能解析、生成部署文件，用户级缓存里这个仓库只克隆一次。

缺口：`brickkit add` 没有指定 `repo`、`path` 的参数；先手写 `brickkit.yaml` 的条目再 `add`，会因为 `deploy.yaml` 没有条目被拒（`DEPLOY_INCONSISTENT`）。所以这类组件只能**手写三层**（`brickkit.yaml` 的条目、`deploy.yaml` 的条目、需要时 `config/` 的骨架），违背“三层由 `add` 一起改”。已写功能请求 FRR-003。

## 2. 测了什么、为什么

计划第 0 步：“一个仓库放多个组件（探针）”。探针是验收用的测试组件，计划把 Go 与 Python 两个探针放在 `be-acceptance` 仓库的子目录里，不为它们各建仓库。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.4.1 |
| 组件 | `test/probe-go`（`probes/go/`，带一个 `go.mod`，模块路径 `github.com/brickKit/be-acceptance/probes/go`）、`test/probe-py`（`probes/py/`）；都是 `brickkit new --path` 的骨架 |
| 远端 | 本机裸仓库 `remotes/be-acceptance.git` |
| 使用方 | `brickkit init consumer`；用户级缓存在草稿目录 |

## 4. 怎样跑

1. 在同一个仓库的 `probes/go`、`probes/py` 生成两个组件，提交、推送。
2. 分别在两个子目录里 `brickkit release`；再手工打 Go 的模块标签 `probes/go/v0.1.0` 并推送。
3. 使用方在 `brickkit.yaml` 写两个条目（`version`、`source.type: git`、`source.repo`、`source.path`），在 `deploy.yaml` 写两个条目，`brickkit up --dry-run`。
4. 另一个新项目只手写 `brickkit.yaml` 的条目，然后 `brickkit add test/probe-go@0.1.0 --yes`，看 `add` 能不能补齐其余两层。

完整输出：`experiment-data/0-03/run1.txt`。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| 子目录里 `brickkit release` | `✅ Released test/probe-go@0.1.0: tag test-probe-go/0.1.0 pushed`；Python 探针同样 |
| 三个标签并存 | `test-probe-go/0.1.0`、`test-probe-py/0.1.0`、`probes/go/v0.1.0` |
| 使用方 `up --dry-run` | 两个组件都解析成功，各取到自己的 `component.yaml`，生成 `compose.yaml` |
| 用户级缓存 | 只有一个裸仓库 `be-acceptance.git` |
| 手写 `brickkit.yaml` 条目后 `add` | 被拒：`DEPLOY_INCONSISTENT … No entry for: test/probe-go`，`deploy.yaml` 没有被改 |

## 6. 观察与异常

- 子目录组件的 BrickKit 标签前缀是组件 ID（`test-probe-go/`），Go 的模块标签前缀是目录（`probes/go/`），两者不同，互不干扰；BrickKit 只认“前缀/精确版本”，Go 只认 `目录/vX.Y.Z`。
- 第一次手写 `brickkit.yaml` 后直接 `up`，也是 `DEPLOY_INCONSISTENT`：三层必须一起写。

## 7. 影响

- **探针放哪**：仍放在 `be-acceptance` 的子目录。它们只出现在实验的部署文件里，手写三层的代价可以接受；每个探针发布时同一提交打 BrickKit 与 Go 两个标签（与根目录组件的两个标签同一道理，只是前缀不同）。第 1 步列仓库动作时照此列。
- **给 BrickKit 的功能请求 FRR-003**：`brickkit add` 能指定 Git 仓库与子目录（例如 `--source-repo`、`--source-path`），或者先写好的带 `source` 的条目能由 `add` 补齐 `deploy.yaml` 与 `config/`。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-03/run1.txt`；复测：`run2.txt`

## 9. v1.5.0 复测（2026-10-17）

BrickKit 对 FRR-003 的回复：不给 `add` 加参数，而是让 git 安装源写 `repo`（一个仓库）代替 `baseUrl`；版本是标签 `<scope>-<name>/<版本>`，组件在哪个子目录由标签里 `metadata.id` 相同的那份 `component.yaml` 决定。理由是组件级 `source` 只管那一行，同一仓库里探针之间的依赖仍会解析失败。

用 CLI v1.5.0 重建同样的仓库（`probes/go`、`probes/py`），这次让 `test/probe-py` 依赖 `test/probe-go@0.1.0`，验证回复里的理由。使用方的 `brickkit.yaml`：

```yaml
sources:
  - name: acceptance
    type: git
    repo: file://<草稿>/remotes/be-acceptance.git
```

| 步 | 结果 |
| --- | --- |
| 两个子目录里 `brickkit release`，再打 Go 标签 `probes/go/v0.1.0` | 三个标签在同一提交上，与第一次相同 |
| 只 `add test/probe-py@0.1.0` | 一条命令加进两个组件（依赖 `test/probe-go` 一起解析），`brickkit.yaml` 与 `deploy.yaml` 都写好，条目里不需要 `source` |
| `lint --all` | 三层一致，0 个错误（4 条警告是项目 `AGENTS.md` 骨架里的 TODO） |
| `up --dry-run`、`deps` | 通过；启动顺序 probe-go → probe-py |
| 另一个项目直接 `add test/probe-go@0.1.0` | 通过 |
| 用户级缓存 | 仍只有一个裸仓库 `be-acceptance.git` |
| 标签存在但里面没有这个 ID（`test-probe-x/0.1.0`） | `MANIFEST_INVALID`，列出标签里所有组件及其 ID |
| 同一标签里同一 ID 出现两份（`probes/go`、`probes/go2`） | `MANIFEST_INVALID`，列出两处，不去猜 |

没有测回复里提到的 `add --repo`（整个仓库克隆进 `components/`）：探针只从标签取，用不到它。

**结论**：通过。**对计划的影响**：探针仍放在 `be-acceptance` 的子目录，实验项目的 `brickkit.yaml` 加一个写 `repo` 的安装源，探针用 `brickkit add` 加入，不再手写三层；第 7 节“手写三层的代价可以接受”作废。每个探针发布时同一提交打 BrickKit 与 Go 两个标签，这一点不变。
