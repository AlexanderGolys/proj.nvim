-- @@@proj.session
-- ###nvim-plugin

local fn = vim.fn

---@class proj.SessionService
---@field dir string Directory where session files are stored.
---@field tab_ssop string Session options used for per-tab session saves.
local Session = {}
Session.__index = Session

---@return proj.SessionService
function Session:new()
    return setmetatable({
        dir = fn.stdpath("data") .. "/proj_sessions/",
        tab_ssop = "buffers,curdir,folds,help,winsize,winpos,localoptions",
    }, self)
end

---@private
---@param name string
---@return string
function Session:_sanitize(name)
    return (name:gsub("[^%w_-]", "_"))
end

---@private
---@param name string
---@return string
function Session:_path(name)
    return self.dir .. self:_sanitize(name) .. ".vim"
end

---@private
function Session:_ensure_dir()
    if fn.isdirectory(self.dir) == 0 and not pcall(fn.mkdir, self.dir, "p") then
        vim.notify("Failed to create session directory", vim.log.levels.WARN)
    end
end

---@param name string Project name.
function Session:save(name)
    self:_ensure_dir()
    local prev = vim.o.sessionoptions
    vim.o.sessionoptions = self.tab_ssop
    local ok = pcall(function() vim.cmd("mksession! " .. fn.fnameescape(self:_path(name))) end)
    vim.o.sessionoptions = prev
    if not ok then
        vim.notify("Failed to save session: " .. name, vim.log.levels.WARN)
    end
end

---@param name string Project name.
---@param root string Project root path.
function Session:restore(name, root)
    local path = self:_path(name)
    if fn.filereadable(path) == 1 then
        pcall(function() vim.cmd("silent! only") end)
        pcall(function() vim.cmd("silent! enew") end)
        if pcall(function() vim.cmd("source " .. fn.fnameescape(path)) end) then
            vim.cmd.tcd(fn.fnameescape(root))
            return
        end
        vim.notify("Failed to restore session, opening directory", vim.log.levels.WARN)
    end
    vim.cmd.edit(root)
end

function Session:save_global()
    self:_ensure_dir()
    pcall(function() vim.cmd("mksession! " .. fn.fnameescape(self.dir .. "_global.vim")) end)
end

function Session:restore_global()
    local path = self.dir .. "_global.vim"
    if fn.filereadable(path) == 1 then
        pcall(function() vim.cmd("source " .. fn.fnameescape(path)) end)
    end
end

---@type proj.SessionService
local service = Session:new()
local M = { Session = Session }

---@param name string
function M.save(name) service:save(name) end
---@param name string
---@param root string
function M.restore(name, root) service:restore(name, root) end
function M.save_global() service:save_global() end
function M.restore_global() service:restore_global() end

return M
