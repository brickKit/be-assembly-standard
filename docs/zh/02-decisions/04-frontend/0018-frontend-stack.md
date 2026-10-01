[English](../../../en/02-decisions/04-frontend/0018-frontend-stack.md) · [中文](0018-frontend-stack.md)

# 0018 前端技术栈：Vue 3，PC 用 AntDV 和 vxe-table，移动端用 wot-design-uni

## 决策

前端用 Vue 3；移动端用 Uni-app 构建。PC 端用 Ant Design Vue v4，表格用 vxe-table；移动端用 wot-design-uni；图表用 ECharts。两端只共享设计令牌（`packages/design-tokens`），绝不共享组件。

## 理由

业务表单需要双向绑定；PC 用 Vue、移动 H5 用 Uni-app，两端是同一个框架；生成的 Vue 模板结构简单，便于评审。PC 端和移动端是两种产品——一边是密集表格和多级联动的长表单，另一边是卡片列表、扫码和两个审批按钮——共享组件只会得到一个难用的移动端和一个处处受限的 PC 端；何况 AntDV 依赖 DOM，本来也无法共享。

## 挡下什么

- React、Next.js 或任何非 Vue 框架
- 用 Element Plus、Naive UI、Vuetify 或其他 PC 组件库替代 AntDV
- "PC 和移动端统一用一套组件库"
- 在 ECharts 之外再引入第二个图表库

## 何时重新讨论

某个锁定的库停止维护，或页面需要的某项 vxe-table 能力被证实只在商业版里提供时——届时在 `<BeTable>` 背后替换表格引擎（[0019](0019-third-party-ui-only-in-ui-kit.md)），页面不用动。
