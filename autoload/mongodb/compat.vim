" Vim / Neovim shims: jobs and hover popups.

" Run cmd (a list, no shell) and call Cb(lines, exit_code) when it finishes.
" stderr is merged into the output.
function! mongodb#compat#job(cmd, Cb) abort
  let ctx = {'out': [], 'err': [], 'code': -1, 'exited': 0, 'closed': 0, 'Cb': a:Cb}
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
  " exit_cb and close_cb may arrive in either order. A killed job exits with -1.
  let job = job_start(a:cmd, {
        \ 'err_io': 'out',
        \ 'out_cb': {ch, msg -> add(ctx.out, msg)},
        \ 'exit_cb': {job, code -> s:vim_done(ctx, {'code': code, 'exited': 1})},
        \ 'close_cb': {ch -> s:vim_done(ctx, {'closed': 1})}})
  if job_status(job) ==# 'fail'
    call a:Cb(['failed to start: ' . a:cmd[0]], -1)
  endif
  return job
endfunction

function! s:vim_done(ctx, update) abort
  call extend(a:ctx, a:update)
  if a:ctx.closed && a:ctx.exited
    call call(a:ctx.Cb, [s:trim(a:ctx.out), a:ctx.code])
  endif
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
