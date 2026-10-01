[English](0014-third-party-ui-only-in-ui-kit.md) · [中文](0014-third-party-ui-only-in-ui-kit.zh.md)

# 0014 第三方 UI 组件只能出现在 ui-kit 中

## 决策

第三方 UI 组件只能在 `packages/ui-kit-pc` 和 `packages/ui-kit-mobile` 中 import，由它们以我们自己的名字对外暴露（`<BeTable>` 等）。业务页面只从 ui-kit 引入——绝不直接引入 AntDV、vxe-table 或 wot-design-uni，`<vxe-grid>` 也不例外。只有 AntDV 缺失的能力（甘特图、审批流设计器、富文本、代码编辑器、大屏看板）才能引入其他 UI 库，并且要包在 ui-kit 里、记录在 `ui-kit-pc/README.md` 中。

## 理由

这样替换实现只改一个包，而不是改每个页面——与后端统一走 `be-sdk-*` 是同一个道理。两个库的令牌体系永远对不齐，为了好看混搭组件库只会更难看；真正毁观感的是页面之间间距不一致。

## 挡下什么

- 在页面里写 `import { Table } from 'ant-design-vue'`（或引入任何第三方组件）
- "这个页面用 X 库吧，更好看"
- 在单个页面里覆盖第三方组件的样式
- 没有记录在 `ui-kit-pc/README.md` 里的封装逃生口

## 何时重新讨论

页面直接引入第三方组件这一点永远不重新讨论。能力缺口清单只在 AntDV 确实做不到时才增加。
