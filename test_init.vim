nmap <space>q :qa!<cr>
packadd packer.nvim

lua << EOF
local packer = require('packer')
local use = packer.use

packer.init()
use { 'lervag/vimtex', setup = {'print("done")'} }
use { 'morhetz/gruvbox', ft = 'markdown', config = 'print("done2")' }
use { 'wbthomason/vim-nazgul', after = 'gruvbox' }
use { 'tpope/vim-unimpaired', after = 'vim-nazgul' }
use { 'tpope/vim-endwise', disable = false, requires = {{'tpope/vim-fugitive', keys = 'bb', config = 'print("yo")' }}}
use { 'dense-analysis/ale', disable = false, after = 'vimtex', requires = 'wbthomason/vim-nazgul' }

packer.compile('~/.config/nvim/plugin/packer_load.vim')
EOF

" colorscheme gruvbox
