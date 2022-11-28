# packer.nvim

[![Gitter](https://badges.gitter.im/packer-nvim/community.svg)](https://gitter.im/packer-nvim/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

[`use-package`](https://github.com/jwiegley/use-package) inspired plugin/package management for
Neovim.

Have questions? Start a [discussion](https://github.com/wbthomason/packer.nvim/discussions).

Have a problem or idea? Make an [issue](https://github.com/wbthomason/packer.nvim/issues) or a [PR](https://github.com/wbthomason/packer.nvim/pulls).

**Packer is built on native packages. You may wish to read `:h packages` before continuing**

## Table of Contents
1. [Features](#features)
2. [Requirements](#requirements)
3. [Quickstart](#quickstart)
4. [Bootstrapping](#bootstrapping)
5. [Usage](#usage)
    1. [The startup function](#the-startup-function)
    2. [Custom Initialization](#custom-initialization)
    3. [Specifying Plugins](#specifying-plugins)
    4. [Performing plugin management operations](#performing-plugin-management-operations)
    5. [Extending packer](#extending-packer)
    6. [Compiling Lazy-Loaders](#compiling-lazy-loaders)
	7. [User autocommands](#user-autocommands)
	8. [Using a floating window](#using-a-floating-window)
6. [Profiling](#profiling)
7. [Debugging](#debugging)
8. [Compatibility and known issues](#compatibility-and-known-issues)
9. [Contributors](#contributors)

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
- You need to be running **Neovim v0.5.0+**
- If you are on Windows 10, you need developer mode enabled in order to use local plugins (creating
  symbolic links requires admin privileges on Windows - credit to @TimUntersberger for this note)

## Quickstart
To get started, first clone this repository to somewhere on your `packpath`, e.g.:

> Unix, Linux Installation

```shell
git clone --depth 1 https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim
```

If you use Arch Linux, there is also [an AUR
package](https://aur.archlinux.org/packages/nvim-packer-git/).

> Windows Powershell Installation

```shell
git clone https://github.com/wbthomason/packer.nvim "$env:LOCALAPPDATA\nvim-data\site\pack\packer\start\packer.nvim"
```

Then you can write your plugin specification in Lua, e.g. (in `~/.config/nvim/lua/plugins.lua`):

```lua
-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  -- Simple plugins can be specified as strings
  use 'rstacruz/vim-closer'

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
-- Regenerate compiled loader file
:PackerCompile

-- Remove any disabled or unused plugins
:PackerClean

-- Clean, then install missing plugins
:PackerInstall

-- Clean, then update and install plugins
-- supports the `--preview` flag as an optional first argument to preview updates
:PackerUpdate

-- Perform `PackerUpdate` and then `PackerCompile`
-- supports the `--preview` flag as an optional first argument to preview updates
:PackerSync

-- Show list of installed plugins
:PackerStatus

-- Loads opt plugin immediately
:PackerLoad completion-nvim ale
```

You can configure Neovim to automatically run `:PackerCompile` whenever `plugins.lua` is updated with
[an autocommand](https://neovim.io/doc/user/autocmd.html#:autocmd):

```
augroup packer_user_config
  autocmd!
  autocmd BufWritePost plugins.lua source <afile> | PackerCompile
augroup end
```

This autocommand can be placed in your `init.vim`, or any other startup file as per your setup.
Placing this in `plugins.lua` could look like this:

```lua
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])
```

## Bootstrapping

If you want to automatically install and set up `packer.nvim` on any machine you clone your configuration to,
add the following snippet (which is due to @Iron-E and @khuedoan) somewhere in your config **before** your first usage of `packer`:

```lua
local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

return require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  -- My plugins here
  -- use 'foo1/bar1.nvim'
  -- use 'foo2/bar2.nvim'

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if packer_bootstrap then
    require('packer').sync()
  end
end)
```

You can also use the following command (with `packer` bootstrapped) to have `packer` setup your
configuration (or simply run updates) and close once all operations are completed:

```sh
$ nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
```

## Usage

The above snippets give some examples of `packer` features and use. Examples include:

- My dotfiles:
  - [Specification file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/lua/plugins.lua)
  - [Loading file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/lua/plugins.lua)
  - [Generated lazy-loader file](https://github.com/wbthomason/dotfiles/blob/linux/neovim/.config/nvim/plugin/packer_compiled.lua)
- An example using the `startup` method: [tjdevries](https://github.com/tjdevries/config_manager/blob/master/xdg_config/nvim/lua/tj/plugins.lua)
    - Using this method, you do not require a "loading" file. You can simply `lua require('plugins')` from your `init.vim`

The following is a more in-depth explanation of `packer`'s features and use.

### The `startup` function
`packer` provides `packer.startup(spec)`, which is used in the above examples.

`startup` is a convenience function for simple setup and can be invoked as follows:
- `spec` can be a function: `packer.startup(function() use 'tjdevries/colorbuddy.vim' end)`
- `spec` can be a table with a function as its first element and config overrides as another element:
  `packer.startup({function() use 'tjdevries/colorbuddy.vim' end, config = { ... }})`
- `spec` can be a table with a table of plugin specifications as its first element, config overrides as another element, and optional rock specifications as another element:
 `packer.startup({{'tjdevries/colorbuddy.vim'}, config = { ... }, rocks = { ... }})`

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
  snapshot = nil, -- Name of the snapshot you would like to load at startup
  snapshot_path = join_paths(stdpath 'cache', 'packer.nvim'), -- Default save directory for snapshots
  package_root   = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  compile_path = util.join_paths(vim.fn.stdpath('config'), 'plugin', 'packer_compiled.lua'),
  plugin_package = 'packer', -- The default package for plugins
  max_jobs = nil, -- Limit the number of simultaneous jobs. nil means no limit
  auto_clean = true, -- During sync(), remove unused plugins
  compile_on_sync = true, -- During sync(), run packer.compile()
  disable_commands = false, -- Disable creating commands
  opt_default = false, -- Default to using opt (as opposed to start) plugins
  transitive_opt = true, -- Make dependencies of opt plugins also opt by default
  transitive_disable = true, -- Automatically disable dependencies of disabled plugins
  auto_reload_compiled = true, -- Automatically reload the compiled file after creating it.
  preview_updates = false, -- If true, always preview updates before choosing which plugins to update, same as `PackerUpdate --preview`.
  git = {
    cmd = 'git', -- The base command for git operations
    subcommands = { -- Format strings for git subcommands
      update         = 'pull --ff-only --progress --rebase=false',
      install        = 'clone --depth %i --no-single-branch --progress',
      fetch          = 'fetch --depth 999999 --progress',
      checkout       = 'checkout %s --',
      update_branch  = 'merge --ff-only @{u}',
      current_branch = 'branch --show-current',
      diff           = 'log --color=never --pretty=format:FMT --no-show-signature HEAD@{1}...HEAD',
      diff_fmt       = '%%h %%s (%%cr)',
      get_rev        = 'rev-parse --short HEAD',
      get_msg        = 'log --color=never --pretty=format:FMT --no-show-signature HEAD -n 1',
      submodules     = 'submodule update --init --recursive --progress'
    },
    depth = 1, -- Git clone depth
    clone_timeout = 60, -- Timeout, in seconds, for git clones
    default_url_format = 'https://github.com/%s' -- Lua format string used for "aaa/bbb" style plugins
  },
  display = {
    non_interactive = false, -- If true, disable display windows for all operations
    compact = false, -- If true, fold updates results by default
    open_fn  = nil, -- An optional function to open a window for packer's display
    open_cmd = '65vnew \\[packer\\]', -- An optional command to open a window for packer's display
    working_sym = '⟳', -- The symbol for a plugin being installed/updated
    error_sym = '✗', -- The symbol for a plugin with an error in installation/updating
    done_sym = '✓', -- The symbol for a plugin which has completed installation/updating
    removed_sym = '-', -- The symbol for an unused plugin which was removed
    moved_sym = '→', -- The symbol for a plugin which was moved (e.g. from opt to start)
    header_sym = '━', -- The symbol for the header line in packer's display
    show_all_info = true, -- Should packer show all update details automatically?
    prompt_border = 'double', -- Border style of prompt popups.
    keybindings = { -- Keybindings for the display window
      quit = 'q',
      toggle_update = 'u', -- only in preview
      continue = 'c', -- only in preview
      toggle_info = '<CR>',
      diff = 'd',
      prompt_revert = 'r',
    }
  },
  luarocks = {
    python_cmd = 'python' -- Set the python command to use for running hererocks
  },
  log = { level = 'warn' }, -- The default print log level. One of: "trace", "debug", "info", "warn", "error", "fatal".
  profile = {
    enable = false,
    threshold = 1, -- integer in milliseconds, plugins which load faster than this won't be shown in profile output
  },
  autoremove = false, -- Remove disabled or unused plugins without prompting the user
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
  bufread = boolean,           -- Manually specifying if a plugin needs BufRead after being loaded
  branch = string,             -- Specifies a git branch to use
  tag = string,                -- Specifies a git tag to use. Supports '*' for "latest tag"
  commit = string,             -- Specifies a git commit to use
  lock = boolean,              -- Skip updating this plugin in updates/syncs. Still cleans.
  run = string, function, or table, -- Post-update/install hook. See "update/install hooks".
  requires = string or list,   -- Specifies plugin dependencies. See "dependencies".
  rocks = string or list,      -- Specifies Luarocks dependencies for the plugin
  config = string or function, -- Specifies code to run after this plugin is loaded.
  -- The setup key implies opt = true
  setup = string or function,  -- Specifies code to run before this plugin is loaded. The code is ran even if
                               -- the plugin is waiting for other conditions (ft, cond...) to be met.
  -- The following keys all imply lazy-loading and imply opt = true
  cmd = string or list,        -- Specifies commands which load this plugin. Can be an autocmd pattern.
  ft = string or list,         -- Specifies filetypes which load this plugin.
  keys = string or list,       -- Specifies maps which load this plugin. See "Keybindings".
  event = string or list,      -- Specifies autocommand events which load this plugin.
  fn = string or list          -- Specifies functions which load this plugin.
  cond = string, function, or list of strings/functions,   -- Specifies a conditional test to load this plugin
  module = string or list      -- Specifies Lua module names for require. When requiring a string which starts
                               -- with one of these module names, the plugin will be loaded.
  module_pattern = string/list -- Specifies Lua pattern of Lua module names for require. When
                               -- requiring a string which matches one of these patterns, the plugin will be loaded.
}
```

For the `cmd` option, the command may be a full command, or an autocommand pattern. If the command contains any
non-alphanumeric characters, it is assumed to be a pattern, and instead of creating a stub command, it creates
a CmdUndefined autocmd to load the plugin when a command that matches the pattern is invoked.

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
**NOTE:** this table is only available *after* `packer_compiled.vim` is loaded so cannot be used till *after* plugins
have been loaded.

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
- `packer.update(opts, plugins)`: First argument can be a table specifying options, such as `{preview_updates = true}` to preview potential changes before updating (same as `PackerUpdate --preview`).
- `packer.clean()`: Remove any disabled or no longer managed plugins
- `packer.sync(plugins)`: Perform a `clean` followed by an `update`.
- `packer.sync(opts, plugins)`: Can take same optional options as `update`.
- `packer.compile(path)`: Compile lazy-loader code and save to `path`.
- `packer.snapshot(snapshot_name, ...)`: Creates a snapshot file that will live under `config.snapshot_path/<snapshot_name>`. If `snapshot_name` is an absolute path, then that will be the location where the snapshot will be taken. Optionally, a list of plugins name can be provided to selectively choose the plugins to snapshot.
- `packer.rollback(snapshot_name, ...)`: Rollback plugins status a snapshot file that will live under `config.snapshot_path/<snapshot_name>`. If `snapshot_name` is an absolute path, then that will be the location where the snapshot will be taken. Optionally, a list of plugins name can be provided to selectively choose which plugins to revert.
- `packer.delete(snapshot_name)`: Deletes a snapshot file under `config.snapshot_path/<snapshot_name>`. If `snapshot_name` is an absolute path, then that will be the location where the snapshot will be deleted.

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

**NOTE:** If you use a function value for `config` or `setup` keys in any plugin specifications, it
**must not** have any upvalues (i.e. captures). We currently use Lua's `string.dump` to compile
config/setup functions to bytecode, which has this limitation.
Additionally, if functions are given for these keys, the functions will be passed the plugin
name and information table as arguments.

### User autocommands
`packer` runs most of its operations asyncronously. If you would like to implement automations that
require knowing when the operations are complete, you can use the following `User` autocmds (see
`:help User` for more info on how to use):

- `PackerComplete`: Fires after install, update, clean, and sync asynchronous operations finish.
- `PackerCompileDone`: Fires after compiling (see [the section on compilation](#compiling-lazy-loaders))

### Using a floating window
You can configure Packer to use a floating window for command outputs by passing a utility
function to `packer`'s config:
```lua
packer.startup({function()
  -- Your plugins here
end,
config = {
  display = {
    open_fn = require('packer.util').float,
  }
}})
```

By default, this floating window will show doubled borders. If you want to customize the window
appearance, you can pass a configuration to `float`, which is the same configuration that would be
passed to `nvim_open_win`:
```lua
packer.startup({function()
  -- Your plugins here
end,
config = {
  display = {
    open_fn = function()
      return require('packer.util').float({ border = 'single' })
    end
  }
}})
```

## Profiling
Packer has built in functionality that can allow you to profile the time taken loading your plugins.
In order to use this functionality you must either enable profiling in your config, or pass in an argument
when running packer compile.

#### Setup via config
```lua
config = {
  profile = {
    enable = true,
    threshold = 1 -- the amount in ms that a plugin's load time must be over for it to be included in the profile
  }
}
```

#### Using the packer compile command
```vim
:PackerCompile profile=true
" or
:PackerCompile profile=false
```

#### Profiling usage
This will rebuild your `packer_compiled.vim` with profiling code included. In order to visualise the output of the profile
restart your neovim and run `PackerProfile`. This will open a window with the output of your profiling.

## Debugging
`packer.nvim` logs to `stdpath(cache)/packer.nvim.log`. Looking at this file is usually a good start
if something isn't working as expected.

## Compatibility and known issues

- **2021-07-31:** If you're on macOS, note that building Neovim with the version of `luv` from `homebrew` [will cause any `packer` command to crash](https://github.com/wbthomason/packer.nvim/issues/496#issuecomment-890371022). More about this issue at [neovim/neovim#15054](https://github.com/neovim/neovim/issues/15054).
- **2021-07-28:** `packer` will now highlight commits/plugin names with potentially breaking changes
  (determined by looking for `breaking change` or `breaking_change`, case insensitive, in the update
  commit bodies and headers) as `WarningMsg` in the status window.
- **2021-06-06**: Your Neovim must include https://github.com/neovim/neovim/pull/14659; `packer` uses the `noautocmd` key.
- **2021-04-19**: `packer` now provides built-in profiling for your config via the `packer_compiled`
  file. Take a look at [the docs](#profiling) for more information!
- **2021-02-18**: Having trouble with Luarocks on macOS? See [this issue](https://github.com/wbthomason/packer.nvim/issues/180).
- **2021-01-19**: Basic Luarocks support has landed! Use the `rocks` key with a string or table to specify packages to install.
- **2020-12-10**: The `disable_commands` configuration flag now affects non-`startup` use as well. This means that, by default, `packer` will create commands for basic operations for you.
- **2020-11-13**: There is now a default implementation for a floating window `open_fn` in `packer.util`.
- **2020-09-04:** Due to changes to the Neovim `extmark` api (see: https://github.com/neovim/neovim/commit/3853276d9cacc99a2698117e904475dbf7033383), users will need to update to a version of Neovim **after** the aforementioned PR was merged. There are currently shims around the changed functions which should maintain support for earlier versions of Neovim, but these are intended to be temporary and will be removed by **2020-10-04**. Therefore Packer will not work with Neovim v0.4.4, which was released before the `extmark` change.

## Contributors
Many thanks to those who have contributed to the project! PRs and issues are always welcome. This
list is infrequently updated; please feel free to bug me if you're not listed here and you would
like to be.

- [@akinsho](https://github.com/akinsho)
- [@nanotee](https://github.com/nanotee)
- [@weilbith](https://github.com/weilbith)
- [@Iron-E](https://github.com/Iron-E)
- [@tjdevries](https://github.com/tjdevries)
- [@numToStr](https://github.com/numToStr)
- [@fsouza](https://github.com/fsouza)
- [@gbrlsnchs](https://github.com/gbrlsnchs)
- [@lewis6991](https://github.com/lewis6991)
- [@TimUntersberger](https://github.com/TimUntersberger)
- [@bfredl](https://github.com/bfredl)
- [@sunjon](https://github.com/sunjon)
- [@gwerbin](https://github.com/gwerbin)
- [@shadmansaleh](https://github.com/shadmansaleh)
- [@ur4ltz](https://github.com/ur4ltz)
- [@EdenEast](https://github.com/EdenEast)
- [@khuedoan](https://github.com/khuedoan)
- [@kevinhwang91](https://github.com/kevinhwang91)
- [@runiq](https://github.com/runiq)
- [@n3wborn](https://github.com/n3wborn)
- [@deathlyfrantic](https://github.com/deathlyfrantic)
- [@doctoromer](https://github.com/doctoromer)
- [@elianiva](https://github.com/elianiva)
- [@dundargoc](https://github.com/dundargoc)
- [@jdelkins](https://github.com/jdelkins)
- [@dsully](https://github.com/dsully)
