local a = require 'packer.async'
local util = require 'packer.util'
local log = require 'packer.log'
local config = require 'packer.config'

local fn = vim.fn
local uv = vim.loop

local record M
  record FSState
    opt     : {string:string}
    start   : {string:string}
    missing : {string:string}
    dirty   : {string:string}
  end

  record Error
    msg: string
    data: any
  end

  get_fs_state: function({string:Plugin}): FSState
end

local function guess_dir_type(dir: string): Plugin.Type
  local globdir = fn.glob(dir)
  local dir_type = (uv.fs_lstat(globdir) or { type = 'noexist' }).type

  -- NOTE: We're assuming here that:
  --
  -- 1. users only create custom plugins for non-git repos;
  -- 2. custom plugins don't use symlinks to install;
  --
  -- otherwise, there's no consistent way to tell from a dir alone…
  if dir_type == 'link' then
    return 'local'
  end

  if uv.fs_stat(globdir .. '/.git') then
    return 'git'
  end

  return 'unknown'
end

function M.list_installed_plugins(): {string:string}, {string:string}
  local opt_plugins = {}
  local start_plugins = {}
  local opt_dir_handle = uv.fs_opendir(config.opt_dir, nil, 50)
  if opt_dir_handle then
    local opt_dir_items = uv.fs_readdir(opt_dir_handle)
    while opt_dir_items do
      for _, item in ipairs(opt_dir_items) do
        opt_plugins[util.join_paths(config.opt_dir, item.name)] = item.name
      end

      opt_dir_items = uv.fs_readdir(opt_dir_handle)
    end
  end

  local start_dir_handle = uv.fs_opendir(config.start_dir, nil, 50)
  if start_dir_handle then
    local start_dir_items = uv.fs_readdir(start_dir_handle)
    while start_dir_items do
      for _, item in ipairs(start_dir_items) do
        start_plugins[util.join_paths(config.start_dir, item.name)] = item.name
      end

      start_dir_items = uv.fs_readdir(start_dir_handle)
    end
  end

  return opt_plugins, start_plugins
end

local find_dirty_plugins = a.sync(function(
  plugins: {string:Plugin},
  -- Plugins installed in config.opt_dir
  opt_plugins: {string:string},
  -- Plugins installed in config.start_dir
  start_plugins: {string:string}
): {string:string}, {string:string}

  local dirty_plugins = {}
  local missing_plugins = {}

  for name, _ in pairs(opt_plugins) do
    if not plugins[name] or not plugins[name].opt then
      dirty_plugins[util.join_paths(config.opt_dir, name)] = name
    end
  end

  for name, _ in pairs(start_plugins) do
    if not plugins[name] or plugins[name].opt then
      dirty_plugins[util.join_paths(config.start_dir, name)] = name
    end
  end

  for plugin_name, plugin in pairs(plugins) do
    local plugin_installed = false
    for _, name in pairs(plugin.opt and opt_plugins or start_plugins) do
      if name == plugin_name then
        plugin_installed = true
        break
      end
    end

    if not plugin_installed then
      missing_plugins[plugin.install_path] = plugin_name
    else
      a.main()
      local guessed_type = guess_dir_type(plugin.install_path)
      if plugin.type ~= guessed_type then
        dirty_plugins[plugin.install_path] = plugin_name
      elseif guessed_type == 'git' then
        local remote = require'packer.plugin_types.git'.remote_url(plugin)
        if remote then
          -- Form a Github-style user/repo string
          local parts = vim.split(remote, '[:/]')
          local repo_name = parts[#parts - 1] .. '/' .. parts[#parts]
          repo_name = repo_name:gsub('%.git', '')

          -- Also need to test for "full URL" plugin names, but normalized to get rid of the
          -- protocol
          local normalized_remote = remote:gsub('https://', ''):gsub('ssh://git@', '')
          local normalized_plugin_url = plugin.url:gsub('https://', ''):gsub('ssh://git@', ''):gsub('\\', '/')
          if (normalized_remote ~= normalized_plugin_url) and (repo_name ~= normalized_plugin_url) then
            dirty_plugins[plugin.install_path] = plugin_name
          end
        end
      end
    end
  end

  return dirty_plugins, missing_plugins
end, 3)

M.get_fs_state = a.sync(function(plugins: {string:Plugin}): M.FSState
  log.debug 'Updating FS state'
  local opt, start = M.list_installed_plugins()
  local dirty, missing = find_dirty_plugins(plugins, opt, start)
  return {
    opt     = opt,
    start   = start,
    missing = missing,
    dirty   = dirty
  }
end, 1)

return M
