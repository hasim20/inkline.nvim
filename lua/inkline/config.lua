-- Configuration defaults and merging for inkline.nvim.
--
-- Lists (such as `sections.left`) are replaced wholesale, while maps (such as
-- `mode.labels`) are merged. This keeps user configuration predictable.

local M = {}

local defaults = {
  -- Blend into the editor instead of painting a statusline background.
  transparent = true,

  -- Show component errors as notifications instead of silently hiding them.
  debug = false,

  icons = {
    modified = '[+]',
    readonly = '[RO]',
    branch = '',
    truncate = '...',
    diagnostics = {
      error = 'E',
      warn = 'W',
      info = 'I',
      hint = 'H',
    },
    -- Optional per-filetype icons, e.g. { lua = 'L', python = 'P' }.
    filetypes = {},
  },

  sections = {
    left = { 'mode', 'filename' },
    center = {},
    right = { 'diagnostics', 'branch', 'location' },
  },

  -- Text between components in the same section.
  separator = '  ',

  -- Spaces at the outer edges of the statusline.
  padding = { left = 1, right = 1 },

  mode = {
    -- Keys are the raw values returned by nvim_get_mode().
    labels = {
      n = 'NORMAL',
      i = 'INSERT',
      v = 'VISUAL',
      V = 'V-LINE',
      ['\22'] = 'V-BLOCK',
      R = 'REPLACE',
      r = 'REPLACE',
      c = 'COMMAND',
      t = 'TERMINAL',
      s = 'SELECT',
      S = 'S-LINE',
      ['\19'] = 'S-BLOCK',
      ['!'] = 'SHELL',
    },
    uppercase = true,
    -- Show only the first character of the label.
    short = false,
  },

  filename = {
    max_width = 60,
    full_path = false,
    basename = false,
    unnamed = '[No Name]',
    -- Override the global icons when set.
    modified = nil,
    readonly = nil,
  },

  diagnostics = {
    -- Severity names or numbers. Order is preserved when rendering.
    severities = { 'ERROR', 'WARN', 'INFO', 'HINT' },
    -- "short" (E1 W2), "long" (1 error, 2 warnings), or "icons" (1 2).
    style = 'short',
    separator = ' ',
    icons = nil,
  },

  branch = {
    max_width = 32,
    icon = nil,
    -- Read the branch from gitsigns when it is available.
    gitsigns = true,
  },

  filetype = {
    devicons = false,
    icons = nil,
    show_name = true,
    max_width = 24,
  },

  location = {
    -- Tokens: {line}, {col}, {percent}
    format = '{line}:{col}',
    show_percent = false,
    percent_format = ' {percent}%',
  },

  progress = {
    format = '{percent}%',
  },

  lsp = {
    max_width = 40,
    separator = ', ',
  },

  macro = {
    format = 'REC @{register}',
  },

  searchcount = {
    format = '[{current}/{total}]',
  },

  selection = {
    format = '{chars} chars',
  },

  disabled = {
    filetypes = {},
    buftypes = { 'prompt' },
  },

  inactive = {
    dim = true,
    highlight = 'InklineInactive',
  },

  refresh = {
    debounce = 60,
    events = {
      'ModeChanged',
      'BufEnter',
      'BufLeave',
      'BufWritePost',
      'FileType',
      'DirChanged',
      'WinEnter',
      'WinLeave',
      'WinResized',
      'VimResized',
      'DiagnosticChanged',
      'LspProgress',
      'CursorMoved',
      'CursorMovedI',
      'User',
    },
  },

  -- Highlight overrides, merged over the generated defaults.
  -- Example: { InklineBranch = { fg = '#7aa2f7' } }
  highlights = {},

  -- Replace built-in components:
  -- Example: { mode = function(ctx, opts) return 'x', 'InklineDim' end }
  components = {},

  -- Global visibility condition: function(ctx) -> boolean
  condition = nil,
}

local current = vim.deepcopy(defaults)

--- Return a fresh copy of the built-in defaults.
--- @return table
function M.defaults()
  return vim.deepcopy(defaults)
end

--- Return the active configuration.
--- @return table
function M.get()
  return current
end

--- Replace the active configuration.
--- @param cfg table
function M.set(cfg)
  current = cfg
end

--- Restore the built-in defaults.
function M.reset()
  current = vim.deepcopy(defaults)
end

--- True when a table only has consecutive integer keys starting at 1.
--- @param value any
--- @return boolean
local function is_list(value)
  if type(value) ~= 'table' then
    return false
  end

  local count = 0
  for key in pairs(value) do
    if type(key) ~= 'number' then
      return false
    end
    count = count + 1
  end

  return count == #value
end

--- Merge `override` into `base`, replacing lists instead of concatenating them.
--- @param base any
--- @param override any
--- @return any
local function merge(base, override)
  if type(base) ~= 'table' or type(override) ~= 'table' then
    return vim.deepcopy(override)
  end

  if is_list(override) then
    -- An empty options table (`setup({})`) is not meant to erase the defaults.
    -- An empty list nested in a known list (such as `sections.left = {}`) is.
    if #override == 0 and not is_list(base) then
      return vim.deepcopy(base)
    end
    return vim.deepcopy(override)
  end

  local result = vim.deepcopy(base)
  for key, value in pairs(override) do
    if type(value) == 'table' and type(result[key]) == 'table' and not is_list(value) then
      result[key] = merge(result[key], value)
    else
      result[key] = vim.deepcopy(value)
    end
  end

  return result
end

--- Turn a single item into a list without mutating it.
--- @param value any
--- @return table
local function ensure_list(value)
  if value == nil then
    return {}
  end
  if type(value) == 'table' then
    return value
  end
  return { value }
end

--- Validate and normalize a merged configuration in place.
--- @param cfg table
local function normalize(cfg)
  if type(cfg.sections) ~= 'table' then
    error('inkline: `sections` must be a table')
  end

  for _, name in ipairs({ 'left', 'center', 'right' }) do
    cfg.sections[name] = ensure_list(cfg.sections[name])
  end

  if type(cfg.separator) ~= 'string' then
    error('inkline: `separator` must be a string')
  end

  if type(cfg.padding) ~= 'table' then
    error('inkline: `padding` must be a table')
  end
  cfg.padding.left = tonumber(cfg.padding.left) or 0
  cfg.padding.right = tonumber(cfg.padding.right) or 0

  if type(cfg.refresh) ~= 'table' then
    error('inkline: `refresh` must be a table')
  end
  cfg.refresh.events = ensure_list(cfg.refresh.events)
  cfg.refresh.debounce = math.max(0, tonumber(cfg.refresh.debounce) or 60)

  if cfg.disabled ~= nil then
    if type(cfg.disabled) ~= 'table' then
      error('inkline: `disabled` must be a table')
    end
    cfg.disabled.filetypes = ensure_list(cfg.disabled.filetypes)
    cfg.disabled.buftypes = ensure_list(cfg.disabled.buftypes)
  end

  if cfg.components ~= nil and type(cfg.components) ~= 'table' then
    error('inkline: `components` must be a table')
  end

  if cfg.highlights ~= nil and type(cfg.highlights) ~= 'table' then
    error('inkline: `highlights` must be a table')
  end

  if cfg.condition ~= nil and type(cfg.condition) ~= 'function' then
    error('inkline: `condition` must be a function')
  end
end

--- Build a complete configuration from user options.
--- @param options table|nil
--- @return table
function M.build(options)
  if options ~= nil and type(options) ~= 'table' then
    error('inkline: setup() expects a table or nil')
  end

  local cfg = merge(defaults, options or {})
  normalize(cfg)
  return cfg
end

return M
