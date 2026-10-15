" Headless tests for Vim and Neovim. Run via test/run.sh.
" Needs $MONGODB_URI pointing at a server seeded with demo/seed.js.

set virtualedit=onemore
runtime plugin/mongodb.vim

function! s:buf(lines, ...) abort
  enew!
  setfiletype mongodb
  call setline(1, a:lines)
  if a:0
    call cursor(a:1, a:2)
  endif
endfunction

" Metadata loads in the background: poll until Cond() is true.
function! s:wait(Cond) abort
  let start = reltime()
  while !a:Cond() && reltimefloat(reltime(start)) < 10
    sleep 20m
  endwhile
endfunction

function! s:hover() abort
  call s:wait({-> mongodb#hover_lines() isnot v:null})
  return mongodb#hover_lines()
endfunction

function! s:words(findstart_col) abort
  let start = mongodb#complete(1, '')
  call assert_equal(a:findstart_col, start)
  let base = strpart(getline('.'), start, col('.') - 1 - start)
  return map(mongodb#complete(0, base), 'v:val.word')
endfunction

function! Test_ftdetect() abort
  edit! /tmp/x.mongodb
  call assert_equal('mongodb', &filetype)
  call assert_equal('mongodb#complete', &omnifunc)
  bwipe!
endfunction

function! Test_uri() abort
  call s:buf([])
  call assert_equal($MONGODB_URI, mongodb#uri())
  let g:mongodb_uri = 'mongodb://g'
  call assert_equal('mongodb://g', mongodb#uri())
  let b:mongodb_uri = 'mongodb://b/shop'
  call assert_equal('mongodb://b/shop', mongodb#uri())
  call assert_equal('shop', mongodb#current_db())
  unlet g:mongodb_uri b:mongodb_uri
endfunction

function! Test_current_db() abort
  call s:buf(['use shop', 'db.users.find()', 'use analytics', 'db.events.find()'])
  call assert_equal('shop', mongodb#current_db(2))
  call assert_equal('analytics', mongodb#current_db(4))
endfunction

function! Test_statements() abort
  let lines = [
        \ '// comment ( {',
        \ 'use shop',
        \ '',
        \ 'db.users.find({ name: "a;b)" })',
        \ '  .sort({ age: -1 }) // trailing (',
        \ '',
        \ '  .limit(2)',
        \ 'db.orders.aggregate([',
        \ '  { $match: { re: /[)}]/ } },',
        \ '])',
        \ 'const x = 1; x + 1',
        \ '/* block',
        \ '   ( */',
        \ 'x +',
        \ '  2',
        \ ]
  let got = map(mongodb#statements(lines), '[v:val.start, v:val.end]')
  call assert_equal([[2, 2], [4, 7], [8, 10], [11, 11], [11, 11], [14, 15]], got)
  call assert_equal('const x = 1', mongodb#statements(lines)[3].text)
  call assert_equal('x + 1', mongodb#statements(lines)[4].text)
endfunction

function! Test_statement_range() abort
  call s:buf(readfile('demo/demo.mongodb'))
  call assert_equal([6, 8], mongodb#statement_range(7))
  call assert_equal([11, 15], mongodb#statement_range(13))
  call assert_equal([], mongodb#statement_range(9))
  call assert_equal([], mongodb#statement_range(10))
endfunction

function! Test_script() abort
  let stmts = mongodb#statements(['use shop', 'show collections', 'const n = 2', 'db.users.find().limit(n)'])
  let js = mongodb#script(stmts)
  call assert_match('db = db.getSiblingDB("shop");', js)
  call assert_match('print(db.getCollectionNames().sort().join', js)
  call assert_match("\nconst n = 2;\n", js)
  call assert_match("__mp(\ndb.users.find().limit(n)\n);", js)
  call assert_match('// L4: db.users.find', js)
endfunction

function! Test_complete_databases() abort
  call s:buf(['use sh'], 1, 7)
  call s:wait({-> !empty(mongodb#databases())})
  call assert_equal(['shop'], s:words(4))
endfunction

function! Test_complete_does_not_block() abort
  call mongodb#refresh()
  call s:buf(['use sh'], 1, 7)
  call assert_equal([], s:words(4))
  call s:wait({-> !empty(mongodb#databases())})
  call assert_equal(['shop'], filter(mongodb#databases(), 'v:val ==# "shop"'))
endfunction

function! Test_complete_collections() abort
  call s:buf(['use shop', 'db.'], 2, 4)
  call s:wait({-> !empty(mongodb#databases())})
  let words = s:words(3)
  call assert_equal(['orders', 'products', 'users'], words[:2])
  call assert_notequal(-1, index(words, 'getSiblingDB'))
endfunction

function! Test_complete_collection_methods() abort
  call s:buf(['use shop', 'db.users.fin'], 2, 13)
  call assert_equal(['find', 'findOne', 'findOneAndDelete', 'findOneAndReplace', 'findOneAndUpdate'], s:words(9))
endfunction

function! Test_complete_cursor_methods() abort
  call s:buf(['db.users.find({})', '  .so'], 2, 6)
  call assert_equal(['sort'], s:words(3))
  call s:buf(['db.users.find({}).li'], 1, 21)
  call assert_equal(['limit'], s:words(18))
endfunction

function! Test_complete_operators() abort
  call s:buf(['db.users.find({ age: { $g'], 1, 26)
  call assert_equal(['$graphLookup', '$group', '$gt', '$gte'], s:words(23))
endfunction

function! Test_complete_fields() abort
  call s:wait({-> !empty(mongodb#collection('shop', 'users')) && !empty(mongodb#collection('shop', 'orders'))})
  call s:buf(['use shop', 'db.users.find({ addr'], 2, 21)
  call assert_equal(['address', 'address.city', 'address.zip'], s:words(16))
  call s:buf(['use shop', 'db.orders.aggregate([{ $group: { _id: "$st'], 2, 43)
  call assert_equal(['status'], s:words(40))
endfunction

function! Test_hover_docs() abort
  call s:buf(['db.users.find({ age: { $gte: 1 } })'], 1, 11)
  call assert_equal('find(filter?, projection?, options?)', s:hover()[1])
  call cursor(1, 25)
  call assert_match('greater than or equal', s:hover()[3])
endfunction

function! Test_hover_does_not_block() abort
  call mongodb#refresh()
  call s:buf(['use shop', 'db.users.find()'], 2, 5)
  call assert_equal(v:null, mongodb#hover_lines())
  call assert_equal('**shop.users** · 25 documents', s:hover()[0])
endfunction

function! Test_hover_collection() abort
  call s:buf(['use shop', 'db.users.find()'], 2, 5)
  let lines = s:hover()
  call assert_equal('**shop.users** · 25 documents', lines[0])
  call assert_match('email_1', join(lines))
  call assert_match('address.city\s\+string', join(lines, "\n"))
endfunction

function! Test_hover_database_and_field() abort
  call s:buf(['use shop', 'db.users.find({ age: 1 })'], 1, 6)
  let lines = s:hover()
  call assert_match('^\*\*shop\*\* · \d\+ objects', lines[0])
  call assert_notequal(-1, index(lines, '- orders'))
  call cursor(2, 17)
  call assert_equal('types: number', s:hover()[2])
  call s:buf(['use test-db'], 1, 7)
  call assert_equal('**test-db**', s:hover()[0])
endfunction

function! s:wait_preview() abort
  let buf = bufnr('[[]MongoDB]')
  let start = reltime()
  while reltimefloat(reltime(start)) < 10 && getbufline(buf, 1)[0] =~# 'running'
    sleep 50m
  endwhile
  return getbufline(buf, 1, '$')
endfunction

function! Test_run_statement() abort
  call s:buf(readfile('demo/demo.mongodb'), 12, 1)
  call mongodb#run_statement()
  let out = s:wait_preview()
  call assert_match('^// mongodb://', out[0])
  let [l1, l2] = mongodb#statement_range(12)
  let i = index(out, '// ' . getline(l1))
  call assert_equal(map(getline(l1, l2), '"// " . v:val'), out[i : i + l2 - l1])
  call assert_match('^// \d\+\.\d\+s$', out[i + l2 - l1 + 1])
  call assert_match("_id: 'paid'", join(out))
  call assert_notmatch('// L', join(out))
  call assert_equal('javascript', getbufvar(bufnr('[[]MongoDB]'), '&filetype'))
endfunction

function! Test_run_remembers_use() abort
  call s:buf(['use analytics;'], 1, 1)
  call mongodb#run_statement()
  call s:wait_preview()
  call setline(1, 'db.getName()')
  call assert_equal('analytics', mongodb#current_db())
  call mongodb#run_statement()
  let out = s:wait_preview()
  call assert_equal(['// use analytics', '// db.getName()'], out[1:2])
  call assert_equal('analytics', out[-1])
  unlet b:mongodb_db
endfunction

function! Test_stop_mapping() abort
  call s:buf(['sleep(10000)'], 1, 1)
  call mongodb#run_statement()
  execute "normal \<C-c>"
  call assert_match('· cancelled$', s:wait_preview()[2])
endfunction

function! Test_run_file() abort
  call s:buf(['use shop', 'show collections', 'db.users.countDocuments()', 'db.nope.find(', '1'])
  2,3MongoRun
  let out = s:wait_preview()
  call assert_match("// L2: show collections\norders\nproducts\nusers\n// L3: db.users.countDocuments()\n25", join(out, "\n"))
  %MongoRun
  let out = s:wait_preview()
  call assert_match('^// \d\+\.\d\+s · exit 1$', out[6])
  call assert_match('SyntaxError', join(out))
endfunction

function! Test_syntax() abort
  if has('nvim')
    return
  endif
  call s:buf(['use shop', 'db.users.find({ $or: [{ x: "$y" }] }).sort({}); ObjectId()'])
  let Name = {l, c -> synIDattr(synID(l, c, 1), 'name')}
  call assert_equal('mongodbShell', Name(1, 1))
  call assert_equal('mongodbShellArg', Name(1, 5))
  call assert_equal('mongodbDb', Name(2, 1))
  call assert_equal('mongodbMethod', Name(2, 10))
  call assert_equal('mongodbOperator', Name(2, 17))
  call assert_equal('mongodbFieldRef', Name(2, 30))
  call assert_equal('mongodbMethod', Name(2, 39))
  call assert_equal('mongodbBson', Name(2, 50))
endfunction

function! Test_treesitter() abort
  if !has('nvim') || !luaeval('require("mongodb.ts").available()')
    return
  endif
  call s:buf(['db.users.find({ $or: [{ x: "$y" }] })', '  .sort({})', '', 'ObjectId()'])
  call assert_true(luaeval('vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil'))
  let Caps = {l, c -> luaeval('vim.tbl_map(function(c) return c.capture end, vim.treesitter.get_captures_at_pos(0, _A[1], _A[2]))', [l - 1, c - 1])}
  call assert_notequal(-1, index(Caps(1, 1), 'variable.builtin'))
  call assert_notequal(-1, index(Caps(1, 17), 'keyword.operator'))
  call assert_notequal(-1, index(Caps(1, 30), 'variable.member'))
  call assert_notequal(-1, index(Caps(4, 1), 'type.builtin'))
  call assert_equal([1, 2], luaeval('require("mongodb.ts").range(0, 2)'))
  call s:buf(['use staging;', 'use production;', 'show dbs', 'const use = 1;'])
  for l in [1, 2, 3]
    call assert_notequal(-1, index(Caps(l, 1), 'keyword'), 'line ' . l)
    call assert_equal('module', Caps(l, 6)[-1], 'line ' . l)
  endfor
  call assert_equal(-1, index(Caps(4, 7), 'keyword'))
endfunction

function! Test_collection_highlight() abort
  call s:buf(['use shop', 'db.users.find()', 'db.nope.find()'])
  call s:wait({-> !empty(mongodb#databases())})
  call mongodb#highlight()
  let pat = filter(getmatches(), 'v:val.group ==# "mongodbCollection"')[0].pattern
  call assert_match(pat, 'db.users')
  call assert_notmatch(pat, 'db.nope')
endfunction

" ------------------------------------------------------------------ runner
let s:failed = 0
let s:out = []
for s:name in sort(filter(map(split(execute('function /^Test_'), "\n"), 'matchstr(v:val, ''Test_\w\+'')'), '!empty(v:val)'))
  let v:errors = []
  try
    call call(s:name, [])
  catch
    call add(v:errors, v:exception . ' @ ' . v:throwpoint)
  endtry
  if empty(v:errors)
    call add(s:out, 'ok   ' . s:name)
  else
    let s:failed += 1
    call add(s:out, 'FAIL ' . s:name)
    call extend(s:out, map(copy(v:errors), '"     " . v:val'))
  endif
endfor
call writefile(s:out, $TEST_RESULT)
execute s:failed ? 'cquit!' : 'qall!'
