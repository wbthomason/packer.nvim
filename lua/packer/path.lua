--- Minimal platform-aware path manipulation utilities for the parts of packer that load on every start
local is_windows = vim.loop.os_uname().sysname:lower():find 'windows' ~= nil
local M = { path_separator = (is_windows and [[\]]) or [[/]] }
function M.join_paths(...)
  return table.concat({ ... }, M.path_separator)
end

return M
