[English](03-frontend.md) · [中文](../../zh/01-conventions/03-frontend.md)

# Frontend conventions

Rules for every frontend component in this project: every member of the frontend slot family, not only `frontend/standard`. A frontend never enters a shell; its constraints come from elsewhere: a page can show only one design system, swapping an implementation must mean changing one package rather than forty pages, and an AI generating pages must not have to guess. Why these choices were made: [../02-decisions/README.md](../02-decisions/README.md).

## Stack

| Layer | PC (`apps/pc`) | Mobile (`apps/mobile`) |
|---|---|---|
| Framework | Vue 3 + TypeScript | Uni-app (Vue 3) + TypeScript |
| Components | Ant Design Vue 4 | wot-design-uni (fallback `uni-ui`) |
| Tables | vxe-table, only through `<BeTable>` | none: card lists and pull-to-refresh |
| Charts | ECharts + `vue-echarts` (works offline) | the same, rendered on canvas |
| Data fetching | `@tanstack/vue-query` over the generated API client | the same |

- No React, anywhere.
- `package.json` pins exact versions: no `^`, `~` or `latest`. Pairs that must match (vxe-table and vxe-pc-ui) are recorded with their versions in `packages/ui-kit-pc/README.md`.
- The two ends use different component libraries on purpose. PC is dense tables, multi-column filters and long cascading forms used all day with mouse and keyboard; mobile is card lists, scanning, photo upload and approve/reject buttons used for seconds on the road. Almost no component could be reused unchanged, and Ant Design Vue needs a DOM that Uni-app targets don't have.

## Packages and what they share

| Package | Holds | Used by |
|---|---|---|
| `packages/design-tokens` | pure data, no framework import: primary colour, colour ramp rules, spacing scale, font sizes, line heights, radii | both ends; **the only UI asset they share** |
| `packages/ui-kit-pc` | the Ant Design Vue + vxe-table wrappers and wiring, `<BeTable>`, the page templates, the skeleton; the only door for third-party PC components | `apps/pc` |
| `packages/ui-kit-mobile` | the wot-design-uni wrappers; the only door for third-party mobile components | `apps/mobile` |
| generated API client and types | request functions and types generated from the components' contracts | both ends |

Share the tokens, not the components. Sharing components for consistency gives a mobile end that is hard to use and a PC end limited by mobile at the same time. One shared ui-kit that imports Ant Design Vue would drag it into the Uni-app build.

## Design tokens and theme

- **Design tokens are runtime-writable CSS variables**, never TypeScript constants compiled into the bundle. Light/dark and density switch tokens at run time; with constants that is impossible, and by the time it is noticed every page has to change.
- `packages/design-tokens` is the single source for spacing, font sizes and line heights. Both ui-kits take them from there; pages refer only to tokens and ui-kit components. **A page never hard-codes a colour or a spacing value.** In this project "good-looking" means consistent: what spoils the look of pages an AI generates in batches is 16px spacing here and 20px on the next page.
- **One theme source on PC.** Ant Design Vue's seed token is the source; `ui-kit-pc` derives vxe-table's `--vxe-ui-*` variables from it at start. `theme.algorithm` and `VxeUI.setTheme()` are switched together, in one function. Unwired, nothing errors and every table looks pasted into the page.
- Editable table cells use Ant Design Vue controls (`<a-select>`, `<a-input-number>`, `<a-date-picker>`) in vxe's edit slot, registered once as global renderers.
- **Visual direction: restrained and professional.** Only the primary colour of the seed token changes; everything else follows Ant Design Vue's derivation. Compact density through `compactAlgorithm`, row heights from the ui-kit. Small radii, restrained shadows, no card around everything. The system font stack, no downloaded or embedded fonts (offline deployments). Tables without zebra stripes, horizontal rules only, hover highlight; fixed header, frozen columns and virtual scrolling are the default.

## Third-party components

- Third-party UI components appear only inside `packages/ui-kit-pc` or `packages/ui-kit-mobile`, which expose our own component names. A business page never imports a third-party component directly, `<vxe-grid>` included.
- Mixing in another library is allowed only for a capability Ant Design Vue lacks: Gantt charts, an approval-flow designer, rich text, a code editor, big-screen dashboards. Each one gets a line in the component's `docs/design.md`: the capability, why Ant Design Vue can't, the licence. Never mix for looks: two libraries' token systems don't line up, so more mixing looks worse.
- **Tables go through `<BeTable>`.** It covers about 80% of use (columns, data source, editing, selection, export, paging or virtual scrolling). The rest may use the engine's API directly, but every such escape hatch gets one line in `packages/ui-kit-pc/README.md`. The list must stay countable: its length is the work of replacing the engine.
- vxe-table is the default table engine, to be confirmed capability by capability: some of its capabilities are commercial. Before depending on one (virtual scrolling, frozen columns, editable cells with keyboard entry, tree tables, Excel import/export, grouping and pivots, Gantt), check it against the free tier and write the result in `docs/design.md`. If editable cells, virtual scrolling or frozen columns are paid, the engine is replaced; candidates get the same check.

## Page templates

A business page never starts from an empty `<div>`. It starts from a page template in `ui-kit-pc`, `<BeListPage>`, `<BeDetailPage>`, `<BeFormPage>` or `<BeSettingsPage>`, and fills its slots. Pages that pick a template and fill slots cannot drift apart in layout; that is the cure for the best-known weakness of large consoles, every service looking like a different product.

## PC skeleton

The PC skeleton is two-tier navigation in the style of a cloud console: pick a service, then navigate inside it. Not a multi-level tree on the left.

| Place | Content |
|---|---|
| Top bar, left | "▾ Services": an overlay that doesn't leave the page, with search, recent items and the components grouped by domain, each can be starred |
| Top bar, middle | **favourites bar**: starred components, one click away |
| Top bar, right | ⌘K command palette (every page, and jump by document number), **organisation / legal-entity switcher**, notifications, user menu |
| Below the top bar | **in-app tabs** across components, closable |
| Main area, left | the component's own pages, **flat, 3–5 items, never collapsible**, with "Component settings" fixed at the bottom |
| Main area, right | breadcrumb and page content |

- Why not a tree: menus are aggregated at assembly time from each component's `assembly.yaml`, and every customer installs a different set, so a tree would have a different shape for every customer and an AI generating a page couldn't know where it belongs. Mapped to component boundaries, the two tiers look the same for every customer.
- Unlike a cloud console: in-app tabs exist (an unsaved ERP form must survive switching away, and the browser already has twenty tabs), the in-service menu is always flat, and the region switcher is the organisation / legal-entity switcher, which also feeds the data scope.
- The app skeleton is our own. For the parts you can't work out, read `vue-vben-admin`'s layout, router + access and request wrapper, never install it ([10-reference-implementations.md](10-reference-implementations.md#which-project-to-read)).

## Preferences and branding

| Setting | Owner |
|---|---|
| Favourite components and their order | the user |
| Light / dark / follow the system | the user |
| Standard / compact density | the user |
| Language | the user |
| Table column widths, order, hidden columns, filters | the user, kept locally only, never synced |
| Primary colour, logo, product name, watermark, greyscale mode | assembly-time configuration, one per company |
| Layout modes (side / top / mixed), radius, animation, footer and breadcrumb switches | don't exist |

User preferences are stored in `localStorage`. Adding a preference beyond these four means a test of every page under it; that is the reason the list is short.

## Features, permissions and menus

- A route or menu item shows only when three things hold: the component is installed (`GET /api/tenant/features`), the user may use it (`GET /api/me/permissions`), and the user is logged in. Checking only features gives a visible menu item that opens a full-page 403. Buttons use `v-be-auth="'<permission key>'"` from `ui-kit-pc`.
- Both endpoints return only what this user may see; the full list is never sent for the frontend to filter, because it reveals which modules the company bought.
- **Hiding in the frontend is never a security boundary.** A user who edits the code can reach a hidden page; it must then be an empty shell, with every data request rejected by the backend.
- Each component declares its menu entries in its `assembly.yaml` under `menus`, each with one of the component's own permission keys. be-ops aggregates them at assembly time; the service selector and the in-service menus are built from that aggregate. There is no central menu table.
- A `401` with `error="token_stale"` triggers a silent token refresh and exactly one retry of the original request (that is how a role change takes effect within seconds).

## Business logic and data access

- Money calculations, stock deductions and core state transitions happen in the backend, never in the frontend.
- The frontend owns form interaction: validation patterns, showing and hiding fields, debounce and throttle, local drafts against data loss. No backend call just to show or hide a field.
- A live estimate that depends on backend rules (a price from customer tier and product) calls the backend's `DryRun` / `Validate` endpoint, debounced; the backend formula is never re-implemented in the frontend.
- No hand-written `fetch('/api/…')`: requests go through the API client generated from the contracts.
- Every date range picker defaults to the last 90 days, so no page scans a whole table by accident.

## Internationalisation

- Every user-facing string goes through the i18n layer, with Chinese and English messages; pages contain no literal UI text.
- Both languages are complete for every page shipped. The language is a user preference.
- Dates, numbers and amounts are formatted by the locale; amounts stay decimal strings from the API to the screen.

## Tests

The frontend test layers are FE-1 (logic: functions, composables, stores), FE-2 (shared components), FE-3 (end-to-end in a real browser on the real backend, one business flow per test) and FE-4 (screenshot comparison inside FE-3 for key pages, light and dark). FE-3 and FE-4 are written once a page's interaction is stable, and run only after the user agrees to the scope. The details are in [06-testing.md](06-testing.md#frontend-tests).
