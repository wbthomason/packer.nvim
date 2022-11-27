-- If a plugin spec contains 'cond' and is a function, load the plugin if cond
-- evaluates to true
--
-- The main use case for this is for users of vscode-neovim who load some
-- plugins only in normal Nvim and not in embedded Nvim

return function(cond_plugins: {string:Plugin}, loader: function({Plugin}))
  for _, plugin in pairs(cond_plugins) do
    local cond = plugin.cond
    if cond is function(): boolean then
      if cond() then
        loader({plugin})
      end
    elseif cond then
      loader({plugin})
    end
  end
end
