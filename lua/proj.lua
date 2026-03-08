local project = require("proj.project")
local last_file = require("proj.last_file")
local lists = require("proj.lists")
local issues = require("proj.issues")
local utils = require("proj.utils")
local config = require("proj.config")

-- @@@proj
-- @##proj
--
-- /@@proj.project
-- /@@proj.last_file
-- /@@proj.lists
-- /@@proj.issues
-- /@@proj.utils
-- /@@proj.config

---@class proj.ProjectManager
---@field cfg proj.Config
---@field tab_projects table<integer, proj.Project>
local ProjectManager = {}
ProjectManager.__index = ProjectManager

---@return proj.ProjectManager
function ProjectManager:new()
  return setmetatable({ cfg = vim.deepcopy(config.get()), tab_projects = {} }, self)
end

---@private
---@param session_file string
---@return string
function ProjectManager:session_state_path(session_file)
  local normalized = vim.fn.fnamemodify(session_file, ":p")
  local key = normalized:gsub("[^%w_.-]", "%%")
  return vim.fn.stdpath("data") .. "/proj_sessions/" .. key .. ".json"
end

---@private
---@param args? table
---@return string?
function ProjectManager:resolve_session_file(args)
  local file = args and args.file or vim.v.this_session
  if type(file) ~= "string" or file == "" then
    return nil
  end
  return vim.fn.fnamemodify(file, ":p")
end

---@private
---@param session_file string
function ProjectManager:save_session_state(session_file)
  local by_tabnr = {}
  for idx, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local proj = self.tab_projects[tab]
    if proj and type(proj.root) == "string" and proj.root ~= "" then
      by_tabnr[tostring(idx)] = proj.root
    end
  end
  utils.write_json(self:session_state_path(session_file), by_tabnr, "proj session state")
end

---@private
---@param session_file string
function ProjectManager:load_session_state(session_file)
  local state = utils.read_json(self:session_state_path(session_file))
  if vim.tbl_isempty(state) then
    return
  end

  local by_root = {}
  for _, proj in ipairs(project.read()) do
    by_root[proj.root] = proj
  end

  self.tab_projects = {}
  for idx, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local root = state[tostring(idx)]
    local proj = type(root) == "string" and by_root[root] or nil
    if proj then
      self.tab_projects[tab] = proj
    end
  end
end

---@param tabpage? integer
---@return proj.Project?
function ProjectManager:current(tabpage)
  return self.tab_projects[tabpage or vim.api.nvim_get_current_tabpage()]
end

---@private
---@return string
function ProjectManager:current_buf_dir()
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name ~= "" and not buf_name:match("^%a+://") then
    return utils.parent_dir(buf_name)
  end
  return vim.fn.getcwd()
end

---@private
---@return proj.Project?
function ProjectManager:current_or_warn()
  local cur = self:current()
  if cur then
    return cur
  end
  utils.warn("No active project")
  return nil
end

---@return string
function ProjectManager:lualine_component()
  local cur = self:current()
  return cur and cur.name or ""
end

---@private
---@param proj proj.Project
function ProjectManager:open_project(proj)
  project.increment_open(proj.root)
  local tab = vim.api.nvim_get_current_tabpage()
  self.tab_projects[tab] = proj
  vim.cmd.tcd(vim.fn.fnameescape(proj.root))
  vim.schedule(function()
    last_file.open(proj.root)
  end)
end

---@private
---@param filename string
---@return string?
function ProjectManager:resolve_list(filename)
  local cur = self:current_or_warn()
  if not cur then
    return nil
  end
  return cur.root .. "/" .. filename
end

---@private
---@param filename string
---@param title string
function ProjectManager:pick_list(filename, title)
  local cur = self:current_or_warn()
  if not cur then
    return
  end
  lists.pick(cur.root .. "/" .. filename, title, cur.root)
end

---@private
---@param filename string
---@param title string
function ProjectManager:add_to_list(filename, title)
  local filepath = self:resolve_list(filename)
  if not filepath then
    return
  end
  utils.input_nonempty("New " .. title, function(value)
    lists.add(filepath, value)
  end)
end

---@private
---@param root string
---@return string?
function ProjectManager:project_readme(root)
  for _, name in ipairs({ "README.md", "readme.md", "Readme.md" }) do
    local path = root .. "/" .. name
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

---@private
---@param path string
---@return boolean
function ProjectManager:in_registered_project(path)
  return project.find_by_path(path) ~= nil
end

---@private
function ProjectManager:auto_detect_project()
  local tab = vim.api.nvim_get_current_tabpage()
  if self.tab_projects[tab] then
    return
  end
  local detected = project.find_by_path(self:current_buf_dir())
  if detected then
    self.tab_projects[tab] = detected
    vim.cmd.tcd(vim.fn.fnameescape(detected.root))
  end
end

---@private
function ProjectManager:sync_tab_cwd()
  local tab = vim.api.nvim_get_current_tabpage()
  if not self.tab_projects[tab] then
    self:auto_detect_project()
  end
  local cur = self.tab_projects[tab]
  if cur then
    vim.cmd.tcd(vim.fn.fnameescape(cur.root))
  end
end

---@private
function ProjectManager:sync_register_keymap()
  local lhs = self.cfg.register_keymap_lhs
  if lhs == "" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if self:in_registered_project(self:current_buf_dir()) then
    vim.keymap.set({ "n", "x" }, lhs, "<Nop>", {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Project add disabled in registered project",
    })
    return
  end
  utils.safe_del_keymap(lhs, buf, { "n", "x" })
end

---@private
---@param cwd string
function ProjectManager:git_commit(cwd)
  utils.input_nonempty("Commit message", function(msg)
    vim.system({ "git", "-C", cwd, "add", "-A" }, {}, function(add_result)
      vim.schedule(function()
        if add_result.code ~= 0 then
          local add_out = utils.system_output(add_result)
          utils.warn(add_out ~= "" and ("git add failed:\n" .. add_out) or "git add failed")
          return
        end
        vim.system({ "git", "-C", cwd, "commit", "-m", msg }, {}, function(commit_result)
          vim.schedule(function()
            local commit_out = utils.system_output(commit_result)
            if commit_result.code == 0 then
              utils.info(commit_out ~= "" and commit_out or "Committed changes")
              return
            end
            utils.warn(commit_out ~= "" and ("git commit failed:\n" .. commit_out) or "git commit failed")
          end)
        end)
      end)
    end)
  end)
end

---@private
function ProjectManager:setup_commands()
  local function cmd(name, callback, opts)
    vim.api.nvim_create_user_command(name, callback, opts)
  end

  local function with_cur(callback)
    local cur = self:current_or_warn()
    if not cur then
      return
    end
    callback(cur)
  end

  vim.api.nvim_create_user_command("ProjectHelp", function()
    local ok = pcall(function()
      vim.cmd("vert help proj.nvim")
    end)
    if not ok then
      pcall(function()
        vim.cmd("vert help proj")
      end)
    end
    pcall(function()
      vim.cmd("wincmd =")
    end)
  end, { desc = "Open proj help in an equal vertical split" })

  cmd("ProjectAdd", function()
    local root = project.find_git_root()
    if not root then
      utils.warn("Not inside a git repo")
      return
    end
    local proj = project.add(root)
    if proj then
      self.tab_projects[vim.api.nvim_get_current_tabpage()] = proj
      vim.cmd.tcd(vim.fn.fnameescape(root))
      self:sync_register_keymap()
    end
  end, { desc = "Register current git repo as project" })

  cmd("ProjectSwitch", function()
    local projects = project.read()
    if #projects == 0 then
      utils.info("No projects registered")
      return
    end
    local remembered_by_root = last_file.all()
    table.sort(projects, function(a, b)
      return (a.open_count or 0) > (b.open_count or 0)
    end)

    local function readme_path(root)
      for _, name in ipairs({ "README.md", "readme.md", "Readme.md" }) do
        local path = root .. "/" .. name
        if vim.fn.filereadable(path) == 1 then
          return path
        end
      end
      return nil
    end

    local function root_files_preview(root)
      local entries = vim.fn.readdir(root)
      if #entries == 0 then
        return { "Files:", "  (no files)" }
      end
      table.sort(entries)
      local lines = { "Files:" }
      local max_entries = 14
      local shown = math.min(#entries, max_entries)
      for idx = 1, shown do
        local name = entries[idx]
        local full = root .. "/" .. name
        local suffix = vim.fn.isdirectory(full) == 1 and "/" or ""
        lines[#lines + 1] = "  - " .. name .. suffix
      end
      if #entries > max_entries then
        lines[#lines + 1] = "  ... +" .. tostring(#entries - max_entries) .. " more"
      end
      return lines
    end

    local function readme_preview(root)
      local path = readme_path(root)
      if not path then
        return { "README:", "  (not found)" }
      end

      local content = utils.read_lines(path)
      if #content == 0 then
        return { "README:", "  (empty)" }
      end

      local lines = { "README (" .. utils.basename(path) .. "):" }
      local max_lines = 20
      local shown = math.min(#content, max_lines)
      for idx = 1, shown do
        lines[#lines + 1] = content[idx]
      end
      if #content > max_lines then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "... +" .. tostring(#content - max_lines) .. " more lines"
      end
      return lines
    end

    local function preview_lines(root, name, open_count)
      local remembered = remembered_by_root[root]
      local readme = readme_path(root)
      local fallback = readme or root
      local open_target = fallback

      local remembered_text = "none"
      if type(remembered) == "string" and remembered ~= "" then
        if vim.fn.filereadable(remembered) == 1 then
          remembered_text = remembered
          open_target = remembered
        else
          remembered_text = remembered .. " (missing)"
        end
      end

      local lines = {
        name,
        "",
        "Root: " .. root,
        "Opened: " .. tostring(open_count or 0),
        "Last modified file: " .. remembered_text,
        "Open target when selected: " .. open_target,
        "",
      }
      vim.list_extend(lines, root_files_preview(root))
      lines[#lines + 1] = ""
      vim.list_extend(lines, readme_preview(root))
      return lines
    end

    local items = {}
    for _, p in ipairs(projects) do
      items[#items + 1] = {
        text = p.name,
        root = p.root,
        name = p.name,
        open_count = p.open_count or 0,
        preview_lines = preview_lines(p.root, p.name, p.open_count or 0),
      }
    end
    Snacks.picker({
      title = "Projects",
      items = items,
      format = function(item)
        return { { item.text } }
      end,
      preview = function(ctx)
        ctx.preview:set_lines(ctx.item.preview_lines or { "(no preview)" })
        return true
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          self:open_project({ root = item.root, name = item.name, open_count = item.open_count or 0 })
        end
      end,
    })
  end, { desc = "Open project switcher" })

  cmd("ProjectList", function(call)
    with_cur(function(cur)
      local filename = call.args
      lists.pick(cur.root .. "/" .. filename, utils.stem(filename), cur.root)
    end)
  end, { nargs = 1, desc = "Pick items from a project list file" })

  cmd("ProjectAddItem", function(call)
    local filename = call.args
    self:add_to_list(filename, utils.stem(filename))
  end, { nargs = 1, desc = "Add item to a project list file" })

  local open_current_readme = function()
    local cur = self:current()
    local root = cur and cur.root or project.find_by_path(self:current_buf_dir())
    if not root then
      utils.warn("No active project")
      return
    end
    local readme = self:project_readme(root)
    if not readme then
      utils.warn("README not found in current project")
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(readme))
  end

  cmd("ProjectReadme", open_current_readme, { desc = "Open README.md in current project" })
  cmd("ProjectReadMe", open_current_readme, { desc = "Open README.md in current project" })
  cmd("ProjectREADME", open_current_readme, { desc = "Open README.md in current project" })

  for _, item in ipairs({
    { "ProjectTodo", "TODO.md", "TODO" },
    { "ProjectBugs", "BUGS.md", "BUGS" },
    { "ProjectTotest", "TOTEST.md", "TOTEST" },
    { "ProjectRemember", "REMEMBER.md", "REMEMBER" },
  }) do
    local name, file, title = item[1], item[2], item[3]
    cmd(name, function()
      self:pick_list(file, title)
    end, { desc = "Pick " .. title .. " items" })
    cmd("ProjectAdd" .. name:sub(8), function()
      self:add_to_list(file, title)
    end, { desc = "Add " .. title .. " item" })
  end

  cmd("ProjectGlobalList", function(call)
    local filename = call.args
    lists.pick_global(project.read(), filename, utils.stem(filename))
  end, { nargs = 1, desc = "Pick items from a list across all projects" })

  for _, item in ipairs({ { "TODO.md", "TODO" }, { "BUGS.md", "BUGS" }, { "TOTEST.md", "TOTEST" } }) do
    local file, title = item[1], item[2]
    cmd("ProjectGlobal" .. title, function()
      lists.pick_global(project.read(), file, title)
    end, { desc = "Global " .. title .. " picker" })
  end

  cmd("ProjectGlobalKeymaps", function()
    lists.pick_own("KEYMAPS.md", "KEYMAPS")
  end, { desc = "Global KEYMAPS list" })
  cmd("ProjectGlobalRemember", function()
    lists.pick_own("REMEMBER.md", "REMEMBER")
  end, { desc = "Global REMEMBER list" })
  cmd("ProjectGlobalAddKeymaps", function()
    lists.add_own("KEYMAPS.md", "KEYMAPS")
  end, { desc = "Add to global KEYMAPS" })
  cmd("ProjectGlobalAddRemember", function()
    lists.add_own("REMEMBER.md", "REMEMBER")
  end, { desc = "Add to global REMEMBER" })

  cmd("ProjectGlobalAddItem", function(call)
    local filename = call.args
    lists.add_to_project(project.read(), filename, utils.stem(filename))
  end, { nargs = 1, desc = "Add item to a list in any project" })

  cmd("ProjectGlobalAddAnyItem", function()
    lists.add_to_any_project_list(project.read())
  end, { desc = "Add item to any list in any project" })

  for _, item in ipairs({ { "TODO.md", "TODO" }, { "BUGS.md", "BUG" }, { "TOTEST.md", "TOTEST" } }) do
    local file, title = item[1], item[2]
    local cmd_name = title == "BUG" and "ProjectGlobalAddBug" or ("ProjectGlobalAdd" .. title)
    cmd(cmd_name, function()
      lists.add_to_project(project.read(), file, title)
    end, { desc = "Add " .. title .. " to any project" })
  end

  local function pick_issues(kind, title)
    local cur = self:current_or_warn()
    if not cur then
      return
    end
    issues.pick(issues.path(cur.root, kind), title, cur.root)
  end

  cmd("ProjectIssues", function()
    pick_issues("bugs", "Bugs")
  end, { desc = "Pick bugs from .issues/bugs.json" })
  cmd("ProjectIssuesTodo", function()
    pick_issues("todos", "Todos")
  end, { desc = "Pick todos from .issues/todos.json" })
  cmd("ProjectIssuesGlobal", function()
    issues.pick_global(project.read(), "bugs", "Bugs")
  end, { desc = "Global bugs picker across all projects" })
  cmd("ProjectIssuesTodoGlobal", function()
    issues.pick_global(project.read(), "todos", "Todos")
  end, { desc = "Global todos picker across all projects" })

  -- @@@proj.git.commands
  cmd("ProjectGitStatus", function()
    with_cur(function(cur)
      Snacks.picker.git_status({ cwd = cur.root, title = "Git Status" })
    end)
  end, { desc = "Git status for current project" })

  cmd("ProjectGitDiff", function()
    with_cur(function(cur)
      Snacks.picker.git_diff({ cwd = cur.root, title = "Git Diff" })
    end)
  end, { desc = "Git diff for current project" })

  cmd("ProjectGitHistory", function()
    with_cur(function(cur)
      Snacks.picker.git_log({ cwd = cur.root, title = "Git History" })
    end)
  end, { desc = "Git history for current project" })

  cmd("ProjectGitCommit", function()
    with_cur(function(cur)
      self:git_commit(cur.root)
    end)
  end, { desc = "Git commit for current project" })

  cmd("ProjectGitStash", function()
    with_cur(function(cur)
      Snacks.picker.git_stash({ cwd = cur.root, title = "Git Stash" })
    end)
  end, { desc = "Git stash for current project" })

  cmd("ProjectGitBranch", function()
    with_cur(function(cur)
      Snacks.picker.git_branches({ cwd = cur.root, title = "Git Branches" })
    end)
  end, { desc = "Git branches for current project" })

  cmd("ProjectPreviewLists", function()
    with_cur(function(cur)
      lists.toggle_preview(cur.root)
    end)
  end, { desc = "Toggle preview of all non-empty lists found in current project" })

  cmd("ProjectInfo", function()
    with_cur(function(cur)
      lists.toggle_project_info(cur.root)
    end)
  end, { desc = "Toggle project info panel (right floating preview)" })
end

---@private
---@param aug integer
function ProjectManager:setup_autocmds(aug)
  vim.api.nvim_create_autocmd("TabNewEntered", {
    group = aug,
    desc = "Inherit project from previous tab",
    callback = function()
      local new_tab = vim.api.nvim_get_current_tabpage()
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab ~= new_tab and self.tab_projects[tab] then
          self.tab_projects[new_tab] = self.tab_projects[tab]
          break
        end
      end
      self:sync_tab_cwd()
    end,
  })

  vim.api.nvim_create_autocmd({ "TabEnter", "BufEnter" }, {
    group = aug,
    desc = "Keep tab cwd and project-add keymap synced",
    callback = function()
      self:sync_tab_cwd()
      self:sync_register_keymap()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = aug,
    desc = "Remember latest project file",
    callback = function(args)
      local file = vim.api.nvim_buf_get_name(args.buf)
      if file == "" or file:match("^%a+://") then
        return
      end
      if vim.bo[args.buf].buftype ~= "" then
        return
      end
      local proj = project.find_by_path(file)
      if not proj then
        return
      end
      last_file.set(proj.root, file)
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = aug,
    desc = "Clean up closed tab project entries",
    callback = function()
      for tab in pairs(self.tab_projects) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          self.tab_projects[tab] = nil
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("SessionWritePost", {
    group = aug,
    desc = "Persist active project per tab for session restore",
    callback = function(args)
      local session_file = self:resolve_session_file(args)
      if session_file then
        self:save_session_state(session_file)
      end
    end,
  })

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = aug,
    desc = "Restore active project per tab after session load",
    callback = function(args)
      local session_file = self:resolve_session_file(args)
      if not session_file then
        return
      end
      self:load_session_state(session_file)
      self:sync_tab_cwd()
      self:sync_register_keymap()
    end,
  })
end

---@private
---@return proj.KeymapConfig|false
function ProjectManager:resolve_keymaps()
  if self.cfg.keymaps == false then
    return false
  end
  local default_prefix = "<leader>" .. self.cfg.keymap_prefix
  local base = {
    add_any_item = default_prefix .. "a",
    preview_lists = default_prefix .. "p",
  }
  if type(self.cfg.keymaps) ~= "table" then
    return base
  end
  return vim.tbl_deep_extend("force", base, self.cfg.keymaps)
end

---@private
function ProjectManager:setup_keymaps()
  -- @@@proj.keymaps
  local keymaps = self:resolve_keymaps()
  if keymaps == false then
    return
  end
  if keymaps.add_any_item and keymaps.add_any_item ~= "" then
    vim.keymap.set("n", keymaps.add_any_item, "<cmd>ProjectGlobalAddAnyItem<CR>", {
      desc = "Add item to any list in any project",
    })
  end
  if keymaps.preview_lists and keymaps.preview_lists ~= "" then
    vim.keymap.set("n", keymaps.preview_lists, "<cmd>ProjectPreviewLists<CR>", {
      desc = "Preview all lists in current project",
    })
  end
end

---@param opts? proj.SetupOptions|proj.Config
function ProjectManager:setup(opts)
  self.cfg = config.setup(opts)
  local aug = vim.api.nvim_create_augroup("Proj", { clear = true })

  -- @@@proj.commands
  self:setup_commands()
  self:setup_keymaps()

  -- @@@proj.autocmds
  self:setup_autocmds(aug)
  vim.schedule(function()
    self:sync_tab_cwd()
    self:sync_register_keymap()
  end)
end

---@type proj.ProjectManager
local manager = ProjectManager:new()
local M = { ProjectManager = ProjectManager }

---@param tabpage? integer
---@return proj.Project?
function M.current(tabpage)
  return manager:current(tabpage)
end

---@return string
function M.lualine_component()
  return manager:lualine_component()
end

---@param opts? proj.SetupOptions|proj.Config
function M.setup(opts)
  manager:setup(opts)
end

return M
