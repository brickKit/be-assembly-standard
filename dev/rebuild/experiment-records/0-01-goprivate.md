# 0-01 GOPRIVATE 让 Go 绕过公共代理与校验和库

## 1. 结论

**部分通过**。设了 `GOPRIVATE=github.com/brickKit/*` 后，Go 不再经公共代理（proxy.golang.org）取模块、也不再查校验和库（sum.golang.org），直接从 GitHub 的 Git 仓库取：这是 A107 “版本号重新使用”所依赖的机制，成立。还差的一半——**删掉旧标签、用同一个版本号打新提交之后，取到的是新代码**——要等第 1 步真正删标签时才能验证，验证方法写在第 7 节。

另外：先前对话里说“erp-sales 的 v1.0.23–v1.0.26 在 GitHub 上已删、代理里还在”是误判（查标签时输出被 `cut -c1-200` 截断）。用 `git ls-remote` 核对，这 10 个仓库在代理里**没有**任何 GitHub 上已不存在的版本。A107 的结论不受影响：代理与校验和库会永久记住今后删掉的版本号。

## 2. 测了什么、为什么

计划第 0 步第一项。A107 决定删掉复用仓库的旧标签、版本号从头算；用过的号（例如 `be-sdk-go` 的 v0.1.0–v0.5.0）会被重新使用。公共代理和校验和库永久保存用过的版本，默认设置下 Go 会取到旧代码或报校验失败。要确认 `GOPRIVATE` 能让我们的构建完全绕开这两者。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 机器 | Linux 7.0.0-38-generic，12 核，14 GiB |
| Go | go1.26.0 linux/amd64 |
| 模块 | `github.com/brickKit/be-sdk-go`（v0.4.0、v0.5.0，旧版本，只读） |
| 模块缓存 | 每条命令一个全新的 `GOMODCACHE`（草稿目录，用完删除） |

## 4. 怎样跑

1. 不设 `GOPRIVATE`、`GOPROXY=off`，下载 `be-sdk-go@v0.5.0`：看默认设置是否只能经代理取。
2. 设 `GOPRIVATE`、`GOPROXY=off`、`GOSUMDB=sum.invalid`（一个无效的校验和库），下载同一版本：能成功就说明既没经代理、也没查校验和库。
3. 不设 `GOPRIVATE`、`GOSUMDB=sum.invalid`，下载 `v0.4.0`：对照，证明默认设置会查校验和库。
4. 打印设了 `GOPRIVATE` 后的 `GONOPROXY`、`GONOSUMDB`。
5. 对 10 个仓库，比较代理的版本列表与 GitHub 的标签，找“代理有、GitHub 没有”的版本。

完整命令与输出：`experiment-data/0-01/run1.txt`。

## 5. 结果

| 步 | 设置 | 结果 | 说明 |
| --- | --- | --- | --- |
| 1 | 默认，`GOPROXY=off` | 失败：`module lookup disabled by GOPROXY=off` | 默认只经代理取 |
| 2 | `GOPRIVATE`，`GOPROXY=off`，无效 `GOSUMDB` | 成功；`Origin` 是 `VCS: git`、`URL: https://github.com/brickKit/be-sdk-go`、`Ref: refs/tags/v0.5.0` | 直接从 Git 取，没有经代理，也没有查校验和库 |
| 3 | 默认，无效 `GOSUMDB` | 失败：`verifying go.mod: invalid GOSUMDB` | 默认会查校验和库 |
| 4 | `GOPRIVATE` 的派生值 | `GONOPROXY`、`GONOSUMDB` 都等于 `github.com/brickKit/*` | `GOPRIVATE` 同时关掉两者 |
| 5 | 代理有、GitHub 没有的版本 | 10 个仓库全部为空 | 目前没有已删除的旧版本留在代理里 |

## 6. 观察与异常

- **Go 没有“发布”这一步**：我们从没主动往 golang.org 发布过；但公共代理在任何人（包括我们自己以前默认设置下的构建）第一次取某个公开模块版本时，自动抓取并永久缓存，校验和库同时记下它的哈希。运行 2 用真实的模块路径查到：代理列出 `be-sdk-go` 的 v0.1.0–v0.5.0、`erp-sales` 的 v1.0.0–v1.0.26 等；校验和库有 `github.com/brickKit/be-sdk-go v0.1.0 h1:3WdZ…`（`experiment-data/0-01/run2.txt`）。
- 运行 1 查代理时把路径转义写成了 `!brick!kit`，它解码成 `github.com/BrickKit/…`（大写 B），不是我们的模块路径（小写 b，转义为 `brick!kit`）。运行 2 用正确的路径重做，结论相同；大写的那条路径也被缓存过（GitHub 不区分大小写，某次构建用大写地址取过）。

- 第一次查标签时用了 `cut -c1-200` 截断输出，看漏了 erp-sales 的 v1.0.23–v1.0.26，误以为它们已被删除；已更正（记忆 `project_rebuild_repo_reuse` 也改了）。以后核对版本列表一律看全量输出，不截断。
- `GOPRIVATE` 只管 Go 怎样取模块，**不管本机的模块缓存**：缓存里已有旧的同号版本时，Go 直接用缓存，并按本地 `go.sum` 校验。所以第 1 步删标签后必须清空本机缓存（A107 已写）；镜像构建每次从空缓存开始，不受影响。

## 7. 影响

- A107 的机制成立，不用改设计。
- **第 1 步删标签、重新打 v0.1.0 之后补验**：在全新的 `GOMODCACHE` 里，
  1. 设 `GOPRIVATE` 取 `be-sdk-go@v0.1.0`，`Origin.Hash` 应当是新的提交；
  2. 不设 `GOPRIVATE` 再取一次，预期取到代理里的旧内容，或报校验和不匹配——这是不设 `GOPRIVATE` 的症状（根 `AGENTS.md` 易错点已写）。
  补验结果写进本记录的第 5 节。

## 8. 原始数据

`dev/rebuild/experiment-data/0-01/run1.txt`
