local packer_load = nil

packer_load = function(names, cause, plugins)
  local some_unloaded = false
  local needs_bufread = false
  local num_names = #names

  local cmd = vim.api.nvim_command
  local fmt = string.format
  for i = 1, num_names do
    local plugin = plugins[names[i]]
    if not plugin.loaded then
      some_unloaded = true
      needs_bufread = needs_bufread or plugin.needs_bufread
      if plugin.commands then
        for _, del_cmd in ipairs(plugin.commands) do cmd('silent! delcommand ' .. del_cmd) end
      end

      if plugin.keys then
        for _, key in ipairs(plugin.keys) do cmd(fmt('silent! %sunmap %s', key[1], key[2])) end
      end

      vim.cmd('packadd ' .. names[i])
      if plugin.after_files then
        for _, file in ipairs(plugin.after_files) do
          cmd('silent exe "source ' .. file .. '"')
        end
      end

      if plugin.config then
        for _, config_line in ipairs(plugin.config) do
          local success, err = pcall(loadstring(config_line))
          if not success then
            print('Error running config for ' .. names[i])
            error(err)
          end
        end
      end

      if plugin.after then
        for _, after_name in ipairs(plugin.after) do
          local after_plugin = plugins[after_name]
          after_plugin.load_after[names[i]] = nil
          if next(after_plugin.load_after) == nil then
            packer_load({after_name}, {}, plugins)
          end
        end
      end

      plugins[names[i]].loaded = true
    end
  end

  if not some_unloaded then return end
  if needs_bufread then cmd('doautocmd BufRead') end
  if cause.cmd then
    local lines = cause.l1 == cause.l2 and '' or (cause.l1 .. ',' .. cause.l2)
    vim.cmd(fmt('%s%s%s %s', lines, cause.cmd, cause.bang, cause.args))
  elseif cause.keys then
    local extra = ''
    while true do
      local c = vim.fn.getchar(0)
      if c == 0 then break end
      extra = extra .. vim.fn.nr2char(c)
    end

    if cause.prefix then
      local prefix = vim.v.count ~= 0 and vim.v.count or ''
      prefix = prefix .. '"' .. vim.v.register .. cause.prefix
      if vim.fn.mode('full') == 'no' then
        if vim.v.operator == 'c' then prefix = '' .. prefix end
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
  end
end

local function load_wrapper(names, cause, plugins)
  local success, err_msg = pcall(packer_load, names, cause, plugins)
  if not success then
    vim.cmd('echohl ErrorMsg')
    vim.cmd('echomsg "Error in packer_compiled: ' .. vim.fn.escape(err_msg, '"') .. '"')
    vim.cmd('echomsg "Please check your config for correctness"')
    vim.cmd('echohl None')
  end
end

return load_wrapper
