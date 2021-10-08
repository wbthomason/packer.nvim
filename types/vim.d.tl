global _: any

global loadstring: function(string): (function(): any)

global unpack: function<T>({T}, number, number): T...

global getfenv: function(function): table

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

global record _packer
end

local record api
  nvim_buf_add_highlight: function(number, number, string, number, number, number): number
  nvim_buf_attach: function(number, boolean, {string:any}): boolean
  nvim_buf_call: function(number, function)
  nvim_buf_clear_highlight: function(number, number, number, number)
  nvim_buf_clear_namespace: function(number, number, number, number)
  nvim_buf_del_extmark: function(number, number, number): boolean
  nvim_buf_del_keymap: function(number, string, string)
  nvim_buf_del_var: function(number, string)
  nvim_buf_detach: function(number): boolean
  nvim_buf_get_changedtick: function(number): number
  nvim_buf_get_commands: function(number, {string:any}): {string:any}
  nvim_buf_get_extmark_by_id: function(number, number, number): {number}
  nvim_buf_get_extmarks: function(number, number, any, any, {string:any}): any
  nvim_buf_get_keymap: function(number, string): {{string:any}}
  nvim_buf_get_lines: function(number, number, number, boolean): {string}
  nvim_buf_get_mark: function(number, string): {number}
  nvim_buf_get_name: function(number): string
  nvim_buf_get_offset: function(number, number): number
  nvim_buf_get_option: function(number, string): any
  nvim_buf_get_var: function(number, string): any
  nvim_buf_get_virtual_text: function(number, number): any
  nvim_buf_is_loaded: function(number): boolean
  nvim_buf_is_valid: function(number): boolean
  nvim_buf_line_count: function(number): number
  nvim_buf_set_extmark: function(integer, integer, integer, integer, {string:any}): integer
  nvim_buf_set_keymap: function(number, string, string, string, {string:any})
  nvim_buf_set_lines: function(number, number, number, boolean, {string})
  nvim_buf_set_name: function(number, string)
  nvim_buf_set_option: function(number, string, any)
  nvim_buf_set_var: function(number, string, any)
  nvim_buf_set_virtual_text: function(number, number, number, any, {string:any}): number
  nvim_call_atomic: function(any): any
  nvim_call_dict_function: function(any, string, any): any
  nvim_call_function: function(string, any): any
  nvim_command: function(string)
  nvim_create_buf: function(boolean, boolean): integer
  nvim_create_namespace: function(string): integer
  nvim_del_current_line: function()
  nvim_del_keymap: function(string, string)
  nvim_del_var: function(string)
  nvim_echo: function({{string}}, boolean, {string:any})
  nvim_err_write: function(string)
  nvim_err_writeln: function(string)
  nvim_eval: function(string): any
  nvim_exec: function(string, boolean): string
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
  nvim_get_current_win: function(): number
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
  nvim_list_uis: function(): any
  nvim_list_wins: function(): {number}
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
  nvim_win_get_buf: function(number): number
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
end

global record vim
  api: api
  record fn
    line: function(string): integer
    join: function({any}, string): string
    getpos: function(string): {integer}
    executable: function(string): integer
    expand: function(string): string
    getcwd: function(): string
    stdpath: function(string): string
    strdisplaywidth: function(string, integer): integer
    stridx: function(haystack: string, needle: string, start: integer): integer
    tempname: function(): string
  end

  cmd: function(string): any

  deepcopy: function<T>(T): T

  diff: function(string|{string}, string|{string}, table)

  record o
    diffopt: string
    wrapscan: boolean
    updatetime: number
    shortmess: string
  end

  record wo
    diff: boolean
  end

  record BufOption
    {BufOption}
    fileformat: string
  end

  bo: BufOption

  record v
    vim_did_enter: integer
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
    record Timer
      start: function(Timer, number, number, function): number
      stop: function(Timer): number
      close: function(Timer): number
      again: function(Timer): number
      set_repeat: function(Timer, number): number
      get_repeat: function(Timer): number
      get_due_in: function(Timer): number
    end
    new_timer: function(): Timer
    timer_start: function(Timer, integer, integer, function()): integer | string

    new_fs_event: function()

    record FSPollObj
      userdata
      start: function
      stop: function
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
      size : number
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

    fs_stat: function(string, function): FsStatRet

    fs_realpath: function(string): string

    new_tcp: function()

    sleep: function(integer)

    record Pipe
      close: function(Pipe)
      is_closing: function(Pipe): boolean | string
      read_start: function(Pipe, err: any, data: string)
      read_stop: function(Pipe)
      write: function(Pipe, string, function())

      open: function(any)
    end

    record Process
      userdata
    end

    record SpawnOpts
      stdio: {Pipe, Pipe, Pipe}
      args: {string}
      cwd: string
      env: {string}
    end

    spawn: function(string, SpawnOpts, function(integer, integer)): Process, integer

    read_start: function(Pipe, function)
    new_pipe: function(boolean): Pipe
    shutdown: function(any, function)
    close: function(any, function)
  end

  in_fast_event: function(): boolean

  list_extend: function({any}, {any}, integer, integer)
  record log
    record levels
      WARN: integer
      ERROR: integer
      INFO: integer
      DEBUG: integer
    end
  end
  notify: function(string, integer, table)
  split: function(string, string): {string}
  split: function(string, string, boolean): {string}

  gsplit: function(string, string, boolean): function(): string

  startswith: function(string, string): boolean

  schedule_wrap: function(function(...:any): any...): function(...:any): any...
  schedule: function(function)
  validate: function({string:{any}})
  trim: function(string): string

  enum ExtendBehavior
    'error'
    'keep'
    'force'
  end

  tbl_deep_extend: function(ExtendBehavior, table, table, ...: table): table

  tbl_extend: function(ExtendBehavior, table, table, ...: table): table

  tbl_map: function(function, table): table

  tbl_keys: function(table): table

  tbl_filter: function((function(any): boolean), table): table

  tbl_count: function(table): integer

  tbl_isempty: function(table): boolean

  tbl_islist: function(table): boolean

  tbl_contains: function(table, any): boolean

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
end
