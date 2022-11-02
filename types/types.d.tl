global _: any

global _TEST: boolean

global loadstring: function(string, string): (function(): any)

global unpack: function<T>({T}, number, number): T...

global getfenv: function(function): table

global record Config
  record Display
    open_cmd        : string
    preview_updates : boolean
    non_interactive : boolean
    prompt_border   : string
    compact         : boolean
    working_sym     : string
    error_sym       : string
    done_sym        : string
    removed_sym     : string
    moved_sym       : string
    item_sym        : string
    header_sym      : string
    header_lines    : integer
    title           : string
    show_all_info   : boolean
    keybindings     : {string: string}
  end

  record Git
    mark_breaking_changes : boolean
    cmd                   : string
    depth                 : integer
    clone_timeout         : integer
    default_url_format    : string
  end


  record Log
    enum Level
      'trace' 'debug' 'info' 'warn' 'error' 'fatal'
    end
    level: Level
  end

  package_root    : string
  pack_dir        : string
  max_jobs        : integer
  start_dir       : string
  opt_dir         : string
  snapshot_path   : string
  preview_updates : boolean
  auto_clean      : boolean
  autoremove      : boolean
  display         : Display
  snapshot        : string
  git             : Git
  log             : Log

  metamethod __call: function(Config, Config): Config
end

global record Plugin
  {string}

  name             : string
  full_name        : string -- Includes rev and branch
  branch           : string
  rev              : string
  revs             : {string, string}
  tag              : string
  commit           : string
  install_path     : string
  keys             : {{string,string}}
  event            : {string}
  ft               : {string}
  cmd              : {string}
  run              : {string | function}
  config           : string|function()

  enum Type
    'git'
    'local'
    'unknown'
  end

  type             : Type
  url              : string
  lock             : boolean
  from_requires    : boolean
  breaking_commits : {string}
  requires         : {Plugin}
  opt              : boolean
  loaded           : boolean

  messages: {string}
  err: {string}
end

global packer_plugins: {string:Plugin}

global record PluginResult
  err: {string}

  -- Used for moves
  from: string
  to: string
end

global record jit
  arch: string
  os: string
  version: string
  version_num: number
  off: function()
  off: function(function)
  on: function()
  status: function(): boolean
end

local record api
  record UserCmdParams
    args: string
    fargs: {string}
    bang: boolean
    line1: integer
    line2: integer
    range: integer
    count: number
    reg: string
    mods: string
    complete: function(string)

    record Mods
      browse       : boolean
      confirm      : boolean
      emsg_silent  : boolean
      hide         : boolean
      keepalt      : boolean
      keepjumps    : boolean
      keepmarks    : boolean
      keeppatterns : boolean
      lockmarks    : boolean
      noautocmd    : boolean
      noswapfile   : boolean
      sandbox      : boolean
      silent       : boolean
      tab          : integer
      verbose      : integer
      vertical     : boolean

      enum Split ''
        'aboveleft'
        'belowright'
        'topleft'
        'botright'
      end

      split : Split
    end
    smods: Mods
  end

  record UserCmdOpts
    nargs: string|integer
    range: boolean|string|integer
    count: boolean|integer
    addr: string
    bang: boolean
    bar: boolean
    register: boolean
    force: boolean
    complete: string|function(arglead: string, line: string): {string}
  end
  nvim_create_user_command   : function(string, function(UserCmdParams), UserCmdOpts)
  nvim_del_user_command      : function(string)
  nvim_buf_attach            : function(integer, boolean, {string:any}): boolean
  nvim_buf_call              : function<T>(integer, function(): T): T
  nvim_buf_clear_namespace   : function(integer, number, number, number)
  nvim_buf_del_extmark       : function(integer, number, number): boolean
  nvim_buf_delete            : function(integer, {string:boolean})
  nvim_buf_get_extmark_by_id : function(integer, integer, integer, table): {integer}

  record GetExtmarOpts
    limit: integer
    details: boolean
  end

  nvim_buf_get_extmarks: function(
    buf: integer,
    ns: integer,
    start: integer | {integer, integer},
    eend: integer | {integer, integer},
    GetExtmarOpts
  ): {{integer, integer, integer}}

  nvim_buf_get_lines    : function(integer, number, number, boolean): {string}
  nvim_buf_get_name     : function(integer): string
  nvim_buf_is_loaded    : function(integer): boolean
  nvim_buf_is_valid     : function(integer): boolean
  nvim_buf_line_count   : function(integer): integer
  nvim_buf_set_extmark  : function(integer, integer, integer, integer, {string:any}): integer
  nvim_buf_set_keymap   : function(integer, string, string, string, {string:any})
  nvim_buf_set_lines    : function(integer, number, number, boolean, {string})
  nvim_buf_set_name     : function(integer, string)
  nvim_create_buf       : function(boolean, boolean): integer
  nvim_create_namespace : function(string): integer

  record AugroupOpts
    clear: boolean
  end

  nvim__buf_redraw_range       : function(integer, number, number)

  nvim_create_augroup: function(string, AugroupOpts): integer

  record AutoCmdOpts
    callback: function()
    command: string
    group: string
    pattern: string|{string}
    once: boolean
    nested: boolean
    desc: string
    buffer: integer
  end

  nvim_create_autocmd: function(string|{string}, AutoCmdOpts): integer
  nvim_del_current_line: function()
  nvim_del_keymap: function(string, string)
  nvim_del_var: function(string)
  nvim_echo: function({{string}}, boolean, {string:any})
  nvim_err_write: function(string)
  nvim_err_writeln: function(string)
  nvim_eval: function(string): any
  nvim_exec: function(string, boolean): string

  record ExecAutoCmdOpts
    group: string|integer
    pattern: string|{string}
    buffer: integer
    modeline: boolean
    data: any
  end

  nvim_exec_autocmds: function(string|{string}, ExecAutoCmdOpts): any
  nvim_exec_lua: function(string, any): any
  nvim_feedkeys: function(string, string, boolean)
  nvim_get_api_info: function(): any
  nvim_get_chan_info: function(number): {string:any}
  nvim_get_color_by_name: function(string): number
  nvim_get_color_map: function(): {string:any}
  nvim_get_commands: function({string:any}): {string:any}
  nvim_get_context: function({string:any}): {string:any}
  nvim_get_current_buf: function(): integer
  nvim_get_current_line: function(): string
  nvim_get_current_tabpage: function(): any
  nvim_get_current_win: function(): integer
  nvim_get_hl_by_id: function(number, boolean): {string:any}
  nvim_get_hl_by_name: function(string, boolean): {string:any}
  nvim_get_hl_id_by_name: function(string): number
  nvim_get_keymap: function(string): {{string:any}}
  nvim_get_mode: function(): {string:any}
  nvim_get_namespaces: function(): {string:any}
  nvim_get_option: function(string): any
  nvim_get_proc: function(number): any
  nvim_get_proc_children: function(number): any
  nvim_get_runtime_file: function(string, boolean): {string}
  nvim_get_var: function(string): any
  nvim_get_vvar: function(string): any
  nvim_input: function(string): number
  nvim_input_mouse: function(string, string, string, number, number, number)
  nvim_list_bufs: function(): {integer}
  nvim_list_chans: function(): any
  nvim_list_runtime_paths: function(): {string}
  nvim_list_tabpages: function(): {any}
  nvim_list_uis: function(): {any}
  nvim_list_wins: function(): {integer}
  nvim_load_context: function({string:any}): any
  nvim_open_win: function(number, boolean, {string:any}): integer
  nvim_out_write: function(string)
  nvim_parse_expression: function(string, string, boolean): {string:any}
  nvim_paste: function(string, boolean, number): boolean
  nvim_put: function({string}, string, boolean, boolean)
  nvim_replace_termcodes: function(string, boolean, boolean, boolean): string
  nvim_select_popupmenu_item: function(number, boolean, boolean, {string:any})
  nvim_set_client_info: function(string, {string:any}, string, {string:any}, {string:any})
  nvim_set_current_buf: function(number)
  nvim_set_current_dir: function(string)
  nvim_set_current_line: function(string)
  nvim_set_current_tabpage: function(any)
  nvim_set_current_win: function(number)
  nvim_set_decoration_provider: function(number, {string:function})
  nvim_set_hl: function(integer, string, {string:any})
  nvim_set_keymap: function(string, string, string, {string:any})
  nvim_set_option: function(string, any)
  nvim_set_var: function(string, any)
  nvim_set_vvar: function(string, any)
  nvim_strwidth: function(string): number
  nvim_subscribe: function(string)
  nvim_tabpage_del_var: function(any, string)
  nvim_tabpage_get_number: function(any): number
  nvim_tabpage_get_var: function(any, string): any
  nvim_tabpage_get_win: function(any): number
  nvim_tabpage_is_valid: function(any): boolean
  nvim_tabpage_list_wins: function(any): {number}
  nvim_tabpage_set_var: function(any, string, any)
  nvim_ui_attach: function(number, number, {string:any})
  nvim_ui_detach: function()
  nvim_ui_pum_set_bounds: function(number, number, number, number)
  nvim_ui_pum_set_height: function(number)
  nvim_ui_set_option: function(string, any)
  nvim_ui_try_resize: function(number, number)
  nvim_ui_try_resize_grid: function(number, number, number)
  nvim_unsubscribe: function(string)
  nvim_win_call: function<T>(number, (function(): T)): T
  nvim_win_close: function(number, boolean)
  nvim_win_del_var: function(number, string)
  nvim_win_get_buf: function(integer): integer
  nvim_win_get_config: function(number): {string:any}
  nvim_win_get_cursor: function(number): {integer}
  nvim_win_get_height: function(integer): integer
  nvim_win_get_number: function(number): number
  nvim_win_get_option: function(number, string): any
  nvim_win_get_position: function(number): {number}
  nvim_win_get_tabpage: function(number): any
  nvim_win_get_var: function(number, string): any
  nvim_win_get_width: function(integer): integer
  nvim_win_is_valid: function(number): boolean
  nvim_win_set_buf: function(number, number)
  nvim_win_set_config: function(number, {string:any})
  nvim_win_set_cursor: function(number, {number})
  nvim_win_set_height: function(number, number)
  nvim_win_set_option: function(number, string, any)
  nvim_win_set_var: function(number, string, any)
  nvim_win_set_width: function(number, number)

  nvim__buf_redraw_range: function(number, number, number)
  nvim_create_autocmd          : function(string|{string}, AutoCmdOpts): integer
  nvim_echo                    : function({{string}}, boolean, {string:any})
  nvim_get_color_by_name       : function(string): number
  nvim_get_current_buf         : function(): integer
  nvim_get_current_line        : function(): string
  nvim_get_current_tabpage     : function(): any
  nvim_get_current_win         : function(): integer
  nvim_get_hl_by_name          : function(string, boolean): {string:any}
  nvim_get_mode                : function(): {string:any}
  nvim_list_bufs               : function(): {integer}
  nvim_list_wins               : function(): {integer}
  nvim_open_win                : function(integer, boolean, {string:any}): integer
  nvim_replace_termcodes       : function(string, boolean, boolean, boolean): string
  nvim_set_current_buf         : function(integer)
  nvim_set_current_line        : function(string)
  nvim_set_current_win         : function(integer)
  nvim_set_decoration_provider : function(integer, {string:function})
  nvim_set_hl                  : function(integer, string, {string:any})
  nvim_set_keymap              : function(string, string, string, {string:any})
  nvim_strwidth                : function(string): number
  nvim_win_call                : function<T>(integer, (function(): T)): T
  nvim_win_close               : function(integer, boolean)
  nvim_win_get_buf             : function(integer): integer
  nvim_win_get_config          : function(integer): {string:any}
  nvim_win_get_cursor          : function(integer): {integer}
  nvim_win_get_height          : function(integer): integer
  nvim_win_get_width           : function(integer): integer
  nvim_win_is_valid            : function(integer): boolean
  nvim_win_set_buf             : function(integer, number)
  nvim_win_set_config          : function(integer, {string:any})
  nvim_win_set_cursor          : function(integer, {number})
  nvim_win_set_height          : function(integer, number)
  nvim_win_set_width           : function(integer, number)
end

global record vim
  api: api
  record fn
    bufexists: function(string): integer
    bufnr: function(string): integer
    delete: function(string, string): integer
    execute: function(string, string)
    iconv: function(string, string, string): string
    line: function(string): integer
    join: function({any}, string): string
    getftime: function(string): integer
    getpos: function(string): {integer}
    environ: function(): {string:string}
    executable: function(string): integer
    exists: function(string): integer
    expand: function(string): string
    fnamemodify: function(string, string): string
    fnameescape: function(string): string
    filereadable: function(string): integer
    foldclosed: function(integer): integer
    foldclosedend: function(integer): integer
    getcwd: function(): string
    glob: function(string, boolean): string
    glob: function(string, boolean, boolean): {string}
    input: function(string, string): string
    isdirectory: function(string): integer
    matchstr: function(string, string): string
    mkdir: function(string, string)

    record QFItem
      bufnr: integer
      filename: string
      lnum: integer
      nr: integer
      text: string
      type: string
    end

    record QFWhat
      context: any
      efm: string
      id: integer
      idx: integer
      items: {QFItem}
      lines: {string}
      nr: integer
      quickfixtextfunc: string
      title: string
    end

    setqflist: function(list: {QFItem}, action: string, what: QFWhat)
    setloclist: function(nr: integer, list: {QFItem}, action: string, what: QFWhat)

    sign_unplace: function(string, {string:any})
    sign_place: function(number, string, string, string | number, {string:any})

    record SignPlaceItem
      buffer: integer
      group: string
      id: integer
      lnum: integer
      name: string
      priority: integer
    end
    sign_placelist: function({SignPlaceItem})
    sign_getdefined: function(string): table

    record SignPlacedInfo
      bufnr: integer
      record SignPlacedSigns
        id: integer
        name: string
        group: string
        lnum: integer
        priority: integer
      end
      signs: {SignPlacedSigns}
    end
    sign_getplaced: function(integer, table): {SignPlacedInfo}

    sign_define: function(string, table): number
    sign_undefine: function(string): number
    stdpath: function(string): string
    strdisplaywidth: function(string, integer): integer
    stridx: function(haystack: string, needle: string, start: integer): integer
    string: function(any): string
    systemlist: function({string}): {string}
    tempname: function(): string
    type: function(any): integer
    writefile: function({string}, string, string): integer
    readfile: function(string, string, integer): {string}
  end

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

  defer_fn: function(function, integer): loop.Timer

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

  record loop
    cwd: function(): string

    enum Fail
      'fail'
    end

    record Timer
      userdata

      start: function(Timer, number, number, function): number
      stop: function(Timer): number
      close: function(Timer): number
      is_closing: function(Timer): boolean
      again: function(Timer): number
      set_repeat: function(Timer, number): number
      get_repeat: function(Timer): number
      get_due_in: function(Timer): number
    end
    hrtime: function(): number
    new_timer: function(): Timer
    timer_start: function(Timer, integer, integer, function()): integer | Fail

    record Prepare
      userdata

      start: function(Prepare, function()): integer | Fail
      stop: function(Prepare): integer | Fail
    end

    new_prepare: function(): Prepare

    new_fs_event: function()

    record FSPollObj
      userdata
      is_closing: function(FSPollObj): boolean | string
      close: function(FSPollObj)
      start: function(FSPollObj, string, integer, function)
      stop: function(FSPollObj)
      getpath: function(FSPollObj): string
    end
    new_fs_poll: function(): FSPollObj

    record FsStatRet
      dev : number
      mode : number
      nlink : number
      uid : number
      gid : number
      rdev : number
      ino : number
      size : integer
      blksize : number
      blocks : number
      flags : number
      gen : number
      record atime
        sec : number
        nsec : number
      end
      record mtime
        sec : number
        nsec : number
      end
      record ctime
        sec : number
        nsec : number
      end
      record birthtime
        sec : number
        nsec : number
      end
      type : string
    end

    fs_stat: function(string, nil): FsStatRet
    fs_stat: function(string, function(string, FsStatRet)): FsT

    fs_lstat: function(string, nil): FsStatRet
    fs_lstat: function(string, function(string, FsStatRet)): FsT

    fs_fstat: function(integer, nil): FsStatRet
    fs_fstat: function(string, function(string, FsStatRet)): FsT

    fs_realpath: function(string): string

    record DirT
      userdata

      closedir: function(DirT): boolean | Fail
    end

    record FsT
      userdata

    end

    record DirResult
      name: string
      type: string
    end

    fs_open: function(string, string|integer, integer, nil): integer|string
    fs_open: function(string, string|integer, integer, function(string, integer)): FsT

    fs_read: function(integer, integer, integer, nil): string
    fs_read: function(integer, integer, integer, function(string, string)): FsT

    fs_close: function(integer, nil): boolean|string
    fs_close: function(integer, function(string, boolean)): FsT

    fs_opendir: function(string, nil, integer): DirT
    fs_opendir: function(string, function, integer): FsT

    fs_closedir: function(string, function, integer): FsT

    fs_readdir: function(DirT, nil): {DirResult}
    fs_readdir: function(DirT, function): FsT

    fs_symlink: function(path:string, new_path:string, flags: table, callback: function(string, boolean)): FsT
    fs_symlink: function(path:string, new_path:string, flags: table, nil): boolean

    fs_unlink: function(string, nil): boolean
    fs_unlink: function(string, function(string, boolean)): FsT

    new_tcp: function()

    sleep: function(integer)

    record Handle
      userdata

      close: function(Handle)
      is_closing: function(Handle): boolean | string
    end

    record Check
      userdata

      start: function(Check, function)
      stop: function(Check)
      close: function(Handle)
      is_closing: function(Handle): boolean | string
    end

    new_check: function(boolean): Check

    record Pipe
      userdata

      close: function(Pipe)
      is_closing: function(Pipe): boolean | string
      read_start: function(Pipe, err: any, data: string)
      read_stop: function(Pipe)
      write: function(Pipe, string, function())

      open: function(any)
    end

    record Process
      userdata

      close: function(Process)
      is_active: function(Process): boolean
      kill: function(Process, signal: string)
    end

    record SpawnOpts
      stdio: {Pipe, Pipe, Pipe}
      args: {string}
      cwd: string
      env: {string}
      hide: boolean

      -- Internal extension
      timeout: integer
    end

    spawn: function(string, SpawnOpts, function(integer, string)): Process, integer

    read_start: function(Pipe, function)
    new_pipe: function(boolean): Pipe, string
    shutdown: function(any, function)
    close: function(any, function)

    record WorkCtx
      queue: function(WorkCtx, ...:any)
    end

    new_work: function(function, function): WorkCtx
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
  tbl_islist: function(table): boolean
  tbl_keys: function<K,V>({K:V}): {K}
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
