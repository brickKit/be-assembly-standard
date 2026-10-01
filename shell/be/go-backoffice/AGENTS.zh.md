[English](AGENTS.md) · [中文](AGENTS.zh.md)

# be/go-backoffice

开发这个外壳的 AI 指南。它托管什么、怎么部署：`BRICKKIT.md`。成员、配置和端口：`component.yaml`。

## 代码地图

| 路径 | 负责 |
|---|---|
| `main.go` | 整个程序：`shell.Main("be-go-backoffice", shell.Registry{...})`，每个成员一项，把它的 ID 映射到它的 `module.New` |
| `go.mod` | be-sdk-go 的版本，以及每个成员的 Go 模块，版本与 `shell.members` 一致 |
| `go.sum` | `go.mod` 的校验和 |
| `Dockerfile` | 两阶段构建；运行阶段是带 `/bin/sh` 和 `wget` 的 alpine，`component.yaml` 放在二进制旁边 |
| `component.yaml` | 成员（`shell.members`）、外壳自己的配置键、端口 8116、健康检查 |
| `BRICKKIT.md` | 项目部署这个外壳需要知道的事 |

| 任务 | 从这里开始 | 然后 |
|---|---|---|
| 加一个成员 | `component.yaml` 的 `shell.members` | `main.go` Registry 里登记它的 `module.New`、`go.mod` 里加它的模块、`BRICKKIT.md` 的外壳声明 |
| 把成员升到新版本 | `shell.members` | `go.mod`，然后升 `metadata.version` 并重新构建 |
| 改外壳自己的配置 | `component.yaml` 的 `configSchema` | `BRICKKIT.md` 的配置指南一节 |

## 构建与测试

```bash
go build -o /dev/null ./...        # 编译外壳和每个已登记的成员
brickkit build be/go-backoffice           # 镜像，tag 为 metadata.version；外壳须已在 brickkit.yaml 里
brickkit lint --strict             # 清单和文档
```

成功的样子：`go build` 无输出；`brickkit build` 在镜像里记下编译进去的成员版本，`brickkit up` 会核对；容器变为 healthy，端口 8116 上 `GET /healthz` 返回 200。

外壳自己没有测试：启动器及其失败契约在 be-sdk-go 里测试，每个成员在它自己的仓库里测试。

## 设计决策

- 外壳是项目代码，不是单独的仓库：哪些组件共用一个进程是本项目的部署选择，所以它和 `brickkit.yaml`、部署文件一起改（项目决策 0022：外壳是项目代码）。
- 一个外壳就是一个镜像、一份成员清单：`shell.members` 写明编译进去的成员确切版本，`main.go` 里的 Registry恰好登记这些成员。
- 启动器逻辑全部在 SDK 里（`shell.Main`），这个目录只剩一份成员清单，长不出自己的逻辑。
- 外壳从不跑迁移：brickKit 在外壳启动前用每个成员自己的镜像执行该成员的迁移。

## 易错点

| 绝不 | 症状 | 原因 |
|---|---|---|
| 让 `shell.members` 为空，还指望清单能加载 | `brickkit lint` 和 `brickkit add` 拒绝它：`MANIFEST_INVALID`，"a shell must list at least one component compiled into it"；外壳加不进项目，也无法用 `brickkit build` 构建 | brickKit 要求至少编译进一个成员。一次部署一个成员都不托管仍然合法：这在部署文件里选择，此时 SDK 拿到的 `BRICKKIT_SERVED_MEMBERS_CONFIG` 是 `[]`，只提供 `/healthz` |
| 从 `Dockerfile` 里去掉 `COPY component.yaml`，或改掉工作目录 | 容器立即退出："读外壳自己的 component.yaml 失败" | `shell.Main` 从 `./component.yaml` 的 `deployment.port` 读自己的端口（8116） |

## 改代码之前

1. 加、删或升级成员时，`shell.members`、`main.go` 里的 Registry和 `go.mod` 一起改，`BRICKKIT.md` 的外壳声明也一起改。
2. 每个成员在 `registry/schemas.tsv` 里都有一行；`make db-init` 把它的角色授给 `shell_go_backoffice`，没有对应行的成员会被拒绝。
3. 成员清单或成员版本变了，外壳就要新的 `metadata.version` 并重新构建；`brickkit up` 会以 `IMAGE_STALE` 拦下过期镜像。
4. 这里的代码只登记成员：不写路由、处理函数、查询，也不写成员之间的调用。
5. 提交前跑 `brickkit lint --strict` 和构建与测试一节里的构建。

## BrickKit

这是一个 BrickKit 组件：平台只读 `component.yaml`。它依赖的规则：

- `configSchema` 的键就是代码读取的环境变量名。绝不用保留名：`COMPONENT_ID`、`COMPONENT_VERSION`、`PORT`、`BRICKKIT_SERVED_MEMBERS`、`BRICKKIT_SERVED_MEMBERS_CONFIG`，以及任何 `*_ENDPOINT`。
- 依赖是精确版本。依赖的地址以 `<ID>_ENDPOINT` 送达；缺席的可选依赖根本没有这个变量，读取时要有兜底。
- `/healthz` 只检查本进程，绝不检查依赖。迁移命令从同一镜像运行，遇到不认识的参数必须失败。
- `BRICKKIT.md` 会随组件到达每个使用它的项目，并在那里脱离仓库被阅读：与代码保持一致，不用相对链接。
- 发布：升 `metadata.version`，提交，推送，`brickkit release`。`brickkit lint` 检查清单和这些文档。
- 完整规则在 `brickkit-component` 技能里（安装了技能的项目或仓库根目录下的 `.claude/skills/brickkit-component/SKILL.md`；`brickkit skills update` 安装它）；参数问 `brickkit <command> --help`。
