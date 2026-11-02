# inkline.nvim

A quiet, fully customizable statusline for Neovim. No powerline arrows, no
colored blocks, no required fonts — just a few muted words and numbers that
blend into your colorscheme.

```
 NORMAL  src/init.lua [+]            main  42:8
```

- Zero dependencies, Neovim 0.10+
- Transparent by default; derives its colors from the active colorscheme
- ASCII-first: no Nerd Font required, but icons are fully configurable
- Declarative sections, per-component options, and inline Lua components
- Branch information from gitsigns when available, with a cached async `git`
  fallback (no diff counts, just the branch)
- Inactive windows are dimmed automatically

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'you/inkline.nvim',
  lazy = false,
  priority = 1000,
  opts = {},
}
```

`setup()` is optional: the plugin applies the defaults automatically. Pass
options through `opts` (or call `require('inkline').setup({ ... })`) to
customize it.

> Requires Neovim 0.10 or newer.

## Default layout

| Section | Components |
| --- | --- |
| left | `mode`, `filename` |
| center | — |
| right | `diagnostics`, `branch`, `location` |

`diagnostics` only appears when the buffer has diagnostics, and `branch` only
appears inside a Git repository.

## Configuration

```lua
require('inkline').setup({
  transparent = true,
  debug = false,

  icons = {
    modified = '[+]',
    readonly = '[RO]',
    branch = '',          -- e.g. '' with a Nerd Font
    truncate = '...',
    diagnostics = { error = 'E', warn = 'W', info = 'I', hint = 'H' },
    filetypes = {},       -- e.g. { lua = 'L', python = 'P' }
  },

  sections = {
    left = { 'mode', 'filename' },
    center = {},
    right = { 'diagnostics', 'branch', 'location' },
  },

  separator = '  ',
  padding = { left = 1, right = 1 },

  mode = {
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
    short = false,
  },

  filename = {
    max_width = 60,
    full_path = false,
    basename = false,
    unnamed = '[No Name]',
    modified = nil,       -- override icons.modified
    readonly = nil,       -- override icons.readonly
  },

  diagnostics = {
    severities = { 'ERROR', 'WARN', 'INFO', 'HINT' },
    style = 'short',      -- 'short' | 'long' | 'icons'
    separator = ' ',
    icons = nil,          -- override icons.diagnostics
  },

  branch = {
    max_width = 32,
    icon = nil,           -- override icons.branch
    gitsigns = true,
  },

  filetype = {
    devicons = false,
    icons = nil,          -- override icons.filetypes
    show_name = true,
    max_width = 24,
  },

  location = {
    format = '{line}:{col}',
    show_percent = false,
    percent_format = ' {percent}%',
  },

  progress = { format = '{percent}%' },
  lsp = { max_width = 40, separator = ', ' },
  macro = { format = 'REC @{register}' },
  searchcount = { format = '[{current}/{total}]' },
  selection = { format = '{chars} chars' },

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
      'ModeChanged', 'BufEnter', 'BufLeave', 'BufWritePost', 'FileType',
      'DirChanged', 'WinEnter', 'WinLeave', 'WinResized', 'VimResized',
      'DiagnosticChanged', 'LspProgress', 'CursorMoved', 'CursorMovedI',
      'User',
    },
  },

  highlights = {},
  components = {},
  condition = nil,
})
```

Lists such as `sections.left` are replaced wholesale; maps such as
`mode.labels` are merged with the defaults. That makes it safe to override only
the pieces you care about.

## Components

| Name | Output | Options |
| --- | --- | --- |
| `mode` | `NORMAL` | `labels`, `uppercase`, `short` |
| `filename` | `src/init.lua [+]` | `max_width`, `full_path`, `basename`, `unnamed`, `modified`, `readonly` |
| `diagnostics` | `E1 W2` | `severities`, `style`, `separator`, `icons` |
| `branch` | `main` | `max_width`, `icon`, `gitsigns` |
| `filetype` | `lua` | `devicons`, `icons`, `show_name`, `max_width` |
| `location` | `42:8` | `format`, `show_percent`, `percent_format` |
| `progress` | `42%` | `format` |
| `lsp` | `lua_ls, ts_ls` | `max_width`, `separator` |
| `encoding` | `utf-8` | — |
| `fileformat` | `unix` | — |
| `macro` | `REC @q` | `format` |
| `searchcount` | `[2/7]` | `format` |
| `selection` | `12 chars` | `format` |
| `custom` | user function | `render` |

### Per-item options and conditions

```lua
require('inkline').setup({
  sections = {
    left = {
      'mode',
      { 'filename', max_width = 40, basename = true },
      {
        'diagnostics',
        severities = { 'ERROR', 'WARN' },
        style = 'long',
        cond = function(ctx)
          return ctx.width >= 80
        end,
      },
    },
    right = {
      { 'branch', icon = '' },
      'location',
    },
  },
})
```

### Inline components

Any section item can be a function. It receives `(ctx, opts)` and may return:

- `nil` or `false` to hide the item
- `"text"` (uses `opts.hl`, default `Inkline`)
- `"text", "HighlightGroup"`
- `{ text = "text", hl = "HighlightGroup" }`
- a list of those segments

```lua
require('inkline').setup({
  sections = {
    right = {
      {
        function(ctx)
          local clients = vim.lsp.get_clients({ bufnr = ctx.bufnr })
          if #clients == 0 then
            return nil
          end
          return ('%d LSP'):format(#clients), 'InklineLsp'
        end,
        hl = 'InklineLsp',
      },
      'location',
    },
  },
})
```

The context contains `bufnr`, `winid`, `bufname`, `filetype`, `buftype`,
`width`, `is_active`, `mode = { raw, name }`, and `config`.

### Replace a built-in component

```lua
require('inkline').setup({
  components = {
    mode = function(ctx)
      return ctx.mode.raw:upper(), 'InklineMode' .. ctx.mode.name
    end,
  },
})
```

### Custom component with its own options

```lua
require('inkline').setup({
  custom = { render = function(ctx, opts) return opts.text end, text = 'hi' },
  sections = { right = { { 'custom', text = 'custom!' } } },
})
```

## Recipes

### Nerd Font icons

```lua
require('inkline').setup({
  icons = {
    -- Use any glyphs your font provides; these are common Nerd Font icons.
    modified = '\u{f040}',  -- pencil
    readonly = '\u{f023}',  -- lock
    branch = '\u{e725}',    -- git branch
    truncate = '…',
    diagnostics = {
      error = '\u{f057}',
      warn = '\u{f071}',
      info = '\u{f05a}',
      hint = '\u{f0eb}',
    },
  },
  filetype = { devicons = true },
})
```

### Show the mode short, with a full file path

```lua
require('inkline').setup({
  mode = { short = true },
  filename = { full_path = true, max_width = 0 },
})
```

### Diagnostics only on wide windows

```lua
require('inkline').setup({
  sections = {
    right = {
      {
        'diagnostics',
        cond = function(ctx) return ctx.width >= 100 end,
      },
      'branch',
      'location',
    },
  },
})
```

### Disable the statusline for a filetype

```lua
require('inkline').setup({
  disabled = { filetypes = { 'dashboard', 'lazy', 'mason' } },
})
```

### Keep the colorscheme's statusline background

```lua
require('inkline').setup({ transparent = false })
```

### Override a highlight

```lua
require('inkline').setup({
  highlights = {
    InklineBranch = { fg = '#7aa2f7' },
    InklineFile = { link = 'Title' },
    InklineModeNormal = { fg = '#a9b1d6', bold = true },
  },
})
```

Set a group to `false` to leave it untouched.

## Highlight groups

`Inkline`, `InklineInactive`, `InklineDim`, `InklineFile`, `InklineModified`,
`InklineReadonly`, `InklineSeparator`, `InklineBranch`, `InklineLocation`,
`InklineProgress`, `InklineFiletype`, `InklineSearch`, `InklineSelection`,
`InklineLsp`, `InklineMacro`, `InklineDiagnostics{Error,Warn,Info,Hint}`, and
`InklineMode{Normal,Insert,Visual,VisualLine,VisualBlock,Replace,Command,Terminal,Select,SelectLine,SelectBlock,Shell}`.

Colors are derived from the active colorscheme and re-applied on `ColorScheme`.

## API

```lua
local inkline = require('inkline')

inkline.setup(opts)        -- configure and install the statusline
inkline.eval()             -- render the statusline for the current window
inkline.redraw()           -- request a debounced redraw
inkline.redraw_now()       -- redraw immediately
inkline.apply_statusline() -- reinstall the statusline expression
inkline.is_setup()         -- whether setup() has run
inkline.get_config()       -- the active configuration
```

Command: `:InklineRedraw`.

## Health and tests

```vim
:checkhealth inkline
```

```sh
nvim --headless -u NONE -l tests/run.lua
```

## License

MIT
