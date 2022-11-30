local util = require 'packer.handlers.util'

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  local keymaps: {{string,string}:{Plugin}} = {}
  for _, plugin in pairs(plugins) do
    if plugin.keys then
      for _, keymap in ipairs(plugin.keys) do
        keymaps[keymap] = keymaps[keymap] or {}
        table.insert(keymaps[keymap], plugin)
      end
    end
  end

  for keymap, kplugins in pairs(keymaps) do
    local names = vim.tbl_map(function(e: Plugin): string
      return e.name
    end, kplugins)

    util.register_destructor(kplugins, function()
      vim.keymap.del(keymap[1], keymap[2])
    end)

    vim.keymap.set(keymap[1], keymap[2], function()
      loader(kplugins)
      vim.api.nvim_feedkeys(keymap[2], keymap[1], false)
    end, {
        desc = 'Packer lazy load: '..table.concat(names, ', '),
        silent = true
      })
  end
end
