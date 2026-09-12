module Shouldfail.Control08 where

-- MUST LOAD. Control for sig01 / sig02 / sig03 / sig04: the same bodies under HONEST
-- signatures, in the four spellings a fix must keep accepting -- explicit partition,
-- `Has`, a let-bound signature, and a two-row library helper (the consRow shape) whose
-- wanted mentions BOTH signature variables.  If a control stops loading, the corresponding
-- should-fail case is no longer evidence of anything.
--
-- Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945.
--
-- MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, backport/SIG-ENTAIL-2.11.md): IT LOADS.
-- At the default `-Dermine.sigEntail=error`, `:load` prints
--     Importing module 'Shouldfail.Control08'
-- and nothing else -- no warning, no NO VERDICT.  The warn-mode sweep records all six of
-- its signatures (`sig healthWith`, `sig healthHas`, `sig bumpWith`, `sig f`, `sig tagged`,
-- `ann <annot>`), every one `lit` (alpha-equivalent to a given up to the fresh remainder),
-- and the oracle ACCEPTS all six.  The outcome is identical under `off` and under `error`.
--
-- ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the fused Scala-2 grammar,
-- not by building:
--   * SYNTAX: every construct below is in this branch's grammar.  `Has` comes from
--     `Constraint.e` (`type Has a b = exists c. a <- (b, c)`) via `export Constraint` in
--     Prelude; `modify`, `cons` and `!` come via `export Field`.  `Prelude.e`,
--     `Constraint.e`, `Field.e` and `Record.e` here are byte-identical to the scala3
--     branch's.  Lambdas are written `(h -> ...)`; no `\x ->` form exists in this grammar.
--   * The EXPLICIT-FORALL annotation in `ok5` parses: `TypeParsers.annot` (:351-355) is an
--     optional `some` quantifier followed by `typ` (:298), which itself takes an optional
--     `forall` (`uQuant`, :294).
--   * sig03 is NOT the LET-1 case on this branch, so `localWith` below is a real control
--     for it: the fused `let` production collects sig statements
--     (`TermParsers.let` :224-243 -> `Statement.gatherBindings` :284-289 ->
--     `checkBindings` :306), so a let-bound signature becomes an ExplicitBinding and
--     reaches the same `sig` site a top-level one does.  `localWith` is therefore the
--     honest let-bound signature that the check must keep accepting.
--   * The seven stdlib signature corrections ARE applied on this branch
--     (backport/CORRECTIONS.md).

import Prelude

field position : Double
field health   : Int
field mana     : Nullable Int

healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int
healthWith r = r ! health

healthHas : forall r. Has r (|health|) => {..r} -> Int
healthHas r = r ! health

bumpWith : forall r t. r <- ((|health|), t) => {..r} -> {..r}
bumpWith = modify health (h -> h + 1)

localWith = let f : forall r t. r <- ((|health|), t) => {..r} -> Int
                f r = r ! health
            in f { position = 1.0, health = 10 }

tagged : forall t r. t <- ((|health|), r) => Int -> {..r} -> {..t}
tagged h rec = cons health h rec

ok1 = healthWith { position = 1.0, health = 10, mana = Some 3 }
ok2 = healthHas  { position = 1.0, health = 10 }
ok3 = bumpWith   { position = 1.0, health = 10 }
ok4 = tagged 3   { position = 1.0 }

-- the annotation site (sig05's twin), honest
ok5 = ((r -> r ! health) : forall r t. r <- ((|health|), t) => {..r} -> Int) { position = 1.0, health = 10 }
