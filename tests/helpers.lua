local util = require 'packer.util'

local M = { base_dir = '/tmp/__packer_tests__' }

---Create a fake git repository
---@param name string
---@param base string
function M.create_git_dir(name, base)
  base = base or M.base_dir
  local repo_path = util.join_paths(base, name)
  local path = util.join_paths(repo_path, '.git')
  if vim.fn.isdirectory(path) > 0 then
    M.cleanup_dirs(path)
  end
  vim.fn.mkdir(path, 'p')
  return repo_path
end

---Remove directories created for test purposes
---@vararg string
function M.cleanup_dirs(...)
  for _, dir in ipairs { ... } do
    vim.fn.delete(dir, 'rf')
  end
end

return M
