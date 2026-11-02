-- Load guard and zero-config startup for inkline.nvim.

if vim.g.loaded_inkline then
  return
end
vim.g.loaded_inkline = 1

if vim.fn.has('nvim-0.10') == 0 then
  vim.notify('inkline.nvim requires Neovim 0.10 or newer', vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command('InklineRedraw', function()
  require('inkline').redraw_now()
end, { desc = 'Redraw the inkline statusline' })

-- Defer setup so a user's explicit setup() call (often from lazy.nvim's opts)
-- runs first. Setup is idempotent either way.
vim.schedule(function()
  local ok, inkline = pcall(require, 'inkline')
  if ok and not inkline.is_setup() then
    inkline.setup()
  end
end)
