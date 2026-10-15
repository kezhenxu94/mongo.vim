-- Neovim treesitter support: a "mongodb" language backed by the javascript
-- parser, so queries/mongodb/*.scm (which inherit javascript) apply.
local M = {}

local available

function M.available()
  if available == nil then
    available = false
    local path = vim.api.nvim_get_runtime_file('parser/javascript.*', false)[1]
    if path then
      available = pcall(vim.treesitter.language.add, 'mongodb', { path = path, symbol_name = 'javascript' })
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
