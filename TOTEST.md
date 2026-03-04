## Registration keymap hidden inside registered projects

When editing a file inside a registered project, the registration keymap
(`register_keymap_lhs`, default `<kEnter>a`) should be disabled for that
buffer. Outside registered projects, it should remain available.

## ProjectHelp opens in equal vertical split

Run `:ProjectHelp`. Help should open in a vertical split and window sizes
should be equalized automatically (`wincmd =` behavior).

## proj repo name normalized to proj.nvim

When this plugin repo is registered via `:ProjectAdd`, its project name should
show as `proj.nvim` (not `proj`) in `:ProjectSwitch` and lualine component.

## ProjectTodo shows legacy/plain TODO files

If `TODO.md` has plain lines (for example `- item` or `item`) without `##`
headings, `:ProjectTodo` should still show those entries in the picker.
Also verify opening a missing TODO file via `:ProjectTodo` creates the file
and opens an empty picker.

## Switching projects no longer closes other tabs

When running `:ProjectSwitch`, restoring the selected project session should
only reset the current tab. Other tabs and their windows should remain open.
Verify with 3+ tabs open and switch projects repeatedly.

## Empty and missing list files handled gracefully

`:ProjectTodo` (and any list picker) on a missing file should create an empty
file and open an empty picker rather than showing an error. On a file with no
`##` headings the picker opens empty. Verify by deleting `TODO.md` and running
`:ProjectTodo` — file should be created and picker should open empty.

## Global list picker always shows picker

`:ProjectGlobalTodo` with only some projects having `TODO.md` content should
show a picker with items only from those projects. If no project has content
the picker opens empty. Verify with a mix of populated and empty projects.

## Add item to any project from global commands

`:ProjectGlobalAddTodo` (and `Bug`, `Totest`, generic `:ProjectGlobalAddItem
<file>`) opens a project picker, then an input prompt. The item is written to
the selected project's file. Also `<leader>pgT`, `pgB`, `pgE` keymaps.
Test by adding a TODO to a non-current project and verifying it appears in
that project's `TODO.md`.

## List picker item actions with keybind hints

In any list picker (`ProjectTodo`, `ProjectList`, etc.) in normal mode:
- `dd` deletes the selected item from the file and reopens the picker
- `mm` opens a secondary picker of other `.md` files in the project root;
  selecting one moves the item there and reopens the original picker
- `mt` (TODO picker only) prompts for an optional annotation, then moves
  the item to `TOTEST.md`
- Available keybinds shown in the picker footer centred below the list

Verify the footer is visible, all three actions modify the file on disk,
and the picker refreshes automatically after each action.

## Git commands wired from keybinds.lua

`<leader>gc` commit, `<leader>gs` stash, `<leader>gb` new branch,
`<leader>ga` add all, `<leader>gA` add current file.
Test each from inside a git repo with staged/unstaged changes.

## Old projectral keymaps removed

Confirm no `ProjectDashboard`, `ProjectSet`, `ProjectViewport` etc. remain.
Run `:map <leader>p` and verify only proj commands appear.

## Global list commands aggregate across all projects

`:ProjectGlobalTodo`, `:ProjectGlobalBugs`, `:ProjectGlobalTotest` and
generic `:ProjectGlobalList <file>` should open a picker with items from
all registered projects. Each item prefixed with project name.

## Keymaps with <leader>p group

`<leader>ps` switch, `<leader>pa` add, `<leader>pt` todo, `<leader>pb` bugs,
`<leader>pe` totest, uppercase for add variants, `<leader>po` opencode,
`<leader>pg{t,b,e}` for global lists. Verify all mappings appear in
`:map <leader>p`.

## ProjectSwitch command lists all registered projects

`:ProjectSwitch` opens a snacks picker with all projects from the registry.
Enter opens the selected project in current tab with session restore.

## Lualine tabline component for current project

`require("proj").lualine_component()` returns the current project name for
the active tab (empty string if none). `require("proj").current(tabpage)`
accepts an optional tabpage id. Usage in lualine tabline config:

```lua
tabline = {
    lualine_a = {
        { require("proj").lualine_component },
    },
    lualine_b = {
        { "buffers", icon_only = true },
    },
}
```

## Tabline shows current project name

Open Neovim with proj loaded, run `:ProjectAdd` or `:ProjectSwitch`. The
lualine tabline `lualine_a` section should show the project name. Previously
it was always empty due to `state.tab.project()` being called as a function
on a non-function value.

## Lualine_b tabline color updates after mode change

Switch modes (normal → insert → visual). The `lualine_b` buffers component
in the tabline should update its `fg` color to match the mode accent. A
`lualine.refresh()` is now triggered on `AccentColorChanged`.

## New tab inherits current project

Open a project, then open a new tab (`:tabnew`). The new tab should show
the same project name in the tabline immediately, without needing to run
`:ProjectSwitch`.

## Error detected while processing BufEnter Autocommands for "*":

Error executing lua callback: /home/flux/.config/nvim/lua/config/state.lua:120: attempt to call global 'oil_current_dir' (a nil value)
stack traceback:
        /home/flux/.config/nvim/lua/config/state.lua:120: in function 'buf_display_name'
        /home/flux/.config/nvim/lua/config/state.lua:191: in function 'update_buffer'
        /home/flux/.config/nvim/lua/config/state.lua:454: in function </home/flux/.config/nvim/lua/config/state.lua:453>

## Sometimes the current ptoject per buffer is detected wrongly, displaying a directory that is not a root (no .git inside). For example this happens for the opencode TUI 

## Sort projects by most frequently opened

When using `:ProjectSwitch`, projects are sorted based on how many times they've been opened. Open several projects via `:ProjectSwitch` multiple times, and verify the ones you open most bubble up to the top of the list in subsequent `:ProjectSwitch` picker windows.

## Toggle preview of all non-empty lists found in current project

Use the `:ProjectPreviewLists` command or `<leader>pp` to toggle a floating preview window displaying all non-empty lists found in the current project's `.md` files. Ensure the window correctly toggles open and closed, handles empty states, and formats the contents with headers.
