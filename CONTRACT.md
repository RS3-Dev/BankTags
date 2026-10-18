# Bank Tags contract

This describes what Bank Tags offers other plugins, what it uses from Bank Core and the host, and the behavior both rest on. Like Bank Core's API it has no version number: nothing has shipped, so a change updates this document and the tests. The share-code format `bankutilities-tags` version 3 is a data format and stays readable.

## Plugin identity

- Plugin name `banktags`. PrettyUI is required; `bankcore` and `runeql` are optional dependencies (see the README for why Bank Core is optional).
- The entry returns the public API below as the injected `banktags` global and publishes it as `_G.__banktags_api`. The running session is `_G.__banktags_session`; a new load shuts it down first. Both are cleared only while they still hold this load's values.
- Event and hook names start with `banktags_`. Saved data uses `banktags:tags:v3:manifest`, `banktags:tags:v3:<a|b>:<n>` chunks, and `banktags:settings:v1`.

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

- The root offers `RegisterExtension(ownerID, label)`, `GetState()` (`{ running }`), and `LIMITS`. Plugins should check each call's result rather than rely on `LIMITS`, which a host that clones exports may not keep.
- A handle offers `RegisterImportProvider`, `UpdateImportProvider`, `RemoveImportProvider`, `GetState()` (`{ running, live, providers }`), and `Dispose()`. A newer `RegisterExtension` with the same owner ID replaces the older owner and its sources; its handle then answers `stale_handle`. Bank Tags shutting down refuses every later call with `stale_api` or `stale_handle`.
- A provider is a plain table of `label`, `icon` (a PrettyUI sprite-button name), `input` (`"text"` or `"action"`), `prompt`, `placeholder` (text sources) or `actionLabel` (action sources), `unavailable` (a short reason the source cannot be used now), and `request`. Labels are 1 to 64 characters without markup. Up to 16 sources in all and 4 per owner.
- Requests start on a logic tick, never inside a window event. `request.input` holds the text; `Resolve(draft)` and `Fail(message)` answer once; `IsCurrent()` reports whether the answer is still wanted. Changing the source or input, closing the window, updating or removing the source, or the owner going makes the request stale and calls the cancel function the provider returned. Answers arrive in the window on a later tick.
- A draft is `{ tags = { { name, icon, folder, rows, items } } }`: up to 32 tags and 2,000 entries in all. Rows are `{ label = text }` or lists of object IDs, config names, and `false` blanks; a repeated object takes its next copy; a config name this client cannot resolve is kept by name in place. Bank Tags checks the whole draft before showing it, and nothing is saved until the player presses Import. One import commits once or not at all.

## What Bank Tags uses from Bank Core

Only the public owner API in Bank Core's `HOST_CONTRACT.md`:

- `RegisterExtension("banktags", "Bank Tags")`, one mounted tab `tags`, one page `tag` updated with the key `tag:<name>`, `SetItemMenu`, `SetListener`, `GetBankItems`, `BeginItemPick`, `UpdateItemPick`, `EndItemPick`, `OpenPage` and `LeavePage` (the mounted context's when the tab is shown, for Core's View All guidance), `GetState`, and `Dispose`.
- `onState` gives readiness, `columns`, and `bounds`. The layout editor opens only with bounds, is placed and sized from them, lays rows out at `columns`, moves when the bounds move, and reopens when the size or columns change. Bank windows close when the reason is `bank_closed` or `not_ready`, and when Bank Core disconnects.
- `onPage` says which tag is shown. `onBankItems` is followed by `GetBankItems`; while that answers `building`, Bank Tags keeps the last snapshot and waits for the next notice, never polling.
- The tab's `onMenu` and `onItemDrop` give pointer positions in the column; Bank Tags finds the row drawn there, including in a scrolled list. Menu entries are added with `menu:Add(label, action, subject)`, at most six per menu. Actions run on a later tick; Bank Core drops one whose page, key, or mounted column changed.
- Mount, menu-building, and drop callbacks never open or leave a page, which Bank Core refuses there. A drop on New Tag creates the tag and opens the name window instead. Row clicks, footer buttons, and menu actions run outside those callbacks.
- Bank Tags never subscribes to `MiniMenuReady`, never reads native bank components, and never requires a Bank Core module.

## Page conversion

A tag becomes `{ title, key = "tag:<name>", layout = rows }`:

- Labels become `{ label = text }`, rows become `{ slots = ... }`, and a deliberately empty row stays `{ slots = {} }`.
- A first copy is its object ID; a later copy or ghost is `{ item, copy, source }`. An item this client cannot resolve, or a copy the page already shows, becomes `false` in place.
- Unsorted items follow under `{ label = "Unsorted" }` in one row, only when there are any.
- The page counts at most 10,000 entries, Bank Core's limit. Edits and imports keep a tag within 9,998 so Unsorted always fits. A larger saved tag gets a notice page (`body` with one plugin block) saying how many entries it has; its saved data is not cut.

## Host behavior Bank Tags relies on

Checked with Bank Core's stand-in host only; see the README's list of what is not yet verified live. In particular: PrettyUI list row positions and scrolling, tooltips through the mount overlay, keyboard focus in the mounted column, how the host clones exports and calls `PluginDependencyUpdate` on reloads, whether module caches are per plugin, and Bank Core's `bounds` as screen coordinates.
