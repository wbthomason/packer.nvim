-- Completion user plugins
-- Intended to provide completion for PackerUpdate/Sync/Install command
local function plugin_complete(lead, _)
  local plugins = require 'packer.plugin'.plugins
  local completion_list = vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, vim.tbl_keys(plugins))
  table.sort(completion_list)
  return completion_list
end

for k, v in pairs {
  install = { 'PackerInstall', plugin_complete},
  update  = { 'PackerUpdate' , plugin_complete},
  sync    = { 'PackerSync'                    },
  clean   = { 'PackerClean'                   },
  status  = { 'PackerStatus'                  },
} do
  vim.api.nvim_create_user_command(v[1], function(args)
    return require('packer.actions')[k](unpack(args.fargs))
  end, { nargs = '*', complete = v[2] })
end

require'packer.plugin_config'.run()
