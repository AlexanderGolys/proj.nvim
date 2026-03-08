-- @@@proj.last_file

local fn = vim.fn
local utils = require("proj.utils")

---@alias proj.LastFileMap table<string, string>

---@class proj.LastFileStore
---@field path string
---@field files proj.LastFileMap
local LastFileStore = {}
LastFileStore.__index = LastFileStore

---@param path? string
---@return proj.LastFileStore
function LastFileStore:new(path)
  local instance = setmetatable({
    path = path or (fn.stdpath("data") .. "/proj_last_files.json"),
    files = {},
  }, self)
  instance:reload()
  return instance
end

---@private
---@param root unknown
---@param file unknown
---@return boolean
local function is_valid_pair(root, file)
  return type(root) == "string" and root ~= "" and type(file) == "string" and file ~= ""
end

---@private
---@param path string
---@return boolean
local function is_readable_file(path)
  return fn.filereadable(path) == 1
end

---@private
---@param path string
---@return string
local function normalize_path(path)
  return utils.normalize_path(path)
end

---@private
---@param root string
---@param file string
---@return boolean
local function file_under_root(root, file)
  local normalized_root = normalize_path(root)
  local normalized_file = normalize_path(file)
  if normalized_root == "" then
    return false
  end
  if normalized_file == normalized_root then
    return true
  end
  return normalized_file:find("^" .. vim.pesc(normalized_root) .. "[/\\]") ~= nil
end

---@private
---@param root string
---@return string?
local function find_readme(root)
  for _, name in ipairs({ "README.md", "readme.md", "Readme.md" }) do
    local path = root .. "/" .. name
    if is_readable_file(path) then
      return path
    end
  end
  return nil
end

---@return proj.LastFileMap
function LastFileStore:reload()
  local data = utils.read_json(self.path)
  self.files = {}
  for root, file in pairs(data) do
    if is_valid_pair(root, file) then
      self.files[root] = file
    end
  end
  return vim.deepcopy(self.files)
end

---@private
function LastFileStore:save()
  utils.write_json(self.path, self.files, "project last files")
end

---@param root string
---@param file string
function LastFileStore:set(root, file)
  self:reload()
  if self.files[root] == file then
    return
  end
  self.files[root] = file
  self:save()
end

---@param root string
---@return string?
function LastFileStore:get(root)
  self:reload()
  return self.files[root]
end

---@return proj.LastFileMap
function LastFileStore:all()
  return self:reload()
end

---@private
---@param root string
---@return string
function LastFileStore:resolve_open_path(root)
  local remembered = self:get(root)
  if remembered and is_readable_file(remembered) and file_under_root(root, remembered) then
    return remembered
  end

  local readme = find_readme(root)
  if readme then
    return readme
  end

  return root
end

---@param root string
function LastFileStore:open(root)
  vim.cmd.edit(fn.fnameescape(self:resolve_open_path(root)))
end

---@type proj.LastFileStore
local store = LastFileStore:new()

local M = { LastFileStore = LastFileStore }

---@param root string
---@param file string
function M.set(root, file)
  store:set(root, file)
end

---@param root string
---@return string?
function M.get(root)
  return store:get(root)
end

---@return proj.LastFileMap
function M.all()
  return store:all()
end

---@param root string
function M.open(root)
  store:open(root)
end

return M
