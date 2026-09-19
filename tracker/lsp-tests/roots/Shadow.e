module Shadow where

-- STALENESS step 1 fixture, the ORDER pin: before the first server boots the
-- smoke writes a second `Shadow` into the classpath copy
-- (core/target/<scala>/classes/modules/Shadow.e, `which` on its line 4).  A
-- server whose roots are ahead of the classpath finds THIS file, so `which`
-- navigates here; the roots-free second server finds the classpath one.

which : Int
which = 1
