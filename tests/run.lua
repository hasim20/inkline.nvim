-- Dependency-free test runner.
--
--   nvim --headless -u NONE -l tests/run.lua

local script = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(script, ':p:h:h')
vim.opt.rtp:prepend(root)
vim.o.laststatus = 2

local inkline = require('inkline')
local config = require('inkline.config')
local git = require('inkline.git')

local failures = 0
local total = 0

--- @param name string
--- @param fn function
local function test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    io.write('ok   ' .. name .. '\n')
  else
    failures = failures + 1
    io.write('FAIL ' .. name .. '\n')
    io.write('     ' .. tostring(err):gsub('\n', '\n     ') .. '\n')
  end
end

--- @param condition any
--- @param message string
local function check(condition, message)
  if not condition then
    error(message, 2)
  end
end

--- @param actual any
--- @param expected any
--- @param message string|nil
local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or 'values differ') .. (': expected %q, got %q'):format(tostring(expected), tostring(actual)), 2)
  end
end

--- @param haystack string
--- @param needle string
--- @param message string|nil
local function contains(haystack, needle, message)
  if not haystack:find(needle, 1, true) then
    error((message or 'missing text') .. (': %q not found in %q'):format(needle, haystack), 2)
  end
end

--- @param haystack string
--- @param needle string
--- @param message string|nil
local function not_contains(haystack, needle, message)
  if haystack:find(needle, 1, true) then
    error((message or 'unexpected text') .. (': %q found in %q'):format(needle, haystack), 2)
  end
end

local tmp = vim.fn.fnamemodify(vim.fn.tempname(), ':p')
vim.fn.mkdir(tmp, 'p')

--- Replace the current buffer with a clean one.
--- @param name string|nil
--- @param filetype string|nil
--- @return integer
local function fresh_buffer(name, filetype)
  vim.cmd('enew!')
  vim.bo.buftype = ''
  vim.bo.filetype = filetype or ''
  vim.bo.modified = false
  vim.bo.readonly = false

  if name then
    vim.api.nvim_buf_set_name(0, name)
  end

  return vim.api.nvim_get_current_buf()
end

test('default layout renders mode, filename, and location', function()
  fresh_buffer(tmp .. '/demo.lua', 'lua')
  inkline.setup()

  local line = inkline.eval()
  contains(line, 'NORMAL')
  contains(line, 'demo.lua')
  check(vim.o.statusline:find('inkline', 1, true) ~= nil, 'statusline option was not installed')
  check(line:find('%#InklineModeNormal#', 1, true) ~= nil, 'mode highlight missing')
end)

test('installed statusline expression expands', function()
  fresh_buffer(tmp .. '/installed.lua', 'lua')
  inkline.setup()

  local result = vim.api.nvim_eval_statusline(vim.o.statusline, {
    winid = vim.api.nvim_get_current_win(),
  })

  contains(result.str, 'NORMAL')
  contains(result.str, 'installed.lua')
  check(result.width > 0, 'statusline should have a width')
end)

test('modified and readonly markers are shown', function()
  fresh_buffer(tmp .. '/markers.lua', 'lua')
  inkline.setup()
  vim.bo.modified = true
  vim.bo.readonly = true

  local line = inkline.eval()
  contains(line, '[+]')
  contains(line, '[RO]')

  vim.bo.modified = false
  vim.bo.readonly = false
end)

test('percent signs in file names are escaped', function()
  fresh_buffer(tmp .. '/100%.lua', 'lua')
  inkline.setup()

  local line = inkline.eval()
  contains(line, '100%%')

  local result = vim.api.nvim_eval_statusline(vim.o.statusline, {
    winid = vim.api.nvim_get_current_win(),
  })
  contains(result.str, '100%')
end)

test('filename truncation keeps the tail and adds a marker', function()
  fresh_buffer(tmp .. '/a-very-long-file-name-for-truncation.lua', 'lua')
  inkline.setup({ filename = { max_width = 12 } })

  local line = inkline.eval()
  contains(line, '...')
  not_contains(line, 'a-very-long-file-name-for-truncation.lua')
end)

test('diagnostics render counts and hide at zero', function()
  local bufnr = fresh_buffer(tmp .. '/diagnostics.lua', 'lua')
  inkline.setup()

  local namespace = vim.api.nvim_create_namespace('inkline-test')
  vim.diagnostic.set(namespace, bufnr, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' },
    { lnum = 1, col = 0, severity = vim.diagnostic.severity.WARN, message = 'meh' },
    { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN, message = 'meh' },
  })

  local line = inkline.eval()
  contains(line, 'E1')
  contains(line, 'W2')

  vim.diagnostic.reset(namespace, bufnr)
  not_contains(inkline.eval(), 'E1')
end)

test('component conditions can hide items', function()
  fresh_buffer(tmp .. '/conditions.lua', 'lua')
  inkline.setup({
    sections = {
      left = {
        'filename',
        {
          function()
            return 'HIDDEN'
          end,
          cond = function()
            return false
          end,
        },
      },
    },
  })

  not_contains(inkline.eval(), 'HIDDEN')
end)

test('inline components support a second highlight return value', function()
  fresh_buffer(tmp .. '/inline.lua', 'lua')
  inkline.setup({
    sections = {
      left = {
        function()
          return 'hello', 'InklineDim'
        end,
      },
    },
  })

  contains(inkline.eval(), '%#InklineDim#hello%*')
end)

test('unknown components fail at setup time', function()
  local ok, err = pcall(inkline.setup, { sections = { left = { 'not-a-component' } } })
  check(not ok, 'setup should reject unknown component names')
  check(tostring(err):find('unknown component', 1, true) ~= nil, 'error should name the unknown component')

  inkline.setup()
end)

test('disabled filetypes produce an empty statusline', function()
  fresh_buffer(tmp .. '/disabled.md', 'markdown')
  inkline.setup({ disabled = { filetypes = { 'markdown' } } })

  equal(inkline.eval(), '')
end)

test('gitsigns branch variables take precedence over git', function()
  local bufnr = fresh_buffer(tmp .. '/gitsigns.lua', 'lua')
  inkline.setup({
    sections = { left = { 'branch' }, right = {} },
  })

  vim.b[bufnr].gitsigns_head = 'feature/branch'
  contains(inkline.eval(), 'feature/branch')
end)

test('git fallback resolves the branch asynchronously and caches it', function()
  if vim.fn.executable('git') ~= 1 then
    io.write('     skipped: git is not installed\n')
    return
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local init = vim.system({ 'git', 'init', '-q', '-b', 'trunk', dir }):wait(5000)
  equal(init.code, 0, 'git init failed')

  local file = dir .. '/file.txt'
  vim.fn.writefile({ 'hello' }, file)
  fresh_buffer(file, 'text')

  git.clear()
  inkline.setup({
    sections = { left = { 'branch' }, right = {} },
    branch = { gitsigns = false },
  })

  vim.wait(5000, function()
    return git.get_branch(dir) == 'trunk'
  end, 25)

  contains(inkline.eval(), 'trunk')
end)

test('location uses the window cursor', function()
  fresh_buffer(tmp .. '/location.lua', 'lua')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three', 'four' })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  inkline.setup()

  contains(inkline.eval(), '3:5')
end)

test('inactive windows use the inactive highlight', function()
  fresh_buffer(tmp .. '/inactive.lua', 'lua')
  inkline.setup()

  local active = vim.api.nvim_get_current_win()
  vim.cmd('split')
  local other = vim.api.nvim_get_current_win()

  vim.g.statusline_winid = active
  vim.g.actual_curwin = other

  local line = inkline.eval()
  contains(line, '%#InklineInactive#')

  vim.g.statusline_winid = nil
  vim.g.actual_curwin = nil
  vim.cmd('close')
  vim.api.nvim_set_current_win(active)
end)

test('config replaces lists but merges maps', function()
  local cfg = config.build({
    sections = { left = { 'filename' } },
    mode = { labels = { n = 'N' } },
  })

  equal(#cfg.sections.left, 1)
  equal(cfg.sections.left[1], 'filename')
  equal(cfg.mode.labels.n, 'N')
  equal(cfg.mode.labels.i, 'INSERT')
  equal(cfg.filename.max_width, 60)
end)

test('highlight groups are generated and transparent by default', function()
  inkline.setup()

  local base = vim.api.nvim_get_hl(0, { name = 'Inkline' })
  check(base.fg ~= nil, 'Inkline should have a foreground')
  check(base.bg == nil, 'Inkline should be transparent by default')

  local mode = vim.api.nvim_get_hl(0, { name = 'InklineModeNormal' })
  check(mode.bold == true, 'mode highlight should be bold')
end)

test('highlight overrides are applied', function()
  inkline.setup({
    highlights = {
      InklineBranch = { link = 'Special' },
      InklineFile = false,
    },
  })

  local branch = vim.api.nvim_get_hl(0, { name = 'InklineBranch' })
  equal(branch.link, 'Special')
end)

test('built-in components can be replaced globally', function()
  fresh_buffer(tmp .. '/override.lua', 'lua')
  inkline.setup({
    sections = { left = { 'filename' }, right = {} },
    components = {
      filename = function()
        return 'CUSTOM-NAME', 'InklineDim'
      end,
    },
  })

  contains(inkline.eval(), 'CUSTOM-NAME')
  not_contains(inkline.eval(), 'override.lua')
end)

test('component errors do not break rendering', function()
  fresh_buffer(tmp .. '/broken.lua', 'lua')
  inkline.setup({
    sections = {
      left = {
        function()
          error('boom')
        end,
        'filename',
      },
    },
  })

  contains(inkline.eval(), 'broken.lua')
end)

test('health module loads', function()
  local health = require('inkline.health')
  check(type(health.check) == 'function', 'health.check should be a function')
end)

test('center section uses statusline alignment', function()
  fresh_buffer(tmp .. '/center.lua', 'lua')
  inkline.setup({
    sections = {
      left = { 'filename' },
      center = { { function() return 'middle' end } },
      right = { 'location' },
    },
  })

  check(inkline.eval():find('%=', 1, true) ~= nil, 'center section should emit %= alignment')
end)

io.write(('\n%d tests, %d failures\n'):format(total, failures))
os.exit(failures == 0 and 0 or 1)
