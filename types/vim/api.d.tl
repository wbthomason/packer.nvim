local record M
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

return M
