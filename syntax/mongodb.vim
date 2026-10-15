if exists('b:current_syntax')
  finish
endif

runtime! syntax/javascript.vim
unlet! b:current_syntax

let s:docs = mongodb#docs#get()

syn match mongodbShell /^\s*\zs\%(use\|show\)\>/
syn match mongodbShell /^\s*\zsit\s*$/
syn keyword mongodbDb db
syn match mongodbOperator /\$\h\w*/
syn match mongodbFieldRef /\$[[:alnum:]_.]\+/ contained containedin=javaScriptStringS,javaScriptStringD
execute 'syn keyword mongodbBson ' . join(keys(s:docs.bson))
execute 'syn match mongodbMethod /\.\@1<=\%(' .
      \ join(uniq(sort(keys(s:docs.db) + keys(s:docs.collection) + keys(s:docs.cursor))), '\|') .
      \ '\)\ze\s*(/'

hi def link mongodbShell Statement
hi def link mongodbDb Special
hi def link mongodbOperator Keyword
hi def link mongodbFieldRef Identifier
hi def link mongodbBson Type
hi def link mongodbMethod Function

unlet s:docs
let b:current_syntax = 'mongodb'
