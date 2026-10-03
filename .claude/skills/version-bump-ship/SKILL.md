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
reason: <一段话，中文，具体到测试名、改了哪条规则或哪个易错点，
  结尾用"无行为/契约变更。"或明确指出有什么变更>
---
id: <另一个根组件>
reason: ...
```

理由只会在 `bump-version` 的输出里原样打印，不写进任何文件、也不进 tag；它是你写提交信息（§3 第 4 步）和发布说明（§3 第 7 步）时的底稿。发布说明另外手写成一个文件，只写上一个 tag 之后的变更。

## §2：传播版本号

### 2.1 组件与外壳仓库内的文件：`make bump-version`

```bash
make bump-version PLAN=<计划文件>            # dry-run，只打印
make bump-version PLAN=<计划文件> APPLY=1    # 确认后落地
```

它只传播三类文件：下游组件 `component.yaml` 里的依赖版本、外壳 `shell/be/<name>/component.yaml` 的 `shell.members`、外壳 `go.mod` 的 require（主版本变化时连 `/vN` 模块路径后缀一起改）。外壳是子模块，后两类改动落在外壳仓库的工作区里，由 §3 第 9 步在那里提交。**它不碰项目的 `brickkit.yaml`、`deploy.yaml`、`config/`、`AGENTS.md`**，那些归 §4 的 `brickkit upgrade`。

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
6. **推送、发布、打 tag 用一条命令 `make ship`**（在装配仓库根目录跑，只有负责发布的人跑）。发布说明（可直接用 §1 的理由；先写使用方必须做的事，再写新增）写进组件目录**之外**的文件，先预览再真跑：

   ```bash
   make ship DIR=components/<scope>/<name> NOTES=<说明文件> DRY_RUN=1   # 只读检查照做，push / tag / release 只打印
   make ship DIR=components/<scope>/<name> NOTES=<说明文件>
   ```

   它按顺序做、第一处失败即停，每步打印 `▸ 第 n 步 … PASS/FAIL/SKIP`。第 1 步：工作区干净、在 `main`，`git push origin main`（发布检查要求被打 tag 的提交已在远端历史里；绝不强推）。第 2 步（Go 组件）：根 `go.mod` require 的本仓库契约包 `gen/<domain>/<name>/vX` 远端还没有就在 `HEAD` 打注解 tag 并推送；远端已有就校验它与 `HEAD` 的 `gen/<domain>/<name>/` 逐字节一致（已发布的契约包不能改，不一致即 FAIL）。
7. **发布**（`make ship` 第 3 步）：`brickkit release --notes-file <说明文件>`，tag 是 `2.0.0`（不带 `v`），带说明的注解 tag，自动推送（推送失败会自动删掉本地 tag）；随后核对 `git cat-file -t` 是 `tag`、远端有这一行、指向 `HEAD`。
8. **Go 组件额外打第二个 tag**（`make ship` 第 4、5 步；Go 模块代理只认 `v` 前缀，v2+ 的模块路径以 `/v2` 结尾）：`v<版本>` 打在同一个提交上、用同一份说明，核对两个 tag 指向同一提交；然后从外壳的视角真拉一次（临时模块 `go get <模块>@v<版本>` + `go build`，`go list -m all` 里本仓库只有 `…/v2 v<版本>` 和契约包两行；代理刚收到新 tag 时最多重试 3 次、间隔 30 秒）。Python/TS 组件只有第 7 步的 tag，`make ship` 自动跳过这一步。第 6 步打印父仓库要按路径提交的内容和 `git submodule status` 的期望形态。

   停在哪一步就在哪一步处理：**已推送的东西不回滚、不删除、不移动**。修好原因后重跑同一条命令，已经在 `HEAD` 上的 tag 视为完成；已推送却不在 `HEAD` 上的 tag 一律 FAIL——发新版本，不要动它。

9. **外壳**是独立仓库（`brickKit/be-<name>`），在装配仓库里以子模块挂在 `shell/be/<name>/`，和组件一样在**它自己的仓库根目录**收尾：第 1–5 步照做（`bump-version` 改的 `shell.members` / `go.mod` 就在子模块的工作区里；Go 外壳的"测试"是 `go build -o /dev/null ./...`，py-render 是装包后 `import main`），在子模块里提交，然后在装配仓库根目录

   ```bash
   make ship DIR=shell/be/<name> NOTES=<说明文件>
   ```

   tag 是裸的 `<版本>`（如 `1.0.1`），`make ship` 自动跳过契约包、`v` tag 和拉取探针（第 8 步）：外壳不被任何人 import，不打 `v` tag。绝不在装配仓库根目录用 `brickkit release --path shell/be/<name>` 发布，也不在装配仓库打 `be-<name>/<版本>` tag。外壳排在它的全部成员之后；它的子模块指针和成员的指针一起在 §4 第 4 步提交。
10. **构建镜像**：`brickkit build <id>`（已有镜像会跳过，改了代码要重建加 `--force`）。构建失败就停下，不带着没验证的镜像往下走。**镜像不推送**，现阶段全部本地使用。

**工具仓库**（`be-sdk-*`、`be-ops`、`be-acceptance`）不是 brickKit 组件，不走 `brickkit release`：测试通过、提交后 `git tag -a vX.Y.Z -F <说明文件>` 并 `git push origin vX.Y.Z`；Go 工具仓库升到 v2+ 时模块路径要同步加 `/v2`。

## §4：装配仓库收尾

1. **项目侧升级**：对每个发布过的组件（含被级联的下游）：

   ```bash
   brickkit upgrade <id>@<新版本> --dry-run   # 先看会改什么
   brickkit upgrade <id>@<新版本>             # 确认后去掉 --dry-run
   ```

   `upgrade` 会让 `brickkit.yaml`、`deploy.yaml`、`config/` 和 `AGENTS.md` 的受管块保持同步，不要手改这些。infra/authz、infra/iam-casdoor 发版后不用改 `config/vars.yaml`：那几个地址写的是 `$endpoint:` 引用，brickKit 每次生成时按 `brickkit.yaml` 填入当前地址（brickKit v1.2.0 起；`service-hostname-scan` 已退役）。
2. `make gates`、`make version-check`——两个都要绿。
3. **真机验证**：
   - 先聚焦：`brickkit up --focus <id>`，再 `make test-cross ID=<scope>/<name>`（需要过滤时加 `ARGS="-run X"`）。⚠️ `--focus` 会打开本地模式（第一次会把 `deploy.yaml` 复制成 `deploy.local.yaml`），`brickkit up --all` 只清焦点、不关本地模式；之后要改 `deploy.yaml`（比如给外壳挂成员），先 `brickkit local off`，或改完 `brickkit local refresh`，否则改动不生效。
   - 改动跨组件（契约、事件、下游被级联）时，再起全套 `brickkit up`，确认全部 `running (healthy)`，挑一两个与改动直接相关的端点 curl（用状态码确认路由/鉴权链路）。
   - 验证完 `brickkit down`（不常年挂着，见根 `AGENTS.md`）。
4. 提交装配仓库自己的改动：**只 add 你这次动过的路径**（子模块指针——组件和外壳的都算、`brickkit.yaml`、`deploy.yaml`、`config/`、`AGENTS.md` 受管块等），提交信息写文件，`git commit -F`，`git log --oneline -1` 确认后 `git push`。

## 什么时候要停下来问人，不能自己一路推到底

- 任何一步测试/gate 红了，且原因不是"级联同步造成的纯字符串替换失败"这种预期之内的情况——出现任何逻辑性失败都要停。
- `bump-version` 打印的级联看起来不对劲（§2 已经说过）。
- **这批改动里其实混进了真实的行为/契约变更，不是纯粹"跳版本号"级别的事**——这种情况下的审查深度、commit 粒度该走正常开发流程的标准（[七步循环](../../../docs/en/01-conventions/01-development-workflow.md#the-seven-step-loop)的红绿节奏、[人要审什么](../../../docs/en/01-conventions/09-ai-development.md#what-a-human-reviews)），不能套用这个技能"批量发布"的节奏。这个技能的前提是"代码本身已经写完、测过、review 过，剩下的只是发布动作"，不是拿它来掩盖一次真实改动该有的审查。
- 任何需要强推、覆盖或删除已推送 tag 的操作（`brickkit build --force` 重建本地镜像不在此列）。
- §0 找出来的候选里，有哪一条你不确定是不是这次任务范围内该发布的。

## 为什么这个技能管到 commit/push，而不是止步于"改文件"

`bump-version` 工具本身刻意不做 git 操作（见 [01-development-workflow.md](../../../docs/en/01-conventions/01-development-workflow.md#versions) 与 `tools/be-acceptance/README.md`）——理由是"批量改文件"和"批量推到远端"是两类不同风险等级的操作，不该被同一次程序调用捆在一起、跳过复核。这个技能把两者重新接在一起，但接的方式不是"再造一个自动 git 的程序"，而是把**判断力**留在执行者身上：每个 commit message 的措辞、每次"这个级联合不合理""这批改动够不够纯粹到可以走批量发布节奏"，都是逐次判断出来的，不是一份写死的脚本替你判断。这正是这个技能存在的意义——把"步骤该怎么走"记下来，省得每次重新推导，但不代替"这一步该不该继续"本身需要的判断。
