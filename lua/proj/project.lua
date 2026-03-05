local fn = vim.fn

-- @@@proj.project
-- @##proj



---@class proj.ProjectRegistry
---@field path string Absolute path to `proj_registry.json`.
local Registry = {}
Registry.__index = Registry

---@return proj.ProjectRegistry
function Registry:new()
    return setmetatable({ path = fn.stdpath("data") .. "/proj_registry.json" }, self)
end

---@param root string
---@return proj.Project
function Registry:new_project(root)
    return { root = root, name = fn.fnamemodify(root, ":t"), open_count = 0 }
end

---@return proj.Project[]
function Registry:read()
    if fn.filereadable(self.path) ~= 1 then
        return {}
    end
    local ok, raw = pcall(fn.readfile, self.path)
    if not ok or #raw == 0 then
        return {}
    end
    local ok_decode, data = pcall(vim.json.decode, table.concat(raw, "\n"))
    return ok_decode and type(data) == "table" and data or {}
end

---@param data proj.Project[]
function Registry:write(data)
    local dir = fn.fnamemodify(self.path, ":h")
    if fn.isdirectory(dir) == 0 and not pcall(fn.mkdir, dir, "p") then
        vim.notify("Failed to create project registry directory", vim.log.levels.WARN)
        return
    end
    local ok_encode, json = pcall(vim.json.encode, data)
    if not ok_encode then
        vim.notify("Failed to encode project registry", vim.log.levels.WARN)
        return
    end
    if not pcall(fn.writefile, { json }, self.path) then
        vim.notify("Failed to write project registry", vim.log.levels.WARN)
    end
end

---@param root string
---@return proj.Project?
function Registry:add(root)
    if fn.isdirectory(root .. "/.git") == 0 then
        vim.notify("Not a git repo: " .. root, vim.log.levels.WARN)
        return nil
    end
    local data = self:read()
    for _, p in ipairs(data) do
        if p.root == root then
            vim.notify("Already registered: " .. p.name, vim.log.levels.WARN)
            return nil
        end
    end
    local proj = self:new_project(root)
    data[#data + 1] = proj
    self:write(data)
    vim.notify("Added project: " .. proj.name, vim.log.levels.INFO)
    return proj
end

---@param root string
function Registry:increment_open(root)
    local data = self:read()
    local changed = false
    for _, p in ipairs(data) do
        if p.root == root then
            p.open_count = (p.open_count or 0) + 1
            changed = true
            break
        end
    end
    if changed then
        self:write(data)
    end
end

---@param root string
function Registry:remove(root)
    local data, filtered = self:read(), {}
    for _, p in ipairs(data) do
        if p.root ~= root then
            filtered[#filtered + 1] = p
        end
    end
    self:write(filtered)
end

---@param path? string Directory to query (defaults to cwd).
---@return string? git_root Absolute git root or `nil` outside a repository.
function Registry:find_git_root(path)
    local result = fn.systemlist({ "git", "-C", path or fn.getcwd(), "rev-parse", "--show-toplevel" })
    if vim.v.shell_error ~= 0 or #result == 0 then
        return nil
    end
    return result[1]
end

---@type proj.ProjectRegistry
local registry = Registry:new()

local M = { Registry = Registry }

---@param root string
---@return proj.Project
function M.new(root)
    return registry:new_project(root)
end

---@return proj.Project[]
function M.read()
    return registry:read()
end

---@param data proj.Project[]
function M.write(data)
    registry:write(data)
end

---@param root string
---@return proj.Project?
function M.add(root)
    return registry:add(root)
end

---@param root string
function M.increment_open(root)
    registry:increment_open(root)
end

---@param root string
function M.remove(root)
    registry:remove(root)
end

---@param path? string
---@return string?
function M.find_git_root(path)
    return registry:find_git_root(path)
end

return M
