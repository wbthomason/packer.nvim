local separator = nil
if jit ~= nil then
  separator = (jit.os == 'Windows') and '\\' or '/'
else
  separator = (package.config:sub(1, 1) == '\\') and '\\' or '/'
end

local function handle_after_plugin(name, plugins)
  local pattern = table.concat({'after', 'plugin', '**', '*.vim'}, separator)
  local path = plugins[name].path .. separator .. pattern
  local glob_ok, files = pcall(vim.fn.glob, path, false, true)
  if not glob_ok then
    if string.find(files, 'E77') then
      vim.cmd('silent exe "source ' .. path .. '"')
    else
      print('Error running config for ' .. name)
      error(files)
    end
  elseif #files > 0 then
    for _, file in ipairs(files) do vim.cmd('silent exe "source ' .. file .. '"') end
  end
end

local source_dirs = {'ftdetect', 'ftplugin', 'after/ftdetect', 'after/ftplugin'}
local function handle_bufread(names, plugins)
  for _, name in ipairs(names) do
    local path = plugins[name].path
    for i = 1, 4 do
      if #vim.fn.finddir(source_dirs[i], path) > 0 then
        vim.cmd('doautocmd BufRead')
        return
      end
    end
  end
end

local packer_load = nil
local function handle_after(name, before, plugins)
  local plugin = plugins[name]
  plugin.load_after[before] = nil
  if next(plugin.load_after) == nil then packer_load({name}, {}, plugins) end
end

packer_load = function(names, cause, plugins)
  local some_unloaded = false
  local num_names = #names

  local cmd = vim.api.nvim_command
  local fmt = string.format
  for i = 1, num_names do
    local plugin = plugins[names[i]]
    if not plugin.loaded then
      some_unloaded = true
      if plugin.commands then
        for _, del_cmd in ipairs(plugin.commands) do cmd('silent! delcommand ' .. del_cmd) end
      end

      if plugin.keys then
        for _, key in ipairs(plugin.keys) do cmd(fmt('silent! %sunmap %s', key[1], key[2])) end
      end

      vim.cmd('packadd ' .. names[i])
      handle_after_plugin(names[i], plugins)
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
          handle_after(after_name, names[i], plugins)
          vim.cmd('redraw')
        end
      end

      plugins[names[i]].loaded = true
    end
  end

  if not some_unloaded then return end
  handle_bufread(names, plugins)
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
