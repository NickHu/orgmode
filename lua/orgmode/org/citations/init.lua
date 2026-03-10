local ts_utils = require('orgmode.utils.treesitter')

---@class OrgCitations
---@field private sources OrgCitationSource[]
---@field private sources_by_name table<string, OrgCitationSource>
---@field private files OrgFiles | nil
local OrgCitations = {}
OrgCitations.__index = OrgCitations

---@param opts? { files?: OrgFiles }
function OrgCitations:new(opts)
  opts = opts or {}
  local this = setmetatable({
    sources = {},
    sources_by_name = {},
    files = opts.files,
  }, OrgCitations)
  this:_setup_builtin_sources()
  this:_add_custom_sources()
  return this
end

---Register a citation source.
---@param source OrgCitationSource
function OrgCitations:add_source(source)
  if self.sources_by_name[source:get_name()] then
    error('Citation source ' .. source:get_name() .. ' already exists', 0)
  end
  self.sources_by_name[source:get_name()] = source
  table.insert(self.sources, source)
end

---Return all citation items from every registered source.
---@return OrgCitationItem[]
function OrgCitations:get_items()
  local items = {}
  for _, source in ipairs(self.sources) do
    vim.list_extend(items, source:get_items())
  end
  return items
end

---Attempt to navigate to the bibliography entry with the given key.
---Each registered source is tried in order; the first one that returns true wins.
---@param key string
---@return boolean
function OrgCitations:follow(key)
  for _, source in ipairs(self.sources) do
    if source.follow and source:follow(key) then
      return true
    end
  end
  return false
end

---Return the citation key under the current cursor position, or nil if not on a citation.
---Prefers the tree-sitter `citation_reference` node (available with the updated grammar);
---falls back to line-pattern matching for compatibility with older parser versions.
---@return string | nil
function OrgCitations:at_cursor()
  -- Try tree-sitter citation_reference node first (available with updated grammar)
  local node = ts_utils.closest_node(ts_utils.get_node(), { 'citation_reference' })
  if node then
    local key_node = node:field('key')[1]
    if key_node then
      return vim.treesitter.get_node_text(key_node, 0)
    end
  end

  return self:_at_cursor_pattern()
end

---@private
---Fallback pattern-based cursor detection for use with older grammar versions
---that do not yet expose `citation_reference` nodes.
---@return string | nil
function OrgCitations:_at_cursor_pattern()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- convert 0-indexed column to 1-indexed

  local before_cursor = line:sub(1, col)
  local after_cursor = line:sub(col + 1)

  -- Must be inside a [cite:...] or [cite/style:...] context
  if not before_cursor:match('%[cite[/:]') then
    return nil
  end

  -- Cursor must be on or after '@'
  local key_prefix = before_cursor:match('@([^%s%]%;,@]*)$')
  if key_prefix == nil then
    return nil
  end

  local key_suffix = after_cursor:match('^([^%s%]%;,@]*)')
  return key_prefix .. (key_suffix or '')
end

---@private
function OrgCitations:_setup_builtin_sources()
  self:add_source(require('orgmode.org.citations.bibtex'):new({ files = self.files }))
end

---@private
function OrgCitations:_add_custom_sources()
  local config = require('orgmode.config')
  for i, source in ipairs(config.citations.sources) do
    if type(source.get_name) == 'function' then
      self:add_source(source)
    else
      vim.notify(('Citation source at index %d must have a get_name method'):format(i), vim.log.levels.ERROR)
    end
  end
end

return OrgCitations
