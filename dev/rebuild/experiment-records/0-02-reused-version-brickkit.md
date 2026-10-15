# 0-02 同一个版本号删掉重发：BrickKit 能发，但两层缓存会静默给出旧内容

## 1. 结论

**通过，但发现一个必须处理的陷阱**。`brickkit release` 可以在删掉旧标签之后用同一个版本号再发布一次。可是使用方那边有两层缓存都按“版本不可变”工作，不会去发现标签已经指向了新提交：

| 缓存 | 位置 | 重发之后拿到的 |
| --- | --- | --- |
| 项目的清单缓存 | 项目的 `.brickkit/manifests/<id>/<版本>/` | 旧内容 |
| 用户级的裸仓库缓存 | `~/.cache/brickkit/repos/<主机>/<路径>.git` | 旧内容：标签已存在就不再联网；即使手工 `git fetch`，Git 也拒绝移动已有标签（`would clobber existing tag`） |
| 两层都清空 | — | 新内容 |

所以 A107 的“删旧标签、版本号从头算”要多一步：删标签之后，**清空用户级的 BrickKit 仓库缓存与每个项目的 `.brickkit/` 缓存**，否则新发的 0.x 版本可能被旧的同号内容静默顶替。这条已写进第 1 步的动作清单与开发流程（见第 7 节）。

## 2. 测了什么、为什么

计划第 0 步第二项：“BrickKit 的发布命令能发一个已删除过的旧版本号”。A107 删掉复用仓库的旧标签，版本号从头算；对 Go 已有 0-01，这里看 BrickKit 自己的发布与安装。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.4.1 |
| 组件 | `brickkit new demo/hello --path work` 生成的骨架，只改 `metadata.description` 区分两次发布 |
| 远端 | 本机的裸仓库 `remotes/demo-hello.git`（不碰 GitHub） |
| 使用方项目 | `brickkit init consumer`，加一个 Git 安装源 `baseUrl: file://<草稿>/remotes/` |
| 用户级缓存 | `XDG_CACHE_HOME` 指到草稿目录，不污染本机真实的缓存 |

## 4. 怎样跑

1. 组件描述写 `FIRST content of 0.1.0`，提交、推送，`brickkit release` 发 0.1.0。
2. 使用方 `brickkit add demo/hello@0.1.0`，确认拿到 FIRST。
3. 组件仓库删掉本地与远端的标签 0.1.0；描述改成 `SECOND content of 0.1.0`，提交、推送，再 `brickkit release`。
4. 使用方分四种情况取 0.1.0：A1 同一项目 `fetch`；A2 同一项目 `sync`；B 新项目、同一用户级缓存；C 新项目、全新的用户级缓存。
5. 对用户级裸仓库手工 `git fetch` 全部标签，看 Git 的反应。

完整输出：`experiment-data/0-02/run1.txt`。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| 第二次 `brickkit release` 0.1.0 | 成功：`✅ Released demo/hello@0.1.0: tag 0.1.0 pushed`；远端标签从 `0cc6908f` 变成 `077a8709` |
| A1 同一项目 `fetch` | FIRST（旧） |
| A2 同一项目 `sync` | FIRST（旧） |
| B 新项目、同一用户级缓存 | FIRST（旧）；裸仓库里的标签仍是 `0cc6908f` |
| C 新项目、全新的用户级缓存 | SECOND（新） |
| 手工 `git fetch` 标签 | `! [rejected] 0.1.0 -> 0.1.0 (would clobber existing tag)` |

## 6. 观察与异常

- 与 BrickKit 文档一致：取清单的顺序是项目缓存 → 用户级裸仓库里的标签 → 没有这个标签才 `git fetch --tags` → 没有仓库才克隆（`03-component-guide/10-git-distribution`）。这是“版本不可变”的设计，不算 BrickKit 的缺陷：只有违反这条前提（移动或重用标签）时才出问题。
- 没有报错、没有警告：旧内容被当成新版本静默使用。对本项目来说最危险的是镜像——构建跳过已有版本的镜像（根 `AGENTS.md` 易错点），所以本机旧镜像也必须删（A107 已写）。
- BrickKit 没有清缓存的命令（`brickkit help` 列出的命令里没有）；清理要直接删目录。

## 7. 影响

- **第 1 步的动作清单加两项**：删旧标签之后，删除 `~/.cache/brickkit/repos/github.com/brickKit/`；删除本项目与组件工作台的 `.brickkit/manifests/` 与 `.brickkit/artifacts/`。连同 0-01 的 Go 模块缓存、本机旧镜像，一共四种缓存。
- **开发流程**：A107 那条补一句“删标签后清空 BrickKit 的两层缓存”（正式文档 `10-development-workflow.md` 的版本一节）。
- **给 BrickKit 的功能请求（低优先级）**：可选的“核对缓存里的标签与远端是否一致、不一致就警告”，以及清缓存的命令；写进 `brickkit-feedback/rebuild.md` 的 FRR-002。只有移动标签的人会碰到，所以是低优先级。

## 8. 原始数据

`dev/rebuild/experiment-data/0-02/run1.txt`
