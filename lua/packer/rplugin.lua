local M = {}

local util = require 'packer.util'

---Add the remote plugin files to the runtime path and source them
---@param path string
function M.update(path)
  local rplugins = M.get(path)
  local dirs = vim.tbl_map(function(r)
    return r:gsub(util.get_separator() .. 'rplugin', '')
  end, rplugins)
  vim.opt.runtimepath:append(dirs)
  vim.cmd [[
    silent UpdateRemotePlugins
    " unlet! g:loaded_remote_plugins
    " runtime! plugin/rplugin.vim
  ]]
end

---@param path string
function M.get(path)
  return vim.fn.globpath(util.join_paths(path, '*'), 'rplugin', false, true)
end

---@param opt_dir string
function M.has_remote_plugins(opt_dir)
  local rplugins = M.get(opt_dir)
  return rplugins and not vim.tbl_isempty(rplugins)
end

return M
