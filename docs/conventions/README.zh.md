[English](README.md) · [中文](README.zh.md)

# 项目约定

本项目每个组件、外壳和工具都遵守的规则。brickKit 的 skill（`.claude/skills/brickkit-*`）讲的是任何项目都适用的平台用法；这里讲本项目怎么用它。两者有重叠是有意的：读者不同。

## 文件

| 文件 | 什么时候读 |
|---|---|
| [configuration.zh.md](configuration.zh.md) | 给配置键起名；接 PostgreSQL、NATS、对象存储、authz、iam；填 `config/` |
| [development-workflow.zh.md](development-workflow.zh.md) | 开始做一个组件；安排步骤顺序；真机运行；升版本号；发布 |
| [backend.zh.md](backend.zh.md) | 写 Go 或 Python 后端代码：技术栈、模块入口、`rt`、权限、数据范围、调用其他组件、SQL、事件、健康检查 |
| [frontend.zh.md](frontend.zh.md) | 写前端代码：技术栈、设计 token、ui-kit、页面模板、PC 骨架、偏好、功能与权限、国际化 |
| [testing.zh.md](testing.zh.md) | 决定写哪种测试、放哪一层；跑测试；被一个红测试卡住 |
| [data.zh.md](data.zh.md) | 设计种子数据或测试数据；依赖方缺你要的数据或能力 |
| [registries.zh.md](registries.zh.md) | 选端口、schema、数据库角色或权限键 |
| [reference-implementations.zh.md](reference-implementations.zh.md) | 设计业务逻辑；同一个功能找到了几种都合理的做法 |
| [ai-development.zh.md](ai-development.zh.md) | 要不要用设计模式；文件、函数、会话该多大；人要审什么；重写还是打补丁 |
| [documentation.zh.md](documentation.zh.md) | 写、拆、翻译文档；组件文档；决策记录 |
| [../seed-data.zh.md](../seed-data.zh.md) | 找演示数据和测试账号 |

## 与其他文档的关系

- **决策**说明项目为什么是现在这个样子、哪些事不要再提：[../decisions/README.zh.md](../decisions/README.zh.md)。这里的规则与某条决策矛盾时，以决策为准，回来改这里。
- **组件自己的规则**写在它的 `AGENTS.md` 和 `docs/design.md` 里，只补充该组件特有的内容，从不重复这里的规则。
- **平台行为**（命令、参数、错误码）归 brickKit：看 skill 和 `brickkit <命令> --help`。

## 这里都没有时

这些文件是项目级规则的全集。在断定"没有规则管这件事"之前，先把每个文件的标题过一遍；再查决策索引；最后看组件自己的 `AGENTS.md`。
