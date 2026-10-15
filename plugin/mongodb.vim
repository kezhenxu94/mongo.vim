if exists('g:loaded_mongodb')
  finish
endif
let g:loaded_mongodb = 1

command! -nargs=? MongoConnect let g:mongodb_uri = empty(<q-args>) ? get(g:, 'mongodb_uri', '') : <q-args>
      \ | call mongodb#refresh() | echo 'mongodb: ' . substitute(mongodb#uri(), '://[^:@/]*:\zs[^@]*\ze@', '***', '')
command! MongoRefresh call mongodb#refresh()
command! MongoStop call mongodb#stop()

augroup mongodb_highlight
  autocmd!
  autocmd BufWinEnter * if exists('w:mongodb_hl') || &filetype ==# 'mongodb' | call mongodb#highlight() | endif
augroup END
