# packer.nvim
An experimental Neovim plugin manager in Lua for speed and ease of development, with some neat
lazy-loading features.

## Status
**tl;dr**: Beta. Things seem to work and most features are complete, but certainly not every edge
case has been tested. People willing to give it a try and report bugs/errors are very welcome! You
can find a (stupid) example of use in `test_init.vim`.

- Basic package management seems to work (i.e. installation, updating, cleaning, start/opt plugins,
  displaying results)
- Automatic generation of lazy-loading code seems to work
- More testing is needed
- The code is rather messy and needs cleanup and refactoring

## Current work
- Luarocks support
- Usage documentation

## TODO
- Allow multiple packages
- Optimizations?
