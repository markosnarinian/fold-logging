# fold-logging.nvim

Automatically fold logging and debug-print statements and keep them folded by
default, so they stay out of the way until you want to see them.

```python
def compute(values):
    logger.debug(···)          # ← folded (shows your normal fold text)
    total = 0
    for v in values:
        total += v
    print(···)                 # ← folded
    return total               #   the function itself stays unfolded
```

## Features

- **Auto-folds logging on open** — logging/print calls are already collapsed
  when you open a supported file.
- **General folding is left untouched** — functions, classes and blocks fold
  exactly as before; fold-logging only *adds* folds for logging statements,
  composing them on top of your existing fold setup.
- **Coexists with [chrisgrieser/nvim-origami](https://github.com/chrisgrieser/nvim-origami)** —
  it never replaces origami's folding, fold text, or keymaps.
- **Python out of the box**, with detection of standard log-level calls and
  `print`/`pprint`. Add more languages with a few lines of config.
- **Commands** to fold, unfold, toggle, and list what was detected.
- Options for single-line vs. multi-line calls and a minimum line threshold, plus
  `enable` / `auto_fold` toggles.

## Requirements

- Neovim **0.10+** (uses `vim.treesitter.foldexpr`; **0.11+** for the LSP-fold
  base).
- Folding driven by an **`expr` foldexpr** — i.e. Treesitter or LSP folds. That
  is exactly what origami uses, so if origami already gives you folds you're set.
  (If you have no folding configured at all, fold-logging will bootstrap
  Treesitter folding for the buffer and keep your general folds open by default.)
- For the built-in Python support, the `python` Treesitter parser is recommended
  (a regex fallback is used when no parser is available).

## Installation (lazy.nvim)

```lua
{
  "you/fold-logging.nvim",
  ft = { "python" },
  cmd = {
    "FoldLoggingFold",
    "FoldLoggingUnfold",
    "FoldLoggingToggle",
    "FoldLoggingList",
  },
  opts = {
    -- see "Configuration"; defaults are used when omitted
  },
}
```

`ft` makes the plugin load (and auto-fold) when you open a supported file; `cmd`
lets the commands lazy-load it too. `opts` is passed straight to `setup()`.

> Add the filetype to `ft` for every language you enable via `opts.languages`.

### Alongside nvim-origami

Keep your origami spec exactly as it is and just add fold-logging — it captures
whatever foldexpr origami configured and composes on top of it:

```lua
{
  "chrisgrieser/nvim-origami",
  event = "VeryLazy",
  opts = {
    useLspFoldsWithTreesitterFallback = true, -- origami drives the general folds
    -- ...your origami options...
  },
},
{
  "you/fold-logging.nvim",
  ft = { "python" },
  opts = {},
},
```

### Local checkout

Before publishing to a repo, point `dir` at the plugin path:

```lua
{ dir = "/path/to/fold-logging", ft = { "python" }, opts = {} }
```

## How it works (and why it's safe next to origami)

Neovim allows only one `foldmethod` per window, so logging folds can't be a
separate "layer". Instead, fold-logging installs a `foldexpr` that **delegates to
your existing base foldexpr** (Treesitter or LSP — auto-detected) and only
rewrites the lines that belong to a logging statement, nesting them one level
deeper than their surroundings.

The practical consequences:

- **Non-logging lines return the base foldexpr value verbatim** — your
  function/class/block folds are byte-for-byte identical to before.
- fold-logging **does not set** `foldtext`, fold keymaps, or `foldlevel`, and
  doesn't touch origami's session persistence. origami's fold text and `h`/`l`
  keymaps apply to logging folds too, so everything looks and behaves
  consistently.
- Auto-fold only **closes the logging folds**; it never changes the open/closed
  state of your general folds.
- `:FoldLoggingDisable` restores the original `foldmethod` / `foldexpr` /
  `foldlevel`.

> If you drive general folds with **LSP**, set `base_foldexpr = vim.lsp.foldexpr`.
> It's auto-detected when your foldexpr mentions `lsp`, but being explicit is
> safest.

## Configuration

`require("fold-logging").setup(opts)` (lazy.nvim does this for you via `opts`).
All fields are optional; defaults shown:

```lua
require("fold-logging").setup({
  -- Master switch. When false, nothing is installed and commands no-op.
  enable = true,

  -- Fold logging statements automatically when a supported file is opened.
  auto_fold = true,

  -- Fold a logging call that sits alone on a single physical line. Off by
  -- default. When enabled, attached windows get `foldminlines = 0` automatically
  -- (restored on disable) so one-line folds actually collapse. Adjacent logging
  -- lines are always merged into one multi-line fold regardless of this option.
  fold_single_line = false,

  -- Minimum number of lines a (possibly merged) logging region must span to be
  -- folded. 1 = fold everything that qualifies; 3 = only fold blocks of 3+ lines.
  min_lines = 1,

  -- Emit vim.notify messages (warnings, "nothing detected", …).
  notify = true,

  -- Base foldexpr producing your GENERAL folds. nil = auto-detect
  -- (LSP if your foldexpr mentions "lsp", otherwise Treesitter). Set to a
  -- function(lnum) -> foldexpr value to override, e.g. vim.lsp.foldexpr.
  base_foldexpr = nil,

  -- Per-filetype detection specs, deep-merged over the built-ins. `python`
  -- ships out of the box; see "Adding a language".
  languages = {},
})
```

### `fold_single_line` vs `min_lines`

- A run of **adjacent** logging lines (e.g. a cluster of `print` calls) is always
  **merged into a single multi-line fold**, which is folded when its span ≥
  `min_lines`.
- A **lone** logging call on a single line (no logging neighbours) is only folded
  when `fold_single_line = true` **and** `min_lines ≤ 1`. Enabling
  `fold_single_line` also sets `foldminlines = 0` on attached windows so the
  one-line fold visibly collapses (this is a window option, so it also lets
  origami's small folds display closed; it's restored on `:FoldLoggingDisable`).

## What counts as a logging statement (Python)

The built-in Python spec folds:

- `print(...)` and `pprint(...)`
- any call whose callee ends in a standard log level — `.debug`, `.info`,
  `.warning`, `.warn`, `.error`, `.critical`, `.exception`, `.fatal`, `.log` —
  e.g. `logging.info(...)`, `logger.debug(...)`, `self.logger.warning(...)`,
  `log.error(...)`.

It deliberately **does not** fold logging *setup* calls such as
`logging.basicConfig(...)` or `logging.getLogger(...)`.

Adjust the patterns under `opts.languages.python.patterns` to add or remove
methods (e.g. loguru's `logger.success` / `logger.trace`).

## Commands

| Command               | Action                                                     |
| --------------------- | ---------------------------------------------------------- |
| `:FoldLoggingFold`    | Create and close the logging folds in the current buffer. |
| `:FoldLoggingUnfold`  | Open the logging folds (general folds untouched).         |
| `:FoldLoggingToggle`  | Toggle the logging folds.                                 |
| `:FoldLoggingList`    | Send all detected logging statements to the quickfix list.|
| `:FoldLoggingRefresh` | Recompute logging folds (after edits or config tweaks).   |
| `:FoldLoggingEnable`  | Enable the plugin and attach to visible supported buffers.|
| `:FoldLoggingDisable` | Disable and restore the original folding.                 |

Example keymaps:

```lua
vim.keymap.set("n", "<leader>lf", "<cmd>FoldLoggingToggle<cr>", { desc = "Toggle logging folds" })
vim.keymap.set("n", "<leader>ll", "<cmd>FoldLoggingList<cr>",   { desc = "List logging statements" })
```

## Lua API

```lua
local fl = require("fold-logging")

fl.fold(bufnr)    -- close logging folds (bufnr optional, defaults to current)
fl.unfold(bufnr)  -- open logging folds
fl.toggle(bufnr)  -- toggle
fl.refresh(bufnr) -- recompute
fl.list(bufnr)    -- quickfix list of detections
fl.detect(bufnr)  -- -> { { start = <lnum>, ["end"] = <lnum>, text = <callee> }, ... }
fl.enable()       -- re-enable at runtime
fl.disable()      -- disable and restore folding
```

## Adding a language

Languages are keyed by **filetype** under `languages`. Your table is deep-merged
over the built-ins, so you can add new filetypes or tweak existing ones.

A language spec has two fields:

```lua
{
  -- Treesitter node types that represent a function/method call.
  call_node_types = { "call_expression" },

  -- Lua patterns tested against the call's *callee* text. Matched with
  -- string.find, so they are substring matches unless you anchor with ^ / $.
  patterns = { "^fmt%.Print", "^log%.", "%.Debug$", "%.Info$" },
}
```

Detection uses Treesitter when a parser is available (exact multi-line ranges)
and falls back to a line-based regex scan otherwise (the same `patterns` are
tested against each `callee(` shape found on a line).

### Example: Go

```lua
require("fold-logging").setup({
  languages = {
    go = {
      call_node_types = { "call_expression" },
      patterns = { "^fmt%.Print", "^log%.", "%.Printf?$", "%.Debug$", "%.Info$" },
    },
  },
})
```

Remember to add `"go"` to the lazy.nvim `ft` list so the plugin loads for it.

### Example: extend the built-in Python spec

To *add* patterns rather than replace the list, append in your config:

```lua
local fl = require("fold-logging")
local py = vim.deepcopy(require("fold-logging.languages").defaults.python)

-- e.g. also fold loguru levels and icecream's debug helper
vim.list_extend(py.patterns, { "%.success$", "%.trace$", "^ic$" })

fl.setup({ languages = { python = py } })
```

### Finding the right node type / callee text

Inspect the syntax tree with `:InspectTree` (built into Neovim). Call nodes are
usually `call` (Python) or `call_expression` (C-family). The callee is the node
in the `function:` field; its text (e.g. `logging.info`, `logger.debug`) is what
your `patterns` are matched against.

## Caveats

- Requires `expr`-based general folding (Treesitter / LSP / origami). With a
  deliberate non-expr `foldmethod` (`marker`, `indent`, `syntax`, `diff`)
  fold-logging won't attach, to avoid clobbering your folds — it emits a one-time
  warning per buffer.
- A single isolated one-line call can't visually collapse unless
  `foldminlines = 0` (a Vim limitation); `fold_single_line` handles this for you.
- The regex fallback's multi-line range detection is a paren-balancing heuristic;
  install the Treesitter parser for exact ranges.

## Development

```bash
nvim --headless -u NORC -c "luafile tests/run.lua"
```
