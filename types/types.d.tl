global _: any

global loadstring: function(string, string): (function(): any)
global unpack = table.unpack

-- Hacky trick to get Plugin defined everywhere without having to require
-- packer.plugin
global Plugin = require'packer.plugin'.Plugin
global UserSpec = require'packer.plugin'.UserSpec

global jit = require('jit')
global vim = require('vim')
