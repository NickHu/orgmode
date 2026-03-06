local OrgCitations = require('orgmode.org.citations')

--- Build a simple in-memory citation source for testing.
---@param name string
---@param items OrgCitationItem[]
---@param follow_handler? fun(key: string): boolean
local function make_source(name, items, follow_handler)
  local source = {}
  function source:get_name()
    return name
  end
  function source:get_items()
    return items
  end
  if follow_handler then
    source.follow = follow_handler
  end
  return source
end

describe('OrgCitations', function()
  describe('add_source', function()
    it('should register a citation source', function()
      local citations = OrgCitations:new()
      citations:add_source(make_source('test', {}))
      assert.are.same(1, #citations.sources)
    end)

    it('should error when registering a source with a duplicate name', function()
      local citations = OrgCitations:new()
      citations:add_source(make_source('test', {}))
      assert.has_error(function()
        citations:add_source(make_source('test', {}))
      end)
    end)
  end)

  describe('get_items', function()
    it('should return items from all registered sources', function()
      local citations = OrgCitations:new()
      citations:add_source(make_source('src1', {
        { key = 'smith2020', label = 'Smith 2020' },
        { key = 'jones2021' },
      }))
      citations:add_source(make_source('src2', {
        { key = 'doe2022', description = 'Doe et al. 2022' },
      }))

      local items = citations:get_items()
      assert.are.same(3, #items)
      assert.are.same('smith2020', items[1].key)
      assert.are.same('jones2021', items[2].key)
      assert.are.same('doe2022', items[3].key)
    end)

    it('should return empty list when no sources are registered', function()
      local citations = OrgCitations:new()
      assert.are.same(0, #citations:get_items())
    end)
  end)

  describe('follow', function()
    it('should return false when no source handles the key', function()
      local citations = OrgCitations:new()
      citations:add_source(make_source('src', { { key = 'key1' } }))
      assert.is_false(citations:follow('missing'))
    end)

    it('should return true when a source handles the key', function()
      local citations = OrgCitations:new()
      local followed = nil
      citations:add_source(make_source('src', { { key = 'key1' } }, function(_, key)
        followed = key
        return true
      end))
      local result = citations:follow('key1')
      assert.is_true(result)
      assert.are.same('key1', followed)
    end)

    it('should try sources in order and stop at the first match', function()
      local citations = OrgCitations:new()
      local calls = {}
      citations:add_source(make_source('src1', {}, function(_, key)
        table.insert(calls, 'src1:' .. key)
        return false
      end))
      citations:add_source(make_source('src2', {}, function(_, key)
        table.insert(calls, 'src2:' .. key)
        return true
      end))
      citations:add_source(make_source('src3', {}, function(_, key)
        table.insert(calls, 'src3:' .. key)
        return true
      end))

      citations:follow('k')
      assert.are.same({ 'src1:k', 'src2:k' }, calls)
    end)
  end)

  describe('_at_cursor_pattern', function()
    -- Helper: mock cursor position on a given line
    local function mock_cursor(line_text, col_1indexed)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { line_text })
      vim.api.nvim_win_set_cursor(0, { 1, col_1indexed - 1 }) -- nvim uses 0-indexed col
    end

    before_each(function()
      vim.cmd('new')
    end)

    after_each(function()
      vim.cmd('bwipeout!')
    end)

    it('should return nil when not inside a citation', function()
      local citations = OrgCitations:new()
      mock_cursor('plain text @key here', 17)
      assert.is_nil(citations:_at_cursor_pattern())
    end)

    it('should return the key when cursor is on @key in [cite:@key]', function()
      local citations = OrgCitations:new()
      -- "See [cite:@smith2020] for details"
      -- col 15 is inside "smith2020" (1-indexed)
      mock_cursor('See [cite:@smith2020] for details', 15)
      local key = citations:_at_cursor_pattern()
      assert.are.same('smith2020', key)
    end)

    it('should return the key for styled citations [cite/t:@key]', function()
      local citations = OrgCitations:new()
      mock_cursor('[cite/t:@key2022]', 12)
      local key = citations:_at_cursor_pattern()
      assert.are.same('key2022', key)
    end)

    it('should return the key when cursor is directly on @', function()
      local citations = OrgCitations:new()
      mock_cursor('[cite:@key]', 7) -- col 7 is on '@'
      local key = citations:_at_cursor_pattern()
      assert.are.same('key', key)
    end)

    it('should return nil for [notcite:@key]', function()
      local citations = OrgCitations:new()
      mock_cursor('[notcite:@key]', 11)
      assert.is_nil(citations:_at_cursor_pattern())
    end)
  end)
end)
