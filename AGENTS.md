# AGENTS.md — WezTerm Config

## Overview
WezTerm terminal emulator configuration. Lua (LuaJIT target). Modular config builder pattern.

## Entrypoint
`wezterm.lua` — loaded by WezTerm on startup. Assembles config by chaining `Config:init():append(module)` calls.

## Architecture
- `config/init.lua` — Config builder class. `:append(t)` merges key/value pairs, warns on duplicates via `wezterm.log_warn`. Returns `self` for chaining.
- `config/*.lua` — each returns a table of WezTerm config options. Order appended in `wezterm.lua` determines precedence (first write wins — duplicates logged but silently dropped).
- `utils/` — pure utility modules, no WezTerm side effects.
- `events/` — WezTerm event handlers (format-tab-title, update-right-status, gui-startup, etc.). Each exposes a `setup(opts?)` function called from `wezterm.lua`.
- `colors/custom.lua` — catppuccin mocha variant.
- `backdrops/` — background image files.

## Developer Commands

```sh
# Format check (config/init.lua is excluded from formatting)
stylua -g '!/config/init.lua' --check wezterm.lua colors/ config/ events/ utils/

# Format apply
stylua -g '!/config/init.lua' wezterm.lua colors/ config/ events/ utils/

# Lint
luacheck wezterm.lua colors/* config/* events/* utils/*
```

## Formatting Rules (stylua.toml)
- **3-space indents** (not 2 — unusual for Lua)
- Single quotes preferred, call parentheses always
- 100 char column width
- LuaJIT syntax, Unix line endings

## Critical Gotchas

- **`set_images_dir` must be called before `set_images()`** in `wezterm.lua`. `set_images()` calls `wezterm.glob()` which only works during initial config load (spawns a child process; fails in event callbacks).
- **`wezterm.glob()` coroutine restriction**: This function can only run during the synchronous config load in `wezterm.lua`. Do not call it inside event handlers.
- **`config/init.lua` is excluded from stylua formatting** (`!/config/init.lua`). Its `goto`/label syntax for `continue` emulation should be preserved.
- **`utils/backdrops.lua` ignores luacheck rule 212** (unused argument `self` — it's a method convention).
- **All default key bindings are disabled** (`disable_default_key_bindings = true`).
- **SUPER key mapping is platform-dependent**: Alt on Windows/Linux, Super on macOS. See `config/bindings.lua:8-13`.
- **`#` at start of multi-line list tables** triggers a stylua decision: the `keys` and `key_tables` tables use `-- stylua: ignore` comments to preserve manual formatting.
- **`math.randomseed` is seeded at module load in `utils/backdrops.lua`** (lines 7-10). This has global effect — no other module should re-seed it.

## Event Module Pattern
Events follow a consistent pattern:
1. Validate options with `OptsValidator` (see `utils/opts-validator.lua`)
2. Expose `M.setup(opts?)` that calls `wezterm.on(...)`
3. Called from `wezterm.lua` before `return Config:init():append(...)`

## Style Conventions
- Method-style (`:`) for OOP (Config, GpuAdapters, BackDrops, Cells, OptsValidator, Tab)
- Module-style (`.`) for pure utility tables (str, math, platform)
- `---@type` / `---@class` lua-language-server annotations used throughout
- `-- stylua: ignore` and `-- luacheck: ignore` used sparingly for specific blocks
