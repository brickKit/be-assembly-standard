[English](README.md) · [中文](README.zh.md)

# be/py-render

把渲染类的 Python 组件放进一个进程里运行，省内存和 CPU。

## 在项目里使用

这个外壳是所在项目的代码。`shell.members` 里至少有一个成员之后：

```bash
brickkit add be/py-render --yes     # 带入它编译进的成员，嵌在外壳下面
brickkit build be/py-render
brickkit up
```

先做准备：见 [BRICKKIT.zh.md](BRICKKIT.zh.md) 的"部署前准备"。

## 文档

| 想知道 | 读 |
|---|---|
| 它托管什么、不做什么、怎么配置和部署 | [BRICKKIT.zh.md](BRICKKIT.zh.md) |
| 它的成员、配置键和端口 | [component.yaml](component.yaml) |
| 怎么修改它 | [AGENTS.zh.md](AGENTS.zh.md) |

## 开发

在项目根目录（`brickkit.yaml` 所在处）操作；先读 [AGENTS.zh.md](AGENTS.zh.md)。
