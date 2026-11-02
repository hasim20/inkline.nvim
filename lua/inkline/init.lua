-- inkline.nvim: a quiet, fully configurable statusline for Neovim.

local components = require('inkline.components')
local config = require('inkline.config')
local git = require('inkline.git')
local highlights = require('inkline.highlights')
local render = require('inkline.render')

local uv = vim.uv or vim.loop

local M = {}

local setup_done = false
local timer

--- The statusline expression installed by setup().
local STATUSLINE = "%{%v:lua.require'inkline'.eval()%}"

--- Build the render context for the window currently being drawn.
--- @param cfg table
--- @return table
local function build_context(cfg)
  local winid = tonumber(vim.g.statusline_winid)

  if not winid or not vim.api.nvim_win_is_valid(winid) then
    winid = vim.api.nvim_get_current_win()
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local raw_mode = vim.api.nvim_get_mode().mode

  -- While evaluating %{% ... %}, Neovim temporarily makes the target window
  -- current and exposes the "real" current window as g:actual_curwin.
  local actual_winid = tonumber(vim.g.actual_curwin)
  if not actual_winid then
    actual_winid = vim.api.nvim_get_current_win()
  end

  local ok, width = pcall(vim.api.nvim_win_get_width, winid)

  return {
    bufnr = bufnr,
    winid = winid,
    bufname = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr }),
    buftype = vim.api.nvim_get_option_value('buftype', { buf = bufnr }),
    is_active = winid == actual_winid,
    mode = {
      raw = raw_mode,
      name = components.mode_name(raw_mode),
    },
    width = ok and width or 0,
    config = cfg,
  }
end

--- Evaluate the statusline for the window being drawn.
--- @return string
function M.eval()
  local cfg = config.get()

  local ok, ctx = pcall(build_context, cfg)
  if not ok then
    return ''
  end

  return render.render(ctx, cfg)
end

--- Request a debounced redraw.
function M.redraw()
  local debounce = config.get().refresh.debounce or 60

  if not timer then
    timer = uv.new_timer()
  end

  if not timer then
    M.redraw_now()
    return
  end

  timer:stop()
  timer:start(debounce, 0, vim.schedule_wrap(function()
    M.redraw_now()
  end))
end

--- Redraw immediately.
function M.redraw_now()
  pcall(vim.cmd, 'redrawstatus!')
end

--- Install the statusline expression.
function M.apply_statusline()
  vim.o.statusline = STATUSLINE
end

--- @return boolean
function M.is_setup()
  return setup_done
end

--- @return table
function M.get_config()
  return config.get()
end

--- Configure inkline.nvim. Can be called again to change the configuration.
--- @param options table|nil
--- @return table
function M.setup(options)
  local cfg = config.build(options or {})

  render.validate(cfg)
  render.reset_warnings()

  config.set(cfg)
  highlights.apply(cfg)
  M.apply_statusline()

  git.on_update = M.redraw

  local group = vim.api.nvim_create_augroup('Inkline', { clear = true })

  if #cfg.refresh.events > 0 then
    vim.api.nvim_create_autocmd(cfg.refresh.events, {
      group = group,
      callback = M.redraw,
      desc = 'inkline: refresh statusline',
    })
  end

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      highlights.apply(config.get())
      M.redraw()
    end,
    desc = 'inkline: reapply highlights',
  })

  setup_done = true
  return M
end

return M
