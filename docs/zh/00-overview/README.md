# 总览

本目录向客户与新读者介绍 BrickEnterprise：产品是什么、有哪些组件、怎样选择与组合、怎样替换与停用。

## 两条阅读路线

**向客户介绍**：

1. [产品与设计原则](01-product.md)：产品解决什么问题，装配全景，规模与对客户说明的口径。
2. [选择方式、关系与客户组合](04-selection.md)：哪些组件互相替换、哪些并存、哪些协作，典型组合需要什么、缺了会怎样。
3. 客户对某个选择点感兴趣时，进入对应的[选型说明](guides/README.md)。
4. 需要完整目录时打开[组件货架](03-catalog.md)。

**设计与开发**：

1. [产品与设计原则](01-product.md)，尤其是“两条不变的原则”。
2. [领域与组件边界](02-domains-and-boundaries.md)：边界怎样确定，三个枢纽与依赖方向，边界结论与数据归属。
3. [组件货架](03-catalog.md)与各组件的边界卡。
4. [选配变更、替换与停用](05-change-and-retirement.md)：所有选择点共用的变更协议。
5. 机制的完整设计在[协议与安全文档](../06-protocols/README.md)中，跨组件的术语在[术语表](07-glossary.md)；底层选择在 [04-foundations](../04-foundations/README.md)，规范在 [01-conventions](../01-conventions/README.md)。
6. 开发的范围与顺序见[路线](06-roadmap.md)。

## 本目录的文件

| 文件 | 回答什么 |
| --- | --- |
| [01-product.md](01-product.md) | 产品、装配全景、原则、规模、对客户说明的口径 |
| [02-domains-and-boundaries.md](02-domains-and-boundaries.md) | 四种边界、边界卡与五项检查、三个枢纽、边界结论、数据归属、伙伴、库存与仓储、销售类型 |
| [03-catalog.md](03-catalog.md) | 全部组件的身份、能力与范围；新增与退役的身份；当前重建范围 |
| [04-selection.md](04-selection.md) | 五种选择方式、能力分图、选择点一览、客户组合与闭包、客户故事 |
| [05-change-and-retirement.md](05-change-and-retirement.md) | 替换的四种路径、从候选到生效、失败恢复、组件的停用与退出 |
| [06-roadmap.md](06-roadmap.md) | 三条范围线、开发的五步、设计与正式文档、问题反馈、项目完成后的整体总结 |
| [07-glossary.md](07-glossary.md) | 跨组件的术语：业务叫法、定义、代码标识符、所属组件与所在文档 |
| [08-system-views.md](08-system-views.md) | 系统上下文、一套部署里的容器、上下文地图、关键流程的时序图在哪里 |
| [09-component-index.md](09-component-index.md) | 由工具生成：每个组件的边界卡、仓库文档、实现版本、双向的必需依赖；已重建组件的事件拓扑 |
| [guides/](guides/README.md) | 各选择点的方案比较 |
