module Aliasing where
-- Post-G1 semantics (roadmap D2): a local binding shadows only its own
-- spelling.  A reference through a module-affixed alias (id_F) still
-- reaches the import even when the plain name is shadowed — the fused
-- pipeline refused these ("would capture references ... in scope under
-- multiple names"); the split pipeline gives them plain Haskell scoping.
import Prelude
import Function as F

viaAlias = id_F 5 where id x = 99
combined = id_F 3 + id 4 where id q = q + 90
