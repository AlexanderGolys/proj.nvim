-- @@@proj.opencode
-- ###nvim-plugin

local utils = require("proj.utils")

---@alias proj.PortRegistry table<string, integer>

---@class proj.OpenCodeService
---@field registry_file string Path to persistent port registry.
local OpenCode = {}
OpenCode.__index = OpenCode

---@return proj.OpenCodeService
function OpenCode:new()
    return setmetatable({ registry_file = vim.fn.stdpath("data") .. "/proj_opencode.json" }, self)
end

---@private
---@return proj.PortRegistry
function OpenCode:read_registry()
    return utils.read_json(self.registry_file)
end

---@private
---@param data proj.PortRegistry
function OpenCode:write_registry(data)
    utils.write_json(self.registry_file, data, "opencode registry")
end

---@private
---@return integer
function OpenCode:get_free_port()
    local server = vim.uv.new_tcp()
    server:bind("127.0.0.1", 0)
    local port = server:getsockname().port
    server:close()
    return port
end

---@private
---@param port integer
---@param cb fun(is_open: boolean)
function OpenCode:check_port(port, cb)
    local client = vim.uv.new_tcp()
    client:connect("127.0.0.1", port, function(err)
        client:close()
        cb(err == nil)
    end)
end

---@private
---@param port integer
---@param cwd string
function OpenCode:start_server(port, cwd)
    vim.fn.jobstart({ "opencode", "serve", "--port", tostring(port) }, { cwd = cwd, detach = true })
end

---@private
---@param port integer
function OpenCode:attach(port)
    local provider = require("opencode.config").provider
    if not provider then
        utils.error("No opencode provider found")
        return
    end
    provider.cmd = "opencode attach http://127.0.0.1:" .. port .. " -c"
    require("opencode").toggle()
end

function OpenCode:toggle()
    local cur = require("proj").current()
    local root = cur and cur.root or "global"
    local cwd = cur and cur.root or vim.fn.getcwd()
    local reg = self:read_registry()
    local port = reg[root]
    local function ensure_attach(chosen)
        reg[root] = chosen
        self:write_registry(reg)
        self:start_server(chosen, cwd)
        vim.defer_fn(function() self:attach(chosen) end, 500)
    end
    if port then
        self:check_port(port, vim.schedule_wrap(function(is_open)
            if is_open then
                self:attach(port)
            else
                ensure_attach(self:get_free_port())
            end
        end))
    else
        ensure_attach(self:get_free_port())
    end
end

---@type proj.OpenCodeService
local service = OpenCode:new()
local M = { OpenCode = OpenCode }

function M.toggle() service:toggle() end

return M
