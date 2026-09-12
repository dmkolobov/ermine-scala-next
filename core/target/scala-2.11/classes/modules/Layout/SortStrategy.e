module Layout.SortStrategy where

{- Relative sort direction implied by a particular Presentation.

By *relative*, I mean that *when you see SortDirection or
SortStrategy, you cannot use it to specify how to sort data.  Really.*
Suppose I have a relation

    xs = relation [{x = 1}, {x = 42}, {x = 3}]

`sortBy reverse x` *does not* mean order these such that you'll see
[1, 3, 42]; it also does not mean you'll see [42, 3, 1].  In fact, you
may even see [1, 3, 42]; by itself, a SortStrategy says nothing about
how to sort data.

However, if the API specifies *something else* that sorts data, such
as a `Sort` from Relation.Sort, then the strategy `sortBy reverse x`
means that however *that other thing* says to sort it, do that, but
reverse it.  So if that other sort specifies that [1, 42, 3] is the
correct order, `sortBy reverse x` causes [3, 42, 1] to result.

`forward` does nothing.
-}

import List as List
import Native
import Layout.Presentation

infixr 5 ++

foreign
  -- | Description of whether an Op reverses the sort order of its
  -- underlying relational field.
  data "com.clarifi.reporting.writers.SortDirection" SortDirection
  value "com.clarifi.reporting.writers.SortDirection$Forward$" "MODULE$"
      forward : SortDirection
  value "com.clarifi.reporting.writers.SortDirection$Reverse$" "MODULE$"
      reverse : SortDirection

data SortStrategy r = SortStrategy (List (SortDirection, List String))

-- Sort using all fields in `pr`, over one particular order.
sortBy : AsPresentation pr => SortDirection -> pr r a -> SortStrategy r
sortBy dir pr = SortStrategy [(dir, columnsUsed (asPresentation pr))]_List

-- Combine sorts, sorting by `left`, then `right`.
(++) : forall r s t. (t <- (r, s))
          => SortStrategy r -> SortStrategy s -> SortStrategy t
(++) (SortStrategy left) (SortStrategy right) =
  SortStrategy (left ++_List right)
