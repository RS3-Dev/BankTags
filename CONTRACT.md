# Bank Tags contract

This describes what Bank Tags uses from Bank Core and the host, and the behavior both rest on. Bank Core is a fixed external dependency; Bank Tags uses its existing public API. The share-code format `bankutilities-tags` version 4 stays readable; earlier versions are not read.

## Plugin identity

- Plugin name `banktags`. PrettyUI is required; `bankcore` and `runeql` are optional dependencies (see the README for why Bank Core is optional).
- Bank Tags exports no plugin API. The running session is `_G.__banktags_session`; a new load shuts it down first, and shutdown clears the key only while it still holds that session. Reload also clears the old `__banktags_api` export from versions with import providers.
- The tutorial retains its owned UI layer as `_G.__banktags_tutorial_root` until that layer is released. A new session removes a retained layer and the tutorial's old event listeners, so an interrupted close does not strand its UI across reloads.
- Event and hook names start with `banktags_`. The manifest sets `hasRibbonIcon` to `false`; Bank Tags draws its preferences on the plugin panel `Event.ContentLayerReady` gives it. Saved data uses `banktags:tags:v4:manifest`, `banktags:tags:v4:<a|b>:<n>` chunks, and `banktags:settings:v1`.

## Import and shared dialogs

- Import/Share reads pasted version 4 share codes and full backups. A preview saves nothing; a single tag can override its name, icon, and folder before one import commits. Multiple-tag backups retain their individual settings. External import providers and their registration API have been removed.
- Name prompts and removal confirmations use PrettyUI's `Dialog` for footer actions and window cleanup. A rejected save keeps the dialog open with its reason; successful saves, Cancel, and X release it. The plugin releases its dialog controllers on bank close and reload.

## What Bank Tags uses from Bank Core

Only the public API in [Bank Core's `docs/API.md`](https://github.com/RS3-Dev/bank-utils-core/blob/main/docs/API.md):

- `bankcore.Register{ id = "banktags", name = "Bank Tags", icon = "LIST_LAYOUT", column, onClose, onBankItems, onBankClose }`, read from the injected `bankcore` or `_G.__bankcore_api`. Bank Tags registers when it loads and again when `PluginDependencyUpdate` reports `bankcore` enabled, replacing its earlier registration, and calls `Dispose` when `bankcore` is disabled and at shutdown. Its extension uses `SetPage`, `Open`, `Close`, `IsOpen`, `GetBankItems`, `GetBankBounds`, `GetMenuItem`, and `Dispose`.
- The rail icon's column is the Tags tab. It reads `ctx.width` and `ctx.height`, and has `resize` so Core keeps it mounted and the search keeps its focus. Tooltips draw in `ctx.overlay`.
- Preferences on Bank Tags' own plugin panel, built each time the host gives the panel and destroyed at shutdown; they need no Bank Core. They save in Bank Tags' own `banktags:settings:v1`, and a refused save puts the control back with a message on the panel.
- `GetBankBounds()` places and sizes the layout editor, which lays rows out at its `columns` and opens only while it answers. Core reports no bank move, so while the editor is open Bank Tags checks the bounds every 10 logic ticks, and also on `onBankItems` and when the column resizes: the editor moves with the bank, and reopens, rather than closing, when the size or columns change. The tutorial places its panel beside the same bounds.
- `onBankClose` ends select mode, stops the tutorial, and closes the bank windows (the layout editor, tag settings, the delete confirmation, and text prompts); Import/Share stays. They also close when Bank Tags disconnects.
- Bank Tags keeps its own tags. Clicking a tag row sets that tag's page with `SetPage` and then calls `Open`; clicking the shown tag calls `Close`. Bank Tags remembers the tag it set last; that tag is shown while `IsOpen()` is true, and `onClose` redraws the Tags tab when it stops. A refusal from `Open` (`not_all_items`, `preset_open`, `bank_closed`, `busy`) is explained in the Tags tab's status line, which a shown tag clears. A change to the shown tag (an edit, import, or rename) sets its page again, which Core redraws in place; a deleted tag is closed. Nothing is set while another page or the native view shows, so a change never takes the bank from them.
- `onBankItems` is followed by `GetBankItems`, whose `{ objectID, quantity }` stacks feed the layout editor's quantities and the sprite picker's and editor's limited search. While it refuses, Bank Tags keeps the last list.
- Menus are Bank Tags' own. It subscribes to `MiniMenuReady` while connected and asks `GetMenuItem(menu)` which bank item the menu belongs to. In select mode it makes "Add to <tag>" the left click over any bank item, adding a slot for its `objectID`. On its own shown page it offers Remove from, which removes the clicked `slot`: Bank Tags maps the slot's position among the page's slot entries back to the saved slot it set there. With no bank item, it finds the Tags row beneath the pointer from the mounted column. Its helper (`banktags/ui/menu_entries.lua`) finds each entry it adds, whatever place the host gave it, and keeps the existing left click. Over a row it adds the row's actions on top, shown in order with Select (or Expand and Collapse) as the left click and Cancel last. A tag row's last action is a folder submenu added with PrettyUI's `MiniMenu.AddSubmenu` at the displayed row just below the others; without `prettyui.MiniMenu` the row has no submenu. An entry that cannot be found leaves Cancel the left click.
- A chosen entry runs on the next logic tick, and only while, both when chosen and when it runs, the extension is the same and the layout editor is closed. Remove from also needs the same page revision, which Bank Tags bumps on each `SetPage`, with its tag still shown; Add to needs the same select-mode session. Row entries need the same column and list mounted and no row clicked after the menu was built. A row answers its own left click, which the client may also deliver to the menu's default before or after the row hears it, from the menu built before the click or one rebuilt after it; so a row entry acts only when chosen from an opened menu (heard through `MiniMenuOpened`, after which the client stops rebuilding the menu), and at most one entry of that menu acts. Select toggles the tag like a row click.
- Select mode is Bank Tags' state. Starting it closes Bank Tags' shown page; showing a tag, Done, deleting the tag, or the bank closing ends it. Adding is object-level, so it works in any bank tab.
- Bank Tags never requires a Bank Core module. Select-mode highlights and bank-item drops use the client's native components directly, as described below.

## Native item interactions

- `banktags/tags/native_items.lua` reads interface 517's item layer (201) directly. While connected and the bank is open, it checks wrappers every 10 logic ticks, and refreshes immediately when Core reports bank items or select mode starts. Unchanged wrappers keep their hooks. Bank close, disconnect, and shutdown remove Bank Tags' named hooks and cancel pending drops.
- Select mode outlines the tag's item slots, stocked stacks before placeholders and otherwise in native bank order. Only `outlineWidth` and `shadowRGBA` change; their original values are restored when selection ends, wrappers change, or the tag's membership changes. Bank Tags restores them before asking Core to open a tag page, so its highlights are not copied into that page. A refused page restores the active selection's highlights.
- Native `ONDRAG` captures the dragged object's ID, and `ONDRAGCOMPLETE` captures the tag row the client reports as hovered through `isMouseOver`. Target selection does not read mouse coordinates or apply scale conversions. Folder headers, hidden or disabled rows, and the layout editor do not accept drops; scrolling and clipping follow the client's hover state. The source's completed-drag arguments are not used as item identity or pointer coordinates.
- Assignment runs on the next logic tick, after native drag handling. It needs the same extension and mounted column, an existing target tag, an open bank, and no layout editor. A repeated drop adds another item slot. Only Bank Tags' listeners are removed; native behavior and other plugins' named listeners remain.

## Page conversion

A tag becomes `{ rows }`, with no page title or reserved title space:

- Labels become `{ label = text }`, rows become `{ slots = ... }`, and a deliberately empty row stays `{ slots = {} }`.
- Each item slot is its object ID; a blank, or an item this client cannot resolve, is `false` in place. An object listed again keeps each slot, and Core shows its next stack there, then a ghost.
- Unsorted items follow under `{ label = "Unsorted" }` in one row, only when there are any.
- The page counts at most 10,000 entries, Bank Core's limit. Edits and imports keep a tag within 9,998 so Unsorted always fits. A larger saved tag is not shown; the Tags tab's status line says how many entries it has, and its saved data is not cut.

## Host behavior Bank Tags relies on

Checked with Bank Core's stand-in host only; see the README's list of what is not yet verified live. In particular: PrettyUI list row positions and scrolling, the folder submenu as the client draws and clicks it, tooltips through the mount overlay, keyboard focus in the mounted column, how the host clones exports and calls `PluginDependencyUpdate` on reloads, whether module caches are per plugin, and Bank Core's `bounds` as screen coordinates.
