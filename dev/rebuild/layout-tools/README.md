# 组件分层用的工具（铺开期间用，做完清理）

`layout-plan.md` 的 L1、L4 用：把一个平铺的 Go 包重排进 `internal/` 的模块包。只改结构，不改行为。

| 工具 | 做什么 |
| --- | --- |
| `restructure/` | 按类型改写（`go/types`，`golang.org/x/tools/go/packages`）：给一张“文件 → 包”的映射，`Module` 的方法改成先收 `*core.Base` 的函数、跨包用到的名字导出、跨包的引用加包名；方法值报出来手接；`-rename` 解决导出后的重名；参数不带名字的方法补 `_` |
| `mvdecl/` | 按语法树把顶层声明（连同注释）从一个文件挪到另一个文件（重排前的预拆） |
| `splitvars.py` | 把一个 `var ( … )` 块拆成每个成员一个 `var`，好分到不同的包 |
| `aliases.py` | 给要用的导入先写上别名（`goimports` 猜不出别名，会选错同名的包） |
| `doccap.py` | 导出改名后，说明注释的第一个词跟着改 |
| `filemap-check.py` | 布局检查的原型（现在由 `infra/scripts/layout-check.py` 取代） |
| `pipelines/` | 每个组件一份可重放的流水线：从分支点 `git reset --hard` 起，预拆 → 改写 → 挪进 `internal/` → 入口 → 集成测试搬进 `itest/` |
| `entry/` | 各组件手写的入口（`module.go`、`services.go`）与 `core.Base` 的样板 |

编译：`cd restructure && go build -o restructure .`、`cd mvdecl && go build -o mvdecl .`（产物不进仓库）；流水线里的路径 `S=` 指向放产物的目录，换会话时改成新的目录。做法与每个组件的额外步骤见 `../layout-plan.md` 的“L1 的结果”。
