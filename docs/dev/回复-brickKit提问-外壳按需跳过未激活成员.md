# 回复：外壳"按需跳过未激活成员"机制确认

> **这份文档是一次性的**：只针对 `BRICKKIT_SERVED_MEMBERS` 这一个细节确认，判断完之后可以直接删掉，跟 `给brickKit的反馈.md` 那份长期文档性质不一样。

## 先确认背景判断是对的

真的去读了我们自己的代码（`shells/go/cmd/shell/main.go`、`shells/python/main.py`、`tools/be-ops/internal/shellconfig`），确认你们的诊断完全准确：

- `tools/be-ops/internal/shellconfig.Gen` 只按 `assembly.yaml` 的 `shell` 字段静态分组，**完全不知道 cascade 的运行时判定**——只要一个组件声明了 `shell: go-core`，不管它当前是不是真的被谁需要，都会原样出现在 `shell-config.json` 里。
- `shells/go/cmd/shell/main.go`（Python 那边 `_build_modules` 结构完全一样）的 `buildModules` 拿到这份列表后，**逐条无条件实例化**——没有任何过滤逻辑。

所以现状确实是：一个 `servedBy` 成员即使被 cascade 判定成"不该跑"，外壳进程完全不知道这件事，代码、数据库连接、迁移逻辑照样会在本地跑起来。这个信息目前我们这边**没有任何办法拿到**（be-ops 自己的生成器不跑 cascade），`BRICKKIT_SERVED_MEMBERS` 提供的是我们现在完全没有的新信息，不是重复造轮子。

## 三个问题的回答

### 1. 值的格式：逗号分隔的版本化服务名够用

确认过 `mdm-customer-1-0-7` 这个格式跟我们项目里已经在用的"服务名/网络别名"规则完全一致——`TestPlatform03` 断言过的既有判据是"变量名不带版本号、**值**带版本号"，真实例子是 `MDM_CUSTOMER_ENDPOINT=http://mdm-customer-1-0-0:8080`：组件 ID 的 `/` 换成 `-`，版本号的 `.` 换成 `-`，拼在一起。这跟你们提议的格式逐字一致，不是我们猜的，是从我们自己现有的断言里直接读出来的。

**够用，而且我们不需要反向解析这个字符串**：我们自己的 `shell-config.json` 里每个模块本来就有干净、结构化的 `componentId`（`mdm/customer`）+`version`（`1.0.7`）字段，我们只需要按同一条规则**自己算出**期望的版本化服务名，去 `BRICKKIT_SERVED_MEMBERS` 这份逗号分隔列表里做一次成员检查——不需要把接收到的字符串反过来拆成 id/version（这条路径本身有歧义：组件 ID 自己也可能带连字符，比如 `infra/iam-casdoor` → `infra-iam-casdoor-1-0-7`，光看这个扁平字符串猜不出哪几段是 scope/name、哪几段是版本号）。所以不需要 JSON 数组，逗号分隔完全够用，我们两边（Go/Python）都是 `strings.Split(",")`/`.split(",")` 一行代码的事。

### 2. 读取时机：能在现有流程里自然接上，不冲突

插入点很明确——`shells/go/cmd/shell/main.go` 的 `buildModules(shellName)`（Python 是 `_build_modules`），现在的逻辑是：

```go
for _, m := range configShell.Modules {
    ctor, ok := moduleRegistry[m.ComponentID]
    // ... 无条件构造 ModuleSpec
}
```

加一层过滤：读 `BRICKKIT_SERVED_MEMBERS`（如果这个变量没设置或者是空字符串，保持现在的行为——全部实例化，完全向后兼容，不是"默认收紧"），按上面第 1 条的规则给 `configShell.Modules` 里每一条自己算一遍期望的版本化服务名，不在这份列表里的直接 `continue`，不追加进 `specs`。

**不会跟现有机制冲突**，原因是这层过滤天然落在两份既有数据的"下游"：`shell-config.json`（哪些模块**理论上**属于这个外壳）和 `shell-env.json`（每个模块**如果跑起来**该拿到什么依赖地址）都完全不用改——`BRICKKIT_SERVED_MEMBERS` 只影响"这次实际要不要把某一条 `New()` 调用真的执行"，跳过的模块自然也就不会被加进 `internal/shell.Run` 后续要跑迁移、要 `Listen` 的那个列表——迁移、DB 连接、健康检查全部跟着一起省掉，不需要在别处单独处理。

### 3. 变量名：不冲突，可以直接用

`BRICKKIT_SERVED_MEMBERS` 跟我们项目现有任何组件的保留变量前缀（`DATABASE_`/`REDIS_`/`MQ_`/`STORAGE_`/`SEARCH_`/`SMTP_`、`*_ENDPOINT` 后缀、`COMPONENT_ID`/`COMPONENT_VERSION`）都不冲突。**顺带说一句不算冲突但值得知会的事**：我们自己 `infra/scripts/test-cross.sh` 里有一个本地脚本变量叫 `BRICKKIT_NET`（找 Docker 网络名用的，纯本地脚本逻辑，从来不会被注入进任何容器）——名字前缀撞了但用途、作用域完全不搭边，不构成真正的冲突，只是提前说明一下，免得将来有人看见两个 `BRICKKIT_` 开头的名字以为有关系。

## 我们这边接下来的动作

这条确认完之后，我们会把"读 `BRICKKIT_SERVED_MEMBERS` 过滤模块列表"这一步，加进 `docs/plans/04b-部署矩阵验证.md` 的 Task 0（我们自己为 `servedBy` 落地做准备的那个任务）里，跟翻译层抽象、`genyaml.Gen` 补 `config:` 块那两件事一起做，不需要单独再开一个任务。
