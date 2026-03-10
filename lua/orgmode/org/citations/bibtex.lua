local config = require('orgmode.config')

---Module-level parse cache: absolute path -> { mtime_sec, items }
---@type table<string, { mtime_sec: number, items: OrgCitationItem[] }>
local _cache = {}

---Parse a BibTeX file and return OrgCitationItem[].
---Only the citation key is extracted; the description is left nil to keep the
---parser simple and dependency-free.
---@param content string  raw file content
---@return OrgCitationItem[]
local function parse_bibtex(content)
  local items = {}
  -- @type{key, ...}  or  @type(key, ...)
  -- Key runs to the first comma, closing brace/paren, or whitespace.
  for entry_type, key in content:gmatch('@(%a%w*)%s*[{(]%s*([^%s,}%)]+)') do
    local lt = entry_type:lower()
    if lt ~= 'string' and lt ~= 'preamble' and lt ~= 'comment' then
      table.insert(items, { key = key })
    end
  end
  return items
end

---Read and parse a .bib file, using a mtime-based cache to avoid re-parsing.
---@param path string  absolute, readable file path
---@return OrgCitationItem[]
local function parse_file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return {}
  end
  local mtime_sec = stat.mtime.sec
  local cached = _cache[path]
  if cached and cached.mtime_sec == mtime_sec then
    return cached.items
  end
  local lines = vim.fn.readfile(path)
  local items = parse_bibtex(table.concat(lines, '\n'))
  _cache[path] = { mtime_sec = mtime_sec, items = items }
  return items
end

---Resolve a raw bibliography path to an absolute path.
---@param raw string  path as written in config or #+bibliography: directive
---@param base_dir? string  directory used to resolve relative paths (default: CWD)
---@return string  absolute (possibly non-existent) path
local function resolve_path(raw, base_dir)
  raw = vim.trim(raw)
  if raw:sub(1, 1) == '~' then
    return vim.fn.expand(raw)
  end
  if raw:sub(1, 1) ~= '/' then
    local base = base_dir or vim.fn.getcwd()
    return vim.fn.fnamemodify(base .. '/' .. raw, ':p')
  end
  return raw
end

---@class OrgCitationBibtex:OrgCitationSource
---@field private files OrgFiles | nil
local OrgCitationBibtex = {}
OrgCitationBibtex.__index = OrgCitationBibtex

---@param opts { files: OrgFiles | nil }
function OrgCitationBibtex:new(opts)
  return setmetatable({ files = opts and opts.files or nil }, OrgCitationBibtex)
end

---@return string
function OrgCitationBibtex:get_name()
  return 'bibtex'
end

---@return OrgCitationItem[]
function OrgCitationBibtex:get_items()
  local items = {}
  for _, path in ipairs(self:_get_bib_paths()) do
    vim.list_extend(items, parse_file(path))
  end
  return items
end

---Open the .bib file at the line of the given citation key.
---@param key string
---@return boolean
function OrgCitationBibtex:follow(key)
  for _, path in ipairs(self:_get_bib_paths()) do
    local lnum = self:_find_key_line(path, key)
    if lnum then
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
      vim.fn.cursor(lnum, 1)
      return true
    end
  end
  return false
end

---Return the list of resolved, readable .bib file paths.
---Sources (in order):
---  1. Global `citations.bibliography` config option (string or string[])
---  2. File-local `#+bibliography:` directives in the current org file
---@private
---@return string[]
function OrgCitationBibtex:_get_bib_paths()
  local paths = {}
  local seen = {}

  local function add(raw, base_dir)
    local resolved = resolve_path(raw, base_dir)
    if not seen[resolved] and vim.fn.filereadable(resolved) == 1 then
      seen[resolved] = true
      table.insert(paths, resolved)
    end
  end

  -- 1. Global bibliography
  local global = config.citations.bibliography
  if global then
    if type(global) == 'string' then
      add(global, nil)
    else
      for _, p in ipairs(global) do
        add(p, nil)
      end
    end
  end

  -- 2. File-local #+bibliography: directives
  if self.files then
    local current_filename = vim.fn.expand('%:p')
    if current_filename ~= '' then
      local file = self.files:load_file_sync(current_filename)
      if file then
        local file_dir = vim.fn.fnamemodify(file.filename, ':p:h')
        -- _get_directive with all_matches=true returns all values for the directive
        local directives = file:_get_directive('bibliography', true)
        if directives then
          if type(directives) == 'string' then
            directives = { directives }
          end
          for _, raw in ipairs(directives) do
            add(raw, file_dir)
          end
        end
      end
    end
  end

  return paths
end

---Return the 1-indexed line number of the entry header for `key`, or nil.
---@private
---@param path string
---@param key string
---@return number | nil
function OrgCitationBibtex:_find_key_line(path, key)
  local lines = vim.fn.readfile(path)
  local escaped = vim.pesc(key)
  -- The key must be followed by a delimiter (comma, closing brace/paren, whitespace)
  -- or be at end of line, to avoid matching keys that are prefixes of longer keys.
  local suffix_pat = '[%s,}%)]'
  for i, line in ipairs(lines) do
    if line:match('@%a%w*%s*[{(]%s*' .. escaped .. suffix_pat)
      or line:match('@%a%w*%s*[{(]%s*' .. escaped .. '$')
    then
      return i
    end
  end
  return nil
end

return OrgCitationBibtex
