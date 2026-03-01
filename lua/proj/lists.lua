local M = {}

-- @@@proj.lists
-- ###nvim-plugin

local fn = vim.fn
local api = vim.api

---@return string
local function global_dir()
    return fn.stdpath("data") .. "/proj_lists/"
end

---@class proj.ListItem
---@field header string
---@field body string[]
---@field lnum number

---@param filepath string
---@return proj.ListItem[]
function M.parse(filepath)
    if fn.filereadable(filepath) ~= 1 then
        return {}
    end
    local ok, lines = pcall(fn.readfile, filepath)
    if not ok then
        return {}
    end
    local items = {}
    local current = nil
    local saw_heading = false
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

    -- Backward-compat for legacy/plain list files without markdown headings.
    for i, line in ipairs(lines) do
        local text = vim.trim(line)
        if text ~= "" then
            text = text:gsub("^[-*+]%s+", "")
            items[#items + 1] = { header = text, body = {}, lnum = i }
        end
    end
    return items
end

-- Rewrite filepath keeping all items except the one with the given header.
---@param filepath string
---@param header string
local function delete_item(filepath, header)
    local items = M.parse(filepath)
    local lines = {}
    local first = true
    for _, item in ipairs(items) do
        if item.header ~= header then
            if not first then
                lines[#lines + 1] = ""
            end
            first = false
            lines[#lines + 1] = "## " .. item.header
            for _, bl in ipairs(item.body) do
                lines[#lines + 1] = bl
            end
        end
    end
    local ok = pcall(fn.writefile, lines, filepath)
    if not ok then
        vim.notify("Failed to rewrite list file", vim.log.levels.WARN)
    end
end

-- Append a parsed item to a file and delete it from the source.
---@param item proj.ListItem
---@param src_filepath string
---@param dst_filepath string
---@param annotation? string  extra line appended below the body
local function move_item(item, src_filepath, dst_filepath, annotation)
    local entry = {}
    entry[#entry + 1] = "## " .. item.header
    for _, bl in ipairs(item.body) do
        entry[#entry + 1] = bl
    end
    if annotation and annotation ~= "" then
        entry[#entry + 1] = annotation
    end
    local dst = {}
    if fn.filereadable(dst_filepath) == 1 then
        local ok, content = pcall(fn.readfile, dst_filepath)
        if ok then dst = content end
    end
    if #dst > 0 then
        dst[#dst + 1] = ""
    end
    for _, l in ipairs(entry) do
        dst[#dst + 1] = l
    end
    local dir = fn.fnamemodify(dst_filepath, ":h")
    if fn.isdirectory(dir) == 0 then
        local ok = pcall(fn.mkdir, dir, "p")
        if not ok then
            vim.notify("Failed to create destination directory", vim.log.levels.WARN)
            return
        end
    end
    local ok_write = pcall(fn.writefile, dst, dst_filepath)
    if not ok_write then
        vim.notify("Failed to write to destination list", vim.log.levels.WARN)
        return
    end
    delete_item(src_filepath, item.header)
    vim.notify(
        "Moved '" .. item.header .. "' → " .. fn.fnamemodify(dst_filepath, ":t"),
        vim.log.levels.INFO
    )
end

-- Pick a target list file. Existing .md files are listed; typing a new name
-- creates that file on confirm.
---@param project_root string
---@param exclude_filepath string
---@param callback fun(filepath: string)
local function pick_target(project_root, exclude_filepath, callback)
    local candidates = fn.glob(project_root .. "/*.md", false, true)
    local items = {}
    for _, path in ipairs(candidates) do
        if path ~= exclude_filepath then
            items[#items + 1] = { text = fn.fnamemodify(path, ":t"), path = path }
        end
    end
    Snacks.picker({
        title = "Move to list",
        items = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx)
            ctx.preview:set_lines({ ctx.item.path })
            return true
        end,
        confirm = function(picker, it)
            picker:close()
            if it then
                callback(it.path)
            else
                -- no match selected: treat the typed pattern as a new filename
                local typed = picker:filter().pattern
                if typed and typed ~= "" then
                    local name = typed:match("%.md$") and typed or (typed .. ".md")
                    callback(project_root .. "/" .. name)
                end
            end
        end,
    })
end

---@param is_todo boolean
---@return string
local function hints(is_todo)
    local parts = { "<CR> open / add if no results", "dd delete", "mm move to list" }
    if is_todo then
        parts[#parts + 1] = "mt → TOTEST"
    end
    return table.concat(parts, "  │  ")
end

-- Open a picker for a list file. Creates the file if it does not exist.
-- Shows an empty picker when the file has no ## headings.
---@param filepath string
---@param title string
---@param project_root? string  needed for move actions; nil disables them
function M.pick(filepath, title, project_root)
    if fn.filereadable(filepath) ~= 1 then
        local dir = fn.fnamemodify(filepath, ":h")
        if fn.isdirectory(dir) == 0 then
            local ok_mkdir = pcall(fn.mkdir, dir, "p")
            if not ok_mkdir then
                vim.notify("Failed to create list directory", vim.log.levels.WARN)
                return
            end
        end
        local ok_create = pcall(fn.writefile, {}, filepath)
        if not ok_create then
            vim.notify("Failed to create list file", vim.log.levels.WARN)
            return
        end
    end

    local is_todo = fn.fnamemodify(filepath, ":t"):upper() == "TODO.MD"
    local totest_path = project_root and (project_root .. "/TOTEST.md") or nil

    local picker_items = {}
    for _, item in ipairs(M.parse(filepath)) do
        picker_items[#picker_items + 1] = {
            text    = item.header,
            _item   = item,
            preview = {
                text = table.concat(item.body, "\n"),
                ft   = "markdown",
            },
            file = filepath,
            pos  = { item.lnum, 0 },
        }
    end

    local function reopen()
        vim.schedule(function()
            M.pick(filepath, title, project_root)
        end)
    end

    Snacks.picker({
        title      = title,
        footer     = hints(is_todo),
        footer_pos = "center",
        items      = picker_items,
        show_empty = true,

        confirm = function(picker, item)
            if item then
                picker:close()
                vim.cmd.edit(fn.fnameescape(item.file))
                api.nvim_win_set_cursor(0, { item.pos[1], 0 })
            else
                local pattern = picker.input.filter.pattern
                if pattern and pattern ~= "" then
                    picker:close()
                    M.add(filepath, pattern)
                    reopen()
                else
                    picker:close()
                    vim.cmd.edit(fn.fnameescape(filepath))
                end
            end
        end,

        actions = {
            list_delete = function(picker, item)
                if not item then return end
                picker:close()
                delete_item(filepath, item._item.header)
                vim.notify("Deleted '" .. item._item.header .. "'", vim.log.levels.INFO)
                reopen()
            end,

            list_move = function(picker, item)
                if not item or not project_root then return end
                picker:close()
                pick_target(project_root, filepath, function(dst)
                    move_item(item._item, filepath, dst)
                    reopen()
                end)
            end,

            list_move_totest = function(picker, item)
                if not item or not totest_path then return end
                picker:close()
                Snacks.input({ prompt = "Test annotation (optional)" }, function(annotation)
                    move_item(item._item, filepath, totest_path, annotation)
                    reopen()
                end)
            end,
        },

        win = {
            input = {
                keys = {
                    ["dd"] = { "list_delete",     mode = { "n" } },
                    ["mm"] = { "list_move",        mode = { "n" } },
                    ["mt"] = { "list_move_totest", mode = { "n" } },
                },
            },
        },
    })
end

-- Open a combined picker across all projects for a given filename.
-- Always shows a picker; items from projects without the file are absent.
---@param projects proj.Project[]
---@param filename string
---@param title string
function M.pick_global(projects, filename, title)
    local picker_items = {}
    for _, proj in ipairs(projects) do
        local filepath = proj.root .. "/" .. filename
        for _, item in ipairs(M.parse(filepath)) do
            picker_items[#picker_items + 1] = {
                text    = proj.name .. ": " .. item.header,
                _item   = item,
                _proj   = proj,
                preview = {
                    text = table.concat(item.body, "\n"),
                    ft   = "markdown",
                },
                file = filepath,
                pos  = { item.lnum, 0 },
            }
        end
    end
    Snacks.picker({
        title = title .. " (all projects)",
        items = picker_items,
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

-- Pick a project then prompt for a new item to add to filename in that project.
---@param projects proj.Project[]
---@param filename string
---@param title string
function M.add_to_project(projects, filename, title)
    if #projects == 0 then
        vim.notify("No projects registered", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, proj in ipairs(projects) do
        items[#items + 1] = { text = proj.name, root = proj.root }
    end
    Snacks.picker({
        title  = "Add " .. title .. " to project",
        items  = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx)
            ctx.preview:set_lines({ ctx.item.root })
            return true
        end,
        confirm = function(picker, it)
            picker:close()
            if not it then return end
            local filepath = it.root .. "/" .. filename
            Snacks.input({ prompt = "New " .. title .. " (" .. it.text .. ")" }, function(value)
                if value and value ~= "" then
                    M.add(filepath, value)
                end
            end)
        end,
    })
end

-- Pick a project, then pick a list in that project, then add an item.
---@param projects proj.Project[]
function M.add_to_any_project_list(projects)
    if #projects == 0 then
        vim.notify("No projects registered", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, proj in ipairs(projects) do
        items[#items + 1] = { text = proj.name, root = proj.root }
    end
    Snacks.picker({
        title  = "Select project to add item to",
        items  = items,
        format = function(it) return { { it.text } } end,
        preview = function(ctx)
            ctx.preview:set_lines({ ctx.item.root })
            return true
        end,
        confirm = function(picker, it)
            picker:close()
            if not it then return end
            
            local candidates = fn.glob(it.root .. "/*.md", false, true)
            local list_items = {}
            for _, path in ipairs(candidates) do
                list_items[#list_items + 1] = { text = fn.fnamemodify(path, ":t"), path = path }
            end
            
            Snacks.picker({
                title = "Select list in " .. it.text,
                items = list_items,
                format = function(list_it) return { { list_it.text } } end,
                preview = function(ctx)
                    ctx.preview:set_lines({ ctx.item.path })
                    return true
                end,
                confirm = function(list_picker, list_it)
                    list_picker:close()
                    local filepath
                    if list_it then
                        filepath = list_it.path
                    else
                        local typed = list_picker:filter().pattern
                        if typed and typed ~= "" then
                            local name = typed:match("%.md$") and typed or (typed .. ".md")
                            filepath = it.root .. "/" .. name
                        else
                            return
                        end
                    end
                    local list_name = fn.fnamemodify(filepath, ":r")
                    Snacks.input({ prompt = "New " .. list_name .. " (" .. it.text .. ")" }, function(value)
                        if value and value ~= "" then
                            M.add(filepath, value)
                        end
                    end)
                end,
            })
        end,
    })
end

-- Open a picker for a project-independent global list (stored in global_dir).
---@param filename string
---@param title string
function M.pick_own(filename, title)
    M.pick(global_dir() .. filename, title)
end

-- Add an item to a project-independent global list. Prompts for text only.
---@param filename string
---@param title string
function M.add_own(filename, title)
    Snacks.input({ prompt = "New " .. title }, function(value)
        if value and value ~= "" then
            M.add(global_dir() .. filename, value)
        end
    end)
end

---@param filepath string
---@param text string
function M.add(filepath, text)
    local lines = vim.split(text, "\n", { plain = true })
    if #lines == 0 or lines[1] == "" then
        return
    end
    local existing = {}
    if fn.filereadable(filepath) == 1 then
        local ok, content = pcall(fn.readfile, filepath)
        if ok then existing = content end
    end
    if #existing > 0 then
        existing[#existing + 1] = ""
    end
    existing[#existing + 1] = "## " .. lines[1]
    for i = 2, #lines do
        existing[#existing + 1] = lines[i]
    end
    local dir = fn.fnamemodify(filepath, ":h")
    if fn.isdirectory(dir) == 0 then
        local ok = pcall(fn.mkdir, dir, "p")
        if not ok then
            vim.notify("Failed to create list directory", vim.log.levels.WARN)
            return
        end
    end
    local ok_write = pcall(fn.writefile, existing, filepath)
    if ok_write then
        vim.notify("Added to " .. fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
    else
        vim.notify("Failed to write to list file", vim.log.levels.WARN)
    end
end

---@param project_root string
function M.toggle_preview(project_root)
    if M._preview_win and M._preview_win:valid() then
        M._preview_win:close()
        M._preview_win = nil
        return
    end

    local candidates = fn.glob(project_root .. "/*.md", false, true)
    local lines = {}
    for _, path in ipairs(candidates) do
        local items = M.parse(path)
        if #items > 0 then
            local filename = fn.fnamemodify(path, ":t")
            if #lines > 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "---"
                lines[#lines + 1] = ""
            end
            lines[#lines + 1] = "# " .. filename
            lines[#lines + 1] = ""
            for _, item in ipairs(items) do
                lines[#lines + 1] = "## " .. item.header
                for _, bl in ipairs(item.body) do
                    lines[#lines + 1] = bl
                end
            end
        end
    end

    if #lines == 0 then
        vim.notify("No non-empty lists found", vim.log.levels.INFO)
        return
    end

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    M._preview_win = Snacks.win({
        buf = buf,
        title = "Lists Preview",
        border = "rounded",
        width = 0.8,
        height = 0.8,
        keys = { q = "close", ["<Esc>"] = "close" },
        on_close = function()
            M._preview_win = nil
        end
    })
end

return M
