# proj.nvim


Tab-scoped project manager for Neovim. Each tab owns one project with its own
working directory, session, and opencode instance. Projects are registered from
git repos and persisted across restarts. Markdown files with `##` headings become
browsable lists with preview. Includes git operations, JSON issue tracking, and
cross-project aggregation.

## Dependencies

- [snacks.nvim](https://github.com/folke/snacks.nvim) -- picker, input, win
- [opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) -- AI coding assistant

## Commands

### Project Management

**`:ProjectAdd`** — Register current directory as a project (requires `.git`).
Project name is the directory basename. Registry saved to `stdpath("data")/proj_registry.json`.

**`:ProjectSwitch`** — Open picker of all registered projects, sorted by open frequency.
Selecting a project switches to it: sets tab-local CWD, restores session, or opens explorer.
Previous project's session saved automatically.

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

**`:ProjectGitStatus`** — Show `git status --short` in a picker.

**`:ProjectGitDiff`** — Show `git diff` in a picker.

**`:ProjectGitHistory`** — Show `git log` in a picker.

**`:ProjectGitCommit`** — Stage/commit workflow via picker.

**`:ProjectGitStash`** — Stash/pop workflow.

**`:ProjectGitBranch`** — Create or switch branches.

### Utilities

**`:ProjectOpenCode`** — Toggle opencode terminal scoped to current project (or global if no project).

**`:ProjectHelp`** — Open plugin help in equal vertical split.

**`:ProjectPreviewLists`** — Toggle floating preview of all non-empty `.md` lists in project root.

## Setup Options

`require("proj").setup({ ... })` supports:

- `keymap_prefix` (default `"p"`) for plugin-owned `<leader>` keymaps.
- `register_keymap_lhs` (default `"<kEnter>a"`): buffer-local disable target
  for project registration keymaps when the current buffer is already inside a
  registered project.

## Architecture

Seven modules under `lua/proj/`:

**`init.lua`** — Entry point. Wires all commands, keymaps, and autocmds.
Maintains tab→project mapping, handles project switching, session save/restore.

**`project.lua`** — Project registry (JSON at `stdpath("data")/proj_registry.json`).
Functions: `new(root)`, `read()`, `add(root)`, `remove(root)`, `write()`, `find_git_root()`.
Tracks open counts for project frequency sorting.

**`session.lua`** — Saves/restores sessions per-project and global.
Files under `stdpath("data")/proj_sessions/`. Fallback to `vim.cmd.edit(root)`.

**`lists.lua`** — Parses markdown by `## ` headings into items.
Functions: `parse()`, `pick()` (snacks picker), `add()`, and cross-project aggregators.

**`git.lua`** — Thin wrappers around `git` commands.
Functions: `status()`, `diff()`, `history()`, `commit()`, `stash()`, `branch()`.

**`issues.lua`** — JSON-based issue tracking (`.issues/{bugs,todos}.json`).
Functions: `pick()`, `pick_global()` for cross-project aggregation.

**`opencode.lua`** — Toggles opencode terminal scoped to project directory.

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

Default keymaps under `<leader>p`:

- `<leader>pa` — Add item to any list in any project
- `<leader>pp` — Preview all lists in current project

Configurable prefix via `require("proj").setup({ keymap_prefix = "..." })`.

## Design

- **One project per tab** — Each tab maps to one project via `tabpage -> Project` table.
- **Registry** — Persisted in JSON at `stdpath("data")/proj_registry.json`.
- **Sessions** — Per-project under `stdpath("data")/proj_sessions/`, global `_global.vim`.
- **Lists** — Any `.md` with `##` headings in project root becomes a browsable list.
- **Auto-detect** — On startup or tab entry, project auto-detected from current directory.
- **CWD sync** — Tab-local CWD (`tcd`) always matches project root.
- **Modules are leaves** — No circular requires; all modules independent except `init.lua`.
