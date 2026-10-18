# Bank Tags standalone plan

This records the signed-off plan for making Bank Tags a standalone plugin on Bank Core's public API, the review amendments adopted before implementation, and the stages it was built in. Results and measurements are in the last section.

## Starting point

- Bank Tags source was preserved from Bank Utilities `beba274` at `3c3771b` on `feature/standalone-banktags`. It was not runnable: it reached into Bank Core's private `Features` bridge and native bank components, and its modules used the same paths as Bank Core's.
- Bank Core (`bankcore`, repository `bank-utilities`) offers one public extension model, described in its `HOST_CONTRACT.md`: owners with pages, mounted tabs, item menus, drops, pick mode, listeners, and bank item snapshots. It has no API version; nothing has shipped, so a change updates the contract instead of adding compatibility layers.
- The share-code format `bankutilities-tags` version 3 is a data format, not an API version, and stays valid.

## Core prerequisites (landed in Bank Core before this work)

- **P1:** dependents follow the documented `PluginDependencyUpdate(event)` with `event.pluginIdentifier` and `event.enabled`.
- **P2:** `GetState()` reports `columns` (the grid columns pages wrap at) and `bounds` (the bank window's position and size) while the bank is open, and `onState` fires when they change.
- **P3:** display text may be 80 characters, and menu labels and subjects 96, so a full tag name fits titles and menu subjects.

## Plan, with the adopted amendments

1. **Plugin and build.** One standalone plugin, `banktags`. PrettyUI is required; `bankcore` and `runeql` are optional dependencies, because the host notifies only optional dependencies of changes. Bank Tags needs Bank Core and says so on its plugin panel when it is missing; RuneQL only widens item search. A repository-local build writes `dist/banktags` with a generated module eviction list; the preserved source stays in `reference/` and is never built.
2. **Unique module paths.** Every runtime module lives under `banktags/`, so no require path can collide with Bank Core's `lib/` modules. The published reload keys are `__banktags_session` and `__banktags_api`.
3. **Lifecycle.** The entry shuts down a previous session found in the same Lua state, then connects. A copy whose owner ID was taken by a newer load retires and never takes it back. Bank Tags never relies on Bank Core's `LIMITS` table surviving a cloned export; it checks each call's result.
4. **One page.** Bank Tags registers one page and updates it with the key `tag:<name>` for whichever tag is shown, so a thousand tags need one page. The adapter passes object IDs, maps unresolved saved items to blanks in place, gives each slot its copy and its ghost's source copy, keeps deliberate empty rows, adds an `Unsorted` label and row only when Unsorted items exist, and blanks a repeated copy rather than letting Core refuse the page.
5. **Entry budget.** Bank Core accepts 10,000 page entries; showing Unsorted adds two. Edits and imports keep each tag within 9,998 entries. A saved tag over that still loads, saves, and can shrink without any data cut; while it is too large to draw, its page explains how many entries it has instead of showing items.
6. **Tags tab.** Bank Tags draws its own column in Bank Core's mounted tab: search, sorting, folders, tag icons, a status line, the select-mode panel, and the footer (Import/Share, New Tag, layout editor). Searching filters only this list. More tags and rows than Core's own row limits are fine, because the list is Bank Tags' own.
7. **Menus.** Row actions use the mounted tab's `onMenu`; item actions use `SetItemMenu`. Bank Tags never subscribes to `MiniMenuReady`. Folder moves use a "Move to folder..." entry that opens a folder chooser, since Bank Core's menus have no submenus and a few entries each.
8. **Drops and select mode.** Drops onto tag rows and New Tag arrive through `onItemDrop`. Select mode is Bank Core's pick session: "Add to <tag>" becomes the left click on native items and members are outlined in gold. Both need the bank's All Items view, where copy numbers are known; elsewhere Bank Tags explains instead of guessing a copy.
9. **Windows.** The layout editor, tag settings, delete confirmation, sprite picker, text prompts, folder chooser, and Import/Share are Bank Tags' own windows. The layout editor takes its size, position, and columns from Bank Core's state and its quantities from Bank Core's item snapshots; it replaces its old bank right-click menu with Create Copy, Remove, and Move to Unsorted buttons. Bank windows close when the bank closes, Bank Core goes, or Bank Tags stops; Import/Share can stay open.
10. **Import providers.** Import/Share and its provider registration belong to Bank Tags. Other plugins register through the `banktags` API (`RegisterExtension`, then `RegisterImportProvider`, `UpdateImportProvider`, `RemoveImportProvider`, and `Dispose` on the handle). Drafts are validated in full before anything is saved; one import commits once or not at all.
11. **Catalog.** With RuneQL loaded, item search uses `runeql.Catalog.Find`. Without it, search finds bank items by name, an exact item ID, or an exact config name, and says so. It never scans config IDs.
12. **Persistence.** New data lives under `banktags:tags:v3:*` and `banktags:settings:v1` in Bank Tags' own saved data. Each plugin's saved data is separate, so a new install starts empty; tags come across with the old plugin's per-tag share codes, which Import reads. The old `bankutils` data is never read, changed, or deleted, and no export helper is added. A save that cannot be read is reported and never overwritten.

## Stages

| Stage | Content | Acceptance |
| --- | --- | --- |
| S1 | Restructure, entry, manifest, build, check, app connection | Built files compile with no unexpected globals and nothing from `reference/` or `tests/`; packaged test covers Core missing, late, reloading, unloading, cloned exports, Bank Tags reloading in shared and separate states, RuneQL present or absent |
| S2 | Store budget, load guard, page adapter | Pages from saved rows are accepted by the real Bank Core; full-size tag renders; oversized saved tag kept whole; failed imports save nothing |
| S3 | Tags tab | Search, folders, sorting, footer, row menus, folder chooser, more than 16 tags and 64 rows, one page with a new key per tag, View All guidance |
| S4 | Actions | Item menus over native items, page items, and ghosts; drops on rows and New Tag; select mode and its end; inventory generations and `building` |
| S5 | Windows | Layout editor geometry, columns, buttons, and closing; settings, delete, sprite picker, prompts, Import/Share and providers |
| S6 | Docs | README and contract describe every change from the old plugin and the host behavior not yet verified live |

## Host limits accepted for this plugin

- Select mode and drops work in the bank's All Items view only; Bank Core's pick session ends on another native tab.
- Bank Core outlines select-mode members in gold, where the old plugin used white.
- Folder moves use a chooser window instead of a submenu.
- The layout editor's item actions are buttons, not a bank right-click menu, and its icons use the client's default look because Bank Core does not report a stack's outline or shadow.
- Select mode's status and Done button are in the Tags tab instead of a panel over the bank's right column.

## Results

All six stages are implemented on `feature/standalone-banktags`, each in its own commit, with `tools/check.lua` passing at every stage. Everything was checked against Bank Core's stand-in host only, loading the real Bank Core from its checkout through `BANKCORE_ROOT`; nothing has been verified in the live client.

| | Lua files | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Preserved `lib/` at `3c3771b` (not runnable; its app, entry, and windows lived in `reference/`) | 47 | 8,435 | 319,584 |
| Built `dist/banktags` (entry and 44 modules, plus `plugin.json`) | 45 | 7,819 | 298,921 |

Tests: `plugin_reload_test` (packaged load orders, cloned exports, reloads in shared, separate, and cached states, RuneQL), `tag_page_test` (conversion and budget against Bank Core), `tag_tab_test` (the tab, menus, folder chooser, panel), `tag_actions_test` (item menus, ghosts, drops, select mode, snapshots), `layout_editor_test` (geometry, columns, buttons, windows), `import_providers_test` (ported), and the preserved `tag_store_test`, `tag_rules_test`, and `tag_layouts_test`.

Found during implementation and left for review:

- Bank Core delivers no drop outside All Items, so the old plugin's drops on native category tabs are gone; the Tags tab says to select All Items while Core reports that reason.
- Bank Core's `examples/page-demo` finds Bank Core with `ipairs({ bankcore, rawget(_G, "__bankcore_api") })`, which stops at a missing injected global and never reaches the published copy. Bank Tags checks both by position.
- Bank Core's stand-in loader shares exported tables instead of cloning them, and Bank Core's API root is a read-only proxy whose fields `pairs` cannot see. How the live host clones it is unverified; Bank Tags' test covers a clone that copies the documented fields.
