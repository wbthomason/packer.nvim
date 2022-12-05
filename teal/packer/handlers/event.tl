local event_plugins: {string:{Plugin}} = {}

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  local new_events: {string} = {}
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
    -- Handle 'User Foo' events
    local ev, pattern = unpack(vim.split(event, '%s+'))
    vim.api.nvim_create_autocmd(ev, {
      pattern = pattern,
      once = true,
      callback = function()
        loader(event_plugins[event])
        vim.api.nvim_exec_autocmds(event, { modeline = false })
      end
    })
  end
end
