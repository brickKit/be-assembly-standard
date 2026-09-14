# brickKit 反馈：`servedBy` 的 labels 合并，少了 env 变量合并那层"排除语义上必然因组件而异的字段"

> **这份文档是一次性的**：只针对这一个具体问题，看完可以直接删掉，跟 `给brickKit的反馈.md` 那份长期文档性质不一样——学的是你们自己那份"回复"文档的做法。完整复现过程、根因分析、临时绕过方式，都已经同步记在了我们自己 `docs/plans/04b-验证记录.md` 的"0.1 真机执行记录"一节，这里只摘要问题本身，方便你们判断。

## 先说结论

`servedBy` 的 labels 合并规则（"同名同值跳过，同名不同值报错"）**没有像 env 变量合并那样，把"语义上就是每个组件各不相同"的字段排除在合并范围之外**。这不是一个边缘场景——我们真实的 11 个 Go 组件里，`component.yaml` 几乎全部声明了 `deployment.labels.prometheus.io/port`（值就是各自的端口号），这意味着**任何两个我们的真实组件被收编进同一个 `servedBy` 外壳，`brickkit up`/`--dry-run` 都会 100% 因为这条标签撞车而报错**——不是"可能"，是必然。

## 怎么复现的

1. 造一个最小外壳组件 `infra/go-core-shell-poc`，把 `mdm/customer`（`prometheus.io/port: "8080"`）和 `mdm/product`（`prometheus.io/port: "8082"`）都改成 `servedBy: infra/go-core-shell-poc@1.0.0`。
2. `brickkit up --dry-run`：报错，提示 `mdm/customer`/`mdm/product` 在 `prometheus.io/port` 上出现冲突（一个 `8080`，一个 `8082`，规则判定"同名不同值"）。
3. 临时把两个组件 `component.yaml` 里的 `prometheus.io/port` 行删掉（只留 `prometheus.io/scrape`/`prometheus.io/path`，这两个两边本来就相同）——重跑成功，`BRICKKIT_SERVED_MEMBERS`、网络别名、依赖方地址路由全部符合预期。
4. 验证完毕后 `git checkout --` 全部回滚，确认两个子仓库、根仓库都恢复干净。

## 为什么这跟 env 变量那次是同一类问题

`*_ENDPOINT` 类环境变量语义上"整个外壳内必须一致"，所以合并 + 冲突检测是对的；但 `COMPONENT_ID`/`COMPONENT_VERSION` 语义上"必然因组件而异"，所以被无条件排除出合并范围——这个收窄你们已经做了，`TestResolveMergesOnlyEndpointVars` 也覆盖了。

`prometheus.io/port` 是 labels 侧完全对应的情况：它的值**就应该**是每个组件自己的端口号，语义上从来就不该要求"整个外壳内一致"。但 labels 合并规则里没有做这层收窄，导致它被套用"同名不同值就报错"这条本来是为了防止真实冲突（比如两个组件都手滑写了同一个自定义标签却给了不同值）而设的规则，变成了必然触发的假阳性。

## 两个可能的修复方向（我们没有偏好，看你们判断）

- **方向一**：labels 合并也做一层"已知语义必然因组件而异"的字段排除，`prometheus.io/port` 首当其冲；类似 env 侧对 `COMPONENT_ID`/`COMPONENT_VERSION` 的处理。
- **方向二**：`prometheus.io/port` 这类标签本来就是"合并后只能有一个共享抓取端口"的事实（多个进程合成一个容器，Prometheus 只能抓一个端口），干脆把它归到 `healthCheck`/`expose` 那一类——**servedBy 成员声明了就警告 + 忽略，不参与合并**，让外壳自己的条目上的 `prometheus.io/port`（如果有）说了算。

我们这边的临时应对方式是等你们确认之前，把这类会必然冲突的标签从 `servedBy` 成员的 `component.yaml` 里去掉，只在外壳自己的条目上保留一份——但这终归是绕过，不是修复，我们更倾向于等你们那边看完再决定怎么处理，不会抢在你们前面动这批组件的 `component.yaml`。
