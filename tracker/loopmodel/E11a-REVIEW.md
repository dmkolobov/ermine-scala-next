# Review: item E11a — a canonical FORM for published schemes

**VERDICT: ACCEPT WITH FIXES.  R-1 is blocking — the item's own checked-in property is RED about
one run in three, on a real defect the rule does not cover (variable NAME hints, not order).**
Everything else in the item holds up, and several of its central claims are stronger than the
report says.  The rule is id-independent where it claims to be (0 mismatches in 6,591 adversarial
id-renumbering trials and 50 named-scheme trials), the two-base stability result reproduces
binding for binding, the printer change is correct and reaches every consumer, and the 47 `other`
interface pairs are 43 order/alpha-equivalent and 4 residual-SET changes — one fewer real change
than the report claims, with `Relation.lookbackJoin`'s two sets hand-proved ENTAILMENT-EQUIVALENT
below.

Reviewer's logs are under
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-e11a/`
(cited below as `<rev>/`).  The implementer's are `<scratch>/e11a/logs/`.

---

## R-items

**R-1 (BLOCKING). `TestTolerantCheck`'s corpus property is red about one run in three, and the
cause is a real gap in the rule: `Canonical.key` is name-free but the RENDERING is
name-dependent.**  `scalacheck-binding/src/main/scala/TestTolerantCheck.scala:1861`
(`form.isEmpty`).  Three independent runs of the property on the final tree:

| run | log | FORM | KIND | SET | result |
|---|---|---|---|---|---|
| inside the full `core/test` | `<rev>/core-test-rev.log:2410` | 0 | 1 | 6 | 1070/1070 pass |
| `core/testOnly *TestTolerantCheck` #1 | `<rev>/rev-ttc1.log:68` | **1** | 3 | 6 | **Falsified**, `rc=1` |
| `core/testOnly *TestTolerantCheck` #2 | `<rev>/rev-ttc2.log` | 0 | 1 | 6 | 58/58 pass |

The falsifying binding is `Relation.e:lookbackJoin`: *"E11a FORM regression: 1 binding(s) render
one constraint set two ways on two cold checks"* (`<rev>/rev-ttc1.log:74`).  I reproduced it
directly with a scratch witness (8 cold checks of `modules/Relation.e`, `Canonical.key` used to
bucket the renderings):

```
### WITNESS Relation.e:lookbackJoin over 8 cold checks: 4 distinct Canonical.key
### key #2 -> 2 distinct rendering(s)   *** ONE SET, TWO FORMS ***
### key #3 -> 2 distinct rendering(s)   *** ONE SET, TWO FORMS ***
### key #4 -> 2 distinct rendering(s)   *** ONE SET, TWO FORMS ***
```

Key #3's two forms, with the binder lists aligned:

```
A  (exists c c1 d c2 e f g r2 h t o.  r1<-(r,c), r1<-(c1,d), a<-(r,c2), a<-(e,f), b<-(e,f,g),
                                      r2<-(c1,h), t<-(c1,d,h), o<-(f,g))
B  (exists c c1 d e  f g h r2 i t o.  r1<-(r,c), r1<-(c1,d), a<-(r,e),  a<-(f,g), b<-(f,g,h),
                                      r2<-(c1,i), t<-(c1,d,i), o<-(g,h))
```

Map A's binders onto B's by POSITION (`c2↦e, e↦f, f↦g, g↦h, h↦i`, the rest fixed) and A becomes B
character for character.  The canonical ORDER is identical; only the printed LETTERS differ.  The
letters come from `Pretty.fresh` (`Pretty.scala:137`), which prefers `v.name` — and the
existentials the solver minted carry different NAME HINTS on the two checks (one run's variable
suggests `c`, bumped to `c2` by `generateFresh`; the other's suggests nothing and gets `e`).
`Canonical.key` (`Type.scala:972`) renders every variable through `pos`, with no name fallback, so
it is name-free and calls the two schemes one set; `Canonical.scheme` (`Type.scala:986`) reorders
`xs` but never touches `V.name`, so the rendering is not.

The rule therefore closes the ORDER half of the FORM defect and not the NAME half.  Fix (one line,
at `Type.scala:1014`): give the ordered existentials canonical name hints, e.g.
`val nxs = xs.sortBy(...).map(_.copy(name = None))`, so `Pretty`'s `suggest` supply names them by
binder position and the letters follow the canonical order.  That is a deliberate readability
trade (the provenance hints `rs`/`so`/`ro`/`t`/`o` go away) and it will move goldens, so it is the
orchestrator's/user's call — but the property **cannot be committed red** ("Never commit red",
GATE-POLICY).  If the names are to be kept, the property's FORM comparison has to say so
explicitly and the report's "FORM 0" headline has to be qualified as "0 up to the letters a
minted existential suggests" — which the ticket's "the user sees the rendering" arguably forbids.

**R-2. The report's §5 table is wrong on two of its six rows.**  `E11a-CANON.md` §5 lists
`incomplete/TargetList.restrictTo` ("no bijection") and `incomplete/RunCalibration.scaledRuns` ("no
bijection") among the 6 that "genuinely differ".  Both ARE alpha-equivalent; my complete matcher
finds a bijection in 74 and 192 nodes and I verified it by applying the substitution and comparing
the normalised constraint multisets (`VERIFIED=True` for both).  Correct row count: **4**, not 6.
Change: replace those two rows with `alpha-equivalent (order plus a renaming)` and change "6
genuinely differ" to "4".

**R-3. §14's "E11b's exact target" is not exact — the membership moves run to run, and the report
says so in §4 but not in §14.**  Three runs of the same property on the same tree give three
different six-element sets (below).  Change §14 to "six on the run of record, 5–8 across runs; the
union over three runs is eight" and list the union.

**R-4. §11's per-file corpus claim "no module got SLOWER by > 10 %" is false.**  Recomputing from
`<scratch>/e11a/cb-1..3/` and `ca-1..3/` with the report's own method (median of three, the last
`(N.NN seconds)` per `.out`) I reproduce every figure in the report's table exactly, and two
modules the table omits: `Interp.e.out` 0.14 → 0.18 s (**+29 %**) and `Ai_ClinicalTrial.e.out`
0.16 → 0.18 s (**+12 %**).  Both are under 40 ms absolute, `Interp.e`'s samples overlap
(before `[0.19, 0.14, 0.14]`, after `[0.18, 0.17, 0.20]`) and `Ai_ClinicalTrial`'s do not
(`[0.15, 0.16, 0.16]` vs `[0.18, 0.21, 0.18]`).  Change: name them, with the absolute deltas.

**R-5. §11's two headline movers are not attributable to the solver, and §10/§11 imply they are.**
See "Trace attribution" below: `Wide/WardRoster.e`'s trace record multiset is IDENTICAL before and
after across all sixteen record kinds, and its before-side samples are bimodal
(`[0.64, 1.47, 1.44]`).  `Ai/IncidentSeverity.e` moves by two records out of ~11,600.  Change: state
that the per-file movers are measurement variance and that the solver-work change in `Wide` is
elsewhere (`learn` 61,759 → 60,535, `step` 19,906 → 19,796, in records that carry no module
location).

**R-6. `-Dermine.canon=off` does not turn the change off on the EDITOR path.**  Both `Subst` sites
are gated (`Subst.scala:895`, `Subst.scala:1792-1793`), but `TolerantCheck.scala:1151` (the `types`
map) and `TolerantCheck.scala:547` (`displayScheme`) call `Canonical.scheme` unconditionally.  The
flag's documented meaning (`Type.scala:855`, "`off` restores the pre-E11a form") is therefore true
of the `.ei` and false of hover.  Change: gate both on `Canonical.atPublication`, or narrow the
flag's documentation to the published data form.

**R-7. §6's browse.txt classification is off by two.**  Of the 95 changed lines, 87 are pure order
and 8 need a renaming or a set change — not 89/5/1.  `(<=_Predicate)` (line 64) and
`(>=_Predicate)` (line 75) are counted in the report's "same tokens, reordered" bucket but need an
alpha renaming (verified, 131 nodes each).  Corrected table below.

**R-8. §7's "the ONE signature whose SET moved" undersells it: two STDLIB signatures moved.**
`modules/Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` is stdlib
(`core/src/main/resources/modules/Layout/Report/Relation.e`), not an example, and its before/after
`.ei` admit no bijection (arity profile differs: A has 3 `part/4` + 3 `part/5`, B has 4 + 2, so no
bijection can exist — this settles the one pair my matcher left BUDGET-EXHAUSTED).  The mitigating
fact, which the report should state here rather than only in §4, is that this binding is itself in
the SET class — it differs between two cold checks of the SAME build — so its before/after
difference is not attributable to E11a.

**R-9. ROSE §4's `OrderIndependent` is never named as the non-requirement it is.**  The report
argues the point (§1 "It is not a proof of canonicity", the `key` docstring's "Two different keys
can still be two spellings of the same meaning") but does not cite ROSE §4.3's P = NP argument or
say that the SET class *is* the `REquiv`-but-not-equal class.  One sentence in §1 or §4.

**R-10. The four-round caps are never exercised, and nobody measured that.**  Counted over 4,047
published schemes (my probe, a faithful copy of `colours`/`scheme`'s loops with counters): colour
refinement rounds `(0,3570) (2,468) (3,7) (4,2)`, **0 schemes still refining at the cap**; tie
fixpoint rounds `(0,1850) (1,2169) (2,26) (3,2)`, **0 schemes unsettled at the cap**.  Add the
histogram to §1 — it is the evidence that rules 2 and 7 terminate on the corpus by fixpoint, not
by truncation.  Add also that the rule canonicalises only the OUTERMOST quantifier: a nested
rank-N `forall`'s binder order is untouched (see the probe result).

---

## What I refuted

1. **"41 of 47 are order- or alpha-equivalent; 6 genuinely differ" (§5) → 43 and 4.**  Command:
   `python3 <rev>/reviewmatch.py <scratch>/e11a/ei-before <scratch>/e11a/ei-after-t2`
   (`<rev>/other47b.log`).  Output: `== complete matcher: 43 of 47 alpha/order equivalent, 4
   genuinely differ`.  Two causes, both independent of the implementer's F-2:
   * **17 of the 47 are order-only and BOTH tools mis-parse them**, not mis-match them.
     `ei-classify.py`'s `split_sig` only finds a context that is PARENTHESISED, so a single
     unparenthesised constraint — `rot3B : forall (t: rho). t <- (c, a, b) => Relation t ->
     Relation t` — is swallowed into the BODY and compared as text.  My `split_top_arrow` splits at
     the first depth-0 `=>` (Ermine writes functions with `->`), after which these are plain
     right-hand-side reorderings.  This is a SECOND defect in the gate tool, and it belongs in the
     implementer's F-2 ticket beside the matcher one.
   * **`restrictTo` and `pnl` really are alpha-equivalent** (R-2).
2. **"no module got SLOWER by > 10 %"** — two did (R-4).
3. **"`Wide/WardRoster.e` 1.44 → 0.69 s (−52 %)" as a solver effect** — the solver does bit-for-bit
   the same work on that module (R-5, and the attribution section).
4. **"the ONE signature whose SET moved"** — two stdlib signatures moved (R-8).
5. **`g1-diff.sh compare <old> <new>` is NOT `EQUIVALENT`.**  The brief expected EQUIVALENT; the
   tool says `G1 COMPARE: DIFFERS`, `129 files, 1447 signatures, 5 differing`, `rc=1`
   (`<rev>/rev-g1-oldnew.log`).  The implementer reported this honestly.  My complete matcher over
   all 14 pairs: **13 of 14 alpha/order equivalent (each verified by applying the substitution), 1
   genuinely differs (`lookbackJoin`)** — same conclusion as §6, but 5 of the 13 need a renaming
   and are not "order-only" as §6 lists them.

## Id-independence: the table, and the adversarial probe

### (a) Every `.id`, `hashCode`, `Set`/`Map` iteration and `toList` in the key and the refinement

`object Canonical`, `core/src/main/scala/com/clarifi/reporting/ermine/Type.scala:848-1021`.
There is no `hashCode` anywhere in the object.

| site | line | what it does | why it is safe |
|---|---|---|---|
| `varOrder` `seen.add(v.id)` / `acc += v.id` | 867 | builds the first-occurrence id list | id used as an identity token only; the ORDER is the pre-order walk's, not the id's |
| `varOrder` `Exists(_,_,cs) => cs.foreach` | 870 | traverses the constraint list in list order | in `scheme` it is called on `cs1`, already sorted; in `key` on `cs1`, already sorted by `render` |
| `varOrder` `Part(_,l,r) => r.foreach` | 871 | traverses the rhs in list order | in `scheme`, `orderRhs` has already sorted the rhs (line 1001/1007). **In `key` it has NOT** — see the note below |
| `pad` | 880-883 | zero-pads a POSITION | position, not id |
| `labels` `fs.toList...sorted` | 888 | concrete row labels | `.sorted` on names — iteration order discarded |
| `render` `local.getOrElseUpdate(v.id, local.size)` | 896 | fallback colour for an uncoloured var | within-constraint first-occurrence index; in `colours` the fallback is unreachable (`all` covers `fixed ++ col`, which is every variable of `cs`) |
| `render` `Exists` `cs.map(go).sorted` | 901 | serialises a nested exists | `.sorted` — list order discarded |
| `render` `Part` `r.map(go).sorted` | 902 | serialises a partition rhs | `.sorted` — list order discarded |
| `constraintKey` `pos.get(v.id)` | 920 | position lookup | map KEY |
| `colours` `bodyPos.map{(id,p)=>(id,pad(p))}` | 925 | `fixed` | builds a Map; consumed by `.get` only |
| `colours` `free = cs.flatMap(typeVars).distinct.filterNot(fixed.contains(_.id))` | 926 | the free list | order-dependent, but `free` is only used to BUILD maps (`occ`, `col`, `raw`); every value that leaves the loop comes from `raw.values.toList.distinct.sorted` |
| `colours` `occ(v.id)` / `typeVars(c).exists(_.id == v.id)` | 930, 940 | occurrence test | identity test |
| `colours` `sigs = ...sorted` | 940 | occurrence profile | `.sorted` |
| `colours` `rank = raw.values.toList.distinct.sorted.zipWithIndex` | 943 | re-rank | `.sorted` on id-free strings — `raw`'s Map iteration order is discarded |
| `colours` `col = raw.map{...}` | 944 | Map rebuild | consumed by `.get` |
| `orderRhs` `sortBy((0,labels)/(1,render))` | 956-959 | rhs order | id-free keys; **ties are stable, i.e. incoming order** |
| `key` `varOrder(body) ++ cs1.flatMap(varOrder)` | 978 | position map | `cs1` sorted first; but `varOrder` on a `Part` reads the rhs LIST — `key` never applies `orderRhs`, so `key` is rhs-list-order sensitive for existential positions (harmless in practice: everything `key` is applied to has already been through `scheme`) |
| `scheme` `xorder`/`torder` `getOrElse(v.id, Int.MaxValue)` | 1014, 1016 | binder sort | positions; a binder in neither body nor constraints keeps its incoming position (stable sort) |

Two exceptions to "order-insensitive or ordered by an id-free key", both benign on this corpus and
both worth a comment in the source: `key`'s `varOrder` over unsorted partition right-hand sides
(line 978), and the stable-sort ties at lines 956 and 1001/1008 and 1014/1016.  **Nothing in the
object orders by an id value.**  What the table does NOT cover, and the rule does not touch, is
`V.name` — which is R-1.

### (b) The adversarial probe

Scratch `runMain` under `scalacheck-binding/` (`<rev>/E11aProbe.scala`, compiled into
`core/Test`, run, and **deleted from the tree**).  It takes a published scheme, applies a RANDOM
bijective renumbering of every variable id and a random shuffle of every list (universal binders,
existential binders, constraints, every partition right-hand side, every concrete label set — the
last by rebuilding the `Set` from a shuffled list, which changes iteration order for `Set1..Set4`),
canonicalises, and compares the RENDERED string to the unshuffled canonical rendering.

```
### (b) NAMED SCHEMES, 10 seeds each
###   modules/Relation.e:lookbackJoin           existentials=11  mismatches=0
###   modules/Layout/Chart.e:seriesW            existentials=1   mismatches=0
###   modules/Layout/Report/Keyed.e:keyValueTabular existentials=1 mismatches=0
###   modules/Relation/Op.e:if                  existentials=7   mismatches=0
###   modules/Relation/Op.e:replace             existentials=7   mismatches=0
### (b) named result: 0 of 5 schemes mismatched
```

(Note for the brief: `seriesW` and `keyValueTabular` carry ONE existential on this build, not ≥ 3.
I added `Relation/Op.if` and `Relation/Op.replace`, the two schemes in `Relation/Op.e` with the
most existentials (7 each), and then ran the attack over the whole corpus rather than five schemes.)

```
### (b2) CORPUS SWEEP, 2197 Forall schemes x 3 seeds = 6591 trials per attack
###   id-renumbering only                   : 0 mismatches
###   list-shuffle only                     : 10 mismatches   (4 distinct schemes)
###   both                                  : 11 mismatches
###   id + shuffle, NESTED foralls exempt   : 0 mismatches
###   failing the full shuffle: Layout/Chart.e:axisLabel#, Layout/Column.e:endoColumn,
###                             Layout/Column.e:foldColumn, Relation/Pivot.e:mapFulcrum
###   failing the scoped attack: (none)
```

**Reading it.**  Pure id renumbering never moves a rendering: 0 of 6,591.  That is ROSE §4.4's
`AlphaCanonical` clause, measured.  The ten shuffle failures are all the same thing and it is a
SCOPE limit, not a bug: `Canonical.scheme` canonicalises the OUTERMOST `Forall` only, so a nested
rank-N argument's binder list (`(forall t t'. …)` in `axisLabel#`) keeps whatever order it came in
with.  That order is the user's source order, not an id-keyed set, so the compiler cannot actually
produce the shuffle — but the limit should be stated (R-10).  Exempt the nested binder lists and
shuffle everything else at every depth: **0 of 6,591**.

### (c) Refinement rounds and the tie

Counted with a faithful copy of both loops (R-10): the four-round caps are never binding — 0
schemes are still refining at round 4 in `colours`, 0 are unsettled at round 4 in the tie fixpoint.
The report does not count rounds; it should.

For the automorphism: I built one by cloning a real published partition constraint with a FRESH
existential carrying the SAME name and kind (a true twin, indistinguishable to colour refinement),
and canonicalised both incoming orders.

```
### (c2) AUTOMORPHISM WITNESS (two existentials, same name, same profile)
###   IDENTICAL -- the tie is harmless
###   (nameless twin) IDENTICAL
```

**Deterministic on the witness, and the reason is the one rule 7 gives:** on a true automorphism
the swap is an isomorphism of the whole scheme, so the letters move with the constraints and the
rendered string is unchanged.  The residual risk is the NEAR-tie — two existentials that colour
refinement cannot separate but that are not symmetric — where `sortBy`'s stability breaks the tie
by the incoming (id) order.  I found no such witness on the corpus by shuffling (the scoped attack
is 0/6591), so rule 7 stands as measured.  It is not proved, and the report says so.

### (d) `OrderIndependent` is not claimed

Confirmed, but only implicitly — see R-9.  The SET class is exactly ROSE §4's "two `REquiv`
residuals that are not equal", and `Canonical.key`'s own docstring (`Type.scala:963-971`) says so
in its own words ("Note what it is NOT: an entailment check").

---

## The 47 "other" pairs — every verdict

Tool: `<rev>/reviewmatch.py` (ei-classify.py's tokeniser and unifier; my own signature parser that
handles an unparenthesised context; a matcher that enumerates every bijection at BOTH levels under
a 4M-node budget).  Log `<rev>/other47b.log`.  **43 alpha/order equivalent, 4 genuinely differ.**

| # | interface | binding | my verdict |
|---|---|---|---|
| 1-2 | `Algebra_Signatures` | `rot3B`, `rot3C` | order-only (rhs multiset) |
| 3 | `Lang_Helpers` | `withRunning` | order-only |
| 4-8 | `Lang_Signatures` | `consRowFull`, `pRecordFull`, `permB`, `withRunningDeduped`, `withRunningFull` | order-only |
| 9-11 | `Present_Signatures` | `permB`, `withFormatsBack`, `withFormatsFull` | order-only |
| 12-14 | `Time_Helpers` | `asOf`, `asOfEach`, `movingAgg` | order-only |
| 15-17 | `Time_Signatures` | `movingAggDeduped`, `perm2B`, `perm4B` | order-only |
| 18-19 | `Wide_Helpers` | `withDerived2`, `withDerived3` | alpha-equivalent (82 / 167 nodes) |
| 20 | `incomplete_RevenueShare` | `shareOfGroup` | **GENUINELY DIFFERS** (A has a 4-member partition, B none) |
| 21-23 | `incomplete_Signatures` | `perm2B`, `permB`, `permC` | order-only |
| 24 | `incomplete_TargetList` | `restrictTo` | alpha-equivalent (74 nodes, verified) — **report says no bijection** |
| 25-26 | `incomplete_RunCalibration` | `scaledRuns`, `valueAsOf` | alpha-equivalent (192 / 280 nodes, verified) — **report says no bijection for `scaledRuns`** |
| 27 | `incomplete_gu01…` | `wideOrderLines` | alpha-equivalent (373) |
| 28 | `incomplete_gu06…` | `withLabel` | alpha-equivalent (1008) |
| 29-30 | `incomplete_gu10…` | `coreOrderLines`, `wideOrderLines` | alpha-equivalent (233 / 485) |
| 31 | `incomplete_np01…` | `inferredRestate` | **GENUINELY DIFFERS** (7 existentials vs 6) |
| 32 | `incomplete_np02…` | `byRegion` | alpha-equivalent (37) |
| 33 | `incomplete_np03…` | `adjusted` | alpha-equivalent (18) |
| 34 | `incomplete_np04…` | `summaryLine` | order-only |
| 35 | `modules_Layout_Report_Relation` | `cutoffGroupedFldsPosNegRel'` | **GENUINELY DIFFERS** (budget exhausted at 4M; settled by arity profile: `part/4` 3 vs 4, `part/5` 3 vs 2 — no bijection exists) |
| 36 | `modules_Layout_Report_SoftRelation` | `joinKey` | order-only |
| 37 | `modules_Record` | `(++)` | order-only |
| 38 | `modules_Relation` | `lookbackJoin` | **GENUINELY DIFFERS** (9 constraints vs 8) |
| 39-40 | `modules_Relation` | `nearestDate`, `nearestDateWithin` | order-only |
| 41-42 | `modules_Relation_Predicate` | `(<=)`, `(>=)` | alpha-equivalent (364 / 1701, verified) |
| 43 | `modules_Relation_Row` | `snoc_Brace` | order-only |
| 44-46 | `modules_Syntax_Relation` | `(&)`, `(&_Mem)`, `(**)` | alpha-equivalent (18 / 18 / 19) |
| 47 | `modules_Validation` | `cons_Bracket` | order-only |

**Does `ei-classify.py` need its matcher fixed?**  Yes, and its PARSER too — two separate defects,
both worth the follow-up ticket F-2 (not a change in this item):
(i) the matcher commits to the first internal right-hand-side bijection (`match_items` returns an
`Option`, not a generator) — 26 of the 47 are only settled by backtracking at both levels;
(ii) `split_sig` mis-parses an UNPARENTHESISED constraint context, which alone accounts for 17 of
the 47.  `G1Compare.alphaEq` shares (i).  Until both are fixed a red from either tool needs a hand
re-check, which is what §5 and §6 did.

**Is any of the 47 a real type change?**  No.  All four genuine differences are residual-SET
changes (E11b's class), two of them in `core/examples/incomplete/` (non-terminating by design;
their `.ei` is whatever the timeout left), and two of them — `cutoffGroupedFldsPosNegRel'` and
`lookbackJoin` — bindings that are themselves in the SET class, i.e. they differ between two cold
checks of ONE build.  `concrete->polymorphic` 0 and `polymorphic->concrete` 0 on every pair.

### `Relation.lookbackJoin`: the two sets are ENTAILMENT-EQUIVALENT

The per-label decision tooling of `ROW-CONSTRAINT-STATE.md` A1 is a COMPILER layer
(`-Dermine.rowSound.decide`), not a CLI that takes two published residuals, so it cannot be pointed
at this pair; `sigentail-entail.py` is explicitly "not a gate and deliberately incomplete".  Hand
derivation instead, on the §7 pair:

```
BEFORE  A1 r1<-(c1,e)  A2 b<-(h,g,f)  A3 r1<-(c2,r)  A4 o<-(g,f)  A5 t<-(d,c1,e)
        A6 t<-(r,d,c2) A7 r2<-(d,c1)  A8 a<-(h,g)    A9 a<-(c,r)                   9
AFTER   B1 r1<-(r,c)   B2 r1<-(c1,d)  B3 a<-(r,e)    B4 a<-(f,g)  B5 b<-(f,g,h)
        B6 r2<-(c1,i)  B7 t<-(c1,d,i) B8 o<-(g,h)                                  8
```

The bijection `c↦c2, c1↦c1, d↦e, e↦c, f↦h, g↦g, h↦f, i↦d, r2↦r2, t↦t, o↦o` sends
B1↦A3, B2↦A1, B3↦A9, B4↦A8, B5↦A2, B6↦A7, B7↦A5, B8↦A4.  So **AFTER = BEFORE minus A6**, exactly.
And A6 follows from three of the eight that survive: A5 gives `t = d ⊎ c1 ⊎ e`; A1 gives
`r1 = c1 ⊎ e`, so `t = d ⊎ r1`; A3 gives `r1 = c2 ⊎ r`, so `t = d ⊎ c2 ⊎ r` — which is A6.
Therefore `AFTER ⊨ BEFORE` and trivially `BEFORE ⊨ AFTER`: **`REquiv`, neither weaker nor
stronger**, and the AFTER set is the smaller of the two.  The universals (`r, r1, a, b`) are the
same on both sides, so ROSE §4.2's `universals` clause is respected.  The derivation uses only
associativity of disjoint union, which is what `Part` means.

---

## Two-base stability — my own two bases

`tracker/tools/ei-diff.sh --snapshot --batch` twice on THIS build, `-Dermine.loadInSeries=true`
then `=false` (`<rev>/ei-base-t.log`, `<rev>/ei-base-f.log`), classified with the shipped
`ei-classify.py` (`<rev>/rev-2base.log`):

```
interfaces: A 270  B 274
== 6 of 270 interfaces differ
== bindings by verdict: {'identical': 3477, 'other': 5, 'order-only': 1}
```

(Side A lost four interfaces — `Accumulate`, `Ai/ClinicalTrial`, `Ai/FiscalCalendar`,
`Ai/IncidentSeverity` — to the batch chunk timeout, because it ran under contention with the
looptrace differential.  The 270 in common are the comparison.)

The six that differ are **exactly the set the report lists in §5**, with the same classes:

| binding | class | matches the report |
|---|---|---|
| `Present/WriterOutputs.reportFor` | SET (3 constraints → 1) | yes |
| `Relation.lookbackJoin` | SET (8 vs 8, no bijection: A `r2<-(c1,i)` vs B `r3<-(d,i)`) | yes |
| `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` | SET | yes |
| `ChartsExample.stackedPair` | KIND (`{a a1 b b1 c} … (sa: c)` vs `{a b} … sa`) | yes |
| `GridExample.stackedBarChart` | KIND | yes |
| `PivotTest.pivotData2` | order-only (report calls it KIND) | near enough |

**3,477 of 3,483 published bindings byte-identical across two id bases, and ZERO FORM
differences.**  That is the item's purpose and it reproduces.

**The count reconciliation (§4 vs §14 vs the sweeps).**  The SET class has SIX members on any one
run and the membership MOVES.  Three runs of the checked-in property on the final tree:

| run | SET members |
|---|---|
| full `core/test` (`<rev>/core-test-rev.log:2412`) | `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'`, `Layout/Report.drilldownKeyValueTable2`, `Relation.lookbackJoin`, `Yahoo.investmentTableData`, `Yahoo.joinCumRet`, `Yahoo.joinTotalValue` |
| ttc #1 (`<rev>/rev-ttc1.log:70`) | …`cutoffGroupedFldsPosNegRel'`, `drilldownKeyValueTable2`, `Present/WriterOutputs.reportFor`, `Yahoo.investmentTableData`, `Yahoo.joinCumRet`, `Yahoo.joinTotalValue` |
| ttc #2 (`<rev>/rev-ttc2.log`) | …`cutoffGroupedFldsPosNegRel'`, `drilldownKeyValueTable2`, `Relation.lookbackJoin`, `Present/WriterOutputs.reportFor`, `Yahoo.investmentTableData`, `Yahoo.joinTotalValue` |

### E11b's target list — what I confirm

The union over my three runs, EIGHT bindings, all confirmed by def-site:

1. `core/src/main/resources/modules/Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'` (stdlib)
2. `core/src/main/resources/modules/Relation.e:lookbackJoin` (stdlib)
3. `core/src/main/resources/modules/Layout/Report.e:drilldownKeyValueTable2` (stdlib) — **not in
   the report's §14 list; it is in every one of my three runs**
4. `core/examples/Present/WriterOutputs.e:reportFor`
5. `core/examples/Yahoo.e:investmentTableData`
6. `core/examples/Yahoo.e:joinCumRet`
7. `core/examples/Yahoo.e:joinTotalValue`
8. (from the interface sweep, not the property) `core/examples/incomplete/RevenueShare.e:shareOfGroup`
   and `core/examples/incomplete/np01_add_or_recompute.e:inferredRestate` — the `incomplete/`
   residuals, which E11b should explicitly exclude or explicitly own.

I confirm items 1-7 as E11b's target and ask that §14 carry the UNION with the run-to-run caveat
(R-3), plus item 3, which the report's list omits.

### The editor, six cold rounds

`<scratch>/review-7.2/nondet.py`, real server, six cold didOpen/hover/didClose rounds of an
unchanged `core/examples/Present/WriterOutputs.e` in ONE JVM (`<rev>/nondet-rev.txt`):

* `reportFor` renders in **THREE** forms, not two and not four — rounds 0, 1, 4, 5 byte-identical;
  round 2 carries a second conjunct `a <- ((|pRegion, pTitle|), c)`; round 3 a different second
  conjunct `a <- ((|pMinValue, pTitle|), c)`.  Three distinct constraint SETS, **one rendering per
  set**.  (The review brief's "exactly TWO forms" is not what the defect leaves behind; §3 of the
  report has it right at three.)
* `asDocument` renders in **ONE** form in all six rounds (two before).
* `writerOutputs` in **ONE**.
* Labels are `(|pMinValue, pRegion, pTitle|)` — name order — in every round.

---

## The corpus property

* The assertion is on RENDERED STRINGS.  `TestTolerantCheck.scala:1855-1862` compares
  `Pretty.prettyType(t,-1).toString` values; `Canonical.key` is used only to decide WHICH pair must
  be equal, never to excuse an inequality; the FORM comparison additionally blanks kinds with
  `t.map(_ => Star(t.loc))` so the KIND class is not double-counted.  **No alpha-equivalence
  loosening** — ticket E11's prohibition is honoured.
* FORM is asserted 0 (`:1861`) — and is not reproducibly 0 (R-1).
* KIND is pinned ≤ 6 (`:1864`).  The three def-sites in the report's §4 —
  `Algebra/SoftSchema.e:pivoted` (`(v34: f)` vs `(v34: rho)`), `PivotTest.e:pivotData` (`(d)` vs
  `(rho)`), `PivotTest.e:pivotData2` (`(rho)` vs `(d)`) — I saw all three on ttc #1 and one
  (`pivotData`) on the other two runs.  Read at source: each is one token, an existential whose
  KIND one check left as a kind VARIABLE and the other solved to `rho`.  That is kind inference,
  **not a form defect the rule should cover** — `Canonical.scheme` does not and should not choose
  kinds — so it is a real second frame, correctly carried as F-1.
* SET is pinned ≤ 10 (`:1868`).
* **Runtime**: 393.9 s (ttc #1) and 325.4 s (ttc #2), wall, `core/testOnly *TestTolerantCheck`
  alone-ish.  6.2c's run of the same suite was ~120 s; the two new properties (2 × 253 cold checks
  plus 4 cold checks of one module) roughly triple it.  Worth a line in the report — this is now
  the most expensive suite in Tier 0.
* **Determinism**: NO.  Two runs, two different FORM counts, two different KIND sets, two different
  SET memberships (table above).  The SET list moves; so does the verdict.

---

## g1

* `g1-validate.sh` on the final tree: **9 / 9 PASS** (`<rev>/rev-g1.log`) — seven oracle fixtures,
  `double-run self-agreement`, `no drift from tracker/g1-baseline`; `129 files, 1447 signatures`.
* `g1-diff.sh compare <HEAD baseline> <new baseline>`: `G1 COMPARE: DIFFERS`, `129 files, 1447
  signatures, 5 differing`, 14 A/B pairs (`<rev>/rev-g1-oldnew.log`; the old baseline extracted
  with `git archive HEAD tracker/g1-baseline`, no `git stash`).  My complete matcher over the 14:
  **13 alpha/order equivalent (each verified by substitution), 1 genuinely different
  (`lookbackJoin`)** — of the 13, eight are order-only (`cons_Bracket`, `replaceColumn`,
  `coalesce`, `combine`, `dateDiff`, `if`, `replace`, `(!=)`) and five need a renaming (`(<=)`,
  `(>=)`, `(&)`, `(&_Mem)`, `(**)`).
* **browse.txt, 95 of 1,301 lines changed, 0 added, 0 removed.**  Classified by finding, for each
  changed line, the MINIMAL subset of {sort labels, sort partition rhs, sort constraints, sort
  binders} that makes the two lines equal:

| class | count |
|---|---|
| partition right-hand-side order alone | 54 |
| constraint order alone | 26 |
| rhs order + constraint order | 5 |
| rhs order + universal binder order | 2 |
| **order plus a renaming (alpha)** — `(&_Mem_Relation)`, `(&_Relation)`, `(**_Relation)`, `(<=_Predicate)`, `(>=_Predicate)`, `drilldownPivotTabular`, `drilldownPivotTabular'` | **7** |
| the residual SET moved — `lookbackJoin` | 1 |
| **anything outside these classes** | **0** |

  Each of the seven alpha lines was verified by applying the found substitution and comparing the
  normalised constraint multisets.  Concrete-row LABEL order accounts for **zero** of the 95:
  browse.txt contains no multi-label concrete row at all, so the printer change does not reach it.
  (The report attributes 54 to "label order and/or rhs order"; it is rhs order alone — cosmetic,
  but worth correcting alongside R-7.)
* **The tripwire's own rule is honoured.**  `g1-validate.sh`'s comment forbids re-cutting the
  baseline to make it green without an explanation; §6 gives one (the GATE-POLICY clause, the
  source `/tmp/g1-selfA`, the 38 `.ei` + `browse.txt`, `groups.txt` byte-identical, the pre-change
  baseline preserved at `<scratch>/e11a/g1-baseline.ORIG`), and it lists the before/after.  I
  independently reproduce the 39-file / 286-insertion / 286-deletion shape and the classification.

---

## Traces, and the attribution

**Fidelity, my own run** (`LOOPTRACE_PAR=3 looptrace-corpus.sh`, main tree, `<rev>/lt-after-rev.log`;
started before the orchestrator's scope correction, so it is the full 18 groups rather than three):
**18 groups, 3,210,881 segments, `agree` = `segments` on every group, `skip=0` on every group,
`rc=0`, `timeouts=0`, `dropped=0`** — identical to `<scratch>/e11a/logs/lt-after.log`.
`TestLoopTrace`: `720 solves; 720 segments; 720 agree; skipped=0; hashdiff=0; eqdiff=0`
(`<rev>/rev-looptrace.log`).

**The attribution, from the implementer's traces** (`<scratch>/e11a/lt-before|after/traces/*.tsv.gz`,
grouping every record by the module in its location column):

* `Wide/WardRoster.e` — the −52 % mover — has an **IDENTICAL record multiset before and after, in
  every one of its kinds**: `solve/sin/rsound` 4,771 each, `slbl` 4,057, `sat` 2,579, `svar` 2,547,
  `ramb` 1,682, `scon` 1,395, `inpart` 1,387, `in` 1,325, `splice`/`detm` 861, `concr` 377,
  `ex` 270.  The solver's path on that module did not change at all.  Its before-side wall times
  are bimodal (`[0.64, 1.47, 1.44]`) and its after-side is not (`[0.74, 0.69, 0.67]`), so the
  median moved from the slow mode to the fast one.  **The −52 % is measurement variance, not a
  solver-path change** (R-5).
* `Ai/IncidentSeverity.e` — the −24 % mover — differs by **two records out of ~11,600** (`concr`
  156 → 155, `sat` 674 → 673).  Also not an explanation for −24 %.
* Where the work really moved in `Wide`: `learn` 61,759 → 60,535 (−1,224) and `step` 19,906 →
  19,796 (−110), in records that carry no module location, plus 4 records in
  `Wide/ClaimsExperience.e` and 3 in `Relation.e`.  In `Ai`: `learn` 16,421 → 16,457 (+36),
  `step` 11,072 → 11,088, `splice`/`detm` 768 → 775, spread over eight modules.
* **Do the keyed-split guarantees still cover it?**  Yes, and by proof, not by measurement:
  `KeyedSplit.lean`'s `terminatesOnSatKeyed` (with `keyed_vs_syntactic`) establishes that keying
  `splitConcrete`'s guard on `(lhs, concrete part)` makes the calculus terminate on every
  satisfiable input **in every run order**, by `ResGuardTerm`'s measure unchanged
  (`ROW-CONSTRAINT-STATE.md` 2026-09-03; `tracker/satterm/KEYED-SPLIT.md`); `Loop/PolicyTerm.lean`'s
  `budgetP_terminates` covers every dequeue policy.  A change in the order in which instantiated
  schemes enter the queue is exactly the quantifier those theorems already range over, so E11a
  cannot take the solver outside them.
* **No module got slower by > 10 %** — false; two did (R-4).

---

## The printer change

* One site only: `Pretty.formatRho` (`Pretty.scala:219`), `fields.toList.sortBy(_.toString)`.
  `ppRho` routes both the `(|…|)` and the record `{…}` spellings through it (`Pretty.scala:359`),
  and there is no other place in the tree that prints `ConcreteRho.fields` — so browse, `.ei`,
  hover, the REPL and error messages all move together, as intended.  Unconditional, with no
  `canon=off` escape, and the source says so.
* **Why the REPL goldens did not move, checked rather than assumed.**  `tracker/repl-tests/*.expected`
  contains exactly TWO printed concrete rows in total, both the same row:
  `(|FavoriteColor, ID, Name|)` — already in `Name.toString` order (`F` < `I` < `N`).  No golden
  could have moved.  `repl-smoke.sh`: **8 groups / 66 checks, all PASS**, goldens untouched
  (`<rev>/rev-repl.log`; aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4,
  smoke 23, tauto 5).  Nothing that would have moved and did not.
* **Through the real server**: the six-round hover above renders
  `a <- ((|pMinValue, pRegion, pTitle|), b)` — a three-label stdlib-style row in name order — in
  all six rounds.  The pre-change control is the implementer's `logs/nondet-before.txt`, whose
  round 0 gives `(|pTitle, pMinValue, pRegion|)`.
* `lsp-smoke.sh`: **`PASS lsp (573 checks)`** (`<rev>/rev-lsp.log`), which is what carries 6.2c's
  `LetAndPatternMatching.e` and `Heads.e` head pins; no pin moved.

## The flag and the strict path

* `-Dermine.canon` = `publication` (default) / `all` / `off`, `Type.scala:857-859`.  The default
  flip IS declared as an ADOPTION in the report (§2, §12) and in `LSP-ROADMAP.md` § "Interstage
  item E11" ("E11a ADOPTION"), whose GATE line asks for the reviewer's Tier 2 and the interface
  classification.
* **`off` restores the pre-E11a DATA form**: booting the stdlib in the pre-change worktree and then
  in this tree with `-Dermine.canon=off` (`<rev>/burst6.sh`, `<rev>/eioff/`),
  `modules/Prelude.ei` and `modules/Syntax/Relation.ei` are **byte-identical**; `modules/Relation/Op.ei`
  has the same byte length and 18 bindings differ, **all 18 order-only** — i.e. with the
  canonicaliser off the order is id-keyed again and two independent boots need not agree, which is
  the original defect, correctly restored.
* **But the flag does not reach the editor** — R-6.
* The 6.2c local-head display now runs on the shared key (`displayScheme`, `TolerantCheck.scala:547`),
  and every 6.2c pin is unchanged: `lsp-smoke` 573 PASS, and inside `core/test` the 6.2b/6.2c pinned
  sets are unmoved (`agreed 174, disagreed 65, requantified 94, constraint elided 58, usable
  constraint lost 0, hover SHOWS a constraint 12`; `Arg(equation) 2874/2874 … agreed 2869
  disagreed 14`).

---

## Every gate, with its figure

| gate | expected | measured (mine unless marked) | log |
|---|---|---|---|
| `sbt core/test` ALONE (Tier 2) | 1068 + the item's, 0 failed | **1070 / 1070, Failed 0, Errors 0, 27 m 39 s**, no intermittent (`TestInterfaceRoundTrip` and `TestLegend."extra args are ignored"` both green) | `<rev>/core-test-rev.log:2426` |
| same, orchestrator's run (cited, per the scope correction) | — | 1070 / 1070, 0 failed, 1380 s | `<scratch>/e11a/logs/core-test-2.log` |
| `TestLoopTrace` | 720/720 | 720 solves / 720 segments / 720 agree / skipped 0 / hashdiff 0 / eqdiff 0 | `<rev>/rev-looptrace.log` |
| `TestTolerantCheck` #1 | 58/58 | **FALSIFIED** — FORM 1 (`Relation.e:lookbackJoin`), KIND 3, SET 6; 393.9 s | `<rev>/rev-ttc1.log` |
| `TestTolerantCheck` #2 | 58/58 | 58 / 58 pass — FORM 0, KIND 1, SET 6; 325.4 s | `<rev>/rev-ttc2.log` |
| 6.2b / 6.2c pinned sets | unchanged | unchanged (figures above) | `<rev>/core-test-rev.log` |
| `corpus-run.sh --batch` | 89/79/0 of 168 | **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168** | `<rev>/rev-corpus.log` |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 / 8 PASS, 66 checks**, no golden moved | `<rev>/rev-repl.log` |
| `lsp-smoke.sh` | 573 | **PASS lsp (573 checks)** | `<rev>/rev-lsp.log` |
| `g1-validate.sh` | 9/9 | **9 / 9 PASS**, 129 files / 1447 signatures, no drift | `<rev>/rev-g1.log` |
| g1 old-vs-new baseline | EQUIVALENT | **tool says DIFFERS** (5 files, 14 pairs); by hand 13 alpha/order + 1 SET | `<rev>/rev-g1-oldnew.log` |
| browse.txt classification | four order classes | 87 order, 7 alpha, 1 SET, **0 outside** | this report |
| `ei-classify` before vs after, the 47 `other` | NONE in other | 43 order/alpha equivalent, **4 genuine, all SET** | `<rev>/other47b.log` |
| two-base byte identity | only the SET class | **6 of 270 differ; 3,477 of 3,483 bindings byte-identical; 0 FORM** | `<rev>/rev-2base.log` |
| looptrace, 18 groups | agree = segments, skip 0 | **18 groups, 3,210,881 segments, agree = segments, skip 0, rc 0, timeouts 0, dropped 0** | `<rev>/lt-after-rev.log` |
| trace attribution | WardRoster / IncidentSeverity | identical / 2 records of 11,600 — not solver work | this report |
| per-file corpus times | none slower > 10 % | sum of medians 27.9 → 27.0 s (−2.9 %); **two slower > 10 %** | `<scratch>/e11a/cb-*`, `ca-*` |
| boot | 129 | 129 modules (`g1-validate`: "129 files, 1447 signatures") | `<rev>/rev-g1.log` |
| `.ei` by `find` | 0 | **0** (`find . -name '*.ei' -not -path './tracker/g1-*'`) | — |
| diff parity | `--histogram` == `-w` | **equal** | — |
| line endings | CRLF/LF preserved | `Type.scala` and `Pretty.scala` CRLF, every added line CR-terminated; `Subst.scala` ASCII/LF with **0** CR in its diff; `TolerantCheck.scala` / `TestTolerantCheck.scala` UTF-8/LF | — |
| adversarial id-independence | — | 0 / 6,591 id-renumbering, 0 / 6,591 scoped shuffle, 0 / 50 named | `<rev>/probe2.log` |
| refinement rounds | — | colour cap never binding, tie cap never reached | `<rev>/probe2.log` |

**What I re-ran vs what I cited.**  Re-ran: the full `core/test` (started before the scope
correction arrived; it is complete and green, and the orchestrator's run is also cited),
`TestLoopTrace`, `TestTolerantCheck` twice, `corpus-run --batch`, `repl-smoke`, `lsp-smoke`,
`g1-validate`, `g1-diff compare`, the 18-group looptrace (also started before the correction), both
sides of my own two-base interface sweep, the six-round editor repro, the `canon=off` interface
control, and two scratch probes.  Cited without re-running: the implementer's batch and editor
perf A/Bs (`logs/perf-*.log`), the before-side corpus and interface snapshots
(`logs/corpus-before.log`, `<scratch>/e11a/ei-before/`), the before-side traces
(`<scratch>/e11a/lt-before/`), the per-file corpus timing runs (`cb-*`, `ca-*` — re-analysed, not
re-measured), and `logs/nondet-before.txt`.

## NOT CHECKED

* **The perf A/Bs were not re-measured.**  The batch A/B (+0.22 % median-of-medians over four
  interleaved rounds), the `canon=all` cost (+2.2 %) and the editor A/B (flat) are the
  implementer's figures, read from `logs/perf-*.log`.  Re-measuring four interleaved rounds alone
  at load < 1.3 does not fit the review's budget and GATE-POLICY puts perf outside a per-stage
  gate.  I did re-analyse the per-file corpus timings (R-4, R-5).
* **`-Dermine.canon=all` was not exercised at all** — no corpus run, no looptrace, no sweep.  The
  decision to ship `publication` rests on the implementer's §2 table.
* **`canon=off` was checked on three stdlib interfaces, not on the corpus.**
* **The `.out` text classification of §9** (27 of 168 corpus outputs differing, in three classes)
  was not reproduced; I checked only that the verdicts are 89/79/0.
* **No Lean.** `tracker/lean/` untouched, per the brief; the `IsAlphaCanonicaliser` formalisation is
  deferred (F-3).
* **The SIG-3 `NO VERDICT` warnings** on `Layout/Report/Relation.e:73/88/104` appear throughout the
  logs on both sides and are pre-existing; not investigated.
* **`ei-classify.py`'s own parser/matcher were not fixed** — that is F-2, a follow-up, and I only
  demonstrated both defects.
* **The two-base sweep lost four interfaces on side A** to a chunk timeout under contention; those
  four were not re-run.

## Follow-ups I endorse

F-1 (the KIND class: kind inference, genuinely a second frame — verified at source), F-2 (both
shipped alpha comparators are incomplete — and `ei-classify.py`'s PARSER is too, which I add),
F-3 (the key is measured, not proved — ROSE §4.4's `AlphaCanonical` is now measured at 0/6,591,
which is worth recording in `ROSE-COMPARISON.md` rank 3 whatever happens to the proof).

## Housekeeping

No JVM of mine is running; no `.ei` anywhere (`find` returns 0); both scratch probes
(`E11aProbe.scala`, `E11aWitness.scala`) were deleted from `scalacheck-binding/src/main/scala/`;
`tracker/tools/__pycache__/` (created by importing `ei-classify.py`) removed;
`tracker/repl-classpath.txt` regenerated for a gate run and restored with `git checkout`; the
pre-change worktree `../ermine-scala-wt-e11a` is untouched apart from its own
`tracker/repl-classpath.txt`.  `git status --short` shows the five implementer source files, the
39-file g1 re-cut, `tracker/loopmodel/E11a-CANON.md`, `tracker/loopmodel/briefs/brief-E11a-review.md`
and this report, and nothing else.
