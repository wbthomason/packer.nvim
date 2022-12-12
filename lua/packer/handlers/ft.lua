local Plugin = require('packer.plugin').Plugin
local util = require('packer.util')

local function detect_ftdetect(plugin_path)
   local source_paths = {}
   for _, parts in ipairs({ { 'ftdetect' }, { 'after', 'ftdetect' } }) do
      parts[#parts + 1] = [[**/*.\(vim\|lua\)]]
      local path = util.join_paths(plugin_path, unpack(parts))
      local ok, files = pcall(vim.fn.glob, path, false, true)
      if not ok then
         if string.find(files, 'E77') then
            source_paths[#source_paths + 1] = path
         else
            error(files)
         end
      elseif #files > 0 then
         vim.list_extend(source_paths, files)
      end
   end

   return source_paths
end

local ft_plugins = {}

return function(plugins, loader)
   local new_fts = {}
   local ftdetect_paths = {}
   for _, plugin in pairs(plugins) do
      if plugin.ft then
         for _, ft in ipairs(plugin.ft) do
            if not ft_plugins[ft] then
               ft_plugins[ft] = {}
               new_fts[#new_fts + 1] = ft
            end

            table.insert(ft_plugins[ft], plugin)
         end

         vim.list_extend(ftdetect_paths, detect_ftdetect(plugin.install_path))
      end
   end

   for _, ft in ipairs(new_fts) do
      vim.api.nvim_create_autocmd('FileType', {
         pattern = ft,
         once = true,
         callback = function()
            loader(ft_plugins[ft])
            for _, group in ipairs({ 'filetypeplugin', 'filetypeindent', 'syntaxset' }) do
               vim.api.nvim_exec_autocmds('FileType', { group = group, pattern = ft, modeline = false })
            end
         end,
      })
   end

   if #ftdetect_paths > 0 then
      vim.cmd('augroup filetypedetect')
      for _, path in ipairs(ftdetect_paths) do

         vim.cmd.source(path)
      end
      vim.cmd('augroup END')
   end

end