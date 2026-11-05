# Bank Tags interface

Match RuneScape's bank: native framed windows, subdued brown surfaces, gold highlights, and Museo Sans 11pt body text. Reuse PrettyUI and the existing BankControls buttons.

Editor concepts must stay within the native RuneScape / PrettyUI component vocabulary. Keep 40px cells on a 44px pitch and 36×32 item sprites; improve hierarchy through contrast and grouping. Use the existing window, filled tabs, BUTTON_PANEL controls, bank headings, and square gold selection outlines. Browser mockups approximate the native font and controls and need a client rendering check.

Editor item sprites use native `outlineWidth = 1` for the bank's black edge, including grid items, search results, tag icons, and drag previews. Preserve their existing quantity and placeholder opacity settings.

Section labels reserve 31px (Core's 28px heading plus 3px headspace), rather than an item row's 44px. Compact every following row accordingly. Rendering, selection marks, hover names, hit testing, and drag previews must use the same label-aware row geometry; saved cell indices remain logical grid indices.

The editor reuses the bank footprint as Unsorted → Layout → Search. Unsorted uses a compact 252px tray for five item columns, their spacing, padding, and scrollbar. Keep Layout at its established width, shift it left with the tray, and give the remaining width to Search. Draw only occupied Unsorted rows, including the final partial row; empty Unsorted draws no cells. Center its grid in the usable viewport, accounting for the scrollbar when visible. Use the same horizontal offset for sprites, outlines, hit testing, and hover names. The center retains its native item grid and grows with wider banks. Right-hand Search retains its padded field and inset results frame. Both sources stay visible and scroll independently.

Use native BANK_TABS_HORIZONTAL backgrounds above Layout: 48×38 tabs on a 50px pitch, with 22px item icons or a UTF-8 initial. Show full tag names in overlay tooltips. Place this strip directly on the default window background; no panel tile, solid header fill, or enclosing gold frame behind it. The item area below retains its own frame. Preserve tag order including folder members. Overflow reserves both left/right arrows. Selecting a tab keeps it visible; wheel/arrows scroll without changing pages.

Future category filtering should use RuneQL metadata beside item-name search, independent of tabs and folders.

Folder headers use warm gray `#3B352D`, above the alternating tag-row fills. Icons use the same item sprites for tags and folders.

The editor's Search column uses Core's tiled sidebar sprite 8082 across its full height, without a solid body fill. Search labels show hover names only when the native font measures wider than their label; readable names need no tooltip. Grid items still show their names on hover.

Copy and the footer divider begin under the left Unsorted column. Search shares SidebarRows' 8px inset, 26px field, 8px gap before framed results, and 8px bottom inset. Omit the Search heading and idle instructions; top-align no-results and error messages inside the frame. The Unsorted header uses Museo Sans 15pt in a 20px row, 4px above its content divider.

Tutorials use a separate 521x144 bank-style help window, a black framed explanation area, numbered steps, and native sprite arrows. The title info icon is 9966 at 26x26, navigation arrows use 9403 at 24x24 (mirror the left arrow), and the pointer is 21393 at 41x54. Build the flashing target from the yellow 11602-11610 and white 11611-11619 nine-piece frames, with 10px corners and opposing alpha pulses. The sidebar Help button uses the 19x19 sprites 36389-36391. Recreate these in plugin-owned layers; never borrow or change live native tutorial components. Highlight layers never take input. Prefer free space above or below the bank for the help window; clamp it to the viewport when space is limited.

Follow native component coordinates, including scrolling, rather than converting mouse pixels. Resolve targets again after UI rebuilds. Play one quiet, short cue when the displayed step changes. Tutorials observe successful actions and never manufacture tags or move items for the player. Numbered navigation must allow revisiting without immediate automatic progression.
