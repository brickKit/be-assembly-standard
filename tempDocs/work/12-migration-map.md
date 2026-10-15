# 承接表（协议 21 第 1 步）

> 2026-10-15。逐行明细在三份对照报告中：[规范与入口](rewrite-reports/migration-map-conventions.md)（287 行）、[底层选择 01–13](rewrite-reports/migration-map-foundations-a.md)（212 行）、[底层选择 14–27 与原有决定](rewrite-reports/migration-map-foundations-b.md)（193 行 + 43 条决定）。本页是汇总：每份旧文档的去处、已经写好的承接、尚未处理的缺口与冲突。逐行状态以报告为准；处理完一项就在本页记下。

## 旧文档的去处

| 旧文档 | 去处 | 状态 |
| --- | --- | --- |
| `docs/zh/01-conventions/01-development-workflow.md` | `01-conventions/10-development-workflow.md` | 已写 |
| `02-backend.md` | `01-conventions/06-component-implementation.md`（新）；技术栈表进底层选择或协议 18（见待定 2） | 待写 |
| `03-frontend.md` | `04-foundations/04-frontend-stack.md` 增补（主题与视觉、写法约定、商业版核对）；协议 20 的多语言 | 待写 |
| `04-configuration.md` | 协议 19 的配置与注册表；`06-component-implementation.md` | 待写 |
| `05-data.md` | `01-conventions/07-seed-and-test-data.md` | 已写 |
| `06-testing.md` | `01-conventions/02-testing-and-validation.md#实现测试的分层与节奏` | 已写 |
| `07-registries.md` | 协议 19 的注册表 | 待写 |
| `08-documentation.md` | `01-conventions/03-documentation.md`（整理时已承接） | 已覆盖 |
| `09-ai-development.md` | `01-conventions/09-ai-coding.md`；会话读多少在 `05-ai-navigation.md` | 已写 |
| `10-reference-implementations.md` | `01-conventions/08-reference-implementations.md` | 已写 |
| `01-conventions/README.md` | 新的 `01-conventions/README.md` | 待改 |
| `02-decisions/0101–0509` | 按原编号写进各主题文件；17 条去向需更正（报告 B 第 2 节） | 待写 |
| `03-seed-data.md` | 新的 `03-seed-data.md`（随重建组件补写）；规则进 07 | 已写 |
| `04-foundations/01–27` 与 README | 规则进协议，比较与改选条件进底层选择（见待定 1、2） | 待定 |
| 根 `AGENTS.md`、`AGENTS.zh.md`、`README*.md`、`docs/*/README.md` | 第 6 步中文重写；易错点按报告 1.14 节逐行处理 | 待写 |
| `.claude/skills/version-bump-ship` | 第 6 步改写链接与规则（报告 1.17 节） | 待写 |

## 已处理的缺口与冲突

- 测试分层不一致（规范 C1）→ A100，测试与验证规范的新一节。
- 版本线写死 2.x（C2）→ 通用写法 + A102 起始版本。
- 0303 没有落点（C16）→ 种子与测试数据的“凭据与部署”；手册 04 的上线检查。
- 种子的令牌（C13）→ A101。
- 外壳登录角色不继承（B-19、A-26a）→ 协议 14 的连接池。
- 模块读进程环境的措辞（C17、B-20）→ 协议 19 的配置。
- 文档语言（`BRICKKIT.md` 只写中文的写法）→ 文档规则的语言一节。

## 尚未处理的设计缺口与冲突

以终稿为准的冲突（报告中标“以终稿为准”的）不需要改动，只在承接时不把旧规则带进来。下列需要改终稿：

| 来源 | 缺口 | 拟处理 |
| --- | --- | --- |
| B-1 | 协议 17 采用熔断，取代 0503 的“用舱壁、不用熔断”，没有记录 | 记 AI 选择；0503 去向改“修订” |
| B-21 | 协议 18 指向协议 17 的“外壳义务”“组件之间的调用”，协议 17 没有这两节 | 协议 17 新增两节：外壳义务（启动器契约、不变量、合并安全核对）；组件之间的调用（截止时间逐跳传递只减不增、重试只对契约声明幂等的方法且只在不可用时、只有一层重试、出站并发上限、熔断） |
| B-22、C8 | `infra/bff-mobile` 卡写“适合外壳”，TypeScript 外壳尚无路线 | 边界卡改为单跑，TypeScript 外壳有路线后再评估 |
| C4 | `features` 随静态资源提供，可能在登录前暴露装配与版本 | 协议 20：只对已登录会话提供 |
| B-15 | 多语言数据由后端按用户语言返回，后端从哪里得知语言没写；与旧“返回整组译文”方向不同 | 协议 14 或 20 定一种 |
| B-23 | 边缘重试只在 `TOKEN_STALE` 时一次，其余带请求体的请求不重试 | 写成边缘的统一规则 |
| B-24 | 请求参数本身是越界的维度值时答什么 | 安全 09a 的结果表补一行，不泄露取值的存在性 |
| B-18 | 对象存储用前缀时的跨属主拒绝检查 | 协议 12 与存储套件补 |
| A-26b–n | `SET ROLE` 后 `ALTER ROLE SET` 不生效；共享池的预备语句；PG 队列的 xmin 屏障；运行期分区维护；连续编号在认领成功后分配；分区的锁级别；缺法人的事件；载荷上限与 claim check；跳数上限；收件表不分区；限制处理；账簿不存个人信息；“创建”命令的残余风险 | 逐项写进协议 14、02、11、03 或事务与消息 |
| A-22、A-24 | 契约金额与规范编码的十进制两种文本形式；用户偏好与显示时区 | 协议 14 写明 |
| A-25、B 第 2 节 | 0103 锁定技术栈、0506 流的划分、0101、0201、0206、0304、0504、0505、0509 的规则正文没有落点 | 随决定改写与待定 1 处理 |
| 规范报告“终稿遗漏的保护” | 模块不退出进程、不绕过 SDK 建引擎与连接；`brickkit remove --force`；测试版本只打本地标签 | 前两项进 `06-component-implementation.md`，后两项已在 10 |

## 待定

1. **线协议层面的细节**（头字段清单、超时与重试数值、错误体与 reason 目录、日志字段与指标、搜索与多语言向量、配置键目录）现在写进项目文档，还是在重建 `be-protocol` 时直接写进协议仓库。待用户裁定。
2. **底层选择的形态**：协议 21 写“每个底层选择一篇”，文档规则写三篇主题；两份报告分别建议恢复 4 篇与 3 篇按方面的文章（数据库引擎、消息运输与信封、冷存储、组件协议与语言；组件间调用与接口、边缘、观测）。待第 1 项定后裁定。
