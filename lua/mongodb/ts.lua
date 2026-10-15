-- Neovim treesitter support: a "mongodb" language backed by the javascript
-- parser, so queries/mongodb/*.scm (which inherit javascript) apply.
local M = {}

local available

-- Columns (0-based) of the command and its argument on a shell helper line:
-- `use <db>`, `show <what>`, `it`. nil if the line isn't one.
local function shell_cols(line)
  if line:match('^%s*it%s*;?%s*$') then
    return #line:match('^%s*'), nil
  end
  local ws, cmd, arg = line:match('^(%s*)(%a+)%s+()[%w_%-]+%s*;?%s*$')
  if cmd == 'use' or cmd == 'show' then
    return #ws, arg - 1
  end
end

-- #mongodb-shell? @capture "cmd"|"arg": the node is that part of a shell
-- helper line. The javascript parser can't parse these lines, and how it
-- recovers depends on the code around them, so match by line instead.
local function shell_predicate(match, _, source, pred)
  local nodes = match[pred[2]]
  for _, node in ipairs(type(nodes) == 'table' and nodes or { nodes }) do
    local row, col = node:start()
    local line = type(source) == 'number' and vim.api.nvim_buf_get_lines(source, row, row + 1, false)[1]
      or vim.split(source, '\n')[row + 1]
    local cmd_col, arg_col = shell_cols(line or '')
    if col ~= (pred[3] == 'cmd' and cmd_col or arg_col) then
      return false
    end
  end
  return true
end

function M.available()
  if available == nil then
    available = false
    local path = vim.api.nvim_get_runtime_file('parser/javascript.*', false)[1]
    if path then
      available = pcall(vim.treesitter.language.add, 'mongodb', { path = path, symbol_name = 'javascript' })
      if available then
        vim.treesitter.query.add_predicate('mongodb-shell?', shell_predicate, { force = true })
      end
    end
  end
  return available
end

function M.start(buf)
  return M.available() and pcall(vim.treesitter.start, buf, 'mongodb') or false
end

-- Line range {start, end} (1-based) of the top-level statement at lnum, or
-- nil when treesitter can't tell (no parser, parse error, comment, blank).
function M.range(buf, lnum)
  if not M.available() then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'mongodb')
  if not ok or not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  local row = lnum - 1
  for node in root:iter_children() do
    local sr, _, er, ec = node:range()
    if ec == 0 and er > sr then
      er = er - 1
    end
    if sr <= row and row <= er then
      if node:has_error() or node:type() == 'comment' then
        return nil
      end
      return { sr + 1, er + 1 }
    end
  end
  return nil
end

return M
