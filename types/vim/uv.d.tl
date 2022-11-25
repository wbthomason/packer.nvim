local record M
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

return M
