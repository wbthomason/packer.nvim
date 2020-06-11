local api = vim.api

local echo_special = vim.schedule_wrap(function(msg, hl)
  api.nvim_command('echohl ' .. hl)
  api.nvim_command('echom "[packer] ' .. msg .. '"')
  api.nvim_command('echohl None')
end)

local log = {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end,
}

return log
