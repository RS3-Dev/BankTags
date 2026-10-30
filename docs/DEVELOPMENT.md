# Developer reference

These are implementation, build, migration, and validation notes. For first-time player instructions, read the [player guide](../README.md). Historical implementation notes are not a statement of release readiness.

# Bank Tags

Bank Tags (`banktags`) is a standalone plugin for tags, folders, saved layouts, select mode, and Import/Share in the bank. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) and reaches the bank only through Bank Core's launch API (`bankcore.Register`): no private Core module or native bank component is used. It adds its own right-click entries from the client's menu event, asking Bank Core which bank item a menu belongs to. The full contract, including the API other plugins use to add import sources, is in [CONTRACT.md](../CONTRACT.md). The staged plan it was built from is in [docs/STANDALONE_PLAN.md](../docs/STANDALONE_PLAN.md).

The automated suite uses Bank Core's stand-in host. Some interaction fixes were informed by live reports and captured events; that does not establish that every behavior in the current build has been tested live. See [release checks](#not-yet-verified-live).

## Player controls

Use the [player guide](../README.md) for the current menus, tutorial, sidebar buttons, and editor controls. This reference focuses on dependencies, saved data, packaging, and verification.

## Requirements and load order

- **PrettyUI** is a required dependency.
- **Bank Core** (`bankcore`) is needed for anything in the bank. It is declared as an optional dependency only because the host reports changes for optional dependencies; required dependencies get no change notification. Without Bank Core, Bank Tags loads, keeps its tags, and waits; other plugins can still register import sources.
- **RuneQL** (`runeql`) is optional. With it, the sprite picker and the editor's item search cover every item. Without it they find items in the bank by name, an exact item ID, or an exact config name, and say so. Once the host reports RuneQL unloaded, search stops reading it, even if its global remains, until the host reports it loaded again.

Any load order works: Bank Tags connects when Bank Core loads, reconnects when Bank Core reloads, and lets go when Bank Core unloads, through the host's `PluginDependencyUpdate`. Reloading Bank Tags shuts down the previous copy in the same Lua state first. Each registration replaces the last one with the same ID, so a copy in another Lua state that registers later takes the rail icon over. A typical development reload is Bank Core first, then Bank Tags, but either can reload alone.

## Saved data

- Tags save under `banktags:tags:v4:*` and preferences under `banktags:settings:v1`, in Bank Tags' own saved data.
- **A new install starts with no tags.** Each plugin's saved data is separate, so Bank Tags cannot read the old Bank Utilities plugin's `bankutils:tags:*` data, and it never changes or deletes it. The share format, `bankutilities-tags`, is now version 4: a slot is just its item's config name (or `#<id>`), and an item listed twice is two slots. Version 3 codes, with their `:copy` and `<source` suffixes, and `v3` saves are not read; there is no converter. The old Bank Utilities plugin is not expected to work against this Bank Core, whose private bridge it used was removed.
- A tag holds at most 9,998 rows, labels, and items, so Bank Core can always add the Unsorted heading. A larger saved tag is kept whole; until it is made smaller, choosing it says in the Tags tab why it is not shown.
- Slots are told apart in the layout editor by a `layoutKey` each is given when it is read or added. Keys last only for the session and are never saved.
- A save that cannot be read is reported in the Tags tab and never overwritten; nothing is saved until it is fixed or removed.

## Changes from the old integrated plugin

- Items are added with select mode or the layout editor's search; dragging a bank item onto a tag row or New Tag is gone.
- Tags list objects, not stacks. Bank Core shows the Nth slot naming an object as that object's Nth stack, stocked stacks first, then placeholders, then a ghost. Select mode works in any bank tab.
- Select mode outlines nothing; the Tags tab names the tag being filled. Its status and Done button are in the Tags tab, not a panel over the bank's right column. The left-click entry reads "Add to <tag>" followed by the item's name.
- Right-clicking a sorted layout item offers Move to Unsorted, Edit row, Remove from Tag, and Cancel, in that order. Item actions affect the clicked slot and can be undone. Blank cells and labels offer Edit row and Cancel. The footer also has Copy, Paste, Remove, and Move to Unsorted. The editor chooses tags from an icon rail, and its item icons use the client's default look because Bank Core does not report a stack's outline or shadow.
- Tag names may be up to 80 characters in the tag settings field, matching what saving always allowed.
- Cleanup, RuneQL queries, and Advanced Bank Search are not part of Bank Tags.

## Layout

- `plugins/banktags/`: the entry (`main.lua`) and manifest.
- `banktags/`: every runtime module. All require paths start with `banktags/`, so none can collide with Bank Core's modules.
- `tools/`: the build and check tools, and the test harness that loads Bank Core beside Bank Tags.
- `tests/`: the tests; see [tests/README.md](../tests/README.md).
- `reference/`: the preserved source from Bank Utilities `beba274`, kept as an archive. Nothing in it is built or loaded. `EXTRACTION_MANIFEST.json` records where each preserved file came from.

## Build and check

```text
lua54 tools/build.lua
lua54 tools/check.lua
```

The build writes only `dist/banktags/`: `main.lua`, `plugin.json`, the 51 modules the entry's require graph loads, and the tutorial's Ogg sound resource, with the entry's module eviction list generated from that graph. It refuses output paths inside the source tree and removes only what its previous build wrote. The check builds into `dist/check`, runs every test, compiles every built file, and fails on unexpected globals, a runtime source the entry never loads, or anything from `reference/`, `tests/`, or `tools/` in the package. Tests that load Bank Core read it from `BANKCORE_ROOT`.

The toolchain used locally is a Lua 5.4 interpreter with `luac54` beside it, which the compile step needs.

## Not yet verified live

- Keyboard focus in the Tags tab's search field inside Bank Core's mounted column, and tooltips drawn through the mount's overlay.
- How the host positions PrettyUI list rows and scrolls them; right-clicks find rows by where they are drawn, which the stand-in host models.
- How the host clones exports. Bank Core's and Bank Tags' roots are plain tables, and the tests inject an ordinary field-by-field clone of each, but the client's own copy, and whether functions it copies can be called across plugins, are unverified. Bank Tags also falls back to `__bankcore_api` when the shared Lua state has it, and never reads `LIMITS`.
- When the host calls `PluginDependencyUpdate` on reloads, whether it re-injects the global, and whether module caches are scoped per plugin.
- Bank Core's `GetBankBounds()` as screen coordinates for placing the layout editor, that checking it every 10 logic ticks while the editor is open follows a moved bank closely enough (Core gives no move event), and how 80-character names fit the bank header.
- PrettyUI's item slot `SetTooltip` and the item grid in the sprite picker, which the stand-in host does not draw.
- The layout editor's item names: that its drag surfaces hear hover over the grids and results, and that a name beside the editor stays in front of it. The stand-in host's tooltips record their text and target; they are not drawn.
- The layout editor's arrow keys, Ctrl+C, Ctrl+V, Ctrl+Z, and Ctrl+Y: that the client sends `KeyDown` with the documented `GameKey.LEFT`, `RIGHT`, `UP`, `DOWN`, `C`, `V`, `Z`, and `Y` with the grid pressed, and reports Ctrl through `ModifierKey.CONTROL` in the event or `Keyboard.IsControlDown`. Captured live events use Ctrl = 4, Alt = 2, and Shift = 1; shortcut matching uses those values. Debug logging records shortcuts for diagnosis. The stand-in host sends the key events directly.
- The Edit row submenu as the client draws it beside the editor, and that picking a child acts once and reaches nothing beneath; the tests run PrettyUI's real `AddSubmenu`, not its drawn rows.
- The layout editor's group selection: that `Keyboard.IsShiftDown` reads Shift at the moment the grid's surface hears the press, that a drag surface's click and release arrive in that order for a Shift-click, and how the translucent gold and red drop cells and the group's count draw over the grid while it scrolls. The stand-in host sets Shift directly.
- Dragging Tags rows to reorder them. PrettyUI's row click reports each press, and the selection or folder toggle now waits for the row's release. The drag relies on four host behaviours the stand-in host only models: the pressed row hears `ONRELEASE` or `ONDRAGCOMPLETE` when the button is released; the pressed row keeps hearing `ONHOLD` or `ONDRAG` after it is stretched under the pointer; it hears `ONMOUSELEAVE` when the pointer leaves it; and the wheel still scrolls the list through PrettyUI's own row listener while held. Drop positions come from the calibrated mouse position, never from the drag events' own coordinates, which were wrong at 125% Windows scaling. The ghost, the gold drop line, and how a stretched row draws over the others are unverified.
- The folder submenu as the client draws it beside a Tags row menu, and that clicking one of its folders moves the tag once and reaches no Tags row beneath; the tests run PrettyUI's real `AddSubmenu` and its clear-then-act order, not its drawn rows.
