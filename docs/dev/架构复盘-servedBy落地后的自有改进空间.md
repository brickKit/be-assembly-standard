# 架构复盘：servedBy 落地后，我们自己这边还有哪些能改得更好

> 这份文档回答的问题是"进入 Task 1 起的完整部署矩阵验证之前，我们自己
> 这边的结构和实现方式，有没有更实用、更完整的做法"。三条发现都来自
> 这次 servedBy 真机迁移（Task 0.4/0.5）里真实撞到、或者向 brickKit 源码
> 求证之后才看清楚的东西，不是凭空猜测的"理论上更优雅"。
>
> ⚠️ **2026-09-15 更新**：给 brickKit 的那份提案文档（原
> `brickKit反馈-两个降低servedBy运维摩擦的架构提案.md`）已经被
> brickKit **v0.4.2 完整采纳并实现**（新增保留变量
> `BRICKKIT_SERVED_MEMBERS_CONFIG` + `brickkit up --ignore-served-by`），
> 反馈文档已按"创建-读取-删除"惯例删除。**下面发现二、发现三原来的
> 建议已经被这次上游改动整个取代**，保留下来是为了记录判断过程，
> 具体怎么改已经更新成"迁移到新的原生机制"，不再是"我们自己造防御
> 措施"。发现一跟这两个提案无关，原样保留。

## 发现一：8 个组件的 `scripts/seed.sh` 里，合并部署寻址那段样板代码近乎逐字重复

### 现状

这次修 servedBy 兼容性，`mdm-customer`/`mdm-product`/`erp-inventory`/
`erp-finance`/`erp-sales`/`infra-authz`/`infra-print`/`crm-opportunity`
八个组件的 `scripts/seed.sh` 都需要加上同一段东西：

- 一份 `component_version()`/`service_name()` 函数（读 `brickkit.yaml`
  算出 brickKit 风格的版本化服务名）；
- 一个一次性"工具箱"容器（`curlimages/curl`，加入 brickkit 网络，
  `--user "$(id -u):$(id -g)"` 避开权限坑）；
- 一段"用 admin/123 登录 Casdoor → 换 ROPC 应用 client_id/secret →
  拿目标用户的 id_token → 换 `infra-iam-casdoor` 签发的应用 JWT"的
  `get_jwt`（或等价内联代码）。

八份文件加起来 877 行，这段样板在每份文件里占大约四分之一到三分之一
（`erp/sales` 161 行里约 50 行、`crm/opportunity` 245 行里约 60 行）。
业务逻辑本身（建哪些客户/商机/订单、什么状态组合）当然每个组件都不同，
不该抽象；但**这段"怎么连上 brickkit 网络、怎么换一个真实 JWT"的部分，
八份文件字面意义上是同一段代码**，未来铺满军火库到 62 个组件，这个数字
只会继续变大，而且**每次这段代码需要修一个坑（这次的 `--user` 权限坑
就是例子），都要在全部有 seed.sh 的组件里各改一遍**——这正是这次真机
验证亲身经历的复发模式。

### 为什么这不违反"组件完全独立"的铁律

自查第一反应应该是"这不是又要在组件之间抽一个共享包吗，铁律六不让"——
但铁律六管的是**业务逻辑代码**（`import ".../mdm-customer/..."` 这类），
`scripts/seed.sh` 从写下第一行起就已经不是"组件独立可运行"意义上的
资产：它靠相对路径 `$ROOT/registry/ports.tsv`、`$ROOT/brickkit.yaml`
读装配仓库的数据，脱离 `be-assembly-standard` 这个仓库检出单独跑这个
脚本本来就不成立。**它已经是"装配仓库的开发工具"，不是"组件自己的
可移植资产"**——这个定位下，抽到装配仓库自己的一个共享脚本，跟组件
是否保持独立部署能力没有任何关系。

### 建议

在 `infra/scripts/` 下新增一个可以被 `source` 的库文件（比如
`infra/scripts/lib/seed-net.sh`），提供：

```bash
# service_name <componentId>  -> 版本化服务名（读 brickkit.yaml 当前版本）
# with_toolbox <net>          -> 起工具箱容器，设置好 curl() 包装函数与
#                                EXIT trap，调用方不需要自己管容器生命周期
# get_app_jwt <username>      -> 换 ROPC 应用 JWT 的完整流程
#                                （固定用 local-dev-seed-app + DevSeed123!，
#                                这是全部种子脚本共享的既有约定，不是
#                                这次才发明的）
```

八个组件的 `scripts/seed.sh` 开头统一改成：

```bash
source "$ROOT/infra/scripts/lib/seed-net.sh"
```

好处不只是"少写字"：以后 brickKit 的地址转换规则、Casdoor 登录方式、
`--user` 这类权限坑，只需要改一处；而且可以顺手加一条低成本的
`make gates` 新判据——"每个有 `scripts/seed.sh` 的组件必须 `source`
这个共享库，不许自己重新实现 `docker run --network`"，跟现有
`import-scan` 的精神一致：机制化住一条容易被人手滑绕开的纪律。

### 权衡

这条改动的成本主要是"多一层间接"：新加入组件的人要先知道有这个共享库
才能正确写 seed.sh，不像现在这样每份文件都是自包含、复制粘贴改改就能
用的独立样板。如果判断"新增组件的频率不高、每次都是 AI 在场帮忙写"，
这个成本可以接受；如果更看重"每个组件文件夹本身能不能被完全孤立地
理解，不用跳去装配仓库另一个目录"，可能宁愿保留现在的重复。这是一个
需要用户判断取舍的点，不是纯技术问题。

---

## 发现二（✅ 已被 brickKit v0.4.2 从根上解决）：`shellConfigJson` 的陈旧风险——这次真机复发了两次，`bump-version` 完全不知道它的存在

### 现状

`shells/go`/`shells/python` 装哪些模块，靠 `brickkit.yaml` 里每个外壳
组件自己 `configSchema` 里贴的一段 `shellConfigJson` 字符串（`be-ops
shell-config --shell <外壳名>` 生成）。这段数据只要下面任何一样变了就
会过期：

- 任何一个被这个外壳收编的成员，版本号变了；
- 任何一个成员的 `config` 键值变了（比如这次批量把 `authzBundleUrl`/
  `iamJwksUrl` 从 `host.docker.internal` 改成网络别名）；
- 哪个成员被哪个外壳收编的关系变了。

这次真机迁移里，这个"忘记重新生成"的坑**复发了两次**：一次是发现
`shell/go-core`/`go-backoffice`/`py-render` 的 `shellConfigJson` 还停
在改地址之前的旧版本，另一次是版本号批量发布之后，漏掉了
`shell/go-infra` 自己的 `shellConfigJson`（它列的是自己收编的
`infra-authz`/`infra-iam-casdoor` 等 5 个成员，版本号变了同样要重新
生成），导致外壳真机 crash-loop，报"`BRICKKIT_SERVED_MEMBERS` 里有
`SHELL_CONFIG_JSON` 找不到的成员"。

去查了 `tools/be-acceptance` 的 `versionbump` 包（`make bump-version`
背后的实现）：它的 `Component` 结构（`versionbump/scan.go:22-27`）只
追踪 `ID`/`Dir`/`Version`/`DepIDs`（依赖边），**完全不知道
`servedBy`/外壳收编关系这回事**。它已经有一套很扎实的"自动同步散落
字面量"的机制（`versionbump/apply.go` 的 `syncHostnameLiteral`，这次
批量发布时自动把 22 处 `authzBundleUrl`/`iamJwksUrl` 里的旧版本主机名
换成新的），但它的正则专门匹配"独立一行的 `authzBundleUrl: "..."`"
这种形状，**看不见嵌在 `shellConfigJson` 那一整段 JSON 字符串里面的
同类值**——两个漏改的坑本质上是同一个根因的两种表现形式。

### ✅ 结论：不需要自己造防御措施了，直接迁移到 brickKit 原生机制

原来这里写的是"两层防御"（加一致性 gate、或者扩展 `bump-version` 自动
重新生成）——两条都是**在问题存在的前提下降低它的影响**，不是消灭
问题本身。brickKit v0.4.2 已经把问题本身消灭了：新增保留变量
`BRICKKIT_SERVED_MEMBERS_CONFIG`（`internal/inject`/`internal/shell`
在生成 `BRICKKIT_SERVED_MEMBERS` 的同一处代码里，把每个被收编成员的
`componentId`/`version`/`httpPort`/`extraPorts`/合并后 `config`（原始
configSchema key，驼峰形式）打包成 JSON 数组，原生注入外壳容器，零个
成员时是 `[]` 而不是变量缺失）——这份数据本来就是平台自己算好的，
**不再需要我们自己起一个命令行工具算一遍、手工贴进 `brickkit.yaml`**，
"改了配置忘记重新生成"这整类坑从设计上就不会再发生。

**需要做的事，从"加两层防御"变成"迁移到新机制"**：

1. `shells/go`/`shells/python` 的外壳启动器，改成读
   `BRICKKIT_SERVED_MEMBERS_CONFIG`（JSON 反序列化直接拿到每个成员的
   完整装配数据），不再解析 `SHELL_CONFIG_JSON`。
2. 退休 `be-ops shell-config` 子命令——它的产出对象不再需要存在。
3. 4 个外壳的 `component.yaml`，删掉 `shellConfigJson` 这个
   `configSchema` 属性；`brickkit.yaml` 里对应的字符串配置也一并删掉。
4. ⚠️ **这条预判被真机验证推翻，记录下来避免重蹈覆辙**：这里原来
   以为 `go-infra` 外壳那 6 个密钥类配置项（`appTokenSigningKeyPem`
   等）走的 `envWithProcessFallback`/`_env_with_process_fallback`
   兜底机制不受这次迁移影响、继续保留——真机 `brickkit up` 复现出
   一个更严重的问题：这几个值在 `brickkit.yaml` 里仍然是 `${VAR}`
   占位符，docker compose 读取生成好的 `docker-compose.yaml` 时会对
   整份文件按纯文本做 `${VAR}` 替换，不知道某个 `${VAR}` 恰好嵌在
   `BRICKKIT_SERVED_MEMBERS_CONFIG` 那份 JSON 字符串内部——真实密钥
   自带原始换行符，替换进去直接把 JSON 断开（`shell-go-infra`
   crash-loop）。恢复 `envWithProcessFallback` 这条老路**治标不治本**
   （撑坏 JSON 的是拥有该密钥的成员自己那条 config 记录，外壳自己
   多存一份不会让它消失），真正的修复是外壳启动器自己在
   `json.Unmarshal`/`json.loads` 之前做一次"只转义 JSON 字符串内部
   裸控制字符"的最小状态机（`sanitizeServedMembersConfig`/
   `_sanitize_served_members_config`）——修好之后
   `envWithProcessFallback` 反而**彻底不需要了**，`BRICKKIT_SERVED_
   MEMBERS_CONFIG` 对全部 config 值（含密钥类）统一成立。这是
   `BRICKKIT_SERVED_MEMBERS_CONFIG` 机制本身的普适性设计缺口（docker
   compose 的全文本 `${VAR}` 替换不知道自己在 JSON 字符串内部），已
   反馈给 brickKit。完整过程见 `docs/plans/05a-迁移到servedBy.md` Task 0.6、
   两个外壳仓库各自 README.md 的"Task 0.6"系列小节。

   ⚠️ **2026-09-16 更新，`sanitizeServedMembersConfig` 本身也已经退休**：
   brickKit v0.4.3 换了个从根上消除这类问题的设计——
   `BRICKKIT_SERVED_MEMBERS_CONFIG` 的 `config` 字段改名
   `configEnvVars`，只携带"这个 key 对应外壳进程环境里哪条独立变量"
   的变量名，不再携带值本身，值改走一条独立的、带组件 ID 前缀命名的
   标量环境变量，`${VAR}` 展开完全交给 docker compose，不再嵌在任何
   结构化字符串内部。两个外壳仓库的
   `sanitizeServedMembersConfig`/`_sanitize_served_members_config`
   这层下游兜底因此也整个删除——上面这段"密钥类值需要 JSON 字符串内部
   转义"的描述本身已经是历史，不再是现状，完整过程见
   `docs/plans/05a-迁移到servedBy.md` Task 0.6 收尾一节。
5. 《BrickEnterprise 设计书.md》§13.8（这次 Task 0.5 才刚重写成
   "`SHELL_CONFIG_JSON` + `be-ops shell-config`"的机制说明）需要跟着
   再改一版，反映"外壳启动器直接读 `BRICKKIT_SERVED_MEMBERS_CONFIG`，
   不需要我们自己生成/维护任何平行数据"这个更简单的新事实。

这条改动本身不难（比原来设想的"扩展 versionbump 包"简单得多），但
牵涉两个外壳仓库 + 装配仓库 + 设计书，需要真机重新验证一遍，属于
"值得做，但要专门排一次真机验证"的工作量，不是编辑一个文件就完事。

---

## 发现三（✅ 已被 brickKit v0.4.2 整体取代）：拆回门禁脚本要处理的两个"连带坑"，根源是我们自己删掉了本来无害的冗余字段

### 现状

`infra/scripts/strip-shell-servedby.py`（`make teardown-up` 用来临时
去掉 `servedBy` 验证组件独立性的脚本）除了删 `servedBy:` 那几行，还要
额外处理两件事：

1. 给每个成员在它原来所属外壳对应的资源上，临时补一条它自己的
   `bindings` 条目；
2. 给每个成员临时加回 `expose: true`。

这两步存在，是因为这次真机迁移把 `servedBy` 落地之后，我们主动把
"暂时不生效、但拆回时会需要"的这两类字段从 `brickkit.yaml` 里删掉了：

- `resources` 段的每个成员各自的 `bindings`（v0.4.1 修复 `servingShellID`
  之后，认为"外壳绑了资源，等价于它收编的每个成员也绑了"，成员自己那份
  变成"多余"，删掉图干净）；
- 12 个成员各自的 `expose: true`（阶段一起就有，理由是"servedBy 成员
  不生成容器，这两个字段对它不生效，不留一份写了不生效的配置"）。

去 brickKit 源码核实了这两类字段在 `servedBy` 常态下真实的处理方式：

- **资源绑定**：`internal/resolver/resolver.go` 的 `matchResource` 判定
  是"外壳绑定 `b.ComponentID==shellID` 或者成员自己绑定
  `b.ComponentID==componentID`，两条路任一为真都算满足"——两者是**等价
  的两条路**，不是"成员绑定已经过时、只有外壳绑定才对"。也就是说，
  就算成员自己的 `bindings` 条目还留着，`servedBy` 常态下也完全不会
  报错或产生任何副作用，纯粹是"多一条判定路径永远为真、但不影响结果"。
- **`expose`**：`internal/compose/servedby.go`/`internal/k8s/servedby.go`
  对 servedBy 成员上的 `expose`/`hostname`/`resources` 等字段的处理是
  **警告 + 忽略**，不是硬错误——留着这个字段，`brickkit up` 照样成功，
  只是多打印一行"这个字段对合并成员不生效"的提示。

**换句话说：这两类字段"删掉"换来的唯一好处是配置文件更干净、没有
"暂时不生效"的字段留着，但代价是拆回脚本要额外写两段逻辑去临时补回
本该一直都在的东西。如果当初不删，`strip-shell-servedby.py` 现在
大概率只需要删 `servedBy:` 那几行这么简单**（甚至可能不需要专门的
Python 脚本，一条 `sed`/`grep -v` 就够了）。

### ✅ 结论：整套"改文件再 git checkout"的机制都不需要了

原来这里在"保留冗余字段简化脚本"和"保持现状接受脚本复杂"之间权衡——
这个权衡本身已经不需要做了。brickKit v0.4.2 新增
`brickkit up --ignore-served-by`：内存里清空全部 `servedBy` 声明再跑
一次（可以叠加 `--dry-run` 只看生成结果，也可以真实启动一遍），
**从不写回 `brickkit.yaml`**，切入点在配置解析之后、送进 resolver 之前
一次性清空，下游资源绑定校验、`expose` 处理都是原生走同一套逻辑，
不需要我们自己的脚本再处理"资源绑定补回""`expose` 补回"这两个连带坑
——这两个坑本来就是"手工改文件"这个做法自己引入的，原生开关不改文件，
坑自然不存在。

**需要做的事**：

1. `infra/scripts/strip-shell-servedby.py` 整个退休。
2. `make teardown-up` 简化成 `brickkit up --ignore-served-by`（真实
   启动，供 `make tier0`/`make tier1` 用）；`make teardown-down` 只需要
   `brickkit down`（不再有"改过的 `brickkit.yaml` 需要 `git checkout`
   恢复"这件事，因为原生开关从来没碰过磁盘上的文件）。
3. `infra/scripts/weekly-teardown-gate.sh` 同步简化，去掉
   `git status`/`git checkout` 相关的前置检查和收尾（不再需要，因为
   不会有"改了一半的文件"这种中间状态）。
4. 《BrickEnterprise 设计书.md》§13.9（这次 Task 0.5 才刚重写成
   "`teardown-up`/`teardown-down` 靠临时改文件 + `git checkout`"的
   机制说明）需要再改一版，反映"直接用 `--ignore-served-by`，不碰
   文件"这个更简单的新事实。

跟发现二一样，这条改动不难，但牵涉 `Makefile`/脚本/设计书三处，建议
和发现二的迁移一起做、一起真机验证，不要分两次。
