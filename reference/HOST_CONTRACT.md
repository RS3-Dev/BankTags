# Page, tab, import-source, and header-launcher API v1 and host contract

Status (2026-10-17): Stage 5 is implemented on `refactor/extensibility-plan` and,
with its third revision (`ac9a90e`), accepted by the root review and Grok. Stage 6 adds
sidebar tabs to the same development API v1 (`RegisterTab`, `UpdateTab`, `RemoveTab`);
it (`a5a0d47`) is accepted by the root review and Grok, and its geometry is checked only
against fake host components. Stage 6a adds import sources (`RegisterImportProvider`,
`UpdateImportProvider`, `RemoveImportProvider`) to the same API; with its review
revision 1 (`304c16f`) it is accepted by the root review and Grok, with no live client
check. Stage 7 adds bank-header launchers (`RegisterLauncher`, `UpdateLauncher`,
`RemoveLauncher`); it (`48c76af`) is accepted by the root review and Grok, and its
placement is computed from stand-in components and a logged component dump, never
measured live. Stage 8 adds no API: `examples/questhelper-lite` is a full-path
consumer of all four surfaces, checked against the fake host only (`b66754e`), and is
accepted; commits through `b66754e` are pushed. Stage 9 adds no custom sidebar mounts
(see the end of the API reference). Stage 10a moved the bank core behind an internal
feature boundary inside one plugin (`099fbd8` through `07d201c`); it is accepted by the
root review and Grok, and commits through `07d201c` are pushed. Stage 10b (`a554c3a`
through `46db7f7`; accepted by the root review and Grok) splits the code into two plugins
built from this tree: **Bank Core** (`bankcore`) serves this API, and **Bank
Utilities** (`bankutils`) attaches its features to it (see "Core and feature
boundary"). The API is unchanged except for its name: dependents now use the
`bankcore` global and `_G.__bankcore_api`. This file describes a **development contract** that the code and
tests support. It is **not frozen**. No live client probe has run, so every statement
here about how the game host loads, reloads, injects, or unloads plugins is either
cited evidence or a fake-host assumption, and is labelled as such. The user
authorized continuing without a manual pause; the probe below is still owed before
the contract freezes.

## What the host is known to do

No live client probe was run, and the Jagex loader is not in these repositories.
The facts below come from Grok's research on 2026-10-17, which used the community
type package [rs3-api-ts](https://github.com/Rs3-Plugins/rs3-api-ts), PrettyUI 1.2.1,
and the local producer plugins. `RSDevSync/docs/plugin-system` states that it is not
an official client specification.

### Cited

- **Dependency global.** rs3-api-ts `docs/errors.md`: the client sets a library
  global only when the library is listed under `requiredDependencies` or
  `optionalDependencies`. The global name is the manifest key. Without that
  declaration the global is nil. The client resolves dependencies by mod.io id,
  and that package's checker rejects a string value (`"<field>.<name>" must be a
  positive mod.io id`).
- **What producers publish.** RuneQL (`RSDevSync/plugins/runeql/main.lua` lines
  17–30) and GE Prices (`geprices/main.lua` lines 9–17) both return their API
  table and also store that exact table in `_G` (`__runeql_api`,
  `__geprices_api`). Their `PluginShutdown` clears the key only if it still holds
  their table. Inventory Cache returns its table and publishes no `_G` copy.
  Nothing in RuneQL assigns the `runeql` global, so that name exists only when
  the host injects the return value.
- **Lifecycle hooks.** `packages/core/types/plugin/Lifecycle.d.ts` declares
  `PluginLogic`, `PluginDraw`, `PluginShutdown`, and
  `PluginOptionalDependencyChanged`, whose event is
  `{ pluginIdentifier: string, loaded: boolean }` (also
  `Event.OptionalDependencyChanged`). The type package says nothing about
  shutdown order, whether reload re-injects dependency globals, or whether a
  missing required dependency blocks loading.
- **Events.** `EventSource.d.ts` declares `Subscribe(id, handler)` and
  `Unsubscribe(id)`. It does not say whether ids are per plugin or global.
- **Module cache.** The sandbox omits `os`, `io`, `debug`, `load`, `loadstring`,
  `dofile`, and `loadfile`, and `package` is undocumented. Bank, RuneQL, and the
  PrettyUI consumers clear their own `package.loaded` keys on startup. That
  shows one plugin keeps its cache across a reload. It does not show that two
  plugins share a cache. `rs_plugins/docs/shared-lua-modules.md` lines 19–24
  says modules load from each plugin's folder, so shared code must be copied
  in. `require("lib/...")` does not reach another plugin.

### Not established

- Whether hot reload drops an injected dependency global. Bank's own `main.lua`
  comment assumes it does. No host source says so.
- `PluginShutdown` order between a library and the plugins that depend on it.
- Whether all plugins run in one Lua VM, or share one `_G` or `package.loaded`.
- Whether `Event` ids collide across plugins.
- Whether a callback can still run after `Unsubscribe` (see `STAGE0_BASELINE.md`).
- Whether the hub client accepts string dependency values such as
  `"runeql": "runeql"`.
- Whether returning a table from a non-library plugin's `main.lua` has any host
  effect. Bank Core returns its API table; Bank Utilities returns nothing.
- Whether the host notifies a plugin, or re-injects its global, when a *required*
  dependency reloads. `PluginOptionalDependencyChanged` is declared for optional
  dependencies; Bank Utilities requires Bank Core.
- Whether `ContentLayerReady` reaches each plugin with its own panel component when
  two plugins both subscribe to it.

## How Bank Core publishes the API

`plugins/bankcore/main.lua` builds one bank session (`lib/core/bank_session.lua`),
starts it, returns `session.publicAPI`, and stores the same table at
`_G.__bankcore_api`. The client injects the returned table into dependents that list
`bankcore` (cited above). `PluginShutdown` closes the API and clears that key only if it
still holds this table. On reload, the previous session (found at
`_G.__bankcore_session`) shuts down before modules are evicted, and the previous table is
unpublished. The previous table and its handles then refuse every call.

Until Stage 10b this API was served by the single Bank Utilities plugin as the
`bankutils` global and `_G.__bankutils_api`. Those names are retired: Bank Utilities no
longer returns or publishes an API, and the examples use `bankcore`.

## Core and feature boundary (internal)

This section describes the private bridge between Bank Core and Bank Utilities. It is
**not** part of API v1, not a sandbox, and not a custom-mount API; consumers must not rely
on any of it. Its code-level contract is in `lib/README.md`.

- **Two plugins, one tree.** `tools/build.lua` builds `dist/bankcore` and `dist/bankutils`
  from the two entries' require graphs. The 17 modules both load are byte-identical
  copies of one source, so neither plugin ever `require`s the other's files (which the
  host does not allow, cited above). Bank Core's manifest depends on PrettyUI `6398181`
  alone; Bank Utilities' requires `bankcore` by the development string `"bankcore"`,
  PrettyUI, RuneQL, and GE prices. Neither plugin's mod.io id is recorded or guessed.
- **One session.** `BankSession.new` builds the bank controller, the native item lease,
  the page, tab, import-source, and launcher registries, and the public table, and
  subscribes to nothing. Only `Start` subscribes to the bank, menu, and game-state events
  (`ContentLayerReady`, `GameStateChanged`, `MiniMenuReady`, `MiniMenuEntrySelected`,
  `InventoryAdded`, `InventoryRemoved`, `InventoryUpdated`), and Bank Core's `main.lua` is
  the only caller. Every core event ID starts with `bankcore_`. A started session that is
  shut down unsubscribes every one before another starts. Bank Utilities subscribes to
  none of these; its only event of its own is `ContentLayerReady` under
  `bankutils_content`, for its own panel, and its features' Logic listeners use the
  `bankutils_` prefix.
- **Core alone.** With no feature attached, the sidebar shows only extension tabs, a
  selection no page claims opens nothing, page content is empty, and import sources
  still register, but every draft is refused with `unavailable`. The core reads neither
  `runeql` nor `geprices`. Bank Core's own panel offers its debug logging and **Reset
  header launchers**.
- **Attaching Bank Utilities.** The API table's `Features` (version 1, separate from API
  v1) has one function, `Attach(hooks, contribution)`. Bank Utilities calls it with its
  app as the hooks (window, sidebar, item, and placeholder menu entries; game suspend and
  resume; bank close; import-source changes; and shutdown) and a contribution with its
  feature ID, its bank-controller features (`lib/features/bank_features.lua`), the draft
  reader, its bank preferences, and its earlier launcher choices. The session attaches
  the features to its own controller and returns a handle that offers only
  `ApplySettings`, `ResetLauncherPreferences`, `Detach`, `IsOpen`, `ClosedReason`, and
  read-only import access (`Sources`, `Begin`, `Cancel`). The bank controller gives the
  features a second handle (`lib/bank/feature_host.lua`) that forwards named calls and
  reads `selectedTag`, `active`, `expanded`, `nativeViewAll`, and `sidebarMode`; it never
  returns the lease, list engine, page snapshot, or native components, and the item
  beneath the pointer comes back as an object ID and layout key only. Bank Utilities'
  page descriptions are still called with the core's controller; that is the one wider,
  documented privilege of this bridge. One feature is served at a time: the same feature
  ID replaces the earlier attachment, another is refused.
- **Lifetime.** `Detach` (Bank Utilities' own shutdown) leaves the feature's page,
  removes its tabs, content, and controls, and closes both handles; the core and other
  plugins' pages keep running. Session shutdown closes both handles too, last, after the
  feature's windows close and the bank is restored. A replaced copy's handles close as
  `replaced`, and that copy refuses to attach again, so it cannot take the attachment
  back from a newer one. This is lifetime hygiene, not a security boundary.
- **Reattaching after a core reload.** The old session closes Bank Utilities' handles as
  it stops. Bank Utilities then reattaches when it next learns of a running core: on
  `PluginOptionalDependencyChanged` for `bankcore` (if the host sends it for a required
  dependency, which is unverified), when its own panel opens (through the injected
  `bankcore` global, or `_G.__bankcore_api` when plugins share `_G`), or when the host
  reruns Bank Utilities. It keeps no reference to the old core and polls nothing. Without
  any of those, its features stay detached and its panel says Bank Core is not running.
- **Function sharing.** Import `request`, launcher `activate`, the feature attach, both
  feature handles, and the session hooks are Lua functions called across the two
  plugins. This works only if both plugins run in one Lua state and can call each other's
  functions; the fake plugin host models separate environments in one state, which is
  not proof of the game host. Isolated VMs with no marshalling would break these calls,
  and no marshalling is provided. Unverified.
- **Module caches.** Both plugins load modules with the same names (`lib/core/config`
  and the rest of the 17). This assumes each plugin has its own `package.loaded`, which
  the cited module-cache evidence suggests but does not establish; if one cache were
  shared, each plugin's eviction would also evict the other's copies of those 17
  modules. Unverified.
- **Saved data.** `bankcore:header_launchers:v1` and `bankcore:settings:v1` belong to
  Bank Core; `bankutils:settings:v1`, the tag manifest and chunks, and the RuneQL keys
  belong to Bank Utilities, with unchanged strings. Whether `PersistentDB` is scoped per
  plugin is not established, so neither plugin reads the other's keys. Instead, Bank
  Utilities reads the launcher choices the single-plugin build saved under its own
  `bankutils:header_launchers:v1` and passes them to the core on attach as plain lists;
  the core adopts them once, validated like saved choices, only while its own key holds
  nothing, and records `importedFrom`. The old key is never written or deleted. If the
  host does share `PersistentDB`, nothing changes, because the keys differ.

## Consumer pattern (development contract)

1. Declare the dependency as optional. During local development, a sibling
   folder on the plugin path can use `"optionalDependencies": { "bankcore":
   "bankcore" }`. That string form is used for `runeql` in this dev client and
   is **not** a hub contract. A hub release needs Bank Core's numeric mod.io
   id, which is not recorded here and must not be guessed; `tools/build.lua
   --dependency-id bankcore=<digits>` writes a known one into built manifests.
2. Read the injected `bankcore` global first and `_G.__bankcore_api` second.
   Accept only a table with `API_VERSION == 1` whose `GetState().running` is true.
3. Call `RegisterExtension` once per API table, and keep the handle.
4. Before each action, check that `handle:GetState().live` is true. If it is not
   because the producer reloaded (the old table's `GetState().running` is false),
   register again on the current table. If it is not but the same table still runs,
   the owner ID was registered again, normally by a newer load of your plugin. Stop
   using that copy instead of registering again, or the older copy takes the owner
   back from the newer one.
5. On `PluginOptionalDependencyChanged` with `loaded == false`, and in your own
   `PluginShutdown`, call `handle:Dispose()` and drop the handle. Close your own
   windows in your own `PluginShutdown`; Bank Core never closes them.
6. Never `require` Bank Core or Bank Utilities modules, never call `Features`, and
   never put callbacks or page tables in `_G`.
7. A hot reload may rerun `main.lua` without calling `PluginShutdown`. A plugin that
   owns windows can call the previous run's `PluginShutdown` at the top of `main.lua`
   when one is defined. This assumes the host reruns a plugin in its own environment;
   every plugin defines its own `PluginShutdown`, so plugins cannot share that name,
   but whether a reload keeps the environment is not established (probe step 11).
8. An Import source that answers later should return a cancel function that forgets
   the request, and should check `Resolve`'s result: `false, "stale_request"` means the
   window no longer wants it. Import sources appear in Bank Utilities' Import/Share
   window; with Bank Core alone they register and every draft is refused.

`examples/questhelper-lite` and `examples/shopping-list` follow this pattern;
`examples/README.md` walks through them. They are scratch plugins for development.
Neither plugin loads them, and they are not meant to be published.

## API v1 reference

API functions use dot calls. Handle methods use colon calls. Every call that can
fail returns `true`, or `false` (`nil` for `RegisterExtension`) followed by a
reason string and sometimes a human-readable detail. API and handle tables are
read-only.

```lua
api.API_VERSION                      -- 1
api.LIMITS                           -- read-only copy of the limits below
api.RegisterExtension(ownerID, label) -- handle | nil, reason, detail
api.GetState()                       -- { running, canOpen, reason }
api.Features                         -- Bank Utilities' private attach; not API v1, do not call

handle.ownerID
handle:RegisterPage(pageID, page)    -- add; never opens or takes the selection
handle:UpdatePage(pageID, page)      -- replace; invalid input keeps the last good page
handle:OpenPage(pageID)              -- show in the bank, or refuse with a reason
handle:RemovePage(pageID)            -- remove; leaves it first if shown
handle:RegisterTab(tabID, tab)       -- add a sidebar tab; never selects it
handle:UpdateTab(tabID, tab)         -- replace; invalid input keeps the last good tab
handle:RemoveTab(tabID)              -- remove; the sidebar returns to its first tab if it was selected
handle:RegisterImportProvider(providerID, provider) -- add an Import source; never selects it
handle:UpdateImportProvider(providerID, provider)   -- replace; invalid input keeps the last good one
handle:RemoveImportProvider(providerID)             -- remove; the window falls back to the share code
handle:RegisterLauncher(launcherID, launcher) -- add a bank-header launcher; never runs it
handle:UpdateLauncher(launcherID, launcher)   -- replace; invalid input keeps the last good one
handle:RemoveLauncher(launcherID)             -- remove; a waiting press is dropped
handle:Dispose()                     -- remove the owner, its pages, tabs, sources, and launchers
handle:GetState()                    -- { running, canOpen, reason, live, pages, openPage,
                                     --   tabs, activeTab, importProviders, launchers }
```

`tabs` lists the owner's tab IDs in registration order. `activeTab` is the
owner's tab the sidebar is showing, if any; `openPage` is independent of it,
because a page opened through the API does not change the selected tab.

### Page data

A page is plain data. Bank Core copies it on every call and keeps no
reference to the caller's tables. It reads fields with `rawget`, so it never runs
the caller's metamethods. A page is checked in full before it replaces anything.

```lua
{
    title = "Cook's Assistant",          -- required, 1–64 characters
    heading = "Ingredients",             -- optional heading above the page
    copies = "all",                      -- "all" (default) or "first"
    items = { 1944, "egg" },             -- either items (config name illustrative)...
    sections = {                         -- ...or 1–32 labelled sections
        { label = "Ingredients", items = { 1944, 1927 } },
    },
}
```

- Each item entry is an object ID (an integer from 0 to 2^31 − 1) or a durable
  config name. Bank Core resolves a config name through `config.Obj[name].id`,
  as its catalog bridge does. An unresolved name refuses the whole call with
  `unknown_item`.
- An object appears once per page, where it was first listed. Later repeats are
  ignored.
- `copies = "all"` shows every bank stack of the object in native bank order.
  `"first"` shows only the first one. Each stack keeps its own identity, so a
  listed object never overwrites another stack's position.
- An object that the bank does not hold is drawn as a ghost placeholder in its
  place. The bank's own zero-quantity placeholders show as placeholders. On an
  empty bank every listed object is a ghost.
- The API has no blanks, custom widgets, callbacks, or native component IDs.

### Tab data

A tab is plain data, read and copied the same way as a page. Bank Core draws
it: a 32-pixel sprite tab in the vertical rail left of the sidebar, and host-drawn
rows in the sidebar content when it is selected. There are no plugin callbacks,
custom widgets, or hit regions in the sidebar or the bank grid.

```lua
{
    label = "Quest Helper",              -- required, 1–64 characters; the title above the rows
    icon = "STAR",                       -- required, a PrettyUI SPRITE_BUTTONS name
    tooltip = "Quest item checklists",   -- optional, defaults to the label
    emptyText = "No quests tracked.",    -- optional, shown when the tab has no rows
    rows = {                             -- optional, 0–64 rows
        { heading = "Quests" },          -- a section heading, alone in its row
        { page = "cooks-assistant",      -- a page this owner has already registered
          label = "Cook's Assistant",    -- optional, defaults to the page title
          detail = "3",                  -- optional, 1–6 characters, right-aligned
          item = 1944 },                 -- optional icon: object ID or config name
    },
}
```

- The icon must name an entry in the running PrettyUI's `Sprites.SPRITE_BUTTONS`
  (for example `STAR`, `PIN`, `SHIELD`). Bank Utilities' own tabs use
  `LIST_LAYOUT`, `ERASER`, and `SEARCH`.
- Register the pages first. A row naming an unregistered page refuses the call with
  `unknown_page`; a page listed twice in one tab is `invalid_tab`.
- A row whose page is later removed is left out of the tab until a page with that
  ID is registered again. Updating a page retitles rows that use its title.
- Pressing a row opens its page through the same arbitration as `OpenPage`. When
  that refuses with `preset_open` or `not_all_items`, the bank shows its usual
  guidance. Pressing the shown page's row again returns the bank to its native view.
- Searching the sidebar filters rows by label; a heading shows only above a match.
- Tags-only actions (New Tag, the layout pencil, sorting, and item drops onto rows)
  are absent on extension tabs. The Import/Share button stays.
- Extension tabs follow the built-in Tags, Cleanup, and Queries tabs, ordered by
  owner ID and then registration order, so load order does not reorder them.
- The rail pages with arrows when tabs outnumber its height, and brings the
  selected tab back into view after any change. The layout editor's sidebar shows
  only Tags.

### Import sources

An import source is listed in the **Source** picker on the Import page of Bank
Utilities' Import/Share window, after the built-in **Share code** source. It is
plain data plus one function. Bank Core copies the data with `rawget`, refuses
a table with a metatable, and checks it in full before anything replaces the last
good copy.

```lua
handle:RegisterImportProvider("gear-guide", {
    label = "Wiki gear guide",           -- required, 1–64 characters, no < or >
    icon = "STAR",                       -- optional PrettyUI SPRITE_BUTTONS name
    input = "text",                      -- "text": a field; "action": a button
    prompt = "Guide address",            -- optional line above the input, defaults to the label
    placeholder = "Paste an address...", -- optional, text sources only
    -- actionLabel = "Choose a preset",  -- optional, action sources only
    -- unavailable = "Open the guide plugin first.", -- optional; listed but not usable
    request = function(request)          -- required
        -- request.input is the field's text (nil for an action source)
        -- Answer once, now or later: request:Resolve(draft) or request:Fail(message)
        -- request:IsCurrent() turns false once the answer is no longer wanted
        return function() end            -- optional: called once if cancelled unanswered
    end,
})
```

- Bank Core calls `request` on a later logic tick, never inside a window event,
  bank page change, render, or lease, and wraps it in `pcall`. A text source is asked
  again after each change of the field. An action source is asked when its button is
  pressed; it may open its own window and answer later. Answering is optional, so a
  link-only source can simply do its own thing. Neither plugin opens URLs or makes
  network requests; a source that fetches does so with whatever its own plugin
  has, which this contract does not establish.
- The request is read-only. It holds no store, window, or object of either plugin.
- `Resolve` and `Fail` return `true` once. Later calls, and calls after the request
  went stale, return `false, "stale_request"`. `Resolve` with a bad draft returns
  `false, "invalid_draft", detail` and the window shows a generic message.
- `Fail(message)` shows the message as one line: markup brackets removed, control
  characters turned to spaces, and at most 120 characters, or a generic message.
  An error raised by `request` shows "<label> stopped with an error."; the detail
  goes only to the debug log.
- A request goes stale when the source or input changes, the window closes, the
  source is updated or removed, its owner is disposed or replaced, or Bank Core
  shuts down. A late answer never changes the window or saves anything.
- When several requests go stale at once (an owner disposed or replaced, or
  shutdown), every one of them is stale and its source already gone before any
  cancel function runs. Cancel functions then run in the order the requests were
  made. A cancel function may call the API: another live owner can register, but a
  dying owner's handle is stale, and during shutdown every registration is refused.
- A selected source that is removed returns the picker to **Share code**. A selected
  text source that is updated is asked again with the field's text. A selected
  action source that is updated returns to empty and waits for the next press; its
  flow is never started on the player's behalf. Registering a source never changes
  the selection. Sources are listed by owner ID, then registration.
- Nothing is saved until the player presses **Import**. Import saves the current
  ready draft once, through the same store method and validation as a pasted share
  code, with the name, sprite, and folder chosen in the window.

A draft is plain data in this schema. It becomes share-code text before the preview,
so it is checked exactly as a pasted code is.

```lua
{
    tags = {                             -- 1–32 tags
        {
            name = "Rotation gear",      -- required tag name, 1–80 characters, no commas or < >
            icon = "iron_bar",           -- optional item: object ID or config name
            folder = "Guides",           -- optional folder name, 1–40 characters
            rows = {                     -- optional arranged rows, in order
                { label = "Weapons" },   -- a page label, 1–60 characters, alone in its table
                { 1944, "egg", false },  -- a row of items; false is a blank slot
            },
            items = { 1927 },            -- optional items after the arranged rows
        },
    },
}
```

- An item is an object ID (an integer from 0 to 2^31 − 1) or a config name of at most
  128 characters without `:`, `<`, `>`, `#`, control characters, or surrounding spaces
  (config names illustrative).
- As in a share code, a config name this client cannot resolve is kept by name and
  shown as a blank until it resolves. The preview counts it as "not recognized".
- An item repeated in one tag takes its next copy (`:2`, `:3`), as a share code does.
- A tag whose name matches an existing tag replaces it when imported, as a share code
  does. Two tags in one draft may not share a name.
- At most 2000 entries in all (rows, labels, slots, and items). Anything else, such
  as a table with a metatable, a gap in a list, an unknown field, or a function, is
  refused.

### Header launchers

A launcher is a sprite button that Bank Core draws in the free part of the bank's
title bar, right of the title and left of the native help and close buttons. It is plain
data plus, for a callback launcher, one function. Bank Core copies the data with
`rawget`, refuses a table with a metatable, and checks it in full before anything replaces
the last good copy. The plugin never chooses coordinates, sizes, or order.

```lua
handle:RegisterLauncher("quest-dialog", {
    label = "Quest Helper",                -- required, 1–64 characters, no < or >
    icon = "STAR",                         -- required PrettyUI SPRITE_BUTTONS name
    tooltip = "Open the quest list",       -- optional, defaults to the label
    -- unavailable = "Load a quest first.", -- optional, 1–120 characters: drawn disabled,
                                           -- the tooltip adds the reason, presses ignored
    activate = function(request)           -- either a callback...
        -- request.launcher is "quest-dialog"; request.IsCurrent() as below
        -- open, focus, or close this plugin's own window here
    end,
    -- page = "overview",                  -- ...or a page this owner registered
})
```

- Give exactly one of `activate` or `page`. A `page` must already be registered by the
  same owner (`unknown_page` otherwise). While that page is removed, its launcher is left
  out of the header; it returns when the page is registered again.
- Availability is static data: `unavailable` is set or cleared with `UpdateLauncher`.
  There is no availability callback, so no plugin code runs while the header is drawn.
- Registering or updating never runs anything. Only a player's press does.
- A press is delivered on a later logic tick, never inside the button event, a bank page
  change, rendering, or a lease, and the call is wrapped in `pcall`. An error goes to the
  debug log; the launcher and every other launcher keep working.
- Updating, removing, hiding, or disposing a launcher, its owner going, and the API
  closing all cancel a waiting press. At delivery Bank Core also checks that the
  player is in game, the bank is open, and the header the press came from is still the
  one shown, so closing, reopening, or rebuilding the header drops it. While a bank page
  change is running, a press waits up to 8 ticks and is then dropped. Two presses of one
  launcher before delivery are one press.
- A page launcher opens its page through the same arbitration as `OpenPage`, and pressing
  it while the page is shown returns the bank to its native view. A refusal shows the
  bank's usual guidance for `preset_open` and `not_all_items`.
- A callback receives a read-only request: `launcher` (the launcher ID) and `IsCurrent()`,
  which stays true until the launcher is updated or removed, its owner goes, the bank
  header closes, or Bank Core stops. It holds no app, layout, store, window, or
  native component, and Bank Core passes no native input components to plugin code.
- The plugin owns the windows it opens and closes them itself, for example in its
  `PluginShutdown` and when its dependency unloads. Bank Core never closes them.
- Placement: 24px buttons at y 8 (the size and row of the sidebar toggle), 4px
  apart, right-aligned 8px left of help, at most 8 buttons including More. They never
  reach the estimated title (below), help, or close. Extra launchers fold into a **More**
  button whose menu lists them below the header. If not even one button fits, the strip
  is not drawn and the debug log says `no_space`. The strip does not depend on whether
  the sidebar is open; it redraws when the sidebar opens or closes, and within 10 ticks of
  any other header change while the bank stays open.
- Order: the player's saved order first, then owner ID, then registration. Right-clicking
  a launcher offers **Move left**, **Move right**, and **Hide**; any launcher's menu, and
  More's, offers **Show** for hidden ones. Bank Core's plugin panel has **Reset header
  launchers**, and so does Bank Utilities' panel while it is attached. These choices
  are saved by Bank Core under its own key, `bankcore:header_launchers:v1`, by
  `ownerID/launcherID`, so they survive reloads and return with a plugin that was
  unloaded. Choices the single-plugin build saved under `bankutils:header_launchers:v1`
  are offered once by Bank Utilities and adopted only into an empty core key (see
  "Saved data" above). Bank Utilities' settings key is unchanged.

**Native component evidence.** `BankWindow` reads the title as the dynamic label
`(311, 14, 14)` inside the border layer, help as static `312`, and close as static `317`.
These come from a logged component dump of interface 517 (RSDevSync network-debugger
log, 2026-09-13 and 2026-09-26): a 714x40 label reading "Bank of Gielinor" at (0,0), and
help at (648,15) and close at (683,15), both 16x16. The equipment preset controls sit in
the right-hand panel below the header (statics 70–86), so they do not share the header.
The label spans the header, so the text's width is estimated at 8px per character (at
least 128px) and treated as centred both in the label's bounds and in the window, in case
the label keeps its old bounds after the sidebar widens the window. Without the label, the
middle 240px of the header stay clear; without help and close, the right 72px stay clear.
None of this is a live measurement.

### Custom sidebar content (deferred)

API v1 has no plugin-drawn sidebar content: a tab is host-drawn rows, and a plugin's
own controls go in its own window opened from a launcher or an action source. The Stage
8 consumer needed nothing more, so custom bounded mounts are deferred (Stage 9) rather
than reserved. If a later consumer needs controls inside the sidebar, they would arrive
as a new handle method, discoverable with `type(handle.<Method>) == "function"`,
after the clipping, z-order, input, resize, unmount, disposal, and unload proof in
the roadmap. The tab data above, its validation, and the existing methods would not
change, so a v1 consumer written today keeps working. No field is reserved for it.

### Limits

| Limit | Value |
| --- | --- |
| Owner and page ID | 1–64 characters, `^[%w][%w_%.%-]*$` |
| Title, heading, section label, owner label | 1–64 characters after trimming |
| Config name | at most 128 characters |
| Owners | 32 |
| Pages per owner | 16 |
| Sections per page | 32 |
| Item entries per page | 512, counting repeats |
| Tab ID | as page IDs |
| Tabs per owner | 4 |
| Extension tabs in all | 16 |
| Rows per tab | 64 |
| Row detail | 1–6 characters after trimming |
| Import sources per owner | 4 |
| Import sources in all | 16 |
| Import source label, prompt, placeholder, action label | 1–64 characters, no `<` or `>` |
| Unavailable and failure message | 1–120 characters |
| Draft tags | 32 |
| Draft entries | 2000 |
| Launcher ID | as page IDs |
| Launchers per owner | 4 |
| Launchers in all | 16 |
| Launcher label and tooltip | 1–64 characters, no `<` or `>` |
| Launcher unavailable message | 1–120 characters, no `<` or `>` |

### Reasons

| Reason | When |
| --- | --- |
| `invalid_owner`, `invalid_label`, `invalid_page_id`, `invalid_page`, `invalid_tab_id`, `invalid_tab` | The input fails validation. The detail says which part failed. |
| `unknown_item` | A config name does not resolve. |
| `duplicate_page`, `duplicate_tab` | `RegisterPage` or `RegisterTab` was called for an existing ID. Use the update call. |
| `too_many_owners`, `too_many_pages`, `too_many_tabs` | A limit was reached. |
| `unknown_page` | The page is not registered for this owner, including a page named by a tab row. |
| `unknown_tab` | The tab is not registered for this owner. |
| `invalid_import_provider_id`, `invalid_import_provider` | An import source ID or description fails validation. The detail says which part failed. |
| `duplicate_import_provider`, `too_many_import_providers` | The source ID exists (use the update call), or a source limit was reached. |
| `unknown_import_provider` | The source is not registered for this owner. |
| `invalid_launcher_id`, `invalid_launcher` | A launcher ID or description fails validation. The detail says which part failed. |
| `duplicate_launcher`, `too_many_launchers` | The launcher ID exists (use the update call), or a launcher limit was reached. |
| `unknown_launcher` | The launcher is not registered for this owner. |
| `stale_request`, `invalid_draft` | Returned by a request's `Resolve` or `Fail`, as above. |
| `stale_handle` | The owner was disposed or replaced, or the API that issued the handle has shut down. |
| `stale_api` | `RegisterExtension` was called on a shut-down API. `GetState` reports the same reason with `running = false`. |
| `not_ready` | The player is not in game. |
| `bank_closed` | The bank window is not open. |
| `building` | The bank is open, but Bank Core has not attached yet, or the bank's item layer is not available. |
| `transition` | A bank page change is already running. |
| `preset_open` | The native preset view is open. |
| `not_all_items` | The native All Items tab is not selected. |
| `rejected`, `failed` | The bank refused the page change, or the change raised an error, which is logged. After `failed` the bank returns to its native view and a retry may succeed. Any rebuild of the shown page that fails, queued or started by the bank itself, including one that finds no item layer, also returns the bank to its native view. |

`OpenPage` checks these conditions in the order listed and refuses the request
without changing the bank. It does not queue the request or show the bank's own
warnings. If the page is already shown, it returns `true` without rebuilding.

### Ownership and lifetime

- Pages are namespaced by owner. Two owners may each have a page called
  `overview`.
- Calling `RegisterExtension` again for a live owner ID disposes the earlier
  owner first: its pages are removed, a shown page is left, and the old handle
  becomes stale. This is how a reloaded consumer replaces its earlier
  registration, even when its `PluginShutdown` did not run.
- Registering or updating never opens a page. Pages may be registered or updated
  while the bank is closed. They persist across bank close and reopen within one
  Bank Core run, and they are not opened again automatically.
- `UpdatePage` on the shown page schedules one rebuild on the next logic tick.
  Several updates in one tick produce one rebuild. Bank Core never runs
  consumer code during selection, rendering, leasing, or recovery.
- Removing or disposing the shown page returns the bank to its native view at
  once. During a page change, this happens on the next tick.
- Registering, updating, or removing a tab never changes the shown page. Tabs
  persist across bank close and reopen. When the selected tab is removed, its
  owner is disposed or replaced, or the API closes, the sidebar returns to its first
  tab, which is Tags while Bank Utilities' features are attached.
  A page that is still registered, such as another owner's, stays shown; the
  owner's own pages leave as above. Switching tabs by hand leaves the shown page,
  as switching between Tags, Cleanup, and Queries always has.
- When Bank Core shuts down or reloads, the API closes before the session stops.
  It leaves any shown extension page, stops its listener, drops every
  registration, and then refuses every call from the old table and handles. A
  reloaded Bank Core publishes a new table. Old handles never touch it.
- Disposing or replacing an owner removes its launchers and drops any press waiting for
  them. When the API closes, launchers close first, so no waiting press runs during
  shutdown. Launchers persist across bank close and reopen within one Bank Core run,
  and reopening never runs one.
- Disposing or replacing an owner removes its import sources. When the API closes,
  every source and outstanding request is dropped before the page API closes.

## Fake-host tests

`tests/page_api_test.lua` drives the public table against the real page modules.
`tests/sidebar_tabs_test.lua` mounts a fake bank window, attaches the real sidebar
through `BankWindow:Apply`, and drives the tab API through the public table: the
expanded geometry, built-in tab content, validation, rows opening pages, overflow
paging, a shorter reopened bank, disposal and replacement fallback, and shutdown.
Its coordinates are what the code asks of stand-in components, not measurements.
`tests/import_providers_test.lua` composes the real Import/Share window, provider
registry, page service, and public table with a stand-in host, and drives two owners'
sources through the window: deferred requests, previews that save nothing, one commit
per Import, stale and repeated answers, failures, malformed drafts, removal,
replacement, disposal, and shutdown.
`tests/header_launchers_test.lua` composes the real session and app with a mounted stand-in bank window
whose header has the title label, help, and close at the logged slots, and drives several
owners' launchers through the public table: placement in the expanded and collapsed
header, sidebar toggles and host resizes while the bank stays open (520, 420, 380, and
340px, down to More alone and then no strip), the title and native-control fallbacks,
zero, two, and sixteen launchers with a More menu whose rows run their callbacks, page
launchers and their preset, All Items, and building refusals, deferred delivery, errors,
reentrant calls, the transition wait, stale updates, removal, hiding, disposal, bank
close and reopen, a rebuilt header, validation, limits, the right-click order and hide
choices with a rejected save and a reset, and shutdown from inside a callback.
`tests/questhelper_consumer_test.lua` is also labelled **FAKE HOST CONTRACT**. It loads the
built Bank Core, Bank Utilities, and both examples, each in its own environment with its own
`require` limited to its built folder and its own module cache, opens the bank through the
core's own inventory event and ready ticks
on the All Items view, and drives every surface through the drawn control: rail tab and
sidebar rows, both header launchers, the example's dialog buttons, and the Import
window's picker, field, action button, and Import button. It covers previews that save
nothing, one save on Import with the draft's folder, a refused Show explained in the
dialog, a disabled launcher, the dialog's choice cancelled by closing either window, an
answer given just before a consumer reload that is never delivered, a reload in a fresh
environment whose old copy is cancelled and cannot take the owner back, producer reload,
unload, and load, a waiting launcher press dropped by the consumer's unload, both load
orders, and the no-shared-`_G` variant. The fixture reads the plugins' private state
to check results; the example never does.
`tests/page_api_plugins_test.lua` is labelled **FAKE HOST CONTRACT**. It loads the built
Bank Core, Bank Utilities, and both examples through `tools/test_support/fake_plugin_host.lua`. Each
plugin gets its own environment, its own `require` limited to its own folder, and its
own `package.loaded`. The test covers both load orders, a producer reload with no
shutdown, re-injection, or notification, a consumer reload, producer unload and load,
the quest example's tab across those reloads, its page and dialog launchers (the dialog is
the example's own PrettyUI window, closed by its own shutdown, and a waiting press is
dropped by the unload),
and a variant in which plugins share no `_G`. In that variant, a consumer recovers
only if the host re-injects the global or notifies it. These tests show only that the
code meets this model. They do not show that the game host behaves this way.
`tests/core_session_test.lua` (Stage 10a, **FAKE HOST**) runs a bank session with no
feature loaded and the `runeql` and `geprices` globals unset: a consumer registers a page,
a tab, a launcher, and an import source; the bank opens through the session's own events
and draws only that tab; the page is built, leased, and left through its row and launcher;
a draft is refused with `unavailable`; and a shutdown and fresh session leave exactly one
owner of each event and of the lease. `tests/feature_attach_test.lua` attaches, detaches,
replaces, and reattaches Bank Utilities' features on an open bank through `Features.Attach`.
`tests/core_boundary_test.lua` walks the require graph from both plugin entries and fails if
the core reaches a feature module or Bank Utilities a session module.
`tests/package_build_test.lua` builds the folders and checks their files against the graph,
their SHA-256 hashes against the sources and between the plugins, the manifests, the
eviction lists, the output-path checks, and that two builds are identical.
`tests/built_packages_test.lua` (Stage 10b, **FAKE HOST CONTRACT**) loads the built Bank
Core, Bank Utilities, and quest example, each with its own environment, module cache, and
`PersistentDB`, and records which plugin holds each `Event` ID. It covers Bank Core alone
with RuneQL and GE prices absent (only the example's tab, its page drawn and leased, its
launcher, drafts refused, the core panel's debug and reset); Bank Utilities' tags, Remove
from through the core's router, cleanup, search, saved queries, and Import across the two
plugins; the launcher choices adopted once into an empty core and never over its own;
unload and reload of each plugin; reattaching through the panel, a host notification, and
both load orders; a replaced Bank Utilities copy when plugins share no `_G`; and one owner,
Bank Core, of every bank, menu, and game-state event throughout.

## Live two-fixture probe (not run)

Build with `lua54 tools/build.lua --examples` and place `dist/bankcore`,
`dist/bankutils`, `dist/questhelperlite`, and `dist/shoppinglist` as sibling plugin
folders on the development plugin path. Add temporary `log` calls in a scratch copy,
not in this repository. Open the bank on All Items, then:

1. Load Bank Core first, then a consumer. Log `type(bankcore)`, whether it
   equals `rawget(_G, "__bankcore_api")`, and whether the consumer's
   `require("lib/core/public_api")` fails. Stop if `require` crosses plugins or
   if the plugins share one `package.loaded`. This contract depends on neither.
2. Reverse the load order. Log whether `PluginOptionalDependencyChanged` fires and
   whether the consumer registers when it does.
3. Run `prl` on Bank Core. Log whether the consumer's `bankcore` global
   changes identity and whether the old handle's `GetState().live` becomes false.
   Then call the consumer's open action and log whether it reconnects through
   `_G.__bankcore_api`.
4. Run `prl` on a consumer. Log whether its `PluginShutdown` ran and whether its
   earlier page was left.
5. Unload Bank Core. Log the consumer's `PluginShutdown` and
   `PluginOptionalDependencyChanged` order, and whether a `Logic` subscription
   runs after `Unsubscribe`.
6. Subscribe two plugins to `Event.Logic` with the same id, and log whether both
   handlers run.
7. With the bank open, call each refusal case (closed bank, numbered tab, preset
   view), then open both examples' `overview` pages. Check that the right items,
   duplicate stacks, and ghosts appear, and that a sidebar tag still works.
8. Sidebar tabs (Stage 6, not run): screenshot the default and a resized bank and
   record the tab rail, tag column, and native content x positions against the
   expected (12,44), (52,44), and (296,44); hover each tab for its tooltip; check
   the sprite names render (`LIST_LAYOUT`, `ERASER`, `SEARCH`, `STAR`, arrows);
   check that the rail tile does not cover the tabs and that the selected frame is
   visible; open the quest tab, press its rows, and repeat with the preset view
   and a numbered tab; `prl` the consumer and Bank Utilities while its tab is
   selected; open the layout editor and check it lines up with the bank and shows
   only the Tags tab.

9. Import sources (Stage 6a, not run): register a text and an action source from a
   scratch consumer. Screenshot the Import page with each selected and check the
   picker, the 30px source icon, the 66px-lower destination rows, and the two-line
   status. Type in the text source and log the tick on which `request` runs. Close the
   window with a request pending and log that the cancel function runs. `prl` the
   consumer and then Bank Utilities with a source selected, and check that the picker
   returns to Share code and a pasted code still imports.

10. Header launchers (Stage 7, not run): with the quest example loaded, screenshot the
   default, expanded, collapsed, and a narrowed bank. Record the title label `(311,14,14)`
   bounds and content, help `312` and close `317` positions, and the strip's x against the
   free area right of the title. Check that the strip never touches the title text, help,
   close, or the toggle, and whether the title label keeps 714px after expansion. Hover
   each launcher for its tooltip; press the page launcher with the preset view and a
   numbered tab; press the dialog launcher and log the tick it runs on; close the bank
   with a press waiting; open More with many launchers; right-click a launcher to move and
   hide it, then `prl` Bank Utilities and check the choice is kept; `prl` the consumer
   with its dialog open and check that its own shutdown closed it; check whether the right-
   click menu appears over plugin-drawn header buttons at all.

11. Full-path consumer (Stage 8, not run): with both examples loaded, repeat steps 8 to
   10 for `questhelper-lite`; track and untrack quests in its dialog and check the tab,
   overview page, and disabled checklist launcher follow; type `cooks-assistant` into
   *Quest by name* and check the preview saves nothing until **Import**; press *Choose in
   Quest Helper*, choose a quest, and check the preview; `prl` the example while it waits
   and log whether the previous run's `PluginShutdown` is visible at the top of
   `main.lua`, whether its dialog closed, and whether the Import page returned to Share
   code.

12. Package split (Stage 10b, not run; the split was built without it under the user's
   no-pause authorization): load the built `bankcore` and `bankutils` folders.
   - Log whether Bank Utilities' `bankcore` global is Bank Core's returned table, whether
     its `Features.Attach` call returns a handle, and whether the bank shows the Tags,
     Cleanup, and quest tabs. This is the cross-plugin function-call check: Bank Core
     calls Bank Utilities' hooks and descriptions, and Bank Utilities calls the handles.
   - Log `PersistentDB:GetStructuredData("bankutils:header_launchers:v1")` from Bank Core
     and `("bankcore:header_launchers:v1")` from Bank Utilities, to learn whether saved data
     is per plugin. Record whether the launcher order from the single-plugin build survived
     the upgrade (it should, through the one-time adoption).
   - Log whether both plugins' `package.loaded["lib/core/config"]` are different tables.
     If they are the same table, the plugins share one module cache and the eviction lists
     must be revisited.
   - Log `type(bankcore)` inside Bank Utilities after `prl` on Bank Core, and whether
     `PluginOptionalDependencyChanged` reaches Bank Utilities for its required dependency.
     Then open Bank Utilities' panel and check that its tabs return.
   - Open each plugin's panel and check that each shows its own controls (whether
     `ContentLayerReady` reaches each plugin with its own panel).
   - Subscribe both plugins to `Event.InventoryUpdated` with one id and log whether both
     run; the built plugins use different ids, so this only decides whether that matters.
   - `prl` Bank Utilities alone and check the core's pages and the quest tab stay; unload
     it and check the bank restores its search controls.

Record the results here before freezing API v1, choosing a hub dependency id, or
building more hosts on this contract. The sidebar, import-source, and header hosts and
the two-plugin split were built on it under the user's no-pause authorization before
this probe ran.
