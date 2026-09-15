# 反馈给 brickKit：servedBy 合并部署下，外部工具（本地开发脚本/运维工具）该怎么直接访问一个组件的端口，目前没有任何文档说明

## 发现于

`be-assembly-standard` 仓库阶段四附加 Task 0.5——8 个组件（`mdm-customer`/`mdm-product`/`erp-inventory`/`erp-finance`/`erp-sales`/`infra-authz`/`infra-print`/`crm-opportunity`）各自的 `scripts/seed.sh`（本地开发种子数据脚本）在 `brickkit.yaml` 从 `local: true` 全量切到 `servedBy` 之后全部失效——脚本原来靠 `docker ps` 按名字前缀找组件自己的独立容器，或者假设组件把端口发布到了宿主机（`http://localhost:<port>`），`servedBy` 合并部署下这两个前提都不成立：组件没有独立容器，也没有发布到宿主机的端口。

## 问题本身

这不是 bug，是一个真实存在、但完全没有文档覆盖的知识缺口：**当一段外部代码（本地开发脚本、运维工具、一次性调试）需要绕过组件自己的业务 API，直接打它的 gRPC/HTTP 端口时，应该怎么拼这个地址？**

排查后确认 brickKit 自己内部其实有一套完全一致、不区分部署形态的解决方案——`internal/manifest/servicename.go` 的 `ServiceName(id, version)`：

```go
var serviceNameReplacer = strings.NewReplacer("/", "-", ".", "-")
func ServiceName(id, version string) string {
    return serviceNameReplacer.Replace(strings.ToLower(id + "-" + version))
}
```

这条转换规则（componentId+version 转小写、`/`和`.`全部替换成`-`）算出来的字符串，**同时是**：
- 组件独立部署时，它自己那个容器的 compose service 名（也是它的 DNS 名）；
- `servedBy` 合并部署时，外壳容器网络别名里的一个别名（`internal/compose/servedby.go` 的 `applyShellGroups`，K8s 侧 `internal/k8s/servedby.go` 新建一个 Service 对象，selector 指向外壳 Pod，命名函数完全一致）。

也就是说，**只要拿到这一条地址，不管目标组件当前是独立部署还是被合并进了某个外壳，从 brickkit 自己管理的 docker 网络内部都能直接连上**——外部工具完全不需要关心"这个组件现在是不是被合并了""它有没有自己的容器"。

## 现有文档的覆盖情况（已确认，不是没找到）

这条规则本身**不是完全没被文档化**——`docs/zh/architecture/overview.md`（`docs/en/` 有对应镜像）"版本化服务名与统一地址格式"一节写明了同样的转换规则和 `http://<版本化服务名>:<端口>` 格式。但这一节的视角完全是"平台自动怎么给 `*_ENDPOINT` 注入地址"，没有一个字提到"外部工具（不是另一个 brickkit 组件，是一段独立跑的脚本/程序）该怎么用同一条规则手工拼地址、加入哪个网络"。

`docs/zh/patterns/servedby-deployment-checklist.md` 的"哪些事平台不会自动帮你做"一节已经点到了这个问题的症状（"有些可观测性/调试工具默认假设一个组件对应一个容器……对于 `servedBy` 组件，日志、指标、进容器排查都要去壳里面找"），但没有给出这个具体场景（外部工具直接打端口）的解决方案。

`ServiceName` 这个函数名/符号本身，从未出现在任何面向平台用户的文档里，只出现在内部实现和面向 brickKit 自己开发者的工程记录里。

## 建议

在 `docs/zh/patterns/servedby-deployment-checklist.md`（及 `docs/en/` 镜像）"哪些事平台不会自动帮你做"这一节，或者 `docs/zh/architecture/overview.md`"版本化服务名与统一地址格式"这一节，补一小段面向"外部工具作者"的具体指引，大意是：

> 如果你要写一段独立跑的脚本/工具（不是另一个 brickkit 组件），需要绕过某个组件自己的业务 API 直接访问它的 gRPC/HTTP 端口——不管这个组件现在是独立部署还是被 `servedBy` 合并进了某个外壳，地址都是 `http://<版本化服务名>:<该组件自己声明的端口>`（版本化服务名的算法见上面"统一地址格式"一节），前提是这段代码要跑在 brickkit 管理的那个 docker 网络内部（比如 `docker run --rm --network <项目网络名> <镜像> ...` 临时加入进去），不能假设组件把端口发布到了宿主机——`expose: true` 只对独立部署的组件生效，`servedBy` 成员完全不受它影响。

我们自己在 `be-assembly-standard` 这边的具体修法（供参考）：8 个组件的 `scripts/seed.sh` 统一改成起一次性"工具箱"容器（`curlimages/curl:latest`）加入 brickkit 网络，全部 REST 调用改在里面跑，gRPC 调用本来就是这个模式（`docker run --rm --network ... fullstorydev/grpcurl`），只是把目标地址从"猜容器名"改成用上面这条转换规则直接算。过程中还踩到一个连带坑：`curlimages/curl` 默认用镜像自带的非 root 用户跑，如果调用方在宿主机侧 `mktemp` 建了一个 cookie jar 文件再挂载进容器（权限 0600，属主是宿主机用户），容器内的 curl 会没有权限读写——现象是 Casdoor 这类返回业务层"请先登录"错误，完全看不出是文件权限问题。挂载宿主机目录跑容器化工具时，加 `--user "$(id -u):$(id -g)"` 能避免这个坑，这也是个通用性的提示，不特定于 brickKit，但既然影响面是"任何人试图用容器化命令行工具去访问宿主机侧文件"，也许值得在同一段落提一句。
