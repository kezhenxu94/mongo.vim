autocmd BufNewFile,BufRead *.mongodb,*.mongosh setfiletype mongodb
" Override the built-in *.js -> javascript detection, which runs first.
" Neovim detects it up front in ftdetect/mongodb.lua instead.
if !has('nvim')
  autocmd BufNewFile,BufRead *.mongo.js set filetype=mongodb
endif
