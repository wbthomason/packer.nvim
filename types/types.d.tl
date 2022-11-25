global _: any

global unpack = table.unpack

-- Hacky trick to get Plugin defined everywhere without having to require
-- packer.plugin
global Plugin = require'packer.plugin'.Plugin

global packer_plugins: {string:Plugin}

global jit = require('jit')
global vim = require('vim')
