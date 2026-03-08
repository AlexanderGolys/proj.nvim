local fn = vim.fn
local utils = require("proj.utils")

-- @@@proj.project
-- @##proj

---@class proj.Project
---@field root string
---@field name string
---@field open_count integer

---@alias proj.ProjectRootIndex table<string, integer>

---@class proj.ProjectEntry
---@field root? unknown
---@field name? unknown
---@field open_count? unknown

---@class proj.ProjectList
---@field path string Absolute path to `proj_registry.json`.
---@field projects proj.Project[]
---@field by_root proj.ProjectRootIndex
local ProjectList = {}
ProjectList.__index = ProjectList

---@param entry proj.ProjectEntry
---@return proj.Project?
local function normalize_project(entry)
  if type(entry) ~= "table" or type(entry.root) ~= "string" or entry.root == "" then
    return nil
  end
  local count = tonumber(entry.open_count) or 0
  if count < 0 then
    count = 0
  end
  return {
    root = entry.root,
    name = (type(entry.name) == "string" and entry.name ~= "") and entry.name or utils.basename(entry.root),
    open_count = math.floor(count),
  }
end

---@private
function ProjectList:reindex()
  self.by_root = {}
  for idx, proj in ipairs(self.projects) do
    self.by_root[proj.root] = idx
  end
end

---@private
---@param entries table
function ProjectList:load_entries(entries)
  self.projects = {}
  for _, entry in ipairs(entries) do
    local proj = normalize_project(entry)
    if proj then
      self.projects[#self.projects + 1] = proj
    end
  end
  self:reindex()
end

---@param path? string
---@return proj.ProjectList
function ProjectList:new(path)
  local instance = setmetatable({
    path = path or (fn.stdpath("data") .. "/proj_registry.json"),
    projects = {},
    by_root = {},
  }, self)
  instance:reload()
  return instance
end

---@param root string
---@return proj.Project
function ProjectList:new_project(root)
  return { root = root, name = utils.basename(root), open_count = 0 }
end

---@return proj.Project[]
function ProjectList:reload()
  self:load_entries(utils.read_json(self.path))
  return vim.deepcopy(self.projects)
end

---@return proj.Project[]
function ProjectList:all()
  return vim.deepcopy(self.projects)
end

---@param data proj.Project[]
function ProjectList:set(data)
  self:load_entries(data)
  self:save()
end

function ProjectList:save()
  utils.write_json(self.path, self.projects, "project registry")
end

---@param root string
---@return proj.Project?
function ProjectList:add(root)
  if fn.isdirectory(root .. "/.git") == 0 then
    utils.warn("Not a git repo: " .. root)
    return nil
  end
  if self.by_root[root] then
    local existing = self.projects[self.by_root[root]]
    utils.warn("Already registered: " .. existing.name)
    return nil
  end
  local proj = self:new_project(root)
  self.projects[#self.projects + 1] = proj
  self:reindex()
  self:save()
  utils.info("Added project: " .. proj.name)
  return proj
end

---@param root string
function ProjectList:increment_open(root)
  local idx = self.by_root[root]
  if not idx then
    return
  end
  local proj = self.projects[idx]
  proj.open_count = (proj.open_count or 0) + 1
  self:save()
end

---@param root string
function ProjectList:remove(root)
  local idx = self.by_root[root]
  if not idx then
    return
  end
  table.remove(self.projects, idx)
  self:reindex()
  self:save()
end

---@param path string
---@return proj.Project?
function ProjectList:find_by_path(path)
  for _, proj in ipairs(self.projects) do
    if path == proj.root or vim.startswith(path .. "/", proj.root .. "/") then
      return proj
    end
  end
  return nil
end

---@param path? string Directory to query (defaults to cwd).
---@return string? git_root Absolute git root or `nil` outside a repository.
function ProjectList:find_git_root(path)
  local result = fn.systemlist({ "git", "-C", path or fn.getcwd(), "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return result[1]
end

---@type proj.ProjectList
local registry = ProjectList:new()

local M = { ProjectList = ProjectList }

---@param root string
---@return proj.Project
function M.new(root)
  return registry:new_project(root)
end

---@return proj.Project[]
function M.read()
  return registry:reload()
end

---@param data proj.Project[]
function M.write(data)
  registry:set(data)
end

---@param root string
---@return proj.Project?
function M.add(root)
  return registry:add(root)
end

---@param root string
function M.increment_open(root)
  registry:increment_open(root)
end

---@param root string
function M.remove(root)
  registry:remove(root)
end

---@param path string
---@return proj.Project?
function M.find_by_path(path)
  registry:reload()
  return registry:find_by_path(path)
end

---@param path? string
---@return string?
function M.find_git_root(path)
  return registry:find_git_root(path)
end

return M
