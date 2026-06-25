local languages = require("fold-logging.languages")

---@class FoldLogging.Config
---@field options FoldLoggingOpts
local M = {}

---@class FoldLoggingOpts
---Fold logging statements automatically when a supported file is opened, and
---fold newly added logging statements when the file is written. When false,
---folds are only created/closed via the commands or the Lua API.
---@field auto_fold? boolean
---Base foldexpr that produces the *general* folds (functions, classes, ...).
---fold-logging composes its logging folds on top of this so it never replaces
---your normal folding. `nil` auto-detects:
---
--- * If the buffer already uses an `expr` foldexpr mentioning "lsp" -> LSP
--- * Otherwise -> Treesitter (`vim.treesitter.foldexpr`)
---
---Set explicitly to a `function(lnum) -> foldexpr` value to override, e.g.
---`base_foldexpr = vim.lsp.foldexpr`.
---@field base_foldexpr? nil|fun(lnum: integer)
---Master switch. When false the plugin installs nothing and all commands
---become no-ops.
---@field enable? boolean
---Also fold plain debug-print calls (a language's `print_patterns`, e.g.
---Python's `print` / `pprint`). Logging calls fold regardless of this.
---@field fold_print? boolean
---Per-filetype detection specs. Merged (deep) over the built-ins, so you can
---add new filetypes or override an existing spec's `patterns`.
---@field languages? table<string, FoldLogging.Languages.Language>
---Minimum number of lines a (possibly merged) logging region must span to be
---folded.
---
--- * `1`: fold everything that qualifies, including one-line calls
--- * `3`: only fold blocks of 3+ lines, and so on.
---@field min_lines? integer
local defaults = {
  auto_fold = true,
  base_foldexpr = nil,
  enable = true,
  fold_print = false,
  languages = languages.defaults,
  min_lines = 2,
}

M.options = {}

---@param opts? FoldLoggingOpts
---@return FoldLoggingOpts options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  return M.options
end

return M
