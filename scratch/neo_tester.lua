package.loaded['packer.neorocks'] = nil

local a      = require('packer.async')
local await = a.wait

local neo = require('packer.neorocks')

neo.get_hererocks()
