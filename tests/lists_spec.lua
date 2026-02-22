-- Tests for proj.lists (parse, add, delete, move).
-- Run with: :PlenaryBustedFile tests/lists_spec.lua

local lists = require("proj.lists")

describe("proj.lists", function()
    local tmp_file

    before_each(function()
        tmp_file = vim.fn.tempname() .. ".md"
    end)

    after_each(function()
        vim.fn.delete(tmp_file)
    end)

    describe("parse()", function()
        it("returns empty table for missing file", function()
            local items = lists.parse("/nonexistent/file.md")
            assert.same({}, items)
        end)

        it("parses ## headings into items", function()
            vim.fn.writefile({ "## First", "body line", "", "## Second" }, tmp_file)
            local items = lists.parse(tmp_file)
            assert.equals(2, #items)
            assert.equals("First", items[1].header)
            assert.equals("body line", items[1].body[1])
            assert.equals("Second", items[2].header)
        end)

        it("ignores lines before the first heading", function()
            vim.fn.writefile({ "preamble", "## Only" }, tmp_file)
            local items = lists.parse(tmp_file)
            assert.equals(1, #items)
            assert.equals("Only", items[1].header)
        end)
    end)

    describe("add()", function()
        it("creates the file when it does not exist", function()
            lists.add(tmp_file, "New entry")
            assert.equals(1, vim.fn.filereadable(tmp_file))
        end)

        it("appends a ## heading", function()
            lists.add(tmp_file, "My item")
            local items = lists.parse(tmp_file)
            assert.equals(1, #items)
            assert.equals("My item", items[1].header)
        end)

        it("adds a blank separator between existing and new content", function()
            lists.add(tmp_file, "First")
            lists.add(tmp_file, "Second")
            local raw = vim.fn.readfile(tmp_file)
            -- There should be a blank line between the two entries.
            local found_blank = false
            for _, l in ipairs(raw) do
                if l == "" then found_blank = true end
            end
            assert.is_true(found_blank)
        end)

        it("does not add blank line when file is empty/new", function()
            lists.add(tmp_file, "Only")
            local raw = vim.fn.readfile(tmp_file)
            assert.equals("## Only", raw[1])
        end)
    end)
end)
