module Layout.PresentationTest where

import Function
import List
import Native.List using toList#
import Relation.Op as Op
import Layout.Presentation

apr = asPresentation

field x : Int

asPreses = [apr x,
            -- TODO apr 42,
            apr (x +_Op prim_Op 1),
            apr (basic . col_Op $ x)]

primAsPreses = toList# asPreses
