# brickKit 反馈：真机 `brickkit up`（非 `--dry-run`）对 servedBy 成员报 `no such service`，直接阻断启动

> **这份文档是一次性的**：只针对这一个具体问题，看完可以直接删掉。这是我们这边继续做真实 `servedBy` 迁移时，真机执行 `brickkit up`（不带 `--dry-run`）复现出来的第三个"校验/编排逻辑没有跟上 servedBy 语义"类问题——前两个分别是 labels 合并、资源绑定校验（另两份反馈文档），这次是**最严重的一个：`brickkit up` 完全无法启动，不是警告，是直接报错退出**。三个问题同一类根因，建议你们一起排查这条 `local: true` → 也要处理 `servedBy` 的改造，是不是还有第四处没跟上。

## 复现

`brickkit.yaml` 里 12 个组件用 `servedBy` 指向 4 个外壳（0 个独立容器化，全部走合并），`brickkit up --dry-run` 完全正常、生成的 `docker-compose.yaml` 完全正确（只有 4 个外壳 service + 2 个独立组件 service，没有为 12 个 servedBy 成员生成 service，符合预期）。

去掉 `--dry-run` 真的执行：

```
❌ 错误：docker 执行失败
   命令：docker compose --project-directory . -p brickkit-be-assembly-standard -f .brickkit/generated/docker-compose.yaml up -d --wait --remove-orphans erp-finance-1-0-12 erp-inventory-1-0-16 frontend-standard-1-0-0 infra-authz-1-0-6 infra-bff-mobile-1-0-18 infra-iam-casdoor-1-0-8 infra-notification-1-0-4 infra-print-1-0-6 infra-workflow-1-0-4 integration-im-dingtalk-1-0-5 mdm-customer-1-0-8 mdm-product-1-0-9 crm-opportunity-1-0-11 erp-sales-1-0-24 shell-go-backoffice-0-4-6 shell-go-core-0-4-6 shell-go-infra-0-4-6 shell-py-render-0-2-4
   输出：no such service: erp-finance-1-0-12
```

`docker compose` 收到的目标 service 列表里混进了 12 个 servedBy 成员自己的版本化服务名（`erp-finance-1-0-12`/`mdm-customer-1-0-8`……），而这些 service **在生成的 compose 文件里根本不存在**（它们没有自己的容器，工作负载在外壳里）——`docker compose` 直接报 `no such service` 退出，`brickkit up` 完全启动不起来，不是某个组件起不来，是**整个命令直接失败，一个容器都没起**。

## 根因（读的是 `internal/cli/up.go`）

`collectTargets(order *resolver.Plan)`（约第 468-494 行）：

```go
func (p *upPlan) collectTargets(order *resolver.Plan) {
	local := map[resolver.Ref]bool{}
	for _, c := range p.cfg.Components {
		if c.Local {
			local[resolver.Ref{ID: c.ID, Version: c.Version}] = true
		}
	}

	for _, step := range order.Steps {
		ref := step.Ref
		if local[ref] {
			continue
		}
		...
		p.services = append(p.services, manifest.ServiceName(ref.ID, ref.Version))
		...
	}
}
```

这个函数只用 `c.Local`（`local: true`）来判断"这个组件没有自己的容器，不该出现在 `docker compose up` 的目标 service 列表里"——完全没有检查 `c.ServedBy`。`servedBy` 落地之后，"没有自己的容器"这个判断多了第二种情况，但这里只处理了旧的那一种。

这跟另外两份反馈是同一类根因：`local: true` 时代写的"没有容器时该怎么办"的判断逻辑，`servedBy` 落地后没有跟着走一遍全仓库，逐处确认是不是都要加上"或者被 servedBy 收编"这半句。

## 我们这边目前的应对（纯临时绕过，不构成长期方案）

**不经过 `brickkit up`，直接对生成好的 compose 文件跑 `docker compose up -d --wait --remove-orphans`（不显式传 service 名，让 docker compose 用文件里的全部 service）**：

```bash
docker compose --project-directory . -p brickkit-be-assembly-standard \
  -f .brickkit/generated/docker-compose.yaml up -d --wait --remove-orphans
```

这样能绕开这个命令构造的 bug，因为文件本身是对的、`--dry-run` 生成的产物没有问题。但这只是让容器起得来，不是完整方案——`brickkit up` 打印的镜像拉取检查、启动顺序、"以下基础资源需要先跑起来"这些人类可读的提示信息全都拿不到了，长期肯定需要你们修好 `collectTargets`（加一句 `servedBy` 判断，跟 `local` 判断同一个位置），而不是我们长期绕开命令本身。

## 建议的修复方向

`collectTargets` 判断"是否跳过"时，除了 `c.Local`，加上"这个组件的 `ServedBy` 是否非空"（同一条件），逻辑上应该跟 `internal/shell.Resolve`（渲染 compose 时决定"这个组件不生成自己的 service"）用的是同一个判据——两处理应共用同一个"这个组件有没有自己的容器"的判断函数，而不是分别各写一份，这样以后再出现类似情况能少一处遗漏。
