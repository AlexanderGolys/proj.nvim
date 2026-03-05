-- @@@proj.issues
-- ###nvim-plugin

local fn = vim.fn

local SUBTYPE_ICONS = {
    notification = "󰵙 ",
    ["input-error"] = " ",
    traceback = "󰆆 ",
    silent = "󰈉 ",
}

---@class proj.IssuesService
local Issues = {}
Issues.__index = Issues

---@return proj.IssuesService
function Issues:new()
    return setmetatable({}, self)
end

---@private
---@param root string
---@param kind "bugs"|"todos"
---@return string
function Issues:issues_path(root, kind)
    return root .. "/.issues/" .. kind .. ".json"
end

---@private
---@param path string
---@return table[]
function Issues:read_json(path)
    if fn.filereadable(path) ~= 1 then return {} end
    local ok, raw = pcall(fn.readfile, path)
    if not ok then return {} end
    local ok_decode, data = pcall(vim.json.decode, table.concat(raw, "\n"))
    return ok_decode and type(data) == "table" and data or {}
end

---@private
---@param path string
---@param data table[]
function Issues:write_json(path, data)
    local dir = fn.fnamemodify(path, ":h")
    if fn.isdirectory(dir) == 0 then
        pcall(fn.mkdir, dir, "p")
    end
    local encoded = vim.json.encode(data)
    local result = vim.system({ "python3", "-c", "import sys,json; print(json.dumps(json.loads(sys.stdin.read()), indent=2))" }, { stdin = encoded }):wait()
    fn.writefile(vim.split(result.code == 0 and result.stdout or encoded, "\n", { plain = true }), path)
end

---@private
---@param entry table
---@return string
function Issues:entry_label(entry)
    local icon = SUBTYPE_ICONS[entry.subtype] or "  "
    local sev = entry.severity and ("[" .. entry.severity .. "] ") or ""
    local proj = entry.project and ("{" .. entry.project .. "} ") or ""
    return icon .. sev .. proj .. (entry.title or entry.id or "?")
end

---@private
---@param entry table
---@return string
function Issues:entry_preview(entry)
    local lines = { "# " .. (entry.title or "Untitled"), "" }
    for _, pair in ipairs({
        { "Subtype", entry.subtype }, { "Severity", entry.severity }, { "Project", entry.project },
        { "Context", entry.context }, { "File", entry.file }, { "Status", entry.status }, { "Created", entry.created },
    }) do
        if pair[2] then lines[#lines + 1] = pair[1] .. ": " .. pair[2] end
    end
    if entry.description and entry.description ~= "" then
        vim.list_extend(lines, { "", "## Description", "" })
        vim.list_extend(lines, vim.split(entry.description, "\n", { plain = true }))
    end
    if entry.image_path then
        vim.list_extend(lines, { "", "Screenshot: " .. entry.image_path })
    end
    return table.concat(lines, "\n")
end

---@private
---@param path string
---@param id string
function Issues:delete_entry(path, id)
    self:write_json(path, vim.tbl_filter(function(e) return e.id ~= id end, self:read_json(path)))
end

---@private
---@param path string
---@param id string
---@param status string
function Issues:set_status(path, id, status)
    local data = self:read_json(path)
    for _, e in ipairs(data) do
        if e.id == id then
            e.status = status
        end
    end
    self:write_json(path, data)
end

---@param path string Absolute path to an issues json file.
---@param title string Picker title.
---@param project_root? string Root used to resolve relative file paths.
function Issues:pick(path, title, project_root)
    local items = {}
    for _, entry in ipairs(self:read_json(path)) do
        if entry.status ~= "resolved" then
            items[#items + 1] = {
                text = self:entry_label(entry),
                _entry = entry,
                _path = path,
                preview = { text = self:entry_preview(entry), ft = "markdown" },
            }
        end
    end
    local function reopen() vim.schedule(function() self:pick(path, title, project_root) end) end
    Snacks.picker({
        title = title,
        footer = "<CR> open file  |  dd delete  |  mr mark resolved  |  mi mark in-progress",
        footer_pos = "center",
        items = items,
        show_empty = true,
        confirm = function(picker, item)
            picker:close()
            if not item or not item._entry.file then return end
            local fpath = project_root and (project_root .. "/" .. item._entry.file) or item._entry.file
            if fn.filereadable(fpath) == 1 then
                vim.cmd.edit(fn.fnameescape(fpath))
            else
                vim.notify("File not found: " .. fpath, vim.log.levels.WARN)
            end
        end,
        actions = {
            issue_delete = function(picker, item)
                if not item then return end
                picker:close()
                self:delete_entry(item._path, item._entry.id)
                vim.notify("Deleted " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
            issue_resolved = function(picker, item)
                if not item then return end
                picker:close()
                self:set_status(item._path, item._entry.id, "resolved")
                vim.notify("Marked resolved: " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
            issue_in_progress = function(picker, item)
                if not item then return end
                picker:close()
                self:set_status(item._path, item._entry.id, "in-progress")
                vim.notify("Marked in-progress: " .. item._entry.id, vim.log.levels.INFO)
                reopen()
            end,
        },
        win = { input = { keys = {
            ["dd"] = { "issue_delete", mode = { "n" } },
            ["mr"] = { "issue_resolved", mode = { "n" } },
            ["mi"] = { "issue_in_progress", mode = { "n" } },
        } } },
    })
end

---@param projects proj.Project[]
---@param kind "bugs"|"todos"
---@param title string
function Issues:pick_global(projects, kind, title)
    local items = {}
    for _, proj in ipairs(projects) do
        local path = self:issues_path(proj.root, kind)
        for _, entry in ipairs(self:read_json(path)) do
            if entry.status ~= "resolved" then
                items[#items + 1] = {
                    text = "{" .. proj.name .. "} " .. self:entry_label(entry),
                    _entry = entry,
                    _root = proj.root,
                    preview = { text = self:entry_preview(entry), ft = "markdown" },
                }
            end
        end
    end
    Snacks.picker({
        title = title .. " (all projects)",
        items = items,
        show_empty = true,
        confirm = function(picker, item)
            picker:close()
            if not item or not item._entry.file then return end
            local fpath = item._root .. "/" .. item._entry.file
            if fn.filereadable(fpath) == 1 then
                vim.cmd.edit(fn.fnameescape(fpath))
            else
                vim.notify("File not found: " .. fpath, vim.log.levels.WARN)
            end
        end,
    })
end

---@param root string
---@param kind "bugs"|"todos"
---@return string
function Issues:path(root, kind)
    return self:issues_path(root, kind)
end

---@type proj.IssuesService
local service = Issues:new()
local M = { Issues = Issues }

---@param path string
---@param title string
---@param project_root? string
function M.pick(path, title, project_root) service:pick(path, title, project_root) end
---@param projects proj.Project[]
---@param kind "bugs"|"todos"
---@param title string
function M.pick_global(projects, kind, title) service:pick_global(projects, kind, title) end
---@param root string
---@param kind "bugs"|"todos"
---@return string
function M.path(root, kind) return service:path(root, kind) end

return M
