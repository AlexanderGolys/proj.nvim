local M = {}

-- @@@proj.git
-- ###nvim-plugin

local fn = vim.fn

---@param cmd string[]
---@param cwd string
---@return string, boolean ok
local function run(cmd, cwd)
    local full = vim.list_extend({ "git", "-C", cwd }, cmd)
    local result = fn.system(full)
    return vim.trim(result), vim.v.shell_error == 0
end

---@param cwd string
function M.status(cwd)
    local out, ok = run({ "status", "--short" }, cwd)
    if not ok then
        vim.notify("git status failed", vim.log.levels.WARN)
        return
    end
    if out == "" then
        vim.notify("Working tree clean", vim.log.levels.INFO)
        return
    end
    local lines = vim.split(out, "\n", { plain = true })
    local items = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            items[#items + 1] = { text = line }
        end
    end
    Snacks.picker({
        title = "Git Status",
        items = items,
        format = function(item) return { { item.text } } end,
        preview = false,
        confirm = function(picker) picker:close() end,
    })
end

---@param cwd string
function M.diff(cwd)
    local out, ok = run({ "diff" }, cwd)
    if not ok then
        vim.notify("git diff failed", vim.log.levels.WARN)
        return
    end
    if out == "" then
        vim.notify("No unstaged changes", vim.log.levels.INFO)
        return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, "\n", { plain = true }))
    vim.bo[buf].filetype = "diff"
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    Snacks.win({
        buf = buf,
        title = "Git Diff",
        border = "rounded",
        width = 0.85,
        height = 0.85,
        keys = { q = "close", ["<Esc>"] = "close" },
    })
end

---@param cwd string
function M.history(cwd)
    local out, ok = run({ "log", "--oneline", "-50" }, cwd)
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
                local show, _ = run({ "show", "--stat", item.hash }, cwd)
                vim.notify(show, vim.log.levels.INFO)
            end
        end,
    })
end

---@param cwd string
function M.commit(cwd)
    Snacks.input({ prompt = "Commit message" }, function(msg)
        if not msg or msg == "" then return end
        local _, ok = run({ "add", "-A" }, cwd)
        if not ok then
            vim.notify("git add failed", vim.log.levels.WARN)
            return
        end
        local out, ok2 = run({ "commit", "-m", msg }, cwd)
        if ok2 then
            vim.notify(out, vim.log.levels.INFO)
        else
            vim.notify("git commit failed:\n" .. out, vim.log.levels.WARN)
        end
    end)
end

---@param cwd string
function M.stash(cwd)
    Snacks.input({ prompt = "Stash message (empty = unnamed)" }, function(msg)
        local cmd = msg and msg ~= "" and { "stash", "push", "-m", msg } or { "stash", "push" }
        local out, ok = run(cmd, cwd)
        if ok then
            vim.notify(out ~= "" and out or "Stashed", vim.log.levels.INFO)
        else
            vim.notify("git stash failed:\n" .. out, vim.log.levels.WARN)
        end
    end)
end

---@param cwd string
function M.branch(cwd)
    local current, _ = run({ "branch", "--show-current" }, cwd)
    Snacks.input({ prompt = "New branch name", default = current .. "-" }, function(name)
        if not name or name == "" then return end
        local out, ok = run({ "checkout", "-b", name }, cwd)
        if ok then
            vim.notify("Switched to branch: " .. name, vim.log.levels.INFO)
        else
            vim.notify("git checkout -b failed:\n" .. out, vim.log.levels.WARN)
        end
    end)
end

return M
