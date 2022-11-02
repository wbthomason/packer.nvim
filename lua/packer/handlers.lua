local M = {}











return setmetatable(M, {
   __index = function(_, cond)
      if cond == 'keys' then
         return require('packer.handlers.keys')
      elseif cond == 'event' then
         return require('packer.handlers.event')
      elseif cond == 'ft' then
         return require('packer.handlers.ft')
      elseif cond == 'cmd' then
         return require('packer.handlers.cmd')
      end
   end,
})