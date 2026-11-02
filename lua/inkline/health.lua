-- :checkhealth inkline

local M = {}

--- @return table
local function inkline()
  return require('inkline')
end

function M.check()
  local health = vim.health

  health.start('inkline.nvim')

  if vim.fn.has('nvim-0.10') == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('inkline.nvim requires Neovim 0.10 or newer')
  end

  local ok, instance = pcall(inkline)
  if not ok then
    health.error('could not load inkline: ' .. tostring(instance))
    return
  end

  if instance.is_setup() then
    health.ok('setup() has been called')
  else
    health.warn('setup() has not run yet (the plugin normally calls it automatically)')
  end

  if vim.o.statusline:find('inkline', 1, true) then
    health.ok("'statusline' is handled by inkline")
  else
    health.warn("'statusline' does not reference inkline; run :InklineRedraw or call require('inkline').setup()")
  end

  local highlight = vim.api.nvim_get_hl(0, { name = 'Inkline' })
  if highlight and (highlight.fg or highlight.bg or highlight.link) then
    health.ok('highlight groups are defined')
  else
    health.warn('highlight group "Inkline" is not defined; call setup()')
  end

  if vim.fn.executable('git') == 1 then
    health.ok('git executable found (used by the branch component)')
  else
    health.warn('git is not executable; the branch component will stay hidden')
  end

  if vim.fn.exists('g:loaded_gitsigns') == 1 or package.loaded['gitsigns'] then
    health.ok('gitsigns detected; the branch component can use its cached branch')
  else
    health.info('gitsigns not detected; branch falls back to a cached `git symbolic-ref` call')
  end

  local cfg = instance.get_config()
  local sections = {}
  for _, name in ipairs({ 'left', 'center', 'right' }) do
    sections[#sections + 1] = ('%s=%d'):format(name, #(cfg.sections[name] or {}))
  end
  health.info('sections: ' .. table.concat(sections, ', '))
  health.info('transparent: ' .. tostring(cfg.transparent))
end

return M
