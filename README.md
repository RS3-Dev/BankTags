# Bank Tags

Preservation snapshot extracted from [Bank Utilities](https://github.com/RS3-Dev/bank-utilities/tree/beba274b57853d444c7017eaa9c813273f222475) at commit `beba274b57853d444c7017eaa9c813273f222475`.

This repository is a starting point for a future separate plugin. **It is not yet installable or independently connected to Bank Utilities Core.** No production entry point or plugin manifest has been invented. Original module paths, function names, storage keys, and source bytes are preserved.

## Contents

- `lib/` and, where needed, `data/`: feature modules and the complete transitive closure of their literal Lua `require` dependencies. Some shared files remain here until a future dependency boundary is implemented.
- `tests/`: existing tests that run independently against these preserved modules.
- `reference/integration/`: unchanged copies of the old mixed application, feature lifecycle, sidebar, menu, settings, and plugin entry code. These preserve behavior that cannot yet be separated without implementation. They are reference material, not a second runnable application.
- `reference/tests/`: original integration tests to port when Core contracts are ready. They still require the original repository's harness and are not included in the standalone checks below.
- `reference/HOST_CONTRACT.md`: the host and API assumptions at the source revision.
- `EXTRACTION_MANIFEST.json`: source commit, original paths, extraction roles, byte lengths, and SHA-256 hashes for every copied file.

## Remaining integration work

- Preserves tags, folders, per-tag layouts, layout editing, sprite selection, and Import/Share.
- The import-provider registry and tag-draft validation are copied here for their intended future Tags ownership; this does not relocate their live owner in Bank Core.
- Tag sidebar and menu modules still contain legacy Cleanup/query branches. They are preserved unchanged, not refactored into a Tags-only runtime.
- Catalog searches in the sprite picker and layout editor still use the external RuneQL API. This snapshot does not implement an optional fallback.
- Keep the legacy bankutils plugin identity and bankutils:tags:* data access until an explicit persistence migration is designed.

No user saves, credentials, game-client files, build output, or external dependency source were copied. The original Bank Utilities source remains intact. Cross-plugin migration, naming, settings registration, and API wiring are future work.

## Checks

The extraction was checked against the committed source bytes and every copied Lua file was syntax-checked with Lua 5.4. These independent source tests were also run:

```text
lua54 tests/tag_store_test.lua
lua54 tests/tag_rules_test.lua
lua54 tests/tag_layouts_test.lua
```

These checks establish source preservation and the listed isolated behaviors; they do not verify a live or standalone plugin. The reference integration tests must be ported before claiming parity with the old integrated feature.
