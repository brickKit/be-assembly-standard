# 工具

`tools/` 下是项目自己的工具，都不是 BrickKit 组件、不进 `brickkit.yaml`；每个是独立仓库，以子模块挂载。外壳在 `shell/`，不在这里。每个工具怎样用、怎样改，读它自己的 `README.md` 与 `AGENTS.md`。

| 目录 | 是什么 | 现状 |
| --- | --- | --- |
| `be-protocol/` | 组件协议：任何语言的组件都要遵守的线上格式、表结构与配置键，以及跨语言的共同语义向量 | 现行（3.0.0 起） |
| `be-sdk-go/` | 组件协议的官方 Go 实现，组件的运行时 | 现行 |
| `be-sdk-python/` | 组件协议的官方 Python 实现 | 现行 |
| `be-acceptance/` | 参考模型、文档检查、实验格工具、L3 场景与负载驱动 | 现行 |
| `be-ops/` | 装配时的生成器（注册表汇总、事实类的图与索引） | 还是旧的 2.x 版本；按新设计评估后重写，在那之前注册表里的权限键与数据范围是 2.x 的（见 [registry/README.md](../registry/README.md)） |
| `be-sdk-ts/` | TypeScript SDK | 当前范围不做，仓库原样不动（[A108](../docs/zh/02-decisions/09-ai-choices.md)） |
