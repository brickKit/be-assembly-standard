[English](0018-frontend-stack.md) · [中文](../../../zh/02-decisions/04-frontend/0018-frontend-stack.md)

# 0018 Frontend stack: Vue 3, AntDV and vxe-table on PC, wot-design-uni on mobile

## Decision

The frontend is Vue 3; the mobile app is built with Uni-app. PC uses Ant Design Vue v4 with vxe-table for tables; mobile uses wot-design-uni; charts use ECharts. The two ends share only the design tokens (`packages/design-tokens`), never components.

## Why

Business forms need two-way binding, Vue on PC and Uni-app on mobile H5 keep both ends in one framework, and generated Vue templates stay structurally plain enough to review. PC and mobile are different products — dense tables and long cascading forms on one side, card lists, scanning and two approval buttons on the other — so shared components would give a poor mobile app and a constrained PC app; AntDV's dependence on the DOM rules sharing out anyway.

## What this rules out

- React, Next.js, or any non-Vue framework
- Element Plus, Naive UI, Vuetify or another PC component library instead of AntDV
- "Unify the component library across PC and mobile"
- A second charting library alongside ECharts

## Revisit only if

A locked library is abandoned, or a vxe-table capability the pages need turns out to be commercial-only — then the table engine is replaced behind `<BeTable>` ([0019](0019-third-party-ui-only-in-ui-kit.md)) without touching pages.
