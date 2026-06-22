# fold-logging.nvim

Automatically fold logging statements—and optionally debug-print calls—without
changing the rest of your folding setup.

## Features

<img width="1822" height="1095" alt="Screenshot 2026-06-22 at 10 46 41 AM" src="https://github.com/user-attachments/assets/c8148518-8c50-49c3-bbf5-2c659513a331" />

- Automatically closes logging folds when a supported file opens.
- Folds newly added logging statements on write without re-closing logging folds
  you manually opened.
- Preserves your existing `expr` folds for functions, classes, and blocks.
- Composes with Treesitter folds, LSP folds, and
  [nvim-origami](https://github.com/chrisgrieser/nvim-origami).
- Supports Python logging calls out of the box.
- Optionally folds plain debug-print calls such as Python's `print(...)` and
  `pprint(...)`.
- Lets you choose the minimum folded region size, so lone one-line calls can stay
  visible while adjacent logging blocks still fold.
- Supports custom languages and logging APIs with Lua patterns.
- Provides commands and a Lua API for folding, unfolding, toggling, refreshing,
  listing detections, enabling, and disabling.

## Installation

Requires Neovim 0.10+ and `expr`-based folding, usually Treesitter or LSP. The
plugin composes logging folds on top of that base fold expression instead of
replacing it.

### With lazy.nvim

```lua
{
  "markosnarinian/fold-logging.nvim",
  ft = { "python" },
  cmd = {
    "FLFold",
    "FLUnfold",
    "FLToggle",
    "FLRefresh",
    "FLList",
    "FLEnable",
    "FLDisable",
  },
  opts = {},
}
```

Add each configured language to `ft` so lazy.nvim loads the plugin for that
filetype.

## Usage

By default, logging folds are created and closed automatically when a supported
file opens. New logging statements are also folded when the file is written. You
can also control them manually:

| Command      | Action                                      |
| ------------ | ------------------------------------------- |
| `:FLFold`    | Close logging folds in the current buffer.  |
| `:FLUnfold`  | Open logging folds in the current buffer.   |
| `:FLToggle`  | Toggle logging folds in the current buffer. |
| `:FLRefresh` | Recompute logging folds after edits.        |
| `:FLList`    | List detected calls in the quickfix window. |
| `:FLEnable`  | Re-enable and attach to open buffers.       |
| `:FLDisable` | Disable and restore previous folding.       |

## Configuration

Pass options through `opts` (or `require("fold-logging").setup{}`). Defaults:

```lua
{
  enable = true,
  auto_fold = true,
  fold_print = false,
  min_lines = 2,
  base_foldexpr = nil,
  languages = {
    python = {
      call_node_types = { "call" },
      patterns = {
        "%.debug$",
        "%.info$",
        "%.warning$",
        "%.warn$",
        "%.error$",
        "%.critical$",
        "%.exception$",
        "%.fatal$",
        "%.log$",
      },
      print_patterns = {
        "^print$",
        "^pprint$",
      },
    },
  },
}
```

- `enable` — Master switch. When `false`, the plugin installs nothing and every
  command is a no-op.
- `auto_fold` — Fold logging statements automatically when a supported file
  opens, and fold newly added logging statements when the file is written. When
  `false`, folds are only created/closed via the commands or the API.
- `fold_print` — Also fold plain debug-print calls (Python's `print` / `pprint`).
  Logging-level calls fold regardless; this just adds the print family.
- `min_lines` — Minimum number of lines a (merged) logging region must span to be
  folded. `2` skips lone one-line calls by default while still folding adjacent
  logging calls as a block. Set `1` to fold everything that qualifies, including
  one-line calls; raise it to fold only larger blocks.
- `base_foldexpr` — The fold expression that produces your general folds. `nil`
  auto-detects (LSP when your foldexpr mentions `lsp`, otherwise Treesitter). Set
  to a `function(lnum)` to override, e.g. `base_foldexpr = vim.lsp.foldexpr`.
- `languages` — Per-filetype detection specs, deep-merged over the built-ins.
  Each spec defines Treesitter call node types, always-active logging patterns,
  and optional `print_patterns` used only when `fold_print = true`. See
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
