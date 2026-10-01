[English](0014-third-party-ui-only-in-ui-kit.md) · [中文](../../../zh/02-decisions/04-frontend/0014-third-party-ui-only-in-ui-kit.md)

# 0014 Third-party UI components appear only inside ui-kit

## Decision

Third-party UI components are imported only inside `packages/ui-kit-pc` and `packages/ui-kit-mobile`, which expose them under our own names (`<BeTable>` and so on). Business pages import from ui-kit only — never from AntDV, vxe-table or wot-design-uni directly, `<vxe-grid>` included. Another UI library comes in only for a capability AntDV lacks (Gantt chart, approval-flow designer, rich text, code editor, large-screen dashboard), wrapped in ui-kit and recorded in `ui-kit-pc/README.md`.

## Why

Swapping an implementation then changes one package instead of every page — the same reason the backend goes through `be-sdk-*`. Two libraries' token systems never line up, so mixing libraries for looks makes pages look worse; inconsistent spacing between pages is what actually spoils the look.

## What this rules out

- `import { Table } from 'ant-design-vue'` (or any third-party component) in a page
- "Use library X for this page, it looks nicer"
- Per-page style overrides of third-party components
- A wrapper escape hatch that is not recorded in `ui-kit-pc/README.md`

## Revisit only if

Never for direct imports in pages. The list of capability gaps grows only when AntDV genuinely cannot do the thing.
