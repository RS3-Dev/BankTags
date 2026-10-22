# Bank Tags interface

Match RuneScape's bank: native framed windows, subdued brown surfaces, gold highlights, and Museo Sans 11pt body text. Reuse PrettyUI and the existing BankControls buttons.

Folder headers use warm gray `#3B352D`, above the alternating tag-row fills. Icons use the same item sprites for tags and folders.

Tutorials use a separate bank-style help window, numbered steps and back/next arrows. Highlight the current live control with a slowly pulsing gold border and a large gold arrow. Highlight layers never take input. Prefer free space above or below the bank for the help window; clamp it to the viewport when space is limited.

Follow native component coordinates, including scrolling, rather than converting mouse pixels. Resolve targets again after UI rebuilds. Play one quiet, short cue when the displayed step changes. Tutorials observe successful actions and never manufacture tags or move items for the player. Numbered navigation must allow revisiting without immediate automatic progression.
