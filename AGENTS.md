# AGENTS

Repository: proj (Neovim plugin in Lua)

Guidance for coding agents working in this repo.

## Quick facts

- Language: Lua (Neovim plugin)
- Entry module: `lua/proj.lua`
- Type annotations: LuaCATS (`---@class`, `---@param`, `---@return`)
- Dependencies: snacks.nvim (picker, input, win), opencode.nvim

## Build / lint / test

No build system. Tests use plenary.nvim and live under `tests/`:

```sh
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

Manual smoke-test in Neovim with the plugin on `runtimepath`:

- `:ProjectSwitch` -- opens project picker, Enter to switch
- `:ProjectAdd` -- registers current git repo
- `:ProjectList <file>` -- generic list picker (any markdown with `##` headings)
- `:ProjectAddItem <file>` -- generic add item via input prompt
- `:ProjectTodo` / `:ProjectBugs` / `:ProjectTotest` -- shorthand list pickers
- `:ProjectAddTodo` / `:ProjectAddBug` / `:ProjectAddTotest` -- shorthand add
- `:ProjectGlobalTodo` / `:ProjectGlobalBugs` / `:ProjectGlobalTotest` -- cross-project pickers
- `:ProjectGlobalAddTodo` / etc. -- add to any project's list
- `:ProjectGlobalKeymaps` / `:ProjectGlobalRemember` -- global-only lists
- `:ProjectIssues` / `:ProjectIssuesTodo` -- JSON-based issue tracking
- `:ProjectIssuesGlobal` / `:ProjectIssuesTodoGlobal` -- cross-project issues
- `:ProjectGitStatus` / `:ProjectGitDiff` / `:ProjectGitHistory` -- git operations
- `:ProjectGitCommit` / `:ProjectGitStash` / `:ProjectGitBranch` -- more git ops
- `:ProjectOpenCode` -- toggle opencode terminal for current project
- `:ProjectHelp` -- open plugin help in equal vertical split
- `:ProjectPreviewLists` -- toggle floating preview of all project lists

## Plugin structure

```
plugin/proj.lua      Auto-sourced entrypoint; calls setup({}) if not yet loaded
lua/
    proj.lua         setup(opts), commands, keymaps, tab <-> project mapping
lua/proj/
    project.lua      ProjectList class + persistent registry (json read/parse/write)
    config.lua       Config defaults/resolution used by setup(opts)
    session.lua      Per-project + global session save/restore
    lists.lua        Parse/pick/add markdown lists; cross-project aggregation
    issues.lua       JSON-based issue tracking (.issues/{bugs,todos}.json)
    opencode.lua     Opencode terminal toggling per-project
    utils.lua        Shared IO/json/notify helpers for proj modules
tests/
    project_spec.lua
    lists_spec.lua
```

Most modules are leaves; `proj.utils` is a shared helper required by other modules. `proj.lua` requires all runtime modules.
`plugin/proj.lua` requires only `proj` (the entry module).

## Fluxtags

Decorative navigation markers placed near the top of each file.
Use `<C-]>` on a `|||ref|||` to jump to the corresponding `@@@mark`.
Not a dependency -- just bookmarks for cross-module navigation.

```lua
-- @@@proj.session
-- ###nvim-plugin
```

When adding a new module, place a `@@@proj.<name>` mark after requires
and add a `|||proj.<name>|||` ref in `proj.lua`.

## Style source of truth

All style, formatting, naming, and code-architecture rules are defined in:

- `STYLE_GUIDELINES.md`

Do not duplicate style rules in this file.

## Key design rules

- One project per tab. `proj.lua` maintains a `tabpage -> Project` map.
- Sessions stored under `vim.fn.stdpath("data") .. "/proj_sessions/"`.
- Global session: `_global.vim`; per-project: `<sanitized_name>.vim`.
- Registry file: `vim.fn.stdpath("data") .. "/proj_registry.json"`.
- List files (any `.md` with `##` headings) live in the project root.
- Opencode: `require("opencode").toggle()` scoped by tab CWD.
- No session for a project -> `vim.cmd.edit(root)` (opens in user's explorer).

## Adding new features

1. New file under `lua/proj/`. Add `@@@proj.<name>` + `###nvim-plugin` marks.
2. Add `|||proj.<name>|||` ref in `proj.lua`.
3. Wire commands / keymaps in `proj.lua`.
4. Update module structure in this file.

## Agent behavior

- Only edit files under `plugin/`, `lua/proj/`, `tests/`, `AGENTS.md`, `README.md`, `TODO.md`, `TOTEST.md`.
- Preserve fluxtag marks when editing; add new ones as needed.
- Keep changes minimal.
- Do not add dependencies beyond snacks.nvim and opencode.nvim.
- When unsure, check snacks.nvim source at `~/.local/share/nvim/lazy/snacks.nvim/`.
