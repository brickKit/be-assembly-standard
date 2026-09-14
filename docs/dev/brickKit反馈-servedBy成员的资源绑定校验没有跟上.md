# brickKit 反馈：`servedBy` 成员的资源绑定校验（`CheckRunningResourceBindings`）没有跟上 servedBy 语义

> **这份文档是一次性的**：只针对这一个具体问题，看完可以直接删掉，跟 `给brickKit的反馈.md` 那份长期文档性质不一样。这是我们这边继续做真实 `servedBy` 迁移时，`brickkit up`（非 `--dry-run`）真机复现出来的第二个"校验/合并机制没跟上 servedBy 语义"类问题——跟 labels 合并那条（见另一份反馈文档）是同一个类别，不是巧合，值得你们一起排查有没有第三处、第四处类似遗漏。

## 先说结论

一个组件声明了 `servedBy: <外壳>@<版本>`、自己不再持有容器之后，它 `component.yaml` 里 `dependencies.resources` 声明的资源依赖（比如 `database`/`mq`），**必须仍然在它自己的 componentId 下有一条 `bindings`，否则真的 `brickkit up`（不带 `--dry-run`）会报「资源依赖未满足」直接阻断**——即使外壳自己已经正确绑定了同一个资源、`DATABASE_*`/`MQ_*` 也确实正确注入进了外壳容器的真实环境。

`--dry-run` 时这条校验只降级成警告（不阻断），所以只用 `--dry-run` 走查很容易漏掉，得真的不带 `--dry-run` 才会暴露。

## 根因（读的是 `internal/resolver/resolver.go`）

`CheckRunningResourceBindings` 遍历 `running`（本次真的会启动的组件），对每一个都调 `unboundResourceDetails` → `matchResource`，逐条核对"这个组件自己的 componentId 在不在某条资源的 `bindings` 里"——这条逻辑完全不知道 `servedBy` 的存在，也没有查过"这个组件是不是被某个外壳 `servedBy` 收编了、外壳自己是不是已经绑了同一份资源"。

这跟 labels 合并那条是同一类根因：合并部署（不管是旧的 vendored-contract 方式、还是新的 servedBy 机制）总会有"这份数据原本是每个组件自己的，合并之后应该只在外壳层面留一份"的地方——env 变量合并已经做了这层收窄（只合并 `*_ENDPOINT`），但**校验层面**（资源绑定完整性检查）还是按"每个组件都得自己独立持有全部东西"的旧假设写的，没有一起跟着更新。

## 两个可能的修复方向（我们没有偏好，看你们判断）

- **方向一**：`CheckRunningResourceBindings`/`matchResource` 增加 servedBy 感知——一个组件如果 `servedBy` 指向了某个外壳，且该外壳自己的 componentId 已经绑了同一个 `kind`+`engine` 的资源，就判定为满足，不需要成员自己也绑一份。
- **方向二**：在文档里明确说清楚——`servedBy` 成员的 `dependencies.resources` 仍然需要在 `brickkit.yaml` 里保留一份指向自己的 `bindings`（哪怕这份绑定实际上不会产生任何真实的容器环境变量），跟外壳自己的绑定"重复"着写两份，这是预期用法，不是遗漏。这样至少让使用者不必像我们一样，先被真机 `up` 报错一次才知道这条隐藏要求。

## 我们这边的临时应对

在 `brickkit.yaml` 每个资源条目的 `bindings` 里，除了外壳自己的 componentId，把它收编的每个成员的 componentId 也原样保留了一份（跟外壳绑同一个资源、同一份凭据）——不会产生任何真实副作用（`servedBy` 成员本来就不生成容器，多出的绑定不会多注入出一份东西），纯粹是为了满足这条校验。已经在 `brickkit.yaml` 对应位置留了注释说明，等你们确认修复方向之后再决定要不要撤掉这份"重复绑定"。
