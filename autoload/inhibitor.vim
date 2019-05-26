let s:save_cpo = &cpo
set cpo&vim

let g:inhibitor_cargo = get(g:, 'inhibitor_cargo', '')
let g:inhibitor_rustfmt = get(g:, 'inhibitor_rustfmt ', '')
let g:inhibitor_use_clippy = get(g:, 'inhibitor_use_clippy', 0)
let g:inhibitor_callbacks = get(g:, 'inhibitor_callbacks', {})

let s:fmt_lines = []
let s:compile_lines = []
let s:rendered_errors = []
let s:changedtick = -1

function! s:callback(ch, msg) abort
  if a:msg =~ '^error:'
    echohl Error | echomsg a:msg | echohl None
  endif
  call add(s:compile_lines, a:msg)
endfunction

function! s:parse(compile_lines) abort
  let results = []
  for line in a:compile_lines
    try
      let json = json_decode(line)
      let message = json['message']
      let spans = message['spans']
      if len(spans) > 0
        call add(s:rendered_errors, message['rendered'])
        for span in spans
          let lnum = span['line_start']
          let col = span['column_start']
          let label = span['label']
          let text = span['text'][0]['text']
          if span['is_primary']
            if type(label) == type(v:null)
              let label = printf('%s : %s', message['message'], text)
            else
              let label = printf('%s : %s : %s', message['message'], label, text)
            endif
          else
            let label = printf('%s : %s ', label, text)
          endif
          let file = fnamemodify(fnamemodify(span['file_name'], ':t'), ':p')
          call add(results, {
            \ 'filename': file,
            \ 'lnum': lnum,
            \ 'col': col,
            \ 'text': label,
            \ })
        endfor
      endif
    catch
    endtry
  endfor
  return results
endfunction

function! s:exit_callback(ch, msg, mode)
  let results = s:parse(s:compile_lines)
  call setqflist(results, a:mode)

  if bufwinnr(bufnr('^__InhibitorScratch__$')) > 0
    " Update scratch
    call inhibitor#errors()
  endif

  if has_key(g:inhibitor_callbacks, 'after_run')
    call g:inhibitor_callbacks['after_run']()
  endif
endfunction

function! s:fmt_callback(ch, msg) abort
  call add(s:fmt_lines, a:msg)
endfunction

function! s:fmt_exit_callback(ch, msg) abort
  try
    let view = winsaveview()
    silent execute '% delete _'

    call setline(1, s:fmt_lines)
    call winrestview(view)
  catch
  endtry
endfunction

function! s:find_rustfmt_bin() abort
  if g:inhibitor_rustfmt != ''
    return executable(g:inhibitor_rustfmt) ? g:inhibitor_rustfmt : ''
  endif
  if executable('rustfmt')
    return exepath('rustfmt')
  endif
  return ''
endfunction

function! s:find_cargo_bin() abort
  if g:inhibitor_cargo != ''
    return g:inhibitor_cargo
  endif
  if executable('cargo')
    return exepath('cargo')
  endif
  return ''
endfunction

function! s:run(cmd, bufnum, options) abort
  let input = join(getbufline(a:bufnum, 1, '$'), "\n") . "\n"
  let s:job = job_start(a:cmd, a:options)
  let channel = job_getchannel(s:job)
  if ch_status(channel) ==# 'open'
    call ch_sendraw(channel, input)
    call ch_close_in(channel)
  endif
endfunction

function! inhibitor#errors() abort
  let content = join(s:rendered_errors, "\n")
  silent pedit __InhibitorScratch__
  silent wincmd P
  setlocal modifiable noreadonly
  setlocal nobuflisted buftype=nofile bufhidden=wipe ft=rust
  put =content
  0d_
  setlocal nomodifiable readonly
  silent wincmd p
endfunction

function! inhibitor#fmt() abort
  let bin = s:find_rustfmt_bin()
  if bin == ''
    return
  endif
  let mode = a:0 > 0 ? a:1 : 'r'

  if exists('s:job') && job_status(s:job) != 'stop'
    call job_stop(s:job)
  endif

  let s:fmt_lines = []
  let cmd = printf('%s --emit stdout', bin)
  let bufnum = bufnr('%')

  call s:run(cmd, bufnum, {
    \ 'callback': {c, m -> s:fmt_callback(c, m)},
    \ 'exit_cb': {c, m -> s:fmt_exit_callback(c, m)},
    \ 'in_mode': 'nl',
    \ })
endfunction

function! inhibitor#run(...) abort
  let bin = s:find_cargo_bin()
  if bin == ''
    return
  endif
  let bufnum = bufnr('%')
  let changedtick = getbufvar(bufnum, 'changedtick')
  if s:changedtick == changedtick
    " Nothing is changed.
    return
  endif
  let s:changedtick = changedtick

  if exists('s:job') && job_status(s:job) != 'stop'
    call job_stop(s:job)
  endif
  let mode = a:0 > 0 ? a:1 : 'r'

  let s:compile_lines = []
  let s:rendered_errors = []

  let linter = g:inhibitor_use_clippy == 1 ? 'clippy' : 'check'
  let cmd = printf('%s %s --message-format=json -q', bin, linter)
  call s:run(cmd, bufnum, {
    \ 'callback': {c, m -> s:callback(c, m)},
    \ 'exit_cb': {c, m -> s:exit_callback(c, m, mode)},
    \ 'in_mode': 'nl',
    \ })
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
