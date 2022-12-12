local Plugin = require('packer.plugin').Plugin

local event_plugins = {}

return function(plugins, loader)
   local new_events = {}
   for _, plugin in pairs(plugins) do
      if plugin.event then
         for _, event in ipairs(plugin.event) do
            if not event_plugins[event] then
               event_plugins[event] = {}
               new_events[#new_events + 1] = event
            end

            table.insert(event_plugins[event], plugin)
         end
      end
   end

   for _, event in ipairs(new_events) do
      local names = vim.tbl_map(function(e)
         return e.name
      end, event_plugins[event])


      local ev, pattern = unpack(vim.split(event, '%s+'))
      vim.api.nvim_create_autocmd(ev, {
         pattern = pattern,
         once = true,
         desc = 'packer.nvim lazy load: ' .. table.concat(names, ', '),
         callback = function()
            loader(event_plugins[event])


         end,
      })
   end
end