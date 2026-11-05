# Bank Tags tests

Run every test, the build, and the compile and globals check from the repository root:

```text
lua54 tools/check.lua
```

Tests that load Bank Core read it, unchanged, from the checkout named by `BANKCORE_ROOT`, or from `../bank-utils-core` when it is unset. They use Bank Core's own stand-in host (`tools/test_support/fake_bank_host.lua` and `fake_plugin_host.lua` in that checkout) and load Bank Core's `main.lua` with its own module cache, beside the Bank Tags folder the build writes under `dist/test/`. Nothing from Bank Core is copied into Bank Tags or its package.

The runtime must support omitted page titles (Core 1.4.0). To test an installed package without its test tools, set `BANKCORE_ROOT` to that package and add the Core checkout's `?.lua` path to `LUA_PATH` for the stand-in host. This runs the installed runtime unchanged; it does not adapt the older runtime to accept title-free pages.

```text
set BANKCORE_ROOT=C:\path\to\bank-utils-core
lua54 tools/check.lua
```

Menus load PrettyUI's real `src/minimenu.lua`, read-only, from the checkout `PRETTYUI_ROOT` names, so the folder submenu is placed and checked by PrettyUI's own `MiniMenu.AddSubmenu`, and PrettyUI clears its submenu state on each new menu before the plugins answer, as it does as a dependency. Drawing the submenu and hovering its parent need the client, so a test chooses a child by running PrettyUI's close handler and then the child's action, the order PrettyUI's row click uses; PrettyUI's own `tests/minimenu_test.lua` covers the drawn submenu.

```text
set PRETTYUI_ROOT=C:\path\to\prettyui-checkout
```

The check prints which Bank Core and PrettyUI checkouts and commits the tests loaded. A checkout whose `docs/API.md` lacks the public API Bank Tags uses (`bankcore.Register(spec)`, `GetBankBounds`, and the menu item's `slot`) is refused with a message rather than tested against, so an older sibling checkout cannot fail or pass the tests for the wrong reason. New test files run before they are committed, too.

The stand-in host is not the game client: these tests show Bank Tags' behavior against Bank Core's public API under that model, not how the live client draws, scrolls, or delivers input.

The page-notice test checks that errors use the bank's top-center overlay, keep the sidebar list and footer intact, clear after a successful choice, and disappear on unmount or unload. Banner appearance and text wrapping still need a client check.

The harness reads Bank Tags' required dependencies from the client's `requiredDependencies` field before adapting them for Core's older stand-in loader. The manifest regression test checks that PrettyUI is injected and the sidebar mounts, so the obsolete `dependencies` field cannot silently pass.

The tutorial overlay test separates the game area and bank into distinct render branches. It checks that the guide draws above the bank and editor, aligns with native component coordinates, and hides targets scrolled out of view. Actual sprite rendering still needs verification in the client.

Shared-dialog tests load PrettyUI's real `src/dialog.lua` with native window and leaf-control stand-ins. They cover footer actions, rejected edits, Cancel, X, bank close, and reload. Import/Share tests cover pasted codes, full backups, overrides, failed-save retries, invalidated previews, and stale icon-picker results. External import providers are no longer part of the plugin.

Editor tests press pane-local points through `Harness:PressEditor`, which converts them to the pressed surface's constant editor-origin coordinates. They dispatch native hover/repeat and release points in those same units (`Harness:ReleaseEditor`). Pointer regressions replay a queued pre-click point after the clipping region expands, verify that the input origin never changes, and move and complete a drag using only the original surface's events. Pointer and item-name regressions reject every editor read of Mouse.GetPosition, covering different rows, independent scrolling, misleading raw mouse values, hidden ghosts before movement, group grabs, search/label grabs, completions whose end point is not the pointer, and cancelled drops after leaving the capture. Keyboard tests deliver general `ONKEY` hooks before shortcuts, independently of input focus, and use the documented native modifier enum. Item-name tests load PrettyUI's actual tooltip controller with native UI stand-ins. They check transient leave/re-enter events and that stationary hover does not re-show the tooltip or reorder the window each tick.

The redraw test counts native components on a 200-item tag: selecting, Shift-toggling, clearing, choosing a paste cell, and bank quantity changes keep every grid cell and item sprite, moving reusable outlines instead; a saved layout change rebuilds the grids. The lifecycle test checks horizontal bank tabs' native active/hover/inactive states, item sprites, UTF-8 initials, full-name tooltips, overflow arrows, wheel movement, and tag changes. Pane tests check the Unsorted → Layout → Search order, five-column Unsorted wrapping, default and wider/taller bank geometry, independent scrolling, source-aware drag capture, and both item sources staying visible. Search-name coverage checks that only clipped labels get full-name tooltips. Closing, reopening, and shutting down during a drag or prompt must leave no editor listener, tooltip, or prompt behind.

Group-to-Unsorted coverage checks the footer button, context menus on selected and unselected items, append order, one-step undo/redo, and complete rollback if the final save fails.

`editor_unsorted_menu_test.lua` covers Unsorted item menus across menu insertion orders, first-open-slot placement, labels and reserved slots, full/empty layouts, duplicate objects, undo/redo, failed saves, and stale menus after a save, tag change, or close.
