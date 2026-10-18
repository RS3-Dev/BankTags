# Bank Tags

Bank Tags (`banktags`) is a standalone plugin for tags, folders, saved layouts, select mode, and Import/Share in the bank. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) through Bank Core's public extension API only.

This branch is being adapted in stages; the staged plan is in [docs/STANDALONE_PLAN.md](docs/STANDALONE_PLAN.md).

## Layout

- `plugins/banktags/`: the entry (`main.lua`) and manifest.
- `banktags/`: every runtime module. All require paths start with `banktags/`, so none can collide with Bank Core's modules.
- `tools/`: the build and check tools, and the test harness that loads Bank Core beside Bank Tags.
- `tests/`: the tests; see [tests/README.md](tests/README.md).
- `reference/`: the preserved source from Bank Utilities `beba274`, kept as an archive. Nothing in it is built or loaded. `EXTRACTION_MANIFEST.json` records where each preserved file came from.

## Build and check

```text
lua54 tools/build.lua
lua54 tools/check.lua
```

The build writes only `dist/banktags/`, holding the entry, manifest, and the modules the entry's require graph loads, with the entry's module eviction list generated from that graph. The check builds, runs the tests, and compiles every built file while checking for unexpected globals.
