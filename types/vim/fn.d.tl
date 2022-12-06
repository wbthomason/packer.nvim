local record M
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
  getcompletion : function(string, string): {string}
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

return M
