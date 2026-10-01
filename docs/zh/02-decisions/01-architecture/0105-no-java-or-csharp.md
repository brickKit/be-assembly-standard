[English](../../../en/02-decisions/01-architecture/0105-no-java-or-csharp.md) · [中文](0105-no-java-or-csharp.md)

# 0105 不用 Java / C#

## 决策

后端组件用 Go 或 Python 编写；TypeScript 只用于移动端 BFF 和前端。不用 Java、Kotlin、C# 或其他 JVM / .NET 语言编写任何组件。

## 理由

客户在自己的一台机器上部署整个系统，每个组件一个 JVM 或 CLR 的内存与启动开销与此直接冲突。每种语言还需要各自的 SDK、外壳启动器和技术栈锁定（[0103](0103-locked-stack-per-language.md)）；多一种语言，用它写的每个组件都要多出这份工作。

## 挡下什么

- "这个组件用 Spring Boot / .NET 写吧，它有更好的 X 库"
- Kotlin、Scala 或其他 JVM 语言
- 为某一个组件引入第四种后端语言

## 何时重新讨论

部署目标不再是客户的单台机器，而且某项必需能力只存在于那个生态时。即便如此，也要先有 SDK、外壳启动器和技术栈锁定行，这门语言才能进来，而不是随某一个组件进来。
