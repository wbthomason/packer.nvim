package.loaded['packer.neorocks'] = nil
package.loaded['packer.jobs'] = nil

local a      = require('packer.async')
local await = a.wait
local util   = require('packer.util')

local neo = require('packer.neorocks')

print(vim.fn.filereadable(util.absolute_path(neo._hererocks_file)))
a.main(neo.setup_hererocks)
print(vim.fn.filereadable(util.absolute_path(neo._hererocks_file)))
