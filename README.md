# packer.nvim
[`use-package`](https://github.com/jwiegley/use-package) inspired plugin/package management for
Neovim.

## Features
- Declarative plugin specification
- Support for dependencies
- (soon) Support for Luarocks dependencies
- Expressive configuration and lazy-loading options
- Automatically compiles efficient lazy-loading code to improve startup time
- Uses native packages
- Extensible
- Written in Lua, configured in Lua
- Post-install/update hooks
- Uses jobs for async installation
- Support for `git` tags, branches, revisions, submodules
- Support for local plugins

## Quickstart
To get started, first clone this repository to somewhere on your `packpath`, e.g.:
```shell
git clone https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/opt/packer.nvim
```

Then you can write your plugin specification in Lua, e.g. (in `~/.config/nvim/lua/plugins.lua`):

```lua
-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer in your `opt` pack
vim.cmd [[packadd packer.nvim]]
-- Temporary until https://github.com/neovim/neovim/pull/12632 is merged
vim._update_package_paths()

return require('packer').startup(function(use)
  -- Packer can manage itself as an optional plugin
  use {'wbthomason/packer.nvim', opt = true}

  -- Simple plugins can be specified as strings
  use '9mm/vim-closer'

  -- Lazy loading:
  -- Load on specific commands
  use {'tpope/vim-dispatch', opt = true, cmd = {'Dispatch', 'Make', 'Focus', 'Start'}}

  -- Load on an autocommand event
  use {'andymass/vim-matchup', event = 'VimEnter *'}

  -- Load on a combination of conditions: specific filetypes or commands
  -- Also run code after load (see the "config" key)
  use {
    'w0rp/ale',
    ft = {'sh', 'zsh', 'bash', 'c', 'cpp', 'cmake', 'html', 'markdown', 'racket', 'vim', 'tex'},
    cmd = 'ALEEnable',
    config = 'vim.cmd[[ALEEnable]]
  }

  -- Plugins can have dependencies on other plugins
  use {
    'haorenW1025/completion-nvim',
    opt = true,
    requires = {{'hrsh7th/vim-vsnip', opt = true}, {'hrsh7th/vim-vsnip-integ', opt = true}}
  }

  -- Local plugins can be included
  use '~/projects/personal/hover.nvim'

  -- Plugins can have post-install/update hooks
  use {'iamcco/markdown-preview.nvim', run = 'cd app && yarn install', cmd = 'MarkdownPreview'}
end)
```

`packer` provides the following commands after you've run and configured `packer` with `require('packer').startup(...)`:

```
-- You must run this whenever you make changes to your plugin configuration
:PackerCompile

-- Only install missing plugins
:PackerInstall

-- Update and install plugins
:PackerUpdate

-- Remove any disabled or unused plugins
:PackerClean

-- Performs `PackerClean` and then `PackerUpdate`
:PackerSync
```

## Usage

The above snippets give some examples of `packer` features and use. Examples include:

- Very simple: `test_init.vim` in this repo.
- A more realistic example in my dotfiles:
  - [Specification file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/lua/plugins.lua)
  - [Loading file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/plugin/plugins.vim)
  - [Generated lazy-loader file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/plugin/packer_load.vim)
- An example using the `startup` method: [tjdevries](https://github.com/tjdevries/config_manager/blob/master/xdg_config/nvim/lua/plugins.lua)
    - Using this method, you do not require a "loading" file. You can simply `lua require('plugins')` from your `init.vim`

The following is a more in-depth explanation of `packer`'s features and use.

### Custom Initialization
You are not required to use `packer.startup` if you prefer a more manual setup with finer control
over configuration and loading.

To take this approach, load `packer` like any other Lua module. You must call `packer.init()` before
performing any operations; it is recommended to call `packer.reset()` if you may be re-running your
specification code (e.g. by sourcing your plugin specification file with `luafile`).

You may pass a table of configuration values to `packer.init()` to customize its operation. The
default configuration values (and structure of the configuration table) are:
```lua
{
  ensure_dependencies   = true, -- Should packer install plugin dependencies?
  package_root   = util.is_windows and '~\\AppData\\Local\\nvim-data\\site\\pack' or '~/.local/share/nvim/site/pack',
  compile_path = vim.fn.stdpath('config') .. '/plugin/packer_compiled.vim',
  plugin_package = 'packer', -- The default package for plugins
  max_jobs = nil, -- Limit the number of simultaneous jobs. nil means no limit
  auto_clean = true, -- During sync(), remove unused plugins
  disable_commands = false, -- During `startup`, disable creating commands
  git = {
    cmd = 'git', -- The base command for git operations
    subcommands = { -- Format strings for git subcommands
      update         = '-C %s pull --ff-only --progress --rebase=false',
      install        = 'clone %s %s --depth %i --no-single-branch --progress',
      fetch          = '-C %s fetch --depth 999999 --progress',
      checkout       = '-C %s checkout %s --',
      update_branch  = '-C %s merge --ff-only @{u}',
      current_branch = '-C %s branch --show-current',
      diff           = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt       = '%%h %%s (%%cr)',
      get_rev        = '-C %s rev-parse --short HEAD',
      get_msg        = '-C %s log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules     = '-C %s submodule update --init --recursive --progress'
    },
    depth = 1, -- Git clone depth
  },
  display = {
    open_fn  = nil, -- An optional function to open a window for packer's display
    open_cmd = '65vnew [packer]', -- An optional command to open a window for packer's display
    working_sym = '⟳', -- The symbol for a plugin being installed/updated
    error_sym = '✗', -- The symbol for a plugin with an error in installation/updating
    done_sym = '✓', -- The symbol for a plugin which has completed installation/updating
    removed_sym = '-', -- The symbol for an unused plugin which was removed
    moved_sym = '→', -- The symbol for a plugin which was moved (e.g. from opt to start)
    header_sym = '━', -- The symbol for the header line in packer's display
  }
}
```

### Specifying plugins

`packer` is based around declarative specification of plugins. You can declare a plugin using the
function `packer.use`, which I highly recommend locally binding to `use` for conciseness.

`use` takes either a string or a table. If a string is provided, it is treated as a plugin location
for a non-optional plugin with no additional configuration. Plugin locations may be specified as

1. Absolute paths to a local plugin
2. Full URLs (treated as plugins managed with `git`)
3. `username/repo` paths (treated as Github `git` plugins)

A table given to `use` must have a plugin location string as its first element, and may additionally
have a number of optional keyword elements, shown below:
```lua
use {
  'myusername/example',   -- The plugin location string
  -- The following keys are all optional
  disable = boolean,           -- Mark a plugin as inactive
  installer = function,        -- Specifies custom installer. See "custom installers" below.
  updater = function,          -- Specifies custom updater. See "custom installers" below.
  after = string or list,      -- Specifies plugins to load before this plugin.
  rtp = string,                -- Specifies a subdirectory of the plugin to add to runtimepath.
  opt = boolean,               -- Manually marks a plugin as optional.
  branch = string,             -- Specifies a git branch to use
  tag = string,                -- Specifies a git tag to use
  commit = string,             -- Specifies a git commit to use
  run = string or function,    -- Post-update/install hook. See "update/install hooks".
  requires = string or list -- Specifies plugin dependencies. See "dependencies".
  config = string or function, -- Specifies code to run after this plugin is loaded.
  -- The following keys all imply lazy-loading
  cmd = string or list,        -- Specifies commands which load this plugin.
  ft = string or list,         -- Specifies filetypes which load this plugin.
  keys = string or list,       -- Specifies maps which load this plugin. See "Keybindings".
  event = string or list,      -- Specifies autocommand events which load this plugin.
  cond = string or function,   -- Specifies a conditional test to load this plugin
  setup = string or function,  -- Specifies code to run before this plugin is loaded.
}
```

#### Custom installers

You may specify a custom installer & updater for a plugin using the `installer` and `updater` keys.
Note that either both or none of these keys are required. These keys should be functions which take
as an argument a `display` object (from `lua/packer/display.lua`) and return an async function (per
`lua/packer/async.lua`) which (respectively) installs/updates the given plugin.

Providing the `installer`/`updater` keys overrides plugin type detection, but you still need to
provide a location string for the name of the plugin.

#### Update/install hooks

You may specify operations to be run after successful installs/updates of a plugin with the `run`
key. This key may either be a Lua function, which will be called with the `plugin` table for this
plugin (containing the information passed to `use` as well as output from the installation/update
commands, the installation path of the plugin, etc.), or a string.

If `run` is a string, then either:

1. If the first character of `run` is ":", it is treated as a Neovim command and executed.
2. Otherwise, `run` is treated as a shell command and run in the installation directory of the
   plugin via `$SHELL -c 'cd <plugin dir> && <run>'`.

#### Dependencies

Plugins may specify dependencies via the `requires` key. This key can be a string or a list (table).

If `requires` is a string, it is treated as specifying a single plugin. If a plugin with the name
given in `requires` is already known in the managed set, nothing happens. Otherwise, the string is
treated as a plugin location string and the corresponding plugin is added to the managed set.

If `requires` is a list, it is treated as a list of plugin specifications following the format given
above.

If `ensure_dependencies` is true, the plugins specified in `requires` will be installed.

Plugins specified in `requires` are removed when no active plugins require them.

#### Keybindings

Plugins may be lazy-loaded on the use of keybindings/maps. Individual keybindings are specified either as a string (in which case they are treated as normal mode maps) or a table in the format `{mode, map}`.

### Performing plugin management operations
`packer` exposes the following functions for common plugin management operations. In all of the
below, `plugins` is an optional table of plugin names; if not provided, the default is "all managed
plugins":

- `packer.install(plugins)`: Install the specified plugins if they are not already installed
- `packer.update(plugins)`: Update the specified plugins, installing any that are missing
- `packer.clean()`: Remove any disabled or no longer managed plugins
- `packer.sync(plugins)`: Perform a `clean` followed by an `update`
- `packer.compile(path)`: Compile lazy-loader code and save to `path`.

### Extending `packer`
You can add custom key handlers to `packer` by calling `packer.set_handler(name, func)` where `name`
is the key you wish to handle and `func` is a function with the signature `func(plugins, plugin,
value)` where `plugins` is the global table of managed plugins, `plugin` is the table for a specific
plugin, and `value` is the value associated with key `name` in `plugin`.

### Compiling Lazy-Loaders
To optimize startup time, `packer.nvim` compiles code to perform the lazy-loading operations you
specify. This means that you do not need to load `packer.nvim` unless you want to perform some
plugin management operations.

To generate the compiled code, call `packer.compile(path)`, where `path` is some file path on you r
`runtimepath`, with a `.vim` extension. This will generate a blend of Lua and Vimscript to load and
configure all your lazy-loaded plugins (e.g. generating commands, autocommands, etc.) and save it to
`path`. Then, when you start vim, the file at `path` is loaded (because `path` must be on your
`runtimepath`), and lazy-loading works.

If `path` is not provided to `packer.compile`, the output file will default to the value of
`config.compile_path`.

Note that you **must** run `packer.compile` yourself to generate this file.

## Status
**tl;dr**: Beta. Things seem to work and most features are complete, but certainly not every edge
case has been tested. People willing to give it a try and report bugs/errors are very welcome! 

- Basic package management works (i.e. installation, updating, cleaning, start/opt plugins,
  displaying results)
- Automatic generation of lazy-loading code works
- More testing is needed
- The code is messy and needs more cleanup and refactoring

## Current work-in-progress
- Luarocks support

## TODO
- Allow multiple packages
- Optimizations?
