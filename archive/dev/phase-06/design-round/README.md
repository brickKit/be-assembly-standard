# 06b 跨组件设计轮

组外壳（06b T21–T24）之前，把 SDK 与跨组件层面的设计定型。每个议题一份分析文档（只读调查，不改代码），格式参照 `../dept-scope-analysis.md`：现状与证据（file:line）、可选方案与取舍、推荐方案、落地顺序（含先写的红测试）、要用户拍板的点。

判据（用户 2026-10-02）：遵循 brickKit 理念；对 AI 开发友好；组件可替换；数据库可按情况替换；能快速定位功能、快速迭代。任何东西都可以改，包括 SDK 整体重新设计——假设可以从头再写，选最好的设计，再说明从现状怎么走过去。

| 文档 | 议题 |
|---|---|
| `events-consistency.md` | 事件至少一次送达（JetStream）、事件快照的回读/回填、TCC/saga 可靠性（预留过期、对账）、幂等重放绑定命令+目标+调用者 |
| `data-layer.md` | 数据库身份解耦（R63 扫尾）、冷热数据生命周期、分区窗口、BatchGet 上限 |
| `identity-permissions.md` | 功能权限与数据权限的整体设计审查、gRPC 上的用户身份、Claims 读取 API |
| `authz-architecture.md` | 权限架构 v2：分享、关系派生、委托与 AI 代理、字段级、槽位族与一致性测试 |
| `data-lifecycle-v2.md` | 冷热数据 v2：四层 + 保全/限制处理、SDK 端口与适配器、治理组件 |
| `foundations-communication.md` | 底层审查：本地事务、跨组件一致性、同步通信、队列、缓存、边缘、后台任务、外壳；新 docs 目录结构 |
| `foundations-data-platform.md` | 底层审查：数据库、主键、时间金额、多租户、迁移、搜索、文件、可观测性、配置密钥、IAM、多语言 |
| `decisions.md` | 全部拍板点汇总 |
| `answers.md` | 用户对 `decisions.md` 各拍板点的实际答复；优先于一切分析的推荐 |
| `sdk-redesign.md` | SDK 整体重新设计：组件协议 be-protocol 1.0（P1–P20）、黑盒一致性套件 compconf（`tools/be-acceptance/conformance/component/`）、三门官方 SDK、现状盘点、迁移路径与任务表、brickKit 候选（附 FR 去向）、平台表参考 DDL |
| `sdk-redesign-apis.md` | `sdk-redesign.md` 的姊妹文件：三门语言逐个 API、外壳启动器、夹具组件 widget、第四门语言指南与 INTERNAL 规则清单 |
