# proj.nvim

Tab-scoped project manager for Neovim. Each tab owns one project with its
own working directory, session, and opencode instance. Projects are registered
from git repos and persisted across restarts. Any markdown file with `##`
headings in the project root becomes a browsable list through snacks pickers
with header/body preview.

## Dependencies

- [snacks.nvim](https://github.com/folke/snacks.nvim) -- picker, input, win
- [opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) -- AI coding assistant

## Commands

### `:ProjectAdd`

Register the current directory as a project. The directory must contain a
`.git` folder. The project name is derived from the directory basename. If
the project is already registered, a warning is shown. The registry is
written to `vim.fn.stdpath("data") .. "/proj_registry.json"` and persists
across Neovim sessions.

### `:ProjectSwitch`

Open a snacks picker listing all registered projects. Pressing `<CR>` on
an entry opens that project in the current tab: sets `tcd` to the project
root, restores the saved session (if one exists), or falls back to opening
the root directory (via the user's default file explorer). The previous
project's session is saved automatically before switching.

### `:ProjectList <file>`

Generic list picker. Takes a filename relative to the project root (e.g.
`TODO.md`, `IDEAS.md`, `GOALS.md`). Parses the file by `## ` headings --
each heading becomes a picker item, and the body text between headings is
shown as a preview. Pressing `<CR>` opens the file at that heading's line.

The shorthand commands are equivalent to:

| Shorthand          | Equivalent                  |
|--------------------|-----------------------------|
| `:ProjectTodo`     | `:ProjectList TODO.md`      |
| `:ProjectBugs`     | `:ProjectList BUGS.md`      |
| `:ProjectTotest`   | `:ProjectList TOTEST.md`    |

### `:ProjectAddItem <file>`

Generic add item. Takes a filename relative to the project root. Opens a
snacks input prompt. The entered text becomes a new `## heading` appended
to the file. If the file does not exist it is created.

The shorthand commands are equivalent to:

| Shorthand             | Equivalent                     |
|-----------------------|--------------------------------|
| `:ProjectAddTodo`     | `:ProjectAddItem TODO.md`      |
| `:ProjectAddBug`      | `:ProjectAddItem BUGS.md`      |
| `:ProjectAddTotest`   | `:ProjectAddItem TOTEST.md`    |

### `:ProjectOpenCode`

Toggle the opencode terminal for the current project. Ensures `tcd` is set
to the project root, then calls `require("opencode").toggle()`. Because
each tab has its own CWD, opencode scopes to the correct project directory.
Server discovery and process lifecycle are handled by opencode.nvim.

See `OPENCODE_ZOMBIE.md` for a known issue with duplicate server processes
across Neovim restarts.

## Internals

The plugin is split into four modules under `lua/proj/`.

### `init.lua`

Entry point. `M.setup(opts)` creates all user commands and sets up autocmds
for session save on `VimLeavePre` and tab cleanup on `TabClosed`. Maintains
a `tabpage -> Project` map so each tab knows its active project. The generic
`:ProjectList` and `:ProjectAddItem` commands live here; shorthand commands
(`:ProjectTodo`, etc.) are thin wrappers that pass the filename.

### `project.lua`

Defines the `proj.Project` class (fields: `root`, `name`) and the persistent
registry. The registry is a JSON file at `stdpath("data")/proj_registry.json`.
Public functions: `new(root)`, `read()`, `add(root)`, `remove(root)`,
`write(projects)`, `find_git_root(path)`.

### `session.lua`

Handles `mksession` / `source` for per-project and global sessions. Session
files live under `stdpath("data")/proj_sessions/`. `save(name)` writes the
current session, `restore(name, root)` loads it. When no session file exists,
falls back to `vim.cmd.edit(root)` which opens the directory in whatever
explorer the user has configured. Also saves/restores a global session
(`_global.vim`) used when no project is active.

### `lists.lua`

Reads any markdown file and splits it into items by `## ` headings. Each item
has a `header`, `body` (lines until the next heading), and `lnum`. `parse()`
returns the raw items, `pick()` opens a snacks picker with body as preview,
`add()` appends a new heading entry to the file.

## Extending

Seven directions the plugin could grow:

1. **Project-scoped marks and bookmarks** -- save per-project named file
   positions, restore them on project switch, expose via picker.

2. **Cross-project overview** -- aggregate lists across all registered
   projects into a single picker, grouped by project name.

3. **Git context panel** -- floating window showing branch, recent commits,
   dirty file count, stash list for the current project.

4. **Project templates** -- register directory templates (e.g. for Lua
   plugins, Rust crates); `:ProjectNew` scaffolds a new project from a
   template and registers it.

5. **Statusline / tabline integration** -- expose `project_name()` and
   `project_status()` functions for lualine or custom tabline rendering.

6. **List item actions** -- delete, reorder, or move items between lists
   (e.g. promote a TODO to a BUG) directly from the picker.

7. **Opencode prompt helpers** -- pre-built prompts scoped to the project
   (e.g. "fix all TODOs", "review BUGS.md") that feed project context into
   opencode automatically.
