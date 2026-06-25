local config = require("fold-logging.config")
local fold = require("fold-logging.fold")
local detect = require("fold-logging.detect")

---@class FoldLogging
local M = {}

---@param buf integer
local function supported(buf)
  return config.options.languages[vim.bo[buf].filetype] ~= nil
end

-- Attach to a freshly visible supported buffer and, if enabled, auto-fold once
-- per file load.
---@param buf integer
local function on_open(buf)
  if not config.options.enable or not vim.api.nvim_buf_is_valid(buf) or not supported(buf) then
    return
  end
  if vim.b[buf].fold_logging_skip then -- already determined unsupported; stay quiet
    return
  end
  local win = fold.window_for(buf)
  if not win then
    return
  end
  if not fold.ensure_attached(buf, win) then
    return
  end
  if config.options.auto_fold and not vim.b[buf].fold_logging_autofolded then
    vim.b[buf].fold_logging_autofolded = true
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and config.options.enable then
        pcall(fold.close, buf)
      end
    end)
  end
end

---@param buf integer
local function on_write(buf)
  if
    not config.options.enable
    or not config.options.auto_fold
    or not vim.api.nvim_buf_is_valid(buf)
    or not supported(buf)
  then
    return
  end
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) and config.options.enable and config.options.auto_fold then
      pcall(fold.close_new, buf)
    end
  end)
end

function M.setup(opts)
  config.setup(opts)

  local group = vim.api.nvim_create_augroup("FoldLogging", { clear = true })
  local fts = vim.tbl_keys(config.options.languages)

  -- Defer to vim.schedule so attachment runs after every synchronous handler
  -- for the same event (e.g. origami's foldexpr setup), letting us capture the
  -- correct base foldexpr regardless of plugin load order.
  local function schedule_open(a)
    vim.schedule(function()
      on_open(a.buf)
    end)
  end

  if #fts > 0 then
    vim.api.nvim_create_autocmd("FileType", { group = group, pattern = fts, callback = schedule_open })
  end
  vim.api.nvim_create_autocmd("BufWinEnter", { group = group, callback = schedule_open })
  -- Re-arm the one-shot auto-fold on every (re)load of the file.
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(a)
      vim.b[a.buf].fold_logging_autofolded = false
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(a)
      on_write(a.buf)
    end,
  })

  local cmd = vim.api.nvim_create_user_command
  cmd("FLFold", function()
    fold.close()
  end, { desc = "Fold logging statements in the current buffer" })
  cmd("FLUnfold", function()
    fold.open()
  end, { desc = "Unfold logging statements in the current buffer" })
  cmd("FLToggle", function()
    fold.toggle()
  end, { desc = "Toggle logging folds in the current buffer" })
  cmd("FLList", function()
    fold.list()
  end, { desc = "List detected logging statements in the quickfix window" })
  cmd("FLRefresh", function()
    fold.refresh()
  end, { desc = "Recompute logging folds for the current buffer" })
  cmd("FLEnable", function()
    M.enable()
  end, { desc = "Enable fold-logging" })
  cmd("FLDisable", function()
    M.disable()
  end, { desc = "Disable fold-logging and restore original folding" })

  -- Handle buffers already open when setup() runs (e.g. lazy-loaded via :cmd).
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and supported(b) then
      vim.schedule(function()
        on_open(b)
      end)
    end
  end
end

function M.enable()
  config.options.enable = true
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if supported(b) then
      fold.ensure_attached(b, w)
    end
  end
end

function M.disable()
  config.options.enable = false
  fold.detach_all()
end

-- Public Lua API.
M.detect = require("fold-logging.detect").detect
M.fold = fold.close
M.list = fold.list
M.refresh = fold.refresh
M.toggle = fold.toggle
M.unfold = fold.open

return M
