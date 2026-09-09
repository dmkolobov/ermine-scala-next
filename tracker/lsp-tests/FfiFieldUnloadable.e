module FfiFieldUnloadable where

-- As FfiMemberUnloadable, for `getField`: `OK` is a plain String
-- constant, but the search also resolves the sibling `GONE`, whose type
-- is the absent class.
foreign
  value "probejar.PresentField" "OK" ok : String
