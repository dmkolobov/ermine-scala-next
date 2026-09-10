module FixCrlf where

import Maybe using isJust

-- A CRLF file (142 of the 161 stdlib modules are CRLF): every inserted
-- line has to carry the buffer's own terminator, not a lone \n.
crlfValue = 42

useJust = isJust
