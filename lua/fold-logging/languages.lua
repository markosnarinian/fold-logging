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

local M = {}

-- Standard library log-level methods. Matching on the method name (anchored to
-- the end of the callee) folds `logging.info(...)`, `logger.debug(...)`,
-- `self.logger.warning(...)`, `log.error(...)`, ... while deliberately leaving
-- setup calls like `logging.basicConfig(...)` / `logging.getLogger(...)` alone.
local python = {
  call_node_types = { "call" },
  patterns = {
    "^print$", -- print(...)
    "^pprint$", -- pprint(...)
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
}

M.defaults = {
  python = python,
}

return M
