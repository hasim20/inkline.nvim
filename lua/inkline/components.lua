-- Built-in statusline components.
--
-- Every component is called as `component(ctx, opts)` and may return:
--   * nil / false              -> hidden
--   * "text"                  -> rendered with opts.hl
--   * { text = "...", hl = "Group" }
--   * { { text = "...", hl = "Group" }, ... }
--   * "text", "Group"         -> second return value is the highlight

local git = require('inkline.git')

local M = {}

--- Read a buffer-local option.
--- @param bufnr integer
--- @param name string
--- @return any
local function bopt(bufnr, name)
  return vim.api.nvim_get_option_value(name, { buf = bufnr })
end

--- Replace `{token}` placeholders without interpreting `%` in the values.
--- @param template string
--- @param values table<string, string|number>
--- @return string
local function fill(template, values)
  return (
    template:gsub('{(%w+)}', function(key)
      local value = values[key]
      if value == nil then
        return ''
      end
      return tostring(value)
    end)
  )
end

--- Truncate to `limit` characters, keeping the beginning of the string.
--- @param text string
--- @param limit number|nil
--- @param marker string
--- @return string
local function truncate_end(text, limit, marker)
  limit = tonumber(limit)
  if not limit or limit <= 0 then
    return text
  end

  local chars = vim.fn.strchars(text)
  if chars <= limit then
    return text
  end

  local marker_chars = vim.fn.strchars(marker)
  local keep = math.max(1, limit - marker_chars)
  return vim.fn.strcharpart(text, 0, keep) .. marker
end

--- Truncate to `limit` characters, keeping the end of the string.
--- @param text string
--- @param limit number|nil
--- @param marker string
--- @return string
local function truncate_start(text, limit, marker)
  limit = tonumber(limit)
  if not limit or limit <= 0 then
    return text
  end

  local chars = vim.fn.strchars(text)
  if chars <= limit then
    return text
  end

  local marker_chars = vim.fn.strchars(marker)
  local keep = math.max(1, limit - marker_chars)
  return marker .. vim.fn.strcharpart(text, chars - keep, keep)
end

-- Raw mode strings returned by nvim_get_mode() -> highlight group suffix.
local mode_names = {
  n = 'Normal',
  no = 'Normal',
  nov = 'Normal',
  niI = 'Normal',
  niR = 'Normal',
  niV = 'Normal',
  i = 'Insert',
  ic = 'Insert',
  ix = 'Insert',
  v = 'Visual',
  V = 'VisualLine',
  ['\22'] = 'VisualBlock',
  R = 'Replace',
  r = 'Replace',
  Rc = 'Replace',
  Rv = 'Replace',
  Rx = 'Replace',
  c = 'Command',
  cv = 'Command',
  ce = 'Command',
  t = 'Terminal',
  s = 'Select',
  S = 'SelectLine',
  ['\19'] = 'SelectBlock',
  ['!'] = 'Shell',
}

--- Normalize a raw mode string into a highlight suffix.
--- @param raw string
--- @return string
function M.mode_name(raw)
  if mode_names[raw] then
    return mode_names[raw]
  end

  return mode_names[raw:sub(1, 1)] or 'Normal'
end

--- @param ctx table
--- @param opts table
--- @return table|nil
function M.mode(ctx, opts)
  local raw = ctx.mode.raw
  local labels = opts.labels or {}
  local label = labels[raw] or labels[raw:sub(1, 1)]

  if not label then
    label = raw ~= '' and raw:upper() or 'NORMAL'
  end

  if opts.uppercase then
    label = label:upper()
  end

  if opts.short then
    label = vim.fn.strcharpart(label, 0, 1)
  end

  if label == '' then
    return nil
  end

  return { text = label, hl = 'InklineMode' .. ctx.mode.name }
end

--- @param ctx table
--- @param opts table
--- @return table|nil
function M.filename(ctx, opts)
  local display
  local buftype = bopt(ctx.bufnr, 'buftype')

  if ctx.bufname == '' then
    display = opts.unnamed or '[No Name]'
  elseif buftype == 'terminal' then
    display = '[term]'
  elseif opts.basename then
    display = vim.fn.fnamemodify(ctx.bufname, ':t')
  elseif opts.full_path then
    display = vim.fn.fnamemodify(ctx.bufname, ':p')
  else
    display = vim.fn.fnamemodify(ctx.bufname, ':~:.')
  end

  local marker = ctx.config.icons.truncate
  display = truncate_start(display, opts.max_width, marker)

  local segments = {
    { text = display, hl = 'InklineFile' },
  }

  if bopt(ctx.bufnr, 'modified') and opts.modified ~= false then
    local icon = opts.modified or ctx.config.icons.modified
    segments[#segments + 1] = { text = ' ' .. icon, hl = 'InklineModified' }
  end

  if bopt(ctx.bufnr, 'readonly') and opts.readonly ~= false then
    local icon = opts.readonly or ctx.config.icons.readonly
    segments[#segments + 1] = { text = ' ' .. icon, hl = 'InklineReadonly' }
  end

  return segments
end

local severity_numbers = {
  ERROR = vim.diagnostic.severity.ERROR,
  WARN = vim.diagnostic.severity.WARN,
  INFO = vim.diagnostic.severity.INFO,
  HINT = vim.diagnostic.severity.HINT,
}

local severity_labels = {
  ERROR = 'Error',
  WARN = 'Warn',
  INFO = 'Info',
  HINT = 'Hint',
}

local severity_words = {
  ERROR = { 'error', 'errors' },
  WARN = { 'warning', 'warnings' },
  INFO = { 'info', 'info' },
  HINT = { 'hint', 'hints' },
}

--- @param list table
--- @return table<integer, string>
local function normalize_severities(list)
  local result = {}
  for _, value in ipairs(list or {}) do
    if type(value) == 'number' then
      for name, number in pairs(severity_numbers) do
        if number == value then
          result[#result + 1] = name
          break
        end
      end
    elseif type(value) == 'string' then
      local name = value:upper()
      if severity_numbers[name] then
        result[#result + 1] = name
      end
    end
  end
  return result
end

--- @param ctx table
--- @param opts table
--- @return table|nil
function M.diagnostics(ctx, opts)
  local diagnostics = vim.diagnostic.get(ctx.bufnr)
  if #diagnostics == 0 then
    return nil
  end

  local counts = { ERROR = 0, WARN = 0, INFO = 0, HINT = 0 }
  for _, diagnostic in ipairs(diagnostics) do
    for name, number in pairs(severity_numbers) do
      if diagnostic.severity == number then
        counts[name] = counts[name] + 1
        break
      end
    end
  end

  local icons = opts.icons or ctx.config.icons.diagnostics
  local style = opts.style or 'short'
  local separator = opts.separator or ' '
  local segments = {}

  for _, name in ipairs(normalize_severities(opts.severities)) do
    local count = counts[name]
    if count > 0 then
      if #segments > 0 then
        segments[#segments + 1] = { text = separator, hl = 'InklineSeparator' }
      end

      local icon = icons[name:lower()] or name:sub(1, 1)

      local text
      if style == 'long' then
        local words = severity_words[name]
        text = count .. ' ' .. (count == 1 and words[1] or words[2])
      elseif style == 'icons' then
        text = icon .. ' ' .. count
      else
        text = icon .. count
      end

      segments[#segments + 1] = {
        text = text,
        hl = 'InklineDiagnostics' .. severity_labels[name],
      }
    end
  end

  if #segments == 0 then
    return nil
  end

  return segments
end

--- @param ctx table
--- @param opts table
--- @return table|nil
function M.branch(ctx, opts)
  local branch

  if opts.gitsigns ~= false then
    local ok, head = pcall(function()
      return vim.b[ctx.bufnr].gitsigns_head
    end)
    if ok and type(head) == 'string' and head ~= '' then
      branch = head
    end
  end

  if not branch then
    -- Named buffers use their own project; unnamed buffers fall back to cwd.
    local root
    if ctx.bufname == '' then
      root = vim.fs.root(vim.fn.getcwd(), '.git')
    else
      root = vim.fs.root(ctx.bufnr, '.git')
    end

    if not root then
      return nil
    end
    branch = git.get_branch(root)
  end

  if not branch or branch == '' then
    return nil
  end

  branch = truncate_end(branch, opts.max_width, ctx.config.icons.truncate)

  local icon = opts.icon
  if icon == nil then
    icon = ctx.config.icons.branch
  end
  if icon ~= '' then
    branch = icon .. ' ' .. branch
  end

  return { text = branch, hl = 'InklineBranch' }
end

--- @param ctx table
--- @param opts table
--- @return table|nil
function M.filetype(ctx, opts)
  local filetype = bopt(ctx.bufnr, 'filetype')
  if filetype == '' then
    return nil
  end

  local icon
  local icon_hl
  if opts.devicons then
    local ok, devicons = pcall(require, 'nvim-web-devicons')
    if ok then
      icon, icon_hl = devicons.get_icon(filetype, nil, { default = true })
    end
  end

  if not icon then
    local icons = opts.icons or ctx.config.icons.filetypes
    icon = icons[filetype]
  end

  local segments = {}
  if icon and icon ~= '' then
    segments[#segments + 1] = { text = icon, hl = icon_hl or 'InklineFiletype' }
  end

  if opts.show_name ~= false or not icon then
    if #segments > 0 then
      segments[#segments + 1] = { text = ' ', hl = 'InklineSeparator' }
    end
    segments[#segments + 1] = { text = filetype, hl = 'InklineFiletype' }
  end

  if #segments == 0 then
    return nil
  end

  return segments
end

--- @param ctx table
--- @return integer, integer, integer
local function cursor_info(ctx)
  local line = 1
  local column = 1
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, ctx.winid)
  if ok then
    line = cursor[1]
    column = cursor[2] + 1
  end

  local line_count = math.max(1, vim.api.nvim_buf_line_count(ctx.bufnr))
  local percent = math.floor((line / line_count) * 100 + 0.5)
  percent = math.max(0, math.min(100, percent))

  return line, column, percent
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.location(ctx, opts)
  local line, column, percent = cursor_info(ctx)
  local format = opts.format or '{line}:{col}'
  local text

  if type(format) == 'function' then
    local ok, result = pcall(format, line, column, percent)
    if not ok or result == nil then
      return nil
    end
    text = tostring(result)
  else
    text = fill(format, { line = line, col = column, percent = percent })
  end

  if opts.show_percent then
    text = text .. fill(opts.percent_format or ' {percent}%', { percent = percent })
  end

  return text, 'InklineLocation'
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.progress(ctx, opts)
  local _, _, percent = cursor_info(ctx)
  return fill(opts.format or '{percent}%', { percent = percent }), 'InklineProgress'
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.lsp(ctx, opts)
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = ctx.bufnr })
  if not ok or not clients or #clients == 0 then
    return nil
  end

  local seen = {}
  local names = {}
  for _, client in ipairs(clients) do
    if client.name and not seen[client.name] then
      seen[client.name] = true
      names[#names + 1] = client.name
    end
  end

  if #names == 0 then
    return nil
  end

  local text = table.concat(names, opts.separator or ', ')
  return truncate_end(text, opts.max_width, ctx.config.icons.truncate), 'InklineLsp'
end

--- @param ctx table
--- @return string|nil, string|nil
function M.encoding(ctx)
  local encoding = bopt(ctx.bufnr, 'fileencoding')
  if encoding == '' then
    encoding = vim.o.encoding
  end
  return encoding, 'InklineDim'
end

--- @param ctx table
--- @return string|nil, string|nil
function M.fileformat(ctx)
  local fileformat = bopt(ctx.bufnr, 'fileformat')
  if fileformat == '' then
    return nil
  end
  return fileformat, 'InklineDim'
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.macro(ctx, opts)
  local register = vim.fn.reg_recording()
  if register == '' then
    return nil
  end

  return fill(opts.format or 'REC @{register}', { register = register }), 'InklineMacro'
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.searchcount(ctx, opts)
  if not ctx.is_active then
    return nil
  end

  local ok, count = pcall(vim.fn.searchcount, { maxcount = 99999 })
  if not ok or type(count) ~= 'table' or (count.total or 0) == 0 then
    return nil
  end

  return fill(opts.format or '[{current}/{total}]', {
    current = count.current or 0,
    total = count.total or 0,
  }), 'InklineSearch'
end

--- @param ctx table
--- @param opts table
--- @return string|nil, string|nil
function M.selection(ctx, opts)
  if not ctx.is_active or not ctx.mode.name:match('^Visual') then
    return nil
  end

  local ok, counts = pcall(vim.fn.wordcount)
  if not ok or type(counts) ~= 'table' then
    return nil
  end

  local lines = math.abs(vim.fn.line('v') - vim.fn.line('.')) + 1
  local chars = tonumber(counts.visual_chars) or 0
  local words = tonumber(counts.visual_words) or 0

  if chars == 0 and ctx.mode.raw ~= 'V' then
    return nil
  end

  return fill(opts.format or '{chars} chars', {
    chars = chars,
    words = words,
    lines = lines,
  }), 'InklineSelection'
end

--- @param ctx table
--- @param opts table
--- @return any
function M.custom(ctx, opts)
  local render = opts.render or opts.fn
  if type(render) ~= 'function' then
    return nil
  end
  return render(ctx, opts)
end

M.builtin = {
  mode = M.mode,
  filename = M.filename,
  diagnostics = M.diagnostics,
  branch = M.branch,
  filetype = M.filetype,
  location = M.location,
  progress = M.progress,
  lsp = M.lsp,
  encoding = M.encoding,
  fileformat = M.fileformat,
  macro = M.macro,
  searchcount = M.searchcount,
  selection = M.selection,
  custom = M.custom,
}

--- Look up a built-in component by name.
--- @param name string
--- @return function|nil
function M.get(name)
  return M.builtin[name]
end

return M
