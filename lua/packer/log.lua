local echo_special = vim.schedule_wrap(function(msg, hl)
  vim.cmd('echohl ' .. hl)
  vim.cmd('echom "[packer] ' .. msg .. '"')
  vim.cmd [[echohl None]]
end)

return {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end
}
