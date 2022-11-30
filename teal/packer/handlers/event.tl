local util = require 'packer.handlers.util'

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  local events: {string:{Plugin}} = {}

  for _, plugin in pairs(plugins) do
    if plugin.event then
      for _, event in ipairs(plugin.event) do
        events[event] = events[event] or {}
        table.insert(events[event], plugin)
      end
    end
  end

  for event, eplugins in pairs(events) do
    -- Handle 'User Foo' events
    local ev, pattern = unpack(vim.split(event, '%s+'))

    local id = vim.api.nvim_create_autocmd(ev, {
      pattern = pattern,
      once = true,
      callback = function()
        loader(eplugins)
        vim.api.nvim_exec_autocmds(event, { modeline = false })
      end
    })

    util.register_destructor(eplugins, function()
      pcall(vim.api.nvim_del_autocmd, id)
    end)

  end
end
