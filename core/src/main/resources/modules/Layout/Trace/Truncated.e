module Layout.Trace.Truncated where

-- A render trace's `truncated`: entries dropped by the 200-query cap or the
-- 256 KiB whole-trace cap, and whether every SQL text was first cut to 1 KiB.

data TraceTruncated = TraceTruncated { queries      : Int
                                     , sqlShortened : Bool }
