# AGENTS

Repository: proj (Neovim plugin in Lua)

Guidance for coding agents working in this repo.

## Quick facts

- Language: Lua (Neovim plugin)
- Entry module: `lua/proj/init.lua`
- Style: follows snacks.nvim conventions with 4-space indent
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
lua/proj/
    init.lua         setup(opts), commands, keymaps, tab <-> project mapping
    project.lua      Project class, persistent registry (read/write/add/remove)
    session.lua      Per-project + global session save/restore
    lists.lua        Parse/pick/add markdown lists; cross-project aggregation
    git.lua          Thin git wrappers (status, diff, history, commit, stash, branch)
    issues.lua       JSON-based issue tracking (.issues/{bugs,todos}.json)
    opencode.lua     Opencode terminal toggling per-project
tests/
    project_spec.lua
    lists_spec.lua
```

All modules are leaves (no internal requires). `init.lua` requires all.
`plugin/proj.lua` requires only `proj` (the init module).

## Fluxtags

Decorative navigation markers placed near the top of each file.
Use `<C-]>` on a `|||ref|||` to jump to the corresponding `@@@mark`.
Not a dependency -- just bookmarks for cross-module navigation.

```lua
-- @@@proj.session
-- ###nvim-plugin
```

When adding a new module, place a `@@@proj.<name>` mark after requires
and add a `|||proj.<name>|||` ref in `init.lua`.

## Code style

Follows snacks.nvim source conventions unless noted otherwise.

### Formatting

- Indentation: **4 spaces**, no tabs.
- No hard line-length limit. Break long lines where it aids readability.
- Double quotes for all strings: `"string"`.
- Parentheses on all function calls: `require("proj.session")`.

### Module pattern

```lua
local M = {}

-- @@@proj.modulename
-- ###nvim-plugin

local project = require("proj.project")

---@class proj.Config
---@field keymap_prefix string

local defaults = { keymap_prefix = "p" }

---@param opts? proj.Config
function M.setup(opts)
    local cfg = vim.tbl_deep_extend("force", defaults, opts or {})
    local aug = vim.api.nvim_create_augroup("Proj", { clear = true })
    -- wire commands, keymaps, autocmds using aug ...
end

return M
```

- `local M = {}` at top, `return M` at bottom.
- Public: `function M.func_name(...)`. Private: `local function helper(...)`.
- Methods on class objects: `function Project:method()`.
- Setup guard via `vim.g.proj_loaded` in `plugin/proj.lua` (not `_did_setup`).
- All autocmds use the `"Proj"` augroup (cleared on each `setup()` call).
- All user commands include a `desc` field.

### Naming

- Files, functions, variables: `snake_case`
- Types/classes: `PascalCase` in annotations (`Project`, `ListItem`)
- Vim aliases at file top: `local api = vim.api`, `local fn = vim.fn`

### Type annotations

```lua
---@class proj.Project
---@field root string
---@field name string

---@param root string
---@return proj.Project
function M.new(root)
```

- `---@class` + `---@field` for public types. Prefix with `proj.`.
- `---@param` / `---@return` on public functions.
- Nullable: `---@param buf? number`.
- `---@private` for internal functions.

### Error handling

- `pcall` for IO / shell / vim.cmd calls that can fail.
- Return safe defaults on failure: `{}`, `false`, `nil`.
- `vim.notify(msg, vim.log.levels.WARN)` for user-visible messages.
- `error()` only for programming errors (missing required args).
- `vim.v.shell_error` check after `vim.fn.system`.
- `vim.fn.fnameescape()` paths passed to ex commands.

### Neovim APIs

- `vim.api` -- buffers, windows, autocmds, user commands, namespaces.
- `vim.fn` -- filesystem, shell, vimscript builtins.
- `vim.bo[buf].option` -- buffer-local options.
- `vim.cmd` / `vim.cmd.edit(path)` -- ex commands.
- `vim.keymap.set` -- keymaps, always with `desc`.

### Snacks usage

```lua
Snacks.picker({ ... })           -- fuzzy selection
Snacks.input({ prompt = "..." }, callback)  -- text input
Snacks.win({ ... })              -- floating window
```

Floating windows: `border = "rounded"`, `q` / `<Esc>` to close.

### UI conventions

- Scratch buffers: `buftype = "nofile"`, `swapfile = false`, `bufhidden = "wipe"`.
- Set `vim.bo[buf].modifiable = false` after filling a display buffer.
- Set `vim.bo[buf].filetype = "markdown"` on buffers showing `.md` content.

## Key design rules

- One project per tab. `init.lua` maintains a `tabpage -> Project` map.
- Sessions stored under `vim.fn.stdpath("data") .. "/proj_sessions/"`.
- Global session: `_global.vim`; per-project: `<sanitized_name>.vim`.
- Registry file: `vim.fn.stdpath("data") .. "/proj_registry.json"`.
- List files (any `.md` with `##` headings) live in the project root.
- Opencode: `require("opencode").toggle()` scoped by tab CWD.
- No session for a project -> `vim.cmd.edit(root)` (opens in user's explorer).

## Adding new features

1. New file under `lua/proj/`. Add `@@@proj.<name>` + `###nvim-plugin` marks.
2. Add `|||proj.<name>|||` ref in `init.lua`.
3. Wire commands / keymaps in `init.lua`.
4. Update module structure in this file.

## Agent behavior

- Only edit files under `plugin/`, `lua/proj/`, `tests/`, `AGENTS.md`, `README.md`, `TODO.md`, `TOTEST.md`.
- Preserve fluxtag marks when editing; add new ones as needed.
- Match surrounding style. Keep changes minimal.
- Do not add dependencies beyond snacks.nvim and opencode.nvim.
- When unsure, check snacks.nvim source at `~/.local/share/nvim/lazy/snacks.nvim/`.
