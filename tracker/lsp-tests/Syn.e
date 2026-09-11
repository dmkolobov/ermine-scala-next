module Syn where

import SynSrc as W

-- TICKET E10(5).  This file reaches `Widget` only through a synonym of its
-- OWN: `ModuleScope.canonicalTypes` holds `Widget_W` and nothing else, so the
-- add-signature action used to refuse `boxed` a signature the file can write.
type Widget = Widget_W

-- A PARAMETERISED synonym licenses nothing.  `type Boxed a = Box_W a` says how
-- to write `Box x`; it does not make the bare constructor `Box` writable, so
-- `wrapped` stays refused.  The narrow rule is the sound one.
type Boxed a = Box_W a

boxed = MkWidget_W

wrapped = MkBox_W MkWidget_W
