module FfiCtorUnloadable where

-- As FfiMemberUnloadable, for `getConstructor`: the (String) constructor
-- is fine, the (Missing) one alongside it is not, and the search
-- resolves both.  A `foreign constructor` names no class and no member,
-- so the warning lands on the declared name.
foreign
  data "probejar.PresentCtor" PC
  constructor mk : String -> PC
