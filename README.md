# Bank Tags

Bank Tags (`banktags`) is a standalone plugin for tags, folders, saved layouts, select mode, and Import/Share in the bank. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) and reaches the bank only through Bank Core's public extension API: no private Core module or native bank component is used. It adds its own right-click entries from the client's menu event, asking Bank Core which bank item a menu belongs to. The full contract, including the API other plugins use to add import sources, is in [CONTRACT.md](CONTRACT.md). The staged plan it was built from is in [docs/STANDALONE_PLAN.md](docs/STANDALONE_PLAN.md).

Everything here is checked against Bank Core's stand-in host only. Nothing in this repository has been verified in the live client yet; see [Not yet verified live](#not-yet-verified-live).

## Features

- **Tags tab.** A sidebar tab Bank Core mounts, drawn by Bank Tags: search, sorting, folders with collapse, tag icons, a status line, and a footer with Import/Share, New Tag, and the layout editor. Any number of tags fits; the list is Bank Tags' own, not Core's row list.
- **Showing a tag.** Choosing a tag shows it through one Bank Core page, keyed `tag:<name>`, with its saved layout: labels, deliberate empty rows, exact copies, ghost copies that open their source, and Unsorted items under their own heading. Choosing the shown tag again returns to the bank's own view. Bank Core names the page's items that have no bank stack beneath them, such as ghosts; Bank Tags adds nothing over the page.
- **Right-click menus.** Tag rows offer Select, Edit (opens the layout editor), Rename (name and icon), Select items, Remove, Remove from folder, and an Add to folder or Move to folder submenu listing the other folders, Create new folder, and Cancel. Folder rows offer Collapse or Expand, Rename folder, and Ungroup folder. Items of the shown tag, including ghosts and items the bank does not hold, offer Remove from the tag, which removes the copy that slot was drawn for.
- **Drag and drop.** Dragging a bank item onto a tag row adds that copy; dropping it on New Tag creates a tag holding it and opens it for naming.
- **Select mode.** Select items makes "Add to <tag>" the left click on bank items and outlines the tag's members in gold. The Tags tab shows the tag being filled, pulses its row, and offers Done.
- **Layout editor.** A window over the bank, sized and placed from Bank Core's bank bounds, laid out at Bank Core's grid columns so it matches the page. A narrow tag rail runs down the left edge, like Bank Core's tab rail: one button per tag in the Tags tab's order, folder members included, showing the tag's icon (or its first letters when it has none), with the open tag outlined in gold and "Folder / Tag" as its tooltip; arrows page through more tags than fit. The rail and both columns start right under the title bar, and the title bar's close button closes the editor. The sorted grid sits beside the rail at Bank Core's columns under a single PrettyUI Layout tab, with the open tag's name beside it; it is level with Unsorted and the same height, and both columns use the same tab header and one framed item area. The rail's outline and tooltips also show the open tag, and the Tags tab's Rename changes its name or icon. New Tag and Import/Share stay in the Tags tab. The right column takes the rest of the width with Unsorted and Search tabs; Unsorted is shown first, at as many columns as the column fits (nine at the default size), and each grid scrolls separately. One row under both columns, from the rail to the right edge, holds Create Copy, Remove, Move to Unsorted, and New label; their tooltips give the shortcuts and drag hints, and changes save automatically. Drag items and labels, drag an item between the sorted grid and Unsorted, and drag search results into the sorted grid. Labels stay in the sorted grid, and Unsorted keeps its own order. Hovering an item in the sorted grid or Unsorted shows its name, also while the grids' drag surfaces cover them; a drag, an open menu, or the label prompt, tag settings, or sprite picker over the editor hides it. Changing tab ends a drag in progress; the search text and each list's scroll are kept. Renaming the open tag keeps it open; deleting it opens the first tag. After pressing an item in either grid, Delete removes it and Ctrl+C creates a copy, once per key press. The client reports no focused text field, so the keys stop working once the search field, the Search tab, or a menu is clicked, the label prompt or tag settings is open, or the game loses focus, until the grid is pressed again. A text field elsewhere, such as chat or a window not opened from the editor, is not detected.
- **Import/Share.** Share codes per tag, import with a preview, renaming, a sprite, and a folder, and import sources other plugins register.
- **Bank settings.** Show tag sprites, where new items go (Unsorted or the first empty slot), and debug logging, in Bank Tags' section of Bank Core's settings window (the gear at the bottom of the bank sidebar). Bank Tags registers the section with `owner:SetSettings` and saves the values itself.
- **No plugin window entry.** Bank Tags has no ribbon icon or panel in the Plugins window; Import/Share opens from the Tags tab's footer.

## Requirements and load order

- **PrettyUI** is a required dependency.
- **Bank Core** (`bankcore`) is needed for anything in the bank. It is declared as an optional dependency only because the host reports changes for optional dependencies; required dependencies get no change notification. Without Bank Core, Bank Tags loads, keeps its tags, and waits; other plugins can still register import sources.
- **RuneQL** (`runeql`) is optional. With it, the sprite picker and the editor's item search cover every item. Without it they find items in the bank by name, an exact item ID, or an exact config name, and say so. Once the host reports RuneQL unloaded, search stops reading it, even if its global remains, until the host reports it loaded again.

Any load order works: Bank Tags connects when Bank Core loads, reconnects when Bank Core reloads, and lets go when Bank Core unloads, through the host's `PluginDependencyUpdate`. Reloading Bank Tags shuts down the previous copy in the same Lua state first; a copy whose owner ID a newer load took stays idle. A typical development reload is Bank Core first, then Bank Tags, but either can reload alone.

## Saved data

- Tags save under `banktags:tags:v3:*` and preferences under `banktags:settings:v1`, in Bank Tags' own saved data.
- **A new install starts with no tags.** Each plugin's saved data is separate, so Bank Tags cannot read the old Bank Utilities plugin's `bankutils:tags:*` data, and it never changes or deletes it. Tags made with the old plugin come across through its per-tag share codes, if you have them: paste each into Import. The share format, `bankutilities-tags` version 3, is unchanged. The old Bank Utilities plugin is not expected to work against this Bank Core, whose private bridge it used was removed.
- A tag holds at most 9,998 rows, labels, and items, so Bank Core can always add the Unsorted heading. A larger saved tag is kept whole; until it is made smaller, its page explains why it is not drawn.
- A save that cannot be read is reported in the Tags tab and never overwritten; nothing is saved until it is fixed or removed.

## Changes from the old integrated plugin

- Drops onto a tag row or New Tag work from any native bank tab. From All Items a drop tags the exact copy dragged; a numbered tab's order is its own, so Bank Core names no copy and the drop tags the object's first copy (with duplicate stacks, that may not be the stack dragged).
- Select mode works in the bank's All Items view only, where copy numbers are known, and ends on another native tab.
- Select mode outlines members in gold, Bank Core's highlight, not white. Its status and Done button are in the Tags tab, not a panel over the bank's right column. The left-click entry reads "Add to <tag>" followed by the item's name.
- The layout editor's item actions are buttons (Create Copy, Remove, Move to Unsorted), not a right-click menu. It chooses tags from an icon rail rather than a tag column, and its item icons use the client's default look because Bank Core does not report a stack's outline or shadow.
- Tag names may be up to 80 characters in the tag settings field, matching what saving always allowed.
- Cleanup, RuneQL queries, and Advanced Bank Search are not part of Bank Tags.

## Layout

- `plugins/banktags/`: the entry (`main.lua`) and manifest.
- `banktags/`: every runtime module. All require paths start with `banktags/`, so none can collide with Bank Core's modules.
- `tools/`: the build and check tools, and the test harness that loads Bank Core beside Bank Tags.
- `tests/`: the tests; see [tests/README.md](tests/README.md).
- `reference/`: the preserved source from Bank Utilities `beba274`, kept as an archive. Nothing in it is built or loaded. `EXTRACTION_MANIFEST.json` records where each preserved file came from.

## Build and check

```text
lua54 tools/build.lua
lua54 tools/check.lua
```

The build writes only `dist/banktags/`: `main.lua`, `plugin.json`, and the 47 modules the entry's require graph loads, with the entry's module eviction list generated from that graph. It refuses output paths inside the source tree and removes only what its previous build wrote. The check builds into `dist/check`, runs every test, compiles every built file, and fails on unexpected globals, a runtime source the entry never loads, or anything from `reference/`, `tests/`, or `tools/` in the package. Tests that load Bank Core read it from `BANKCORE_ROOT`.

The toolchain used locally is a Lua 5.4 interpreter with `luac54` beside it, which the compile step needs.

## Not yet verified live

- Keyboard focus in the Tags tab's search field inside Bank Core's mounted column, and tooltips drawn through the mount's overlay.
- How the host positions PrettyUI list rows and scrolls them; drops and right-clicks find rows by where they are drawn, which the stand-in host models.
- How the host clones exports. Bank Core's and Bank Tags' roots are plain tables, and the tests inject an ordinary field-by-field clone of each, but the client's own copy, and whether functions it copies can be called across plugins, are unverified. Bank Tags also falls back to `__bankcore_api` when the shared Lua state has it, and never reads `LIMITS`.
- When the host calls `PluginDependencyUpdate` on reloads, whether it re-injects the global, and whether module caches are scoped per plugin.
- The drop hook's return value and naming, which Bank Core owns.
- Bank Core's bank bounds as screen coordinates for placing the layout editor, and how 80-character names fit the bank header.
- PrettyUI's item slot `SetTooltip` and the item grid in the sprite picker, which the stand-in host does not draw.
- The layout editor's item names: that its drag surfaces hear hover over the grids and results, and that a name beside the editor stays in front of it. The stand-in host's tooltips record their text and target; they are not drawn.
- The folder submenu as the client draws it beside a Tags row menu, and that clicking one of its folders moves the tag once and reaches no Tags row beneath; the tests run PrettyUI's real `AddSubmenu` and its clear-then-act order, not its drawn rows.
