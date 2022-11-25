local api = require 'vim.api'
local fn = require 'vim.fn'
local uv = require 'vim.uv'

local record M
  api: api
  fn: fn
  loop: uv

  call: function(string, ...:any)

  record cmd
    record Opts
      {string}

      record Mods
        silent: boolean
      end
      mods: Mods
    end

    packadd: function(string|Opts, Opts)
    pedit: function(string)
    source: function(string|Opts, Opts)
    wincmd: function(string)

    metamethod __call: function(cmd, string)
  end

  deepcopy: function<T>(T): T

  defer_fn: function(function, integer): uv.Timer

  type DiffResult = {integer, integer, integer, integer}

  -- Assume result_type == 'indices'
  diff: function(string|{string}, string|{string}, table): {DiffResult}

  record json
    encode: function(any): string
    decode: function(string): any
  end

  record go
    operatorfunc: string
  end

  record o
    columns     : integer
    diffopt     : string
    eventignore : string
    lines       : integer
    shell       : string
    shellslash  : boolean
    shortmess   : string
    splitright  : boolean
    updatetime  : number
    wrapscan    : boolean
    runtimepath : string
  end

  record WinOption
    {WinOption}
    diff: boolean
    signcolumn: string
    previewwindow: boolean
  end

  wo: WinOption

  record BufOption
    {BufOption}
    fileformat: string
    fileencoding: string
    filetype: string
    modifiable: boolean
    modified: boolean
    swapfile: boolean
    tabstop: integer

    enum BufHidden
      '' 'hide' 'unload' 'delete' 'wipe'
    end

    bufhidden: BufHidden

    enum BufType
      '' 'acwrite' 'help' 'nofile' 'nowrite' 'quickfix' 'terminal' 'prompt'
    end
    buftype: BufType
    buflisted: boolean
  end

  bo: BufOption

  record BufVar
    {BufVar}
    changedtick: integer
  end

  b: BufVar

  record WinVar
    {WinVar}
  end

  w: WinVar

  record g
  end

  record v
    vim_did_enter: integer
    t_string: integer
  end

  record opt
    record Opt<T>
      get: function<T>(Opt<T>): T
    end

    diffopt: Opt<{string}>
    foldopen: Opt<{string}>
    shortmess: Opt<{string:boolean}>
    wrapscan: Opt<boolean>
  end

  record lsp
    record util
      close_preview_autocmd: function ({string}, number)
    end
  end

  in_fast_event: function(): boolean

  list_extend: function<T>({T}, {T}, integer, integer): {T}
  list_slice: function<T>({T}, integer, integer): {T}

  record keymap
    record Options
      buffer: boolean|integer
      expr: boolean
      silent: boolean
      nowait: boolean
      desc: string
    end
    set: function(string|{string}, string, string|function, Options)
    del: function(string, string)
  end

  record log
    enum Level
      'WARN'
      'ERROR'
      'INFO'
      'DEBUG'
    end
    levels: {Level:integer}
  end
  notify: function(string, integer, table)
  pretty_print: function(any)

  split: function(string, string): {string}
  split: function(string, string, boolean): {string}

  gsplit: function(string, string, boolean): function(): string

  pesc: function(string): string

  startswith: function(string, string): boolean
  endswith: function(string, string): boolean

  schedule_wrap: function<T>(T): T

  schedule: function(function)
  validate: function({string:{any}})
  trim: function(string): string

  enum ExtendBehavior
    'error'
    'keep'
    'force'
  end

  tbl_add_reverse_lookup: function<K,I>({K:I}): {I:K}
  tbl_contains: function(table, any): boolean
  tbl_count: function(table): integer
  tbl_deep_extend: function<T>(ExtendBehavior, T, ...: T): T
  tbl_extend: function<T>(ExtendBehavior, T, T, ...: T): T
  tbl_filter: function<S,T>((function(T): boolean), {S:T}): {S:T}
  tbl_isempty: function(table): boolean
  tbl_islist: function(any): boolean
  tbl_keys: function<K,V>({K:V}): {K}
  tbl_values: function<K,V>({K:V}): {V}
  tbl_map: function<T,R>((function(T): R), {T}): {R}

  record InspectOptions
    depth: number
    newline: string
    indent: string
    process: function
  end
  record inspect
    METATABLE: any
    KEY: any
    metamethod __call: function(inspect, any, InspectOptions): string
    metamethod __call: function(inspect, any): string
  end

  wait: function(number, function, number, boolean)

  record ui
    input: function({string:any}, function(string))
    record SelectOpts<T>
      prompt: string
      format_item: function(T): string
      kind: string
    end
    select: function<T>({T}, SelectOpts<T>, on_choice: function(T, idx: integer))
  end

  record VersionDetails
    api_compatible: integer
    api_level: integer
    api_prerelease: boolean
    major: integer
    minor: integer
    patch: integer
  end

  version: function(): VersionDetails

  record mpack
    encode: function(any): string
    decode: function(string): any
  end

  is_thread: function(): boolean
end

return M
