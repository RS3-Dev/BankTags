# Native bank tutorial art

Read from the live client with Network Debugger on 2026-10-22. Addresses below identify the observed native components, not components Bank Tags changes. Bank Tags creates its own controls using the same sprite resources.

| Element | Observed component | Sprite resource | Size |
| --- | --- | --- | --- |
| Title info icon | `955:19`, `UITUTORIAL__FLASHY_ICON` | `9966`, `TUTSYS_INFO_ICON` | 26x26 |
| Left navigation graphic | `955:30`, `UITUTORIAL__LEFT_ARROW_GRAPHIC` | `9403`, `RS3_ICON_CALENDAR_NAVIGATION_24PX_0` | 24x24 |
| Right navigation graphic | `955:4`, `UITUTORIAL__RIGHT_ARROW_GRAPHIC` | Same sprite as left | 24x24 |
| Large pointer | `955:22/24/26/28`, `UITUTORIAL__ARROW_*_MOVING` | `21393`, `RS3_INFO_DISPLAY_POINTER` | 41x54 |
| Bank Help button | `517:313`, `BANK__HELP_BUTTON` | `36389`, `RS3_BUTTON_INFO_CHILD_0`; related states `36390-36391` | 19x19 |
| Yellow flashing frame | `1477:845`, `TOPLEVEL_V2__FLASH_YELLOW_1` | `11602-11610`, `AIF_EXAMINE_HIGHLIGHT_1_0` through `_8` | Nine pieces |
| White flashing frame | `1477:846`, `TOPLEVEL_V2__FLASH_WHITE_1` | `11611-11619`, `AIF_EXAMINE_HIGHLIGHT_2_0` through `_8` | Nine pieces |

The active frame sat in `1477:844`, `TOPLEVEL_V2__IF_HIGHLIGHT_1_DISPLAY`, at 33x33 around the 30x30 PIN button. The nine pieces are row-major: top-left, top, top-right, left, middle, right, bottom-left, bottom, bottom-right. Corners are 10x10; middle strips fill the remaining width and height.

The native help box measured 521x144 and its navigation buttons measured 26x26. Bank Tags matches those sizes, the native art, and the small pointer bob. Its pulse timing and pointer placement are implemented by Bank Tags; the native animation script was not inspected. The eight tutorial steps, starting with New Tag, progression rules, and sound remain Bank Tags' own.

The step cue plays once at 25% volume. Its sound instance can expire before the next action; navigation and cleanup clear the retained handle before attempting to stop it, tolerating the client's dead-instance error. Audio setup or playback failures leave the walkthrough usable.

The window, highlight, and arrow share one click-through owner layer. Closing hides that owner immediately; PrettyUI destroys the X-clicked window once its callback returns. Bank close, replay, and reload release the owner even after an interrupted cleanup. Its private `__banktags_tutorial_root` reference lets a new session remove retained tutorial UI if the old controller was lost.

The owner attaches to `TOPLEVEL_V2__BANK_LAYER`, falling back to the game area only if the bank layer is unavailable. Raising a child in the game area cannot put it above the bank's separate render branch. Target and parent positions both use native `xyGlobal` coordinates. The layout editor keeps the guide in front without treating it as a dialog that blocks shortcuts, menus, or item tooltips.
