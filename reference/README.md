# Reference archive

Preserved source from Bank Utilities `beba274b57853d444c7017eaa9c813273f222475`, kept for history and comparison. Nothing here is built, loaded, or tested; the build refuses to ship it.

- `integration/`: the old integrated app, feature glue, sidebar, menus, settings, and plugin entry.
- `preserved/lib/`: preserved modules the standalone plugin no longer loads, such as native bank component access, menu reordering, and the old sidebar frame and tab rail.
- `tests/`: the old integration tests. `import_providers_test.lua` was ported to `tests/`; the others describe the old integrated sidebar and Core bridge.
- `HOST_CONTRACT.md`: the host and API assumptions at the source revision, superseded by Bank Core's `HOST_CONTRACT.md` and this repository's `CONTRACT.md`.

`EXTRACTION_MANIFEST.json` at the repository root records each preserved file's original path and hash. Files that became runtime modules moved to `banktags/` and were adapted there; their history is in git.
