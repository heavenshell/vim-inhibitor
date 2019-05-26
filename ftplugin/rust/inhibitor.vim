" File: inhibitor.vim
" Author: Shinya Ohyanagi <sohyanagi@gmail.com>
" WebPage: http://github.com/heavenshell/vim-inhibitor
" Description: Vim plugin for Rust
" License: BSD, see LICENSE for more details.
let s:save_cpo = &cpo
set cpo&vim

if get(b:, 'loaded_inhibitor')
  finish
endif

" version check
if !has('channel') || !has('job')
  echoerr '+channel and +job are required for inhibitor.vim'
  finish
endif

command! -buffer Inhibitor       :call inhibitor#run()
command! -buffer InhibitorFmt    :call inhibitor#fmt()
command! -buffer InhibitorErrors :silent! call inhibitor#errors()
noremap <silent> <buffer> <Plug>(Inhibitor)       :Inhibitor<CR>
noremap <silent> <buffer> <Plug>(InhibitorFmt)    :InhibitorFmt<CR>
noremap <silent> <buffer> <Plug>(InhibitorErrors) :InhibitorErrors<CR>

let b:loaded_inhibitor = 1

let &cpo = s:save_cpo
unlet s:save_cpo
