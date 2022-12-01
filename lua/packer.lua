local config = require('packer.config')

local Config = config.Config

local M = {}










function M.startup(spec)
   local log = require('packer.log')
   local plugin = require('packer.plugin')
   local loader = require('packer.loader')

   log.debug('STARTING')

   assert(type(spec) == 'table')
   assert(type(spec[1]) == 'table')

   log.debug('PROCESSING CONFIG')
   config(spec.config)

   for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
      if vim.fn.isdirectory(dir) == 0 then
         vim.fn.mkdir(dir, 'p')
      end
   end

   log.debug('PROCESSING PLUGIN SPEC')
   plugin.process_spec(spec[1])

   log.debug('LOADING PLUGINS')

   loader.setup(plugin.plugins)
end

return M