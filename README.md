# fold-logging.nvim

Automatically fold logging and debug-print statements without changing the rest
of your folding setup.

## Overview

```python
def compute(values):
    logger.debug(···)          # ← folded
    total = sum(values)
    logger.info(···)           # ← folded
    return total               #   the function itself stays unfolded
```

- Closes logging folds when a supported file opens.
- Preserves your existing `expr` folds for functions, classes, and blocks.
- Works with Treesitter folds, LSP folds, and
  [nvim-origami](https://github.com/chrisgrieser/nvim-origami).
- Supports Python out of the box; other languages can be configured with Lua
  patterns.

## Installation

Requires Neovim 0.10+ and `expr`-based folding, usually Treesitter or LSP. The
plugin composes logging folds on top of that base fold expression instead of
replacing it.

### With lazy.nvim

```lua
{
  "markosnarinian/fold-logging.nvim",
  ft = { "python" },
  cmd = { "FoldLoggingFold", "FoldLoggingUnfold", "FoldLoggingToggle", "FoldLoggingList" },
  opts = {},
}
```

Add each configured language to `ft` so lazy.nvim loads the plugin for that
filetype.

## Usage

By default, logging folds are created and closed automatically when a supported
file opens. You can also control them manually:

| Command               | Action                                       |
| --------------------- | -------------------------------------------- |
| `:FoldLoggingFold`    | Close logging folds in the current buffer.   |
| `:FoldLoggingUnfold`  | Open logging folds in the current buffer.    |
| `:FoldLoggingToggle`  | Toggle logging folds in the current buffer.  |
| `:FoldLoggingRefresh` | Recompute logging folds after edits.         |
| `:FoldLoggingList`    | List detected calls in the quickfix window.  |
| `:FoldLoggingEnable`  | Re-enable and attach to open buffers.        |
| `:FoldLoggingDisable` | Disable and restore previous folding.        |

## Configuration

Pass options through `opts` (or `require("fold-logging").setup{}`). Defaults:

```lua
{
  enable = true,
  auto_fold = true,
  fold_print = false,
  fold_single_line = false,
  min_lines = 1,
  notify = true,
  base_foldexpr = nil,
  languages = {},
}
```

- `enable` — Master switch. When `false`, the plugin installs nothing and every
  command is a no-op.
- `auto_fold` — Fold logging statements automatically when a supported file
  opens. When `false`, folds are only created/closed via the commands or the API.
- `fold_print` — Also fold plain debug-print calls (Python's `print` / `pprint`).
  Logging-level calls fold regardless; this just adds the print family.
- `fold_single_line` — Fold logging calls that sit alone on a single line.
  Enabling it also sets `foldminlines = 0` on attached windows (restored on
  disable) so a one-line fold actually collapses. Adjacent logging lines are
  merged into one multi-line fold regardless of this option.
- `min_lines` — Minimum number of lines a (merged) logging region must span to be
  folded. `1` folds everything that qualifies; raise it to fold only larger
  blocks.
- `notify` — Emit `vim.notify` messages (warnings, "nothing detected", …).
- `base_foldexpr` — The fold expression that produces your general folds. `nil`
  auto-detects (LSP when your foldexpr mentions `lsp`, otherwise Treesitter). Set
  to a `function(lnum)` to override, e.g. `base_foldexpr = vim.lsp.foldexpr`.
- `languages` — Per-filetype detection specs, deep-merged over the built-ins. See
  [Adding a language](#adding-a-language).

### What gets folded

For Python, the built-in rules fold any call ending in a standard log level:
`.debug`, `.info`, `.warning`, `.warn`, `.error`, `.critical`, `.exception`,
`.fatal`, `.log` (so `logging.info(...)`, `logger.debug(...)`,
`self.logger.warning(...)`, …).

`print(...)` and `pprint(...)` are only folded when `fold_print = true`.

Setup calls such as `logging.basicConfig(...)` and `logging.getLogger(...)` are
never folded.

### Adding a language

Languages are keyed by Neovim filetype. A language spec contains:

- `call_node_types`: Treesitter node types that represent calls
- `patterns`: Lua patterns matched against the called function name
- `print_patterns` (optional): extra patterns folded only when `fold_print = true`

```lua
opts = {
  languages = {
    go = {
      call_node_types = { "call_expression" },
      patterns = { "^fmt%.Print", "^log%.", "%.Debug$", "%.Info$" },
    },
  },
}
```

Patterns match the callee text, not the full source line. For example,
`"%.Info$"` matches `log.Info(...)` and `logger.Info(...)`.

Use `:InspectTree` to find the call node type for a language.

## API

```lua
local fl = require("fold-logging")

fl.setup(opts)    -- configure (lazy does this via `opts`)
fl.fold(bufnr)    -- close logging folds (bufnr optional, defaults to current)
fl.unfold(bufnr)  -- open logging folds
fl.toggle(bufnr)  -- toggle
fl.refresh(bufnr) -- recompute
fl.list(bufnr)    -- quickfix list of detections
fl.detect(bufnr)  -- -> { { start = <lnum>, ["end"] = <lnum>, text = <callee> }, ... }
fl.enable()       -- re-enable at runtime
fl.disable()      -- disable and restore folding
```

## Contributing

Issues and pull requests are welcome.

## License

[MIT](LICENSE)
