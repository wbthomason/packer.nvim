-- Modules loaded here will not be cleared and reloaded by Busted.
-- Busted started doing this to help provide more isolation.
local global_helpers = require('test.helpers')

-- Bypoass CI behaviour logic
global_helpers.isCI = function(_)
  return false
end

require('test.functional.helpers')(nil)

