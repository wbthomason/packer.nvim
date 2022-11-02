
return function(key_plugins, loader)
   local keymaps = {}
   for _, plugin in pairs(key_plugins) do
      for _, keymap in ipairs(plugin.keys) do
         keymaps[keymap] = keymaps[keymap] or {}
         table.insert(keymaps[keymap], plugin)
      end
   end

   for keymap, kplugins in pairs(keymaps) do
      local names = vim.tbl_map(function(e)
         return e.name
      end, kplugins)

      vim.keymap.set(keymap[1], keymap[2], function()
         vim.keymap.del(keymap[1], keymap[2])
         loader(kplugins)
         vim.api.nvim_feedkeys(keymap[2], keymap[1], false)
      end, {
         desc = 'Packer lazy load: ' .. table.concat(names, ', '),
         silent = true,
      })
   end
end
