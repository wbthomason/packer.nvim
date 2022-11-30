global _: any

global loadstring: function(string, string): (function(): any)
global unpack = table.unpack

global record UserSpec
  {string}

  branch     : string
  rev        : string
  tag        : string
  commit     : string
  opt        : boolean
  keys       : string|{string|{string,string}}
  event      : string|{string}
  ft         : string|{string}
  cmd        : string|{string}
  enable     : boolean|function(): boolean
  run        : string|function|{string|function}
  config_pre : string|function()
  config     : string|function()
  lock       : boolean
  requires   : string|{string|UserSpec}
  start      : boolean
  lazy       : boolean
end

global record Plugin
  branch       : string
  rev          : string
  tag          : string
  commit       : string
  install_path : string
  keys         : {{string,string}}
  event        : {string}
  ft           : {string}
  cmd          : {string}
  enable       : boolean|function(): boolean
  run          : {string|function}
  config_pre   : string|function()
  config       : string|function()
  requires     : {string}
  start        : boolean
  lazy         : boolean
  simple       : boolean

  name         : string
  full_name    : string -- Includes rev and branch
  revs         : {string, string}
  required_by  : {string}

  enum Type
    'git'
    'local'
    'unknown'
  end

  type             : Type
  url              : string
  lock             : boolean
  breaking_commits : {string}
  opt              : boolean
  loaded           : boolean
  destructors      : {integer:function()}

  messages: {string}
  err: {string}
end

global jit = require('jit')
global vim = require('vim')
