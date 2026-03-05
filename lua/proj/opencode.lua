local M = {}

-- @@@proj.opencode
-- ###nvim-plugin

local project = require("proj.project")

local REGISTRY_FILE = vim.fn.stdpath("data") .. "/proj_opencode.json"

---@return table<string, integer>
local function read_registry()
    local f = io.open(REGISTRY_FILE, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    if content == "" then return {} end
    local ok, parsed = pcall(vim.json.decode, content)
    return ok and parsed or {}
end

---@param data table<string, integer>
local function write_registry(data)
    local f = io.open(REGISTRY_FILE, "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

---@return integer
local function get_free_port()
    local server = vim.uv.new_tcp()
    server:bind("127.0.0.1", 0)
    local port = server:getsockname().port
    server:close()
    return port
end

---@param port integer
---@param cb fun(is_open: boolean)
local function check_port(port, cb)
    local client = vim.uv.new_tcp()
    client:connect("127.0.0.1", port, function(err)
        client:close()
        cb(err == nil)
    end)
end

---@param port integer
---@param cwd string
local function start_server(port, cwd)
    -- Start opencode in headless server mode
    local cmd = { "opencode", "serve", "--port", tostring(port) }
    vim.fn.jobstart(cmd, {
        cwd = cwd,
        detach = true,
    })
end

function M.toggle()
    local cur = require("proj.init").current()
    local root = cur and cur.root or "global"
    local cwd = cur and cur.root or vim.fn.getcwd()
    
    local reg = read_registry()
    local port = reg[root]

    local function run_attach(p)
        local provider = require("opencode.config").provider
        if provider then
            provider.cmd = "opencode attach http://127.0.0.1:" .. p .. " -c"
            require("opencode").toggle()
        else
            vim.notify("No opencode provider found", vim.log.levels.ERROR)
        end
    end

    if port then
        check_port(port, vim.schedule_wrap(function(is_open)
            if is_open then
                run_attach(port)
            else
                -- Port is invalid, server died
                local new_port = get_free_port()
                reg[root] = new_port
                write_registry(reg)
                start_server(new_port, cwd)
                -- Defer to let the server bind the port
                vim.defer_fn(function()
                    run_attach(new_port)
                end, 500)
            end
        end))
    else
        local new_port = get_free_port()
        reg[root] = new_port
        write_registry(reg)
        start_server(new_port, cwd)
        vim.defer_fn(function()
            run_attach(new_port)
        end, 500)
    end
end

return M
