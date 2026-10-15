if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal omnifunc=mongodb#complete
setlocal iskeyword+=$
setlocal commentstring=//\ %s comments=s1:/*,mb:*,ex:*/,://
setlocal completeopt=menuone,noinsert,noselect,popup
let b:undo_ftplugin = 'setlocal omnifunc< iskeyword< commentstring< comments< completeopt<'

if has('nvim') && get(g:, 'mongodb_treesitter', 1)
  call luaeval('require("mongodb.ts").start(_A)', bufnr('%'))
endif

command! -buffer -range=% MongoRun call mongodb#run(<line1>, <line2>)
command! -buffer MongoRunStatement call mongodb#run_statement()
command! -buffer MongoHover call mongodb#hover()

nnoremap <buffer> <silent> <Plug>(mongodb-run-statement) :<C-u>call mongodb#run_statement()<CR>
nnoremap <buffer> <silent> <Plug>(mongodb-run-file) :<C-u>%MongoRun<CR>
xnoremap <buffer> <silent> <Plug>(mongodb-run-selection) :MongoRun<CR>
nnoremap <buffer> <silent> <Plug>(mongodb-hover) :<C-u>call mongodb#hover()<CR>
nnoremap <buffer> <silent> <Plug>(mongodb-stop) :<C-u>call mongodb#stop()<CR>

if !get(g:, 'mongodb_no_mappings', 0)
  nmap <buffer> <LocalLeader>rr <Plug>(mongodb-run-statement)
  nmap <buffer> <LocalLeader>rf <Plug>(mongodb-run-file)
  xmap <buffer> <LocalLeader>r <Plug>(mongodb-run-selection)
  nmap <buffer> K <Plug>(mongodb-hover)
  nmap <buffer> <C-c> <Plug>(mongodb-stop)
endif

if get(g:, 'mongodb_autocomplete', 1)
  augroup mongodb_autocomplete
    autocmd! * <buffer>
    autocmd TextChangedI <buffer> call mongodb#autocomplete()
  augroup END
endif
augroup mongodb_complete_done
  autocmd! * <buffer>
  autocmd CompleteDone <buffer> call mongodb#complete_done()
augroup END

call mongodb#init_buffer()
