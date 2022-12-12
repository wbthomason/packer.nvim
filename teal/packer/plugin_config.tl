local plugin_configs: {function()} = {}

local M = {}

function M.add(cfg: function())
  plugin_configs[#plugin_configs+1] = cfg
end

function M.run()
  for _, cfg in ipairs(plugin_configs) do
    cfg()
  end
  plugin_configs = {}
end

return M
