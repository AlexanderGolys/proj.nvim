local M = {}

-- @@@proj.session
-- ###nvim-plugin

local fn = vim.fn

local session_dir = fn.stdpath("data") .. "/proj_sessions/"

---@param name string
---@return string
local function sanitize(name)
    return name:gsub("[^%w_-]", "_")
end

---@param name string
---@return string
local function session_path(name)
    return session_dir .. sanitize(name) .. ".vim"
end

local function ensure_dir()
    if fn.isdirectory(session_dir) == 0 then
        fn.mkdir(session_dir, "p")
    end
end

-- sessionoptions for a single-tab save: no tabpages, no global options.
local TAB_SSOP = "buffers,curdir,folds,help,winsize,winpos,localoptions"

---@param name string
function M.save(name)
    ensure_dir()
    local path = session_path(name)
    local prev_ssop = vim.o.sessionoptions
    vim.o.sessionoptions = TAB_SSOP
    local ok = pcall(vim.cmd, "mksession! " .. fn.fnameescape(path))
    vim.o.sessionoptions = prev_ssop
    if not ok then
        vim.notify("Failed to save session: " .. name, vim.log.levels.WARN)
    end
end

---@param name string
---@param root string
function M.restore(name, root)
    local path = session_path(name)
    if fn.filereadable(path) == 1 then
        -- Wipe only the current tab's windows before sourcing.
        -- mksession with TAB_SSOP doesn't emit tabnew, so it restores
        -- into whatever tab is current without touching others.
        pcall(vim.cmd, "silent! %bwipeout!")
        local ok = pcall(vim.cmd, "source " .. fn.fnameescape(path))
        if ok then
            vim.cmd.tcd(fn.fnameescape(root))
            return
        end
        vim.notify("Failed to restore session, opening directory", vim.log.levels.WARN)
    end
    vim.cmd.edit(root)
end

function M.save_global()
    ensure_dir()
    local path = session_dir .. "_global.vim"
    pcall(vim.cmd, "mksession! " .. fn.fnameescape(path))
end

function M.restore_global()
    local path = session_dir .. "_global.vim"
    if fn.filereadable(path) == 1 then
        pcall(vim.cmd, "source " .. fn.fnameescape(path))
    end
end

return M
