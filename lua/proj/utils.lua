-- @@@proj.utils
-- ###nvim-plugin

local fn = vim.fn

---@class proj.Utils
local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
    vim.notify(msg, level or vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
    M.notify(msg, vim.log.levels.INFO)
end

---@param msg string
function M.warn(msg)
    M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.error(msg)
    M.notify(msg, vim.log.levels.ERROR)
end

---@param path string
---@param context string
---@return boolean
function M.ensure_parent_dir(path, context)
    local dir = fn.fnamemodify(path, ":h")
    if fn.isdirectory(dir) == 1 then
        return true
    end
    local ok = pcall(fn.mkdir, dir, "p")
    if not ok then
        M.notify("Failed to create directory for " .. context .. ": " .. dir)
        return false
    end
    return true
end

---@param path string
---@return string[]
function M.read_lines(path)
    if fn.filereadable(path) ~= 1 then
        return {}
    end
    local ok, lines = pcall(fn.readfile, path)
    if not ok or type(lines) ~= "table" then
        return {}
    end
    return lines
end

---@param path string
---@param lines string[]
---@param context string
---@return boolean
function M.write_lines(path, lines, context)
    if not M.ensure_parent_dir(path, context) then
        return false
    end
    local ok = pcall(fn.writefile, lines, path)
    if not ok then
        M.notify("Failed to write " .. context .. ": " .. path)
        return false
    end
    return true
end

---@param path string
---@return table
function M.read_json(path)
    local lines = M.read_lines(path)
    if #lines == 0 then
        return {}
    end
    local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok or type(data) ~= "table" then
        return {}
    end
    return data
end

---@param path string
---@param data table
---@param context string
---@return boolean
function M.write_json(path, data, context)
    local ok, encoded = pcall(vim.json.encode, data)
    if not ok or type(encoded) ~= "string" then
        M.notify("Failed to encode " .. context)
        return false
    end
    return M.write_lines(path, { encoded }, context)
end

---@param callback fun()
---@param context string
---@return boolean
function M.try_cmd(callback, context)
    local ok, err = pcall(callback)
    if ok then
        return true
    end
    M.notify(context .. ": " .. tostring(err))
    return false
end

return M
