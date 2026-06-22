local languages = require("fold-logging.languages")

local M = {}

M.defaults = {
  -- Master switch. When false the plugin installs nothing and all commands
  -- become no-ops.
  enable = true,

  -- Fold logging statements automatically when a supported file is opened.
  -- When false, folds are only created/closed via the commands or the Lua API.
  auto_fold = true,

  -- Also fold plain debug-print calls (a language's `print_patterns`, e.g.
  -- Python's `print` / `pprint`). Logging calls fold regardless of this.
  fold_print = false,

  -- Fold logging calls that occupy a single physical line on their own. When
  -- enabled, attached windows get 'foldminlines' = 0 automatically (restored on
  -- disable) so one-line folds actually collapse. Note that several *adjacent*
  -- logging lines are always merged into one multi-line fold regardless of this.
  fold_single_line = false,

  -- Minimum number of lines a (possibly merged) logging region must span to be
  -- folded. 1 = fold everything that qualifies; 3 = only fold blocks of 3+
  -- lines, and so on.
  min_lines = 1,

  -- Emit `vim.notify` messages (warnings, "nothing detected", ...).
  notify = true,

  -- Base foldexpr that produces the *general* folds (functions, classes, ...).
  -- fold-logging composes its logging folds on top of this so it never replaces
  -- your normal folding. `nil` auto-detects:
  --   * if the buffer already uses an `expr` foldexpr mentioning "lsp" -> LSP
  --   * otherwise -> Treesitter (`vim.treesitter.foldexpr`)
  -- Set explicitly to a `function(lnum) -> foldexpr value` to override, e.g.
  --   base_foldexpr = vim.lsp.foldexpr
  base_foldexpr = nil,

  -- Per-filetype detection specs. Merged (deep) over the built-ins, so you can
  -- add new filetypes or override an existing spec's `patterns`.
  languages = languages.defaults,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
