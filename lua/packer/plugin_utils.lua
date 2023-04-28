local a = require 'packer.async'
local jobs = require 'packer.jobs'
local util = require 'packer.util'
local result = require 'packer.result'
local log = require 'packer.log'

local await = a.wait

local config = nil
local plugin_utils = {}
plugin_utils.cfg = function(_config)
  config = _config
end

plugin_utils.custom_plugin_type = 'custom'
plugin_utils.local_plugin_type = 'local'
plugin_utils.git_plugin_type = 'git'

plugin_utils.guess_type = function(plugin)
  if plugin.installer then
    plugin.type = plugin_utils.custom_plugin_type
  elseif vim.fn.isdirectory(plugin.path) ~= 0 then
    plugin.url = plugin.path
    plugin.type = plugin_utils.local_plugin_type
  elseif
    string.sub(plugin.path, 1, 6) == 'git://'
    or string.sub(plugin.path, 1, 6) == 'ssh://'
    or string.sub(plugin.path, 1, 10) == 'git+ssh://'
    or string.sub(plugin.path, 1, 10) == 'ssh+git://'
    or string.sub(plugin.path, 1, 4) == 'http'
    or string.match(plugin.path, '@')
  then
    plugin.url = plugin.path
    plugin.type = plugin_utils.git_plugin_type
  else
    local path = table.concat(vim.split(plugin.path, '\\', true), '/')
    plugin.url = string.format(config.git.default_url_format, path)
    plugin.type = plugin_utils.git_plugin_type
  end
end

plugin_utils.guess_dir_type = function(dir)
  local globdir = vim.fn.glob(dir)
  local dir_type = (vim.loop.fs_lstat(globdir) or { type = 'noexist' }).type

  --[[ NOTE: We're assuming here that:
             1. users only create custom plugins for non-git repos;
             2. custom plugins don't use symlinks to install;
             otherwise, there's no consistent way to tell from a dir alone… ]]
  if dir_type == 'link' then
    return plugin_utils.local_plugin_type
  elseif vim.loop.fs_stat(globdir .. '/.git') then
    return plugin_utils.git_plugin_type
  elseif dir_type ~= 'noexist' then
    return plugin_utils.custom_plugin_type
  end
end

plugin_utils.helptags_stale = function(dir)
  -- Adapted directly from minpac.vim
  local txts = vim.fn.glob(util.join_paths(dir, '*.txt'), true, true)
  vim.list_extend(txts, vim.fn.glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))
  local tags = vim.fn.glob(util.join_paths(dir, 'tags'), true, true)
  vim.list_extend(tags, vim.fn.glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))
  local txt_ftimes = util.map(vim.fn.getftime, txts)
  local tag_ftimes = util.map(vim.fn.getftime, tags)
  if #txt_ftimes == 0 then
    return false
  end
  if #tag_ftimes == 0 then
    return true
  end
  local txt_newest = math.max(unpack(txt_ftimes))
  local tag_oldest = math.min(unpack(tag_ftimes))
  return txt_newest > tag_oldest
end

plugin_utils.update_helptags = vim.schedule_wrap(function(...)
  for _, dir in ipairs(...) do
    local doc_dir = util.join_paths(dir, 'doc')
    if plugin_utils.helptags_stale(doc_dir) then
      log.info('Updating helptags for ' .. doc_dir)
      vim.cmd('silent! helptags ' .. vim.fn.fnameescape(doc_dir))
    end
  end
end)

plugin_utils.update_rplugins = vim.schedule_wrap(function()
  if vim.fn.exists ':UpdateRemotePlugins' == 2 then
    vim.cmd [[silent UpdateRemotePlugins]]
  end
end)

plugin_utils.ensure_dirs = function()
  if vim.fn.isdirectory(config.opt_dir) == 0 then
    vim.fn.mkdir(config.opt_dir, 'p')
  end

  if vim.fn.isdirectory(config.start_dir) == 0 then
    vim.fn.mkdir(config.start_dir, 'p')
  end
end

plugin_utils.list_installed_plugins = function()
  local opt_plugins = {}
  local start_plugins = {}
  local opt_dir_handle = vim.loop.fs_opendir(config.opt_dir, nil, 50)
  if opt_dir_handle then
    local opt_dir_items = vim.loop.fs_readdir(opt_dir_handle)
    while opt_dir_items do
      for _, item in ipairs(opt_dir_items) do
        opt_plugins[util.join_paths(config.opt_dir, item.name)] = true
      end

      opt_dir_items = vim.loop.fs_readdir(opt_dir_handle)
    end
  end

  local start_dir_handle = vim.loop.fs_opendir(config.start_dir, nil, 50)
  if start_dir_handle then
    local start_dir_items = vim.loop.fs_readdir(start_dir_handle)
    while start_dir_items do
      for _, item in ipairs(start_dir_items) do
        start_plugins[util.join_paths(config.start_dir, item.name)] = true
      end

      start_dir_items = vim.loop.fs_readdir(start_dir_handle)
    end
  end

  return opt_plugins, start_plugins
end

plugin_utils.find_missing_plugins = function(plugins, opt_plugins, start_plugins)
  return a.sync(function()
    if opt_plugins == nil or start_plugins == nil then
      opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
    end

    -- NOTE/TODO: In the case of a plugin gaining/losing an alias, this will force a clean and
    -- reinstall
    local missing_plugins = {}
    for _, plugin_name in ipairs(vim.tbl_keys(plugins)) do
      local plugin = plugins[plugin_name]
      if not plugin.disable then
        local plugin_path = util.join_paths(config[plugin.opt and 'opt_dir' or 'start_dir'], plugin.short_name)
        local plugin_installed = (plugin.opt and opt_plugins or start_plugins)[plugin_path]

        await(a.main)
        local guessed_type = plugin_utils.guess_dir_type(plugin_path)
        if not plugin_installed or plugin.type ~= guessed_type then
          missing_plugins[plugin_name] = true
        elseif guessed_type == plugin_utils.git_plugin_type then
          local r = await(plugin.remote_url())
          local remote = r.ok and r.ok.remote or nil
          if remote then
            -- Form a Github-style user/repo string
            local parts = vim.split(remote, '[:/]')
            local repo_name = parts[#parts - 1] .. '/' .. parts[#parts]
            repo_name = repo_name:gsub('%.git', '')

            -- Also need to test for "full URL" plugin names, but normalized to get rid of the
            -- protocol
            local normalized_remote = remote:gsub('https://', ''):gsub('ssh://git@', '')
            local normalized_plugin_name = plugin.name:gsub('https://', ''):gsub('ssh://git@', ''):gsub('\\', '/')
            if (normalized_remote ~= normalized_plugin_name) and (repo_name ~= normalized_plugin_name) then
              missing_plugins[plugin_name] = true
            end
          end
        end
      end
    end

    return missing_plugins
  end)
end

plugin_utils.get_fs_state = function(plugins)
  log.debug 'Updating FS state'
  local opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
  return a.sync(function()
    local missing_plugins = await(plugin_utils.find_missing_plugins(plugins, opt_plugins, start_plugins))
    return { opt = opt_plugins, start = start_plugins, missing = missing_plugins }
  end)
end

plugin_utils.load_plugin = function(plugin)
  if plugin.opt then
    vim.cmd('packadd ' .. plugin.short_name)
  else
    vim.o.runtimepath = vim.o.runtimepath .. ',' .. plugin.install_path
    for _, pat in ipairs {
      table.concat({ 'plugin', '**/*.vim' }, util.get_separator()),
      table.concat({ 'after', 'plugin', '**/*.vim' }, util.get_separator()),
    } do
      local path = util.join_paths(plugin.install_path, pat)
      local glob_ok, files = pcall(vim.fn.glob, path, false, true)
      if not glob_ok then
        if string.find(files, 'E77') then
          vim.cmd('silent exe "source ' .. path .. '"')
        else
          error(files)
        end
      elseif #files > 0 then
        for _, file in ipairs(files) do
          file = file:gsub('\\', '/')
          vim.cmd('silent exe "source ' .. file .. '"')
        end
      end
    end
  end
end

plugin_utils.post_update_hook = function(plugin, disp)
  local plugin_name = util.get_plugin_full_name(plugin)
  return a.sync(function()
    if plugin.run or not plugin.opt then
      await(a.main)
      plugin_utils.load_plugin(plugin)
    end

    if plugin.run then
      if type(plugin.run) ~= 'table' then
        plugin.run = { plugin.run }
      end
      disp:task_update(plugin_name, 'running post update hooks...')
      local hook_result = result.ok()
      for _, task in ipairs(plugin.run) do
        if type(task) == 'function' then
          local success, err = pcall(task, plugin, disp)
          if not success then
            return result.err {
              msg = 'Error running post update hook: ' .. vim.inspect(err),
            }
          end
        elseif type(task) == 'string' then
          if string.sub(task, 1, 1) == ':' then
            await(a.main)
            vim.cmd(string.sub(task, 2))
          else
            local hook_output = { err = {}, output = {} }
            local hook_callbacks = {
              stderr = jobs.logging_callback(hook_output.err, hook_output.output, nil, disp, plugin_name),
              stdout = jobs.logging_callback(hook_output.err, hook_output.output, nil, disp, plugin_name),
            }
            local cmd
            local shell = os.getenv 'SHELL' or vim.o.shell
            if shell:find 'cmd.exe$' then
              cmd = { shell, '/c', task }
            else
              cmd = { shell, '-c', task }
            end
            hook_result = await(jobs.run(cmd, { capture_output = hook_callbacks, cwd = plugin.install_path })):map_err(
              function(err)
                return {
                  msg = string.format('Error running post update hook: %s', table.concat(hook_output.output, '\n')),
                  data = err,
                }
              end
            )

            if hook_result.err then
              return hook_result
            end
          end
        else
          -- TODO/NOTE: This case should also capture output in case of error. The minor difficulty is
          -- what to do if the plugin's run table (i.e. this case) already specifies output handling.

          hook_result = await(jobs.run(task)):map_err(function(err)
            return {
              msg = string.format('Error running post update hook: %s', vim.inspect(err)),
              data = err,
            }
          end)

          if hook_result.err then
            return hook_result
          end
        end
      end

      return hook_result
    else
      return result.ok()
    end
  end)
end

return plugin_utils
