-- Headless test harness. Run from the repo root with:
--   nvim --headless -u NORC -c "luafile tests/run.lua"
--
-- It exercises detection and folding against the fixtures, using a Treesitter
-- foldexpr as the "base" (the same kind of general folding origami drives).

local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:append(root)

local failures = 0
local function check(name, cond, extra)
  if cond then
    print("ok   - " .. name)
  else
    failures = failures + 1
    print("FAIL - " .. name .. (extra and ("  (" .. tostring(extra) .. ")") or ""))
  end
end

require("fold-logging").setup({ auto_fold = true, fold_print = true })
local config = require("fold-logging.config")

-- Simulate a foldexpr-based general-folding setup (as origami/treesitter give).
local function open_fixture(path)
  vim.cmd("enew")
  vim.cmd("edit " .. root .. path)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("foldmethod", "expr", { win = win })
  vim.api.nvim_set_option_value("foldexpr", "v:lua.vim.treesitter.foldexpr()", { win = win })
  vim.api.nvim_set_option_value("foldlevel", 99, { win = win }) -- general folds open
  -- Trigger our BufWinEnter path now that the base foldexpr is set.
  require("fold-logging.init")
  vim.cmd("doautocmd BufWinEnter")
  return vim.api.nvim_get_current_buf()
end

-- ---- Python detection -----------------------------------------------------
local buf = open_fixture("/tests/fixtures/sample.py")
local detect = require("fold-logging.detect")
local regions = detect.detect(buf)

local starts = {}
for _, r in ipairs(regions) do
  starts[r.start] = r["end"]
end

-- multi-line logger.debug(...) call spanning lines 7..11
check("py: detects multi-line logger.debug", starts[7] == 11, vim.inspect(regions))
-- print("partial", total) on line 15
check("py: detects print()", starts[15] ~= nil, vim.inspect(regions))
-- logging.info on line 16
check("py: detects logging.info", starts[16] ~= nil, vim.inspect(regions))
-- three consecutive print() calls (lines 21..23)
check("py: detects first chatty print", starts[21] ~= nil, vim.inspect(regions))
-- it should NOT fold the function/return/import lines
check("py: does not flag import", starts[1] == nil)
-- it should NOT flag logging setup calls (basicConfig / getLogger), only levels
check("py: does not flag logging.getLogger setup", starts[3] == nil, vim.inspect(regions))

-- fold_print toggle: print(...) is only detected when fold_print is enabled
config.options.fold_print = false
local noprint = {}
for _, r in ipairs(detect.detect(buf)) do
  noprint[r.start] = r["end"]
end
check("fold_print=false: print(15) NOT detected", noprint[15] == nil, vim.inspect(noprint))
check("fold_print=false: logging.info(16) still detected", noprint[16] ~= nil, vim.inspect(noprint))
config.options.fold_print = true

-- ---- Folding behaviour ----------------------------------------------------
require("fold-logging.fold")._recompute(buf)
local cache = require("fold-logging.fold")._cache[buf]
-- merged debug block stays its own fold; the 3 consecutive prints merge to 22..24
local function has_region(s, e)
  for _, r in ipairs(cache.regions) do
    if r.start == s and r["end"] == e then
      return true
    end
  end
  return false
end
check("fold: multi-line debug region 7..11", has_region(7, 11), vim.inspect(cache.regions))
check("fold: consecutive prints merged 21..23", has_region(21, 23), vim.inspect(cache.regions))
-- with default fold_single_line=false, the lone print/logging.info on 15/16
-- merge together (adjacent) into 15..16 and are kept (span 2)
check("fold: adjacent single-liners merged 15..16", has_region(15, 16), vim.inspect(cache.regions))

-- Auto-fold should have closed the logging folds while leaving the function open.
vim.wait(200, function()
  return false
end)
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_call(win, function()
  check("autofold: logger.debug fold is closed", vim.fn.foldclosed(7) == 7, "foldclosed(7)=" .. vim.fn.foldclosed(7))
  check("autofold: function body line not folded away", vim.fn.foldclosed(13) == -1, "foldclosed(13)=" .. vim.fn.foldclosed(13))
end)

-- Unfold then re-fold via the API.
require("fold-logging").unfold(buf)
vim.api.nvim_win_call(win, function()
  check("unfold: logger.debug fold is open", vim.fn.foldclosed(7) == -1)
end)
require("fold-logging").fold(buf)
vim.api.nvim_win_call(win, function()
  check("refold: logger.debug fold closed again", vim.fn.foldclosed(7) == 7)
end)

-- ---- Base composition preserved -------------------------------------------
-- A non-logging line must return exactly the base foldexpr value.
local base_val = vim.treesitter.foldexpr(6) -- def compute(...) line
require("fold-logging.fold")._recompute(buf)
local ours_val = require("fold-logging.fold")._cache[buf].result[6]
check("compose: non-logging line keeps base foldexpr value", tostring(ours_val) == tostring(base_val), ("base=%s ours=%s"):format(tostring(base_val), tostring(ours_val)))

-- ---- min_lines option -----------------------------------------------------
config.options.min_lines = 3
require("fold-logging.fold")._cache[buf] = nil
require("fold-logging.fold")._recompute(buf)
local mcache = require("fold-logging.fold")._cache[buf]
local function mcache_has(s, e)
  for _, r in ipairs(mcache.regions) do
    if r.start == s and r["end"] == e then
      return true
    end
  end
  return false
end
check("min_lines=3: keeps 5-line logger.debug (7..11)", mcache_has(7, 11), vim.inspect(mcache.regions))
check("min_lines=3: keeps 3-line print block (21..23)", mcache_has(21, 23), vim.inspect(mcache.regions))
check("min_lines=3: drops 2-line block (15..16)", not mcache_has(15, 16), vim.inspect(mcache.regions))
config.options.min_lines = 1

-- ---- regex fallback (no treesitter) ---------------------------------------
local fb = require("fold-logging.detect").fallback
-- effective spec with print patterns active (mirrors fold_print = true)
local pyspec = config.options.languages.python
local spec = {
  call_node_types = pyspec.call_node_types,
  patterns = vim.list_extend(vim.deepcopy(pyspec.patterns), vim.deepcopy(pyspec.print_patterns)),
}
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "x = 1",
  "logger.info(",
  '    "multi",',
  ")",
  'print("solo")',
})
local fbuf = vim.api.nvim_get_current_buf()
local fregions = fb(fbuf, spec)
local fstarts = {}
for _, r in ipairs(fregions) do
  fstarts[r.start] = r["end"]
end
check("fallback: multi-line logger.info 2..4", fstarts[2] == 4, vim.inspect(fregions))
check("fallback: single-line print 5", fstarts[5] == 5, vim.inspect(fregions))
check("fallback: does not flag assignment", fstarts[1] == nil)

print(("\n%d failure(s)"):format(failures))
vim.cmd((failures == 0) and "qa!" or "cq!")
