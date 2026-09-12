module Layout.Report.Keyed.Syntax where

{- This module is meant to be used in tandem with Layout.Report.Keyed;
it provides the := and []_Opt syntax for setting options. -}

import Function

-- | Setting options.
infix 0 :=
(:=) : forall a b c. (a -> b -> c) -> a -> b -> c
(:=) = id

-- | Grouping option settings together.
empty_Bracket_Opt : forall a. a -> a
cons_Bracket_Opt : forall a b c. (b -> c) -> (a -> b) -> a -> c
empty_Bracket_Opt = id
cons_Bracket_Opt = (.)

-- | An alias for []_Opt, or just using defaults.
defaults : forall a. a -> a
defaults = []_Opt
