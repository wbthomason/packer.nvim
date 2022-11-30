local util = require 'packer.handlers.util'

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  local commands: {string:{Plugin}} = {}
  for _, plugin in pairs(plugins) do
    if plugin.cmd then
      for _, cmd in ipairs(plugin.cmd) do
        commands[cmd] = commands[cmd] or {}
        table.insert(commands[cmd], plugin)
      end
    end
  end

  for cmd, cplugins in pairs(commands) do

    util.register_destructor(cplugins, function()
      vim.api.nvim_del_user_command(cmd)
    end)

    vim.api.nvim_create_user_command(cmd,
      function(args: vim.api.UserCmdParams)
        loader(cplugins)

        local lines = args.line1 == args.line2 and '' or (args.line1 .. ',' .. args.line2)
        vim.cmd(string.format(
          '%s %s%s%s %s',
          args.mods or '',
          lines,
          cmd,
          args.bang and '!' or '',
          args.args
        ))
      end,
      { complete = 'file', bang = true, nargs = '*' }
    )
  end
end
