# Bank Tags tests

Run every test, the build, and the compile and globals check from the repository root:

```text
lua54 tools/check.lua
```

Tests that load Bank Core read it, unchanged, from the checkout named by `BANKCORE_ROOT`, or from `../bank-utilities` when it is unset. They use Bank Core's own stand-in host (`tools/test_support/fake_bank_host.lua` and `fake_plugin_host.lua` in that checkout) and load Bank Core's `plugins/bankcore/main.lua` with its own module cache, beside the Bank Tags folder the build writes under `dist/test/`. Nothing from Bank Core is copied into Bank Tags or its package.

```text
set BANKCORE_ROOT=C:\path\to\bank-utilities
lua54 tools/check.lua
```

The check prints which Bank Core checkout and commit the tests loaded. A checkout whose `HOST_CONTRACT.md` lacks the API Bank Tags uses (`PluginDependencyUpdate(event)`, `SetItemMenu`, `BeginItemPick`, and the reported `columns`) is refused with a message rather than tested against, so an older sibling checkout cannot fail or pass the tests for the wrong reason.

The stand-in host is not the game client: these tests show Bank Tags' behavior against Bank Core's public API under that model, not how the live client draws, scrolls, or delivers input.
