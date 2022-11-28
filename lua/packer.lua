local log = require('packer.log')
local config = require('packer.config')

local Config = config.Config

local did_setup = false

local function setup(user_config)
   log.debug('setup')

   config(user_config)

   for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
      if vim.fn.isdirectory(dir) == 0 then
         vim.fn.mkdir(dir, 'p')
      end
   end

   did_setup = true
end

local M = {}

function M.add(spec)
   if not did_setup then
      setup()
   end

   local plugin = require('packer.plugin')
   local loader = require('packer.loader')

   log.debug('PROCESSING PLUGIN SPEC')
   plugin.process_spec(spec)

   log.debug('LOADING PLUGINS')
   loader.setup(plugin.plugins)
end


function M.setup(user_config, user_spec)
   setup(user_config)

   if user_spec then
      M.add(user_spec)
   end
end





function M.startup(spec)
   log.debug('STARTING')
   assert(type(spec) == 'table')

   local user_spec = spec[1]
   assert(type(user_spec) == "table")

   M.setup(spec.config)
   M.add(user_spec)
end

return M