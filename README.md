# fold-logging.nvim

Automatically fold logging and debug-print statements, and keep them folded by
default — so they stay out of the way until you want them.

```python
def compute(values):
    logger.debug(···)          # ← folded
    total = sum(values)
    print(···)                 # ← folded
    return total               #   the function itself stays unfolded
```

- Logging calls are folded the moment you open a file.
- General folding (functions, classes, blocks) is left untouched.
- Coexists with [nvim-origami](https://github.com/chrisgrieser/nvim-origami):
  it composes on top without replacing its folding, fold text, or keymaps.
- Python built in; more languages via config.

## Requirements

- Neovim 0.10+ (0.11+ for the LSP-fold base).
- `expr`-based folding (Treesitter or LSP) — what origami already uses. With no
  folding configured, Treesitter folding is bootstrapped automatically.

## Install (lazy.nvim)

```lua
{
  "you/fold-logging.nvim",
  ft = { "python" },
  cmd = { "FoldLoggingFold", "FoldLoggingUnfold", "FoldLoggingToggle", "FoldLoggingList" },
  opts = {},
}
```

Add a filetype to `ft` for every language you enable in `opts.languages`. Using
LSP folds? Set `opts.base_foldexpr = vim.lsp.foldexpr`.

## Configuration

Defaults (all optional):

```lua
require("fold-logging").setup({
  enable = true,            -- master switch
  auto_fold = true,         -- fold automatically on open
  fold_single_line = false, -- also fold lone one-line calls (sets foldminlines=0)
  min_lines = 1,            -- only fold regions spanning >= this many lines
  notify = true,            -- emit vim.notify messages
  base_foldexpr = nil,      -- general-fold source; nil auto-detects Treesitter/LSP
  languages = {},           -- deep-merged over the built-ins
})
```

Adjacent logging lines are merged into one fold. `min_lines` is the threshold for
the merged region; `fold_single_line` controls lone one-liners.

## Commands

| Command               | Action                                       |
| --------------------- | -------------------------------------------- |
| `:FoldLoggingFold`    | Fold logging statements.                     |
| `:FoldLoggingUnfold`  | Unfold logging statements.                   |
| `:FoldLoggingToggle`  | Toggle logging folds.                        |
| `:FoldLoggingList`    | List detections in the quickfix window.      |
| `:FoldLoggingRefresh` | Recompute folds after edits.                 |
| `:FoldLoggingEnable`  | Enable and attach to open buffers.           |
| `:FoldLoggingDisable` | Disable and restore the original folding.    |

```lua
local fl = require("fold-logging")
fl.fold(bufnr); fl.unfold(bufnr); fl.toggle(bufnr); fl.refresh(bufnr)
fl.list(bufnr); fl.detect(bufnr)        -- bufnr optional, defaults to current
fl.enable(); fl.disable()
```

## What gets folded (Python)

`print(...)`, `pprint(...)`, and any call ending in a standard log level —
`.debug`, `.info`, `.warning`, `.warn`, `.error`, `.critical`, `.exception`,
`.fatal`, `.log` (so `logging.info`, `logger.debug`, `self.logger.warning`, …).
Setup calls like `logging.basicConfig` and `logging.getLogger` are ignored.

## Adding a language

Languages are keyed by filetype. A spec has two fields:

```lua
require("fold-logging").setup({
  languages = {
    go = {
      call_node_types = { "call_expression" }, -- Treesitter call node(s)
      patterns = { "^fmt%.Print", "^log%.", "%.Debug$", "%.Info$" }, -- Lua patterns on the callee
    },
  },
})
```

Patterns are matched (via `string.find`) against the callee text — use `:InspectTree`
to find the call node type and callee. Detection uses Treesitter when a parser is
available and falls back to a line regex otherwise. Remember to add the filetype
to lazy's `ft` list.

To extend the built-in Python spec instead of replacing it:

```lua
local py = vim.deepcopy(require("fold-logging.languages").defaults.python)
vim.list_extend(py.patterns, { "%.success$", "%.trace$" }) -- e.g. loguru
require("fold-logging").setup({ languages = { python = py } })
```

## How it works

Neovim allows one `foldmethod` per window, so fold-logging installs a `foldexpr`
that delegates to your existing base foldexpr and only rewrites the lines of a
logging call, nesting them one level deeper. Non-logging lines pass through
unchanged, so general folds are identical to before. It never sets `foldtext`,
fold keymaps, or `foldlevel`, and restores everything on `:FoldLoggingDisable`.

Non-`expr` foldmethods (`marker`, `indent`, …) are left alone with a one-time
warning, to avoid clobbering deliberate folding setups.

## Development

```bash
nvim --headless -u NORC -c "luafile tests/run.lua"
```
