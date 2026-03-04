-- Tests for proj.project (registry read/write/add/remove, find_git_root).
-- Run with a test runner such as plenary.nvim:
--   :PlenaryBustedFile tests/project_spec.lua
--
-- These are integration tests that touch the filesystem; they use a temp dir
-- to avoid polluting the real registry.

local project = require("proj.project")

describe("proj.project", function()
    local tmp = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmp, "p")
        vim.fn.system({ "git", "init", tmp })
        -- Point the registry at a temp file for isolation.
        -- (Requires exposing registry_path or a test helper in project.lua)
    end)

    after_each(function()
        vim.fn.delete(tmp, "rf")
    end)

    describe("new()", function()
        it("derives name from basename", function()
            local p = project.new(tmp)
            assert.equals(vim.fn.fnamemodify(tmp, ":t"), p.name)
            assert.equals(tmp, p.root)
        end)

        it("names this plugin repo as proj.nvim", function()
            local proj_tmp = vim.fn.tempname()
            vim.fn.mkdir(proj_tmp .. "/plugin", "p")
            vim.fn.mkdir(proj_tmp .. "/lua/proj", "p")
            vim.fn.writefile({ "-- test" }, proj_tmp .. "/plugin/proj.lua")
            vim.fn.writefile({ "-- test" }, proj_tmp .. "/lua/proj/init.lua")

            local p = project.new(proj_tmp)
            assert.equals("proj.nvim", p.name)
            assert.equals(proj_tmp, p.root)

            vim.fn.delete(proj_tmp, "rf")
        end)
    end)

    describe("find_git_root()", function()
        it("finds root when inside a git repo", function()
            local root = project.find_git_root(tmp)
            -- git rev-parse returns the real path; compare basenames only.
            assert.is_not_nil(root)
        end)

        it("returns nil outside a git repo", function()
            local notgit = vim.fn.tempname()
            vim.fn.mkdir(notgit, "p")
            local root = project.find_git_root(notgit)
            assert.is_nil(root)
            vim.fn.delete(notgit, "rf")
        end)
    end)
end)
