-- If a plugin spec contains 'cond' and is a function, load the plugin if cond
-- evaluates to true
--
-- The main use case for this is for users of vscode-neovim who load some
-- plugins only in normal Nvim and not in embedded Nvim

return function(cond_plugins: {string:Plugin}, loader: function({Plugin}))
  for _, plugin in pairs(cond_plugins) do
    if type(plugin.cond) == 'function' and plugin.cond() then
      loader({plugin})
    end
  end
end
