# 🚧 WIP 🚧

Packer v2

Differences:
- heavily refactored
- lockfile support
- no compilation
- re-written in Teal

## Table of Contents
1. [Features](#features)
2. [Requirements](#requirements)
3. [Quickstart](#quickstart)
4. [Bootstrapping](#bootstrapping)
5. [Usage](#usage)
    1. [The setup and add functions](#the-setup-and-add-function)
    2. [Custom Initialization](#custom-initialization)
    3. [Specifying Plugins](#specifying-plugins)
    4. [Performing plugin management operations](#performing-plugin-management-operations)
6. [Debugging](#debugging)

## Features
- Declarative plugin specification
- Support for dependencies
- Expressive configuration and lazy-loading options
- Extensible
- Post-install/update hooks
- Async
- Support for `git` tags, branches, revisions
- Support for local plugins

## Requirements
- **You need to be running Neovim v0.8.0+**
- If you are on Windows 10, you need developer mode enabled in order to use local plugins (creating
  symbolic links requires admin privileges on Windows - credit to @TimUntersberger for this note)

## Quickstart
To get started, first clone this repository to somewhere on your `packpath`, e.g.:

> Unix, Linux Installation

```bash
git clone --depth 1 https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim
```

If you use Arch Linux, there is also [an AUR package](https://aur.archlinux.org/packages/nvim-packer-git/).

> Windows Powershell Installation

```bash
git clone https://github.com/wbthomason/packer.nvim "$env:LOCALAPPDATA\nvim-data\site\pack\packer\start\packer.nvim"
```

Then you can write your plugin specification in Lua, e.g. (in `~/.config/nvim/lua/plugins.lua`):

```lua
-- This file can be loaded by calling `lua require('plugins')` from your init.vim

require('packer').add{
  -- Packer can manage itself
  'wbthomason/packer.nvim';

  -- Simple plugins can be specified as strings
  '9mm/vim-closer';

  -- Lazy loading:
  -- Load on specific commands
  {'tpope/vim-dispatch', cmd = {'Dispatch', 'Make', 'Focus', 'Start'}};

  -- Load on specific keymap
  {'tpope/vim-commentary', keys = 'gc'},

  -- Load on a combination of conditions: specific filetypes or commands
  -- Also run code after load (see the "config" key)
  { 'w0rp/ale',
    ft = {'sh', 'zsh', 'bash', 'c', 'cpp', 'cmake', 'html', 'markdown', 'racket', 'vim', 'tex'},
    cmd = 'ALEEnable',
    config = 'vim.cmd[[ALEEnable]]'
  };

  -- Local plugins can be included
  '~/projects/personal/hover.nvim';

  -- Plugins can have post-install/update hooks
  {'iamcco/markdown-preview.nvim', run = 'cd app && yarn install', cmd = 'MarkdownPreview'};

  -- Post-install/update hook with neovim command
  -- Install plugin as a 'start' plugin
  { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate', start = true };

  -- Post-install/update hook with call of vimscript function with argument
  { 'glacambre/firenvim', run = function()
    vim.fn['firenvim#install'](0)
  end };

  -- Use specific branch, dependency and run lua file after load
  { 'glepnir/galaxyline.nvim',
    branch = 'main',
    requires = {'kyazdani42/nvim-web-devicons'},
    config = function()
      require'statusline'
    end
  };

  -- Run config *before* the plugin is loaded
  {'whatyouhide/vim-lengthmatters', config_pre = function()
    vim.g.lengthmatters_highlight_one_column = 1
    vim.g.lengthmatters_excluded = {'packer'}
  end},
}
```

`packer` provides the following commands.

```vim
" Remove any disabled or unused plugins
:Packer clean

" Install missing plugins
:Packer install

" Update installed plugins
" supports the `--preview` flag as an optional first argument to preview updates
:Packer update

" Clean, fix, install then update
" supports the `--preview` flag as an optional first argument to preview updates
:Packer sync

" View status of plugins
:Packer status

" Create a lockfile of plugins with their current commits
:Packer lock

" Restore plugins using saved lockfile
:Packer restore
```

## Bootstrapping

If you want to automatically install and set up `packer.nvim` on any machine you clone your configuration to,
add the following snippet (which is due to @Iron-E and @khuedoan) somewhere in your config **before** your first usage of `packer`:

```lua
local function bootstrap_packer()
  if not pcall(require, 'packer') then
    if vim.fn.input("Download Packer? (y for yes): ") ~= "y" then
      return
    end

    print("Downloading packer.nvim...")
    print(fn.system{
     'git',
     'clone',
     '--depth', '1',
     'https://github.com/wbthomason/packer.nvim',
     fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
    })
  end
end

bootstrap_packer()

require('packer').add{
  'wbthomason/packer.nvim';
  -- My plugins here
  -- 'foo1/bar1.nvim';
  -- 'foo2/bar2.nvim';

}
```

## Usage

The following is a more in-depth explanation of `packer`'s features and use.

### The `setup` and `add` functions
`packer` provides`packer.add(spec)`, which is used in the above examples
where `spec` is a table specifying a single or multiple plugins.

### Custom Initialization
`packer.setup()` can be used to provide custom configuration (note that this is optional).
The default configuration values (and structure of the configuration table) are:

```lua
require('packer').setup{
  package_root        = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  plugin_package      = 'packer', -- The default package for plugins
  max_jobs            = nil, -- Limit the number of simultaneous jobs. nil means no limit
  auto_clean          = true, -- During sync(), remove unused plugins
  preview_updates     = false, -- If true, always preview updates before choosing which plugins to update, same as `PackerUpdate --preview`.
  git = {
    cmd = 'git', -- The base command for git operations
    depth = 1, -- Git clone depth
    clone_timeout = 60, -- Timeout, in seconds, for git clones
    default_url_format = 'https://github.com/%s' -- Lua format string used for "aaa/bbb" style plugins
  },
  display = {
    non_interactive = false, -- If true, disable display windows for all operations
    working_sym     = '⟳', -- The symbol for a plugin being installed/updated
    error_sym       = '✗', -- The symbol for a plugin with an error in installation/updating
    done_sym        = '✓', -- The symbol for a plugin which has completed installation/updating
    removed_sym     = '-', -- The symbol for an unused plugin which was removed
    moved_sym       = '→', -- The symbol for a plugin which was moved (e.g. from opt to start)
    header_sym      = '━', -- The symbol for the header line in packer's display
    show_all_info   = true, -- Should packer show all update details automatically?
    prompt_border   = 'double', -- Border style of prompt popups.
    keybindings = { -- Keybindings for the display window
      quit          = 'q',
      toggle_update = 'u', -- only in preview
      continue      = 'c', -- only in preview
      toggle_info   = '<CR>',
      diff          = 'd',
      prompt_revert = 'r',
    }
  },
  log = { level = 'warn' }, -- The default print log level. One of: "trace", "debug", "info", "warn", "error", "fatal".
  autoremove = false, -- Remove disabled or unused plugins without prompting the user
  lockfile = {
    path = util.join_paths(vim.fn.stdpath('config', 'packer', 'lockfile.lua'))
  }
}
```

### Specifying plugins

`packer` is based around declarative specification of plugins.

1. Absolute paths to a local plugin
2. Full URLs (treated as plugins managed with `git`)
3. `username/repo` paths (treated as Github `git` plugins)

Plugin specs can take two forms:

1. A list of plugin specifications (strings or tables)
2. A table specifying a single plugin. It must have a plugin location string as its first element,
   and may additionally have a number of optional keyword elements, shown below:
```lua
{
  'myusername/example',    -- The plugin location string

  -- The following keys are all optional
  branch   = string,              -- Specifies a git branch to use
  tag      = string,              -- Specifies a git tag to use. Supports '*' for "latest tag"
  commit   = string,              -- Specifies a git commit to use
  lock     = boolean,             -- Skip updating this plugin in updates/syncs. Still cleans.
  run      = string, function or table,  -- Post-update/install hook. See "update/install hooks".
  requires = string or string[],  -- Specifies plugin dependencies. See "dependencies".
  config_pre = string or function,  -- Specifies code to run before this plugin is loaded.
  config   = string or function,  -- Specifies code to run after this plugin is loaded.

  -- The following keys all imply lazy-loading and imply opt = true
  cmd   = string or string[],     -- Specifies commands which load this plugin. Can be an autocmd pattern.
  ft    = string or string[],     -- Specifies filetypes which load this plugin.
  keys  = string or string[],     -- Specifies maps which load this plugin. See "Keybindings".
  event = string or string[],     -- Specifies autocommand events which load this plugin.
  cond  = boolean or function,    -- Specifies custom loader
}
```

#### Checking plugin statuses

> 🚧 **TODO**: Currently main plugin table is accessed via `require'packer.plugin'.plugins` but
the format for this table is not API stable.

#### Update/install hooks

You may specify operations to be run after successful installs/updates of a plugin with the `run`
key. This key may either be a Lua function, which will be called with the `plugin` table for this
plugin (containing the information passed to the spec as well as output from the installation/update
commands, the installation path of the plugin, etc.), a string, or a table of functions and strings.

If an element of `run` is a string, then either:

1. If the first character of `run` is ":", it is treated as a Neovim command and executed.
2. Otherwise, `run` is treated as a shell command and run in the installation directory of the
   plugin via `$SHELL -c '<run>'`.

#### Dependencies

Plugins may specify dependencies via the `requires` key. This key can be a string or a list (table).

If `requires` is a string, it is treated as specifying a single plugin. If a plugin with the name
given in `requires` is already known in the managed set, nothing happens. Otherwise, the string is
treated as a plugin location string and the corresponding plugin is added to the managed set.

If `requires` is a list, it is treated as a list of plugin specifications following the format given
above.

Plugins specified in `requires` are removed when no active plugins require them.

> 🚧 **TODO**: explain that plugins can only be specified as a table once.

#### Keybindings

Plugins may be lazy-loaded on the use of keybindings/maps.
Individual keybindings are specified either as a string (in which case they are treated as normal mode maps) or a table in the format `{mode, map}`.

#### Custom loader

A custom loader for a plugin may be specified via `cond`.
This is a function which has a function as its first argument.
When this function argument is called, the plugin is loaded.

For example, the following plugin is lazy-loaded on the key mapping `ga`:

```lua
packer.add{
  {"my/plugin", cond = function(load_plugin)
    vim.keymap.set('n', 'ga', function()
      vim.keymap.del('n', 'ga')
      load_plugin()
      vim.api.nvim_input('ga')
    end)
  end}

  -- equivalent to --

  {"my/plugin", keys = 'ga'},
}
```

### Performing plugin management operations

> 🚧 **TODO**:
>
> API here will be similar to what it was before with the only exception being the
> final argument to every command will be a callback which is called when the operation finishes.

`packer` exposes the following functions for common plugin management operations. In all of the
below, `plugins` is an optional table of plugin names; if not provided, the default is "all managed
plugins":

- `packer.install(plugins)`: Install the specified plugins if they are not already installed
- `packer.update(plugins)`: Update the specified plugins, installing any that are missing
- `packer.update(opts, plugins)`: First argument can be a table specifying options, such as `{preview_updates = true}` to preview potential changes before updating (same as `PackerUpdate --preview`).
- `packer.clean()`: Remove any disabled or no longer managed plugins

## Debugging
`packer.nvim` logs to `stdpath(cache)/packer.nvim.log`. Looking at this file is usually a good start
if something isn't working as expected.

