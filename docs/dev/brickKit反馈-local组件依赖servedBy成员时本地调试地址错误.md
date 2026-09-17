# brickKit 反馈：`local:true` 组件依赖 `servedBy` 成员时，生成的本地调试地址是错的

> 这份文档是一次性的：只用来把这一条问题完整交给 brickKit，不是本项目的长期文档。完整的真机复现过程记在装配仓库 `docs/plans/05b-组合矩阵验证.md` 的 Task 8 里，这里只摘要结论、复现步骤、根因和修复方向。

## 结论

`local:true` 组件如果依赖了一个 `servedBy` 成员（合并进某个外壳容器、自己没有独立容器的组件），`brickkit up` 生成的 `local-debug.<组件>.env` 里，这个依赖的两类地址**都连不通**，而且是两种不同的错法：

- **额外端口（gRPC 端口）地址：静默给出一个看起来完全合理、实际上宿主机上没有任何进程监听的 `localhost:<端口>`**——没有报错、没有警告，调用方会稳定收到 `connection refused`，但配置本身"看上去完全正确"。
- **主端口（HTTP 端口）地址：保留成了容器内部的服务名形式（如 `http://mdm-customer-1-0-9:8080`）**，这个地址在宿主机上同样连不通（宿主机没有这个 DNS 名字），但至少没有伪装成本地地址。

两条路径都用不了，`local:true` 组件事实上完全够不着任何一个 `servedBy` 成员。

## 怎么复现

最小场景：一份 `brickkit.yaml`，某个组件 A 声明 `local: true`，同时依赖组件 B；B 被另一个外壳 `servedBy` 收编（不是独立容器，也没有 `expose: true`）。真实复现用的是本项目当前的真实组件：

```yaml
deploy:
  target: docker
components:
  - id: infra/bff-mobile
    version: 1.0.19
    local: true          # A：本地调试
  - id: mdm/customer
    version: 1.0.9
    servedBy: shell/go-core@0.5.4   # B：被合并进 go-core 外壳，不是独立容器
  # ……go-core 外壳本身也不 expose 任何端口
```

`brickkit up` 之后：

1. `docker port <go-core 容器>` 返回空——外壳容器没有发布任何端口到宿主机。
2. 生成的 `local-debug.infra-bff-mobile-1-0-19.env` 里：
   ```
   MDM_CUSTOMER_ENDPOINT=http://mdm-customer-1-0-9:8080       # 宿主机解析不了这个名字
   MDM_CUSTOMER_GRPC_ENDPOINT=http://localhost:9090            # 看起来对，但宿主机 9090 没人监听
   ```
3. `curl`/`nc` 直接验证：`localhost:9090` `connection refused`。

## 为什么值得修

`local:true` 是这个平台专门为"想在 IDE 里跑一个组件、其它依赖照常用容器"这个开发场景设计的能力（005 §4.6/§4.8/§4.9），而且这个能力已经对"依赖是独立组件（`expose` 与否都覆盖到）"这一种情况做了专门的正确性修复（见 `internal/compose/local.go` 里那段关于"依赖既 expose 又有 extraPorts"坑的详细注释和修复）。但**"依赖是一个 servedBy 成员"这第三种情况完全没有被这个修复覆盖到**——从 05a（`servedBy` 落地）开始，这种组合在真实项目里只会越来越常见（外壳合并部署是这个平台现在推荐的默认形态，独立组件反而是少数），`local:true` 这个开发者最常用的调试手段目前对它完全失效，而且失效得**没有任何提示**（生成的文件看起来语法、格式都对，直到真的发起请求才会发现）。这正是"看起来完全正确，直到真的跑起来才会发现"这一类最难排查的问题。

## 根因（已经读源码定位到具体函数和具体行）

`internal/compose/local.go` 的 `pointDependenciesAtLocalhost`（约第 497–526 行）：

```go
for _, extra := range node.Manifest.Deployment.ExtraPorts {
    port, ok := p.debugExtraPort[service][extra.Port]
    if !ok {
        // 只剩一种情况：依赖自己也是 local。……
        port = extra.Port
    }
    setVar(vars, prefix+"_"+strings.ToUpper(extra.Name)+"_ENDPOINT",
        localhostEndpoint(port))
}
```

这段代码自己的注释写的是"只剩一种情况：依赖自己也是 local"——但实际上 `p.debugExtraPort[service][extra.Port]` 查不到时，还有第三种可能：**依赖是一个 servedBy 成员**（这种情况下 `mapDependencyToHost` 因为 `!p.rendered[service]`——servedBy 成员没有自己的 compose service block——在函数开头就直接 `return` 了，从来没机会往 `p.debugExtraPort` 里写任何东西，见同文件第 298–343 行 `mapDependencyToHost` 的实现）。代码没有区分"依赖是 local"和"依赖是 servedBy 成员"这两种同样查不到 `debugExtraPort` 的情况，一律当成前者处理，于是拿组件自己 `component.yaml` 里声明的端口号（这里是 `9090`，`mdm/customer` 的 gRPC 端口）拼出一个 `localhost:9090`——巧合般地"看起来完全合理"，实际上宿主机上完全没有进程监听这个端口。

主端口那条路径（`pointDependenciesAtLocalhost` 第 503–505 行，`p.hostAccessPort`）没有这个"假阳性"问题，是因为 `hostAccessPort`（第 363–371 行）只查 `p.localPort`/`p.exposedPort`/`p.debugPort` 三张表，servedBy 成员在这三张表里也都查不到，`ok` 是 `false`，`setVar` 干脆不会被调用——这条路径的行为是"查不到就不改"，额外端口那条路径的行为却是"查不到就瞎猜一个"，两条路径对"查不到"的处理方式不一致，这也是这个 bug 存在的直接原因。

## 修复方向（不代为决定，供参考）

`pointDependenciesAtLocalhost` 的额外端口分支需要能区分"依赖真的是 `local:true`"和"依赖是 servedBy 成员"——前者才应该走 `port = extra.Port` 这条回退，后者应该跟主端口的处理方式一致（`setVar` 不调用，让这个变量保留"容器版"的值，如同现在主端口的行为），或者更进一步——既然这个变量注定连不通，也可以考虑生成时在 `local-debug.*.env` 文件里对这类地址加一行醒目注释（比如"⚠️ 这个依赖被合并进了外壳 xxx，目前没有任何机制能让宿主机上的 local:true 进程连到它，需要临时手工找一个绕过的办法"），至少让开发者不用真的发起一次请求、排查半天才发现问题。要不要连带修"servedBy 成员完全没有对 local:true 调试场景开放宿主机端口映射通路"这个更大的能力缺口（比如外壳容器要不要支持临时把某个成员的端口发布出去），是一个更大的产品决策，不在这次反馈范围内，这里只反馈已经确认、根因明确的这一处逻辑缺口。

## 临时应对（本项目这边）

05b Task 8 系列真机验证时，遇到这个问题后手动给 `shell-go-core`/`shell-go-infra` 对应的 compose service 临时加了 `ports:` 映射（直接编辑 `.brickkit/generated/docker-compose.yaml` 后用 `docker compose ... up -d` 局部重建这一个服务），让 `infra-bff-mobile` 的 `local:true` 裸进程能够连上外壳内的 `mdm-customer`/`erp-sales` 完成代表性业务调用；这个手工端口映射测完就撤销，不进 `brickkit.yaml`。这只是绕开测试，不是修复。
