---
name: version-bump-ship
description: 一批组件的真实代码/测试/文档改动做完之后，把版本号传播到全部下游文件、逐组件测试+commit+release（Go 组件双 tag）+构建镜像、用 brickkit upgrade 更新项目并真机验证——覆盖从"确认这次真的动了什么"到"推完收尾"的完整链路，含怎么写 commit message、什么时候该停下来问人而不是一路自动推到底。用户说"发布这批改动""跑一下版本号流程""ship it"，或者你自己刚做完一批组件改动、按项目纪律该发版了，用这个技能。
---

# 版本升级与发布

## 什么时候用这个技能

- 已经做完一批组件的真实代码/测试/文档改动，该发布了
- 用户说"发布""ship it""跑一下版本号流程"
- 接着上次没收尾完的发布工作继续（比如上次做完 `APPLY=1` 但还没逐个组件走完 §3）

纪律：**每个改动都要跳版本号，纯文档/纯测试也不例外。** 一个会话里动过的所有组件，写进**同一份**计划文件，不要每个组件跑一遍。

## 前提

这个技能假设"这次真的动了什么、值得发布"已经清楚。不确定（接手别人开了一半的活、隔了很久回来）就先跑 §0，不要凭记忆。

## §0（可选）：不确定动过哪些组件时，先找出来

```bash
bash infra/scripts/list-unshipped-components.sh
```

列出每个"HEAD 已经领先自己最新 tag"的组件仓库，连同 commit 摘要。列出来的不代表都该现在一起发——可能混着任务范围之外的半成品提交，逐条核对。

## §1：写计划文件

为每个真正要发布的**根**组件写一段理由（下游组件由工具自动算），存到 scratchpad（一次性输入，不提交）：

```
id: <scope>/<name>
version: <可选，精确版本；不写就在当前版本上 patch+1>
reason: <一段话，中文，具体到测试名/pitfall 编号，
  结尾用"无行为/契约变更。"或明确指出有什么变更>
---
id: <另一个根组件>
reason: ...
```

理由会原样进入这个组件的版本历史，认真写。同一段理由也会作为 §3 的发布说明。

## §2：传播版本号

### 2.1 组件与外壳仓库内的文件：`make bump-version`

```bash
make bump-version PLAN=<计划文件>            # dry-run，只打印
make bump-version PLAN=<计划文件> APPLY=1    # 确认后落地
```

它只传播三类文件：下游组件 `component.yaml` 里的依赖版本、外壳 `shell/be/<name>/component.yaml` 的 `shell.members`、外壳 `go.mod` 的 require（主版本变化时连 `/vN` 模块路径后缀一起改）。**它不碰项目的 `brickkit.yaml`、`deploy.yaml`、`config/`、`AGENTS.md`**，那些归 §4 的 `brickkit upgrade`。

dry-run 时重点核对：
- **有没有被拉进来的组件让你意外？** 有的话先停下搞清楚——通常是某个 `dependencies.components` 声明了一条不该有的边，比"赶紧发布"更值得处理。
- **波及范围是不是明显过大？** 也是该停下想的信号。

## §3：逐个组件收尾（先被依赖者，后依赖者）

对每一个：

1. **加上这次真正改的代码/测试/文档文件**——`bump-version` 只改元数据。
2. **跑这个组件自己的测试，必须全绿**（Go：`go test ./backend/... -race -count=1`；Python/TS 用各自命令）。红了就诊断根因，不绕过。
3. 契约变了跑 `make contract-check`。
4. **提交信息写到 scratchpad 文件，用 `git commit -F`，不要内联 `-m`**——长文本/双引号可能让 commit 静默失败，之后的 tag 会打在旧提交上（真实吃过的亏）。结构：一句话概括，空行，理由（搬 §1 那段），空行，署名行。
5. `git commit -F <消息文件>`，**`git log --oneline -1` 确认 commit 真的落了**，再发布。
6. 推送当前分支（发布检查要求被打 tag 的提交已在远端历史里）：`git push origin main`。
7. **发布**：把发布说明（可直接用 §1 的理由）写进一个文件，在组件目录里：

   ```bash
   brickkit release --notes-file <说明文件>
   ```

   tag 是 `2.0.0`（不带 `v`），带说明的注解 tag，自动推送；推送失败会自动删掉本地 tag。
8. **Go 组件额外打第二个 tag**（Go 模块代理只认 `v` 前缀；v2+ 的模块路径以 `/v2` 结尾），打在同一个提交上、用同一份说明：

   ```bash
   git tag -a v<版本> -F <说明文件> && git push origin v<版本>
   ```

   Python/TS 组件只要第 7 步的 tag。
9. **外壳**住在装配仓库里（`shell/be/<name>/`），不是独立仓库：先把外壳目录的改动提交并推送，再在装配仓库根目录发布：

   ```bash
   brickkit release --path shell/be/<name> --notes-file <说明文件>
   ```

   tag 形如 `be-<name>/<版本>`（子目录组件）；用 `brickkit release --help` 核对。外壳的 Go 模块若也要被引用，同样补 `v` 前缀 tag。
10. **构建镜像**：`brickkit build <id>`（已有镜像会跳过，改了代码要重建加 `--force`）。构建失败就停下，不带着没验证的镜像往下走。**镜像不推送**，现阶段全部本地使用。

**工具仓库**（`be-sdk-*`、`be-ops`、`be-acceptance`）不是 brickKit 组件，不走 `brickkit release`：测试通过、提交后 `git tag -a vX.Y.Z -F <说明文件>` 并 `git push origin vX.Y.Z`；Go 工具仓库升到 v2+ 时模块路径要同步加 `/v2`。

## §4：装配仓库收尾

1. **项目侧升级**：对每个发布过的组件（含被级联的下游）：

   ```bash
   brickkit upgrade <id>@<新版本> --dry-run   # 先看会改什么
   brickkit upgrade <id>@<新版本>             # 确认后去掉 --dry-run
   ```

   `upgrade` 会让 `brickkit.yaml`、`deploy.yaml`、`config/` 和 `AGENTS.md` 的受管块保持同步，不要手改这些。
2. `make gates`、`make version-check`——两个都要绿。
3. **真机验证**：
   - 先聚焦：`brickkit up --focus <id>`，再 `make test-cross ID=<scope>/<name>`（需要过滤时加 `ARGS="-run X"`）。
   - 改动跨组件（契约、事件、下游被级联）时，再起全套 `brickkit up`，确认全部 `running (healthy)`，挑一两个与改动直接相关的端点 curl（用状态码确认路由/鉴权链路）。
   - 验证完 `brickkit down`（不常年挂着，见根 `AGENTS.md`）。
4. 提交装配仓库自己的改动：**只 add 你这次动过的路径**（子模块指针、`brickkit.yaml`、`deploy.yaml`、`config/`、`AGENTS.md` 受管块等），提交信息写文件，`git commit -F`，`git log --oneline -1` 确认后 `git push`。

## 什么时候要停下来问人，不能自己一路推到底

- 任何一步测试/gate 红了，且原因不是"级联同步造成的纯字符串替换失败"这种预期之内的情况——出现任何逻辑性失败都要停。
- `bump-version` 打印的级联看起来不对劲（§2 已经说过）。
- **这批改动里其实混进了真实的行为/契约变更，不是纯粹"跳版本号"级别的事**——这种情况下的审查深度、commit 粒度该走正常开发流程的标准（SOP-W 红绿循环、W-6 人工评审五件套），不能套用这个技能"批量发布"的节奏。这个技能的前提是"代码本身已经写完、测过、review 过，剩下的只是发布动作"，不是拿它来掩盖一次真实改动该有的审查。
- 任何需要强推、覆盖或删除已推送 tag 的操作（`brickkit build --force` 重建本地镜像不在此列）。
- §0 找出来的候选里，有哪一条你不确定是不是这次任务范围内该发布的。

## 为什么这个技能管到 commit/push，而不是止步于"改文件"

`bump-version` 工具本身刻意不做 git 操作（见 `docs/standards/en/00-master-guide.md` SOP-W-11）——理由是"批量改文件"和"批量推到远端"是两类不同风险等级的操作，不该被同一次程序调用捆在一起、跳过复核。这个技能把两者重新接在一起，但接的方式不是"再造一个自动 git 的程序"，而是把**判断力**留在执行者身上：每个 commit message 的措辞、每次"这个级联合不合理""这批改动够不够纯粹到可以走批量发布节奏"，都是逐次判断出来的，不是一份写死的脚本替你判断。这正是这个技能存在的意义——把"步骤该怎么走"记下来，省得每次重新推导，但不代替"这一步该不该继续"本身需要的判断。
