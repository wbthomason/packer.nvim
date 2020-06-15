local util  = require('packer/util')
local slice = util.slice

local config = nil
local plugin_utils = {}
plugin_utils.cfg = function(_config)
  config = _config
end

plugin_utils.guess_type = function(plugin)
  if plugin.installer then
    plugin.type = 'custom'
  elseif vim.fn.isdirectory(plugin.path) ~= 0 then
    plugin.url = plugin.path
    plugin.type = 'local'
  elseif
    slice(plugin.path, 1, 6) == 'git://'
    or slice(plugin.path, 1, 4) == 'http'
    or string.match(plugin.path, '@')
  then
    plugin.url = plugin.path
    plugin.type = 'git'
  else
    plugin.url = 'https://github.com/' .. plugin.path
    plugin.type = 'git'
  end
end

plugin_utils.list_installed_plugins = function()
  local opt_plugins = {}
  local start_plugins = {}
  for _, path in ipairs(vim.fn.globpath(config.opt_dir, '*', true, true)) do
    opt_plugins[path] = true
  end

  for _, path in ipairs(vim.fn.globpath(config.start_dir, '*', true, true)) do
    start_plugins[path] = true
  end

  return opt_plugins, start_plugins
end

plugin_utils.helptags_stale = function(dir)
  -- Adapted directly from minpac.vim
  local txts = vim.fn.glob(util.join_paths(dir, '*.txt'), true, true)
  txts = vim.list_extend(txts, vim.fn.glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))
  local tags = vim.fn.glob(util.join_paths(dir, 'tags'), true, true)
  tags = vim.list_extend(tags, vim.fn.glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))
  local txt_newest = math.max(unpack(util.map(vim.fn.getftime, txts)))
  local tag_oldest = math.min(unpack(util.map(vim.fn.getftime, tags)))
  return txt_newest > tag_oldest
end

plugin_utils.update_helptags = vim.schedule_wrap(function(...)
  for _, dir in ipairs(...) do
    local doc_dir = util.join_paths(dir, 'doc')
    if plugin_utils.helptags_stale(doc_dir) then
      vim.api.nvim_command('silent! helptags ' .. vim.fn.fnameescape(doc_dir))
    end
  end
end)

plugin_utils.update_rplugins = vim.schedule_wrap(function()
  vim.api.nvim_command('UpdateRemotePlugins')
end)

plugin_utils.ensure_dirs = function()
  if vim.fn.isdirectory(config.opt_dir) == 0 then
    vim.fn.mkdir(config.opt_dir, 'p')
  end

  if vim.fn.isdirectory(config.start_dir) == 0 then
    vim.fn.mkdir(config.start_dir, 'p')
  end
end

plugin_utils.find_missing_plugins = function(plugins, opt_plugins, start_plugins)
  if opt_plugins == nil or  start_plugins == nil then
    opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
  end

  local missing_plugins = {}
  for _, plugin_name in ipairs(vim.tbl_keys(plugins)) do
    local plugin = plugins[plugin_name]
    if
      (not plugin.opt
      and not start_plugins[util.join_paths(config.start_dir, plugin.short_name)])
      or (plugin.opt
      and not opt_plugins[util.join_paths(config.opt_dir, plugin.short_name)])
    then
      table.insert(missing_plugins, plugin_name)
    end
  end

  return missing_plugins
end

return plugin_utils
