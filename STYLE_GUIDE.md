# Lua Plugin Style Guide

Favor straightforward Lua that is easy to follow and modify. Code should make the plugin's current state and event flow obvious without adding abstractions, fallbacks, or safety checks that do not solve an observed problem.

## Project structure

- Keep `main.lua` as a small entry point that creates, starts, and stops the plugin
- Give each module one clear job, such as instance detection, encounter state, fungus tracking, timing, or display
- Put related static values and configuration in dedicated data modules
- Keep game logic out of UI modules
- Prefer calling a small module directly over adding another wrapper layer

## Lua style

- Use `local` for modules, constants, helpers, and variables unless the host requires a global
- Use colon syntax for object methods: `plugin:start()`
- Use `not value` for boolean negation and `value ~= nil` when `false` and `nil` have different meanings
- Prefer early returns over deeply nested conditions
- Expand important conditions and function calls across lines when that makes the flow easier to scan
- Use four spaces for indentation and separate logical steps with blank lines
- Use `pcall` only around an external call that is known to fail during normal runtime conditions

## State and event flow

- Represent the plugin flow with explicit states such as `waiting`, `ready`, and `active`
- Check the current host state when the plugin loads before waiting for a future event
- Subscribe to events only while they are relevant
- Keep shared subscriptions active for as long as every feature that uses them may need them
- Start task-specific subscriptions when the task begins and stop them when it ends
- Unsubscribe and reset state when the relevant context ends or the plugin shuts down
- Keep required delays close to the event that needs them and explain the runtime reason

## Defensive checks

- Trust confirmed host state instead of checking the same value at every layer
- Keep checks at real loading boundaries, such as waiting for host state, external data, a UI parent, or a dependency to become available
- Do not add fallback paths for events that are already guaranteed by the plugin lifecycle
- Avoid duplicate state checks and duplicate subscriptions
- Add guards when they prevent a demonstrated crash, invalid subscription, or reload problem

## Naming

- Name things after the concept they represent, such as `session`, `tracker`, `display`, or `settings`
- Use verbs for actions, such as `waitForStart`, `startSession`, `resetState`, or `leaveContext`
- Use `is`, `has`, or `active` for boolean values
- Use uppercase names for file-level constants
- Use one term consistently across the project

## Comments

- Give named functions a short summary directly above their declaration
- Keep function summaries between 3 and 10 words when practical
- Start function summaries with a plain action such as `Find`, `Save`, or `Restore`
- Keep comments short, plain, and non-technical
- Put detailed contracts and historical context in project documentation
- Use inline comments only when an operation order would otherwise be unclear
- Do not restate parameters or individual code lines
- Do not end code comments with a period

```lua
-- Wait for the context to finish loading
self.contextCreatedCallback = function()
    self:startContextCheck()
end
```

## Debugging and logging

- Keep routine production logs out of the plugin
- Put temporary runtime state in the debugger panel instead of scattering log calls through the logic
- Control optional debugging through a single configuration toggle
- Let the panel read plugin state directly instead of duplicating it
- Refresh debug UI at a limited rate rather than every game tick
- Remove temporary counters and fields once they no longer help diagnose active problems

## Preferred lifecycle

1. On load, inspect the current host state
2. If the required context is inactive, subscribe only to the event that can activate it
3. When activation occurs, wait for dependent host data if necessary and confirm the context
4. Subscribe to events needed throughout the active context
5. Start task-specific trackers, timers, and displays when the task begins
6. When the task ends, reset its tools while keeping any context-wide listeners that are still needed
7. When the context ends, remove its subscriptions and return to the waiting state
