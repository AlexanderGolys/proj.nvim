-- @@@proj.lists
-- ###nvim-plugin

local fn, api = vim.fn, vim.api

---@class proj.ListItem
---@field header string Heading text without `##`.
---@field body string[] Body lines under the heading.
---@field lnum integer 1-based line number where heading starts.

---@class proj.ListsService
---@field preview_win snacks.win? Active preview window handle.
local Lists = {}
Lists.__index = Lists

---@return proj.ListsService
function Lists:new()
    return setmetatable({}, self)
end

---@private
---@return string
function Lists:global_dir()
    return fn.stdpath("data") .. "/proj_lists/"
end

---@param filepath string
---@return proj.ListItem[]
function Lists:parse(filepath)
    if fn.filereadable(filepath) ~= 1 then
        return {}
    end
    local ok, lines = pcall(fn.readfile, filepath)
    if not ok then
        return {}
    end
    local items, current, saw_heading = {}, nil, false
    for i, line in ipairs(lines) do
        local heading = line:match("^##%s+(.+)")
        if heading then
            saw_heading = true
            if current then
                items[#items + 1] = current
            end
            current = { header = heading, body = {}, lnum = i }
        elseif current then
            current.body[#current.body + 1] = line
        end
    end
    if current then
        items[#items + 1] = current
    end
    if saw_heading then
        return items
    end
    items = {}
    for i, line in ipairs(lines) do
        local text = vim.trim(line):gsub("^[-*+]%s+", "")
        if text ~= "" then
            items[#items + 1] = { header = text, body = {}, lnum = i }
        end
    end
    return items
end

---@private
---@param filepath string
---@param header string
function Lists:delete_item(filepath, header)
    local out, first = {}, true
    for _, item in ipairs(self:parse(filepath)) do
        if item.header ~= header then
            if not first then
                out[#out + 1] = ""
            end
            first = false
            out[#out + 1] = "## " .. item.header
            for _, line in ipairs(item.body) do
                out[#out + 1] = line
            end
        end
    end
    if not pcall(fn.writefile, out, filepath) then
        vim.notify("Failed to rewrite list file", vim.log.levels.WARN)
    end
end

---@private
---@param item proj.ListItem
---@param src string
---@param dst string
---@param annotation? string
function Lists:move_item(item, src, dst, annotation)
    local entry, content = { "## " .. item.header }, {}
    for _, line in ipairs(item.body) do
        entry[#entry + 1] = line
    end
    if annotation and annotation ~= "" then
        entry[#entry + 1] = annotation
    end
    if fn.filereadable(dst) == 1 then
        local ok, existing = pcall(fn.readfile, dst)
        if ok then
            content = existing
        end
    end
    if #content > 0 then
        content[#content + 1] = ""
    end
    vim.list_extend(content, entry)
    local dir = fn.fnamemodify(dst, ":h")
    if fn.isdirectory(dir) == 0 and not pcall(fn.mkdir, dir, "p") then
        vim.notify("Failed to create destination directory", vim.log.levels.WARN)
        return
    end
    if not pcall(fn.writefile, content, dst) then
        vim.notify("Failed to write to destination list", vim.log.levels.WARN)
        return
    end
    self:delete_item(src, item.header)
    vim.notify("Moved '" .. item.header .. "' -> " .. fn.fnamemodify(dst, ":t"), vim.log.levels.INFO)
end

---@private
---@param project_root string
---@param exclude_filepath string
---@param callback fun(filepath: string)
function Lists:pick_target(project_root, exclude_filepath, callback)
    local items = {}
    for _, path in ipairs(fn.glob(project_root .. "/*.md", false, true)) do
        if path ~= exclude_filepath then
            items[#items + 1] = { text = fn.fnamemodify(path, ":t"), path = path }
        end
    end
    Snacks.picker({
        title = "Move to list",
        items = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx) ctx.preview:set_lines({ ctx.item.path }); return true end,
        confirm = function(picker, it)
            picker:close()
            if it then
                callback(it.path)
                return
            end
            local typed = picker:filter().pattern
            if typed and typed ~= "" then
                callback(project_root .. "/" .. (typed:match("%.md$") and typed or typed .. ".md"))
            end
        end,
    })
end

---@private
---@param is_todo boolean
---@return string
function Lists:hints(is_todo)
    return table.concat(vim.tbl_filter(function(v) return v end, {
        "<CR> open / add if no results", "dd delete", "mm move to list", is_todo and "mt -> TOTEST" or nil,
    }), "  |  ")
end

---@param filepath string
---@param title string
---@param project_root? string
function Lists:pick(filepath, title, project_root)
    local dir = fn.fnamemodify(filepath, ":h")
    if fn.filereadable(filepath) ~= 1 then
        if fn.isdirectory(dir) == 0 and not pcall(fn.mkdir, dir, "p") then
            vim.notify("Failed to create list directory", vim.log.levels.WARN)
            return
        end
        if not pcall(fn.writefile, {}, filepath) then
            vim.notify("Failed to create list file", vim.log.levels.WARN)
            return
        end
    end
    local is_todo = fn.fnamemodify(filepath, ":t"):upper() == "TODO.MD"
    local totest = project_root and (project_root .. "/TOTEST.md") or nil
    local picker_items = {}
    for _, item in ipairs(self:parse(filepath)) do
        picker_items[#picker_items + 1] = {
            text = item.header,
            _item = item,
            file = filepath,
            pos = { item.lnum, 0 },
            preview = { text = table.concat(item.body, "\n"), ft = "markdown" },
        }
    end
    local function reopen() vim.schedule(function() self:pick(filepath, title, project_root) end) end
    Snacks.picker({
        title = title,
        footer = self:hints(is_todo),
        footer_pos = "center",
        items = picker_items,
        show_empty = true,
        confirm = function(picker, item)
            if item then
                picker:close()
                vim.cmd.edit(fn.fnameescape(item.file))
                api.nvim_win_set_cursor(0, { item.pos[1], 0 })
                return
            end
            local pattern = picker.input.filter.pattern
            picker:close()
            if pattern and pattern ~= "" then
                self:add(filepath, pattern)
                reopen()
            else
                vim.cmd.edit(fn.fnameescape(filepath))
            end
        end,
        actions = {
            list_delete = function(picker, item)
                if not item then return end
                picker:close()
                self:delete_item(filepath, item._item.header)
                vim.notify("Deleted '" .. item._item.header .. "'", vim.log.levels.INFO)
                reopen()
            end,
            list_move = function(picker, item)
                if not item or not project_root then return end
                picker:close()
                self:pick_target(project_root, filepath, function(dst) self:move_item(item._item, filepath, dst); reopen() end)
            end,
            list_move_totest = function(picker, item)
                if not item or not totest then return end
                picker:close()
                Snacks.input({ prompt = "Test annotation (optional)" }, function(note)
                    self:move_item(item._item, filepath, totest, note)
                    reopen()
                end)
            end,
        },
        win = { input = { keys = {
            ["dd"] = { "list_delete", mode = { "n" } },
            ["mm"] = { "list_move", mode = { "n" } },
            ["mt"] = { "list_move_totest", mode = { "n" } },
        } } },
    })
end

---@param projects proj.Project[]
---@param filename string
---@param title string
function Lists:pick_global(projects, filename, title)
    local items = {}
    for _, proj in ipairs(projects) do
        local filepath = proj.root .. "/" .. filename
        for _, item in ipairs(self:parse(filepath)) do
            items[#items + 1] = {
                text = proj.name .. ": " .. item.header,
                file = filepath,
                pos = { item.lnum, 0 },
                preview = { text = table.concat(item.body, "\n"), ft = "markdown" },
            }
        end
    end
    Snacks.picker({
        title = title .. " (all projects)",
        items = items,
        show_empty = true,
        confirm = function(picker, item)
            picker:close()
            if item then
                vim.cmd.edit(fn.fnameescape(item.file))
                api.nvim_win_set_cursor(0, { item.pos[1], 0 })
            end
        end,
    })
end

---@param projects proj.Project[]
---@param filename string
---@param title string
function Lists:add_to_project(projects, filename, title)
    if #projects == 0 then
        vim.notify("No projects registered", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, proj in ipairs(projects) do
        items[#items + 1] = { text = proj.name, root = proj.root }
    end
    Snacks.picker({
        title = "Add " .. title .. " to project",
        items = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx) ctx.preview:set_lines({ ctx.item.root }); return true end,
        confirm = function(picker, it)
            picker:close()
            if not it then return end
            local filepath = it.root .. "/" .. filename
            Snacks.input({ prompt = "New " .. title .. " (" .. it.text .. ")" }, function(value)
                if value and value ~= "" then self:add(filepath, value) end
            end)
        end,
    })
end

---@param projects proj.Project[]
function Lists:add_to_any_project_list(projects)
    if #projects == 0 then
        vim.notify("No projects registered", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, proj in ipairs(projects) do
        items[#items + 1] = { text = proj.name, root = proj.root }
    end
    Snacks.picker({
        title = "Select project to add item to",
        items = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx) ctx.preview:set_lines({ ctx.item.root }); return true end,
        confirm = function(picker, proj)
            picker:close()
            if not proj then return end
            local list_items = {}
            for _, path in ipairs(fn.glob(proj.root .. "/*.md", false, true)) do
                list_items[#list_items + 1] = { text = fn.fnamemodify(path, ":t"), path = path }
            end
            Snacks.picker({
                title = "Select list in " .. proj.text,
                items = list_items,
                format = function(it) return { { it.text } } end,
                preview = function(ctx) ctx.preview:set_lines({ ctx.item.path }); return true end,
                confirm = function(list_picker, item)
                    list_picker:close()
                    local filepath = item and item.path or nil
                    if not filepath then
                        local typed = list_picker:filter().pattern
                        if not typed or typed == "" then return end
                        filepath = proj.root .. "/" .. (typed:match("%.md$") and typed or typed .. ".md")
                    end
                    local list_name = fn.fnamemodify(filepath, ":r")
                    Snacks.input({ prompt = "New " .. list_name .. " (" .. proj.text .. ")" }, function(value)
                        if value and value ~= "" then self:add(filepath, value) end
                    end)
                end,
            })
        end,
    })
end

---@param filename string
---@param title string
function Lists:pick_own(filename, title)
    self:pick(self:global_dir() .. filename, title)
end

---@param filename string
---@param title string
function Lists:add_own(filename, title)
    Snacks.input({ prompt = "New " .. title }, function(value)
        if value and value ~= "" then
            self:add(self:global_dir() .. filename, value)
        end
    end)
end

---@param filepath string
---@param text string
function Lists:add(filepath, text)
    local lines = vim.split(text, "\n", { plain = true })
    if #lines == 0 or lines[1] == "" then
        return
    end
    local existing = {}
    if fn.filereadable(filepath) == 1 then
        local ok, content = pcall(fn.readfile, filepath)
        if ok then
            existing = content
        end
    end
    if #existing > 0 then
        existing[#existing + 1] = ""
    end
    existing[#existing + 1] = "## " .. lines[1]
    for i = 2, #lines do
        existing[#existing + 1] = lines[i]
    end
    local dir = fn.fnamemodify(filepath, ":h")
    if fn.isdirectory(dir) == 0 and not pcall(fn.mkdir, dir, "p") then
        vim.notify("Failed to create list directory", vim.log.levels.WARN)
        return
    end
    if pcall(fn.writefile, existing, filepath) then
        vim.notify("Added to " .. fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
    else
        vim.notify("Failed to write to list file", vim.log.levels.WARN)
    end
end

---@param project_root string
function Lists:toggle_preview(project_root)
    if self.preview_win and self.preview_win:valid() then
        self.preview_win:close()
        self.preview_win = nil
        return
    end
    local lines = {}
    for _, path in ipairs(fn.glob(project_root .. "/*.md", false, true)) do
        local items = self:parse(path)
        if #items > 0 then
            local filename = fn.fnamemodify(path, ":t")
            if #lines > 0 then
                vim.list_extend(lines, { "", "---", "" })
            end
            vim.list_extend(lines, { "# " .. filename, "" })
            for _, item in ipairs(items) do
                lines[#lines + 1] = "## " .. item.header
                vim.list_extend(lines, item.body)
            end
        end
    end
    if #lines == 0 then
        vim.notify("No non-empty lists found", vim.log.levels.INFO)
        return
    end
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype, vim.bo[buf].modifiable, vim.bo[buf].bufhidden = "markdown", false, "wipe"
    self.preview_win = Snacks.win({
        buf = buf,
        title = "Lists Preview",
        border = "rounded",
        width = 0.85,
        height = 0.85,
        keys = { q = "close", ["<Esc>"] = "close" },
    })
end

---@type proj.ListsService
local service = Lists:new()
local M = { Lists = Lists }

---@param filepath string
---@return proj.ListItem[]
function M.parse(filepath) return service:parse(filepath) end
---@param filepath string
---@param title string
---@param project_root? string
function M.pick(filepath, title, project_root) service:pick(filepath, title, project_root) end
---@param projects proj.Project[]
---@param filename string
---@param title string
function M.pick_global(projects, filename, title) service:pick_global(projects, filename, title) end
---@param projects proj.Project[]
---@param filename string
---@param title string
function M.add_to_project(projects, filename, title) service:add_to_project(projects, filename, title) end
---@param projects proj.Project[]
function M.add_to_any_project_list(projects) service:add_to_any_project_list(projects) end
---@param filename string
---@param title string
function M.pick_own(filename, title) service:pick_own(filename, title) end
---@param filename string
---@param title string
function M.add_own(filename, title) service:add_own(filename, title) end
---@param filepath string
---@param text string
function M.add(filepath, text) service:add(filepath, text) end
---@param project_root string
function M.toggle_preview(project_root) service:toggle_preview(project_root) end

return M
