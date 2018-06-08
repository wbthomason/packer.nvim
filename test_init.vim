lua << EOF
local p = require('plague')
use = p.use
sync = p.sync
configure = p.configure

use { 'wbthomason/vim-nazgul', ensure = true }

sync()

EOF
