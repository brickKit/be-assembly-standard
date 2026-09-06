# 全局册子

这四张表是**写任何 `component.yaml` / `assembly.yaml` 之前必须来查的东西**。

| 文件 | 是什么 | 为什么必须提前定死 |
|---|---|---|
| `ports.tsv` | 62 个组件的 HTTP + gRPC 端口 **+ 带外容器端口** | gRPC 等额外端口**没有任何事后补救手段**：平台改写地址时明确跳过额外端口，两个 `local: true` 组件撞同一额外端口时 `brickkit up` 在生成阶段硬报错（设计书 §3.5.1.1）。写到第 30 个组件才发现要回头改前 29 份 Manifest |
| `schemas.tsv` | 每组件的 PG schema / Role / 所属外壳登录角色 | 库一旦按「一组件一 database」建好、数据进去了，再改成一库多 schema 就是一次数据迁移（设计书决策 3、`006` §9.5） |
| `permissions.tsv` | 权限键册（`key`/`title`/`type`/`owner_component`/`deprecated`） | 改一个已发布的键名，所有已分配它的角色**静默失权且不报错**（设计书第 14 章 §14.1.2）。**现在是空文件**——内容来自各组件 `assembly.yaml` 的 `permissions` 段，而组件还一个都没有 |
| `data-scopes.tsv` | 数据权限总表（`component`/`dimension`/`column`/`mode`/`tables`） | 纯派生、可随时重生成，**不需要防改**——列在这里只是为了和另外三张放一起，别处一份份组件仓库找 |

## 改这两张「只增不改」的表的规矩

**`ports.tsv` 与 `schemas.tsv`（以及将来的 `permissions.tsv`）适用，`data-scopes.tsv` 不适用：**

1. **只增不改。** 已分配的端口/schema/权限键不许改——改了就是所有依赖方的 `*_ENDPOINT` 换值，或所有已分配角色静默失权。
2. 改完必须跑 `make registry-check`。
3. `ports.tsv` 里 `_infra-` 前缀的行是**带外容器**，不是组件。设计书的端口册只管 62 个组件，本项目把带外容器一起纳进来——因为外壳必须把端口发布到宿主机（§13.1），两边会真撞。
   ⚠️ **带外容器互相之间允许同端口**（`rustfs`/`minio` 同为 9000、`traefik`/`nginx` 同为 80）——它们是互斥替换件，永不同时跑。校验脚本只在冲突双方至少有一个是真实组件时才报错。
4. **`1xxxx` 整段是平台保留，不许分配。** brickKit 给 `local: true` 组件及其依赖做宿主机映射时首选 `10000 + 容器端口`、fallback 从 `18080` 起递增（`internal/compose/local.go`）。组件端口最大 9401（`integration-edi` 的 gRPC），所以平台实际会用到 **18080–19401** 这个范围里被撞到的那些。带外容器一律走 `2xxxx`。
5. 唯一的端口复用例外是 `slot:frontend` 族共用 80（槽位互斥、永不共存、各自独立 Nginx 容器不进外壳）+ 上面第 3 条的带外容器互斥对。校验脚本对两者都有专门放行。
6. `permissions.tsv` 废弃走 `deprecated` 墓碑列，**键名永不回收**（现在还没有内容，这条规矩留给阶段三 `infra-authz` 开工时用）。
