[English](0404-four-user-preferences.md) · [中文](../../../zh/02-decisions/04-frontend/0404-four-user-preferences.md)

# 0404 Users own four preferences

## Decision

A user sets exactly four things: favourite components, light / dark / follow system, density, and language — plus table column state (width, order, hidden columns), kept locally and not synced. Primary colour, logo, product name, watermark and grayscale mode are assembly-time configuration of the deployment. There is no layout-mode switch.

## Why

Every display option a user can switch multiplies the pages that have to be tested; no real customer switches layout. Favourites and column state are what ERP users actually use every day, and branding is company policy, not a personal choice.

## What this rules out

- "Let users choose sidebar / top bar / mixed layout"
- A per-user theme colour or logo
- Copying an admin template's settings panel (rounded corners, animations, footer, breadcrumb toggles)
- A new backend service or repository just to store preferences

## Revisit only if

Several real customers ask for the same additional preference.
