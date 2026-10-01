[English](../../../en/02-decisions/04-frontend/0405-design-tokens-are-css-variables.md) · [中文](0405-design-tokens-are-css-variables.md)

# 0405 设计令牌是运行时 CSS 变量

## 决策

`packages/design-tokens` 把每个令牌定义成可在运行时改写的 CSS 自定义属性——绝不写成编译进 bundle 的 TypeScript 常量。ui-kit 用这些令牌同时驱动 AntDV 主题和 vxe-table 主题；页面里从不硬编码颜色、尺寸或间距。

## 理由

亮 / 暗模式和密度都要在应用运行时切换令牌。编译进 bundle 的常量切换不了，事后再改就要动每一个已经写好的页面。

## 挡下什么

- 把令牌导出成 TS / JS 常量，或只在构建期解析的 Sass 变量
- 在页面里硬编码十六进制颜色或像素间距
- 每个 UI 库各用一套互不相通的主题

## 何时重新讨论

永不重新讨论。
