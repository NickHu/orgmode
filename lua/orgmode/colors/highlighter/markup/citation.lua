---@class OrgCitationHighlighter : OrgMarkupHighlighter
---@field private markup OrgMarkupHighlighter
local OrgCitation = {
  valid_capture_names = {
    ['citation.start'] = true,
    ['citation.end'] = true,
  },
}

---@param opts { markup: OrgMarkupHighlighter }
function OrgCitation:new(opts)
  local data = {
    markup = opts.markup,
  }
  setmetatable(data, self)
  self.__index = self
  return data
end

---@param node TSNode
---@param name string
---@return OrgMarkupNode | false
function OrgCitation:parse_node(node, name)
  if not self.valid_capture_names[name] then
    return false
  end
  local type = node:type()
  if type == '[' then
    return self:_parse_start_node(node)
  end

  if type == ']' then
    return self:_parse_end_node(node)
  end

  return false
end

---@private
---@param node TSNode
---@return OrgMarkupNode | false
function OrgCitation:_parse_start_node(node)
  local first_sibling = node:next_sibling()
  local second_sibling = first_sibling and first_sibling:next_sibling()

  if not first_sibling or not second_sibling then
    return false
  end
  if first_sibling:type() ~= 'str' then
    return false
  end
  if second_sibling:type() ~= ':' and second_sibling:type() ~= '/' then
    return false
  end

  return {
    type = 'citation',
    id = 'citation_start',
    char = '[',
    seek_id = 'citation_end',
    nestable = false,
    range = self.markup:node_to_range(node),
    node = node,
  }
end

---@private
---@param node TSNode
---@return OrgMarkupNode | false
function OrgCitation:_parse_end_node(node)
  local prev_sibling = node:prev_sibling()

  if not prev_sibling then
    return false
  end

  return {
    type = 'citation',
    id = 'citation_end',
    seek_id = 'citation_start',
    char = ']',
    nestable = false,
    range = self.markup:node_to_range(node),
    node = node,
  }
end

---@param entry OrgMarkupNode
---@return boolean
function OrgCitation:is_valid_start_node(entry)
  return entry.type == 'citation' and entry.id == 'citation_start'
end

---@param entry OrgMarkupNode
---@return boolean
function OrgCitation:is_valid_end_node(entry)
  return entry.type == 'citation' and entry.id == 'citation_end'
end

---@param highlights OrgMarkupHighlight[]
---@param bufnr number
function OrgCitation:highlight(highlights, bufnr)
  local namespace = self.markup.highlighter.namespace
  local ephemeral = self.markup:use_ephemeral()

  for _, entry in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace, entry.from.line, entry.from.start_col, {
      ephemeral = ephemeral,
      end_col = entry.to.end_col,
      hl_group = '@org.citation',
      priority = 110,
    })
  end
end

---@param highlights OrgMarkupHighlight[]
---@return OrgMarkupPreparedHighlight[]
function OrgCitation:prepare_highlights(highlights)
  local ephemeral = self.markup:use_ephemeral()
  local extmarks = {}
  for _, entry in ipairs(highlights) do
    table.insert(extmarks, {
      start_line = entry.from.line,
      start_col = entry.from.start_col,
      end_col = entry.to.end_col,
      ephemeral = ephemeral,
      hl_group = '@org.citation',
      priority = 110,
    })
  end
  return extmarks
end

return OrgCitation
