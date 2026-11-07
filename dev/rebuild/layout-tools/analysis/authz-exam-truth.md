# 窄题：冷静期改成配置键（infra/authz，标准答案，考前写）

题：部署所有者确认的放宽类受保护操作的冷静期现在固定 24 小时。要改成配置键 `AUTHZ_COOLING_OFF`（时长，默认 24h）。要改哪些地方（文件、函数）、测在哪、要谁决定什么？

- G1 常量 `CoolingOff`（`cooling.go`）有两处用：生效点把所有者确认的放宽保存为待生效时，生效时间 = 此刻 + 冷静期（`facts.go`）；判断别的管理员“在冷静期内变得不可用”的回看窗口（`cooling.go` 的 `madeUnavailableBy` 的 SQL）。两处都要换成配置值。
- G2 配置键的声明：入口的 `Keys`（`definition.go`）；`component.yaml` 的 `configSchema`；`manifest_test.go` 的 `ownKeys` 说明；`BRICKKIT.md` 的配置指南。
- G3 值怎样到模块：模块共用的状态（新：`core.Base` 加字段；旧：`Module` 加字段）在 `New` 里读配置并校验（> 0）。
- G4 测试：集成测试的冷静期一步（`cooling_integration_test.go` 的 `coolingOff`）；它用 `ageHoldings` 把持有资格的更新时间改成 25 小时前，绑着 24 小时：配置化后这里要跟着配置（或测试设一个短的值）。
- G5 已保存的记录带着自己的 `cooling_off_until`（期满不再重判）：改配置不影响已经在冷静期里的记录，要不要追溯是一个决定。
- G6 规范：安全 08 的参数表写着 24 小时（以及 CP113 的例子）；配置化要改协议或记一个决定（部署可调的范围、上下限），由维护者定。
- G7 `docs/design.md` 的冷静期一段（写着 24 小时）跟着改。
