# Bank Tags

Bank Tags lets you group bank items into named tags and arrange them into your own layouts. An item can belong to more than one tag. Tags are views of your bank: removing an item from a tag does **not** destroy or withdraw the bank item.

## Before you start

Enable **PrettyUI**, **Bank Core**, and **Bank Tags** in the client's plugin manager. **RuneQL** is optional: it lets item and icon searches cover its full catalog. Without it, those searches cover your bank, exact item IDs, and config names.

Open a bank and click **Bank Tags** on the left rail. There is no separate Bank Tags ribbon panel.

## Make your first tag

1. Click **New Tag** at the bottom of the sidebar.
2. Enter a name, choose an icon if you want one, and save.
3. Drag a bank item onto the tag's row to add it.
4. Click the tag to view its items. Click it again to return to the normal bank view.

You can also drop an item onto **New Tag**, then name the new tag. Dragging adds the item to the tag; it does not move the item out of your bank.

Opening an empty tag list offers an eight-step tutorial, starting with **New Tag**. Click the **Help “i” beside Search** to replay it. Its arrows and numbered steps let you go back or skip ahead.

## Add several bank items

Right-click a tag and choose **Select items**. Click bank items to add them to that tag; items already included have a gold outline. Click **Done** in the sidebar to finish.

Select mode needs the bank's **All Items** view. Drops from numbered native bank tabs use the item's first stack when the exact stack cannot be identified.

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

The left grid is **Layout**. The right side contains **Unsorted** items and **Search**. Items in Unsorted still belong to the tag; they simply have no chosen layout position.

- Drag items into Layout to position them. Moving onto another item swaps positions.
- Shift-click Layout items to select a group, then drag a selected item without Shift to move the group. The group keeps its shape. Gold previews fit; red previews are refused.
- **New label** adds a heading. Labels can be renamed, moved, or removed.
- Right-click a Layout item for **Move to Unsorted**, **Edit row**, **Remove from Tag**, and **Cancel**.
- Right-click a blank cell or label for row editing.
- **Edit row** offers row insertion and removal. Removing a populated row asks for confirmation and removes its contents from the tag, not your bank.
- Click **Close** or the title-bar X to leave the editor. Edits save automatically.

### Copy, paste, and undo

Click an item before using a shortcut. Click an empty Layout cell to choose where to paste.

| Action | Shortcut | What it does |
| --- | --- | --- |
| Copy | Ctrl+C | Copies the selected item or group to the editor clipboard |
| Paste | Ctrl+V | Places additional layout copies into empty cells |
| Remove | Delete | Removes the selected single item from the tag |
| Undo | Ctrl+Z | Reverses the last layout edit |
| Redo | Ctrl+Y | Reapplies an undone edit |

Layout copies point to the same bank stack; they do not duplicate real items. Every destination cell must be empty for a paste to succeed. **Cut is not implemented.**

Undo keeps up to 50 steps for the current tag while the editor stays open. Switching tags or closing the editor clears undo and the clipboard. Renaming the tag keeps them. Changes made elsewhere to that tag end its undo history.

Remove and Move to Unsorted require a single selection; Copy supports a group. Shortcuts pause while you type in editor fields or use its dialogs. Click the grid again to resume them.

Arrow-key movement is **off by default**. Enable it in Bank settings → Bank Tags if desired. The arrows also move the game's camera.

## Import and share

Click **Import/Share** at the bottom-left of the sidebar.

- **Share:** select the tag's code field and copy its text.
- **Import:** choose a source, enter the code or source details, review the preview, then confirm the import.

Sharing a tag shares its layout, labels, icon, and folder information, not bank ownership or quantities. Keep a share code for important layouts before making large changes.

## Settings and troubleshooting

Open the sidebar gear and choose **Bank Tags** to change tag icons, new-item placement, arrow-key movement, or debug logging.

- **Nothing appears:** check that Bank Core and PrettyUI are enabled.
- **Cannot open a tag or use select mode:** switch to the native All Items tab and try again.
- **Limited item search:** enable RuneQL for the full catalog.
- **Shortcut does nothing:** close dialogs, click the grid, and release Shift/Alt before using Ctrl.
- **Save error:** read the displayed message. Unreadable saved data is protected from being overwritten; do not delete it without a backup.

A new installation starts empty. Tags from the older integrated Bank Utilities plugin must be transferred with its share codes; they are not imported automatically.

## For reviewers and developers

[Build, saved-data details, architecture, and validation limits](docs/DEVELOPMENT.md) · [API contract](CONTRACT.md) · [code style](STYLE_GUIDE.md).

The current build has automated regression coverage. Live-client checks are still required for the exact release, especially scaling, drag-and-drop, shortcuts, menus, and tutorial placement.
