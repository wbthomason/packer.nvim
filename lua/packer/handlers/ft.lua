local join_paths = require('packer.util').join_paths

local util = require('packer.handlers.util')

local function detect_ftdetect(plugin_path)
   local source_paths = {}
   for _, parts in ipairs({ { 'ftdetect' }, { 'after', 'ftdetect' } }) do
      parts[#parts + 1] = [[**/*.\(vim\|lua\)]]
      local path = join_paths(plugin_path, unpack(parts))
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

return function(plugins, loader)
   local fts = {}

   local ftdetect_paths = {}

   for _, plugin in pairs(plugins) do
      if plugin.ft then
         for _, ft in ipairs(plugin.ft) do
            fts[ft] = fts[ft] or {}
            table.insert(fts[ft], plugin)
         end

         vim.list_extend(ftdetect_paths, detect_ftdetect(plugin.install_path))
      end
   end

   for ft, fplugins in pairs(fts) do
      local id = vim.api.nvim_create_autocmd('FileType', {
         pattern = ft,
         once = true,
         callback = function()
            loader(fplugins)
            for _, group in ipairs({ 'filetypeplugin', 'filetypeindent', 'syntaxset' }) do
               vim.api.nvim_exec_autocmds('FileType', { group = group, pattern = ft, modeline = false })
            end
         end,
      })

      util.register_destructor(fplugins, function()
         pcall(vim.api.nvim_del_autocmd, id)
      end)

   end

   if #ftdetect_paths > 0 then
      vim.cmd('augroup filetypedetect')
      for _, path in ipairs(ftdetect_paths) do

         vim.cmd.source(path)
      end
      vim.cmd('augroup END')
   end

end