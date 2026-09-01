import Mathlib.Data.Finset.Card
example (s t : Finset ℕ) (h : Disjoint s t) : (s ∪ t).card = s.card + t.card :=
  Finset.card_union_of_disjoint h
