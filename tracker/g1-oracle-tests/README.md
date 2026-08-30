Hand-built .ei fixture pairs validating the G1 comparator both ways
(tracker/LSP-ROADMAP.md item 1.1): every `diff-*` pair MUST flag as
different (a pass-everything comparator dies here), every `eq-*` pair
must NOT (the solver's known churn shapes must stay green).

Note eq-reordered-forall: quantifier list order is EQUAL by design —
qtyp parses interface text through Forall.mk, which canonicalizes binder
order (Type.scala:340-345), so rendered order is presentation, not
semantics; nothing downstream observes internal binder order (no explicit
type application, and interface loading re-parses through the same
normalizer).

Known groups-layer gap (measured 2026-08-30): 5/129 modules — Field,
Native.List, String, Type.Eq, Relation — cannot be re-parsed outside
their original incremental scope construction under ANY own-global
filtering variant (terms-only fixes Type.Eq but Multiple-fixity/shadow
errors return elsewhere; cons filtering breaks Type.Eq's own type ops;
Relation's [| |] sugar needs Relation.rename in scope while parsing
Relation itself).  G1Groups records them as deterministic PARSE-ERROR
lines so they diff cleanly; their resolution oracle is the
occurrence->def-site differential (roadmap item 4.2).  This difficulty is
itself evidence for the Stage-1 split: parsing is not separable from
scope replay in the old pipeline.
