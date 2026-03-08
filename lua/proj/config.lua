-- @@@proj.config

---@class proj.KeymapConfig
---@field add_any_item? string|false Map for `ProjectGlobalAddAnyItem`.
---@field preview_lists? string|false Map for `ProjectPreviewLists`.

---@class proj.Config
---@field keymap_prefix string Leader suffix used by plugin keymaps.
---@field register_keymap_lhs string LHS to disable in registered project buffers.
---@field keymaps proj.KeymapConfig|false Optional keymap overrides. `false` disables plugin keymaps.
---@field open_weighting fun(date_rank: integer): number Weighting helper for future ranking features.

---@class proj.SetupOptions: proj.Config
---@field opts? proj.Config Optional nested options table.
---@field config? fun(cfg: proj.Config): proj.Config? Optional callback to mutate/finalize resolved config.

local M = {}

---@type proj.Config
M.defaults = {
    keymap_prefix = "p",
    register_keymap_lhs = "<kEnter>a",
    keymaps = {
        add_any_item = "<leader>pa",
        preview_lists = "<leader>pp",
    },
    open_weighting = function(date_rank)
        return 1 / math.sqrt(date_rank)
    end,
}

---@type proj.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? proj.SetupOptions|proj.Config
---@return proj.Config
function M.setup(opts)
    local cfg_opts = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            if key ~= "opts" and key ~= "config" then
                cfg_opts[key] = value
            end
        end
        if type(opts.opts) == "table" then
            cfg_opts = vim.tbl_deep_extend("force", cfg_opts, opts.opts)
        end
    end
    local resolved = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), cfg_opts)
    if type(opts) == "table" and type(opts.config) == "function" then
        local ok, maybe_cfg = pcall(opts.config, resolved)
        if not ok then
            vim.notify("proj.config callback failed", vim.log.levels.WARN)
        elseif type(maybe_cfg) == "table" then
            resolved = vim.tbl_deep_extend("force", resolved, maybe_cfg)
        end
    end
    M.options = resolved
    return M.options
end

---@return proj.Config
function M.get()
    return M.options
end

return M
