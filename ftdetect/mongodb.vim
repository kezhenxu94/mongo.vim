autocmd BufNewFile,BufRead *.mongodb,*.mongosh setfiletype mongodb
" Override the built-in *.js -> javascript detection, which runs first
autocmd BufNewFile,BufRead *.mongo.js set filetype=mongodb
