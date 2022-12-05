local packer_load = nil
local cmd = vim.api.nvim_command
local fmt = string.format

local function verify_conditions(conds, name)
  if conds == nil then
    return true
  end
  for _, cond in ipairs(conds) do
    local success, result
    if type(cond) == 'boolean' then
      result = cond
    elseif type(cond) == 'string' then
      success, result = pcall(loadstring(cond))
      if not success then
        vim.schedule(function()
          vim.api.nvim_notify(
            'packer.nvim: Error running cond for ' .. name .. ': ' .. result,
            vim.log.levels.ERROR,
            {}
          )
        end)
        return false
      end
    end
    if result == false then
      return false
    end
  end
  return true
end

local function loader_clear_loaders(plugin)
  if plugin.commands then
    for _, del_cmd in ipairs(plugin.commands) do
      cmd('silent! delcommand ' .. del_cmd)
    end
  end

  if plugin.keys then
    for _, key in ipairs(plugin.keys) do
      cmd(fmt('silent! %sunmap %s', key[1], key[2]))
    end
  end
end

local function loader_apply_config(plugin, name)
  if plugin.config then
    for _, config_line in ipairs(plugin.config) do
      local success, err = pcall(loadstring(config_line), name, plugin)
      if not success then
        vim.schedule(function()
          vim.api.nvim_notify('packer.nvim: Error running config for ' .. name .. ': ' .. err, vim.log.levels.ERROR, {})
        end)
      end
    end
  end
end

local function loader_apply_wants(plugin, plugins)
  if plugin.wants then
    for _, wanted_name in ipairs(plugin.wants) do
      packer_load({ wanted_name }, {}, plugins)
    end
  end
end

local function loader_apply_after(plugin, plugins, name)
  if plugin.after then
    for _, after_name in ipairs(plugin.after) do
      local after_plugin = plugins[after_name]
      after_plugin.load_after[name] = nil
      if next(after_plugin.load_after) == nil then
        packer_load({ after_name }, {}, plugins)
      end
    end
  end
end

local function apply_cause_side_effects(cause)
  if cause.cmd then
    local lines = cause.l1 == cause.l2 and '' or (cause.l1 .. ',' .. cause.l2)
    -- This is a hack to deal with people who haven't recompiled after updating to the new command
    -- creation logic
    local bang = ''
    if type(cause.bang) == 'string' then
      bang = cause.bang
    elseif type(cause.bang) == 'boolean' and cause.bang then
      bang = '!'
    end
    cmd(fmt('%s %s%s%s %s', cause.mods or '', lines, cause.cmd, bang, cause.args))
  elseif cause.keys then
    local extra = ''
    while true do
      local c = vim.fn.getchar(0)
      if c == 0 then
        break
      end
      extra = extra .. vim.fn.nr2char(c)
    end

    if cause.prefix then
      local prefix = vim.v.count ~= 0 and vim.v.count or ''
      prefix = prefix .. '"' .. vim.v.register .. cause.prefix
      if vim.fn.mode 'full' == 'no' then
        if vim.v.operator == 'c' then
          prefix = '' .. prefix
        end
        prefix = prefix .. vim.v.operator
      end

      vim.fn.feedkeys(prefix, 'n')
    end

    local escaped_keys = vim.api.nvim_replace_termcodes(cause.keys .. extra, true, true, true)
    vim.api.nvim_feedkeys(escaped_keys, 'm', true)
  elseif cause.event then
    cmd(fmt('doautocmd <nomodeline> %s', cause.event))
  elseif cause.ft then
    cmd(fmt('doautocmd <nomodeline> %s FileType %s', 'filetypeplugin', cause.ft))
    cmd(fmt('doautocmd <nomodeline> %s FileType %s', 'filetypeindent', cause.ft))
    cmd(fmt('doautocmd <nomodeline> %s FileType %s', 'syntaxset', cause.ft))
  end
end

packer_load = function(names, cause, plugins, force)
  local some_unloaded = false
  local needs_bufread = false
  local num_names = #names
  for i = 1, num_names do
    local plugin = plugins[names[i]]
    if not plugin then
      local err_message = 'Error: attempted to load ' .. names[i] .. ' which is not present in plugins table!'
      vim.notify(err_message, vim.log.levels.ERROR, { title = 'packer.nvim' })
      error(err_message)
    end

    if not plugin.loaded then
      loader_clear_loaders(plugin)
      if force or verify_conditions(plugin.cond, names[i]) then
        -- Set the plugin as loaded before config is run in case something in the config tries to load
        -- this same plugin again
        plugin.loaded = true
        some_unloaded = true
        needs_bufread = needs_bufread or plugin.needs_bufread
        loader_apply_wants(plugin, plugins)
        cmd('packadd ' .. names[i])
        if plugin.after_files then
          for _, file in ipairs(plugin.after_files) do
            cmd('silent source ' .. file)
          end
        end
        loader_apply_config(plugin, names[i])
        loader_apply_after(plugin, plugins, names[i])
      end
    end
  end

  if not some_unloaded then
    return
  end

  if needs_bufread then
    if _G._packer and _G._packer.inside_compile == true then
      -- delaying BufRead to end of packer_compiled
      _G._packer.needs_bufread = true
    else
      cmd 'doautocmd BufRead'
    end
  end
  -- Retrigger cmd/keymap...
  apply_cause_side_effects(cause)
end

local function load_wrapper(names, cause, plugins, force)
  local success, err_msg = pcall(packer_load, names, cause, plugins, force)
  if not success then
    vim.cmd 'echohl ErrorMsg'
    vim.cmd('echomsg "Error in packer_compiled: ' .. vim.fn.escape(err_msg, '"') .. '"')
    vim.cmd 'echomsg "Please check your config for correctness"'
    vim.cmd 'echohl None'
  end
end

return load_wrapper
