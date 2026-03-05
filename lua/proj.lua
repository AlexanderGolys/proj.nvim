local project = require("proj.project")
local session = require("proj.session")
local lists = require("proj.lists")
local issues = require("proj.issues")
local utils = require("proj.utils")
local config = require("proj.config")

-- @@@proj
-- @##proj
--
-- /@@proj.project
-- /@@proj.session
-- /@@proj.lists
-- /@@proj.issues
-- /@@proj.opencode
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

---@param tabpage? integer
---@return proj.Project?
function ProjectManager:current(tabpage)
  return self.tab_projects[tabpage or vim.api.nvim_get_current_tabpage()]
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
  local prev = self:current()
  if prev then
    session.save(prev.name)
  end
  project.increment_open(proj.root)
  local tab = vim.api.nvim_get_current_tabpage()
  self.tab_projects[tab] = proj
  vim.cmd.tcd(vim.fn.fnameescape(proj.root))
  session.restore(proj.name, proj.root)
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
  Snacks.input({ prompt = "New " .. title }, function(value)
    if value and value ~= "" then
      lists.add(filepath, value)
    end
  end)
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
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local cwd = (buf_name ~= "" and not buf_name:match("^%a+://")) and vim.fn.fnamemodify(buf_name, ":h") or vim.fn.getcwd()
  local detected = project.find_by_path(cwd)
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
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local dir = (buf_name ~= "" and not buf_name:match("^%a+://")) and vim.fn.fnamemodify(buf_name, ":p:h") or vim.fn.getcwd()
  if self:in_registered_project(dir) then
    vim.keymap.set({ "n", "x" }, lhs, "<Nop>", {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Project add disabled in registered project",
    })
    return
  end
  pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  pcall(vim.keymap.del, "x", lhs, { buffer = buf })
end

---@private
---@param cwd string
function ProjectManager:git_commit(cwd)
  Snacks.input({ prompt = "Commit message" }, function(msg)
    if not msg or msg == "" then
      return
    end
    vim.system({ "git", "-C", cwd, "add", "-A" }, {}, function(add_result)
      vim.schedule(function()
        if add_result.code ~= 0 then
          local add_out = vim.trim(((add_result.stderr or "") .. "\n" .. (add_result.stdout or "")))
          utils.warn(add_out ~= "" and ("git add failed:\n" .. add_out) or "git add failed")
          return
        end
        vim.system({ "git", "-C", cwd, "commit", "-m", msg }, {}, function(commit_result)
          vim.schedule(function()
            local commit_out = vim.trim(((commit_result.stdout or "") .. "\n" .. (commit_result.stderr or "")))
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

  vim.api.nvim_create_user_command("ProjectAdd", function()
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

  vim.api.nvim_create_user_command("ProjectSwitch", function()
    local projects = project.read()
    if #projects == 0 then
      utils.info("No projects registered")
      return
    end
    table.sort(projects, function(a, b)
      return (a.open_count or 0) > (b.open_count or 0)
    end)
    local items = {}
    for _, p in ipairs(projects) do
      items[#items + 1] = { text = p.name, root = p.root, name = p.name }
    end
    Snacks.picker({
      title = "Projects",
      items = items,
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          self:open_project({ root = item.root, name = item.name, open_count = 0 })
        end
      end,
      preview = function(ctx)
        ctx.preview:set_lines({ ctx.item.name, "", ctx.item.root })
        return true
      end,
    })
  end, { desc = "Open project switcher" })

  vim.api.nvim_create_user_command("ProjectList", function(cmd)
    local cur = self:current_or_warn()
    if not cur then
      return
    end
    local filename = cmd.args
    lists.pick(cur.root .. "/" .. filename, vim.fn.fnamemodify(filename, ":r"), cur.root)
  end, { nargs = 1, desc = "Pick items from a project list file" })

  vim.api.nvim_create_user_command("ProjectAddItem", function(cmd)
    local filename = cmd.args
    self:add_to_list(filename, vim.fn.fnamemodify(filename, ":r"))
  end, { nargs = 1, desc = "Add item to a project list file" })

  for _, item in ipairs({
    { "ProjectTodo", "TODO.md", "TODO" },
    { "ProjectBugs", "BUGS.md", "BUGS" },
    { "ProjectTotest", "TOTEST.md", "TOTEST" },
    { "ProjectRemember", "REMEMBER.md", "REMEMBER" },
  }) do
    local name, file, title = item[1], item[2], item[3]
    vim.api.nvim_create_user_command(name, function()
      self:pick_list(file, title)
    end, { desc = "Pick " .. title .. " items" })
    vim.api.nvim_create_user_command("ProjectAdd" .. name:sub(8), function()
      self:add_to_list(file, title)
    end, { desc = "Add " .. title .. " item" })
  end

  vim.api.nvim_create_user_command("ProjectGlobalList", function(cmd)
    local filename = cmd.args
    lists.pick_global(project.read(), filename, vim.fn.fnamemodify(filename, ":r"))
  end, { nargs = 1, desc = "Pick items from a list across all projects" })

  for _, item in ipairs({ { "TODO.md", "TODO" }, { "BUGS.md", "BUGS" }, { "TOTEST.md", "TOTEST" } }) do
    local file, title = item[1], item[2]
    vim.api.nvim_create_user_command("ProjectGlobal" .. title, function()
      lists.pick_global(project.read(), file, title)
    end, { desc = "Global " .. title .. " picker" })
  end

  vim.api.nvim_create_user_command("ProjectGlobalKeymaps", function()
    lists.pick_own("KEYMAPS.md", "KEYMAPS")
  end, { desc = "Global KEYMAPS list" })
  vim.api.nvim_create_user_command("ProjectGlobalRemember", function()
    lists.pick_own("REMEMBER.md", "REMEMBER")
  end, { desc = "Global REMEMBER list" })
  vim.api.nvim_create_user_command("ProjectGlobalAddKeymaps", function()
    lists.add_own("KEYMAPS.md", "KEYMAPS")
  end, { desc = "Add to global KEYMAPS" })
  vim.api.nvim_create_user_command("ProjectGlobalAddRemember", function()
    lists.add_own("REMEMBER.md", "REMEMBER")
  end, { desc = "Add to global REMEMBER" })

  vim.api.nvim_create_user_command("ProjectGlobalAddItem", function(cmd)
    local filename = cmd.args
    lists.add_to_project(project.read(), filename, vim.fn.fnamemodify(filename, ":r"))
  end, { nargs = 1, desc = "Add item to a list in any project" })

  vim.api.nvim_create_user_command("ProjectGlobalAddAnyItem", function()
    lists.add_to_any_project_list(project.read())
  end, { desc = "Add item to any list in any project" })

  for _, item in ipairs({ { "TODO.md", "TODO" }, { "BUGS.md", "BUG" }, { "TOTEST.md", "TOTEST" } }) do
    local file, title = item[1], item[2]
    local cmd_name = title == "BUG" and "ProjectGlobalAddBug" or ("ProjectGlobalAdd" .. title)
    vim.api.nvim_create_user_command(cmd_name, function()
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

  vim.api.nvim_create_user_command("ProjectIssues", function()
    pick_issues("bugs", "Bugs")
  end, { desc = "Pick bugs from .issues/bugs.json" })
  vim.api.nvim_create_user_command("ProjectIssuesTodo", function()
    pick_issues("todos", "Todos")
  end, { desc = "Pick todos from .issues/todos.json" })
  vim.api.nvim_create_user_command("ProjectIssuesGlobal", function()
    issues.pick_global(project.read(), "bugs", "Bugs")
  end, { desc = "Global bugs picker across all projects" })
  vim.api.nvim_create_user_command("ProjectIssuesTodoGlobal", function()
    issues.pick_global(project.read(), "todos", "Todos")
  end, { desc = "Global todos picker across all projects" })

  -- @@@proj.git.commands
  vim.api.nvim_create_user_command("ProjectGitStatus", function()
    local cur = self:current_or_warn()
    if cur then
      Snacks.picker.git_status({ cwd = cur.root, title = "Git Status" })
    end
  end, { desc = "Git status for current project" })

  vim.api.nvim_create_user_command("ProjectGitDiff", function()
    local cur = self:current_or_warn()
    if cur then
      Snacks.picker.git_diff({ cwd = cur.root, title = "Git Diff" })
    end
  end, { desc = "Git diff for current project" })

  vim.api.nvim_create_user_command("ProjectGitHistory", function()
    local cur = self:current_or_warn()
    if cur then
      Snacks.picker.git_log({ cwd = cur.root, title = "Git History" })
    end
  end, { desc = "Git history for current project" })

  vim.api.nvim_create_user_command("ProjectGitCommit", function()
    local cur = self:current_or_warn()
    if cur then
      self:git_commit(cur.root)
    end
  end, { desc = "Git commit for current project" })

  vim.api.nvim_create_user_command("ProjectGitStash", function()
    local cur = self:current_or_warn()
    if cur then
      Snacks.picker.git_stash({ cwd = cur.root, title = "Git Stash" })
    end
  end, { desc = "Git stash for current project" })

  vim.api.nvim_create_user_command("ProjectGitBranch", function()
    local cur = self:current_or_warn()
    if cur then
      Snacks.picker.git_branches({ cwd = cur.root, title = "Git Branches" })
    end
  end, { desc = "Git branches for current project" })

  vim.api.nvim_create_user_command("ProjectOpenCode", function()
    local cur = self:current()
    if not cur then
      utils.info("No active project, opening global opencode")
      require("proj.opencode").toggle()
      return
    end
    vim.cmd.tcd(vim.fn.fnameescape(cur.root))
    require("proj.opencode").toggle()
  end, { desc = "Toggle opencode for current project" })

  vim.api.nvim_create_user_command("ProjectPreviewLists", function()
    local cur = self:current_or_warn()
    if not cur then
      return
    end
    lists.toggle_preview(cur.root)
  end, { desc = "Toggle preview of all non-empty lists found in current project" })
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

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    desc = "Save sessions on exit",
    callback = function()
      local cur = self:current()
      if cur then
        session.save(cur.name)
      end
      session.save_global()
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
