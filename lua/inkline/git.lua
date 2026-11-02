-- Git branch lookup with a small per-directory cache.
--
-- Rendering a statusline must never block. The first lookup for a directory
-- returns nil and starts an asynchronous `git` process; the cached result is
-- used from then on and a redraw is requested when the lookup finishes.

local uv = vim.uv or vim.loop

local M = {
  --- Cache entries keyed by directory: { branch = string|false, time = number }
  cache = {},
  --- Directories with an in-flight lookup.
  pending = {},
  --- How long a known result stays fresh, in milliseconds.
  ttl = 5000,
  --- How long a "not a repository" result stays fresh, in milliseconds.
  negative_ttl = 30000,
  --- Called after a lookup completes. Set by init.lua.
  on_update = nil,
}

--- Current monotonic time in milliseconds.
--- @return number
local function now()
  return uv.now()
end

--- @return boolean
local function git_available()
  if M._git_available == nil then
    M._git_available = vim.fn.executable('git') == 1
  end
  return M._git_available
end

--- Store a lookup result and notify the renderer.
--- @param dir string
--- @param branch string|false
local function finish(dir, branch)
  M.cache[dir] = { branch = branch, time = now() }
  M.pending[dir] = nil

  vim.schedule(function()
    if M.on_update then
      M.on_update()
    end
  end)
end

--- Resolve the branch for a directory, without blocking.
--- @param dir string
local function resolve(dir)
  if not git_available() then
    return
  end

  M.pending[dir] = true

  local ok = pcall(vim.system, {
    'git',
    'symbolic-ref',
    '--short',
    '-q',
    'HEAD',
  }, { cwd = dir, text = true }, function(result)
    local branch = nil

    if result.code == 0 then
      local stdout = vim.trim(result.stdout or '')
      if stdout ~= '' then
        branch = stdout
      end
    end

    if branch then
      finish(dir, branch)
      return
    end

    -- Detached HEAD: fall back to the short commit hash.
    local second_ok = pcall(
      vim.system,
      { 'git', 'rev-parse', '--short', 'HEAD' },
      { cwd = dir, text = true },
      function(second)
        if second.code == 0 then
          local hash = vim.trim(second.stdout or '')
          finish(dir, hash ~= '' and hash or false)
        else
          finish(dir, false)
        end
      end
    )

    if not second_ok then
      finish(dir, false)
    end
  end)

  if not ok then
    finish(dir, false)
  end
end

--- Return the cached branch for a directory, refreshing it when stale.
---
--- The previous value is returned while a stale cache entry is refreshed, so
--- the statusline does not flicker. `nil` means "not known yet" or "not a
--- repository".
---
--- @param dir string|nil Directory to search from. Defaults to the cwd.
--- @return string|nil
function M.get_branch(dir)
  if not git_available() then
    return nil
  end

  dir = dir or vim.fn.getcwd()
  if dir == '' then
    dir = vim.fn.getcwd()
  end

  -- Symlinked directories (notably /tmp on macOS) must share one cache key.
  dir = uv.fs_realpath(dir) or dir

  local entry = M.cache[dir]
  local age = entry and (now() - entry.time) or nil
  local max_age = entry and entry.branch and M.ttl or M.negative_ttl

  if entry and age < max_age then
    return entry.branch or nil
  end

  -- Refresh in the background. If there is a stale value, keep showing it.
  if not M.pending[dir] then
    resolve(dir)
  end

  return entry and entry.branch or nil
end

--- Forget every cached result. Useful after a checkout or in tests.
function M.clear()
  M.cache = {}
  M.pending = {}
end

return M
