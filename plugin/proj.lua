-- Public entrypoint. Sourced automatically by Neovim when the plugin is on
-- runtimepath. Calls setup() with empty opts so the plugin is usable without
-- an explicit require("proj").setup() in the user config.
if vim.g.proj_loaded then
    return
end
vim.g.proj_loaded = true

require("proj").setup({})
