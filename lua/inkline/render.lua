-- Statusline rendering.
--
-- The renderer turns component output into a statusline string. All user text
-- is escaped so that `%` in file names cannot break the statusline format.

local components = require('inkline.components')

local M = {}

local warned = {}

--- Reset the "already warned" table. Called by setup().
function M.reset_warnings()
  warned = {}
end

--- True when a table is a list (only consecutive numeric keys).
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

--- Merge per-item options over component defaults, replacing lists.
--- @param base table
--- @param override table
--- @return table
local function merge_options(base, override)
  local result = vim.deepcopy(base or {})
  for key, value in pairs(override or {}) do
    if type(value) == 'table' and type(result[key]) == 'table' and not is_list(value) then
      result[key] = merge_options(result[key], value)
    else
      result[key] = vim.deepcopy(value)
    end
  end
  return result
end

--- Escape text for use inside a statusline.
--- @param text any
--- @return string
local function escape(text)
  text = tostring(text)
  text = text:gsub('%c', ' ')
  return (text:gsub('%%', '%%%%'))
end

--- Notify about a broken component once per component name.
--- @param cfg table
--- @param label string
--- @param message string
local function report(cfg, label, message)
  if not cfg.debug or warned[label] then
    return
  end
  warned[label] = true

  vim.schedule(function()
    vim.notify(('inkline: component %q failed: %s'):format(label, message), vim.log.levels.WARN)
  end)
end

--- Extract a component name from a section item, if it has one.
--- @param item any
--- @return string|nil
local function item_name(item)
  if type(item) == 'string' then
    return item
  end
  if type(item) ~= 'table' then
    return nil
  end
  if type(item[1]) == 'string' then
    return item[1]
  end
  if type(item.name) == 'string' then
    return item.name
  end
  return nil
end

--- Resolve a section item into a render function and its options.
--- @param item any
--- @param cfg table
--- @return function|nil, table, string
local function resolve(item, cfg)
  local render_fn
  local opts
  local name

  if type(item) == 'function' then
    render_fn = item
    opts = {}
  elseif type(item) == 'string' then
    name = item
    opts = {}
  elseif type(item) == 'table' then
    if type(item[1]) == 'function' then
      render_fn = item[1]
      opts = item
    elseif type(item[1]) == 'string' then
      name = item[1]
      opts = item
    elseif type(item.render) == 'function' then
      render_fn = item.render
      opts = item
    elseif type(item.name) == 'string' then
      name = item.name
      opts = item
    else
      error('inkline: invalid section item (expected a name or function)')
    end
  else
    error('inkline: invalid section item (expected a name or function)')
  end

  if name then
    local override = cfg.components and cfg.components[name]
    if type(override) == 'function' then
      render_fn = override
    elseif override ~= nil then
      error(('inkline: component %q must be a function'):format(name))
    else
      render_fn = components.get(name)
      if not render_fn then
        error(('inkline: unknown component %q'):format(name))
      end
    end
  end

  local defaults = name and type(cfg[name]) == 'table' and cfg[name] or {}
  local merged = merge_options(defaults, opts or {})
  return render_fn, merged, name or 'inline'
end

--- Validate component names without rendering.
--- @param cfg table
function M.validate(cfg)
  for _, section in ipairs({ 'left', 'center', 'right' }) do
    for _, item in ipairs(cfg.sections[section] or {}) do
      local name = item_name(item)
      if name then
        local override = cfg.components and cfg.components[name]
        if override ~= nil and type(override) ~= 'function' then
          error(('inkline: component %q must be a function'):format(name))
        end
        if override == nil and not components.get(name) then
          error(('inkline: unknown component %q in sections.%s'):format(name, section))
        end
      end
    end
  end
end

--- Normalize a component result into a list of segments.
--- @param result any
--- @param extra_hl string|nil
--- @param fallback_hl string
--- @return table
local function normalize(result, extra_hl, fallback_hl)
  if result == nil or result == false then
    return {}
  end

  if type(result) == 'string' or type(result) == 'number' then
    return { { text = tostring(result), hl = extra_hl or fallback_hl } }
  end

  if type(result) ~= 'table' then
    return {}
  end

  if result.text ~= nil then
    return {
      {
        text = tostring(result.text),
        hl = result.hl or extra_hl or fallback_hl,
      },
    }
  end

  local segments = {}
  for _, segment in ipairs(result) do
    if type(segment) == 'string' or type(segment) == 'number' then
      segments[#segments + 1] = { text = tostring(segment), hl = extra_hl or fallback_hl }
    elseif type(segment) == 'table' then
      if segment.text ~= nil then
        segments[#segments + 1] = {
          text = tostring(segment.text),
          hl = segment.hl or extra_hl or fallback_hl,
        }
      elseif type(segment[1]) == 'string' or type(segment[1]) == 'number' then
        segments[#segments + 1] = {
          text = tostring(segment[1]),
          hl = segment[2] or extra_hl or fallback_hl,
        }
      end
    end
  end

  return segments
end

--- Render one component.
--- @param item any
--- @param ctx table
--- @param cfg table
--- @return table
local function render_item(item, ctx, cfg)
  local ok, render_fn, opts, label = pcall(resolve, item, cfg)
  if not ok or not render_fn then
    report(cfg, 'resolve', tostring(render_fn))
    return {}
  end

  if type(opts.cond) == 'function' then
    local cond_ok, visible = pcall(opts.cond, ctx)
    if not cond_ok then
      report(cfg, label .. ':cond', tostring(visible))
      return {}
    end
    if not visible then
      return {}
    end
  end

  local call_ok, result, extra_hl = pcall(render_fn, ctx, opts)
  if not call_ok then
    report(cfg, label, tostring(result))
    return {}
  end

  local segments = normalize(result, extra_hl, opts.hl or 'Inkline')
  local nonempty = {}
  for _, segment in ipairs(segments) do
    if tostring(segment.text) ~= '' then
      nonempty[#nonempty + 1] = segment
    end
  end
  return nonempty
end

--- Render one section, joining non-empty components with the separator.
--- @param items table
--- @param ctx table
--- @param cfg table
--- @return table
local function render_section(items, ctx, cfg)
  local groups = {}

  for _, item in ipairs(items or {}) do
    local segments = render_item(item, ctx, cfg)
    if #segments > 0 then
      groups[#groups + 1] = segments
    end
  end

  if #groups == 0 then
    return {}
  end

  local result = {}
  for index, segments in ipairs(groups) do
    if index > 1 and cfg.separator ~= '' then
      result[#result + 1] = { text = cfg.separator, hl = 'InklineSeparator' }
    end
    for _, segment in ipairs(segments) do
      result[#result + 1] = segment
    end
  end

  return result
end

--- True when the current buffer should not have a statusline.
--- @param ctx table
--- @param cfg table
--- @return boolean
local function is_disabled(ctx, cfg)
  local disabled = cfg.disabled
  if not disabled then
    return false
  end

  for _, filetype in ipairs(disabled.filetypes or {}) do
    if filetype == ctx.filetype then
      return true
    end
  end

  for _, buftype in ipairs(disabled.buftypes or {}) do
    if buftype == ctx.buftype then
      return true
    end
  end

  return false
end

--- Turn segments into a statusline string.
--- @param segments table
--- @return string
local function draw(segments)
  local parts = {}

  for _, segment in ipairs(segments) do
    if segment.raw then
      parts[#parts + 1] = segment.text
    else
      local text = escape(segment.text)
      if text ~= '' then
        local hl = segment.hl
        if type(hl) == 'string' and hl ~= '' and not hl:find('[%%#]') then
          parts[#parts + 1] = '%#' .. hl .. '#' .. text .. '%*'
        else
          parts[#parts + 1] = text
        end
      end
    end
  end

  return table.concat(parts)
end

--- @param ctx table
--- @param cfg table
--- @return string
local function render(ctx, cfg)
  if is_disabled(ctx, cfg) then
    return ''
  end

  if type(cfg.condition) == 'function' then
    local ok, visible = pcall(cfg.condition, ctx)
    if not ok then
      report(cfg, 'condition', tostring(visible))
    elseif not visible then
      return ''
    end
  end

  local left = render_section(cfg.sections.left, ctx, cfg)
  local center = render_section(cfg.sections.center, ctx, cfg)
  local right = render_section(cfg.sections.right, ctx, cfg)

  local segments = {}
  if cfg.padding.left > 0 then
    segments[#segments + 1] = { text = string.rep(' ', cfg.padding.left) }
  end

  local function append(list)
    for _, segment in ipairs(list) do
      segments[#segments + 1] = segment
    end
  end

  append(left)

  if #center > 0 then
    segments[#segments + 1] = { text = '%=', raw = true }
    append(center)
    segments[#segments + 1] = { text = '%=', raw = true }
  elseif #right > 0 then
    segments[#segments + 1] = { text = '%=', raw = true }
  end

  append(right)

  if cfg.padding.right > 0 then
    segments[#segments + 1] = { text = string.rep(' ', cfg.padding.right) }
  end

  if not ctx.is_active and cfg.inactive and cfg.inactive.dim ~= false then
    local normal_hl = cfg.inactive.highlight or 'InklineInactive'
    for _, segment in ipairs(segments) do
      if segment.text ~= '%=' then
        segment.hl = normal_hl
      end
    end
  end

  return draw(segments)
end

--- Render a statusline string for a context.
--- @param ctx table
--- @param cfg table
--- @return string
function M.render(ctx, cfg)
  local ok, result = pcall(render, ctx, cfg)
  if not ok then
    report(cfg, 'render', tostring(result))
    return ''
  end
  return result
end

return M
