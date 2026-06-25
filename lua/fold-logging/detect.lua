---@class FoldLogging.Detect
local M = {}

-- A detected region is `{ start = <1-based line>, ["end"] = <1-based line>, text = <callee> }`.

---@param text? string
---@param patterns string[]
---@return boolean match
local function matches(text, patterns)
  if not text then
    return false
  end
  for _, pat in ipairs(patterns) do
    if text:find(pat) then
      return true
    end
  end
  return false
end

-- Text of the function being called for a treesitter call node, e.g.
-- "print", "logging.info", "self.logger.warning".
---@param node TSNode
---@param bufnr integer
---@return string|nil text
local function callee_text(node, bufnr)
  local fn = node:field("function")[1] or node:named_child(0)
  if not fn then
    return nil
  end
  return vim.treesitter.get_node_text(fn, bufnr)
end

-- Treesitter backend. Returns a list of regions, or nil if no parser/query.
---@param bufnr integer
---@param spec FoldLogging.Languages.Language
---@param lang string
---@return { start: integer, ["end"]: integer, text: string }[]|nil
function M.treesitter(bufnr, spec, lang)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not (ok and parser) then
    return nil
  end
  local trees = parser:parse()
  if not (trees and trees[1]) then
    return nil
  end
  local root = trees[1]:root()

  local parts = {} ---@type string[]
  for _, nt in ipairs(spec.call_node_types or {}) do
    table.insert(parts, ("(%s) @call"):format(nt))
  end
  if #parts == 0 then
    return nil
  end
  local okq, query = pcall(vim.treesitter.query.parse, lang, table.concat(parts, "\n"))
  if not (okq and query) then
    return nil
  end

  local out = {} ---@type { start: integer, ["end"]: integer, text: string }[]
  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local txt = callee_text(node, bufnr)
    if matches(txt, spec.patterns) then
      local sr, _, er, ec = node:range()
      -- treesitter end position is exclusive; if it lands on column 0 the call
      -- really ends on the previous line.
      if ec == 0 and er > sr then
        er = er - 1
      end
      table.insert(out, { start = sr + 1, ["end"] = er + 1, text = vim.trim(txt or "") })
    end
  end
  return out
end

-- Walk forward from `start_line` counting parentheses to find the line on which
-- the call's argument list closes. Heuristic, used only without a parser.
---@param lines string[]
---@param start_line integer
---@return integer line_idx
local function balanced_end(lines, start_line)
  local depth, started = 0, false
  for j = start_line, #lines do
    for ch in lines[j]:gmatch("[%(%)]") do
      if ch == "(" then
        depth, started = depth + 1, true
      else
        depth = depth - 1
      end
    end
    if started and depth <= 0 then
      return j
    end
  end
  return start_line
end

-- Regex/line backend for when no treesitter parser is available.
---@param bufnr integer
---@param spec FoldLogging.Languages.Language
---@return { start: integer, ["end"]: integer, text: string }[] spec
function M.fallback(bufnr, spec)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {} ---@type { start: integer, ["end"]: integer, text: string }[]
  for i, line in ipairs(lines) do
    for callee in line:gmatch("([%w_%.]+)%s*%(") do
      if matches(callee, spec.patterns) then
        table.insert(out, { start = i, ["end"] = balanced_end(lines, i), text = callee })
        break
      end
    end
  end
  return out
end

-- Keep only the outermost regions: drop any region fully contained in (or
-- overlapping the tail of) one that starts earlier.
---@param regions { start: integer, ["end"]: integer, text: string }[]
---@return { start: integer, ["end"]: integer, text: string }[] out
local function normalize(regions)
  table.sort(regions, function(a, b)
    if a.start ~= b.start then
      return a.start < b.start
    end
    return a["end"] > b["end"]
  end)
  local out, last_end = {}, 0 ---@type { start: integer, ["end"]: integer, text: string }[], integer
  for _, r in ipairs(regions) do
    if r.start > last_end then
      table.insert(out, r)
      last_end = r["end"]
    elseif r["end"] > last_end then
      last_end = r["end"]
    end
  end
  return out
end

-- The patterns active for a spec: always `patterns`, plus `print_patterns` when
-- the `fold_print` option is enabled.
---@param spec FoldLogging.Languages.Language
---@return FoldLogging.Languages.Language effective_spec
local function effective_spec(spec)
  local patterns = vim.deepcopy(spec.patterns or {})
  if require("fold-logging.config").options.fold_print and spec.print_patterns then
    vim.list_extend(patterns, spec.print_patterns)
  end
  return { call_node_types = spec.call_node_types, patterns = patterns }
end

-- Public: detect logging regions in `bufnr`. Returns normalized outermost
-- regions sorted by start line.
---@param bufnr? integer
---@return { start: integer, ["end"]: integer, text: string }[] normalized
function M.detect(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local spec = require("fold-logging.config").options.languages[ft]
  if not spec then
    return {}
  end
  spec = effective_spec(spec)
  local lang = vim.treesitter.language.get_lang(ft) or ft
  local regions = M.treesitter(bufnr, spec, lang)
  if not regions then
    regions = M.fallback(bufnr, spec)
  end
  return normalize(regions)
end

return M
