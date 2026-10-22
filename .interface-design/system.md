# Bank Tags interface

Match RuneScape's bank: native framed windows, subdued brown surfaces, gold highlights, and Museo Sans 11pt body text. Reuse PrettyUI and the existing BankControls buttons.

Folder headers use warm gray `#3B352D`, above the alternating tag-row fills. Icons use the same item sprites for tags and folders.

Tutorials use a separate 521x144 bank-style help window, a black framed explanation area, numbered steps, and native sprite arrows. The title info icon is 9966 at 26x26, navigation arrows use 9403 at 24x24 (mirror the left arrow), and the pointer is 21393 at 41x54. Build the flashing target from the yellow 11602-11610 and white 11611-11619 nine-piece frames, with 10px corners and opposing alpha pulses. The sidebar Help button uses the 19x19 sprites 36389-36391. Recreate these in plugin-owned layers; never borrow or change live native tutorial components. Highlight layers never take input. Prefer free space above or below the bank for the help window; clamp it to the viewport when space is limited.

Follow native component coordinates, including scrolling, rather than converting mouse pixels. Resolve targets again after UI rebuilds. Play one quiet, short cue when the displayed step changes. Tutorials observe successful actions and never manufacture tags or move items for the player. Numbered navigation must allow revisiting without immediate automatic progression.
