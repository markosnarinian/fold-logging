local config = require("fold-logging.config")

---@class FoldLogging.Fold
---@field _base table<integer, fun(lnum: integer): base: integer>
---@field _cache table<integer, { tick: integer, result: string[], regions: { start: integer, ["end"]: integer, texts: string[] }[] }>
---@field _closed table<integer, boolean>
---@field _known table<integer, table<string, integer>>
---@field _prev table<integer, { foldmethod: string, foldexpr: string, foldlevel: integer, foldminlines: integer }>
local M = {}

-- Per-buffer state.
M._base = {} -- bufnr -> base foldexpr function(lnum)
M._cache = {} -- bufnr -> { tick, result = {lnum -> foldexpr value}, regions }
M._closed = {} -- bufnr -> bool: are the logging folds currently meant to be closed?
M._known = {} -- bufnr -> multiset of logging region signatures seen after the last fold pass
M._prev = {} -- bufnr -> { foldmethod, foldexpr } captured before we attached

-- Default base: Treesitter folds. Safe to call on any line; returns "0" if no
-- parser so we never throw inside a foldexpr.
---@param lnum integer
---@return integer base
local function default_base(lnum)
  local ok, r = pcall(vim.treesitter.foldexpr, lnum) ---@type boolean, integer|nil
  return (ok and r) and r or 0
end

---@param bufnr integer
---@param ft string
---@return boolean has
local function has_parser(bufnr, ft)
  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return false
  end
  return (pcall(vim.treesitter.get_parser, bufnr, lang))
end

-- Resolve a single foldexpr token to an absolute fold level given the previous
-- line's resolved level. Handles the forms documented in `:h fold-expr`.
---@param value integer
---@param prev integer
---@return integer num
local function resolve(value, prev)
  local s = tostring(value)
  if s == "=" then
    return prev
  end
  local head = s:sub(1, 1)
  if head == ">" or head == "<" then
    return tonumber(s:sub(2)) or prev
  elseif head == "a" then
    return prev + (tonumber(s:sub(2), 10) or 0)
  elseif head == "s" then
    return math.max(0, prev - (tonumber(s:sub(2)) or 0))
  end
  local num = tonumber(s, 10)
  if not num or num < 0 then
    return prev -- -1 ("undefined") and junk: approximate with previous level
  end
  return num
end

---@param region { start: integer, ["end"]: integer, texts: string[] }
---@return string signature
local function signature(region)
  return table.concat(region.texts or {}, "\n")
end

---@param regions { start: integer, ["end"]: integer, texts: string[] }[]
---@return table<string, integer> signatures
local function signatures(regions)
  local out = {} ---@type table<string, integer>
  for _, r in ipairs(regions) do
    local key = signature(r)
    out[key] = (out[key] or 0) + 1
  end
  return out
end

-- Merge adjacent detection regions and apply the min_lines filter. Returns the
-- regions that should actually become folds.
---@param detected { start: integer, ["end"]: integer, text: string }[]
---@param opts FoldLoggingOpts
---@return { start: integer, ["end"]: integer, texts: string[] }[] regions
local function fold_regions(detected, opts)
  local merged = {} ---@type { start: integer, ["end"]: integer, texts: string[] }[]
  for _, r in ipairs(detected) do
    local prev = merged[#merged]
    if prev and r.start <= prev["end"] + 1 then
      prev["end"] = math.max(prev["end"], r["end"])
      prev.texts[#prev.texts + 1] = r.text or ""
    else
      table.insert(merged, { start = r.start, ["end"] = r["end"], texts = { r.text or "" } })
    end
  end

  local out = {} ---@type { start: integer, ["end"]: integer, texts: string[] }[]
  for _, r in ipairs(merged) do
    local span = r["end"] - r.start + 1
    if span >= opts.min_lines then
      table.insert(out, r)
    end
  end
  return out
end

---@param win integer
---@param regions { start: integer, ["end"]: integer, texts: string[] }[]
local function close_regions(win, regions)
  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    for _, r in ipairs(regions) do
      -- Only act when the line is currently visible (not hidden by a closed
      -- parent). `zc` then closes the innermost open fold, i.e. the logging one.
      if vim.fn.foldlevel(r.start) > 0 and vim.fn.foldclosed(r.start) == -1 then
        vim.fn.cursor(r.start, 1)
        pcall(vim.cmd.normal, { args = { "zc" }, bang = true })
      end
    end
    vim.fn.winrestview(view)
  end)
end

-- Build (and cache) the per-line foldexpr result for `bufnr`. Non-logging lines
-- get the *verbatim* base value, so general folding is byte-for-byte identical
-- to whatever origami/treesitter/LSP produces. Only logging lines are rewritten
-- to nest one level deeper than their surroundings.
---@param bufnr integer
function M._recompute(bufnr)
  local n = vim.api.nvim_buf_line_count(bufnr)
  local base = M._base[bufnr] or default_base

  local raw, levels, prev = {}, {}, 0 ---@type integer[], integer[], integer
  for l = 1, n do
    local v = base(l)
    raw[l] = v
    levels[l] = resolve(v, prev)
    prev = levels[l]
  end

  local regions = fold_regions(require("fold-logging.detect").detect(bufnr), config.options)
  local result = {} ---@type (string|integer)[]
  for l = 1, n do
    result[l] = raw[l]
  end
  for _, reg in ipairs(regions) do
    local lvl = (levels[reg.start] or 0) + 1
    result[reg.start] = ">" .. lvl
    for l = reg.start + 1, reg["end"] - 1 do
      result[l] = tostring(lvl)
    end
    if reg["end"] > reg.start then
      result[reg["end"]] = "<" .. lvl
    end
  end

  M._cache[bufnr] = {
    tick = vim.api.nvim_buf_get_changedtick(bufnr),
    result = result,
    regions = regions,
  }
end

-- The foldexpr installed on attached buffers. Cheap: full computation happens
-- once per change, then every line is a table lookup.
function M.expr()
  local bufnr = vim.api.nvim_get_current_buf()
  local c = M._cache[bufnr]
  if not c or c.tick ~= vim.api.nvim_buf_get_changedtick(bufnr) then
    M._recompute(bufnr)
    c = M._cache[bufnr]
  end
  return c.result[vim.v.lnum] or "0"
end

-- Capture a base foldexpr and install ours. Returns false (without touching the
-- buffer) when we can't produce sensible general folds, so we never wipe out a
-- user's existing folding.
---@param bufnr? integer
---@param win? integer
---@return boolean attached
function M.attach(bufnr, win)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  win = (win and win ~= 0) and win or vim.api.nvim_get_current_win()
  local ft = vim.bo[bufnr].filetype

  local cur = vim.api.nvim_get_option_value("foldexpr", { win = win }) or "" --[[@as string]]
  local cur_fm = vim.api.nvim_get_option_value("foldmethod", { win = win }) --[[@as string]]
  -- "ours" means we already attached *this buffer* (foldexpr/foldmethod are
  -- window-local, so the string alone can be a leftover from another buffer).
  local ours = M._base[bufnr] ~= nil
  -- A foldexpr string left over from another fold-logging buffer in the same
  -- window must not be mistaken for this buffer's original folding.
  local inherited = cur:find("fold%-logging") ~= nil

  -- Don't clobber a deliberate non-expr folding setup (marker/indent/syntax/diff).
  -- We compose with `expr` (origami/treesitter/LSP) and will bootstrap from the
  -- inert `manual` default, but anything else is left alone.
  if not ours and cur_fm ~= "expr" and cur_fm ~= "manual" then
    vim.b[bufnr].fold_logging_skip = true
    return false
  end

  local bootstrapping = not ours and cur_fm ~= "expr"
  local base = config.options.base_foldexpr ---@type (fun(lnum: integer): string|integer|nil)|nil
  if not base then
    if cur:find("lsp") then
      base = function(lnum)
        local ok, r = pcall(vim.lsp.foldexpr, lnum)
        return (ok and r) and r or 0
      end
    elseif cur:find("treesitter") or has_parser(bufnr, ft) then
      base = default_base
    elseif ours then
      base = M._base[bufnr] or default_base
    else
      vim.b[bufnr].fold_logging_skip = true
      return false
    end
  end

  if not ours then
    M._prev[bufnr] = {
      foldmethod = cur_fm,
      foldexpr = inherited and "0" or cur,
      foldlevel = vim.api.nvim_get_option_value("foldlevel", { win = win }),
      foldminlines = vim.api.nvim_get_option_value("foldminlines", { win = win }),
    }
  end
  M._base[bufnr] = base
  M._cache[bufnr] = nil
  vim.api.nvim_set_option_value("foldmethod", "expr", { win = win })
  vim.api.nvim_set_option_value("foldexpr", "v:lua.require'fold-logging.fold'.expr()", { win = win })
  -- When we introduce expr folding ourselves, keep general folds open by default
  -- so only the logging folds (which we close explicitly) appear collapsed.
  if bootstrapping then
    vim.api.nvim_set_option_value("foldlevel", 99, { win = win })
  end
  -- A lone single-line fold only displays closed when 'foldminlines' is 0, so
  -- enable that when min_lines allows one-line logging folds.
  if config.options.min_lines <= 1 then
    vim.api.nvim_set_option_value("foldminlines", 0, { win = win })
  end
  return true
end

---@param bufnr? integer
---@param win? integer
---@return boolean attached
function M.ensure_attached(bufnr, win)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  win = (win and win ~= 0) and win or vim.api.nvim_get_current_win()
  local cur = vim.api.nvim_get_option_value("foldexpr", { win = win }) or "" --[[@as string]]
  if M._base[bufnr] and cur:find("fold%-logging") then
    return true
  end
  return M.attach(bufnr, win)
end

-- Find a window currently displaying `bufnr` (preferring the current one).
---@param bufnr integer
---@return integer|nil window
function M.window_for(bufnr)
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(cur) == bufnr then
    return cur
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      return w
    end
  end
  return nil
end

-- Close only the logging folds, leaving general folds (and parents the user has
-- closed) untouched.
---@param bufnr? integer
function M.close(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local win = M.window_for(bufnr)
  if not win then
    return
  end
  vim.b[bufnr].fold_logging_skip = false -- explicit invocation: retry and report
  if not M.ensure_attached(bufnr, win) then
    return
  end
  M._recompute(bufnr)
  local regions = M._cache[bufnr].regions

  close_regions(win, regions)
  M._known[bufnr] = signatures(regions)
  M._closed[bufnr] = true
end

-- Close only regions that were not present during the previous fold pass. Used
-- on write so manually opened existing logging folds stay open.
---@param bufnr? integer
function M.close_new(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local win = M.window_for(bufnr)
  if not win then
    return
  end
  if not M.ensure_attached(bufnr, win) then
    return
  end
  local known = vim.deepcopy(M._known[bufnr] or {})
  M._recompute(bufnr)
  local regions = M._cache[bufnr].regions
  local new_regions = {}
  for _, r in ipairs(regions) do
    local key = signature(r)
    if (known[key] or 0) > 0 then
      known[key] = known[key] - 1
    else
      new_regions[#new_regions + 1] = r
    end
  end

  close_regions(win, new_regions)
  M._known[bufnr] = signatures(regions)
end

-- Open only the logging folds (folds that start exactly on a detected region).
---@param bufnr? integer
function M.open(bufnr)
  bufnr = (bufnr or bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local win = M.window_for(bufnr)
  if not win then
    return
  end
  vim.b[bufnr].fold_logging_skip = false -- explicit invocation: retry and report
  if not M.ensure_attached(bufnr, win) then
    return
  end
  M._recompute(bufnr)
  local regions = M._cache[bufnr].regions

  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    for _, r in ipairs(regions) do
      if vim.fn.foldclosed(r.start) == r.start then
        vim.fn.cursor(r.start, 1)
        pcall(vim.cmd.normal, { args = { "zo", bang = true } })
      end
    end
    vim.fn.winrestview(view)
  end)
  M._closed[bufnr] = false
end

---@param bufnr? integer
function M.toggle(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  if M._closed[bufnr] then
    M.open(bufnr)
  else
    M.close(bufnr)
  end
end

-- Recompute folds (e.g. after edits) and re-apply the closed state if active.
---@param bufnr? integer
function M.refresh(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local win = M.window_for(bufnr)
  M._cache[bufnr] = nil
  if win then
    -- re-assert our foldexpr to force Vim to recompute folds
    vim.api.nvim_win_call(win, function()
      vim.api.nvim_set_option_value("foldmethod", "expr", { win = win })
    end)
  end
  if M._closed[bufnr] then
    M.close(bufnr)
  else
    M._recompute(bufnr)
    M._known[bufnr] = signatures(M._cache[bufnr] and M._cache[bufnr].regions or {})
  end
end

-- Populate the quickfix list with detected logging statements.
---@param bufnr? integer
function M.list(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local regions = require("fold-logging.detect").detect(bufnr)
  if #regions == 0 then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local items = {} ---@type vim.quickfix.entry[]
  for _, r in ipairs(regions) do
    table.insert(items, {
      bufnr = bufnr,
      lnum = r.start,
      end_lnum = r["end"],
      text = vim.trim(lines[r.start] or r.text or ""),
    })
  end
  vim.fn.setqflist({}, " ", { title = "fold-logging: detected", items = items })
  vim.cmd("botright copen")
end

-- Restore original folding on every window we changed and forget all state.
function M.detach_all()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    local prev = M._prev[b]
    local cur = vim.api.nvim_get_option_value("foldexpr", { win = w }) or "" --[[@as string]]
    if prev and cur:find("fold%-logging") then
      vim.api.nvim_set_option_value("foldmethod", prev.foldmethod or "manual", { win = w })
      vim.api.nvim_set_option_value("foldexpr", prev.foldexpr or "0", { win = w })
      if prev.foldlevel then
        vim.api.nvim_set_option_value("foldlevel", prev.foldlevel, { win = w })
      end
      if prev.foldminlines then
        vim.api.nvim_set_option_value("foldminlines", prev.foldminlines, { win = w })
      end
    end
  end
  M._base, M._cache, M._closed, M._prev, M._known = {}, {}, {}, {}, {}
end

return M
