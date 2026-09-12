# SIG-3b: the dishonest row signatures, corrected and verified against the oracle

Worktree `ermine-scala-wt-fix`, branch `sig-fixes` from 9a0fd02. No commits. The entailment
CHECK itself is S3's (`sig-entail`); every verdict below is the S1 warn probe
(`-Dermine.sigEntail=warn`) feeding S2's decision procedure, `tracker/tools/sigcheck.py`.
A signature is HONEST here iff the oracle ACCEPTS every row obligation the probe prints for
it, read under the closure of SIG-2-DESIGN.md (a3).

**Headline.** Same worktree, same configuration, one corpus sweep per side
(`corpus-run.sh --batch` with the probe on, `tracker/tools/sigcheck.py` over the records):

| | signatures decided | ACCEPT | REJECT | NO VERDICT |
|---|---|---|---|---|
| HEAD (control) | 310 | 284 | **24** | 2 |
| corrected | 314 | 306 | **5** | 3 |

The 24 are the 19 dishonest signatures plus the 5 pinned negatives
(`shouldfail/sig01..sig05`, which MUST be rejected); the 5 that remain are exactly those
pins. `284 / 24 / 2` on the control is byte-identical to the count S3 measured with the
shipped Scala engine (`SIG-3-IMPL.md` §7.5), so the two sides of this A/B are the same
population S3's checker saw. Corpus load verdicts: **91 LOADED / 74 REJECTED / 165** before,
**94 / 74 / 168** after -- no module changed verdict; the three new modules are the
exercising ones.

## 0. The oracle

`tracker/tools/sigcheck.py` is **S3's committed version** (`../ermine-scala-wt-sig`), which
fixes two bugs in S2's scratch copy -- the (a3) closure must be a fixpoint in `F`, and
`(||) <- (p1..pk)` must be normalised to `pi <- ()` -- plus three S3b conveniences that do
not touch the decision procedure: a single FILE is accepted as well as a sweep directory, a
record is found anywhere in a line (a logger stamp may precede it), and the dumps print
variable NAMES with the ids, the `ds` set and the obligations' source positions, which is
what makes a rejection readable while a signature is being fixed.

    python3 tracker/tools/sigcheck.py <S2-scratch>/corpus-warn
    signatures decided: 309   {'ACCEPT': 288, 'REJECT': 21}

On the S1 records it reproduces S2's **21 rejections byte-identically** (`diff` against
`verdicts.txt` is empty), before and after the S3b edits. It cannot find more on that input:
S1's probe printed nine columns, and the closure needs the tenth.

**The tenth column.** To verify the closure-only items on this branch the probe had to print
`ds`, the skolem-free half of the residual, as `sig-entail`'s does. Two lines:
`SigEntail.probe(site, qs, rs, ds)` renders it as a tenth column, and `Subst.scala:547`
passes it. That is instrumentation, identical in shape to S3's, and it is held OUT of the
A/B swap so both sides of every measurement below print the same record format. Without it
the oracle decides a strictly smaller system and four of the corrected signatures come out
ACCEPT that the check rejects (§2, `Time`).

## 1. The nineteen

`Q` is the given set. "verdict" is `sigcheck.py` on a fresh warn sweep of the corrected tree,
under the closure. Every row is measured.

### Standard library (7) -- `core/src/main/resources/modules/`

| # | binding | before | after | the obligation it discharges | verdict |
|---|---|---|---|---|---|
| c1 | `Relation/UnifyFields.e:6` `unify1` | `(r <- (h,f,t), r2 <- (h,f2,t))` | `(r2 <- (f1,f2,p), r <- (f2,p,u))` | `r2\f2 <- (f1, _)`: `f1` occurred in NO given, so `rename f1 f2` renamed a column that need not be there (`Failure(Renaming non-existent attribute)`) | ACCEPT |
| c2 | `Relation.e:107` `partialLookup` | `(RelationalComb rel, PrimitiveAtom a, kv <- (key,val), r <- (key,base))` | `+ exists r2 . r2 <- (key,val,base)` | `r2' <- (base, val, key)`, `partialLookup'`'s own constraint: nothing made `val` disjoint from `base`, and at `val ⊆ base` the body's row is UNSATISFIABLE | ACCEPT |
| c3 | `DrilldownList.e:18` `cons_Bracket` | `(Has rout f1, Has rout f2, Has rout r)` | `(rout <- (f1, f2, r))` | `_ <- (r, f1)`, `rout <- (f2, _)`: the three `Has` were an applied type VARIABLE (`Constraint` is not imported), and `Has` gives membership where `append` needs disjointness | ACCEPT |
| c4 | `Layout/Report/Keyed.e:52` `softRelation` | `(AsPresentation prk, AsPresentation prvd)` | `+ exists o . o <- (k, v)` | `o' <- (k, v)` -- the constraint the wrapped `Layout.Report.softRelation` (Report.e:635-642) declares and the wrapper dropped | ACCEPT |
| c5 | `Layout/Report/Keyed.e:65` `keyValueTabular` | `(Relational rel, Relational rel2)` | `+ exists o . r2 <- (k,v,i), i <- (label,o), r2 <- (k,v,pid,cid,i), r2 <- (k,v,r,i)` | all seven, one group per branch of the `case`: `keyValueTabular_R`'s `r <- (k,v,i)`, `pivotTabular'_R`'s permutation, `drilldownKeyValueTable_R`'s `r <- (k,v,p,c,i)` + `i <- (lbl,o)`, `drilldownKeyValueTable2_R`'s `r2 <- (k,v,r,i)` + two existential consequences | ACCEPT (honest but degenerate -- §3) |
| c6 | `Layout/Report/Relation.e:87` `cutoffs` | `r <- (p, v, (\|cutoff\|))` | `r <- (p, (\|cutoff\|))` | `r'' <- (r, v)`: the body ends `\|> except {valueFld}`, so the declared result kept a column the body removes and the wanted was unsatisfiable for every non-empty `v` | NO VERDICT (§3) |
| c7 | `Layout/Report/Relation.e:177` `others` | `forall .. s r ..`, `(s <- (p,v,d,c), l <- ((\|cutoff\|), s))`, result `Relation r` | `forall .. s ..`, `(exists l . s <- (p,v,d,c), l <- ((\|cutoff,cutoffCount,cutoffChild,cutoffGroup\|), s))`, result `Relation s` | `r' <- ((\|cutoffCount\|), p)` and its two siblings, and `r' <- ((\|3 cutoffs\|), r)`: the result row was in no constraint at all, and nothing said the three private `cutoff*` columns were outside `p`. The body's row IS `s`, which is what its one caller uses | ACCEPT |

### Examples (12) -- `core/examples/`

| # | binding | before | after | the obligation it discharges | verdict |
|---|---|---|---|---|---|
| c8a | `Wide/Helpers.e:325` `melt2` | `(r <- (i,fa,fb), out <- (i,key,val), RelationalComb rel)` | `+ r \| key` | `t' <- (fb, out\val)`, i.e. `key # fa` and `key # fb`: the givens make `key` disjoint from `i` and `val` only | ACCEPT |
| c8b | `Wide/Helpers.e:335` `melt3` | as above, arity 3 | `+ r \| key` | the same, three times | ACCEPT |
| c8c | `Wide/Helpers.e:346` `melt4` | as above, arity 4 | `+ r \| key` | the same, four times | ACCEPT |
| c8d | `Wide/Signatures.e:250` `melt3Simple` | as `melt3` | `+ r \| key` | the same, three times | ACCEPT |
| c9 | `Algebra/Signatures.e:275` `runningTotalFullViaWritten` | the 21 inferred constraints | `+ exists rest . r <- (a,b,rest), d <- (c,r)` | `r <- (rest,b,a)` and `d <- (c,r)`: `a`/`b` (the ordering and amount columns) occur in none of the 21, and the second needs `c = m`, which nothing forces | ACCEPT |
| c10 | `Time/Helpers.e:312` `dayCount` | `forall r r1 out.` (none) | `RUnion2 out r r1 =>` | `out <- (ro,so,rs)`, `r <- (ro,rs)`, `r1 <- (so,rs)` -- literally `RUnion2`'s expansion: the result row is the UNION of the operands' | ACCEPT |
| c11 | `Time/Helpers.e:327` `monthsBetween` | `forall r r1 out.` (none) | `RUnion2 out r r1 =>` | the same three | ACCEPT |
| c12 | `Time/Helpers.e:333` `monthsSince` | `forall r out.` (none) | `forall r.` … `-> Op r Int` | the same three with the other operand a CONSTANT: `ds` carries `(\|\|) <- (ro, rs)`, which forces both remainders empty and **pins `out` to `r`** | ACCEPT |
| c13 | `Time/Helpers.e:337` `daysSince` | `forall r out.` (none) | `forall r.` … `-> Op r Int` | the same | ACCEPT |
| c14 | `Time/Helpers.e:343` `daysUntil` | `forall r out.` (none) | `forall r.` … `-> Op r Int` | the mirror (`so`, `rs` forced empty) | ACCEPT |
| c15 | `Time/Signatures.e:151` `yearFrac365Full` | `(out <- (out), PrimitiveTemporal a)` | `+ RUnion2 out r r1` | S3's closure finding: `out` is the union of the two date columns' rows, and the compiler's published residual for this body is the tautology `out <- (out)` and nothing else | ACCEPT |
| c16 | `Time/Signatures.e:160` `yearFrac365Simple` | (none) | `RUnion2 out r r1 =>` | the same | ACCEPT |

### Seven more the nineteen FORCE (cascade), all measured

An honest callee makes a dishonest caller, and a corrected signature makes an obligation
VISIBLE that the check never saw. Each of these was ACCEPT (or invisible) before and became
REJECT the moment its callee was corrected; each is the minimal restatement at its own
variables. They are corrections, not scope creep: without them the enforced check refuses
the module.

| binding | forced by | after | verdict |
|---|---|---|---|
| `Layout/Report/Relation.e:55` `cutoffDrilldownRel` (public) | c7 -- `others` now asks for the three private `cutoff*` labels outside `s`, and this is its only caller | `l <- ((\|cutoff,cutoffCount,cutoffChild,cutoffGroup\|), s)` | ACCEPT |
| `Algebra/Helpers.e:184` `translate` (`= partialLookup`) | c2 | `+ exists r2 . r2 <- (key, val, o)` | ACCEPT |
| `Time/Helpers.e:317` `yearFrac365` | c10 (its body divides `dayCount`) -- newly VISIBLE to the check, and rejected | `RUnion2 out r r1 =>` | ACCEPT |
| `Time/Helpers.e:354` `yearFrac360` | c10 | `RUnion2 out r r1 =>` | ACCEPT |
| `Time/Helpers.e:348` `yearsOn` | c14 (its body divides `daysUntil`) | `forall r.` … `-> Op r Double` | ACCEPT |
| `Time/Signatures.e:156` `yearFrac365Deduped` (`= yearFrac365Full`) | c15 | `+ RUnion2 out r r1` | ACCEPT |
| `core/examples/SoftRelation.e:105` `groupingDateDrilldown` | c3 -- NOT a signature: a CALL the honest `cons_Bracket` refuses | `[(pid, cid), (dtGroup, dt)]_DDL` (a new `dtGroup` column) instead of `[(pid, cid), (dt, dt)]_DDL` | the module LOADS again |

`SoftRelation.e` is the only place a correction cost a corpus module a change of BEHAVIOUR,
and it is a fourteenth witness for the survey's list -- a static one: `(dt, dt)`, one
drilldown level whose parent and child are the SAME column, type-checked only because
`cons_Bracket`'s three `Has` constraints asserted nothing. The body appends both to the
list's row, so the honest `rout <- (f1, f2, r)` refuses it
(`Fields appear twice in row: SoftRelation.dt`), as would ANY honest signature for that body:
the obligations are `_ <- (r, f1)` and `rout <- (f2, _)`, and at `f1 = f2` they have no
model. What it did at run time was not measured (this file's reports cannot be rendered on
this build); the `Row` it built had `dt` in it twice. The date level is keyed on `(dtGroup, dt)` -- year, then
date -- which is what a date drilldown means. Caught by `sbt core/testOnly *TestErmine*`,
not by the corpus sweep: `SoftRelation.e` is in the sweep and was REJECTED there too, but
the test named it first.

## 2. Reconciliation with S3's patch, and where I differ

S3 had written and verified the 17 before its scope was cut
(`scratchpad/S3/17-corrections-VERIFIED.diff`, `SIG-3-IMPL.md` §9). Thirteen of my
corrections are that patch's, arrived at independently and character-for-character where the
spelling is forced:

* **identical**: c2 `partialLookup` (`exists r2 . r2 <- (key,val,base)`), c3 `cons_Bracket`,
  c4 `softRelation`, c5 `keyValueTabular` (same four constraints, parts in a different
  order), c6 `cutoffs`, c9 `runningTotalFullViaWritten`, c10/c11 `dayCount`/`monthsBetween`.
* **same constraint, house spelling**: c8a-d, the melts. S3 writes
  `exists w. …, w <- (r, key)`; I write `r | key`, which is that constraint's alias in
  `Constraint.e` (`type (|) a b = exists c. c <- (a, b)`) and the spelling
  `Lang/TypesAndRows.e`'s row-vocabulary table teaches. The published `.ei` is the same
  either way: `exists (c: rho). c <- (r, key)`.
* **same shape, one more member**: c7 `others`. S3 keeps `l <- ((|cutoff|), s)` and adds
  `exists o. o <- ((|cutoffChild,cutoffCount,cutoffGroup|), s)`; I merge the four labels into
  one constraint and bind the dangling `l` with `exists`. Logically identical. But S3's
  patch stops there, and `others`' only caller then has to supply the new fact: with
  `cutoffDrilldownRel` untouched the oracle REJECTS it (measured), so the module would not
  load under the enforced check. The cascade row above is the rest of that correction.

**Where I disagree, with the measurement.**

**c1 `unify1`: I did not take the recommended form, because the caller it assumes does not
exist does exist.** The brief and S3 both use `r <- (h,f2,t)` with `r2 <- (h,f1,f2,t)` ("no
caller exists"). That IS honest -- the oracle accepts it -- and it refuses
`Algebra/Customer360.e:207`:

    selfAliasSemiJoin = unify1_UF customerId crmAccountId
                                  (carry customerId crmAccountId crm)
                                  (carry customerId crmAccountId crm)

Both operands are the same relation, so `r = r2`; `r2 = h+f1+f2+t` with `r = h+f2+t` then
forces `f1 = (||)`, and `f1` is the concrete label `customerId`. Measured, with the
recommended form in place:

    core/examples/Algebra/Customer360.e:207:21: Row partitions are unsatisfiable at field
    'Algebra.Customer360.customerId': the whole contains it but no part does

That call is sound -- it evaluates to a relation with exactly its declared header -- so a
correction that refuses it is too strong. What the body needs is only: `f1` and `f2` are
columns of `r2`; the rest of `r2` (`p`) and `f2` are columns of `r`; `r` may hold more (`u`).
That is `(r2 <- (f1,f2,p), r <- (f2,p,u))`, which is WEAKER than the old signature where the
old one was too strong (the operands no longer have to agree outside `f2 + p`) and stronger
where it was too weak (`f1` is now a column of the second operand). `Customer360.e` loads,
and `Algebra/shouldfail/alg03_unify_cross_schema.e` -- the negative control for the same
function -- is still REJECTED, at the same position, with a byte-identical message.

**c12-c14 `monthsSince`/`daysSince`/`daysUntil`: `Has out r` is NOT enough, and S3's patch
has it.** I wrote `Has out r` first, for the same reason S3 did (a constant operand
contributes no columns, so the result row need only CONTAIN the column's row), and the oracle
accepted it under `W = rs`. Under the closure it is REJECTED, with the witness "a label in
`c`" -- `Has out r` is `exists c. out <- (r, c)`, and the `ds` half carries `(||) <- (ro, rs)`
(the `prim` operand's empty row), which forces `ro = rs = (||)` and pins `out` to `r` exactly.
So the honest signature does not quantify over `out` at all: `Op r Int`. Measured both ways,
on this tree:

| | `Has out r` | `Op r Int` |
|---|---|---|
| oracle, `W = rs` (9-column records) | ACCEPT | ACCEPT |
| oracle, under the closure (10-column) | **REJECT** ×3 | ACCEPT ×3 |

S3's §9 says the 17 were verified under the default `error`, and its §7.1 dates the closure
fix after that; this is the one place where the earlier verification and the shipped closure
disagree, and it is worth a line in S3's own record. The collapsed form costs callers
nothing: `combine`'s `op s a` asks only that `s` be part of the relation's row, so a caller
whose relation is wider instantiates nothing -- `Time/CohortRetention.e`,
`SubscriptionWaterfall.e` and `EmployeeTenure.e` all still load.

**c5 `keyValueTabular` is honest but DEGENERATE, and the function should be split.** Its four
`case` branches place incompatible demands on one row: `r2 = k⊎v⊎i` (two branches),
`r2 = k⊎v⊎pid⊎cid⊎i` (drilldown) and `r2 = k⊎v⊎r⊎i` (drilldown-2). All four obligations are
real, so an honest signature must imply all four -- and together they force
`pid = cid = r = (||)`. The set is satisfiable (the module loads, the oracle accepts), but
the two drilldown branches are then callable only at empty column rows, i.e. not callable.
The wrapper cannot have a signature that is both honest and useful; it has to become four
functions, one per branch, which is the shape `Layout.Report` already has. That is an API
change the brief excludes, so what ships is the honest signature and this paragraph is the
ticket. S3 reached the same conclusion independently (§9 row 5). There is no corpus call
either way.

**c6 `cutoffs` ends at NO VERDICT, not ACCEPT.** Its refutation is gone -- the unsatisfiable
`r'' <- (r, v)` cannot arise once the declared result stops keeping `v` -- but the oracle
will not certify it, because the `ds` half of its residual carries
`(|cutoff|) <- (rs, so)`: a NON-EMPTY concrete left-hand side, which neither the Lean model
nor the engine can state, and a dropped obligation forbids ACCEPT. Its two siblings
`largers` and `small` are NO VERDICT on BOTH sides for the same reason (they are the 2 of the
control's `284 / 24 / 2`), so the correction moves `cutoffs` from REJECT into the company of
its own siblings rather than out of the module's pre-existing blind spot. Under the shipped
check that is a warn-and-accept, so the module loads; what it means is that this one
correction is verified by the load and by hand, not by the oracle.

**c7 `others`' result row.** The minimal way to discharge `r' <- (3 cutoffs, r)` with `r`
unconstrained would be to declare the three labels disjoint from `r` and leave `r` free. I
fixed the signature to the body (`Relation s`) for the reason the brief gives for `cutoffs`:
the body returns `p+v+d+c = s`, its only caller uses it at `s`
(`union (largers ...) (others ...)`), and a free result row that merely avoids three private
labels is a type no caller can use.

## 3. Gates

All numbers are from this worktree at the final tree, with the `ds`-printing probe on both
sides.

### 3.1 The oracle over the corpus, control vs corrected

    ERMINE_JAVA_OPTS="-Dermine.sigEntail=warn" tracker/tools/corpus-run.sh --batch <out>
    python3 tracker/tools/sigcheck.py <out>

| | decided | ACCEPT | REJECT | NO VERDICT | rejections |
|---|---|---|---|---|---|
| control (HEAD) | 310 | 284 | 24 | 2 | the 19 + the 5 pins |
| corrected | 314 | 306 | 5 | 3 | the 5 pins only |

Cost: propagation steps max 24109 (control) / 17760 (corrected), median 64, p90 527/536;
Q-models at one label max 256/101; label classes max 7. Rejection-set difference: exactly the
19 removed, **nothing added**. Four signatures are decided on the corrected side only --
`Time.Helpers.yearFrac365`, `.yearFrac360`, `.yearsOn` and `Time.Signatures.yearFrac365Deduped`
-- because a corrected callee makes their obligations reach the check; all four ACCEPT after
their own (forced) corrections.

### 3.2 Corpus `--batch` load verdicts

Re-measured on the FINAL tree (every prose edit included): 168 outputs,
`94 LOADED / 74 REJECTED / 0 UNKNOWN`, oracle `314 decided: 306 ACCEPT / 5 REJECT / 3 NO
VERDICT`, `verdict CHANGED` empty against the control.

| | LOADED | REJECTED | UNKNOWN | files |
|---|---|---|---|---|
| control | 91 | 74 | 0 | 165 |
| corrected | 94 | 74 | 0 | 168 |

**No module changed verdict** (`cmp-corpus.sh`, join on the per-file verdict). The three new
files are `Lang/Corrected.e`, `Wide/Corrected.e`, `Time/Corrected.e`, all LOADED. Ten
REJECTED modules print a different CLAUSE of the same refutation at the same field and
position, and one (`inf02_substitution_chain.e`) names a different field of the same
partition: that is the load-order variation `corpus-run.sh`'s header and ticket B6 record
(adding three files to a batch shifts every later module's session), not a consequence of
the corrections -- none of the ten calls a corrected function except `alg03`, whose position
moved 44:7 -> 49:7 because I added five lines of comment to it, and whose recorded expected
diagnostic is updated in the file.

### 3.3 `.ei`: the published interfaces that move

`tracker/tools/ei-diff.sh`'s sweep, restricted to the modules that can be affected and run
PER FILE on both sides (the stdlib boot set plus the three modules it does not load, then
every corpus module that calls a corrected function -- 24 files, 27 runs), classified by
`tracker/tools/ei-classify.py`. Per file, not `--batch`: the corrected side has three more
files, and that script's own header says a chunk shift makes a different module fall out.

    tracker/tools/ei-classify.py <base-snapshot> <corrected-snapshot>
    interfaces: A 169  B 172  only-in-A -  only-in-B ['Lang_Corrected', 'Time_Corrected', 'Wide_Corrected']
    == 16 of 169 interfaces differ
    == bindings by verdict: {'identical': 2119, 'order-only': 69, 'other': 29, 'alpha-equivalent': 1}

**29 bindings' published types moved. 25 of them are the corrections** -- the 19, plus the six
cascaded signatures (`cutoffDrilldownRel`, `translate`, `yearFrac365`, `yearFrac360`,
`yearsOn`, `yearFrac365Deduped`). No published type became WEAKER: `ei-classify.py` reports
no `concrete->polymorphic`, and every correction either adds a constraint to a context or
narrows a declared result row to the row the body already returned.

**The other four are not corrections**, and they are the id-shift churn a changed minting
order always produces:

| binding | what moved | reading |
|---|---|---|
| `Relation.lookbackJoin` | constraints 8 -> 9 | the extra member is `t <- (r, h, c)`, which the other eight entail (`r1 = c ⊎ r = g ⊎ f` and `t = h ⊎ g ⊎ f`) -- hand-checked |
| `Report.Relation.cutoffGroupedFldsPosNegRel'` | constraints 39 -> 40 | the same shape, in the module where `cutoffs`/`others` changed; not hand-checked at 40 members |
| `GridExample.stackedAreaChart`, `.stackedBarChart` | a KIND variable named or not (`{a a1 b b1 c}` with `(sa: c)` against `{a a1 b b1}` with bare `sa`, and the two bindings swap) | the same type; `ei-classify.py`'s bijection search does not cover kind variables, so it lands in `other` |

"One further consequence the remaining members already entail" is the effect
`Algebra/Signatures.e`'s own prose records for stage S3's simplifier
(`S3-SIMPLIFY.md` §6): `mkSimplified` is order-sensitive, and adding a constraint to
`Relation.e` moves every later id.

The corrected bindings' published contexts, as a caller now sees them:

    unify1 : … (r <- (f2, p, u), r2 <- (f1, f2, p)) => …
    partialLookup : … (exists (r2: rho). r2 <- (key, val, base), …) => …
    cons_Bracket : … rout <- (f1, f2, r) => …
    softRelation : … (exists (o: rho). …, o <- (k, v)) => …
    cutoffs : … (exists (l: rho) (e: rho). r <- ((|…cutoff|), p), …) => …
    others : … (exists (l: rho). l <- ((|…cutoff, …cutoffCount, …cutoffChild, …cutoffGroup|), s), …) => … -> Relation s
    melt2 : … (exists (c: rho). c <- (r, key), …) => …
    dayCount : … (exists (ro: rho) (so: rho) (rs: rho). out <- (ro, so, rs), r <- (ro, rs), r1 <- (so, rs)) => …
    daysSince : forall (r: rho). Date -> Field r Date -> Op r Int

Callers whose inferred types moved, by module: `Algebra/Helpers.e` (`translate`, a
correction; five more order-only), `Algebra/Signatures.e` (`runningTotalFullViaWritten`; four
order-only), `Time/Helpers.e` (the eight corrected; `orElseNum` order-only),
`Time/Signatures.e` (the three `yearFrac365*`; six order-only), `Wide/Helpers.e` and
`Wide/Signatures.e` (the melts; eleven each order-only), `Relation.e` (`partialLookup` +
`lookbackJoin`; five order-only), `Relation/Op.e`, `Relation_Predicate`, `Present/Helpers.e`,
`GridExample.e` (all order-only bar the two kind-variable ones), and the four other corrected
stdlib modules.

### 3.4 `repl-smoke.sh`

`tracker/repl-classpath.txt` regenerated from this worktree first (and `git checkout`ed back
at the end). **PASS 8/8, 66 checks** -- aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12,
relations 6, scoping 4, smoke 23, tauto 5. 0 FAIL.

### 3.5 `sbt core/testOnly`

    sbt -batch -J-Xmx3g 'core/testOnly *TestErmine* *TestSigEntail *TestLetSignatures \
                         *TestInterfaceConcreteRow *TestTolerantRead'

**63 properties, 63 pass, `[success]` in 230 s** on the corrected tree, and 63/63 on the
control (re-run at HEAD through the same file swap, so the suite is known green on both
sides; the control run predates the probe's tenth column, which no test reads -- every
test runs at the default `off`). `Interface concrete row` collects "199 of 249 interfaces
re-print byte-identically", as on the control (248 there: the corrected tree publishes one
more interface).

The one intermediate failure worth recording: before the `SoftRelation.e` fix,
`TestErmineModules.all interesting examples load` and
`TestTolerantRead.strict and tolerant agree` both failed, and both named
`core/examples/SoftRelation.e:97:25: Fields appear twice in row: SoftRelation.dt`. That is
how the `(dt, dt)` drilldown level was found; nothing else in either suite moved.

## 4. Exercising the corrections

Three new corpus modules -- one per group that can resolve the library it needs. A module in
`Lang/` cannot import `Wide.Helpers` (`corpus-run.sh` hoists only its OWN group's library),
so one module cannot call both `melt2` and `dayCount`; and a module that sorts before its
group's other files cannot import them either (`Wide/Corrected.e` had
`import Wide.Signatures` and was `Module not found` in the batch until it was dropped).
Each header says which correction each binding exercises; each is in its group's README
table.

| module | binding | correction exercised | evaluates to |
|---|---|---|---|
| `core/examples/Lang/Corrected.e` | `sameMeasure` | c1 `unify1`, with `f1 = feedAmt` a real column of the second operand | `Success(Map(acctCode, ledgerAmt))` |
| | `canonical` | c2 `partialLookup`, `canonCode` outside `netAmt` | `Success(Map(netAmt, acctCode))` |
| | `levels` | c3 `cons_Bracket`, three levels over six disjoint columns | the `DD` value, six-column `Row` |
| | `smallOthers` | c6 + c7 + the `cutoffDrilldownRel` cascade | `Success(HashMap(nodeValue, nodeGroup, nodeParent, nodeChild))` |
| `core/examples/Wide/Corrected.e` | `long`, `long3` | c8a `melt2` and c8b `melt3` at a key column outside the input | `Success(…(storeId, month, measure, amount))` |
| `core/examples/Time/Corrected.e` | `withSpan` | c10 `dayCount` under `RUnion2 out r r1`, both dates real columns | `Success(…(contractId, startDay, endDay, spanDays))` |
| | `withTenure` | c14 `daysUntil` in its collapsed form `Op r Int` | `Success(…(contractId, startDay, endDay, tenureDays))` |

Every binding prints a `Success` whose runtime header is exactly its declared row -- the
contrast with SIG-1-REVIEW's witnesses for the same functions
(`Failure(Renaming non-existent attribute)`, `Failure(Cannot union columns …)`, a relation
whose header lacks a declared column) is the point of the modules.

**Not exercised by a new module**, and why: c8c `melt4` and c8d `melt3Simple` are exercised
where they already were (`Wide/SurveyPanel.e`; and `Wide/Signatures.e` itself, whose body is
written out, so loading it IS the check); c9 `runningTotalFullViaWritten` and c15/c16 are
`Signatures.e` bindings of the same kind; c11-c13 are the same two shapes as c10/c14;
c4 `softRelation` and c5 `keyValueTabular` have **no** positive control -- they are
presentation-valued, have no corpus call, and c5's honest signature is degenerate (§2).

## 4b. TICKET: `Layout.Report.Keyed.keyValueTabular` is honest but degenerate

The honest signature forces `pid = cid = r = (||)` (cancellation across its four branches), so
the two drilldown branches of the wrapper are uncallable. No corpus caller exists, so shipping is
defensible, but it is a real API regression for an outside caller. Fix = split the wrapper into
one function per branch, each with the original's own row constraint. Recorded at the signature
(`Keyed.e:65`) and here; not S3's work.

## 5. What the oracle could NOT verify -- for S3 to re-run

1. **`Report.Relation.cutoffs`, `largers`, `small` are NO VERDICT** (§3.1): a `ds` member
   with a non-empty concrete left-hand side (`(|cutoff|) <- (rs, so)`, from
   `filter_P (abs_Op valueFld >_P cutoff)`) is outside the model. `largers` and `small` are
   NO VERDICT on both sides; `cutoffs` joins them. The shipped check warns and accepts, so
   the modules load, but c6 is verified by the load and by hand, not by the oracle.
2. **An ACCEPT is not a guarantee that a CALLER type-checks.** The oracle decides the
   signature's own judgement over the constraints the probe prints; constraints purely among
   existentials are invisible to it, and they are exactly what refuted the recommended
   `unify1` form at `Customer360.e:207`. Every correction here is therefore gated on loading
   as well: the module, its callers, and the corpus.
3. **Class constraints are out of scope** (S1 §8 item 6): they are checked at generalisation.
4. **Signatures whose obligations never reach `subsumeType`** are invisible to probe and
   oracle alike -- an ACCEPT means "nothing dishonest reached the check", not "provably
   honest". The four signatures that became visible when their callees were corrected (§3.1)
   are the measurement of how big that gap can be.
5. **I did not run S3's Scala checker.** Everything above is the oracle plus loading. When
   the branches merge, S3 should re-run the real check over this tree -- particularly c12-c14
   (where its own patch and the closure disagree, §2), c6 (the NO VERDICT), and the seven
   cascaded corrections, which its patch does not contain.
6. **`sbt core/copyResources`** is needed before `bin/ermine` sees a stdlib edit (the probe
   reads `core/target/scala-3.3.8/classes/modules`); every measurement here was taken after
   a sync. `Relation.e`, `Layout/Report/Keyed.e`, `UnifyFields.e` and `SoftRelation.e` are
   CRLF files and were edited byte-wise.

## 6. Files changed

    core/src/main/resources/modules/Relation.e                       +4  -1   c2
    core/src/main/resources/modules/Relation/UnifyFields.e           +1  -1   c1
    core/src/main/resources/modules/DrilldownList.e                  +1  -1   c3
    core/src/main/resources/modules/Layout/Report/Keyed.e            +9  -2   c4 c5
    core/src/main/resources/modules/Layout/Report/Relation.e         +7  -6   c6 c7 + cutoffDrilldownRel
    core/examples/Time/Helpers.e                                     +33 -15  c10-c14 + 3 cascaded + prose
    core/examples/Time/Signatures.e                                  +17 -3   c15 c16 + yearFrac365Deduped + prose
    core/examples/Wide/Helpers.e                                     +14 -7   c8a-c + prose
    core/examples/Wide/Signatures.e                                  +9  -4   c8d + prose
    core/examples/Algebra/Signatures.e                               +33 -10  c9 + the corrected claim
    core/examples/Algebra/Helpers.e                                  +29 -5   translate + the `unify1` note
    core/examples/SoftRelation.e                                     +11 -3   the (dt, dt) drilldown level
    core/examples/Algebra/Customer360.e                              +14 -5   prose (the `unify1` finding)
    core/examples/Algebra/shouldfail/alg03_...e                      +16 -11  prose + the recorded diagnostic
    core/examples/Present/DrilldownExplorer.e                        +12 -5   prose (the `Has rout` paragraphs)
    core/examples/Present/AtomicAndRelation.e                        +8  -2   prose (the cutoff constraint)
    core/examples/Time/InterestAccrual.e                             +3  -1   prose (`dateDiff`'s result row)
    core/examples/{Lang,Wide,Time}/README.md                         +12 -7   one table row each
    core/examples/{Lang,Wide,Time}/Corrected.e                       NEW      the exercising modules
    tracker/tools/sigcheck.py                                        NEW      S3's oracle + 3 conveniences
    tracker/loopmodel/SIG-3b-CORRECTIONS.md                          NEW      this report
    core/src/main/scala/.../SigEntail.scala                          +12 -3   the probe's `ds` column
    core/src/main/scala/.../Subst.scala                              +1  -1   passes `ds`

No wholesale line-ending conversion: `Relation.e`, `Layout/Report/Keyed.e`,
`Relation/UnifyFields.e` and `SoftRelation.e` are CRLF and every edit to them was made
byte-wise (`git diff --numstat` above is the check -- a text-mode rewrite would show every
line of the file).

**For the merge:** `SigEntail.scala` and `Subst.scala` here carry only the probe's tenth
column, which `sig-entail` already has as part of the checker; take S3's version of both
files. `tracker/tools/sigcheck.py` is S3's file plus the three conveniences of §0, which are
additive.
