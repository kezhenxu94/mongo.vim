# mongodb.vim

**Write MongoDB queries in Vim or Neovim and run them in place.** Completion and hover docs come from your live database: database names, collections, methods, operators, and field names with their types.

![demo](demo/demo.gif)

No plugin dependencies. No LSP server to install. No Node toolchain. Just `mongosh` and a single plugin that works in **Vim 9** and **Neovim** alike.

## Features

- **Run the statement under the cursor**: `<LocalLeader>rr` finds the whole statement, even across several lines (chained `.sort().limit()`, multi-line pipelines), and runs it. The nearest `use <db>` above it is applied automatically, else the last `use <db>` you ran in that buffer.
- **Results in a preview pane**: output lands in a reusable `[MongoDB]` vertical split with `javascript` highlighting, and each statement's result is labelled. Press `q` to close it.
- **Schema-aware completion**: it pops up as you type.
  | You type | You get |
  | --- | --- |
  | `use ` | databases on the server |
  | `db.` | collections of the current db + `db` methods |
  | `db.users.` | collection methods, with signatures and docs |
  | `db.users.find().` | cursor methods |
  | `$` | query / update / aggregation operators |
  | `find({ ` | **field names sampled from the collection, with their BSON types** |
  | `'$` inside a pipeline | field references |

  Dotted paths like `address.city` are quoted for you when used as keys.
- **Hover docs with `K`**:
  - on a **collection**: document count, indexes and the sampled schema
  - on a **database** (`use shop`): object count, size and its collections
  - on a **method, operator or BSON constructor**: signature and description
  - on a **field**: the types seen in the data
- **Highlighting**: shell helpers (`use`, `show`), `db`, `$operators`, `"$field"` references, BSON constructors and MongoDB methods. Collections that **actually exist on the server** are highlighted, so a typo'd collection name stands out.
- **Neovim + treesitter**: if a `javascript` parser is installed, the plugin uses treesitter for highlighting (via `queries/mongodb/highlights.scm`) and for finding the statement under the cursor. Otherwise it falls back to the built-in highlighter and statement scanner.

## Requirements

- Vim 9.0+ or Neovim 0.10+
- [`mongosh`](https://www.mongodb.com/docs/mongodb-shell/) on your `$PATH`

## Install

```vim
" vim-plug
Plug 'kezhenxu94/mongodb.vim'
```

```lua
-- lazy.nvim
{ 'kezhenxu94/mongodb.vim', ft = 'mongodb' }
```

Or with Vim's native packages:

```sh
git clone https://github.com/kezhenxu94/mongodb.vim ~/.vim/pack/plugins/start/mongodb.vim
```

Files named `*.mongodb`, `*.mongo.js` or `*.mongosh` get the `mongodb` filetype.

## Connect

The connection string is resolved in this order:

1. `b:mongodb_uri`, per buffer
2. `g:mongodb_uri`, or `:MongoConnect mongodb://user:pass@host/db`
3. `$MONGODB_URI`
4. `mongodb://localhost:27017`

```sh
MONGODB_URI=mongodb+srv://me@cluster0.example.net/shop vim report.mongodb
```

Passwords are masked as `***` in the results header.

## Usage

| Mapping | Command | Action |
| --- | --- | --- |
| `<LocalLeader>rr` | `:MongoRunStatement` | run the statement under the cursor |
| `<LocalLeader>rf` | `:MongoRun` | run the whole buffer |
| `<LocalLeader>r` (visual) | `:'<,'>MongoRun` | run the selection |
| `K` | `:MongoHover` | hover docs |
| `<C-c>` | `:MongoStop` | cancel the running query (also in the results window) |
| | `:MongoRefresh` | reload databases, collections and schemas |
| | `:MongoConnect [uri]` | switch server |

To use your own keys, set `g:mongodb_no_mappings = 1` and map the `<Plug>(mongodb-run-statement)`, `<Plug>(mongodb-run-file)`, `<Plug>(mongodb-run-selection)`, `<Plug>(mongodb-hover)` and `<Plug>(mongodb-stop)` targets.

## Options

| Option | Default | |
| --- | --- | --- |
| `g:mongodb_uri` | `''` | connection string (see above) |
| `g:mongodb_mongosh` | `'mongosh'` | path to `mongosh` |
| `g:mongodb_preview_width` | half the window | width of the results split, opened to the right |
| `g:mongodb_autocomplete` | `1` | open the completion menu as you type (otherwise use `<C-x><C-o>`) |
| `g:mongodb_treesitter` | `1` | use treesitter in Neovim when available |
| `g:mongodb_no_mappings` | `0` | skip the default mappings |

## How it works

- Queries run as `mongosh <uri> --quiet --eval <script>` in a background job, so the editor never blocks. Arguments are passed as a list and never go through a shell.
- `--eval` normally prints only the last value, and it rejects shell helpers mixed with code. So the plugin splits the selection into statements, rewrites `use x` and `show dbs` / `show collections` into plain JavaScript, and wraps each expression in `print()`. You get one labelled result per statement, like the interactive shell.
- Metadata comes from `listDatabases`, `getCollectionNames()`, and a `$sample` of 50 documents per collection, flattened into field paths. It is loaded asynchronously when you open a buffer, and the field schema of a collection is fetched the first time you need it. Nothing blocks: completion fills in and hover opens once the data arrives.

## Running the tests

```sh
test/run.sh   # starts a throwaway mongo:8 container on :27118, runs the suite in Vim and Neovim
```

Set `MONGODB_URI` to use an existing server instead. **The suite seeds and drops the `shop` and `analytics` databases.** `demo/record.sh` regenerates the GIF above with [asciinema](https://asciinema.org) and [agg](https://github.com/asciinema/agg).

## License

MIT
