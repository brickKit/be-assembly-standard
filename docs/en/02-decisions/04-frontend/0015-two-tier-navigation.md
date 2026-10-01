[English](0015-two-tier-navigation.md) · [中文](../../../zh/02-decisions/04-frontend/0015-two-tier-navigation.md)

# 0015 PC navigation is two-tier, console style, with in-app tabs

## Decision

The PC skeleton is a cloud-console layout: a service selector (components grouped by domain, with search, recents and stars), a favourites bar, a flat menu of 3–5 pages inside each component, in-app tabs across components, a ⌘K command palette, and an organisation / legal-entity switcher where a console has a region switcher. Business pages start from ui-kit page templates — `<BeListPage>`, `<BeDetailPage>`, `<BeFormPage>`, `<BeSettingsPage>` — and fill their slots.

## Why

The menu is aggregated from each component's `assembly.yaml` when the project is generated, and every customer installs a different set of components, so a multi-level tree would have a different shape for every customer and no central table to reorder. Two tiers map onto component boundaries and look the same for everyone. In-app tabs stay because an unsaved ERP form is lost when the browser refreshes. Page templates keep pages generated in batches visually consistent.

## What this rules out

- A left-hand multi-level tree menu (domain → component → page)
- Collapsible or nested menus inside a component
- Dropping in-app tabs in favour of browser tabs
- vue-vben-admin, antdv-pro or another admin template as a dependency — read their layout, routing and request code, don't install them
- A central, hand-edited menu table
- Starting a page from a blank `<div>` and laying it out by hand

Hiding a component from the selector is a convenience, not security: the backend still checks every request.

## Revisit only if

A component outgrows a flat menu of a handful of pages — split the component before deepening the menu.
