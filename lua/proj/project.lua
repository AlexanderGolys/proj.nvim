local M = {}

-- @@@proj
-- ###nvim-plugin

local fn = vim.fn

---@class proj.Project
---@field root string
---@field name string
---@field open_count? integer

local registry_path = fn.stdpath("data") .. "/proj_registry.json"

---@param root string
---@return proj.Project
function M.new(root)
    return {
        root = root,
        name = fn.fnamemodify(root, ":t"),
    }
end

---@return proj.Project[]
function M.read()
    if fn.filereadable(registry_path) ~= 1 then
        return {}
    end
    local ok, raw = pcall(fn.readfile, registry_path)
    if not ok or #raw == 0 then
        return {}
    end
    local ok2, data = pcall(vim.json.decode, table.concat(raw, "\n"))
    if not ok2 or type(data) ~= "table" then
        return {}
    end
    return data
end

---@param projects proj.Project[]
function M.write(projects)
    local dir = fn.fnamemodify(registry_path, ":h")
    if fn.isdirectory(dir) == 0 then
        local ok = pcall(fn.mkdir, dir, "p")
        if not ok then
            vim.notify("Failed to create project registry directory", vim.log.levels.WARN)
            return
        end
    end
    local ok_encode, json = pcall(vim.json.encode, projects)
    if not ok_encode then
        vim.notify("Failed to encode project registry", vim.log.levels.WARN)
        return
    end
    local ok_write = pcall(fn.writefile, { json }, registry_path)
    if not ok_write then
        vim.notify("Failed to write project registry", vim.log.levels.WARN)
    end
end

---@param root string
---@return proj.Project?
function M.add(root)
    if fn.isdirectory(root .. "/.git") == 0 then
        vim.notify("Not a git repo: " .. root, vim.log.levels.WARN)
        return nil
    end
    local projects = M.read()
    for _, p in ipairs(projects) do
        if p.root == root then
            vim.notify("Already registered: " .. p.name, vim.log.levels.WARN)
            return nil
        end
    end
    local proj = M.new(root)
    proj.open_count = 0
    projects[#projects + 1] = proj
    M.write(projects)
    vim.notify("Added project: " .. proj.name, vim.log.levels.INFO)
    return proj
end

---@param root string
function M.increment_open(root)
    local projects = M.read()
    local updated = false
    for _, p in ipairs(projects) do
        if p.root == root then
            p.open_count = (p.open_count or 0) + 1
            updated = true
            break
        end
    end
    if updated then
        M.write(projects)
    end
end

---@param root string
function M.remove(root)
    local projects = M.read()
    local filtered = {}
    for _, p in ipairs(projects) do
        if p.root ~= root then
            filtered[#filtered + 1] = p
        end
    end
    M.write(filtered)
end

---@param path? string
---@return string?
function M.find_git_root(path)
    path = path or fn.getcwd()
    local result = fn.systemlist({ "git", "-C", path, "rev-parse", "--show-toplevel" })
    if vim.v.shell_error ~= 0 or #result == 0 then
        return nil
    end
    return result[1]
end

return M
