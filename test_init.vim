packadd packer.nvim

lua << EOF
local packer = require('packer')
use = packer.use

packer.init()

use { 'morhetz/gruvbox' }
use { 'wbthomason/vim-nazgul' }
use { 'tpope/vim-unimpaired' }
use { 'tpope/vim-endwise', disable = false }

packer.sync()
EOF

" colorscheme gruvbox
