# SIG-3b REVIEW: the 19 signature corrections and the 7 callers they forced

Reviewer pass over the UNCOMMITTED tree of `ermine-scala-wt-fix` (`sig-fixes`, HEAD c0e027b),
against `SIG-3b-CORRECTIONS.md`, `briefs/brief-SIG-3b.md` and S3's patch
(`scratchpad/S3/17-corrections-VERIFIED.diff`). Nothing edited but this file and scratch; no
commits; no `git stash`; `find core -name '*.ei'` is 0 at the end.

## VERDICT: FIX-THEN-ADVANCE

Three documentation edits, no code or signature changes. The nineteen corrections and the
seven forced callers are HONEST and, with one named exception (`keyValueTabular`, which
cannot have a signature that is both honest and useful), MINIMAL. Where the implementer
disagreed with the brief (`unify1`) and with S3's patch (`monthsSince`/`daysSince`/
`daysUntil`) **the implementer is right and the brief was wrong**, and I reproduced both
findings independently, one of them with a self-contained witness.

The edits:

1. `core/examples/Time/README.md:57` -- "`daysUntil` under its new `Has out r`". The adopted
   signature is `Op r Int`; `Has out r` is the form this very stage measured as DISHONEST
   (§2 of the report, and my hand-check below). A shipped README must not name it as what
   ships. Replace with "under its collapsed result row `Op r Int` (the constant operand's row
   is `(||)`, so `out` can only be `r`)".
2. `core/examples/Lang/Corrected.e:80-81` -- the two comment lines describing the `unify1`
   call are written in the variables of the form the file's own header says was REFUSED
   (`r <- (h, f2, t)` / `r2 <- (h, f1, f2, t)`). Restate at the adopted variables:
   `r2 <- (f1, f2, p)` with f1 = `(|feedAmt|)`, f2 = `(|ledgerAmt|)`, p = `(|acctCode|)`;
   `r <- (f2, p, u)` with u = `(||)`. (This module is the positive control; its comment is
   the thing a reader checks the signature against.)
3. `core/src/main/resources/modules/Layout/Report/Keyed.e:65` -- the honest
   `keyValueTabular` constraint set forces `pid = cid = r = (||)`, so the two drilldown
   branches of the `case` are no longer callable: the one place in this stage where a shipped
   public function loses reachable functionality, and it is recorded in the report's §2 but
   nowhere a user of the module can see it. Add two comment lines at the signature
   (degenerate; the fix is four functions, one per branch) and promote §2's paragraph to a
   numbered §5 item or a tracker ticket. Nothing else about c5 changes.

None of the three is a correctness problem; they are the stale text that makes the next
reader mistrust the rest.

## The 26 bindings

"honest" = the oracle ACCEPTs every obligation the probe prints for it on my own fresh warn
sweep (`tracker/tools/sigcheck.py`, 314 decided), AND -- new at this review -- S3's real
Scala checker at its default `error` accepts it (§Gates 2). "minimal" = it excludes no call
the body could serve; five are derived by hand from the probe records below, the rest by the
same argument at a different arity.

| # | binding | honest? | minimal? | agrees with S3 patch? | note |
|---|---|---|---|---|---|
| c1 | `Relation/UnifyFields.e unify1` | yes (hand-derived) | **yes, exactly the weakest precondition** | **no -- and the implementer is right** | S3's/the brief's form refuses a SOUND call; witness below |
| c2 | `Relation.e partialLookup` | yes | yes (adds only `val # base`, which the body's `partialLookup'` row needs) | identical | |
| c3 | `DrilldownList.e cons_Bracket` | yes (hand-derived) | yes (Q **is** the wanteds' closure) | identical | refuses chained levels `(a,b),(b,c)`; the body cannot serve those either -- it would append `b` twice |
| c4 | `Keyed.e softRelation` | yes | yes (`k # v` is the wrapped function's own constraint) | identical | no corpus caller (checked: the 4 modules that import `Layout.Report.Keyed` call neither) |
| c5 | `Keyed.e keyValueTabular` | yes | **no -- degenerate** | identical (S3 agrees) | the 4 branch obligations force `pid = cid = r = (||)`; drilldown modes uncallable. Edit 3 |
| c6 | `Report/Relation.e cutoffs` | oracle NO VERDICT; **yes by hand** | yes (`r = p ⊎ (|cutoff|)` IS the body's row after `except {valueFld}`) | identical | behaviour-neutral for its callers: the old *runtime* row was already `p ⊎ cutoff`; only the declared row lied |
| c7 | `Report/Relation.e others` | yes (hand-derived) | yes | same shape, one member merged, plus the cascade S3's patch lacks | result `Relation r` -> `Relation s`: `private`, one caller, body's row IS `s` |
| c8a | `Wide/Helpers.e melt2` | yes (hand-derived) | yes (`r \| key` ⟺ the wanteds' `key # fa, fb, i`) | same constraint, house spelling | `r \| key` = `exists c. c <- (r, key)`, identical `.ei` |
| c8b | `melt3` | yes | yes | as c8a | |
| c8c | `melt4` | yes | yes | as c8a | exercised by `Wide/SurveyPanel.e` |
| c8d | `Wide/Signatures.e melt3Simple` | yes | yes | as c8a | body written out, so loading the module is the check |
| c9 | `Algebra/Signatures.e runningTotalFullViaWritten` | yes | yes (the 2 added facts are exactly the dropped obligations) | identical | the prose correction ("one direction checks") is the substance; it is right |
| c10 | `Time/Helpers.e dayCount` | yes | yes (`RUnion2` IS the three obligations) | identical | |
| c11 | `monthsBetween` | yes | yes | identical | |
| c12 | `monthsSince` | yes | **yes, forced** | **no -- and the implementer is right** | `prim : Op (\|\|) a` + `RUnion2` ⟹ `out = r`; `Has out r` is strictly too weak |
| c13 | `daysSince` | yes (hand-derived) | yes, forced | as c12 | |
| c14 | `daysUntil` | yes | yes, forced | as c12 | |
| c15 | `Time/Signatures.e yearFrac365Full` | yes | yes | not in the 17 (S3 §7.4 closure finding) | keeps the tautology `out <- (out)` deliberately -- it is what the compiler published |
| c16 | `yearFrac365Simple` | yes | yes | as c15 | |
| f1 | `Report/Relation.e cutoffDrilldownRel` (public) | yes | yes | **not in S3's patch** | strengthened from 1 to 4 private labels; no user row can contain `Layout.Report.Relation.cutoff*`, so no concrete call is lost -- a POLYMORPHIC third-party caller must restate the 4 labels (migration note) |
| f2 | `Algebra/Helpers.e translate` | yes | yes | not in S3's patch | `= partialLookup`, the same added fact at its own variables |
| f3 | `Time/Helpers.e yearFrac365` | yes | yes | not in S3's patch | newly VISIBLE to the check once c10 was honest |
| f4 | `yearFrac360` | yes | yes | not in S3's patch | |
| f5 | `yearsOn` | yes | yes, forced | not in S3's patch | collapsed like c14 (its body divides `daysUntil`) |
| f6 | `Time/Signatures.e yearFrac365Deduped` | yes | yes | not in S3's patch | |
| f7 | `SoftRelation.e:105 groupingDateDrilldown` | n/a (a CALL) | n/a | not in S3's patch | the old call built a `Row` with `dt` TWICE -- measured below |

Five hand-checks from the probe records (`sigcheck.py <sweep> <binding>`), derived
independently of the implementer's prose: `unify1`, `cons_Bracket`, `melt2`, `daysSince`,
`others`. All five discharge for every model of the givens, and for four the givens are the
exact closure of the wanteds -- nothing could be dropped, which is what "minimal" means here.

## `unify1` (brief item 1): the brief's recommendation is NOT minimal

The body is `join (rename f1 f2 (except {f2} r2)) r`. From the probe record

    Q: r <- (f2, p, u); r2 <- (f1, f2, p)
    W: r <- (_402,_403,_406); r <- (_403,_406); r2' <- (f1,_405); _401 <- (f2,_405); r2 <- (f2,r2')
    ds: _401 <- (_402,_403)

the solution is forced: `r2' = f1 ⊎ p`, `_405 = p`, `_401 = f2 ⊎ p`, `_402 = (||)` (W1 and W2
together), `_403 = f2 ⊎ p`, `_406 = u`. Reading it back: the body type-checks **iff**
`f1, f2 ⊆ r2` disjointly and `f2 ⊎ (r2∖f1∖f2) ⊆ r`. That is the adopted pair verbatim, so it
is the weakest honest signature -- not merely an honest one.

The brief's (and S3's) `r2 <- (h,f1,f2,t)` with `r <- (h,f2,t)` adds `u = (||)`: it forbids
`r` from carrying anything beyond `f2 ⊎ p`. `Customer360.e:207` is exactly that call --
`unify1_UF customerId crmAccountId (carry ...) (carry ...)`, the SAME relation twice, so
`r = r2` and `u = f1` -- and S3's patch even carries the comment "`unify1` has no caller in
the corpus", which is false. I reproduced the whole thing in scratch, two modules identical
but for the signature (`scratchpad/review-S3b/min/Uf{Ado,Rec}.e`, three columns, r = r2):

    UfAdo (adopted)  res0 : Relation (|acctCode, ledgerAmt, feedAmt|)
                            = Success(Map(acctCode -> StringT, ledgerAmt -> DoubleT, feedAmt -> DoubleT))
    UfRec (S3's)     UfRec.e:22:13: Row partitions are unsatisfiable at field 'UfRec.feedAmt':
                            a part contains it but the whole does not

So the call is sound -- it EVALUATES, and its runtime header is exactly the declared row --
and S3's form refuses it. S3's patch as written does not load the corpus.

`alg03` is still refused, message byte-identical, position 44:7 -> 49:7 from the five comment
lines inserted above the call; the file's recorded expectation is updated to match and no
other file records the old position (`Algebra/shouldfail/` has no `RESULTS.md`).

## `Op r Int` (brief item 2): honest, minimal, and FORCED

`prim : forall a. Primitive a => a -> Op (||) a` (Relation/Op.e:33) and
`RUnion2 t r s = exists ro so rs. t <- (ro,so,rs), r <- (ro,rs), s <- (so,rs)`
(Constraint.e:7). At `s = (||)`: `(||) <- (so,rs)` forces `so = rs = (||)`, hence `t = ro = r`
-- the result row is not merely contained in `r`, it IS `r`. The probe agrees: `daysSince` has
NO givens, wanteds `r <- (so,rs)`, `r <- (ro,so,rs)`, `ds: ro <- (), rs <- ()`, `so = r`.

So `Has out r` (S3's patch) is strictly too weak: with `out = r ⊎ c` and `c` chosen by the
caller, `out = r` is unprovable -- which is the REJECT the implementer measured under the
closure. And keeping `out` with `RUnion2 out r r1` would be unsound: the body cannot produce
a row wider than `r`. Nothing weaker or stronger is available.

No caller can want `out ⊋ r`: the only way an `Op` reaches a relation is `combine`, whose
`(exists o. RUnion2 t r c, r <- (s, o))` asks only that the op's row be PART of the relation's,
and rows of different ops meet through `RUnion2` in the operators, not through widening. I grepped every corpus use (`Time/CohortRetention.e`, `EmployeeTenure.e`,
`InterestAccrual.e`, `SubscriptionWaterfall.e`, `Time/Corrected.e`): all LOADED, and none
instantiates `out` at anything but the date column's row. **Not a behaviour change for any
caller.**

## `keyValueTabular` (item 3): useless as shipped for two of its four modes

`r2 = k⊎v⊎i` and `r2 = k⊎v⊎pid⊎cid⊎i` and `r2 = k⊎v⊎r⊎i` in one conjunction give
`pid ⊎ cid = (||)` and `r = (||)` by cancellation of a disjoint union, so any instantiation
with a concrete `pid`/`cid` label is unsatisfiable: the two `drilldown*` branches cannot be
called at all. Those calls were previously type-checkable AND runtime-sound (the branch is
chosen by the options value, each with its own honest constraints) -- so this correction does
remove reachable functionality.
It costs no corpus caller: the four modules that import `Layout.Report.Keyed`
(`PieChartLegendExample`, `Yahoo`, `ChartsExample`, `GridExample`) call neither
`keyValueTabular` nor `softRelation`, and the corpus's `keyValueTabular` calls are all
`Layout.Report`'s three-argument one. Shipping the honest signature is therefore right, but
it must be labelled at the signature and ticketed -- edit 3. I did not build an Options-level
witness for the refusal; the cancellation argument is exact and needs none.

## `cutoffs` (item 4): loads under `error`, honest by hand, decidable in principle

Confirmed on S3's real checker (see Gates 2): the module loads and prints

    warning: the signature-entailment check gave NO VERDICT at .../Layout/Report/Relation.e:98:3
    (sig cutoffs: ... the partition has a NON-EMPTY literal column set on its LEFT
    ((|Layout.Report.Relation.cutoff|)) ...); this signature is accepted on the shipped rules alone

with `largers`:82 and `small`:113 doing the same, on both sides. By hand the signature is
honest and minimal: the body is `aggregateByGroup ... {parentFld} valueFld rel` (row `p ⊎ v`),
then `[| cutoff = ... |]` (row `p ⊎ v ⊎ (|cutoff|)`), then `except {valueFld}` -- so the row
is `p ⊎ (|cutoff|)`, which is the corrected `r <- (p, (|cutoff|))` exactly. The old
`r <- (p, v, (|cutoff|))` was the lie, and note its callers are unaffected at RUN time: the
runtime row was already `p ⊎ cutoff`, only the type said otherwise.

Could it be made decidable? Not by rewriting the signature -- the unreadable member is in
`ds`, minted by the body's `filter_P (abs_Op valueFld >_P cutoff)`, and no signature can
remove it. But it is decidable in principle: `(|cutoff|) <- (rs, so)` says "for the label
class `cutoff`, exactly one of `rs`/`so` holds it; for every other class both are empty",
which the per-label one-hot model already expresses (it is the mirror of the `(||) <- (p1..pk)`
normalisation the oracle does at S3). The gap is in the decision procedure and the Lean
model, not in the signature; that is the shape of the fix, and it would also retire
`largers`/`small`'s pre-existing NO VERDICT.

## `SoftRelation.e` (item 5): the old call built a duplicate column

Run before and after, same JVM configuration, evaluating the three bindings the change
touches (`scratchpad/review-S3b/sr-head.log`, `sr-fix.log`):

    HEAD  groupingDateDrilldown : forall rout. (exists Has Has1 rout1. Has rout rout1, ...) => DrilldownList rout
          = DD [("pid","cid",IntT),("dt","dt",StringT)] (Row [cid, pid, dt, dt])
    fix   groupingDateDrilldown : DrilldownList (|dt, dtGroup, cid, pid|)
          = DD [("pid","cid",IntT),("dtGroup","dt",StringT)] (Row [cid, pid, dt, dtGroup])

So the old value carried `dt` TWICE in its `Row`, and its type was `forall rout` with the
three `Has` applications visible as ordinary type variables -- the survey's item c3 exactly.
**The honest `cons_Bracket` correctly refuses it**, and any honest signature would: the
obligations are `r' <- (r, f1)` and `rout <- (f2, r')`, which have no model at `f1 = f2`.

There IS a change in the example: `ddWordstats2` gains a `dtGroup` column (6 -> 7:
`Relation (|pid, dt, k, idc, cid, v|)` -> `(|pid, dt, k, idc, v, dtGroup, cid|)`) and the
second drilldown level is re-keyed `(dt, dt)` -> `(dtGroup, dt)`. No RENDERED output changed,
because the report cannot be rendered on this build on either side -- `drillDown2Example`
evaluates to `Report <function>` in both runs -- so there is no report diff to show, which is
what the implementer said and I confirm. Nothing imports `SoftRelation.e`, so the change is
contained. The new level (year, then date) is what a date drilldown means; I would keep it.

## `lookbackJoin` 8 -> 9 (item 6): the extra member is entailed -- hand-checked

From the final snapshots (`ei-base` vs `ei-fix2`), the nine are
`b <- (e,d,c1)`, `a <- (e,d)`, `r1 <- (c,r)`, `a <- (c2,r)`, `o <- (d,c1)`, `t <- (h,g,f)`,
`r1 <- (g,f)`, `r2 <- (h,g)`, **`t <- (r,h,c)`**; the base set is the same eight modulo
renaming (I matched them one by one: `c1->c`, `e->d`, `h->c1`, `f->e`, `d->h`, `c->g`, `g->f`,
`i->c2`). The ninth follows from three of the others: `r1 = c ⊎ r` and `r1 = g ⊎ f` give
`c ⊎ r = g ⊎ f`, so `t = h ⊎ g ⊎ f = h ⊎ c ⊎ r`, and the parts are pairwise disjoint
(`h # g⊎f` from the `t` partition, `c # r` from `r1`). A caller that satisfies the eight
therefore satisfies the nine; the published context grew but forbids nothing. Its three
corpus callers (`Time/Helpers.e`, `Time/ReadingHistory.e`, `Time/Signatures.e`) all still
LOAD. I did not hand-check `cutoffGroupedFldsPosNegRel'` at 39 -> 40 members; the brief did
not ask, and its module is the one where `cutoffs`/`others` moved, so the same reading is
plausible but unverified. The two `GridExample` chart bindings really are the same type:
they SWAP which of the pair spells the kind variable (`{a a1 b b1 c}` with `(sa: c)` against
`{a a1 b b1}` with bare `sa`) -- I read both interfaces on both sides.

## Gates I re-ran

1. **Corpus `--batch`, warn probe, this tree**: 168 outputs, **94 LOADED / 74 REJECTED / 0
   UNKNOWN**; oracle **314 decided: 306 ACCEPT / 5 REJECT / 3 NO VERDICT**, the 5 rejections
   exactly `shouldfail/sig01..sig05`, the 3 NO VERDICTs exactly `cutoffs`/`largers`/`small`.
   Joined per file against the implementer's control (`scratchpad/S3b/corpus-base`, 91/74/165):
   **no module changed verdict**, the only new files the three `Corrected.e`. Cost:
   propagation steps max 17794 (report: 17760), median 64, p90 536 -- id churn, not a change.
2. **NEW -- the REAL check, at its default `error`**, which the implementer explicitly could
   not run (§5 item 5). S3's compiled checker (`../ermine-scala-wt-sig`, read-only) with THIS
   tree's corrected `core/src/main/resources` first on the classpath, via `ERMINE_CP`:
   **89 LOADED / 79 REJECTED / 168**, and the per-file join against gate 1 shows the ONLY
   five modules that move are `shouldfail/sig01..sig05`, LOADED -> REJECTED, which is what
   the pins are for. Control with HEAD's resources and the same checker: the stdlib does not
   load at all -- `DrilldownList.e:20` (`sig cons_Bracket`) and `Relation.e:113`
   (`sig partialLookup`) are rejected, "Unable to load Prelude and Layout". So the
   corrections are exactly what makes the tree pass the enforced check, and none of the 25
   corrected signatures is rejected by it.
3. **`sbt core/testOnly *TestSigEntail *TestLetSignatures`**: 18 properties, **18 pass**,
   `[success]` in 37 s (9 let-signature + 9 pinned-hole).
4. **`ei-classify.py ei-base ei-fix2`** reproduces the report's numbers exactly: A 169 / B 172,
   only-in-B the three `Corrected` interfaces, 16 of 169 interfaces differ,
   `{identical 2119, order-only 69, other 29, alpha-equivalent 1}`.
5. **Line endings**: `Relation.e`, `Layout/Report/Keyed.e`, `Relation/UnifyFields.e` and
   `SoftRelation.e` still have CR on every line (CR count == line count, 279/279, 142/142,
   8/8, 117/117); `Layout/Report/Relation.e` and `DrilldownList.e` were LF at HEAD and still
   are. No wholesale conversion.

Not re-run (not asked for): `repl-smoke.sh`, the other three suites, the `.ei` sweep itself.

## For the merge

`SIG-3b-CORRECTIONS.md` §"For the merge" stands, plus: gate 2 means S3 need not discover
whether its checker accepts these corrections -- it does, at `error`, over the whole corpus.
Still owed after the merge is that run with S3's own `shouldfail/sig0*.e` edits in place, and
`TestSigEntailDiff` (engine vs `sigcheck.py`, signature by signature) -- the only gate that
catches the two implementations agreeing for the wrong reason.
