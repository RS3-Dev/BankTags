# Bank Tags

Bank Tags lets you group bank items into named tags and arrange them into your own layouts. An item can belong to more than one tag. Tags are views of your bank: removing an item from a tag does **not** destroy or withdraw the bank item.

## Before you start

Enable **PrettyUI**, **Bank Core 1.1.0 or later**, **RuneQL**, and **Bank Tags** in the client's plugin manager. All three libraries are required. RuneQL lets item and icon searches cover its full catalog.

Bank Core remains a required dependency. A background check recovers missing or stale registrations after Core loads or reloads without replacing a working connection or relying on optional-dependency notifications.

Open a bank and click **Bank Tags** on the left rail. There is no separate Bank Tags ribbon panel.

## Make your first tag

1. Click **New Tag** at the bottom of the sidebar.
2. Enter a name, choose an icon if you want one, and save.
3. Right-click the tag, choose **Select items**, and click a bank item to add it. Adding an item does not move it out of your bank.
4. Click the tag to view its items. Click it again to return to the normal bank view.

Opening an empty tag list offers an eight-step tutorial, starting with **New Tag**. Click the **Help “i” beside Search** to replay it. Its arrows and numbered steps let you go back or skip ahead.

## Add several bank items

Right-click a tag and choose **Select items**. Click bank items to add them to that tag. Click **Done** in the sidebar to finish. Select mode works in any bank tab.

Items already in the tag have a gold outline during select mode. Adding another copy outlines its next available stack, with stocked stacks before placeholders. Leaving select mode restores the items' normal appearance.

You can also drag a bank item onto a tag's row in the sidebar to add it to that tag.

A tag lists items, not particular stacks. Clicking an item already in the tag adds another layout slot. Items that stack in the bank show the same stack in every slot. Other repeated items use their next available stack, with stocked stacks before placeholders; extra slots show an empty item picture.

To remove an item, view the tag, right-click the item, and choose **Remove from**.

## Rename, group, and reorder tags

- **Rename:** right-click a tag to change its name or icon.
- **Folders:** right-click a tag and use **Add to folder** or **Move to folder**. Create a new folder there if needed.
- **Folder icons:** right-click the folder and choose **Rename folder**.
- **Expand or collapse:** click a folder's row.
- **Reorder:** drag a tag or folder row and release it where the gold line shows. A folder moves with all its tags, even while collapsed. A tag inside a folder moves only among that folder's tags; right-click it and use **Move to folder** or **Remove from folder** to change folders. Clear the search first: rows don't move while a search filters the list.
- **Cancel a drag:** drop the row back where it started, or move the pointer out of the list.
- **Remove:** removing a tag deletes the tag and its saved layout, not the bank items. Removing it from a folder keeps the tag.

## Arrange a tag's layout

Right-click the tag and choose **Edit**, or use the sidebar's Edit button while that tag is open.

The editor follows the bank from left to right: **Unsorted → Layout → Search**. Both side panes use matching search fields and borders. Unsorted displays a grid inside its border; Search displays named result rows. Native bank tabs above Layout show each tag's item icon, or its first letter; hover for the full name. Tabs follow the sidebar's tag order, including folder members. Left/right arrows appear on overflow; arrows and the wheel scroll through tabs without changing the selected page.

Search stays open on the right. Drag a named result into the central Layout, which keeps the bank's item spacing and column count. Item tooltips are centered beneath the hovered item, moving above it when there is no room below. Unsorted stays open on the left; search its grid by item name to find items already in the tag that have no chosen layout position. Filtering does not remove, reorder, or add items. Drag an item into Layout, or right-click it for Move to Layout and Remove from Tag. Each area scrolls independently. Editing actions and persistent status feedback sit in the footer, with Close at the right.

- Drag items into Layout to position them. Moving onto another item swaps positions.
- Shift-click Layout items to select a group, then drag a selected item without Shift to move the group. The group keeps its shape. Gold previews fit; red previews are refused.
- Hold Shift and drag from empty Layout space to draw a selection box and add the enclosed items to your selection. Keep Shift held until you release the mouse. The pane scrolls near its top and bottom edges; the wheel also works. Release Shift early or press Escape to cancel the box and restore your previous selection. Labels are skipped.
- **New label** asks for a heading's text and adds it above the selected item or the cell chosen for pasting, or after the layout. To add one at any row, right-click the row and use **Edit row**, then **Add label above** or **Add label below**. Drag a label to move it; drop it back on its own row to rename or remove it.
- Right-click a Layout item for **Move to Unsorted**, **Edit row**, **Remove from Tag**, and **Cancel**.
- Right-click an Unsorted item for **Move to Layout** or **Remove from Tag**. Move to Layout fills the first open cell, skipping labels and reserved slots, or adds a row if needed.
- Click **Add row** in the footer to append an empty row. Right-click a blank cell or label for row editing. The grid shows only saved layout rows, including empty rows you added. On an empty layout, you can also right-click its background and choose **Add row** to start.
- **Edit row** offers row insertion, label insertion, and row removal. **Add row below** on the last row extends the layout. Empty rows stay saved until you remove them. Removing a populated row asks for confirmation and removes its contents from the tag, not your bank.
- Click **Close** or the title-bar X to leave the editor. Edits save automatically.

### Copy, paste, and undo

Click an item before using a shortcut. Click an empty layout cell to choose where to paste. Clicking or typing in item search, or choosing a tag tab, gives the keyboard away from the grid until you click a grid again, so typing never edits the layout.

| Action | Shortcut | What it does |
| --- | --- | --- |
| Copy | Ctrl+C | Copies the selected item or group to the editor clipboard |
| Paste | Ctrl+V | Adds the copied items again into empty cells |
| Remove | Delete | Removes the selected single item from the tag |
| Undo | Ctrl+Z | Reverses the last layout edit |
| Redo | Ctrl+Y | Reapplies an undone edit |

Pasting adds layout slots for the same items; it does not duplicate real items. Stackable items share their bank stack across slots, while other items use successive stacks. Every destination cell must be empty for a paste to succeed. **Cut is not implemented.**

Undo keeps up to 50 steps for the current tag while the editor stays open. Switching tags or closing the editor clears undo and the clipboard. Renaming the tag keeps them. Changes made elsewhere to that tag end its undo history.

Remove (Delete), Copy, and Move to Unsorted support a group. Removing a group or moving it to Unsorted is one undo step. Right-clicking a selected item and choosing Move to Unsorted moves the whole selection; an unselected item moves on its own. Shortcuts pause while you type in editor fields or use its dialogs. Click the grid again to resume them.

Arrow-key movement is **off by default**. Enable it through the Bank Tags settings cog in **Plugin Hub → Manage** if desired. The arrows also move the game's camera.

## Import and share

Click **Import/Share** at the bottom-left of the sidebar.

- **Share:** select the tag's code field and copy its text.
- **Import:** paste a share code or full backup, review the preview, then confirm the import. For a single tag, you can change its name, icon, and folder before importing.

Sharing a tag shares its layout, labels, icon, and folder information, not bank ownership or quantities. Keep a share code for important layouts before making large changes.

## Settings and troubleshooting

Open **Plugin Hub → Manage → Bank Tags → settings cog** to change tag icons, new-item placement, arrow-key movement, or debug logging.

- **Nothing appears:** check that Bank Core and PrettyUI are enabled.
- **Cannot open a tag:** the error appears at the top center of the bank, over its title. Close the preset selector, clear native bank search and filters, switch to All Items, and try again. These controls also close a shown tag; clearing them lets you select it again. A tag with more than 10,000 rows, labels, and items cannot be shown; remove some in the layout editor.
- **Limited item search:** enable RuneQL for the full catalog.
- **Shortcut does nothing:** close dialogs, click the grid, and release Shift/Alt before using Ctrl.
- **Save error:** read the displayed message. Unreadable saved data is protected from being overwritten; do not delete it without a backup.

Names, folder names, labels, and imported share data are plain text. Bank Tags uses
Bank Core's `SanitizeString` when available, with a local fallback, to remove markup
tags before saving or displaying text. Existing saved data is cleaned as it loads;
you do not need to delete PluginData.db.

A new installation starts empty. Share codes and saved tags from earlier versions, including the older integrated Bank Utilities plugin, are not read.

## Manual installation

This repository contains the Bank Tags 1.0.3 runtime. Copy `main.lua`, `plugin.json`, and `resources/` into a `banktags` folder in your client's development plugins directory, or extract the release ZIP's contents into that folder. The ZIP opens directly to `main.lua`, `plugin.json`, and `resources/`. Enable PrettyUI, Bank Core, RuneQL, and Bank Tags in the plugin manager.

Older local builds used the manifest name `banktags`. The required listing name,
`Bank Tags`, uses a different client database namespace even though the save keys
and tag format are unchanged. Export tags from the old build before switching,
then import them in the new build. This release does not automatically migrate
the old namespace. Do not delete PluginData.db; it also stores other plugins' data.

## Tests

Run the suite from the repository root with Lua 5.4:

```sh
lua tests/run.lua
```

The tests use native UI stubs and fresh globals and module caches for each case.
They run outside the game client and require no Python packages or test framework.
Failures print a traceback and return a nonzero exit code.

To also test sanitization against a Bank Core checkout or installation, set
`BANKCORE_ROOT` to its root directory before running the suite. Without it, that
integration test is reported as skipped. A configured path must contain
`lib/core/public_api.lua`; an invalid path fails the test.
