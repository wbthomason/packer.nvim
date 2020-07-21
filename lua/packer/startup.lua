local startup = {}

startup.initialize_default_mappings = function(files)
  vim.cmd [[command! PackerInstall  lua require('plugins').install()]]
  vim.cmd [[command! PackerUpdate   lua require('plugins').update()]]
  vim.cmd [[command! PackerSync     lua require('plugins').sync()]]
  vim.cmd [[command! PackerClean    lua require('plugins').clean()]]
  vim.cmd(string.format(
    [[command! PackerCompile lua require('plugins').compile('%s')]],
    files.compile_location or vim.fn.stdpath('config') .. '/plugin/packer_compiled.vim'
  ))
end

startup.create = function(packer, files, f)
  packer.init()
  packer.reset()

  f(packer.use)

  startup.initialize_default_mappings(files)

  return packer
end

return startup.create
