local M = {}

-- @@@proj.init
-- ###nvim-plugin
--
-- |||proj.project|||
-- |||proj.session|||
-- |||proj.lists|||
-- |||proj.git|||

local project = require("proj.project")
local session = require("proj.session")
local lists = require("proj.lists")
local git = require("proj.git")

---@class proj.Config
---@field keymap_prefix string   leader prefix for all proj keymaps (default: "p")

---@type proj.Config
local defaults = {
    keymap_prefix = "p",
}

---@type table<integer, proj.Project>
local tab_projects = {}

-- ── Public API ────────────────────────────────────────────────────────────────

---@param tabpage? integer
---@return proj.Project?
function M.current(tabpage)
    return tab_projects[tabpage or vim.api.nvim_get_current_tabpage()]
end

---@return string  project name for current tab, or "" if none
function M.lualine_component()
    local cur = M.current()
    return cur and cur.name or ""
end

-- ── Private helpers ───────────────────────────────────────────────────────────

---@param proj proj.Project
local function open_project(proj)
    local prev = M.current()
    if prev then
        session.save(prev.name)
    end
    local tab = vim.api.nvim_get_current_tabpage()
    tab_projects[tab] = proj
    vim.cmd.tcd(vim.fn.fnameescape(proj.root))
    session.restore(proj.name, proj.root)
end

---@param filename string
---@return string?
local function resolve_list(filename)
    local cur = M.current()
    if not cur then
        vim.notify("No active project", vim.log.levels.WARN)
        return nil
    end
    return cur.root .. "/" .. filename
end

---@param filename string
---@param title string
local function pick_list(filename, title)
    local cur = M.current()
    if not cur then
        vim.notify("No active project", vim.log.levels.WARN)
        return
    end
    lists.pick(cur.root .. "/" .. filename, title, cur.root)
end

---@param filename string
---@param title string
local function add_to_list(filename, title)
    local filepath = resolve_list(filename)
    if not filepath then
        return
    end
    Snacks.input({ prompt = "New " .. title }, function(value)
        if value and value ~= "" then
            lists.add(filepath, value)
        end
    end)
end

---@param cur proj.Project
local function with_root(cur, fn)
    fn(cur.root)
end

-- Auto-detect current project if none is set. If the current buffer's directory
-- matches a registered project, set it as the current project for this tab.
local function auto_detect_project()
    local tab = vim.api.nvim_get_current_tabpage()
    if tab_projects[tab] then
        return  -- already set
    end

    -- Get current buffer's directory (or cwd if no buffer)
    local buf = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(buf)
    local cwd = buf_name ~= "" and vim.fn.fnamemodify(buf_name, ":h") or vim.fn.getcwd()

    -- Check against registered projects
    local projects = project.read()
    for _, proj in ipairs(projects) do
        if proj.root == cwd then
            tab_projects[tab] = proj
            vim.cmd.tcd(vim.fn.fnameescape(proj.root))
            return
        end
    end

    -- Also try to find a parent directory that matches (handles subdirs)
    for _, proj in ipairs(projects) do
        if cwd:find("^" .. proj.root .. "/") then
            tab_projects[tab] = proj
            vim.cmd.tcd(vim.fn.fnameescape(proj.root))
            return
        end
    end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

-- @@@proj.commands

---@param opts? proj.Config
function M.setup(opts)
    ---@type proj.Config
    local cfg = vim.tbl_deep_extend("force", defaults, opts or {})

    local aug = vim.api.nvim_create_augroup("Proj", { clear = true })

    -- Auto-detect project on startup if none is set for the current tab
    auto_detect_project()

    -- ── Commands ──────────────────────────────────────────────────────────────

    vim.api.nvim_create_user_command("ProjectAdd", function()
        local root = project.find_git_root()
        if not root then
            vim.notify("Not inside a git repo", vim.log.levels.WARN)
            return
        end
        local proj = project.add(root)
        if proj then
            local tab = vim.api.nvim_get_current_tabpage()
            tab_projects[tab] = proj
            vim.cmd.tcd(vim.fn.fnameescape(root))
        end
    end, { desc = "Register current git repo as project" })

    vim.api.nvim_create_user_command("ProjectSwitch", function()
        local projects = project.read()
        if #projects == 0 then
            vim.notify("No projects registered", vim.log.levels.INFO)
            return
        end
        local items = {}
        for _, p in ipairs(projects) do
            items[#items + 1] = { text = p.name, root = p.root, name = p.name }
        end
        Snacks.picker({
            title = "Projects",
            items = items,
            format = function(item) return { { item.text } } end,
            confirm = function(picker, item)
                picker:close()
                if item then
                    open_project({ root = item.root, name = item.name })
                end
            end,
            preview = function(ctx)
                ctx.preview:set_lines({ ctx.item.name, "", ctx.item.root })
                return true
            end,
        })
    end, { desc = "Open project switcher" })

    vim.api.nvim_create_user_command("ProjectList", function(cmd)
        local filename = cmd.args
        local cur = M.current()
        if not cur then
            vim.notify("No active project", vim.log.levels.WARN)
            return
        end
        lists.pick(cur.root .. "/" .. filename, vim.fn.fnamemodify(filename, ":r"), cur.root)
    end, { nargs = 1, desc = "Pick items from a project list file" })

    vim.api.nvim_create_user_command("ProjectAddItem", function(cmd)
        local filename = cmd.args
        add_to_list(filename, vim.fn.fnamemodify(filename, ":r"))
    end, { nargs = 1, desc = "Add item to a project list file" })

    vim.api.nvim_create_user_command("ProjectTodo",    function() pick_list("TODO.md",    "TODO")    end, { desc = "Pick TODO items" })
    vim.api.nvim_create_user_command("ProjectBugs",    function() pick_list("BUGS.md",    "BUGS")    end, { desc = "Pick BUGS items" })
    vim.api.nvim_create_user_command("ProjectTotest",  function() pick_list("TOTEST.md",  "TOTEST")  end, { desc = "Pick TOTEST items" })
    vim.api.nvim_create_user_command("ProjectRemember",function() pick_list("REMEMBER.md","REMEMBER")end, { desc = "Pick REMEMBER items" })

    vim.api.nvim_create_user_command("ProjectAddTodo",    function() add_to_list("TODO.md",    "TODO")    end, { desc = "Add TODO item" })
    vim.api.nvim_create_user_command("ProjectAddBug",     function() add_to_list("BUGS.md",    "BUG")     end, { desc = "Add BUG item" })
    vim.api.nvim_create_user_command("ProjectAddTotest",  function() add_to_list("TOTEST.md",  "TOTEST")  end, { desc = "Add TOTEST item" })
    vim.api.nvim_create_user_command("ProjectAddRemember",function() add_to_list("REMEMBER.md","REMEMBER")end, { desc = "Add REMEMBER item" })

    vim.api.nvim_create_user_command("ProjectGlobalList", function(cmd)
        local filename = cmd.args
        lists.pick_global(project.read(), filename, vim.fn.fnamemodify(filename, ":r"))
    end, { nargs = 1, desc = "Pick items from a list across all projects" })

    vim.api.nvim_create_user_command("ProjectGlobalTodo",   function() lists.pick_global(project.read(), "TODO.md",   "TODO")   end, { desc = "Global TODO picker" })
    vim.api.nvim_create_user_command("ProjectGlobalBugs",   function() lists.pick_global(project.read(), "BUGS.md",   "BUGS")   end, { desc = "Global BUGS picker" })
    vim.api.nvim_create_user_command("ProjectGlobalTotest", function() lists.pick_global(project.read(), "TOTEST.md", "TOTEST") end, { desc = "Global TOTEST picker" })

    vim.api.nvim_create_user_command("ProjectGlobalKeymaps", function() lists.pick_own("KEYMAPS.md",  "KEYMAPS")  end, { desc = "Global KEYMAPS list" })
    vim.api.nvim_create_user_command("ProjectGlobalRemember",function() lists.pick_own("REMEMBER.md", "REMEMBER") end, { desc = "Global REMEMBER list" })

    vim.api.nvim_create_user_command("ProjectGlobalAddKeymaps", function() lists.add_own("KEYMAPS.md",  "KEYMAPS")  end, { desc = "Add to global KEYMAPS" })
    vim.api.nvim_create_user_command("ProjectGlobalAddRemember",function() lists.add_own("REMEMBER.md", "REMEMBER") end, { desc = "Add to global REMEMBER" })

    vim.api.nvim_create_user_command("ProjectGlobalAddItem", function(cmd)
        local filename = cmd.args
        lists.add_to_project(project.read(), filename, vim.fn.fnamemodify(filename, ":r"))
    end, { nargs = 1, desc = "Add item to a list in any project" })

    vim.api.nvim_create_user_command("ProjectGlobalAddTodo",   function() lists.add_to_project(project.read(), "TODO.md",   "TODO")   end, { desc = "Add TODO to any project" })
    vim.api.nvim_create_user_command("ProjectGlobalAddBug",    function() lists.add_to_project(project.read(), "BUGS.md",   "BUG")    end, { desc = "Add BUG to any project" })
    vim.api.nvim_create_user_command("ProjectGlobalAddTotest", function() lists.add_to_project(project.read(), "TOTEST.md", "TOTEST") end, { desc = "Add TOTEST to any project" })

    -- @@@proj.git.commands

    vim.api.nvim_create_user_command("ProjectGitStatus",  function()
        local cur = M.current(); if cur then with_root(cur, git.status)  end
    end, { desc = "Git status for current project" })
    vim.api.nvim_create_user_command("ProjectGitDiff",    function()
        local cur = M.current(); if cur then with_root(cur, git.diff)    end
    end, { desc = "Git diff for current project" })
    vim.api.nvim_create_user_command("ProjectGitHistory", function()
        local cur = M.current(); if cur then with_root(cur, git.history) end
    end, { desc = "Git history for current project" })
    vim.api.nvim_create_user_command("ProjectGitCommit",  function()
        local cur = M.current(); if cur then with_root(cur, git.commit)  end
    end, { desc = "Git commit for current project" })
    vim.api.nvim_create_user_command("ProjectGitStash",   function()
        local cur = M.current(); if cur then with_root(cur, git.stash)   end
    end, { desc = "Git stash for current project" })
    vim.api.nvim_create_user_command("ProjectGitBranch",  function()
        local cur = M.current(); if cur then with_root(cur, git.branch)  end
    end, { desc = "Git new branch for current project" })

    vim.api.nvim_create_user_command("ProjectOpenCode", function()
        local cur = M.current()
        if not cur then
            vim.notify("No active project", vim.log.levels.WARN)
            return
        end
        vim.cmd.tcd(vim.fn.fnameescape(cur.root))
        require("opencode").toggle()
    end, { desc = "Toggle opencode for current project" })

    -- @@@proj.keymaps

    local prefix = "<leader>" .. cfg.keymap_prefix
    local function map(lhs, rhs, desc)
        vim.keymap.set("n", prefix .. lhs, rhs, { desc = "Proj: " .. desc })
    end

    map("s",   "<cmd>ProjectSwitch<cr>",           "[S]witch project")
    map("A",   "<cmd>ProjectAdd<cr>",              "[A]dd project")
    map("t",   "<cmd>ProjectTodo<cr>",             "[T]odo list")
    map("b",   "<cmd>ProjectBugs<cr>",             "[B]ugs list")
    map("d",   "<cmd>ProjectTotest<cr>",           "Tot[e]st list")
    map("r",   "<cmd>ProjectRemember<cr>",         "[R]emember list")
    map("at",  "<cmd>ProjectAddTodo<cr>",          "Add [t]odo")
    map("ab",  "<cmd>ProjectAddBug<cr>",           "Add [b]ug")
    map("ad",  "<cmd>ProjectAddTotest<cr>",        "Add tot[e]st")
    map("ar",  "<cmd>ProjectAddRemember<cr>",      "Add [r]emember")
    map("o",   "<cmd>ProjectOpenCode<cr>",         "[O]pencode toggle")
    map("gt",  "<cmd>ProjectGlobalTodo<cr>",       "[G]lobal [t]odo")
    map("gk",  "<cmd>ProjectGlobalKeymaps<cr>",    "[G]lobal [k]eymaps")
    map("gr",  "<cmd>ProjectGlobalRemember<cr>",   "[G]lobal [r]emember")
    map("agt", "<cmd>ProjectGlobalAddTodo<cr>",    "[G]lobal add [t]odo")
    map("agk", "<cmd>ProjectGlobalAddKeymaps<cr>", "[G]lobal add [k]eymaps")
    map("agr", "<cmd>ProjectGlobalAddRemember<cr>","[G]lobal add [r]emember")

    -- @@@proj.autocmds

    vim.api.nvim_create_autocmd("TabNewEntered", {
        group = aug,
        desc = "Inherit project from previous tab",
        callback = function()
            local new_tab = vim.api.nvim_get_current_tabpage()
            for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
                if tab ~= new_tab and tab_projects[tab] then
                    tab_projects[new_tab] = tab_projects[tab]
                    break
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("TabClosed", {
        group = aug,
        desc = "Clean up closed tab project entries",
        callback = function()
            for tab in pairs(tab_projects) do
                if not vim.api.nvim_tabpage_is_valid(tab) then
                    tab_projects[tab] = nil
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = aug,
        desc = "Save sessions on exit",
        callback = function()
            local cur = M.current()
            if cur then
                session.save(cur.name)
            end
            session.save_global()
        end,
    })
end

return M
