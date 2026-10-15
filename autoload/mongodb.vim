" mongodb.vim: run, preview, hover, completion and metadata.

let s:cache = {}        " uri -> {'data': {key: decoded result}, 'jobs': {key: job}}
let s:run = {}          " running query: {'job', 'uri', 'start'}
let s:preview_buf = -1
let s:hover_at = []     " cursor position of a hover waiting for metadata

" ---------------------------------------------------------------- settings

function! mongodb#uri() abort
  for uri in [get(b:, 'mongodb_uri', ''), get(g:, 'mongodb_uri', ''), $MONGODB_URI]
    if !empty(uri)
      return uri
    endif
  endfor
  return 'mongodb://localhost:27017'
endfunction

function! s:redact(uri) abort
  return substitute(a:uri, '://[^:@/]*:\zs[^@]*\ze@', '***', '')
endfunction

" Database in effect at lnum: nearest `use X` above, else the last `use X`
" run in this buffer, else the URI path, else test.
function! mongodb#current_db(...) abort
  let lnum = get(a:000, 0, line('.'))
  while lnum > 0
    let m = matchlist(getline(lnum), '^\s*use\s\+\([^ ;]\+\)')
    if !empty(m)
      return m[1]
    endif
    let lnum -= 1
  endwhile
  if !empty(get(b:, 'mongodb_db', ''))
    return b:mongodb_db
  endif
  let db = matchstr(mongodb#uri(), '^mongodb\%(+srv\)\=://[^/]*/\zs[^?]\+')
  return empty(db) ? 'test' : db
endfunction

function! s:mongosh(uri, code) abort
  return [get(g:, 'mongodb_mongosh', 'mongosh'), a:uri, '--quiet', '--eval', a:code]
endfunction

" -------------------------------------------------------------- statements

" Split lines into top-level statements: [{'start', 'end', 'text'}].
" Tracks strings, comments, regex literals and bracket depth. A statement
" ends at a top-level `;`, or at the end of a line unless the line ends with
" an operator or the next code line starts with `.`, `?`, `:`, `&&` or `||`.
function! mongodb#statements(lines, ...) abort
  let first = get(a:000, 0, 1)
  let stmts = []
  let n = len(a:lines)
  let depth = 0
  let state = ''
  let prev = ''
  let cur = {'start': 0, 'text': []}
  let i = 0
  while i < n
    let line = a:lines[i]
    let len = strlen(line)
    let from = 0
    let last = ''
    let j = 0
    while j < len
      let c = line[j]
      if state ==# '*'
        if c ==# '*' && line[j + 1] ==# '/'
          let state = ''
          let j += 1
        endif
      elseif state !=# ''
        if c ==# '\'
          let j += 1
        elseif c ==# state
          let state = ''
        endif
        let last = c
      elseif c ==# '/' && line[j + 1] ==# '/'
        break
      elseif c ==# '/' && line[j + 1] ==# '*'
        let state = '*'
        let j += 1
      elseif c ==# ';' && depth == 0
        if cur.start
          call add(cur.text, strpart(line, from, j - from))
          call s:push(stmts, cur, i + first)
        endif
        let cur = {'start': 0, 'text': []}
        let from = j + 1
        let prev = c
      elseif c !~# '\s'
        if !cur.start
          let cur.start = i + first
          let from = j
        endif
        if c =~# '[''"`]'
          let state = c
        elseif c ==# '/' && (prev ==# '' || prev =~# '[(,=:[!&|?{};]')
          let j = s:skip_regex(line, j)
          let c = '/r'
        elseif c =~# '[([{]'
          let depth += 1
        elseif c =~# '[)\]}]'
          let depth = max([0, depth - 1])
        endif
        let last = c
        let prev = c
      endif
      let j += 1
    endwhile
    if state =~# '[''"]'
      let state = ''
    endif
    if cur.start
      call add(cur.text, strpart(line, from))
      if depth == 0 && state ==# '' && !s:continues(last, a:lines, i + 1)
        call s:push(stmts, cur, i + first)
        let cur = {'start': 0, 'text': []}
      endif
    endif
    let i += 1
  endwhile
  if cur.start
    call s:push(stmts, cur, n + first - 1)
  endif
  return stmts
endfunction

function! s:push(stmts, cur, end) abort
  let text = trim(join(a:cur.text, "\n"))
  if !empty(text)
    call add(a:stmts, {'start': a:cur.start, 'end': a:end, 'text': text})
  endif
endfunction

function! s:skip_regex(line, j) abort
  let j = a:j + 1
  let cls = 0
  while j < strlen(a:line)
    let c = a:line[j]
    if c ==# '\'
      let j += 1
    elseif c ==# '['
      let cls = 1
    elseif c ==# ']'
      let cls = 0
    elseif c ==# '/' && !cls
      return j
    endif
    let j += 1
  endwhile
  return j
endfunction

function! s:continues(last, lines, next) abort
  if a:last =~# '^[.,+\-*=&|?:<>!(\[{]$'
    return 1
  endif
  let k = a:next
  while k < len(a:lines)
    let l = a:lines[k]
    if l !~# '^\s*\%(//.*\)\=$'
      return l =~# '^\s*\%(\.\|?\|:\|&&\|||\)'
    endif
    let k += 1
  endwhile
  return 0
endfunction

" Line range [start, end] of the statement under lnum, or [] if none.
function! mongodb#statement_range(lnum) abort
  if has('nvim') && get(g:, 'mongodb_treesitter', 1)
    let r = luaeval('require("mongodb.ts").range(_A[1], _A[2])', [bufnr('%'), a:lnum])
    if !empty(r)
      return r
    endif
  endif
  for st in mongodb#statements(getline(1, '$'))
    if st.start <= a:lnum && a:lnum <= st.end
      return [st.start, st.end]
    endif
  endfor
  return []
endfunction

let s:decl = '^\%(const\|let\|var\|function\|async\s\+function\|class\|if\|for\|while\|do\|try\|switch\|return\|throw\|import\|export\)\>\|^{'

" Turn statements into one mongosh --eval script that prints the result of
" every expression statement, like the interactive shell does.
function! mongodb#script(stmts) abort
  let many = len(filter(copy(a:stmts), 'v:val.text !~# ''^use\s'' && v:val.text !~# s:decl')) > 1
  let out = ['const __mp = (v) => { if (v !== undefined) print(v) };']
  for st in a:stmts
    let t = st.text
    let m = matchlist(t, '^use\s\+\(\S\+\)$')
    if !empty(m)
      call add(out, printf('db = db.getSiblingDB(%s);', json_encode(m[1])))
      continue
    endif
    if t =~# '^it$'
      continue
    endif
    if many && t !~# s:decl
      let head = substitute(split(t, "\n")[0], '\s\+', ' ', 'g')
      call add(out, printf('print(%s);', json_encode('// L' . st.start . ': ' . strcharpart(head, 0, 70))))
    endif
    if t =~# '^show\s\+\%(dbs\|databases\)$'
      call add(out, 'print(db.adminCommand({ listDatabases: 1, nameOnly: true }).databases.map((d) => d.name).join("\n"));')
    elseif t =~# '^show\s\+\%(collections\|tables\)$'
      call add(out, 'print(db.getCollectionNames().sort().join("\n"));')
    elseif t =~# '^show\s\+users$'
      call add(out, '__mp(db.getUsers());')
    elseif t =~# s:decl
      call add(out, t . ';')
    else
      call add(out, "__mp(\n" . t . "\n);")
    endif
  endfor
  return join(out, "\n")
endfunction

" Statements of lines [l1, l2] plus the nearest `use` above them, else the
" last `use` run in this buffer.
function! s:with_context(l1, l2) abort
  let stmts = mongodb#statements(getline(a:l1, a:l2), a:l1)
  if empty(stmts)
    return []
  endif
  if stmts[0].text !~# '^use\s'
    let lnum = a:l1 - 1
    while lnum > 0
      let m = matchlist(getline(lnum), '^\s*\(use\s\+[^ ;]\+\)')
      if !empty(m)
        call insert(stmts, {'start': lnum, 'end': lnum, 'text': m[1]})
        break
      endif
      let lnum -= 1
    endwhile
    if lnum == 0 && !empty(get(b:, 'mongodb_db', ''))
      call insert(stmts, {'start': 0, 'end': 0, 'text': 'use ' . b:mongodb_db})
    endif
  endif
  return stmts
endfunction

" -------------------------------------------------------------------- run

function! mongodb#run(l1, l2) abort
  call s:execute(s:with_context(a:l1, a:l2))
endfunction

function! mongodb#run_statement() abort
  let r = mongodb#statement_range(line('.'))
  if empty(r)
    echohl WarningMsg | echo 'mongodb: no statement under cursor' | echohl None
    return
  endif
  call s:execute(s:with_context(r[0], r[1]))
endfunction

function! s:execute(stmts) abort
  if empty(a:stmts)
    echohl WarningMsg | echo 'mongodb: nothing to run' | echohl None
    return
  endif
  for st in a:stmts
    let m = matchlist(st.text, '^use\s\+\(\S\+\)$')
    if !empty(m)
      let b:mongodb_db = m[1]
    endif
  endfor
  call mongodb#stop()
  let run = {'uri': mongodb#uri(), 'start': reltime(),
        \ 'script': get(g:, 'mongodb_echo_script', 1) ? map(split(join(map(copy(a:stmts), 'v:val.text'), "\n"), "\n"), '"// " . v:val') : []}
  let s:run = run
  call s:preview(['// running on ' . s:redact(run.uri) . ' … (<C-c> to cancel)'])
  let run.job = mongodb#compat#job(s:mongosh(run.uri, mongodb#script(a:stmts)),
        \ {lines, code -> s:executed(run, lines, code)})
endfunction

function! s:header(run, status) abort
  return ['// ' . s:redact(a:run.uri), printf('// %.2fs%s', reltimefloat(reltime(a:run.start)), a:status)] + a:run.script
endfunction

" Ignores runs that were cancelled or replaced by a newer one.
function! s:executed(run, lines, code) abort
  if a:run isnot s:run
    return
  endif
  let s:run = {}
  call s:preview(s:header(a:run, a:code ? ' · exit ' . a:code : '') + a:lines)
endfunction

function! mongodb#stop() abort
  if empty(s:run)
    return
  endif
  call mongodb#compat#stop(get(s:run, 'job', 0))
  call s:preview(s:header(s:run, ' · cancelled'))
  let s:run = {}
endfunction

function! s:preview(lines) abort
  if !bufexists(s:preview_buf)
    let s:preview_buf = bufadd('[MongoDB]')
    call bufload(s:preview_buf)
    call setbufvar(s:preview_buf, '&buftype', 'nofile')
    call setbufvar(s:preview_buf, '&bufhidden', 'hide')
    call setbufvar(s:preview_buf, '&swapfile', 0)
    call setbufvar(s:preview_buf, '&buflisted', 0)
  endif
  let winid = bufwinid(s:preview_buf)
  if winid == -1
    let cur = win_getid()
    execute 'belowright vertical ' . get(g:, 'mongodb_preview_width', max([winwidth(0) / 2, 1])) . 'split'
    execute 'buffer ' . s:preview_buf
    setlocal filetype=javascript winfixwidth signcolumn=no
    nnoremap <buffer> <silent> q :close<CR>
    nnoremap <buffer> <silent> <C-c> :<C-u>call mongodb#stop()<CR>
    let winid = win_getid()
    call win_gotoid(cur)
  endif
  call setbufvar(s:preview_buf, '&modifiable', 1)
  silent call deletebufline(s:preview_buf, 1, '$')
  call setbufline(s:preview_buf, 1, a:lines)
  call setbufvar(s:preview_buf, '&modifiable', 0)
  call win_execute(winid, 'normal! gg')
endfunction

" --------------------------------------------------------------- metadata

let s:js_dbs = join([
      \ 'const out = {};',
      \ 'for (const d of db.adminCommand({ listDatabases: 1, nameOnly: true, authorizedDatabases: true }).databases)',
      \ '  out[d.name] = db.getSiblingDB(d.name).getCollectionNames();',
      \ 'print(EJSON.stringify(out));'], "\n")

let s:js_coll = join([
      \ 'const t = (v) => v === null ? "null" : Array.isArray(v) ? "array" : v instanceof Date ? "date"',
      \ '  : v && v._bsontype ? v._bsontype : typeof v;',
      \ 'const s = {};',
      \ 'const walk = (o, p) => { for (const k of Object.keys(o)) {',
      \ '  const v = o[k], f = p ? p + "." + k : k, ty = t(v);',
      \ '  (s[f] = s[f] || {})[ty] = 1; if (ty === "object") walk(v, f); } };',
      \ 'const c = db.getSiblingDB(%s).getCollection(%s);',
      \ 'c.aggregate([{ $sample: { size: 50 } }]).forEach((d) => walk(d, ""));',
      \ 'print(EJSON.stringify({ count: c.estimatedDocumentCount(),',
      \ '  indexes: c.getIndexes().map((i) => ({ name: i.name, key: i.key })),',
      \ '  fields: Object.fromEntries(Object.entries(s).map(([k, v]) => [k, Object.keys(v)])) }));'], "\n")

let s:js_db = 'print(EJSON.stringify(db.getSiblingDB(%s).stats()))'

function! s:meta() abort
  let uri = mongodb#uri()
  if !has_key(s:cache, uri)
    let s:cache[uri] = {'data': {}, 'jobs': {}}
  endif
  return s:cache[uri]
endfunction

function! s:decode(lines) abort
  for l in reverse(copy(a:lines))
    if l =~# '^{'
      try
        return json_decode(l)
      catch
      endtry
    endif
  endfor
  return {}
endfunction

" Cached metadata under key, fetched in the background on first use; {} until
" it arrives. Never blocks.
function! s:get(key, code) abort
  let meta = s:meta()
  if has_key(meta.data, a:key)
    return meta.data[a:key]
  endif
  if !mongodb#compat#running(get(meta.jobs, a:key, 0))
    let meta.jobs[a:key] = mongodb#compat#job(s:mongosh(mongodb#uri(), a:code),
          \ {lines, code -> s:loaded(meta, a:key, lines, code)})
  endif
  return get(meta.data, a:key, {})
endfunction

function! s:loading(key) abort
  return mongodb#compat#running(get(s:meta().jobs, a:key, 0))
endfunction

function! s:loaded(meta, key, lines, code) abort
  let r = a:code == 0 ? s:decode(a:lines) : {}
  if empty(r)
    if !empty(s:hover_at)
      let s:hover_at = []
      echohl ErrorMsg | echo 'mongodb: failed to load metadata: ' . get(a:lines, -1, '') | echohl None
    endif
    return
  endif
  let a:meta.data[a:key] = r
  if a:key ==# 'dbs'
    call mongodb#highlight_all()
  endif
  call s:refresh_menu()
  call s:hover_resume()
endfunction

function! s:dbs() abort
  return s:get('dbs', s:js_dbs)
endfunction

function! s:coll_key(db, coll) abort
  return 'coll:' . a:db . '.' . a:coll
endfunction

function! s:stats(db) abort
  return s:get('stats:' . a:db, printf(s:js_db, json_encode(a:db)))
endfunction

function! mongodb#refresh() abort
  let uri = mongodb#uri()
  if has_key(s:cache, uri)
    call remove(s:cache, uri)
  endif
  call s:dbs()
endfunction

function! mongodb#databases() abort
  return sort(keys(s:dbs()))
endfunction

function! mongodb#collections(db) abort
  return sort(copy(get(s:dbs(), a:db, [])))
endfunction

" Collection info {count, indexes, fields}.
function! mongodb#collection(db, coll) abort
  return s:get(s:coll_key(a:db, a:coll), printf(s:js_coll, json_encode(a:db), json_encode(a:coll)))
endfunction

" ------------------------------------------------------------- completion

function! s:item(word, kind, menu, ...) abort
  let item = {'word': a:word, 'kind': a:kind, 'menu': a:menu, 'dup': 0}
  if a:0
    let item.info = a:1[0] . "\n\n" . a:1[1]
  endif
  return item
endfunction

" Collection referenced by the statement around the cursor, e.g. db.users.find(
function! s:stmt_collection() abort
  let [lnum, col] = searchpos('\<db\.\%(\h\w*\|getCollection(\s*[''"][^''"]\+[''"]\s*)\)\.\h\w*\s*(', 'bnW', max([1, line('.') - 50]))
  if lnum == 0
    return ''
  endif
  let text = strpart(getline(lnum), col - 1)
  let m = matchlist(text, '^db\.\%(getCollection(\s*[''"]\([^''"]\+\)[''"]\s*)\|\(\h\w*\)\)')
  return empty(m[1]) ? m[2] : m[1]
endfunction

function! s:context() abort
  let pre = strpart(getline('.'), 0, col('.') - 1)
  let rules = [
        \ ['^\s*use\s\+\zs[[:alnum:]_-]*$', 'dbs'],
        \ ['^\s*show\s\+\zs\w*$', 'show'],
        \ ['\<db\.\zs\w*$', 'db'],
        \ ['\<db\.\%(\h\w*\|getCollection([^)]*)\)\.\zs\w*$', 'collection'],
        \ ['[''"]\$\zs[[:alnum:]_.]*$', 'fieldref'],
        \ ['\$\w*$', 'operator'],
        \ ['\%()\s*\|^\s*\)\.\zs\w*$', 'cursor'],
        \ ['\%([{,]\s*[''"]\=\|^\s*[''"]\=\)\zs[[:alnum:]_.]*$', 'field'],
        \ ]
  for [pat, kind] in rules
    let start = match(pre, pat)
    if start >= 0
      if kind ==# 'field' && (empty(s:stmt_collection()) || !s:in_braces())
        continue
      endif
      return [start, kind]
    endif
  endfor
  return [match(pre, '\h\w*$'), 'global']
endfunction

function! s:in_braces() abort
  let pos = searchpairpos('{', '', '}', 'bnW', '', max([1, line('.') - 50]))
  return pos[0] > 0
endfunction

function! mongodb#complete(findstart, base) abort
  if a:findstart
    let [start, s:ctx] = s:context()
    return start < 0 ? -3 : start
  endif
  return filter(s:candidates(s:ctx), 'stridx(v:val.word, a:base) == 0')
endfunction

function! s:candidates(kind) abort
  let docs = mongodb#docs#get()
  let db = mongodb#current_db()
  let items = []
  if a:kind ==# 'dbs'
    call map(mongodb#databases(), 'add(items, s:item(v:val, "d", "[db]"))')
  elseif a:kind ==# 'show'
    call map(['dbs', 'databases', 'collections', 'tables', 'users'], 'add(items, s:item(v:val, "k", "[show]"))')
  elseif a:kind ==# 'db'
    call map(mongodb#collections(db), 'add(items, s:item(v:val, "t", "[" . db . "]"))')
    call map(sort(keys(docs.db)), 'add(items, s:item(v:val, "f", "[db]", docs.db[v:val]))')
  elseif a:kind ==# 'collection'
    call map(sort(keys(docs.collection)), 'add(items, s:item(v:val, "f", "[collection]", docs.collection[v:val]))')
  elseif a:kind ==# 'cursor'
    call map(sort(keys(docs.cursor)), 'add(items, s:item(v:val, "f", "[cursor]", docs.cursor[v:val]))')
  elseif a:kind ==# 'operator'
    call map(sort(keys(docs.operator)), 'add(items, s:item(v:val, "o", "[op]", docs.operator[v:val]))')
  elseif a:kind ==# 'field' || a:kind ==# 'fieldref'
    let coll = s:stmt_collection()
    if !empty(coll)
      let fields = get(mongodb#collection(db, coll), 'fields', {})
      call map(sort(keys(fields)), 'add(items, extend(s:item(v:val, "v", join(fields[v:val], "|")), {"user_data": a:kind}))')
    endif
  else
    for kind in ['bson', 'shell']
      call map(sort(keys(docs[kind])), 'add(items, s:item(v:val, "f", "[" . kind . "]", docs[kind][v:val]))')
    endfor
  endif
  return items
endfunction

" Called on TextChangedI: open the menu after `use `, `db.`, `.`, `$` etc.
" Metadata loads in the background; the menu is refreshed when it arrives.
function! mongodb#autocomplete() abort
  if !pumvisible()
    call s:show_menu()
  endif
endfunction

" Metadata arrived: redo the menu if still typing in a mongodb buffer.
function! s:refresh_menu() abort
  if &filetype ==# 'mongodb' && get(g:, 'mongodb_autocomplete', 1)
    call s:show_menu()
  endif
endfunction

function! s:show_menu() abort
  if mode() !=# 'i'
    return
  endif
  let pre = strpart(getline('.'), 0, col('.') - 1)
  if pre !~# '\%(\.\|\$\|\<use \|\w\w\)$'
    return
  endif
  let [start, kind] = s:context()
  if start < 0 || (kind ==# 'global' && col('.') - 1 - start < 2)
    return
  endif
  let base = strpart(pre, start)
  let items = filter(s:candidates(kind), 'stridx(v:val.word, base) == 0 && v:val.word !=# base')
  if !empty(items)
    call complete(start + 1, items)
  endif
endfunction

" Called on CompleteDone: a dotted field path used as an object key must be
" quoted, so `address.city` becomes 'address.city'.
function! mongodb#complete_done() abort
  let item = get(v:, 'completed_item', {})
  if get(item, 'user_data', '') !=# 'field' || item.word !~# '\.'
    return
  endif
  let col = col('.') - 1
  let line = getline('.')
  let start = col - strlen(item.word)
  if strpart(line, start, strlen(item.word)) !=# item.word || line[start - 1] =~# '[''"]'
    return
  endif
  call setline('.', strpart(line, 0, start) . "'" . item.word . "'" . strpart(line, col))
  call cursor(line('.'), col + 3)
endfunction

" ------------------------------------------------------------------ hover

" Missing metadata is fetched in the background; the popup opens once it
" arrives, if the cursor hasn't moved.
function! mongodb#hover() abort
  let lines = mongodb#hover_lines()
  if lines is v:null
    let s:hover_at = [bufnr(), getcurpos()]
    echo 'mongodb: loading...'
    return
  endif
  if empty(lines)
    echo 'mongodb: no documentation for ' . expand('<cword>')
    return
  endif
  call mongodb#compat#hover(lines)
endfunction

function! s:hover_resume() abort
  let at = s:hover_at
  let s:hover_at = []
  if at ==# [bufnr(), getcurpos()] && mode() ==# 'n'
    echo ''
    call mongodb#hover()
  endif
endfunction

" Markdown lines describing the word under the cursor, or v:null while the
" metadata they need is still loading.
function! mongodb#hover_lines() abort
  let line = getline('.')
  let col = col('.') - 1
  " Database names may contain '-', which the word scan below stops at.
  let [db, s, e] = matchstrpos(line, '^\s*use\s\+\zs[^ ;]\+')
  if s >= 0 && s <= col && col < e
    return s:hover_db(db)
  endif
  let s = col
  while s > 0 && line[s - 1] =~# '[[:alnum:]_$.]'
    let s -= 1
  endwhile
  let e = col
  while e < strlen(line) && line[e] =~# '[[:alnum:]_$]'
    let e += 1
  endwhile
  let token = strpart(line, s, e - s)
  let word = matchstr(token, '[[:alnum:]_$]*$')
  let pre = strpart(line, 0, s) . strpart(token, 0, strlen(token) - strlen(word))
  return s:hover_lines(word, token, pre)
endfunction

function! s:doc(entry) abort
  return ['```javascript', a:entry[0], '```', a:entry[1]]
endfunction

function! s:hover_lines(word, token, pre) abort
  if empty(a:word)
    return []
  endif
  let docs = mongodb#docs#get()
  let db = mongodb#current_db()
  if a:pre =~# '\<db\.$'
    if has_key(docs.db, a:word)
      return s:doc(docs.db[a:word])
    endif
    return s:hover_collection(db, a:word)
  endif
  let m = matchlist(a:pre, 'getCollection(\s*[''"]$')
  if !empty(m)
    return s:hover_collection(db, a:word)
  endif
  if a:pre =~# '\.$'
    for kind in a:pre =~# '\<db\.\h\w*\.$' ? ['collection', 'cursor'] : ['cursor', 'collection']
      if has_key(docs[kind], a:word)
        return s:doc(docs[kind][a:word])
      endif
    endfor
  endif
  if has_key(docs.operator, a:word)
    return s:doc(docs.operator[a:word])
  endif
  for kind in ['bson', 'shell']
    if has_key(docs[kind], a:word)
      return s:doc(docs[kind][a:word])
    endif
  endfor
  let coll = s:stmt_collection()
  if !empty(coll)
    let fields = get(mongodb#collection(db, coll), 'fields', {})
    if s:loading(s:coll_key(db, coll))
      return v:null
    endif
    let path = substitute(a:token, '^\$', '', '')
    for f in [path, a:word]
      if has_key(fields, f)
        return ['**' . f . '** in `' . db . '.' . coll . '`', '', 'types: ' . join(fields[f], ' | ')]
      endif
    endfor
  endif
  return []
endfunction

function! s:hover_collection(db, coll) abort
  let colls = mongodb#collections(a:db)
  if s:loading('dbs')
    return v:null
  endif
  if index(colls, a:coll) < 0
    return ['**' . a:db . '.' . a:coll . '**', '', '_collection does not exist (yet)_']
  endif
  let info = mongodb#collection(a:db, a:coll)
  if s:loading(s:coll_key(a:db, a:coll))
    return v:null
  endif
  if empty(info)
    return []
  endif
  let lines = ['**' . a:db . '.' . a:coll . '** · ' . info.count . ' documents', '', 'Indexes:']
  for idx in info.indexes
    call add(lines, '- `' . idx.name . '` `' . substitute(json_encode(idx.key), '"', '', 'g') . '`')
  endfor
  call extend(lines, ['', 'Fields (sampled):', '```javascript'])
  let width = max(map(keys(info.fields), 'strlen(v:val)'))
  for f in sort(keys(info.fields))
    call add(lines, printf('%-*s  %s', width, f, join(info.fields[f], ' | ')))
  endfor
  return add(lines, '```')
endfunction

function! s:hover_db(db) abort
  let dbs = s:dbs()
  if s:loading('dbs')
    return v:null
  endif
  if !has_key(dbs, a:db)
    return ['**' . a:db . '**', '', '_database does not exist (yet)_']
  endif
  let st = s:stats(a:db)
  if s:loading('stats:' . a:db)
    return v:null
  endif
  let lines = ['**' . a:db . '**' . (empty(st) ? '' : printf(' · %d objects · %.1f KiB data · %d indexes',
        \ get(st, 'objects', 0), get(st, 'dataSize', 0) / 1024.0, get(st, 'indexes', 0))), '', 'Collections:']
  for c in sort(copy(dbs[a:db]))
    call add(lines, '- ' . c)
  endfor
  return lines
endfunction

" ------------------------------------------------------------- highlight

" Highlight collection names that exist on the server (schema-aware).
function! mongodb#highlight() abort
  if exists('w:mongodb_hl')
    silent! call matchdelete(w:mongodb_hl)
    unlet w:mongodb_hl
  endif
  if &filetype !=# 'mongodb'
    return
  endif
  highlight default link mongodbCollection Structure
  let names = {}
  for [db, colls] in items(get(s:meta().data, "dbs", {}))
    for c in colls
      if c =~# '^\h\w*$'
        let names[c] = 1
      endif
    endfor
  endfor
  if empty(names)
    return
  endif
  let alt = '\%(' . join(sort(keys(names)), '\|') . '\)'
  let w:mongodb_hl = matchadd('mongodbCollection',
        \ '\<db\.\zs' . alt . '\>\|getCollection(\s*[''"]\zs' . alt . '\ze[''"]', 5)
endfunction

function! mongodb#highlight_all() abort
  for winid in range(1, winnr('$'))->map('win_getid(v:val)')
    call win_execute(winid, 'call mongodb#highlight()')
  endfor
endfunction

function! mongodb#init_buffer() abort
  call s:dbs()
  call mongodb#highlight()
endfunction
