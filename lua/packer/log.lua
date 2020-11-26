local echo_special = vim.schedule_wrap(function(msg, hl)
  vim.cmd('echohl ' .. hl)
  vim.cmd('echom "[packer] ' .. msg .. '"')
  vim.cmd [[echohl None]]
end)

local config = nil

local log = {
  info = function(msg) echo_special(msg, 'None') end,
  error = function(msg) echo_special(msg, 'ErrorMsg') end,
  warning = function(msg) echo_special(msg, 'WarningMsg') end,
  debug = function(msg)
    if config.debug then
      echo_special(msg, 'WarningMsg')
    end
  end,
  cfg = function(_config) config = _config.log end
}

return log
