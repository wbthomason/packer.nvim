-- Private variables and constants
local nvim = vim.api -- luacheck: ignore
-- Adapted from https://github.com/hkupty/nvimux
local nvim_vars = {}
setmetatable(nvim_vars, {
  __index = function(_, key) 
    local key_ = 'g:plague_' .. key
    return nvim.nvim_get_var(key_)
  end
})

local plague = {}
plague.src_repo = 'https://github.com/wbthomason/plague.nvim'
plague.config = {
  dependencies = true,
  on_start = true,
  plugin_dir = '~/.local/share/nvim/plugins'
}

plague.fns = {}
plague.cmds = {
  install = ':PlagueInstall',
  remove = ':PlagueRemove',
  update = ':PlagueUpdate',
  upgrade = ':PlagueUpgrade',
}

plague.plugins = nil
plague.triggers = {}

-- Function definitions
-- Utility functions
plague.fns.err = function (msg) 
  nvim.nvim_err_writeln("[Plague] " .. msg)
end

-- Plugin specification functions
plague.fns.plug_begin = function (...) 
  if arg.n > 0 then
    plague.config.plugin_dir = arg[1]
  elseif nvim_vars['plugin_dir'] then
    plague.config.plugin_dir = nvim_vars['plugin_dir']
  elseif #nvim.nvim_list_runtime_paths() > 0 then
    plague.config.plugin_dir = nvim.nvim_list_runtime_paths()[1] .. '/plugins'
  else
    plague.fns.err("Couldn't find the plugin directory!")
    return
  end

  plague.plugins = {}
  return 1
end

plague.fns.plug_end = function ()
 if plague.plugins == nil then
   plague.fns.err("Call plague#begin() first")
   return
 end
end

function! plug#end()
  if !exists('g:plugs')
    return s:err('Call plug#begin() first')
  endif

  if exists('#PlugLOD')
    augroup PlugLOD
      autocmd!
    augroup END
    augroup! PlugLOD
  endif
  let lod = { 'ft': {}, 'map': {}, 'cmd': {} }

  if exists('g:did_load_filetypes')
    filetype off
  endif
  for name in g:plugs_order
    if !has_key(g:plugs, name)
      continue
    endif
    let plug = g:plugs[name]
    if get(s:loaded, name, 0) || !has_key(plug, 'on') && !has_key(plug, 'for')
      let s:loaded[name] = 1
      continue
    endif

    if has_key(plug, 'on')
      let s:triggers[name] = { 'map': [], 'cmd': [] }
      for cmd in s:to_a(plug.on)
        if cmd =~? '^<Plug>.\+'
          if empty(mapcheck(cmd)) && empty(mapcheck(cmd, 'i'))
            call s:assoc(lod.map, cmd, name)
          endif
          call add(s:triggers[name].map, cmd)
        elseif cmd =~# '^[A-Z]'
          let cmd = substitute(cmd, '!*$', '', '')
          if exists(':'.cmd) != 2
            call s:assoc(lod.cmd, cmd, name)
          endif
          call add(s:triggers[name].cmd, cmd)
        else
          call s:err('Invalid `on` option: '.cmd.
          \ '. Should start with an uppercase letter or `<Plug>`.')
        endif
      endfor
    endif

    if has_key(plug, 'for')
      let types = s:to_a(plug.for)
      if !empty(types)
        augroup filetypedetect
        call s:source(s:rtp(plug), 'ftdetect/**/*.vim', 'after/ftdetect/**/*.vim')
        augroup END
      endif
      for type in types
        call s:assoc(lod.ft, type, name)
      endfor
    endif
  endfor

  for [cmd, names] in items(lod.cmd)
    execute printf(
    \ 'command! -nargs=* -range -bang -complete=file %s call s:lod_cmd(%s, "<bang>", <line1>, <line2>, <q-args>, %s)',
    \ cmd, string(cmd), string(names))
  endfor

  for [map, names] in items(lod.map)
    for [mode, map_prefix, key_prefix] in
          \ [['i', '<C-O>', ''], ['n', '', ''], ['v', '', 'gv'], ['o', '', '']]
      execute printf(
      \ '%snoremap <silent> %s %s:<C-U>call <SID>lod_map(%s, %s, %s, "%s")<CR>',
      \ mode, map, map_prefix, string(map), string(names), mode != 'i', key_prefix)
    endfor
  endfor

  for [ft, names] in items(lod.ft)
    augroup PlugLOD
      execute printf('autocmd FileType %s call <SID>lod_ft(%s, %s)',
            \ ft, string(ft), string(names))
    augroup END
  endfor

  call s:reorg_rtp()
  filetype plugin indent on
  if has('vim_starting')
    if has('syntax') && !exists('g:syntax_on')
      syntax enable
    end
  else
    call s:reload_plugins()
  endif
endfunction
