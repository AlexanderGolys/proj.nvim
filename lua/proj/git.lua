-- @@@proj.git
-- ###nvim-plugin

local fn, api = vim.fn, vim.api

---@class proj.GitService
local Git = {}
Git.__index = Git

---@return proj.GitService
function Git:new()
    return setmetatable({}, self)
end

---@private
---@param cmd string[]
---@param cwd string
---@return string output
---@return boolean ok
function Git:run(cmd, cwd)
    local out = fn.system(vim.list_extend({ "git", "-C", cwd }, cmd))
    return vim.trim(out), vim.v.shell_error == 0
end

---@param cwd string Project root.
function Git:status(cwd)
    local out, ok = self:run({ "status", "--short" }, cwd)
    if not ok then
        vim.notify("git status failed", vim.log.levels.WARN)
        return
    end
    if out == "" then
        vim.notify("Working tree clean", vim.log.levels.INFO)
        return
    end
    local items = {}
    for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
        if line ~= "" then items[#items + 1] = { text = line } end
    end
    Snacks.picker({
        title = "Git Status",
        items = items,
        format = function(item) return { { item.text } } end,
        preview = false,
        confirm = function(picker) picker:close() end,
    })
end

---@param cwd string Project root.
function Git:diff(cwd)
    local out, ok = self:run({ "diff" }, cwd)
    if not ok then
        vim.notify("git diff failed", vim.log.levels.WARN)
        return
    end
    if out == "" then
        vim.notify("No unstaged changes", vim.log.levels.INFO)
        return
    end
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, "\n", { plain = true }))
    vim.bo[buf].filetype, vim.bo[buf].modifiable, vim.bo[buf].bufhidden = "diff", false, "wipe"
    Snacks.win({ buf = buf, title = "Git Diff", border = "rounded", width = 0.85, height = 0.85, keys = { q = "close", ["<Esc>"] = "close" } })
end

---@param cwd string Project root.
function Git:history(cwd)
    local out, ok = self:run({ "log", "--oneline", "-50" }, cwd)
    if not ok or out == "" then
        vim.notify("No git history", vim.log.levels.INFO)
        return
    end
    local items = {}
    for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
        if line ~= "" then
            local hash, msg = line:match("^(%x+)%s+(.+)$")
            items[#items + 1] = { text = line, hash = hash, msg = msg }
        end
    end
    Snacks.picker({
        title = "Git History",
        items = items,
        format = function(item) return { { item.text } } end,
        confirm = function(picker, item)
            picker:close()
            if item and item.hash then
                local show = self:run({ "show", "--stat", item.hash }, cwd)
                vim.notify(show, vim.log.levels.INFO)
            end
        end,
    })
end

---@param cwd string Project root.
function Git:commit(cwd)
    Snacks.input({ prompt = "Commit message" }, function(msg)
        if not msg or msg == "" then return end
        local _, add_ok = self:run({ "add", "-A" }, cwd)
        if not add_ok then
            vim.notify("git add failed", vim.log.levels.WARN)
            return
        end
        local out, ok = self:run({ "commit", "-m", msg }, cwd)
        vim.notify(ok and out or ("git commit failed:\n" .. out), ok and vim.log.levels.INFO or vim.log.levels.WARN)
    end)
end

---@param cwd string Project root.
function Git:stash(cwd)
    Snacks.input({ prompt = "Stash message (empty = unnamed)" }, function(msg)
        local out, ok = self:run(msg and msg ~= "" and { "stash", "push", "-m", msg } or { "stash", "push" }, cwd)
        vim.notify(ok and (out ~= "" and out or "Stashed") or ("git stash failed:\n" .. out), ok and vim.log.levels.INFO or vim.log.levels.WARN)
    end)
end

---@param cwd string Project root.
function Git:branch(cwd)
    local current = self:run({ "branch", "--show-current" }, cwd)
    Snacks.input({ prompt = "New branch name", default = current .. "-" }, function(name)
        if not name or name == "" then return end
        local out, ok = self:run({ "checkout", "-b", name }, cwd)
        vim.notify(ok and ("Switched to branch: " .. name) or ("git checkout -b failed:\n" .. out), ok and vim.log.levels.INFO or vim.log.levels.WARN)
    end)
end

---@type proj.GitService
local service = Git:new()
local M = { Git = Git }

---@param cwd string
function M.status(cwd) service:status(cwd) end
---@param cwd string
function M.diff(cwd) service:diff(cwd) end
---@param cwd string
function M.history(cwd) service:history(cwd) end
---@param cwd string
function M.commit(cwd) service:commit(cwd) end
---@param cwd string
function M.stash(cwd) service:stash(cwd) end
---@param cwd string
function M.branch(cwd) service:branch(cwd) end

return M
