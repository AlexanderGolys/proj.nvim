local last_file = require("proj.last_file")

describe("proj.last_file", function()
  local tmp_root
  local tmp_store_path
  local readme_path
  local remembered_path

  before_each(function()
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_store_path = vim.fn.tempname() .. ".json"
    readme_path = tmp_root .. "/readme.md"
    remembered_path = tmp_root .. "/notes.md"
    vim.fn.writefile({ "# Readme" }, readme_path)
    vim.fn.writefile({ "notes" }, remembered_path)
  end)

  after_each(function()
    vim.fn.delete(tmp_store_path)
    vim.fn.delete(tmp_root, "rf")
  end)

  it("stores and returns remembered file by project root", function()
    local store = last_file.LastFileStore:new(tmp_store_path)
    store:set(tmp_root, remembered_path)
    assert.equals(remembered_path, store:get(tmp_root))
  end)

  it("opens remembered file when it exists", function()
    local store = last_file.LastFileStore:new(tmp_store_path)
    store:set(tmp_root, remembered_path)

    local called
    local original_edit = vim.cmd.edit
    vim.cmd.edit = function(path)
      called = path
    end

    store:open(tmp_root)
    vim.cmd.edit = original_edit

    assert.equals(vim.fn.fnameescape(remembered_path), called)
  end)

  it("opens readme.md when no file is remembered", function()
    local store = last_file.LastFileStore:new(tmp_store_path)

    local called
    local original_edit = vim.cmd.edit
    vim.cmd.edit = function(path)
      called = path
    end

    store:open(tmp_root)
    vim.cmd.edit = original_edit

    assert.equals(vim.fn.fnameescape(readme_path), called)
  end)

  it("falls back to root when remembered file and readme.md are missing", function()
    local store = last_file.LastFileStore:new(tmp_store_path)
    store:set(tmp_root, tmp_root .. "/missing.md")
    vim.fn.delete(readme_path)

    local called
    local original_edit = vim.cmd.edit
    vim.cmd.edit = function(path)
      called = path
    end

    store:open(tmp_root)
    vim.cmd.edit = original_edit

    assert.equals(vim.fn.fnameescape(tmp_root), called)
  end)

  it("opens README.md when no remembered file exists and uppercase readme is present", function()
    local upper_readme_path = tmp_root .. "/README.md"
    vim.fn.delete(readme_path)
    vim.fn.writefile({ "# README" }, upper_readme_path)
    local store = last_file.LastFileStore:new(tmp_store_path)

    local called
    local original_edit = vim.cmd.edit
    vim.cmd.edit = function(path)
      called = path
    end

    store:open(tmp_root)
    vim.cmd.edit = original_edit

    assert.equals(vim.fn.fnameescape(upper_readme_path), called)
  end)
end)
