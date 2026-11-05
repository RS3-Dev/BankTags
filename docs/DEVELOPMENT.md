# Developer reference

These are implementation, build, migration, and validation notes. For first-time player instructions, read the [player guide](../README.md). Historical implementation notes are not a statement of release readiness.

# Bank Tags

Bank Tags (`banktags`) is a standalone plugin for tags, folders, saved layouts, select mode, and Import/Share in the bank. It uses [Bank Core](https://github.com/RS3-Dev/bank-utils-core) (`bankcore`) for the sidebar and custom pages through its public API (`bankcore.Register`), without loading private Core modules. Bank Tags owns select-mode outlines and bank-item drops through the client's native component hooks. It adds its own right-click entries from the client's menu event, asking Bank Core which bank item a menu belongs to. The full runtime contract is in [CONTRACT.md](../CONTRACT.md). The staged plan it was built from is in [docs/STANDALONE_PLAN.md](../docs/STANDALONE_PLAN.md).

The automated suite uses Bank Core's stand-in host. Some interaction fixes were informed by live reports and captured events; that does not establish that every behavior in the current build has been tested live. See [release checks](#not-yet-verified-live).

## Player controls

Use the [player guide](../README.md) for the current menus, tutorial, sidebar buttons, and editor controls. This reference focuses on dependencies, saved data, packaging, and verification.

## Runtime module organization

Keep ownership and lifecycle in the controller; compose related method tables from focused modules. These internal modules never require their owning controller, so the dependency graph remains acyclic.

| Area | Controller / lifecycle | Focused responsibilities |
| --- | --- | --- |
| Layout editor | `windows/layout_editor_window.lua` | `layout_editor_view.lua` builds/draws panes and maps grid coordinates; `layout_editor_rows.lua` handles row/label prompts and menu targets. Existing drag, selection, search, tabs, clipboard, keys, and history modules keep their own responsibilities. |
| Tag sidebar | `sidebar/tag_list.lua` | `tag_list_drag.lua` owns presses, drag capture, edge scrolling, and release; `tag_list_parts.lua` shares row identity helpers and measurements. |
| Import / Share | `windows/import_share.lua` | `import_share_draft.lua` owns decode/preview state, name/icon/folder overrides, and import submission. |
| Tutorial | `windows/tutorial.lua` | `tutorial_view.lua` builds the guide controls and positions/animates the target overlay. The controller observes progress and owns subscriptions and teardown. |
| Saved layouts | `tags/tag_store_layouts.lua` | `tag_store_labels.lua` owns label edits; `tag_store_folders.lua` owns folders. `tag_store.lua` composes these into the same store API. |

All paths above are relative to `banktags/`. Packaging follows the entry point's require graph; new runtime modules must be loaded by that graph, and the build generates their reload eviction list. Run `tools/check.lua` after moving methods: it checks for unshipped runtime sources, runs the regressions, and compiles every shipped Lua file with the allowed host globals. Extracting a UI method must preserve its native callbacks, clipping parents, and teardown owner.

The same check enforces 3–10 word summaries above named functions in current source, tools, and tests. Longer callbacks also have short explanations where helpful. Historical files in `reference/` retain their original comments and hashes.

Group removal and Move to Unsorted copy the store once and scan the selected tag once. They keep reading order, save once, and remain one undo step. Folder filing and expansion share one save; nested `SaveTogether` calls wait for the outer save. A label prompt captures the saved layout it targets and refuses a later submission if that layout changed.

Writes use the same 1,000-tag, 200-folder, and 1,000,000-byte limits as reads. An unreadable chunk list, missing chunk, or storage read failure blocks edits instead of creating an empty writable store. JSON imports preserve Unicode escapes and empty array positions, and reject malformed numbers, raw control characters, and excessive nesting.

## Requirements and load order

- **PrettyUI** is a required dependency. Its [published documentation](https://prettyui.j3.gg/index.html) defines the API Bank Tags uses, including `Dialog`, managed text fields, and dialog actions.
- **Bank Core** (`bankcore`) is needed for anything in the bank. It is declared as an optional dependency only because the host reports changes for optional dependencies; required dependencies get no change notification. Without Bank Core, Bank Tags loads, keeps its tags, and waits. Core is a fixed dependency; Bank Tags uses its existing public API without changes to Core.
- Bank Core 1.5.0 or later is required. Bank Tags reads the initial state and listens for changes. Pages require an open bank on All Items with no native presets, search, or filter active. Each open attempt checks a fresh snapshot; clearing a restriction does not reopen a page automatically.
- **RuneQL** (`runeql`) is optional. With it, the sprite picker and the editor's item search cover every item. Without it they find items in the bank by name, an exact item ID, or an exact config name, and say so. Once the host reports RuneQL unloaded, search stops reading it, even if its global remains, until the host reports it loaded again.

Any load order works: Bank Tags connects when Bank Core loads, reconnects when Bank Core reloads, and lets go when Bank Core unloads, through the host's `PluginDependencyUpdate`. Reloading Bank Tags shuts down the previous copy in the same Lua state first. Each registration replaces the last one with the same ID, so a copy in another Lua state that registers later takes the rail icon over. A typical development reload is Bank Core first, then Bank Tags, but either can reload alone.

## Saved data

- Tags save under `banktags:tags:v4:*` and preferences under `banktags:settings:v1`, in Bank Tags' own saved data.
- **A new install starts with no tags.** Each plugin's saved data is separate, so Bank Tags cannot read the old Bank Utilities plugin's `bankutils:tags:*` data, and it never changes or deletes it. The share format, `bankutilities-tags`, is now version 4: a slot is just its item's config name (or `#<id>`), and an item listed twice is two slots. Version 3 codes, with their `:copy` and `<source` suffixes, and `v3` saves are not read; there is no converter. The old Bank Utilities plugin is not expected to work against this Bank Core, whose private bridge it used was removed.
- A tag holds at most 9,998 rows, labels, and items, so Bank Core can always add the Unsorted heading. A larger saved tag is kept whole; until it is made smaller, choosing it says in the Tags tab why it is not shown.
- Slots are told apart in the layout editor by a `layoutKey` each is given when it is read or added. Keys last only for the session and are never saved.
- A save that cannot be read is reported in the Tags tab and never overwritten; nothing is saved until it is fixed or removed.

## Import and dialogs

Import/Share accepts pasted share codes and full backups. The external provider API, asynchronous request queue, draft format, and source picker have been removed. Name, icon, and folder overrides for a single imported tag remain available.

Name prompts and removal confirmations use PrettyUI's existing `Dialog` component. The adapters retain validation and failed-save messages while PrettyUI owns footer actions and window destruction. The tutorial points at the folder-name field while that prompt is open.

The editor uses native click, hold, and mouse-repeat coordinates throughout hover, dragging, and release; it does not read or calibrate global mouse pixels. Scroll changes which slot is selected, not the ghost's position. Native drag-start and completion arguments are not treated as current pointer coordinates. A drop with no current point is cancelled. Item-name tooltips use a hidden, disabled, click-through positioning anchor; leave/re-enter events settle on the logic tick, and unchanged tooltips and idle editor windows are not re-shown or raised each tick.

## Changes from the old integrated plugin

- Items are added with select mode, the layout editor's search, or a bank-item drop onto an existing tag row.
- Tags list objects, not stacks. Bank Core shows the Nth slot naming an object as that object's Nth stack, stocked stacks first, then placeholders, then a ghost. Select mode works in any bank tab.
- Select mode outlines the tagged stacks in gold and restores their original looks when it ends. The Tags tab names the tag being filled and holds the Done button. The left-click entry reads "Add to <tag>" followed by the item's name.
- App errors appear over the bank title in the column's window-sized overlay. The notice uses native sizing anchors, stays click-through, and hides to reveal the title when cleared. Updating it does not rebuild the tag list or footer. Core is unchanged.
- Right-clicking a sorted layout item offers Move to Unsorted, Edit row, Remove from Tag, and Cancel, in that order. Move to Unsorted affects the whole selection when the clicked item is selected, otherwise only the clicked slot; Remove from Tag affects the clicked slot. Both can be undone. Unsorted item menus offer Move to Layout and Remove from Tag, without the row submenu. Move to Layout fills the first open logical cell, skipping label rows and reserved slots, or appends a row; the moved slot remains selected. The footer Move to Unsorted also batches the selection in reading order, in one save and undo step. Blank cells and labels offer Edit row and Cancel. Edit row also adds a label above or below the row. The footer groups compact Copy, Paste, and Remove controls beside Move to Unsorted and New label, with Close at the far right. The editor uses persistent Unsorted, Layout, and Search columns. The compact left tray holds five Unsorted columns by default; Search stays visible on the right. Native icon/initial bank tabs above Layout choose the tag; larger bank column counts grow Layout and the tab strip. Status feedback shares the footer. Editor item sprites use a native 1px black outline, preserving their stack quantities and placeholder opacity.
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

The build writes only `dist/banktags/`: `main.lua`, `plugin.json`, the modules the entry's require graph loads, and the tutorial's Ogg sound resource, with the entry's module eviction list generated from that graph. It refuses output paths inside the source tree and removes only what its previous build wrote. The check builds into `dist/check`, runs every test, compiles every built file, and fails on unexpected globals, a runtime source the entry never loads, or anything from `reference/`, `tests/`, or `tools/` in the package. Tests that load Bank Core read it from `BANKCORE_ROOT`.

The toolchain used locally is a Lua 5.4 interpreter with `luac54` beside it, which the compile step needs.

## Not yet verified live

- Select-mode outlines and native bank-item drops in this build: native wrapper replacement, stocked stacks before placeholders, restoration of sprite styles, and delivery of `ONDRAG` and `ONDRAGCOMPLETE` alongside Core's own listeners. Automated checks cover assignments from native and custom bank views, scaling, scrolling, stale callbacks, and teardown; the stand-in host does not draw the outlines or deliver the client's actual drag gestures.

- Keyboard focus in the Tags tab's search field inside Bank Core's mounted column, and tooltips drawn through the mount's overlay.
- How the host positions PrettyUI list rows and scrolls them; right-clicks find rows by where they are drawn, which the stand-in host models.
- How the host clones exports. Bank Core's and Bank Tags' roots are plain tables, and the tests inject an ordinary field-by-field clone of each, but the client's own copy, and whether functions it copies can be called across plugins, are unverified. Bank Tags also falls back to `__bankcore_api` when the shared Lua state has it, and never reads `LIMITS`.
- When the host calls `PluginDependencyUpdate` on reloads, whether it re-injects the global, and whether module caches are scoped per plugin.
- Bank Core's `GetBankBounds()` as screen coordinates for placing the layout editor, that checking it every 10 logic ticks while the editor is open follows a moved bank closely enough (Core gives no move event), and how 80-character names fit the bank header.
- PrettyUI's item slot `SetTooltip` and the item grid in the sprite picker, which the stand-in host does not draw.
- The layout editor's item names: that its drag surfaces hear hover over the grids and results, and that a name beside the editor stays in front of it. The stand-in host's tooltips record their text and target; they are not drawn.
- The layout editor's arrow keys, Ctrl+C, Ctrl+V, Ctrl+Z, and Ctrl+Y: that the client sends `KeyDown` with the documented `GameKey` values with the grid pressed. Shortcut matching uses the native `ModifierKey` enum and held-key queries instead of hard-coded masks. The [keyboard reference](https://developer.runescape.com/rs/core/keyboard.html) documents Shift = 1, Ctrl = 2, and Alt = 4. `ONKEY` is a general key hook, so it must not clear grid focus; actual field clicks and content changes do that. Debug logging records shortcuts for diagnosis. Tests deliver general field hooks before shortcut events to check this distinction.
- Editor drags keep the originally pressed surface as their input owner. Each surface spans the editor with its coordinate origin at the editor's origin, inside a parent layer that clips it to its pane. A drag expands that clip and compensates the child's position, leaving the input origin unchanged; release restores the clip. The user's recording caught a ghost displaced by the old pane offset when a queued event crossed the former origin change. Tests replay pre-click coordinates after the clip expands. Hold/repeat points still come from the same pressed surface, with no hover handoff or native drag overrides. Ghost contents are built in hidden, positioned layers and appear after four interface units of movement. Native clipping and the corrected rendering still need live client verification.
- The Edit row submenu as the client draws it beside the editor, and that picking a child acts once and reaches nothing beneath; the tests run PrettyUI's real `AddSubmenu`, not its drawn rows.
- The editor's horizontal tag tabs use native BANK_TABS_HORIZONTAL inactive, active, and hovered sprites at 48×38, with 22px associated-object icons or a UTF-8 initial. Tooltips render in the editor overlay. Tab order follows the Tags tab, including folder members. Overflow reserves left/right arrow buttons; arrows and wheel input scroll without changing the selected tag. Selecting a tag keeps it visible. Verify states, overflow, clipping, and tooltip placement in the client. Use SetAssociatedObject for item icons; object IDs are not built-in sprite IDs.
- Unsorted, Layout, and Search are independent scrolling areas in that order. Search's input surface clips to the right list and can retain drag capture across both grids; no tab state gates input or scrolling. Hovering a search result uses the editor's passive item-name tooltip, so narrow result labels remain readable. Verify drag routing between all three columns and tooltip placement in the client.
- The editor's status line, outlines, and headings as the client draws them: one inward `Rectangle` outline per frame and selected cell, and the gold selection outlines staying above the grid's cells.
- The layout editor's group selection: that `Keyboard.IsShiftDown` reads Shift at the moment the grid's surface hears the press, that a drag surface's click and release arrive in that order for a Shift-click, and how the translucent gold and red drop cells and the group's count draw over the grid while it scrolls. The stand-in host sets Shift directly.
- Dragging Tags rows to reorder them. PrettyUI's row click reports each press, and the selection or folder toggle now waits for the row's release. The drag relies on four host behaviours the stand-in host only models: the pressed row hears `ONRELEASE` or `ONDRAGCOMPLETE` when the button is released; the pressed row keeps hearing `ONHOLD` or `ONDRAG` after it is stretched under the pointer; it hears `ONMOUSELEAVE` when the pointer leaves it; and the wheel still scrolls the list through PrettyUI's own row listener while held. Drop positions come from the calibrated mouse position, never from the drag events' own coordinates, which were wrong at 125% Windows scaling. The ghost, the gold drop line, and how a stretched row draws over the others are unverified.
- The folder submenu as the client draws it beside a Tags row menu, and that clicking one of its folders moves the tag once and reaches no Tags row beneath; the tests run PrettyUI's real `AddSubmenu` and its clear-then-act order, not its drawn rows.
