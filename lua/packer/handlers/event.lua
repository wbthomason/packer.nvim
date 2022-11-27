return function(plugins, loader)
   local events = {}

   for _, plugin in pairs(plugins) do
      if plugin.event then
         for _, event in ipairs(plugin.event) do
            events[event] = events[event] or {}
            table.insert(events[event], plugin)
         end
      end
   end

   for event, eplugins in pairs(events) do

      local ev, pattern = unpack(vim.split(event, '%s+'))

      vim.api.nvim_create_autocmd(ev, {
         pattern = pattern,
         once = true,
         callback = function()
            loader(eplugins)
            vim.api.nvim_exec_autocmds(event, { modeline = false })
         end,
      })
   end
end