local M = {}

-- @@@proj.issues
-- ###nvim-plugin

local fn = vim.fn
local api = vim.api

local SUBTYPE_ICONS = {
    notification = "󰵙 ",
    ["input-error"] = " ",
    traceback = "󰆆 ",
    silent = "󰈉 ",
}

local SEVERITY_HL = {
    ASAP     = "DiagnosticError",
    CAN_WAIT = "DiagnosticHint",
}

---@param root string  git root of the project
---@param kind "bugs"|"todos"
---@return string
local function issues_path(root, kind)
    return root .. "/.issues/" .. kind .. ".json"
end

---@param path string
---@return table[]
local function read_json(path)
    if fn.filereadable(path) ~= 1 then return {} end
    local ok, raw = pcall(fn.readfile, path)
    if not ok then return {} end
    local content = table.concat(raw, "\n")
    local decoded_ok, data = pcall(vim.json.decode, content)
    if not decoded_ok or type(data) ~= "table" then return {} end
    return data
end

---@param path string
---@param data table[]
local function write_json(path, data)
    local dir = fn.fnamemodify(path, ":h")
    if fn.isdirectory(dir) == 0 then
        fn.mkdir(dir, "p")
    end
    local encoded = vim.json.encode(data)
    -- pretty-print via python (always available on arch)
    local result = vim.system({ "python3", "-c",
        "import sys,json; print(json.dumps(json.loads(sys.stdin.read()), indent=2))" },
        { stdin = encoded }):wait()
    local lines = vim.split(result.code == 0 and result.stdout or encoded, "\n", { plain = true })
    fn.writefile(lines, path)
end

---@param entry table
---@return string
local function entry_label(entry)
    local icon = SUBTYPE_ICONS[entry.subtype] or "  "
    local sev  = entry.severity and ("[" .. entry.severity .. "] ") or ""
    local proj = entry.project and ("{" .. entry.project .. "} ") or ""
    return icon .. sev .. proj .. (entry.title or entry.id or "?")
end

---@param entry table
---@return string
local function entry_preview(entry)
    local lines = {}
    lines[#lines+1] = "# " .. (entry.title or "Untitled")
    lines[#lines+1] = ""
    if entry.subtype  then lines[#lines+1] = "Subtype:  " .. entry.subtype end
    if entry.severity then lines[#lines+1] = "Severity: " .. entry.severity end
    if entry.project  then lines[#lines+1] = "Project:  " .. entry.project end
    if entry.context  then lines[#lines+1] = "Context:  " .. entry.context end
    if entry.file     then lines[#lines+1] = "File:     " .. entry.file end
    if entry.status   then lines[#lines+1] = "Status:   " .. entry.status end
    if entry.created  then lines[#lines+1] = "Created:  " .. entry.created end
    if #lines > 1 then lines[#lines+1] = "" end
    if entry.description and entry.description ~= "" then
        lines[#lines+1] = "## Description"
        lines[#lines+1] = ""
        for _, l in ipairs(vim.split(entry.description, "\n", { plain = true })) do
            lines[#lines+1] = l
        end
    end
    if entry.image_path then
        lines[#lines+1] = ""
        lines[#lines+1] = "Screenshot: " .. entry.image_path
    end
    return table.concat(lines, "\n")
end

---Delete entry by id from path.
---@param path string
---@param id string
local function delete_entry(path, id)
    local data = read_json(path)
    local filtered = vim.tbl_filter(function(e) return e.id ~= id end, data)
    write_json(path, filtered)
end

---Mark entry status.
---@param path string
---@param id string
---@param status string
local function set_status(path, id, status)
    local data = read_json(path)
    for _, e in ipairs(data) do
        if e.id == id then e.status = status end
    end
    write_json(path, data)
end

-- Open a Snacks picker for a single .issues/bugs.json or todos.json file.
---@param path string
---@param title string
---@param project_root? string  for re-open after mutations
function M.pick(path, title, project_root)
    local data = read_json(path)
    local items = {}
    for _, entry in ipairs(data) do
        if entry.status ~= "resolved" then
            items[#items+1] = {
                text    = entry_label(entry),
                _entry  = entry,
                _path   = path,
                preview = { text = entry_preview(entry), ft = "markdown" },
            }
        end
    end

    local function reopen()
        vim.schedule(function() M.pick(path, title, project_root) end)
    end

    local hints = "<CR> open file  │  dd delete  │  mr mark resolved  │  mi mark in-progress"

    Snacks.picker({
        title      = title,
        footer     = hints,
        footer_pos = "center",
        items      = items,
        show_empty = true,

        confirm = function(picker, item)
            picker:close()
            if item and item._entry.file then
                local fpath = project_root
                    and (project_root .. "/" .. item._entry.file)
                    or item._entry.file
                if fn.filereadable(fpath) == 1 then
                    vim.cmd.edit(fn.fnameescape(fpath))
                else
                    vim.notify("File not found: " .. fpath, vim.log.levels.WARN)
                end
            end
        end,

        actions = {
            issue_delete = function(picker, item)
                if not item then return end
                picker:close()
                delete_entry(item._path, item._entry.id)
                vim.notify("Deleted " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
            issue_resolved = function(picker, item)
                if not item then return end
                picker:close()
                set_status(item._path, item._entry.id, "resolved")
                vim.notify("Marked resolved: " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
            issue_in_progress = function(picker, item)
                if not item then return end
                picker:close()
                set_status(item._path, item._entry.id, "in-progress")
                vim.notify("Marked in-progress: " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
        },

        win = {
            input = {
                keys = {
                    ["dd"] = { "issue_delete",      mode = { "n" } },
                    ["mr"] = { "issue_resolved",    mode = { "n" } },
                    ["mi"] = { "issue_in_progress", mode = { "n" } },
                },
            },
        },
    })
end

-- Global picker across all projects — merges bugs or todos from all roots.
---@param projects proj.Project[]
---@param kind "bugs"|"todos"
---@param title string
function M.pick_global(projects, kind, title)
    local items = {}
    for _, proj in ipairs(projects) do
        local path = issues_path(proj.root, kind)
        for _, entry in ipairs(read_json(path)) do
            if entry.status ~= "resolved" then
                local label = "{" .. proj.name .. "} " .. entry_label(entry)
                items[#items+1] = {
                    text    = label,
                    _entry  = entry,
                    _path   = path,
                    _root   = proj.root,
                    preview = { text = entry_preview(entry), ft = "markdown" },
                }
            end
        end
    end

    Snacks.picker({
        title      = title .. " (all projects)",
        items      = items,
        show_empty = true,
        confirm = function(picker, item)
            picker:close()
            if item and item._entry.file then
                local fpath = item._root .. "/" .. item._entry.file
                if fn.filereadable(fpath) == 1 then
                    vim.cmd.edit(fn.fnameescape(fpath))
                else
                    vim.notify("File not found: " .. fpath, vim.log.levels.WARN)
                end
            end
        end,
    })
end

---@param root string
---@param kind "bugs"|"todos"
---@return string
function M.path(root, kind)
    return issues_path(root, kind)
end

return M
