# 交付关键路径上的工具（都不是 brickKit 组件）

| 目录 | 用途 | 阶段（总纲 §2.4 / §3.5.1） |
|---|---|---|
| `be-ops/` | 装配生成器。认领平台明确不做的 11 个产出（总纲 §2.4） | 阶段一 |
| `be-acceptance/` | 验收测试：20 条平台验收 + 业务闭环 + 拆回门禁 + import 扫描 | 阶段一 |
| `be-sdk-go/` | Go 横切基础库（SOP-L 十四项能力）。零业务逻辑、零组件 model | 阶段一 |
| `be-sdk-python/` | Python 横切基础库，与 `be-sdk-go` 同一套能力 | 阶段三 |
| `be-sdk-ts/` | TS 横切基础库（只有一半：无 `withTx` / 无冷热路由，多 GraphQL 限制） | 阶段三 |

`be-shell-go` / `be-shell-python`（外壳启动器）**不放这里**，见 [`shells/README.md`](../shells/README.md)。
