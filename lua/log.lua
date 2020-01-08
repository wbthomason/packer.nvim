local nvim = vim.api

local function echo_special(msg, hl)
  nvim.nvim_command('echohl ' .. hl)
  nvim.nvim_command('echom [plague] ' .. msg)
  nvim.nvim_command('echohl None')
end

local log = {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end,
}

return log
