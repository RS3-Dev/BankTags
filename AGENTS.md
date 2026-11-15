# Local plugin sync

When syncing Bank Tags to `C:\Users\thejo\Documents\RSDevSync\plugins\banktags`,
set the installed `plugin.json` required dependencies to `"bankcore": "bankcore"`
and `"runeql": "runeql"` so the client uses the local development plugins.
Keep PrettyUI's numeric dependency ID. Apply these overrides after copying the
runtime, and verify the installed manifest. This local sync policy does not change
the repository or release manifest's dependency IDs.

The manifest display name is `Bank Tags`, matching mod.io exactly. The local
installation folder remains `banktags`; do not use the folder name as the manifest
display name. Release ZIPs must have `main.lua` and `plugin.json` at their root.
