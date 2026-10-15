" Vim / Neovim shims: jobs and hover popups.

" Run cmd (a list, no shell) and call Cb(lines, exit_code) when it finishes.
" stderr is merged into the output.
function! mongodb#compat#job(cmd, Cb) abort
  let ctx = {'out': [], 'err': [], 'code': -1, 'closed': 0, 'Cb': a:Cb}
  if has('nvim')
    let id = jobstart(a:cmd, {
          \ 'stdout_buffered': 1, 'stderr_buffered': 1,
          \ 'on_stdout': {j, data, e -> extend(ctx.out, data)},
          \ 'on_stderr': {j, data, e -> extend(ctx.err, data)},
          \ 'on_exit': {j, code, e -> call(ctx.Cb, [s:trim(ctx.out + ctx.err), code])}})
    if id <= 0
      call a:Cb(['failed to start: ' . a:cmd[0]], -1)
    endif
    return id
  endif
  " exit_cb and close_cb may arrive in either order.
  let job = job_start(a:cmd, {
        \ 'err_io': 'out',
        \ 'out_cb': {ch, msg -> add(ctx.out, msg)},
        \ 'exit_cb': {job, code -> s:vim_done(ctx, 'code', code)},
        \ 'close_cb': {ch -> s:vim_done(ctx, 'closed', 1)}})
  if job_status(job) ==# 'fail'
    call a:Cb(['failed to start: ' . a:cmd[0]], -1)
  endif
  return job
endfunction

function! s:vim_done(ctx, key, val) abort
  let a:ctx[a:key] = a:val
  if a:ctx.closed && a:ctx.code != -1
    call call(a:ctx.Cb, [s:trim(a:ctx.out), a:ctx.code])
  endif
endfunction

" Block until the job ends or timeout_ms passes. Returns 1 if it ended.
function! mongodb#compat#wait(job, timeout_ms) abort
  if has('nvim')
    return jobwait([a:job], a:timeout_ms)[0] != -1
  endif
  let start = reltime()
  while job_status(a:job) ==# 'run' || ch_status(job_getchannel(a:job)) !=# 'closed'
    if reltimefloat(reltime(start)) * 1000 > a:timeout_ms
      return 0
    endif
    sleep 10m
  endwhile
  " Let pending callbacks (exit_cb/close_cb) fire.
  sleep 1m
  return 1
endfunction

function! mongodb#compat#running(job) abort
  if has('nvim')
    return a:job > 0 && jobwait([a:job], 0)[0] == -1
  endif
  return type(a:job) == v:t_job && job_status(a:job) ==# 'run'
endfunction

function! mongodb#compat#stop(job) abort
  if has('nvim')
    silent! call jobstop(a:job)
  elseif type(a:job) == v:t_job
    call job_stop(a:job)
  endif
endfunction

" Show markdown lines in a popup at the cursor, closed when the cursor moves.
function! mongodb#compat#hover(lines) abort
  if has('nvim')
    call luaeval("vim.lsp.util.open_floating_preview(_A, 'markdown', {border = 'rounded', focus_id = 'mongodb_hover'})", a:lines)
    return
  endif
  " Vim's markdown syntax doesn't conceal fences or code spans: show plain text.
  let lines = map(filter(copy(a:lines), 'v:val !~# "^```"'), 'substitute(v:val, "\\*\\*\\|`", "", "g")')
  call popup_clear()
  let id = popup_atcursor(lines, {
        \ 'border': [], 'padding': [0, 1, 0, 1], 'moved': 'any',
        \ 'maxwidth': 80, 'maxheight': 25, 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰']})
  call matchaddpos('Title', [1], 10, -1, {'window': id})
endfunction

function! s:trim(lines) abort
  let lines = copy(a:lines)
  while !empty(lines) && lines[-1] ==# ''
    call remove(lines, -1)
  endwhile
  return map(lines, 'substitute(v:val, "\r$", "", "")')
endfunction
