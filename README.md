# fold-logging.nvim

Automatically fold logging and debug-print statements without changing the rest
of your folding setup.

## Overview

<img width="1822" height="1095" alt="Screenshot 2026-06-22 at 10 46 41 AM" src="https://github.com/user-attachments/assets/c8148518-8c50-49c3-bbf5-2c659513a331" />

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
  enable = true,            -- master switch
  auto_fold = true,         -- fold automatically on open
  fold_single_line = false, -- also fold lone one-line calls (sets foldminlines=0)
  min_lines = 1,            -- only fold regions spanning >= this many lines
  notify = true,            -- emit vim.notify messages
  base_foldexpr = nil,      -- general-fold source; nil auto-detects Treesitter/LSP
  languages = {},           -- deep-merged over the built-ins
}
```

If you use LSP folds and auto-detection does not pick them up, set:

```lua
opts = {
  base_foldexpr = vim.lsp.foldexpr,
}
```

### What gets folded

For Python, the built-in rules fold:

- `print(...)`
- `pprint(...)`
- calls ending in a standard log level: `.debug`, `.info`, `.warning`, `.warn`,
  `.error`, `.critical`, `.exception`, `.fatal`, `.log`

Setup calls such as `logging.basicConfig(...)` and `logging.getLogger(...)` are
not folded.

### Adding a language

Languages are keyed by Neovim filetype. A language spec contains:

- `call_node_types`: Treesitter node types that represent calls
- `patterns`: Lua patterns matched against the called function name

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
