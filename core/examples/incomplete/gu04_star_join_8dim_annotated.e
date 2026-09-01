module Incomplete.Gu04 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- 4 of 4: the escape hatch.

   THE SCENARIO.  Gu03's eight-dimension order-line view -- BYTE-FOR-BYTE the
   same definition -- with the type signature written out.  The signature says
   nothing inference did not already know: per dimension, the row accumulated so
   far splits into a join key and a carried remainder, the dimension splits into
   that same key and its attributes, and the result is the three of them.  That
   is what `join` means, restated eight times.

   WHAT A COMPETENT USER EXPECTS.  Writing down the answer should not change
   the answer, and adding 24 constraints for the checker to verify should be, if
   anything, more work than leaving them out.

   WHAT ACTUALLY HAPPENS, one JVM per file, nothing else running:

       dimensions   inferred (Gu01/02/03)   checked against this signature
       6            11.21s                  0.10s
       7            329.58s                 0.36s
       8            killed                  1.97s

   Three orders of magnitude at seven dimensions, from adding information the
   compiler had already computed.

   THE INCOMPLETENESS.  This is the shape of the defect, stated as sharply as it
   can be: the checking problem for these constraints is easy, the inference
   problem for the SAME constraints is not, and the gap is not a small constant.
   The advice "add a signature" is measured to work -- but it requires the user
   to already know the 24-constraint partition system inference was searching
   for.  Gu05 shows what happens when they write down the OBVIOUS signature
   instead.

   Note that the annotated column is still growing (0.10 -> 0.36 -> 1.97, ratios
   3.6x and 5.5x).  The signature moves the wall; it does not remove it.
-}

import Prelude
import Relation
import Syntax.Relation

wideOrderLines : forall rel fact dimProduct dimRegion dimChannel dimCalendar dimCustomer dimCurrency dimTax dimPromo rowProduct rowRegion rowChannel rowCalendar rowCustomer rowCurrency rowTax rowPromo.
  ( exists keyProduct attProduct carryProduct keyRegion attRegion carryRegion keyChannel attChannel carryChannel keyCalendar attCalendar carryCalendar keyCustomer attCustomer carryCustomer keyCurrency attCurrency carryCurrency keyTax attTax carryTax keyPromo attPromo carryPromo.
    fact <- (carryProduct, keyProduct),
    dimProduct <- (attProduct, keyProduct),
    rowProduct <- (carryProduct, keyProduct, attProduct),
    rowProduct <- (carryRegion, keyRegion),
    dimRegion <- (attRegion, keyRegion),
    rowRegion <- (carryRegion, keyRegion, attRegion),
    rowRegion <- (carryChannel, keyChannel),
    dimChannel <- (attChannel, keyChannel),
    rowChannel <- (carryChannel, keyChannel, attChannel),
    rowChannel <- (carryCalendar, keyCalendar),
    dimCalendar <- (attCalendar, keyCalendar),
    rowCalendar <- (carryCalendar, keyCalendar, attCalendar),
    rowCalendar <- (carryCustomer, keyCustomer),
    dimCustomer <- (attCustomer, keyCustomer),
    rowCustomer <- (carryCustomer, keyCustomer, attCustomer),
    rowCustomer <- (carryCurrency, keyCurrency),
    dimCurrency <- (attCurrency, keyCurrency),
    rowCurrency <- (carryCurrency, keyCurrency, attCurrency),
    rowCurrency <- (carryTax, keyTax),
    dimTax <- (attTax, keyTax),
    rowTax <- (carryTax, keyTax, attTax),
    rowTax <- (carryPromo, keyPromo),
    dimPromo <- (attPromo, keyPromo),
    rowPromo <- (carryPromo, keyPromo, attPromo),
    RelationalComb rel )
  => rel fact -> rel dimProduct -> rel dimRegion -> rel dimChannel -> rel dimCalendar -> rel dimCustomer -> rel dimCurrency -> rel dimTax -> rel dimPromo -> rel rowPromo
wideOrderLines orderLine productDim regionDim channelDim calendarDim customerDim currencyDim taxDim promoDim =
  orderLine ** productDim ** regionDim ** channelDim ** calendarDim ** customerDim ** currencyDim ** taxDim ** promoDim
