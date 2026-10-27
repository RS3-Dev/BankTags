# Bank Tags contract

This describes what Bank Tags offers other plugins, what it uses from Bank Core and the host, and the behavior both rest on. Like Bank Core's API it has no version number: nothing has shipped, so a change updates this document and the tests. The share-code format `bankutilities-tags` version 3 is a data format and stays readable.

## Plugin identity

- Plugin name `banktags`. PrettyUI is required; `bankcore` and `runeql` are optional dependencies (see the README for why Bank Core is optional).
- The entry returns the public API below as the injected `banktags` global and publishes it as `_G.__banktags_api`. The running session is `_G.__banktags_session`; a new load shuts it down first. Both are cleared only while they still hold this load's values.
- Event and hook names start with `banktags_`. The manifest sets `hasRibbonIcon` to `false`, and Bank Tags does not subscribe to `Event.ContentLayerReady`. Saved data uses `banktags:tags:v3:manifest`, `banktags:tags:v3:<a|b>:<n>` chunks, and `banktags:settings:v1`.

## Public API: import sources

Another plugin adds sources to Bank Tags' Import window. It declares `banktags` as an optional dependency, reads the injected global or `_G.__banktags_api`, and follows `PluginDependencyUpdate` as Bank Tags does for Bank Core.

```lua
local owner, reason = banktags.RegisterExtension("example.guides", "Guides")
owner:RegisterImportProvider("guide", {
    label = "Guide", input = "text", prompt = "Guide address", placeholder = "Paste an address...",
    request = function(request)
        -- later: request:Resolve({ tags = { { name = "Melee", rows = { { 4151, false, "abyssal_whip" } } } } })
        -- or:    request:Fail("Guide not found")
        return function() --[[ the request is no longer wanted ]] end
    end,
})
owner:Dispose()
```

- The root offers `RegisterExtension(ownerID, label)`, `GetState()` (`{ running }`), and `LIMITS`. The host clones a loaded dependency's export before injecting it, so the root is a plain table with no metatable, and `LIMITS` is a plain copy: a clone that copies fields through `next` keeps every one. Callers must not change the root or `LIMITS`; a change reaches no Bank Tags state, but the published `__banktags_api` copy is shared. The owner registry lives behind the functions and is never in the root. Plugins should still check each call's result rather than rely on `LIMITS`.
- Handles are not exports: `RegisterExtension` returns one to its caller, and it stays read-only.
- A handle offers `RegisterImportProvider`, `UpdateImportProvider`, `RemoveImportProvider`, `GetState()` (`{ running, live, providers }`), and `Dispose()`. A newer `RegisterExtension` with the same owner ID replaces the older owner and its sources; its handle then answers `stale_handle`. Bank Tags shutting down refuses every later call with `stale_api` or `stale_handle`.
- A provider is a plain table of `label`, `icon` (a PrettyUI sprite-button name), `input` (`"text"` or `"action"`), `prompt`, `placeholder` (text sources) or `actionLabel` (action sources), `unavailable` (a short reason the source cannot be used now), and `request`. Labels are 1 to 64 characters without markup. Up to 16 sources in all and 4 per owner.
- Requests start on a logic tick, never inside a window event. `request.input` holds the text; `Resolve(draft)` and `Fail(message)` answer once; `IsCurrent()` reports whether the answer is still wanted. Changing the source or input, closing the window, updating or removing the source, or the owner going makes the request stale and calls the cancel function the provider returned. Answers arrive in the window on a later tick.
- A draft is `{ tags = { { name, icon, folder, rows, items } } }`: up to 32 tags and 2,000 entries in all. Rows are `{ label = text }` or lists of object IDs, config names, and `false` blanks; a repeated object takes its next copy; a config name this client cannot resolve is kept by name in place. Bank Tags checks the whole draft before showing it, and nothing is saved until the player presses Import. One import commits once or not at all.

## What Bank Tags uses from Bank Core

Only the public owner API in Bank Core's `HOST_CONTRACT.md`:

- `RegisterExtension("banktags", "Bank Tags")`, one mounted tab `tags`, `CreatePage` with the key `tag:<name>` and `LeavePage` (the mounted context's when the tab is shown, for Core's View All guidance), `SetListener`, `GetBankItems`, `GetMenuItem`, `SetItemHighlight`, `SetSettings`, `GetState`, and `Dispose`. A Bank Core whose handle has no `CreatePage` is too old: Bank Tags disposes the handle and writes to the host log that Bank Core needs updating.
- One settings section through `SetSettings({ mount })`, labelled with the owner label. Its controls are built when Bank Core mounts it and destroyed on `unmount`; the preferences stay in Bank Tags' own `banktags:settings:v1`, and a refused save puts the control back with a message in the section. Disposal on disconnect or shutdown removes the section.
- `onState` gives readiness, `columns`, `bounds`, and `highlighted`. The layout editor opens only with bounds, is placed and sized from them, lays rows out at `columns`, moves when the bounds move, and reopens, rather than closing, when the size or columns change.
- `onBankClose(reason)` closes the bank windows (the layout editor, tag settings, the delete confirmation, and text prompts) when the bank closes, the game state is lost, or Bank Core stops with the bank open; Import/Share stays. They also close when Bank Core disconnects. Readiness is not read for this: Bank Core can report `building` rather than `bank_closed` when the bank inventory goes before its window.
- Bank Tags keeps its own tags and builds a tag's page each time it shows it; Bank Core keeps only the page it shows. `onPage(visible, key)` says which tag is shown. A change to the shown tag (an edit, import, rename, or item change) draws it again with `CreatePage` only while `GetState().pageVisible` says Bank Core still shows Bank Tags' page, so a change never takes the bank from another plugin's page or the native view the player chose; a click on the tag shows it again. `onBankItems` is followed by `GetBankItems`; while that answers `building`, Bank Tags keeps the last snapshot and waits for the next notice, never polling.
- The tab's `onItemDrop` gives the pointer position in the column; Bank Tags finds the row drawn there, including in a scrolled list.
- Menus are Bank Tags' own. It subscribes to `MiniMenuReady` while connected and asks `GetMenuItem(menu)` which bank item the menu belongs to. Over a native item in select mode it makes "Add to <tag>" the left click; on its own shown page it offers Remove from over the slot's own copy (a borrowed slot or ghost names its copy, not the stack beneath). With no bank item, it finds the Tags row beneath the pointer from the mounted column's position and `ctx:GetBounds()`. Its helper (`banktags/ui/menu_entries.lua`) finds each entry it adds, whatever place the host gave it, and keeps the existing left click. Over a row it adds the row's actions on top, shown in order with Select (or Expand and Collapse) as the left click and Cancel last. A tag row's last action is a folder submenu added with PrettyUI's `MiniMenu.AddSubmenu` at the displayed row just below the others; without `prettyui.MiniMenu` the row has no submenu. Each row action and submenu child acts once, on the next tick, only if picked from the opened menu while the tab, list, row clicks, tag, and (for a folder) folder are unchanged. Bank Core leaves that plugin entry the left click over the tab's content, and promotes Cancel over ghosts, displaced stacks, and header launchers, before or after Bank Tags answers. An entry that cannot be found leaves Cancel the left click.
- A chosen entry runs on the next logic tick, and only while, both when chosen and when it runs, the handle is the same, `GetState().viewID` equals the item's (for item entries), the tag and the member still exist, and for row entries the same column and list are mounted and no row was clicked after the menu was built. A row answers its own left click, which the client may also deliver to the menu's default before or after the row hears it, from the menu built before the click or one rebuilt after it; so a row entry acts only when chosen from an opened menu (heard through `MiniMenuOpened`, after which the client stops rebuilding the menu), and at most one entry of that menu acts. Select toggles the tag like a row click. In select mode, a native item with no known copy, or a highlight Bank Core has cleared, gets Cancel as its left click instead of Withdraw.
- Select mode is Bank Tags' state. Bank Core only draws the outline through `SetItemHighlight` and clears it whenever a page or another view needs the bank's own looks; Bank Tags ends select mode when `onState` reports `highlighted` false, saying why when the bank cannot show it.
- Mount and drop callbacks never open or leave a page, which Bank Core refuses there. A drop on New Tag creates the tag and opens the name window instead. Row clicks, footer buttons, and menu actions run outside those callbacks.
- Bank Tags never reads native bank components and never requires a Bank Core module.

## Page conversion

A tag becomes `{ title, key = "tag:<name>", layout = rows }`:

- Labels become `{ label = text }`, rows become `{ slots = ... }`, and a deliberately empty row stays `{ slots = {} }`.
- A first copy is its object ID; a later copy or ghost is `{ item, copy, source }`. An item this client cannot resolve, or a copy the page already shows, becomes `false` in place.
- Unsorted items follow under `{ label = "Unsorted" }` in one row, only when there are any.
- The page counts at most 10,000 entries, Bank Core's limit. Edits and imports keep a tag within 9,998 so Unsorted always fits. A larger saved tag gets a notice page (an empty `layout` whose `mount` draws the text) saying how many entries it has; its saved data is not cut.

## Host behavior Bank Tags relies on

Checked with Bank Core's stand-in host only; see the README's list of what is not yet verified live. In particular: PrettyUI list row positions and scrolling, the folder submenu as the client draws and clicks it, tooltips through the mount overlay, keyboard focus in the mounted column, how the host clones exports and calls `PluginDependencyUpdate` on reloads, whether module caches are per plugin, and Bank Core's `bounds` as screen coordinates.
