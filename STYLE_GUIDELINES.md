# fluxtags.nvim Style Guidelines

This file is the single source of style, formatting, naming, and architectural coding rules for this repository.

## Scope and Evidence

These rules are intentionally aligned to observed `snacks.nvim` conventions and adapted for this plugin:

- Formatting/tooling evidence: `.editorconfig`, `stylua.toml`, `selene.toml` in `snacks.nvim`
- Core module evidence: `lua/snacks/init.lua`, `lua/snacks/util/init.lua`, `lua/snacks/git.lua`
- Complex subsystem evidence: `lua/snacks/picker/core/picker.lua`, `lua/snacks/picker/source/lsp/config.lua`
- Test/tooling evidence: `tests/config_spec.lua`, `tests/minit.lua`, `scripts/test`

Repository-specific operational behavior remains documented in `AGENTS.md`; this file only defines style and code-convention rules.

## Formatting

- Use spaces, never tabs.
- Use 2-space indentation in new/edited code.
- Keep lines at or below 120 columns where practical.
- End every file with a trailing newline.
- Keep table literals and argument tables compact when readability allows.
- Avoid introducing new formatter/linter conventions unless adopted repo-wide.

## Naming and Module Structure

- Use `snake_case` for local variables, functions, and file names.
- Keep module shape as:
  - `local M = {}`
  - function definitions on `M`
  - `return M` at file end
- Keep private helpers as file-local `local` functions/values.
- Use `SCREAMING_SNAKE_CASE` only for true constants.
- For internal/private fields, a leading underscore is allowed when it clarifies lifecycle/internal ownership.

## LuaLS and Types

- Annotate public API and non-trivial structures with LuaLS `---@` blocks.
- Prefer concise, accurate annotations over broad or speculative typing.
- Keep type annotations aligned with runtime behavior; update both together.
- Preserve existing per-file annotation style when touching older files.

## Architectural Conventions

- Keep entrypoints thin and delegate behavior to domain modules.
- Keep modules focused on one concern (config, command registration, parsing, persistence, rendering, etc.).
- Prefer explicit module boundaries and local `require` usage over hidden/global coupling.
- Use lazy-loading patterns only when they reduce startup overhead or avoid optional dependency cost.
- Keep shared state on module tables and buffer-scoped state in buffer-local storage.

## Error Handling and Validation

- Validate inputs early and return early on invalid state.
- Use `pcall()` for Neovim/runtime calls that may fail due to environment or optional integration.
- Use `vim.notify()` for user-facing errors/status with clear, actionable messages.

## Performance and Data Flow

- Favor `vim.api` / `vim.fn` primitives over heavy abstractions.
- Minimize repeated IO; cache file-derived data when repeatedly queried.
- Prefer batched line reads (`nvim_buf_get_lines`) over many single-line calls.
- Keep loops and parsing logic straightforward; optimize only known hot paths.

## Comments and Documentation

- Keep code self-documenting where possible.
- Add short comments only when intent is non-obvious.
- Avoid noisy comments that restate literal code behavior.

## Tests and Tooling Style

- Keep tests behavior-focused and table-driven where practical.
- Prefer small fixtures and direct assertions over deep test abstractions.
- Keep helper scripts simple wrappers around explicit commands.

## Prescriptive Rules for New Changes

- Follow this file for style choices instead of ad-hoc per-file variation.
- When existing local style conflicts with this file, prefer this file for newly edited code and keep refactors scoped.
- Do not duplicate style rules in `AGENTS.md`; update this file instead.
