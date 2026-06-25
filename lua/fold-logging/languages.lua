-- Built-in language specifications.
--
-- A spec is keyed by `filetype` and describes how to recognise logging /
-- debug-print calls in that language. Two detection backends use the same spec:
--
--   * Treesitter (preferred): every node whose type is in `call_node_types`
--     is inspected, the *callee* text is extracted (e.g. "logger.info",
--     "print") and tested against `patterns`.
--   * Regex fallback (no parser): each line is scanned for `callee(` shapes and
--     the captured callee is tested against the same `patterns`.
--
-- `patterns` are plain Lua patterns matched with `string.find` (unanchored
-- unless you anchor them yourself). They are tested against the callee text, so
-- `"%.info$"` matches `logging.info` / `logger.info` / `self.logger.info`.

---@class FoldLogging.Languages.Language
---@field call_node_types? string[]
---@field patterns? string[]
---@field print_patterns? string[]

---@class FoldLogging.Languages
---@field defaults table<string, FoldLogging.Languages.Language>
local M = {}

M.defaults = {
  -- `patterns` are always active. `print_patterns` are only used when the
  -- `fold_print` option is enabled.
  --
  -- The log-level patterns match on the method name (anchored to the end of the
  -- callee), so `logging.info(...)`, `logger.debug(...)`, `self.logger.warning(...)`,
  -- `log.error(...)`, ... fold, while setup calls like `logging.basicConfig(...)`
  -- / `logging.getLogger(...)` are deliberately left alone.
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
      "%.log$", -- logging.log(level, ...)
    },
    print_patterns = {
      "^print$", -- print(...)
      "^pprint$", -- pprint(...)
    },
  },
}

return M
