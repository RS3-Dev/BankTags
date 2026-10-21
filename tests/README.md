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

Menus load PrettyUI's real `src/minimenu.lua`, read-only, from the checkout `PRETTYUI_ROOT` names, so the folder submenu is placed and checked by PrettyUI's own `MiniMenu.AddSubmenu`, and PrettyUI clears its submenu state on each new menu before the plugins answer, as it does as a dependency. Drawing the submenu and hovering its parent need the client, so a test chooses a child by running PrettyUI's close handler and then the child's action, the order PrettyUI's row click uses; PrettyUI's own `tests/minimenu_test.lua` covers the drawn submenu.

```text
set PRETTYUI_ROOT=C:\path\to\prettyui-checkout
```

The check prints which Bank Core and PrettyUI checkouts and commits the tests loaded. A checkout whose `HOST_CONTRACT.md` lacks the API Bank Tags uses (`PluginDependencyUpdate(event)`, `GetMenuItem`, `SetItemHighlight`, the reported `columns`, a plain, clonable root, `SetSettings`, and `onBankClose(reason)`) is refused with a message rather than tested against, so an older sibling checkout cannot fail or pass the tests for the wrong reason.

The stand-in host is not the game client: these tests show Bank Tags' behavior against Bank Core's public API under that model, not how the live client draws, scrolls, or delivers input.
