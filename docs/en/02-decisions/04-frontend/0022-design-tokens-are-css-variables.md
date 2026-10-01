[English](0022-design-tokens-are-css-variables.md) · [中文](../../../zh/02-decisions/04-frontend/0022-design-tokens-are-css-variables.md)

# 0022 Design tokens are runtime CSS variables

## Decision

`packages/design-tokens` defines every token as a CSS custom property that can be rewritten at runtime — never as TypeScript constants compiled into the bundle. ui-kit drives both the AntDV theme and the vxe-table theme from these tokens, and pages never hard-code a colour, size or spacing.

## Why

Light / dark mode and density both switch tokens while the app runs. A constant compiled into the bundle cannot switch, and changing that later means touching every page already written.

## What this rules out

- Exporting tokens as TS / JS constants, or as build-time-only Sass variables
- Hard-coded hex colours or pixel spacing in a page
- A separate, unconnected theme for each UI library

## Revisit only if

Never.
