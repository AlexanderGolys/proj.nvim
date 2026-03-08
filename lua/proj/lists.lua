-- @@@proj.lists
-- ###nvim-plugin

local fn, api = vim.fn, vim.api
local utils = require("proj.utils")
local last_file = require("proj.last_file")

---@class proj.ListItem
---@field header string Heading text without `##`.
---@field body string[] Body lines under the heading.
---@field lnum integer 1-based line number where heading starts.

---@class proj.ListsService
---@field preview_win snacks.win? Active preview window handle.
---@field project_info_wins integer[] Active project info window handles.
---@field project_info_bufs integer[] Buffers used by project info windows.
local Lists = {}
Lists.__index = Lists

---@return proj.ListsService
function Lists:new()
    return setmetatable({
        project_info_wins = {},
        project_info_bufs = {},
    }, self)
end

---@private
---@return string
function Lists:global_dir()
    return fn.stdpath("data") .. "/proj_lists/"
end

---@private
---@param project_root string
---@return string[]
function Lists:markdown_files(project_root)
    return fn.glob(project_root .. "/*.md", false, true)
end

---@private
---@param projects proj.Project[]
---@return { text: string, root: string }[]
function Lists:project_items(projects)
    local items = {}
    for _, proj in ipairs(projects) do
        items[#items + 1] = { text = proj.name, root = proj.root }
    end
    return items
end

---@param filepath string
---@return proj.ListItem[]
function Lists:parse(filepath)
    local lines = utils.read_lines(filepath)
    if #lines == 0 and fn.filereadable(filepath) ~= 1 then
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
---@param root string
---@return string[]
local function collect_todo_headers(root)
  local path = root .. "/TODO.md"
  if fn.filereadable(path) ~= 1 then
    return { "  (TODO.md not found)" }
  end
  local headers = {}
  for _, line in ipairs(utils.read_lines(path)) do
    local header = line:match("^##%s+(.+)")
    if header then
      headers[#headers + 1] = "  - " .. header
    end
  end
  if #headers == 0 then
    headers[1] = "  (no TODO headers)"
  end
  return headers
end

---@private
---@param root string
---@param depth integer
---@return string[]
local function collect_file_tree(root, depth)
  local lines = {}
  local max_nodes = 300
  local count = 0

  local function walk(dir, lvl, indent)
    if lvl < 0 or count >= max_nodes then
      return
    end
    local ok, entries = pcall(fn.readdir, dir)
    if not ok then
      return
    end
    table.sort(entries)
    for _, name in ipairs(entries) do
      if name == "." or name == ".." or name:sub(1, 1) == "." then
        goto continue
      end
      if count >= max_nodes then
        lines[#lines + 1] = indent .. "... (+more)"
        return
      end
      local full = dir .. "/" .. name
      lines[#lines + 1] = indent .. name .. (fn.isdirectory(full) == 1 and "/" or "")
      count = count + 1
      if fn.isdirectory(full) == 1 then
        walk(full, lvl - 1, indent .. "  ")
      end
    ::continue::
    end
  end
  walk(root, depth, "  ")
  if #lines == 0 then
    lines[#lines + 1] = "  (no files)"
  end
  return lines
end

---@private
---@param lines string[]
---@param title string
---@param row integer
---@param col integer
---@param width integer
---@param height integer
---@return integer
---@return integer
local function open_info_window(lines, title, row, col, width, height, focus)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].bufhidden = "wipe"

  local win = api.nvim_open_win(buf, focus == true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    title = title,
    title_pos = "center",
    style = "minimal",
    focusable = focus == true,
  })
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "conceallevel", 2)
  return win, buf
end

local function close_project_info_windows(wins)
  for _, win in ipairs(wins) do
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
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
    utils.write_lines(filepath, out, "list file rewrite")
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
    content = utils.read_lines(dst)
    if #content > 0 then
        content[#content + 1] = ""
    end
    vim.list_extend(content, entry)
    if not utils.write_lines(dst, content, "destination list") then
        return
    end
    self:delete_item(src, item.header)
    utils.info("Moved '" .. item.header .. "' -> " .. fn.fnamemodify(dst, ":t"))
end

---@private
---@param project_root string
---@param exclude_filepath string
---@param callback fun(filepath: string)
function Lists:pick_target(project_root, exclude_filepath, callback)
    local items = {}
    for _, path in ipairs(self:markdown_files(project_root)) do
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
    if fn.filereadable(filepath) ~= 1 then
        if not utils.write_lines(filepath, {}, "list file") then
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
                utils.info("Deleted '" .. item._item.header .. "'")
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
        utils.warn("No projects registered")
        return
    end
    Snacks.picker({
        title = "Add " .. title .. " to project",
        items = self:project_items(projects),
        format = function(it) return { { it.text } } end,
        preview = function(ctx) ctx.preview:set_lines({ ctx.item.root }); return true end,
        confirm = function(picker, it)
            picker:close()
            if not it then return end
            local filepath = it.root .. "/" .. filename
            utils.input_nonempty("New " .. title .. " (" .. it.text .. ")", function(value)
                self:add(filepath, value)
            end)
        end,
    })
end

---@param projects proj.Project[]
function Lists:add_to_any_project_list(projects)
    if #projects == 0 then
        utils.warn("No projects registered")
        return
    end
    Snacks.picker({
        title = "Select project to add item to",
        items = self:project_items(projects),
        format = function(it) return { { it.text } } end,
        preview = function(ctx) ctx.preview:set_lines({ ctx.item.root }); return true end,
        confirm = function(picker, proj)
            picker:close()
            if not proj then return end
            local list_items = {}
            for _, path in ipairs(self:markdown_files(proj.root)) do
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
                    utils.input_nonempty("New " .. list_name .. " (" .. proj.text .. ")", function(value)
                        self:add(filepath, value)
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
    utils.input_nonempty("New " .. title, function(value)
        self:add(self:global_dir() .. filename, value)
    end)
end

---@param filepath string
---@param text string
function Lists:add(filepath, text)
    local lines = vim.split(text, "\n", { plain = true })
    if #lines == 0 or lines[1] == "" then
        return
    end
    local existing = utils.read_lines(filepath)
    if #existing > 0 then
        existing[#existing + 1] = ""
    end
    existing[#existing + 1] = "## " .. lines[1]
    for i = 2, #lines do
        existing[#existing + 1] = lines[i]
    end
    if utils.write_lines(filepath, existing, "list file") then
        utils.info("Added to " .. fn.fnamemodify(filepath, ":t"))
    else
        utils.warn("Failed to write to list file")
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
    for _, path in ipairs(self:markdown_files(project_root)) do
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
        utils.info("No non-empty lists found")
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

---@param project_root string
function Lists:toggle_project_info(project_root)
    self.project_info_wins = self.project_info_wins or {}
    if #self.project_info_wins > 0 then
        close_project_info_windows(self.project_info_wins)
        self.project_info_wins = {}
        self.project_info_bufs = {}
        return
    end

    local last_modified = last_file.get(project_root)
    local info_lines = {
        "# Project Info",
        "",
        "## Name",
        "  " .. fn.fnamemodify(project_root, ":t"),
        "## Root",
        "  " .. project_root,
        "## Last Modified File",
        "  " .. ((last_modified and last_modified ~= "" and last_modified) or "(none)"),
    }

    local file_tree_lines = { "# File Tree", "" }
    vim.list_extend(file_tree_lines, collect_file_tree(project_root, 3))

    local todo_lines = { "# Todos (headers only)", "" }
    vim.list_extend(todo_lines, collect_todo_headers(project_root))

    local width = math.max(36, math.floor(vim.o.columns * 0.34))
    local col = math.max(0, vim.o.columns - width - 2)
    local available_height = math.max(12, vim.o.lines - 6)
    local heights = {
        math.max(6, #info_lines + 2),
        math.max(8, #file_tree_lines + 2),
        math.max(6, #todo_lines + 2),
    }
    local minimum = { 4, 4, 4 }

    while heights[1] + heights[2] + heights[3] > available_height do
        if heights[2] > minimum[2] then
            heights[2] = heights[2] - 1
        elseif heights[3] > minimum[3] then
            heights[3] = heights[3] - 1
        elseif heights[1] > minimum[1] then
            heights[1] = heights[1] - 1
        else
            break
        end
    end

    local row = 1
    local win_rows = {
        row,
        row + heights[1],
        row + heights[1] + heights[2],
    }

    local close = function()
        close_project_info_windows(self.project_info_wins)
        self.project_info_wins = {}
        self.project_info_bufs = {}
    end

    local info_win, info_buf = open_info_window(info_lines, "Project", win_rows[1], col, width, heights[1], true)
    local tree_win, tree_buf = open_info_window(file_tree_lines, "File tree", win_rows[2], col, width, heights[2], false)
    local todo_win, todo_buf = open_info_window(todo_lines, "Todos", win_rows[3], col, width, heights[3], false)

    self.project_info_wins = { info_win, tree_win, todo_win }
    self.project_info_bufs = { info_buf, tree_buf, todo_buf }
    vim.keymap.set("n", "q", close, { buffer = info_buf, noremap = true, silent = true, nowait = true, desc = "Close project info" })
    vim.keymap.set("n", "<Esc>", close, { buffer = info_buf, noremap = true, silent = true, nowait = true, desc = "Close project info" })
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
---@param project_root string
function M.toggle_project_info(project_root) service:toggle_project_info(project_root) end

return M
