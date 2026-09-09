-- S5 review, Q-1: the C12 tautology deletion, seen through the REPL.
--
-- `-Dermine.tautoDelete` (DEFAULT ON, stage S5.1) deletes a published partition
-- that says nothing: `r <- (t1, .., tk)` with `r` a row the caller fixes, every
-- `ti` a distinct existential carrying no concrete label and occurring in no
-- other published constraint.  It fires ONLY from the generalisation that
-- publishes a module's signatures, so the thing to guard is that `:type` -- which
-- is inference, not a cached interface (the smoke suite runs with
-- `-Dermine.useInterface=false`) -- answers the SHORTENED form, i.e. the form the
-- compiler writes into the `.ei`.
--
-- Every `xSig` is an EXPLICIT binding and publishes its written signature
-- verbatim; every `x` is INFERRED from it and therefore goes through
-- `Subst.mkSimplified`.  So each pair is a before/after in one module.
--
-- Types here are kept SHORT on purpose: `tracker/tools/repl-smoke.sh` drops
-- indented continuation lines (`grep -v '^  '`, which is how it discards
-- `:import`'s module listing), so a wrapped answer would compare only its first
-- line.  The real `Layout.Scan` signatures are checked at full width by the LSP
-- hover case in `tracker/tools/lsp-client.py` instead.
module Tauto where

import Prelude

-- DELETED: C12's shape exactly.  `h`, `t` existential, no concrete label,
-- occurring in no other constraint, `r` universal.
posSig : r <- (h, t) => Relation r -> Relation r
posSig x = x
pos = posSig

-- DELETED: the general k = 3 form, not just C12's two parts.
pos3Sig : r <- (a, b, c) => Relation r -> Relation r
pos3Sig x = x
pos3 = pos3Sig

-- KEPT (near miss): a CONCRETE label among the parts still says `foo` is in `r`.
concSig : r <- (h, (|foo|)) => Relation r -> Relation r
concSig x = x
conc = concSig

-- KEPT (near miss): a part occurring in ANOTHER published row constraint.
sharedSig : (r <- (h, t), s <- (h, u)) => Relation r -> Relation s -> Relation r
sharedSig x y = x
shared = sharedSig
