# fold-logging.nvim

Automatically fold logging and debug-print statements, and keep them folded by
default — so they stay out of the way until you want them.

## Overview

```python
def compute(values):
    logger.debug(···)          # ← folded
    total = sum(values)
    print(···)                 # ← folded
    return total               #   the function itself stays unfolded
```

- Folds logging/print calls the moment you open a file.
- Leaves general folding (functions, classes, blocks) completely untouched.
- Coexists with [nvim-origami](https://github.com/chrisgrieser/nvim-origami):
  it composes on top without replacing its folding, fold text, or keymaps.
- Python built in; add more languages via config.
- Options for single-line vs. multi-line calls and a minimum line threshold, plus
  `enable` / `auto_fold` toggles.

It works by layering its folds onto your existing `expr` foldexpr (Treesitter or
LSP), so general folds are byte-for-byte identical to before and everything is
restored on `:FoldLoggingDisable`.

## Installation

Requires Neovim 0.10+ and `expr`-based folding (Treesitter or LSP) — what origami
already uses.

### With lazy.nvim

```lua
{
  "markosnarinian/fold-logging.nvim",
  ft = { "python" },
  cmd = { "FoldLoggingFold", "FoldLoggingUnfold", "FoldLoggingToggle", "FoldLoggingList" },
  opts = {},
}
```

Add a filetype to `ft` for every language you enable in `opts.languages`.

## Usage

Folding happens automatically on open. The commands let you fold on demand:

| Command               | Action                                       |
| --------------------- | -------------------------------------------- |
| `:FoldLoggingFold`    | Fold logging statements.                     |
| `:FoldLoggingUnfold`  | Unfold logging statements.                   |
| `:FoldLoggingToggle`  | Toggle logging folds.                        |
| `:FoldLoggingList`    | List detections in the quickfix window.      |
| `:FoldLoggingRefresh` | Recompute folds after edits.                 |
| `:FoldLoggingEnable`  | Enable and attach to open buffers.           |
| `:FoldLoggingDisable` | Disable and restore the original folding.    |

### Configuration

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

Using LSP folds? Set `base_foldexpr = vim.lsp.foldexpr`.

### What gets folded

For Python: `print(...)`, `pprint(...)`, and any call ending in a standard log
level — `.debug`, `.info`, `.warning`, `.warn`, `.error`, `.critical`,
`.exception`, `.fatal`, `.log`. Setup calls like `logging.basicConfig` and
`logging.getLogger` are ignored.

### Adding a language

Languages are keyed by filetype. A spec has a list of Treesitter call-node types
and Lua patterns matched against the callee text:

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

Use `:InspectTree` to find the call node type and callee. Detection uses
Treesitter when a parser is available and falls back to a line regex otherwise.

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

All contributions are welcome! Open an issue or a PR and I'll take the time to
review it.

## License

[MIT](LICENSE)
