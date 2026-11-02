-- Highlight groups for inkline.nvim.
--
-- The default palette is derived from the active colorscheme instead of using
-- hardcoded colors, so the statusline adapts to any theme. The only visual
-- "theme" is minimal: muted foregrounds, a transparent background by default,
-- and bold mode names.

local M = {}

--- Convert a numeric highlight color to a hex string.
--- @param value any
--- @return any
local function to_color(value)
  if type(value) == 'number' then
    return string.format('#%06x', value)
  end
  return value
end

--- Read highlight attributes, following links.
--- @param name string
--- @return table
local function attrs(name)
  local seen = {}
  local current = name

  while current and not seen[current] do
    seen[current] = true
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = current })
    if not ok or not hl then
      break
    end

    if hl.fg or hl.bg then
      hl.fg = to_color(hl.fg)
      hl.bg = to_color(hl.bg)
      return hl
    end

    current = hl.link
  end

  return {}
end

--- Get the foreground of a highlight group.
--- @param name string
--- @return string|nil
local function fg(name)
  return attrs(name).fg
end

--- Merge user overrides into a group definition and set it.
--- @param name string
--- @param definition table
--- @param overrides table
local function set(name, definition, overrides)
  local override = overrides and overrides[name]

  if override == false then
    return
  end

  if type(override) == 'string' then
    vim.api.nvim_set_hl(0, name, { link = override })
    return
  end

  if type(override) == 'table' then
    if override.link then
      vim.api.nvim_set_hl(0, name, { link = override.link })
      return
    end
    definition = vim.tbl_extend('force', definition, override)
  end

  vim.api.nvim_set_hl(0, name, definition)
end

--- Compute and apply all highlight groups.
--- @param cfg table
function M.apply(cfg)
  local normal = attrs('Normal')
  local statusline = attrs('StatusLine')
  local statusline_nc = attrs('StatusLineNC')
  local comment = attrs('Comment')

  local base_fg = statusline.fg or normal.fg
  local base_bg
  if cfg.transparent then
    base_bg = 'NONE'
  else
    base_bg = statusline.bg or normal.bg
  end

  local function group(extra)
    local definition = { fg = base_fg, bg = base_bg }
    for key, value in pairs(extra or {}) do
      definition[key] = value
    end
    return definition
  end

  --- @param name string
  --- @param fallback string|nil
  --- @return string|nil
  local function diagnostic(name, fallback)
    return fg('Diagnostic' .. name) or (fallback and fg(fallback)) or base_fg
  end

  local overrides = cfg.highlights or {}

  set('Inkline', group(), overrides)

  local function dim(extra)
    return group(vim.tbl_extend('force', { fg = comment.fg or base_fg }, extra or {}))
  end

  set('InklineInactive', group({
    fg = statusline_nc.fg or comment.fg or base_fg,
    bg = cfg.transparent and 'NONE' or (statusline_nc.bg or base_bg),
  }), overrides)

  set('InklineDim', dim(), overrides)
  set('InklineFile', group({ fg = normal.fg or base_fg }), overrides)
  set('InklineModified', group({ fg = diagnostic('Warn', 'WarningMsg') }), overrides)
  set('InklineReadonly', dim(), overrides)
  set('InklineSeparator', dim({ fg = fg('NonText') or comment.fg or base_fg }), overrides)
  set('InklineBranch', group({ fg = fg('Special') or diagnostic('Info') }), overrides)
  set('InklineLocation', dim(), overrides)
  set('InklineProgress', dim(), overrides)
  set('InklineFiletype', dim(), overrides)
  set('InklineSearch', dim(), overrides)
  set('InklineSelection', dim(), overrides)
  set('InklineLsp', group({ fg = diagnostic('Info') }), overrides)
  set('InklineMacro', group({ fg = diagnostic('Error', 'ErrorMsg'), bold = true }), overrides)

  set('InklineDiagnosticsError', group({ fg = diagnostic('Error', 'ErrorMsg') }), overrides)
  set('InklineDiagnosticsWarn', group({ fg = diagnostic('Warn', 'WarningMsg') }), overrides)
  set('InklineDiagnosticsInfo', group({ fg = diagnostic('Info', 'MoreMsg') }), overrides)
  set('InklineDiagnosticsHint', group({ fg = diagnostic('Hint', 'Comment') }), overrides)

  -- Base mode group, used as a fallback for custom mode names.
  set('InklineMode', group({ bold = true }), overrides)

  local mode_colors = {
    Normal = base_fg,
    Insert = diagnostic('Ok', 'String'),
    Visual = diagnostic('Warn', 'WarningMsg'),
    VisualLine = diagnostic('Warn', 'WarningMsg'),
    VisualBlock = diagnostic('Warn', 'WarningMsg'),
    Replace = diagnostic('Error', 'ErrorMsg'),
    Command = fg('Special'),
    Terminal = diagnostic('Info', 'MoreMsg'),
    Select = fg('Statement'),
    SelectLine = fg('Statement'),
    SelectBlock = fg('Statement'),
    Shell = fg('Special'),
  }

  for name, color in pairs(mode_colors) do
    set('InklineMode' .. name, group({ fg = color or base_fg, bold = true }), overrides)
  end
end

return M
