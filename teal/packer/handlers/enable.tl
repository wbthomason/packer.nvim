-- If a plugin spec contains 'cond' and is a function, load the plugin if cond
-- evaluates to true
--
-- The main use case for this is for users of vscode-neovim who load some
-- plugins only in normal Nvim and not in embedded Nvim

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  for _, plugin in pairs(plugins) do
    local enable = plugin.enable
    if enable is function(): boolean then
      if enable() then
        loader({plugin})
      end
    elseif enable then
      loader({plugin})
    end
  end
end
