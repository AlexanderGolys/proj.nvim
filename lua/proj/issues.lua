-- @@@proj.issues
-- ###nvim-plugin

local fn = vim.fn
local utils = require("proj.utils")

---@alias proj.IssueKind "bugs"|"todos"
---@alias proj.IssueStatus "open"|"in-progress"|"resolved"
---@alias proj.IssueSubtype "notification"|"input-error"|"traceback"|"silent"|string

---@class proj.IssueEntry
---@field id string
---@field title? string
---@field subtype? proj.IssueSubtype
---@field severity? string
---@field project? string
---@field context? string
---@field file? string
---@field status? proj.IssueStatus
---@field created? string
---@field description? string
---@field image_path? string

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
---@param kind proj.IssueKind
---@return string
function Issues:issues_path(root, kind)
    return root .. "/.issues/" .. kind .. ".json"
end

---@private
---@param path string
---@return proj.IssueEntry[]
function Issues:read_json(path)
    return utils.read_json(path)
end

---@private
---@param path string
---@param data proj.IssueEntry[]
function Issues:write_json(path, data)
    utils.write_json(path, data, "issues file")
end

---@private
---@param entry proj.IssueEntry
---@return string
function Issues:entry_label(entry)
    local icon = SUBTYPE_ICONS[entry.subtype] or "  "
    local sev = entry.severity and ("[" .. entry.severity .. "] ") or ""
    local proj = entry.project and ("{" .. entry.project .. "} ") or ""
    return icon .. sev .. proj .. (entry.title or entry.id or "?")
end

---@private
---@param entry proj.IssueEntry
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
---@param status proj.IssueStatus
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
                utils.warn("File not found: " .. fpath)
            end
        end,
        actions = {
            issue_delete = function(picker, item)
                if not item then return end
                picker:close()
                self:delete_entry(item._path, item._entry.id)
                utils.info("Deleted " .. item._entry.id)
                reopen()
            end,
            issue_resolved = function(picker, item)
                if not item then return end
                picker:close()
                self:set_status(item._path, item._entry.id, "resolved")
                utils.info("Marked resolved: " .. item._entry.id)
                reopen()
            end,
            issue_in_progress = function(picker, item)
                if not item then return end
                picker:close()
                self:set_status(item._path, item._entry.id, "in-progress")
                utils.info("Marked in-progress: " .. item._entry.id)
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
---@param kind proj.IssueKind
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
                utils.warn("File not found: " .. fpath)
            end
        end,
    })
end

---@param root string
---@param kind proj.IssueKind
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
---@param kind proj.IssueKind
---@param title string
function M.pick_global(projects, kind, title) service:pick_global(projects, kind, title) end
---@param root string
---@param kind proj.IssueKind
---@return string
function M.path(root, kind) return service:path(root, kind) end

return M
