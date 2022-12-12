-- If a plugin spec contains 'cond' and is a function, load the plugin if cond
-- evaluates to true
--
-- Also pass the load function as an argument to cond so the user can implement
-- their own lazy loader.
--
-- The main use case for this is for users of vscode-neovim who load some
-- plugins only in normal Nvim and not in embedded Nvim

local Plugin = require'packer.plugin'.Plugin

local type Loader = function(function()): boolean

return function(plugins: {string:Plugin}, loader: function({Plugin}))
  for _, plugin in pairs(plugins) do
    local cond = plugin.cond

    local function load_plugin()
      loader({plugin})
    end

    if cond is {Loader} then
      for _, c in ipairs(cond) do
        if c(load_plugin) then
          load_plugin()
        end
      end
    elseif cond is Loader then
      if cond(load_plugin) then
        load_plugin()
      end
    end
    -- else cond must be false
  end
end
