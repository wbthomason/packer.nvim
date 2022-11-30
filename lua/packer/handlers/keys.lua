local keymap_plugins = {}

return function(plugins, loader)
   local new_keymaps = {}
   for _, plugin in pairs(plugins) do
      if plugin.keys then
         for _, keymap in ipairs(plugin.keys) do
            if not keymap_plugins[keymap] then
               keymap_plugins[keymap] = {}
               new_keymaps[#new_keymaps + 1] = keymap
            end

            table.insert(keymap_plugins[keymap], plugin)
         end
      end
   end

   for _, keymap in ipairs(new_keymaps) do
      local kplugins = keymap_plugins[keymap]
      local names = vim.tbl_map(function(e)
         return e.name
      end, kplugins)

      vim.keymap.set(keymap[1], keymap[2], function()
         vim.keymap.del(keymap[1], keymap[2])
         loader(kplugins)
         if keymap[1] == 'n' then
            vim.api.nvim_input(keymap[2])
         else
            vim.api.nvim_feedkeys(keymap[2], keymap[1], false)
         end
      end, {
         desc = 'packer.nvim lazy load: ' .. table.concat(names, ', '),
         silent = true,
      })
   end
end
