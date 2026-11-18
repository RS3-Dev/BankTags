# Contributing

Keep Bank Tags small, readable and focused on organizing tagged bank items and
editing their layouts. Shared bank integration belongs in Bank Core.

- Open an issue before adding or changing a public API so we can discuss the need
  and how other plugins would use it.
- Keep pull requests focused. Avoid unrelated rewrites, new dependencies and
  abstractions that make a simple change harder to follow.
- Use clear names and short comments that a new junior developer can follow.
  Explain necessary technical terms in plain language; avoid repeating the code.
- AI assistance is welcome, but you must understand and review everything you
  submit. Do not submit code you cannot explain or maintain.
- Do not use AI to generate your PR body. The PR body must be handwritten.
  Pull requests with AI-generated bodies will be closed.
- Run `lua tests/run.lua` with Lua 5.4 from the repository root. Set `BANKCORE_ROOT`
  to a Bank Core checkout or installation to include its integration test. See
  the [test instructions](README.md#tests) for details.
- Try your changes in RuneScape. For input or layout changes, check bank opening
  and closing, reloads, dragging, scrolling and different interface scales.
- Explain what changed, why, how you checked it and any problems still known.
  Update the docs or examples when their behavior changes.
