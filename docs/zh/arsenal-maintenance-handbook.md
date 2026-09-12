# 军火库维护手册

> 给**开发者**看：怎么把组件源码接进本仓库、日常怎么聚焦到几个组件、提交前要注意什么。
> 部署相关请看 [`docs/ops/部署手册.md`](../ops/部署手册.md)；踩坑记录见 [`docs/dev/field-tested-pitfalls-log.md`](dev/field-tested-pitfalls-log.md)。

## 新机器上手三步

```bash
git clone --recurse-submodules git@github.com:brickKit/be-assembly-standard.git
cd be-assembly-standard
git config core.hooksPath .githooks     # ⚠️ 这一条不随仓库分发，必须手动跑
cp .env.example .env                    # 填上真值
make up                                 # 拉起基础资源
```

已经 clone 过但漏了 submodule：`git submodule update --init --recursive`

## 日常开发循环（本地聚焦）

```bash
# 1. 只留你要动的那几个组件
#    改 brickkit.yaml：给不相关的顶层组件写 enabled: false
brickkit sync            # 其余源码收进 components/.archived/，IDE 与 grep 都清爽了

# 2. 开发、测试……

# 3. 提交前还原结构（否则 pre-commit 会拦你）
make arsenal-restore     # 把 enabled 与目录结构还原到与 brickkit.yaml 一致
git status               # 复查
git commit -m "..."
```

## 三条禁令

| 禁令 | 为什么 |
|---|---|
| **`brickkit remove` 前必须先 commit & push** | 它会**连同已归档的源码目录一起删除**（§9.4.2）。submodule 目录里有未 push 的改动时，这是数据丢失 |
| **不许改已分配的端口与 schema** | 端口册见 [`registry/README.md`](../../registry/README.md)；gRPC 端口没有事后补救手段 |
| **不许在 Fork 件里改 `metadata.id` 或 `version`** | 改了之后所有依赖方拿到的 `*_ENDPOINT` **整个消失**——平台注入的变量名是从组件 ID 推导的。整条 Fork 机制当场垮掉（§3.4.1） |

## 找不到源码时

先看 `components/.archived/`——它以 `.` 开头，文件管理器默认隐藏（§9.4.2）。

## 加一个组件到军火库

见总纲 §3.5「仓库创建检查点的标准动作」。三步：建目录 → 停下叫人建仓库 → `git init` + push + `git submodule add`。

## pre-commit 闸门怎么工作

`.githooks/pre-commit` 调 `infra/scripts/arsenal.sh check`。它的判据：

1. `components/` 还没被跟踪（默认状态）→ 零成本放行
2. 处于合并冲突中 → 放行 + 警告
3. `brickkit` 不在 PATH → 放行 + 警告
4. **`brickkit restore --help` 能跑通就直接委派给官方命令**（`brickkit restore --check` / `brickkit restore`）——**这是当前实际会走的路径**，本地兜底实现只在官方命令不可用时才接管
5. 兜底实现：从 `brickkit up --dry-run` 算出「这次该跑哪些组件」，逐个比对 `components/<id>` 与 `components/.archived/<id>` 两处是否只有一处有源码

拦下时的三条出路：`make arsenal-restore`（本地聚焦忘了还原）/ 把 `enabled: false` 一起提交（意图声明）/ `git commit --no-verify`（不推荐）。
