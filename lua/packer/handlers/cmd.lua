local command_plugins = {}

return function(plugins, loader)
   local new_commands = {}
   for _, plugin in pairs(plugins) do
      if plugin.cmd then
         for _, cmd in ipairs(plugin.cmd) do
            if not command_plugins[cmd] then
               command_plugins[cmd] = {}
               new_commands[#new_commands + 1] = cmd
            end

            table.insert(command_plugins[cmd], plugin)
         end
      end
   end

   for _, cmd in ipairs(new_commands) do

      vim.api.nvim_create_user_command(cmd,
      function(args)
         vim.api.nvim_del_user_command(cmd)
         loader(command_plugins[cmd])
         local lines = args.line1 == args.line2 and '' or (args.line1 .. ',' .. args.line2)
         vim.cmd(string.format(
         '%s %s%s%s %s',
         args.mods or '',
         lines,
         cmd,
         args.bang and '!' or '',
         args.args))

      end,
      { complete = 'file', bang = true, nargs = '*' })

   end
end