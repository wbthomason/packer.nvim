local startup = {}

startup.initialize_default_mappings = function(files)
  vim.cmd [[command! PackerInstall packadd packer.nvim | lua require('plugins').install()]]
  vim.cmd [[command! PackerUpdate packadd packer.nvim | lua require('plugins').update()]]
  vim.cmd [[command! PackerSync packadd packer.nvim | lua require('plugins').sync()]]
  vim.cmd [[command! PackerClean packadd packer.nvim | lua require('plugins').clean()]]
  vim.cmd(string.format(
    [[command! PackerCompile packadd packer.nvim | lua require('plugins').compile('%s')]],
    files.plugin_file or vim.fn.stdpath('config') .. '/plugin/packer_load.vim'
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
