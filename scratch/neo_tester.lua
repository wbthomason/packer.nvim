package.loaded['packer.neorocks'] = nil
package.loaded['packer.jobs'] = nil

local a   = require('packer.async')
local neo = require('packer.neorocks')

a.main(neo.setup_hererocks)
