# Drag sidebar rows to reorder

## Starting point

Bank Tags commit `9295041`: eight-step tutorial, current sidebar buttons, folder icons, narrow refreshes, and the hover/DPI fixes. Snapshot: `snapshot/before-tag-row-drag-20261022`. A verified Git bundle is kept in the sibling `bank-tags-snapshots` directory.

The goal is to replace the Sort footer button and per-row up/down arrows with direct dragging of the named tag and folder rows. This does not change the editor's icon rail, native bank tabs, or Core's plugin rail.

## Interaction rules

- A normal click still selects a tag or expands/collapses a folder.
- A press followed by a deliberate movement threshold starts reordering. Do not navigate, collapse, or save merely on press. A completed drag must not trigger the normal click as well.
- Show a click-through row ghost and an insertion line. Commit once on a valid release; never save intermediate hover positions.
- Tags outside folders reorder among top-level tags and folders. A folder moves as one block with its members, including when collapsed.
- Tags inside a folder reorder only within that folder in this first version. Folder membership changes keep using the existing menu. No nesting or implicit membership change.
- Reordering is disabled while a text search filters the list. Normal selection and bank-item drops still work in filtered results. Explain the restriction in the player guide or an appropriate tooltip.
- Preserve selection, expanded/collapsed state, icons, scroll position, and every item's layout. Reordering changes only sidebar order.
- Dropping outside the list, on an incompatible target, or back at the original position cancels without a write. Failed saves retain the original order and show a useful message.

## Coordinates and input

Reuse the existing component hover state and `Geometry.trackPointer` calibration that handle Windows DPI and RuneScape interface scale. Do not trust native drag start/stop screen positions or assume 1080p/100% scaling.

Determine the destination row from native hover where the host permits it. Use native component-local coordinates or the already calibrated geometry only to resolve a row's upper/lower insertion edge. If capture prevents target hover events, inspect the actual local client API and existing working gestures before choosing a minimal fallback. Do not add a full-screen hit layer that blocks bank-item drops, menus, or target hover.

PrettyUI's List currently selects on ONCLICK. Resolve that conflict explicitly: there must be one clear click/gesture owner rather than two competing handlers. Preserve wheel scrolling during a gesture; support edge scrolling if it can be added with the existing list scroll API and a small, scoped listener.

Native bank-item dragging onto a tag is a different action. It must continue tagging the correct stack exactly once, and must never start row reordering. Right-click must open the current menu without moving or selecting the row. Keep the existing menu freshness/once-only checks effective after a drag.

## Store and layout

`TagStoreFolders:TagTree`, `treeTagOrder`, `MoveSidebarEntry`, and `SaveTagOrder` already describe the ordering model. Add a direct source/target insertion operation if needed; do not repeatedly call the adjacent-move method and save each hop. Resolve stable row IDs against the current tree, validate sibling membership, then save once. Stale gestures after changes must cancel.

Remove Sort state, buttons, arrow decorations, and dead helpers that have no callers. The footer becomes Import/Share followed by a wider New Tag and optional Edit at the far right. Help stays beside Search. Keep changes inside Bank Tags; do not fork or edit PrettyUI or Core.

## Cleanup

Cancel and remove the ghost, insertion line, and any polling on refresh/rebuild, filtering, resize, dependency loss, bank close, reload, or destruction. Do not allow a gesture to outlive its rows. Avoid swallowing a real persistence failure or adding defensive checks for values guaranteed by the new gesture constructor.

## Verification

Test store moves up/down, before/after, folder blocks, member ordering, invalid cross-folder targets, no-ops, stale IDs, save failure, and one write per successful drop. Check persistence after reload/export without changing folder or tag data.

Test normal click vs drag, threshold behavior, cancel outside, insertion feedback, scrolling, filtered lists, collapsed folders, right-click freshness, close mid-drag, and native bank-item drops. Include simulated 125% Windows scaling with correct component hover and misleading raw drag coordinates, plus independent game interface scaling.

Update the existing sidebar geometry assertions, sorting tests, player guide, and affected tutorial tests. Run the full Bank Tags check with the current Core and PrettyUI references, stage new tests before discovery, and build fresh output. Report which input behaviors remain unverified in the real client.

Keep the implementation lean and commented around gesture ownership, coordinate handling, and persistence. No framework or generic drag engine is needed. Return a clean local commit and build path for parent review; do not push, merge, or install.
