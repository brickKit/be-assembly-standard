[English](../../../en/02-decisions/01-architecture/0109-language-neutral-component-protocol.md) · [中文](0109-language-neutral-component-protocol.md)

# 0109 规则写在语言中立的组件协议里，由黑盒套件检查

**状态**：已决定，随 3.0.0 统一升级落地（be-protocol v1.0.0、SDK v0.6.0）。

## 决策

一个组件要成为本项目合格成员必须做到的一切，在线上协议、表结构和配置键这一层只写一次，称为**组件协议**：配置、进程生命周期与健康检查、token 验证与权限、数据范围、系统面与用户面、错误模型、截止时间、库身份与事务、迁移、带 outbox 和游标的事件、幂等、后台任务、对象存储、遥测字段，以及外壳成员的义务。

| 部分 | 放在哪 | 里面有什么 |
|---|---|---|
| 协议 | 独立仓库 `brickKit/be-protocol`，从 v1.0.0 起单独版本化 | 规范正文（英文为准、中文镜像）、JSON Schema、平台表参考 DDL、语义向量、夹具组件的契约；没有代码 |
| 黑盒套件 | `tools/be-acceptance/conformance/component/` | 对运行中的容器跑的用例，不看语言；自带假 IdP、假 authz、假对端，用真 PostgreSQL 和真总线 |
| 官方 SDK | `be-sdk-go`、`be-sdk-python`、`be-sdk-ts` | 协议的参考实现，三门语言用同一套名词；每门都自带夹具组件 `widget`，并对它跑套件 |

- 每条规则分三级：**MUST**（套件测）、**SHOULD**（套件只警告）、**INTERNAL**（外面看不见，比如"事务里不发网络调用"；官方 SDK 用自己的测试守住，其他语言的组件在 `AGENTS.md` 里写明怎么守住，评审时核对）。
- **组件发版需要一次全绿的套件运行。** 组件在 `component.yaml` 里声明 `release: {checks: [[make, conformance]]}`，`brickkit release`（brickKit v1.4.0 或更新版本）就会对发布提交跑套件，失败则拒绝打 tag（`RELEASE_CHECK_FAILED`）。项目不自己发布的组件（别家厂商的、去掉了这项检查的 fork），由 `make gates`（`compconf-record-scan`）要求项目里保存一份对应精确版本和镜像摘要的全绿报告。
- **SDK 里不许有规范没写的行为。** 改动顺序固定：先改规范和 schema，再补向量，再加一条先对坏夹具跑出红的套件用例，再改三门 SDK，最后打 tag。
- **协议的 minor 版本只增加可选的面**；会让已经符合的组件变得不符合的改动是 major。
- 协议之下的基础设施端口（数据库、总线、Jobs、缓存、密钥、遥测等）各有自己的套件，放在 `tools/be-acceptance/conformance/<端口>/`。

## 理由

组件可以用任何语言写（[0105](0105-any-language-one-protocol.md)），所以住在某一个 SDK 里的规则当不了规则。对运行中的容器做测试，是唯一一种对 Go、Python、TypeScript 和还没人选过的语言一视同仁的检查。三门 SDK 用同一个夹具过同一套套件，它们的等价就有了证据，而不只是意图；规范和向量共用一个版本号，SDK 也就不可能跑到写下来的东西前面去。

## 挡下什么

- 只存在于某个 SDK 代码或文档里的规则；规范没有描述的 SDK 功能
- 组件的当前版本没有全绿的套件运行就发版：把 `--skip-checks` 当成常规用法，或者钉住别家厂商的组件却没有对应其版本和镜像的全绿报告
- 协议规则的按语言变体（某个 SDK 里头名、表结构或错误 reason 不一样）
- 手工把向量或 schema 拷进 SDK，而不是从 `be-protocol` 的 tag 同步
- 先写实现、后写套件用例，而且那条用例从没见过红

## 何时重新讨论

要紧的规则从外面观察不到，于是太多地方只能停留在 INTERNAL、评审已无法可靠核对时；或者维持三门 SDK 等价的成本，超过了自由选语言给项目带来的好处时。

完整分析：[02-languages-and-component-protocol.md，选择](../../04-foundations/02-languages-and-component-protocol.md#选择)；端口的判据见 [01-ports-and-adapters.md，选择](../../04-foundations/01-ports-and-adapters.md#选择)。
