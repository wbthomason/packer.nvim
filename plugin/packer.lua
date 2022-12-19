
vim.api.nvim_create_user_command(
  'Packer',
  function(args)
    return require('packer.cli').run(args)
  end, {
    nargs = '*',
    complete = function(arglead, line)
      return require('packer.cli').complete(arglead, line)
    end
  }
)

-- Run 'config' keys in user spec.
require'packer.plugin_config'.run()
