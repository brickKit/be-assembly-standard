[English](../../../en/02-decisions/01-architecture/0105-any-language-one-protocol.md) · [中文](0105-any-language-one-protocol.md)

# 0105 任何语言，一份协议

**状态**：为 3.0.0 重写（取消 Java / C# 禁令）；已决定，随 3.0.0 统一升级落地。

## 决策

组件可以用任何语言编写。让它成为本项目成员的，是语言中立的组件协议（[0109](0109-language-neutral-component-protocol.md)），而不是它的语言：

| 组件所用语言 | 进项目、单独运行 | 进外壳 |
|---|---|---|
| 有官方 SDK 的语言（Go、Python、TypeScript） | 当前版本的一致性报告全绿 | 该 SDK 还要有外壳启动器（今天是 Go 和 Python，见 [0108](0108-one-repository-per-shell.md)） |
| 其他任何语言 | 当前版本的一致性报告全绿 | 要等这门语言有了官方 SDK 和外壳启动器 |

用其他语言写的组件，在 `assembly.yaml` 里写上 `protocol` 和 `language`，自己选栈并记进 `AGENTS.md`（[0103](0103-locked-stack-per-language.md)），评审时按协议的 INTERNAL 规则逐条核对，因为扫源码的门禁只认官方语言。

**是提醒，不是禁令。** JVM 或 CLR 进程常驻约 256–512 MiB，冷启动以秒计。用这类语言写的组件，要在 `BRICKKIT.md` 的 "Before you deploy" 一节写明，并相应调大 `healthCheck.startPeriodSeconds` 和内存请求。

## 理由

组件本来就应当可替换、能按需求选用合适的生态。住在某一门语言 SDK 里的规则，没法拿去检查用另一门语言写的组件；对容器做黑盒测试，才能让每一门语言守同一套规则。单机内存预算是真实的约束，但它是客户应当看得见的部署取舍，不是禁止一门语言的理由。外壳是一个进程、一个运行时，所以合并只限于有 SDK 和启动器的语言；这个限制只多花内存，从不影响正确性。

## 挡下什么

- 把不同语言的成员合进一个进程：外壳里的 sidecar、嵌入式运行时、Go 外壳里装 Python 成员
- 任何语言的组件，当前版本和镜像没有全绿的一致性报告
- 为某一个组件的语言在官方 SDK 里加特例
- JVM 或 CLR 组件的 `BRICKKIT.md` 对内存和启动开销只字不提
- 在 [0103](0103-locked-stack-per-language.md) 为一门新语言加列之前，就给它加第二个组件

## 何时重新讨论

协议表达不了某个语言生态必需的能力，或者太多要紧的规则只能作为套件测不到的 INTERNAL 规则来守时。

完整分析：[02-languages-and-component-protocol.md，选择](../../04-foundations/02-languages-and-component-protocol.md#选择)。
