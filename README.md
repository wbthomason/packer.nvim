# packer.nvim

[![Gitter](https://badges.gitter.im/packer-nvim/community.svg)](https://gitter.im/packer-nvim/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

[`use-package`](https://github.com/jwiegley/use-package) inspired plugin/package management for
Neovim.

Have questions? Start a [discussion](https://github.com/wbthomason/packer.nvim/discussions).

Have a problem or idea? Make an [issue](https://github.com/wbthomason/packer.nvim/issues) or a [PR](https://github.com/wbthomason/packer.nvim/pulls).

## Table of Contents
1. [Notices](#notices)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Quickstart](#quickstart)
5. [Bootstrapping](#bootstrapping)
6. [Usage](#usage)
    1. [The startup function](#the-startup-function)
    2. [Custom Initialization](#custom-initialization)
    3. [Specifying Plugins](#specifying-plugins)
    4. [Performing plugin management operations](#performing-plugin-management-operations)
    5. [Extending packer](#extending-packer)
    6. [Compiling Lazy-Loaders](#compiling-lazy-loaders)
7. [Debugging](#debugging)
8. [Status](#status)
9. [Contributors](#contributors)

## Notices
- **2021-02-18**: Having trouble with Luarocks on macOS? See [this issue](https://github.com/wbthomason/packer.nvim/issues/180).
- **2021-01-19**: Basic Luarocks support has landed! Use the `rocks` key with a string or table to specify packages to install.
- **2020-12-10**: The `disable_commands` configuration flag now affects non-`startup` use as well. This means that, by default, `packer` will create commands for basic operations for you.
- **2020-11-13**: There is now a default implementation for a floating window `open_fn` in `packer.util`.
- **2020-09-04:** Due to changes to the Neovim `extmark` api (see: https://github.com/neovim/neovim/commit/3853276d9cacc99a2698117e904475dbf7033383), users will need to update to a version of Neovim **after** the aforementioned PR was merged. There are currently shims around the changed functions which should maintain support for earlier versions of Neovim, but these are intended to be temporary and will be removed by **2020-10-04**. Therefore Packer will not work with Neovim v0.4.4, which was released before the `extmark` change.

## Features
- Declarative plugin specification
- Support for dependencies
- Support for Luarocks dependencies
- Expressive configuration and lazy-loading options
- Automatically compiles efficient lazy-loading code to improve startup time
- Uses native packages
- Extensible
- Written in Lua, configured in Lua
- Post-install/update hooks
- Uses jobs for async installation
- Support for `git` tags, branches, revisions, submodules
- Support for local plugins

## Requirements
- You need to be running Neovim v0.5.0+; `packer` makes use of extmarks and other newly-added Neovim
  features.
- If you are on Windows 10, you need developer mode enabled in order to use local plugins (`packer`
  needs to use `mklink`, which requires admin privileges - credit to @TimUntersberger for this note)

## Quickstart
To get started, first clone this repository to somewhere on your `packpath`, e.g.:
```shell
git clone https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim
```

Then you can write your plugin specification in Lua, e.g. (in `~/.config/nvim/lua/plugins.lua`):

```lua
-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer in your `opt` pack
vim.cmd [[packadd packer.nvim]]
-- Only if your version of Neovim doesn't have https://github.com/neovim/neovim/pull/12632 merged
vim._update_package_paths()

return require('packer').startup(function()
  -- Packer can manage itself as an optional plugin
  use {'wbthomason/packer.nvim', opt = true}

  -- Simple plugins can be specified as strings
  use '9mm/vim-closer'

  -- Lazy loading:
  -- Load on specific commands
  use {'tpope/vim-dispatch', opt = true, cmd = {'Dispatch', 'Make', 'Focus', 'Start'}}

  -- Load on an autocommand event
  use {'andymass/vim-matchup', event = 'VimEnter'}

  -- Load on a combination of conditions: specific filetypes or commands
  -- Also run code after load (see the "config" key)
  use {
    'w0rp/ale',
    ft = {'sh', 'zsh', 'bash', 'c', 'cpp', 'cmake', 'html', 'markdown', 'racket', 'vim', 'tex'},
    cmd = 'ALEEnable',
    config = 'vim.cmd[[ALEEnable]]'
  }

  -- Plugins can have dependencies on other plugins
  use {
    'haorenW1025/completion-nvim',
    opt = true,
    requires = {{'hrsh7th/vim-vsnip', opt = true}, {'hrsh7th/vim-vsnip-integ', opt = true}}
  }

  -- Plugins can also depend on rocks from luarocks.org:
  use {
    'my/supercoolplugin',
    rocks = {'lpeg', {'lua-cjson', version = '2.1.0'}}
  }

  -- You can specify rocks in isolation
  use_rocks 'penlight'
  use_rocks {'lua-resty-http', 'lpeg'}

  -- Local plugins can be included
  use '~/projects/personal/hover.nvim'

  -- Plugins can have post-install/update hooks
  use {'iamcco/markdown-preview.nvim', run = 'cd app && yarn install', cmd = 'MarkdownPreview'}

  -- Post-install/update hook with neovim command
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }

  -- Post-install/update hook with call of vimscript function with argument
  use { 'glacambre/firenvim', run = function() vim.fn['firenvim#install'](0) end }

  -- Use specific branch, dependency and run lua file after load
  use {
    'glepnir/galaxyline.nvim', branch = 'main', config = function() require'statusline' end,
    requires = {'kyazdani42/nvim-web-devicons'}
  }

  -- Use dependency and run lua function after load
  use {
    'lewis6991/gitsigns.nvim', requires = { 'nvim-lua/plenary.nvim' },
    config = function() require('gitsigns').setup() end
  }

  -- You can specify multiple plugins in a single call
  use {'tjdevries/colorbuddy.vim', {'nvim-treesitter/nvim-treesitter', opt = true}}

  -- You can alias plugin names
  use {'dracula/vim', as = 'dracula'}
end)
```

Note that if you get linter complaints about `use` being an undefined global, these errors are
spurious - `packer` injects `use` into the scope of the function passed to `startup`.
If these errors bother you, the easiest fix is to simply specify `use` as an argument to the
function you pass to `startup`, e.g.
```lua
packer.startup(function(use)
...your config...
end)
```

`packer` provides the following commands after you've run and configured `packer` with `require('packer').startup(...)`:

```
-- You must run this or `PackerSync` whenever you make changes to your plugin configuration
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

You can configure Neovim to automatically run `:PackerCompile` whenever `plugins.lua` is updated with an autocommand:
```
autocmd BufWritePost plugins.lua PackerCompile
```
This autocommand can be placed in your `init.vim`, or any other startup file as per your setup.

## Bootstrapping

If you want to automatically ensure that `packer.nvim` is installed on any machine you clone your
configuration to, add the following snippet (which is due to @Iron-E) somewhere in your config **before** your first usage of
`packer`:
```lua
local execute = vim.api.nvim_command
local fn = vim.fn

local install_path = fn.stdpath('data')..'/site/pack/packer/opt/packer.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  execute('!git clone https://github.com/wbthomason/packer.nvim '..install_path)
  execute 'packadd packer.nvim'
end
```

Note that this will install `packer` as an `opt` plugin; if you want `packer` to be a `start`
plugin, you must modify the value of `install_path` in the above snippet.

## Usage

The above snippets give some examples of `packer` features and use. Examples include:

- My dotfiles:
  - [Specification file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/lua/plugins.lua)
  - [Loading file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/plugin/plugins.vim)
  - [Generated lazy-loader file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/plugin/packer_load.vim)
- An example using the `startup` method: [tjdevries](https://github.com/tjdevries/config_manager/blob/master/xdg_config/nvim/lua/tj/plugins.lua)
    - Using this method, you do not require a "loading" file. You can simply `lua require('plugins')` from your `init.vim`

The following is a more in-depth explanation of `packer`'s features and use.

### The `startup` function
`packer` provides `packer.startup(spec)`, which is used in the above examples.

`startup` is a convenience function for simple setup and can be invoked as follows:
- `spec` can be a function: `packer.startup(function() use 'tjdevries/colorbuddy.vim' end)`
- `spec` can be a table with a function as its first element and config overrides as another element:
  `packer.startup({function() use 'tjdevries/colorbuddy.vim' end, config = { ... }})`
- `spec` can be a table with a table of plugin specifications as its first element and config overrides as another element:
 `packer.startup({{'tjdevries/colorbuddy.vim'}, config = { ... }})`

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
  package_root   = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  compile_path = util.join_paths(vim.fn.stdpath('config'), 'plugin', 'packer_compiled.vim'),
  plugin_package = 'packer', -- The default package for plugins
  max_jobs = nil, -- Limit the number of simultaneous jobs. nil means no limit
  auto_clean = true, -- During sync(), remove unused plugins
  compile_on_sync = true, -- During sync(), run packer.compile()
  disable_commands = false, -- Disable creating commands
  opt_default = false, -- Default to using opt (as opposed to start) plugins
  transitive_opt = true, -- Make dependencies of opt plugins also opt by default
  transitive_disable = true, -- Automatically disable dependencies of disabled plugins
  auto_reload_compiled = true, -- Automatically reload the compiled file after creating it.
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
    clone_timeout = 60, -- Timeout, in seconds, for git clones
  },
  display = {
    non_interactive = false, -- If true, disable display windows for all operations
    open_fn  = nil, -- An optional function to open a window for packer's display
    open_cmd = '65vnew [packer]', -- An optional command to open a window for packer's display
    working_sym = '⟳', -- The symbol for a plugin being installed/updated
    error_sym = '✗', -- The symbol for a plugin with an error in installation/updating
    done_sym = '✓', -- The symbol for a plugin which has completed installation/updating
    removed_sym = '-', -- The symbol for an unused plugin which was removed
    moved_sym = '→', -- The symbol for a plugin which was moved (e.g. from opt to start)
    header_sym = '━', -- The symbol for the header line in packer's display
    show_all_info = true, -- Should packer show all update details automatically?
    keybindings = { -- Keybindings for the display window
      quit = 'q',
      toggle_info = '<CR>',
      prompt_revert = 'r',
    }
  },
  luarocks = {
    python_cmd = 'python' -- Set the python command to use for running hererocks
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

A table given to `use` can take two forms:

1. A list of plugin specifications (strings or tables)
2. A table specifying a single plugin. It must have a plugin location string as its first element,
   and may additionally have a number of optional keyword elements, shown below:
```lua
use {
  'myusername/example',        -- The plugin location string
  -- The following keys are all optional
  disable = boolean,           -- Mark a plugin as inactive
  as = string,                 -- Specifies an alias under which to install the plugin
  installer = function,        -- Specifies custom installer. See "custom installers" below.
  updater = function,          -- Specifies custom updater. See "custom installers" below.
  after = string or list,      -- Specifies plugins to load before this plugin. See "sequencing" below
  rtp = string,                -- Specifies a subdirectory of the plugin to add to runtimepath.
  opt = boolean,               -- Manually marks a plugin as optional.
  branch = string,             -- Specifies a git branch to use
  tag = string,                -- Specifies a git tag to use
  commit = string,             -- Specifies a git commit to use
  lock = boolean,              -- Skip this plugin in updates/syncs
  run = string or function,    -- Post-update/install hook. See "update/install hooks".
  requires = string or list,   -- Specifies plugin dependencies. See "dependencies".
  rocks = string or list,      -- Specifies Luarocks dependencies for the plugin
  config = string or function, -- Specifies code to run after this plugin is loaded.
  -- The setup key implies opt = true
  setup = string or function,  -- Specifies code to run before this plugin is loaded.
  -- The following keys all imply lazy-loading and imply opt = true
  cmd = string or list,        -- Specifies commands which load this plugin.
  ft = string or list,         -- Specifies filetypes which load this plugin.
  keys = string or list,       -- Specifies maps which load this plugin. See "Keybindings".
  event = string or list,      -- Specifies autocommand events which load this plugin.
  fn = string or list          -- Specifies functions which load this plugin.
  cond = string, function, or list of strings/functions,   -- Specifies a conditional test to load this plugin
  module = string or list      -- Specifies patterns (e.g. for string.match) of Lua module names which, when required, load this plugin
}
```

#### Checking plugin statuses
You can check whether or not a particular plugin is installed with `packer` as well as if that plugin is loaded.
To do this you can check for the plugin's name in the `packer_plugins` global table.
Plugins in this table are saved using only the last section of their names
e.g. `tpope/vim-fugitive` if installed will be under the key `vim-fugitive`.

```lua
if packer_plugins["vim-fugitive"] and packer_plugins["vim-fugitive"].loaded then
print("Vim fugitive is loaded")
-- other custom logic
end
```

#### Luarocks support

You may specify that a plugin requires one or more Luarocks packages using the `rocks` key. This key
takes either a string specifying the name of a package (e.g. `rocks=lpeg`), or a list specifying one or more packages.
Entries in the list may either be strings, a list of strings or a table --- the latter case is used to specify arguments such as the
particular version of a package.
all supported luarocks keys are allowed except: `tree` and `local`. Environment variables for the luarocks command can also be
specified using the `env` key which takes a table as the value as shown below.
```lua
rocks = {'lpeg', {'lua-cjson', version = '2.1.0'}}
use_rocks {'lua-cjson', 'lua-resty-http'}
use_rocks {'luaformatter', server = 'https://luarocks.org/dev'}
use_rocks {'openssl' env = {OPENSSL_DIR = "/path/to/dir"}}
```

Currently, `packer` only supports equality constraints on package versions.

`packer` also provides the function `packer.luarocks.install_commands()`, which creates the
`PackerRocks <cmd> <packages...>` command. `<cmd>` must be one of "install" or "remove";
`<packages...>` is one or more package names (currently, version restrictions are not supported with
this command). Running `PackerRocks` will install or remove the given packages. You can use this
command even if you don't use `packer` to manage your plugins. However, please note that (1)
packages installed through `PackerRocks` **will** be removed by calls to `packer.luarocks.clean()`
(unless they are also part of a `packer` plugin specification), and (2) you will need to manually
invoke `packer.luarocks.setup_paths` (or otherwise modify your `package.path`) to ensure that Neovim
can find the installed packages.

Finally, `packer` provides the function `packer.use_rocks`, which takes a string or table specifying
one or more Luarocks packages as in the `rocks` key. You can use this to ensure that `packer`
downloads and manages some rocks which you want to use, but which are not associated with any
particular plugin.

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

#### Sequencing

You may specify a loading order for plugins using the `after` key. This key can be a string or a
list (table).

If `after` is a string, it must be the name of another plugin managed by `packer` (e.g. the final segment of a plugin's path - for a Github plugin `FooBar/Baz`, the name would be just `Baz`). If `after` is a table, it must be a list of plugin names. If a plugin has an alias (i.e. uses the `as` key), this alias is its name.

The set of plugins specified in a plugin's `after` key must **all** be loaded before the plugin
using `after` will be loaded. For example, in the specification
```lua
  use {'FooBar/Baz', ft = 'bax'}
  use {'Something/Else', after = 'Baz'}
```
the plugin `Else` will only be loaded after the plugin `Baz`, which itself is only loaded for files
with `bax` filetype.

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

To generate the compiled code, call `packer.compile(path)`, where `path` is some file path on your
`runtimepath`, with a `.vim` extension. This will generate a blend of Lua and Vimscript to load and
configure all your lazy-loaded plugins (e.g. generating commands, autocommands, etc.) and save it to
`path`. Then, when you start vim, the file at `path` is loaded (because `path` must be on your
`runtimepath`), and lazy-loading works.

If `path` is not provided to `packer.compile`, the output file will default to the value of
`config.compile_path`.

The option `compile_on_sync`, which defaults to `true`, will run `packer.compile()` during
`packer.sync()`, if set to `true`. Note that otherwise, you **must** run `packer.compile` yourself
to generate the lazy-loader file!

## Debugging
`packer.nvim` logs to `stdpath(cache)/packer.nvim.log`. Looking at this file is usually a good start
if something isn't working as expected.

## Status
**tl;dr**: Beta. Things seem to work and most features are complete, but certainly not every edge
case has been tested. People willing to give it a try and report bugs/errors are very welcome!

- Basic package management works (i.e. installation, updating, cleaning, start/opt plugins,
  displaying results)
- Automatic generation of lazy-loading code works
- More testing is needed
- The code is messy and needs more cleanup and refactoring

## Current work-in-progress
- Playing with ideas to make manual compilation less necessary

## Contributors
Many thanks to those who have contributed to the project! PRs and issues are always welcome. This
list is infrequently updated; please feel free to bug me if you're not listed here and you would
like to be.

- @akinsho
- @nanotee
- @weilbith
- @Iron-E
- @tjdevries
- @numToStr
- @fsouza
- @gbrlsnchs
- @lewis6991
- @TimUntersberger
- @bfredl
- @sunjon
- @gwerbin
- @shadmansaleh
- @ur4ltz
- @EdenEast
