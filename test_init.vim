set packpath^=~/.local/share/nvim/site

lua << EOF
local p = require('plague')
use = p.use
sync = p.sync
configure = p.configure

use { 'morhetz/gruvbox', ensure = true }
use { 'wbthomason/vim-nazgul', ensure = true }
use { 'tpope/vim-unimpaired', ensure = true }

sync()

EOF

set runtimepath
set packpath
" colorscheme gruvbox
