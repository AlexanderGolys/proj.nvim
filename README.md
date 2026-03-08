# proj.nvim


Tab-scoped project manager for Neovim. Each tab owns one project with its own
working directory. Projects are registered from
git repos and persisted across restarts. Markdown files with `##` headings become
browsable lists with preview. Includes git operations, JSON issue tracking, and
cross-project aggregation.

## Dependencies

- [snacks.nvim](https://github.com/folke/snacks.nvim) -- picker, input, win

## Commands

### Project Management

**`:ProjectAdd`** — Register current directory as a project (requires `.git`).
Project name is the directory basename. Registry saved to `stdpath("data")/proj_registry.json`.

**`:ProjectSwitch`** — Open picker of all registered projects, sorted by open frequency.
Selecting a project switches to it: sets tab-local CWD and opens the remembered
last modified file for that project. If no file is remembered, opens `readme.md`
from project root, then falls back to opening the project root.

**`:ProjectReadme`** — Open `README.md` from the current project root.

### Lists (Markdown with `##` headings)

**`:ProjectList <file>`** — Pick items from a markdown file (any `.md` in project root).
Each `## Heading` becomes a picker item; body text shown as preview. Enter opens file at heading.

**`:ProjectAddItem <file>`** — Add new item to a markdown file (creates file if missing).

**Shorthand commands:**

| Command | Equivalent |
|---------|-----------|
| `:ProjectTodo` | `:ProjectList TODO.md` |
| `:ProjectBugs` | `:ProjectList BUGS.md` |
| `:ProjectTotest` | `:ProjectList TOTEST.md` |
| `:ProjectRemember` | `:ProjectList REMEMBER.md` |
| `:ProjectAddTodo` | `:ProjectAddItem TODO.md` |
| `:ProjectAddBug` | `:ProjectAddItem BUGS.md` |
| `:ProjectAddTotest` | `:ProjectAddItem TOTEST.md` |
| `:ProjectAddRemember` | `:ProjectAddItem REMEMBER.md` |

### Cross-Project Lists

**`:ProjectGlobalList <file>`** — Aggregate list items across all projects into one picker.
Each item prefixed with project name.

**`:ProjectGlobalTodo`** / **`:ProjectGlobalBugs`** / **`:ProjectGlobalTotest`** — Shorthand global pickers.

**`:ProjectGlobalAddItem <file>`** — Pick a project, then add item to its file.

**`:ProjectGlobalAddTodo`** / **`:ProjectGlobalAddBug`** / **`:ProjectGlobalAddTotest`** — Shorthand add.

**`:ProjectGlobalAddAnyItem`** — Interactively choose project and list file, then add.

### Global-Only Lists

**`:ProjectGlobalKeymaps`** / **`:ProjectGlobalRemember`** — View global lists stored in `stdpath("data")/proj_lists/`.

**`:ProjectGlobalAddKeymaps`** / **`:ProjectGlobalAddRemember`** — Add to global lists.

### Issues (JSON-based)

**`:ProjectIssues`** — Pick bugs from `.issues/bugs.json`.

**`:ProjectIssuesTodo`** — Pick todos from `.issues/todos.json`.

**`:ProjectIssuesGlobal`** / **`:ProjectIssuesTodoGlobal`** — Cross-project issue pickers.

### Git Operations

Git pickers are delegated to `Snacks.picker.git_*` in the project root.

**`:ProjectGitStatus`** — Open `Snacks.picker.git_status`.

**`:ProjectGitDiff`** — Open `Snacks.picker.git_diff`.

**`:ProjectGitHistory`** — Open `Snacks.picker.git_log`.

**`:ProjectGitCommit`** — Async `git add -A` + `git commit -m`.

**`:ProjectGitStash`** — Open `Snacks.picker.git_stash`.

**`:ProjectGitBranch`** — Open `Snacks.picker.git_branches`.

### Utilities

**`:ProjectHelp`** — Open plugin help in equal vertical split.

**`:ProjectPreviewLists`** — Toggle floating preview of all non-empty `.md` lists in project root.

**`:ProjectInfo`** — Toggle a right-side floating project info panel showing name, root, last modified file, file tree, and TODO headers.

## Setup Options

Standard usage:

```lua
require("proj").setup({
    keymaps = {
        add_any_item = "<leader>pa",
        preview_lists = "<leader>pp",
    },
})
```

You can also use a config callback:

```lua
require("proj").setup({
    opts = { keymap_prefix = "p" },
    config = function(cfg)
        cfg.keymaps = cfg.keymaps or {}
        cfg.keymaps.preview_lists = "<leader>pP"
        return cfg
    end,
})
```

Supported config fields:

- `keymap_prefix` (default `"p"`) for plugin-owned `<leader>` keymaps.
- `register_keymap_lhs` (default `"<kEnter>a"`): buffer-local disable target
  for project registration keymaps when the current buffer is already inside a
  registered project.
- `keymaps` (optional table) to override plugin mappings:
  - `add_any_item` for `:ProjectGlobalAddAnyItem`
  - `preview_lists` for `:ProjectPreviewLists`
- set `keymaps = false` to disable plugin mappings entirely

## Architecture

Six modules under `lua/proj/`:

**`proj.lua`** — Entry point. Wires all commands, keymaps, and autocmds.
Maintains tab→project mapping, handles project switching and per-project file restore.

**`project.lua`** — `ProjectList` object backed by registry JSON at
`stdpath("data")/proj_registry.json`. Constructor reads/parses projects,
keeps an in-memory index, and persists on mutations.

**`config.lua`** — Config defaults + resolved options. Handles merge logic for
`setup(opts)` and optional `config` callback.

**`last_file.lua`** — Stores and restores last modified file per project in
`stdpath("data")/proj_last_files.json`.

**`lists.lua`** — Parses markdown by `## ` headings into items.
Functions: `parse()`, `pick()` (snacks picker), `add()`, and cross-project aggregators.

**`issues.lua`** — JSON-based issue tracking (`.issues/{bugs,todos}.json`).
Functions: `pick()`, `pick_global()` for cross-project aggregation.

**`utils.lua`** — Shared IO/json/notify helpers used by project modules.

## Integration

### Lualine Tabline Component

Show current project name in tabline:

```lua
require("lualine").setup({
    tabline = {
        lualine_a = {
            { require("proj").lualine_component },
        },
        lualine_b = {
            { "buffers" },
        },
    },
})
```

### Keymaps

Default keymaps:

- `<leader>pa` — Add item to any list in any project
- `<leader>pp` — Preview all lists in current project

Configurable via `require("proj").setup({ keymaps = { ... } })`.

## Design

- **One project per tab** — Each tab maps to one project via `tabpage -> Project` table.
- **Registry** — Persisted in JSON at `stdpath("data")/proj_registry.json`.
- **Last modified file restore** — Per-project file map under `stdpath("data")/proj_last_files.json`.
- **Lists** — Any `.md` with `##` headings in project root becomes a browsable list.
- **Auto-detect** — On startup or tab entry, project auto-detected from current directory.
- **CWD sync** — Tab-local CWD (`tcd`) always matches project root.
- **Modules are mostly leaves** — Shared helper logic lives in `proj.utils`.
