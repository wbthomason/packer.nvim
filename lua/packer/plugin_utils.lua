local a = require('packer.async')
local jobs = require('packer.jobs')
local util = require('packer.util')
local result = require('packer.result')
local log = require('packer.log')

local await = a.wait

local config = nil
local plugin_utils = {}
plugin_utils.cfg = function(_config) config = _config end

plugin_utils.custom_plugin_type = 'custom'
plugin_utils.local_plugin_type = 'local'
plugin_utils.git_plugin_type = 'git'

plugin_utils.guess_type = function(plugin)
  if plugin.installer then
    plugin.type = plugin_utils.custom_plugin_type
  elseif vim.fn.isdirectory(plugin.path) ~= 0 then
    plugin.url = plugin.path
    plugin.type = plugin_utils.local_plugin_type
  elseif string.sub(plugin.path, 1, 6) == 'git://' or string.sub(plugin.path, 1, 4) == 'http'
    or string.match(plugin.path, '@') then
    plugin.url = plugin.path
    plugin.type = plugin_utils.git_plugin_type
  else
    local path = table.concat(vim.split(plugin.path, "\\", true), "/")
    plugin.url = 'https://github.com/' .. path
    plugin.type = plugin_utils.git_plugin_type
  end
end

plugin_utils.guess_dir_type = function(dir)
  local globdir = vim.fn.glob(dir)
  local dir_type = (vim.loop.fs_lstat(globdir) or {type = 'noexist'}).type

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
  vim.list_extend(txts, vim.fn.glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))
  local tags = vim.fn.glob(util.join_paths(dir, 'tags'), true, true)
  vim.list_extend(tags, vim.fn.glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))
  local txt_ftimes = util.map(vim.fn.getftime, txts)
  local tag_ftimes = util.map(vim.fn.getftime, tags)
  if #txt_ftimes == 0 then return false end
  if #tag_ftimes == 0 then return true end
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

plugin_utils.update_rplugins = vim.schedule_wrap(function() vim.cmd [[silent UpdateRemotePlugins]] end)

plugin_utils.ensure_dirs = function()
  if vim.fn.isdirectory(config.opt_dir) == 0 then vim.fn.mkdir(config.opt_dir, 'p') end

  if vim.fn.isdirectory(config.start_dir) == 0 then vim.fn.mkdir(config.start_dir, 'p') end
end

plugin_utils.find_missing_plugins = function(plugins, opt_plugins, start_plugins)
  if opt_plugins == nil or start_plugins == nil then
    opt_plugins, start_plugins = plugin_utils.list_installed_plugins()
  end

  -- NOTE/TODO: In the case of a plugin gaining/losing an alias, this will force a clean and
  -- reinstall
  local missing_plugins = {}
  for _, plugin_name in ipairs(vim.tbl_keys(plugins)) do
    local plugin = plugins[plugin_name]

    local plugin_path = util.join_paths(config[plugin.opt and 'opt_dir' or 'start_dir'],
                                        plugin.short_name)
    local plugin_installed = (plugin.opt and opt_plugins or start_plugins)[plugin_path]

    if not plugin_installed or plugin.type ~= plugin_utils.guess_dir_type(plugin_path) then
      table.insert(missing_plugins, plugin_name)
    end
  end

  return missing_plugins
end

plugin_utils.load_plugin = function(plugin)
  if plugin.opt then
    vim.cmd('packadd ' .. plugin.short_name)
  else
    vim.o.runtimepath = vim.o.runtimepath .. ',' .. plugin.install_path
    for _, pat in ipairs({
      table.concat({'plugin', '**', '*.vim'}, util.get_separator()),
      table.concat({'after', 'plugin', '**', '*.vim'}, util.get_separator())
    }) do
      local path = util.join_paths(plugin.install_path, pat)
      local glob_ok, files = pcall(vim.fn.glob, path, false, true)
      if not glob_ok then
        if string.find(files, 'E77') then
          vim.cmd('silent exe "source ' .. path .. '"')
        else
          error(files)
        end
      elseif #files > 0 then
        for _, file in ipairs(files) do vim.cmd('silent exe "source ' .. file .. '"') end
      end
    end
  end
end

plugin_utils.post_update_hook = function(plugin, disp)
  local plugin_name = util.get_plugin_full_name(plugin)
  return a.sync(function()
    if plugin.run or not plugin.opt then
      await(vim.schedule)
      plugin_utils.load_plugin(plugin)
    end
    if plugin.run then
      disp:task_update(plugin_name, 'running post update hook...')
      if type(plugin.run) == 'function' then
        if pcall(plugin.run, plugin) then
          return result.ok()
        else
          return result.err({msg = 'Error running post update hook'})
        end
      elseif type(plugin.run) == 'string' then
        if string.sub(plugin.run, 1, 1) == ':' then
          await(a.main)
          vim.cmd(string.sub(plugin.run, 2))
          return result.ok()
        else
          local hook_output = {err = {}, output = {}}
          local hook_callbacks = {
            stderr = jobs.logging_callback(hook_output.err, hook_output.output, nil, disp,
                                           plugin_name),
            stdout = jobs.logging_callback(hook_output.err, hook_output.output, nil, disp,
                                           plugin_name)
          }
          local cmd = {
            os.getenv('SHELL'), '-c', 'cd ' .. plugin.install_path .. ' && ' .. plugin.run
          }
          return await(jobs.run(cmd, {capture_output = hook_callbacks})):map_err(
                   function(err)
              return {
                msg = string.format('Error running post update hook: %s',
                                    table.concat(hook_output.output, '\n')),
                data = err
              }
            end)
        end
      else
        -- TODO/NOTE: This case should also capture output in case of error. The minor difficulty is
        -- what to do if the plugin's run table (i.e. this case) already specifies output handling.
        return await(jobs.run(plugin.run))
      end
    else
      return result.ok()
    end
  end)
end

return plugin_utils
