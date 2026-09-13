# Item E11a — a canonical FORM for published schemes

**Outcome: DONE, and green, with one thing for the reviewer to sign off.**  The FORM half of
ticket E11 is closed: over the 253-file clean corpus, two cold checks in one JVM now render
**0** published bindings differently for reasons of form (129 before), and the E11 repro's four
cold checks of `Present/WriterOutputs.e` now produce **one rendering per constraint set**
instead of four renderings of three sets.  Nothing was loosened to alpha-equivalence: every
assertion and every count in this report compares RENDERED TEXT.

The thing to sign off: canonical publication changes the order in which downstream
instantiations enter the solver's queue, and on **six** published bindings the solver's
order-dependent residual (the SET half, interstage item E11b) moved as a result — one of them a
stdlib signature, `Relation.lookbackJoin` (9 constraints before, 8 after).  Controls, blast
radius and the reasons it is not a soundness change are in §7 and §11.

Every number below names its log under
`<scratch>/e11a/logs/` (`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11a/`).
The pre-change worktree is left at `../ermine-scala-wt-e11a` (detached at `9976b78d`, compiled,
with its own `target/ermine-classpath` and `tracker/repl-classpath.txt` regenerated).

---

## 1. The canonical form, as a rule a reader can apply by hand

Given a published scheme `forall <ts>. (exists <xs>. c1, …, cn) => body`:

1. **Colours.**  Every variable gets a COLOUR that mentions no id.  A variable the BODY shows is
   `#i`, zero-padded, where `i` is its first-occurrence index in a pre-order walk of the body.
   An existential starts at its name (`@n`) or, nameless, at `?`, and is then refined (step 2).
2. **Keys and refinement.**  A constraint's KEY is its structure serialised with each variable by
   its colour, a concrete row by its labels SORTED BY NAME, a constructor by its name, and a
   partition's right-hand side by its members' keys SORTED.  Refinement: an existential's next
   colour is the sorted multiset of the keys of the constraints that mention it, with itself
   marked; the colours are then re-ranked to their sort position.  Repeat until the partition of
   the existentials stops refining (colour refinement in the Weisfeiler–Leman sense; four rounds
   cap it).
3. **Right-hand sides.**  Each partition's right-hand side is ordered CONCRETE ROW FIRST (labels
   by name), then the rest by key.
4. **Constraints.**  The constraints are ordered by key.
5. **Existential binders.**  Ordered by first occurrence in the ordered constraints — which is
   what assigns their LETTERS.
6. **Universal binders.**  Ordered by first occurrence in the BODY, then in the ordered
   constraints.
7. **Ties.**  Refinement leaves a tie exactly between two constraints it cannot tell apart — an
   automorphism of the set (two existentials with the same name and the same occurrence profile,
   `ChartsExample.stackedPair`'s two `AsOp`s).  A tie broken by the incoming list order is broken
   by ids, and the two orders do NOT render alike, because the binder order that names the
   letters is fixed by the constraints the tie does not touch.  So steps 3–4 are then re-run
   against the POSITIONS the current order gives the existentials, to a fixpoint (capped at four
   rounds).
8. **Printing.**  A concrete row prints its labels in name order (`Pretty.formatRho`).

**Why it is id-free.**  No step compares or orders an id: `.id` appears only as the KEY of a
position map or of a colour map.  `grep '\.id' core/.../Type.scala` inside `object Canonical`
gives eleven hits — `varOrder`'s `seen.add(v.id)` / `acc += v.id` (building the position list),
`render`'s `colour(v)` fallback `local.getOrElseUpdate(v.id, …)` (a within-constraint
first-occurrence index), `constraintKey`'s `pos.get(v.id)`, `colours`' `fixed.contains(v.id)` /
`occ(v.id)` / `typeVars(c).exists(_.id == v.id)` / `w.id == v.id`, `orderRhs`'s `col.get(v.id)`
and `scheme`'s `xorder.getOrElse(v.id, …)` / `torder.getOrElse(v.id, …)` — every one a map key
or an identity test, none of them a value that is ordered.

**What it is NOT.**  It is a FORM and not a simplification: no constraint is added, deleted or
rewritten.  `new Part` and `new Exists` are used deliberately — `Part.apply` rewrites concrete
rows and `Exists.apply` ends in `p.toSet.toList`, which is the very re-bucketing the object
exists to remove.  (That `toSet.toList` is also where 6.2c's careful `displayScheme` sort was
being thrown away again; review R-7 saw the symptom and read it as rule 1 only HIDING the
residual.)  Deleting a redundant constraint is E11b's and needs an entailment oracle.

**It is not a proof of canonicity.**  Colour refinement is incomplete for graph isomorphism, and
`ROSE-COMPARISON.md` rank 3 asks for the key to be PROVED invariant.  The measurement that
stands in for the proof is the corpus FORM count in §4, now pinned by a test.

## 2. Where it runs, and the intermediate-generalisation decision

**Three sites, all of them "publication" — the module's top-level group, where a binding's
signature is made.**

| site | file | which bindings |
|---|---|---|
| `Subst.generalize`, after `mkSimplified`, when `publishing` | `Subst.scala` | every INFERRED top-level binding |
| `Subst.inferBindingGroupTypes`'s `el`, when `publishing` | `Subst.scala` | every DECLARED (explicit) top-level binding |
| `TolerantCheck.checkWith`'s `types` map | `TolerantCheck.scala` | what the EDITOR hands to hover, `.ei`-free |

The second and third sites are beyond the brief's letter (`Subst.generalize`) and were added
because the measurement demanded them: with `generalize` alone the corpus FORM count fell only
from 129 to **97** (`logs/sweep-after.tsv`).  The 97 were all explicit bindings.  A DECLARED
signature never passes through `generalize`; it reaches the `.ei` through `substType`, whose
`Exists.apply` re-buckets the constraint list by the hash of the SUBSTITUTED types, so two cold
checks of one unedited file ordered it two ways (measured on `Layout/Chart.e`'s `seriesW` and
`Layout/Report/Keyed.e`'s `keyValueTabular`).  That is the other half of ticket E11's "16 of 249
modules render a published type differently on a reuse with no edit".  With the declared half
canonicalised the count fell to 4, and with the tie fixpoint (rule 7) to **3**, all three of them
the KIND class of §4.

**Intermediate generalisations: NO — publishing only, which is the shipped default.**
`-Dermine.canon=all` canonicalises every generalisation, including the intermediate ones the
inference around them re-instantiates.  Measured:

| | corpus verdicts | corpus FORM/SET sweep | looptrace (boot, top, Wide) |
|---|---|---|---|
| `publication` (default) | 89 / 79 / 0 of 168 (`logs/corpus-after.log`) | FORM 0, KIND 1, SET 6 (`logs/ttc2.log`) | 18 groups, 3,210,881 segments, agree = segments, skip 0 (`logs/lt-after.log`) |
| `all` | 89 / 79 / 0 of 168 (`logs/corpus-canonall.log`) | FORM 0, KIND 1, SET 5 (`logs/sweep-canonall.tsv`) | 3 groups, 263,376 segments, agree = segments, skip 0 (`logs/lt-canonall.log`) |

`all` buys nothing the editor's reuse class needs — the FORM count is already 0 without it — and
it reshapes residuals the rule was not aimed at, because an intermediate scheme's order feeds the
solver's queue (the same argument `S5-HYGIENE.md` made for confining the C12 tautology deletion).
Default stays `publication`.  `-Dermine.canon=off` restores the pre-E11a data form (the printer's
label sort is unconditional).

## 3. The E11 four renderings, before and after

Real server, `nondet.py` (the 7.2 review's repro), four cold didOpen/hover/didClose rounds of an
unchanged `core/examples/Present/WriterOutputs.e` in ONE JVM, hover on `reportFor`.
`logs/nondet-before.txt` (pre-change worktree) and `logs/nondet-after.txt`.

**BEFORE — four rounds, four renderings:**

```
0  (exists (b: rho). a <- ((|pTitle, pMinValue, pRegion|), b))
1  (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b))
2  (exists (b: rho) (c: rho). a <- ((|pTitle, pMinValue, pRegion|), c), a <- ((|pRegion, pTitle|), b))
3  (exists (b: rho) (c: rho). a <- ((|pTitle, pMinValue, pRegion|), c), a <- ((|pTitle, pMinValue|), b))
```

**AFTER — four rounds, three renderings, one per constraint SET:**

```
0  (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b))
1  (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b))
2  (exists (b: rho) (c: rho). a <- ((|pMinValue, pRegion, pTitle|), b), a <- ((|pRegion, pTitle|), c))
3  (exists (b: rho) (c: rho). a <- ((|pMinValue, pRegion, pTitle|), b), a <- ((|pMinValue, pTitle|), c))
```

Rounds 0 and 1 are now byte-identical; rounds 2 and 3 carry a SECOND constraint that 0–1 do not,
and that is E11b's — the solver's order-dependent residual, not a form.  Everything the form rule
owns is fixed: the labels are in name order, the first conjunct is the same string in all four
rounds, the letters follow first occurrence, and the partition puts the concrete row first.
`asDocument` renders identically in all four rounds after (two ways before);
`writerOutputs` was and is stable.

This is the checked-in test `TestTolerantCheck` "E11a: four cold checks of one module publish ONE
form per constraint set": renderings with the same `Canonical.key` must be BYTE-IDENTICAL, and
the number of distinct keys is pinned at 3 with E11b named in the failure message.  An assertion
that would pass under alpha-equivalence is not in it: `Canonical.key` says WHICH renderings are
required to be equal, never excuses two that are not.

## 4. The FORM / SET split over the corpus, with counts and def-sites

Two COLD checks of every clean module in ONE JVM (`Resident.checkFile` with a fresh `Documents`
each time, so no per-uri inference cache survives and the `Supply` has advanced between them),
every published top-level binding compared AS RENDERED.

| | files | bindings | identical | **FORM** | KIND | **SET** |
|---|---|---|---|---|---|---|
| BEFORE (`logs/sweep-before.tsv`) | 256 (1 skipped) | 4047 | 3910 | **129** (incl. 3 KIND) | — | **8** |
| AFTER (`logs/sweep-after3.tsv`) | 256 (1 skipped) | 4047 | 4039 | **0** | 3 | **5** |
| AFTER, the checked-in test (`logs/ttc2.log`) | 257 (1 skipped) | 4047 | 4040 | **0** | 1 | **6** |

*FORM* = the two renderings differ with the binder KIND annotations blanked and the same
`Canonical.key` — one constraint set, two forms.  This item's, and **0**.
*KIND* = the two renderings differ ONLY in the kind a binder is annotated with.
*SET* = the `Canonical.key` differs — the published constraint set itself moved.

**The 129 BEFORE, by class** (`logs/sweep-before.tsv`, every def-site listed there): constraint
order inside the `Exists` (e.g. `Layout/Report.e:bar`, `:line`, `:scatter`, `Relation/Op.e:%`,
`:coalesce`), partition right-hand-side order (`Wide/Helpers.e:rankWithin`,
`Time/Helpers.e:latestPerKey`), universal binder order (`Relation.e:setColumn`,
`Yahoo.e:joinCalc`, `Present/Signatures.e:unreconciledFull`), existential binder order and
therefore the LETTERS (`Algebra/SoftSchema.e:fulcrum4`, `PivotTest.e:pivotData`), and concrete
row label order (`Present/WriterOutputs.e:asDocument`, `:asProfiledDocument`,
`Present/ProjectionCost.e:proj4`, `Yahoo.e:joinCumRet`).

**The 3 KIND after, with their whole difference** (`logs/sweep-after3.tsv`; the test's run saw
one of the three, which is why it is pinned at 6 rather than 3):

| def-site | the difference |
|---|---|
| `core/examples/Algebra/SoftSchema.e:pivoted` | `(v34: f)` vs `(v34: rho)` |
| `core/examples/PivotTest.e:pivotData` | `(d)` vs `(rho)` |
| `core/examples/PivotTest.e:pivotData2` | `(rho)` vs `(d)` |

One token each: an existential whose KIND one check left as a kind variable and the other solved
to `rho`.  That is kind inference, not row-constraint form; it is out of E11a's scope, pinned by
the test at 6 so it cannot grow unnoticed, and carried as follow-up F-1 below.

**The SET survivors — E11b's exact target list** (from the test's run, `logs/ttc2.log`):

```
Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'
Relation.e:lookbackJoin
Present/WriterOutputs.e:reportFor
Yahoo.e:investmentTableData
Yahoo.e:joinCumRet
Yahoo.e:joinTotalValue
```

BEFORE the item the same sweep counted 8 (`Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`,
`Relation/RTree.e:level1`, `Relation.e:lookbackJoin`, `Algebra/Signatures.e:runningTotalFull`,
`:runningTotalFullViaWritten`, `Present/WriterOutputs.e:reportFor`, `Yahoo.e:investmentTableData`,
`Yahoo.e:joinTotalValue`).  The class is itself order-sensitive, so the membership moves run to
run; the count is 5–8 either way.  **That is the number E11b takes to 0.**

## 5. The interface classification

`ei-diff.sh --snapshot --batch` with `-Dermine.loadInSeries=true` on both sides — the pre-change
build in `../ermine-scala-wt-e11a` and this one — then `ei-classify.py`.  274 interfaces captured
on each side (`logs/ei-before.log`, `logs/ei-after-t2.log`).

```
== 134 of 274 interfaces differ
== bindings by verdict: {'identical': 2461, 'order-only': 1000, 'other': 47, 'alpha-equivalent': 15}
```
(`logs/ei-classify-ba2.log`)

**`concrete->polymorphic` 0, `polymorphic->concrete` 0** — nothing published got weaker or
stronger by that test.  The gate the brief sets is NOTHING in `other`; there are 47, and they
break down as follows.

**41 of the 47 are order- or alpha-equivalent, and `ei-classify.py` cannot see it.**  Its matcher
(`match_constraint` → `match_items`) returns the FIRST bijection a constraint pair admits, and the
outer `go` has no way to ask for a different one — so one doomed right-hand-side assignment
condemns a match that exists.  `G1Compare.alphaEq` has the same shape
(`alphaEq(c1, cs2(j), e) flatMap …`) and fails on the same inputs.  A matcher that backtracks
over BOTH levels (`<scratch>/e11a/alphacheck.py`, `classify-other.py`; budgeted at 4M nodes,
never exhausted here) re-checks all 47:

```
### 41 of 47 re-checked pairs are alpha-equivalent (order only); 6 genuinely differ
```

Worked example, `Syntax/Relation.(&)`: A `a <- (e, d), r <- (d, c), b <- (e, d, c)`, B
`a <- (c, d), r <- (c, e), b <- (c, d, e)`.  The bijection is `c↦d, d↦e, e↦c`; the greedy matcher
takes `c↦e, d↦d` on the first constraint, which dooms the second, and never revisits it.

**The 6 that genuinely differ are all residual-SET changes (E11b's class), 4 of them in
`core/examples/incomplete/`** — the modules that are non-terminating by design and whose `.ei`
are whatever the timeout left:

| interface | binding | how it differs |
|---|---|---|
| `core/examples/incomplete/RevenueShare.ei` | `shareOfGroup` | no bijection (different residual) |
| `core/examples/incomplete/TargetList.ei` | `restrictTo` | no bijection |
| `core/examples/incomplete/RunCalibration.ei` | `scaledRuns` | no bijection |
| `core/examples/incomplete/np01_add_or_recompute.ei` | `inferredRestate` | different existential count |
| `modules/Layout/Report/Relation.ei` | `cutoffGroupedFldsPosNegRel'` | no bijection |
| `modules/Relation.ei` | `lookbackJoin` | 9 constraints → 8 |

Note also `Record.(++)`: `c <- (b, a)` → `c <- (a, b)`, which is the rule working — `a` is at body
position 0 and `b` at 1.

**Two-base byte identity** (`logs/ei-classify-2base.log`).  Two AFTER-side snapshots at different
id bases — `-Dermine.loadInSeries=true` against `=false`, which is exactly the knob
`Session.scala`'s own note says "reaches interface bytes through the constraint solver's id-hash
queue":

```
== 6 of 274 interfaces differ
== bindings by verdict: {'identical': 3517, 'other': 5, 'order-only': 1}
```

3,517 of 3,523 published bindings **byte-identical** across two different id bases.  The six
exceptions, all named:

| binding | class |
|---|---|
| `Present/WriterOutputs.reportFor` | SET (3 constraints → 1) |
| `Relation.lookbackJoin` | SET (8 → 9) |
| `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` | SET |
| `ChartsExample.stackedPair` | KIND (`{a a1 b b1 c} … (sa: c)` vs `{a b} … sa`) |
| `GridExample.stackedBarChart` | KIND |
| `PivotTest.pivotData2` | KIND (`(v32: rho)` vs `(v32: b2)`) |

**Zero FORM differences across two id bases.**  That is the stability claim this item exists for:
3 SET (E11b's, and the number the roadmap carries) and 3 KIND (follow-up F-1); nothing whose
labels, constraints or binders are merely ordered differently.

## 6. g1

`g1-validate.sh` (`logs/g1-after3.log`): **9 / 9 PASS** — seven oracle fixtures, `double-run
self-agreement` EQUIVALENT (129 files, 1,447 signatures), `no drift from tracker/g1-baseline`.

Before the baseline was re-cut, the drift tripwire fired (`logs/g1-after.log`): 5 files, 14
signature pairs.  `tracker/g1-baseline` was refreshed in the tree (GATE-POLICY: "an INTENDED
signature change refreshes the baseline in the same commit, with the before/after listed"), from
`/tmp/g1-selfA` — `ei/` (38 of 129 files moved) and `browse.txt`; `groups.txt` was byte-identical
and `README.md`, `wall-seconds.txt` untouched.  `git diff --stat tracker/g1-baseline`: 39 files
changed, 286 insertions, 286 deletions.  The pre-change baseline is kept at
`<scratch>/e11a/g1-baseline.ORIG` for the reviewer.

`g1-diff.sh compare <old baseline> <new baseline>` (`logs/g1-oldnew.log`): `129 files, 1447
signatures, 5 differing`, 14 A/B pairs.  Re-checked with the backtracking matcher
(`logs/…`, `alphacheck.py`):

```
### 13 alpha-equivalent, 1 genuinely different, of 14 pairs
```

13 order-only (`cons_Bracket`, `replaceColumn`, `coalesce`, `combine`, `dateDiff`, `if`,
`replace`, `(!=)`, `(<=)`, `(>=)`, `(&)`, `(&_Mem)`, `(**)`); the one that genuinely differs is
`Relation.lookbackJoin`, §7.

`browse.txt`, 1,301 signature lines, **95 changed**, 0 added, 0 removed:

| class | count |
|---|---|
| concrete-row label order and/or partition right-hand-side order | 54 |
| same tokens, reordered (constraint order and/or binder order) | 35 |
| order plus a renaming of bound variables (alpha) — `(&_Relation)`, `(&_Mem_Relation)`, `(**_Relation)`, `drilldownPivotTabular`, `drilldownPivotTabular'` | 5 |
| the residual SET moved — `lookbackJoin` | 1 |

## 7. `Relation.lookbackJoin` — the one signature whose SET moved, and why it is not a form bug

```
BEFORE  (exists … 11 existentials. r1 <- (c1, e), b <- (h, g, f), r1 <- (c2, r), o <- (g, f),
         t <- (d, c1, e), t <- (r, d, c2), r2 <- (d, c1), a <- (h, g), a <- (c, r))      9 constraints
AFTER   (exists … 11 existentials. r1 <- (r, c), r1 <- (c1, d), a <- (r, e), a <- (f, g),
         b <- (f, g, h), r2 <- (c1, i), t <- (c1, d, i), o <- (g, h))                     8 constraints
```

**Control.** `g1-diff.sh run new` in the PRE-CHANGE worktree reproduces the 9-constraint form
(`logs/g1-before-run.log`); the same run on this build reproduces the 8-constraint form, and the
two independent boots of this build agree with each other (the `double-run self-agreement` check).
So it is a deterministic consequence of this change, not run-to-run noise.

**Mechanism.**  `lookbackJoin` is INFERRED.  Its residual comes from the solver, whose queue order
follows the order in which the schemes it instantiates present their constraints — and those
schemes are now in canonical order.  This is the same "the published order feeds call sites"
effect the brief anticipates for the row traces, arriving on a published signature.  It is
exactly the class `ROW-CONSTRAINT-STATE.md` records as entailment-equivalent and PERF-ROADMAP P10
/ the G1 delta already name `lookbackJoin` for.

**Evidence it is usable.**  `lookbackJoin` has 17 call sites in the corpus
(`Time/ReadingHistory.e`, `Time/Signatures.e`, `Time/Helpers.e`) and every one of them still
type-checks: corpus verdicts 89 / 79 / 0 of 168, unchanged.  A published scheme that had become
too weak would break the definition; one that had become too strong would break the call sites;
neither happened.  The full ROSE `⊒`-in-both-directions check is not attempted here — it is
E11b's oracle, and this is the reviewer's call.

## 8. Goldens

| golden | verdict |
|---|---|
| `tracker/repl-tests/*.expected` | **NOT MOVED.**  `repl-smoke.sh` 8 groups / 66 checks, all PASS (`logs/repl-smoke-1.log`) |
| `tracker/lsp-tests` pins | **NOT MOVED.**  `lsp-smoke.sh` `PASS lsp (573 checks)` (`logs/lsp-smoke-1.log`) |
| 6.2b / 6.2c pinned sets | **NOT MOVED.**  `agreed 174, disagreed 65, requantified 94, constraint elided 58, usable constraint lost 0, hover SHOWS a constraint 12`; 6.2b `Arg(equation) 2874/2874 … misses 29, agreed 2869 disagreed 14` (`logs/tier0-suites.log`) — the same def-site strings as the baseline |
| `tracker/g1-baseline` | **RE-CUT**, §6: 38 `.ei` files + `browse.txt`, 95 of 1,301 browse lines, classified above |

`TestReplDifferential` is part of the full `core/test` run in §12.

## 9. Corpus outputs

Verdicts **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168** on both sides
(`logs/corpus-before.log`, `logs/corpus-after.log`), and under `-Dermine.canon=all`
(`logs/corpus-canonall.log`).

The `.out` texts, after normalising the tree path and every wall-clock figure: **27 of 168
differ**, in three classes and nothing else.

| class | count | example |
|---|---|---|
| internal variable ids only (`r^1496142S` → `r^1495118S`) | 11 | `shouldfail_sk01_row_append_self` |
| concrete-row LABEL ORDER in an error message — the printer change, intended | 6 | `mis03`: `with type (\|region, orderId\|)` → `(\|orderId, region\|)` |
| the row-partition blame message / caret moved on a `shouldfail` fixture | 10 | `inc04`: "the whole contains it but no part does" → "a part contains it but the whole does not" |

The ten blame-message movers are all in `shouldfail*` and all still REJECTED at the same file and
(with one exception) the same line: `inf05_union_two_fields` moves within line 23 from column 18
to column 30 and names field `b` instead of `a`.  This is the blame-location mechanism
`ROW-CONSTRAINT-STATE.md` documents — which partition the per-label check reaches first — moving
because the published order moved.  Full list in `logs/` via the `cmpb`/`cmpa` normalised trees.

## 10. Traces

**Fidelity gate, AFTER side** (`LOOPTRACE_PAR=3 looptrace-corpus.sh`, `logs/lt-after.log`):
**18 groups, 3,210,881 segments, `agree` = `segments` on every group, `skip=0`, `rc=0`,
`timeouts=0`, `dropped=0`.**  The Lean model reproduces the compiler segment for segment.
`TestLoopTrace` 720 solves / 720 segments / 720 agree / skipped 0 / hashdiff 0 / eqdiff 0
(`logs/tier0-suites.log`).

**Blast radius** (`trace-ab.py` against the pre-change traces, all sixteen record kinds,
`logs/trace-ab.log`).  IDENTICAL is not expected: the published order feeds every call site.

| group | segments | IDENTICAL | PERMUTATION-ONLY | CONTENT-DIFFERS | KINDCOUNT-DIFFERS | sinmoved |
|---|---|---|---|---|---|---|
| boot | 54,209 | 7,986 | 0 | 46,221 | 2 | 1 |
| top | 92,747 | 40,685 | 52 | 52,008 | 2 | 1 |
| Ai | 83,976 | 10,782 | 10,311 | 56,946 | 5,937 | 23,227 |
| Algebra | 101,039 | 42,194 | 8,209 | 50,159 | 477 | 10,117 |
| Algebra-shouldfail | 55,401 | 8,620 | 28 | 46,749 | 4 | 2 |
| bugs | 54,245 | 8,022 | 0 | 46,221 | 2 | 1 |
| guide | 54,254 | 8,027 | 0 | 46,225 | 2 | 1 |
| incomplete | 1,905,718 | 286,649 | 350 | 1,618,627 | 92 | 156 |
| Lang | 94,542 | 41,494 | 11 | 53,035 | 2 | 1 |
| Lang-shouldfail | 58,789 | 11,580 | 0 | 47,207 | 2 | 1 |
| Present | 131,400 | 76,214 | 182 | 55,002 | 2 | 1 |
| Present-shouldfail | 59,503 | 9,471 | 12 | 50,018 | 2 | 1 |
| shouldfail | 56,291 | 9,838 | 6 | 46,445 | 2 | 1 |
| shouldfail-controls | 55,266 | 8,978 | 0 | 46,286 | 2 | 1 |
| Time | 125,386 | 68,029 | 680 | 56,672 | 5 | 3 |
| Time-shouldfail | 55,908 | 9,004 | 134 | 46,766 | 4 | 3 |
| Wide | 116,420 | 43,282 | 14,004 | 56,576 | 2,558 | 20,655 |
| Wide-shouldfail | 55,787 | 8,898 | 179 | 46,708 | 2 | 1 |

Reading it: the per-group SEGMENT COUNTS are identical before and after — the solver runs the same
number of solves — and the bulk of `CONTENT-DIFFERS` is the `scon` record, which lists a solve's
input constraints in order with their hash codes, and which therefore moves for every solve whose
instantiated scheme was re-ordered.  `KINDCOUNT-DIFFERS` — the multiset of record KINDS changed,
i.e. the solver did different work — is 2 on most groups (the `sin` bounds) and concentrates in
`Ai` (5,937), `Wide` (2,558) and `Algebra` (477); those three are also where `sinmoved` is large.
`concrete identities in A: 0` on every group.

## 11. Performance

**Batch A/B (the shipped `publication` default), `perf-bench.sh batch -n 3`, FOUR interleaved rounds, alone,
loads 0.33-1.25** (`logs/perf-before-1..4.log`, `logs/perf-after-1..4.log`; cold median seconds in-process):

| round | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| before | 11.56 | 11.41 | 11.33 | 11.22 |
| after | 11.50 | 11.37 | 11.40 | 11.39 |

Median of medians 11.37 -> 11.395 s (**+0.22 %**); mean of medians 11.38 -> 11.415 s (+0.3 %).  Inside the ~1 %
floor; round 4's after-side is the one high reading and rounds 1-2 go the other way.

**`-Dermine.canon=all` against `publication`, two interleaved rounds each** (`logs/perf-pub-1..2.log`,
`logs/perf-all-1..2.log`): publication 11.31 / 11.28 s, all 11.51 / 11.57 s — canonicalising every intermediate
generalisation costs **+2.2 %** on the batch target, which with §2's "buys nothing the editor needs" is why the
default is `publication`.

**Per-file corpus wall times, medians of three interleaved rounds each side** (`<scratch>/e11a/cb-1..3/`,
`ca-1..3/`, the per-file `(N.NN seconds)` line of each module): 168 files, sum of medians 27.9 -> 27.0 s
(-2.9 %).  Movers > 20 %: `Wide_WardRoster.e.out` 1.44 -> 0.69 s (-52 %), `Ai_IncidentSeverity.e.out` 0.29 -> 0.22 s (-24 %).  Largest moves by ratio:

| file | before | after | delta |
|---|---|---|---|
| `Wide_WardRoster.e.out` | 1.44 | 0.69 | -52 % |
| `Ai_IncidentSeverity.e.out` | 0.29 | 0.22 | -24 % |
| `Present_Helpers.e.out` | 0.26 | 0.24 | -8 % |
| `Wide_MediaSpend.e.out` | 0.27 | 0.29 | +7 % |
| `Present_SortShowcase.e.out` | 0.33 | 0.35 | +6 % |

**Editor A/B, `perf-bench.sh editor -k 15` (debounce pinned 300), two interleaved rounds** (`logs/perf-ed-*.log`):
round trip before 0.912 / 0.913 s, after 0.904 / 0.919 s; typecheck segment before 0.540 / 0.535 s, after
0.525 / 0.540 s; `read` 0.050 s on all four.  Flat — the editor path canonicalises one `types` map per check.

(Sections 11 and 13 were filled in by the orchestrator from the implementer's logs after an accidental interrupt
stopped the implementer during its Tier 2 run; the numbers are the implementer's, the prose is not.)

## 12. Gates

(Filled by the orchestrator from the implementer's logs; see the note at the end of §11.)

| gate | expected | measured | log |
|---|---|---|---|
| `core/compile core/copyResources` | clean | clean | `logs/compile4.log` |
| `TestLoopTrace` | 720/720 | 720 solves, 720 segments, 720 agree | `logs/tier0-suites.log` |
| `TestTolerantCheck` | 56 + the item's | **58 / 58** on the final build (57 on the previous) | `logs/ttc2.log`, `logs/tier0-suites.log` |
| 6.2b / 6.2c pinned sets | unchanged | `agreed 2869 disagreed 14`; `heads … usable constraint lost 0, hover SHOWS a constraint 12` | `logs/tier0-suites.log` |
| the FORM/SET corpus property | FORM 0 | FORM 0, KIND 1, SET 6 (§4) | `logs/ttc2.log` |
| `corpus-run.sh --batch` | 89/79/0 of 168 both sides | 89 / 79 / 0 of 168, verdicts identical (§9) | `logs/corpus-before.log`, `logs/corpus-after.log` |
| `repl-smoke.sh` | 8 groups, goldens untouched | 8 / 8 PASS, no golden moved (§8) | `logs/repl-smoke-1.log` |
| `lsp-smoke.sh` | 573 | PASS lsp (573 checks) | `logs/lsp-smoke-1.log` |
| `g1-validate.sh` | 9/9 EQUIVALENT | 9 / 9, `129 files, 1447 signatures, EQUIVALENT`, no drift against the RE-CUT baseline; old-vs-new baseline EQUIVALENT (§6) | `logs/g1-after3.log`, `logs/g1-oldnew.log` |
| `ei-diff` before vs after | identical / order-only / alpha only | 134 of 274 differ: identical 2461, order-only 1000, alpha-equivalent 15, **other 47** (§5: re-checked with a complete matcher; the reviewer re-checks) | `logs/ei-classify-ba2.log` |
| two-base byte identity | only the SET class differs | 6 of 274 differ: 5 other (the SET class) + 1 order-only; 3517 of 3523 bindings byte-identical | `logs/ei-classify-2base.log` |
| looptrace, AFTER side (fidelity) | agree = segments, skip 0, 18 groups | 18 groups, 3 210 881 segments, **0 mismatches**, rc 0, timeouts 0, dropped 0 | `logs/lt-after.log` |
| `trace-ab.py` vs BEFORE | not IDENTICAL (expected); blast radius reported | §10 | `logs/trace-ab.log` |
| batch / editor A/B | inside the floor / flat | §11 | `logs/perf-*.log` |
| Tier 2 `core/test` ALONE | 1068 + the item's, 0 failed | the implementer's run was interrupted (`logs/core-test.log`, partial); the orchestrator's re-run: **1070 / 1070, 0 failed, 0 errors, 1380 s (23:00), no intermittent** (1068 + the two new properties) | `logs/core-test-2.log` |
| `.ei` by `find` | 0 | 0 after the runs (the orchestrator cleaned 7 under `target/` left by the interrupted `core/test`) | — |
| diff parity, line endings | `--histogram` == `-w`; CRLF/LF preserved | equal; `Type.scala`/`Pretty.scala` CRLF, others LF, unchanged (§13) | — |

## 13. Files changed

```
14	1	core/src/main/scala/com/clarifi/reporting/ermine/Pretty.scala
30	2	core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala
234	0	core/src/main/scala/com/clarifi/reporting/ermine/Type.scala
45	53	core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala
136	1	scalacheck-binding/src/main/scala/TestTolerantCheck.scala
(+ 39 files under tracker/g1-baseline/ re-cut, line-for-line: browse.txt 95/95 and 38 .ei files; §6)
```

`git diff --stat --histogram` equals `git diff --stat --histogram -w` for the code (no
whitespace-only reflow).  Line endings preserved: `Type.scala` and `Pretty.scala` CRLF,
`Subst.scala` ASCII/LF, `TolerantCheck.scala` and `TestTolerantCheck.scala` UTF-8/LF — `file`
reports the same before and after.

## 14. Follow-ups

* **E11b, with its exact target.**  Six published bindings whose constraint SET differs between
  two cold checks — `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'`, `Relation.lookbackJoin`,
  `Present/WriterOutputs.reportFor`, `Yahoo.investmentTableData`, `Yahoo.joinCumRet`,
  `Yahoo.joinTotalValue` — and three interfaces whose bytes are not stable across two id bases for
  the same reason.  That is the number E11b takes to 0.  `TestTolerantCheck` pins it at 10 and
  prints the def-sites on every run.
* **F-1: an existential's KIND is left as a kind VARIABLE by one check and solved by the other.**
  Three def-sites (`Algebra/SoftSchema.pivoted`, `PivotTest.pivotData`, `PivotTest.pivotData2`),
  plus `ChartsExample.stackedPair` and `GridExample.stackedBarChart` across two id bases.  One
  token each, in a binder annotation.  Kind inference, not row-constraint form; pinned at 6 by the
  corpus property so it cannot grow unnoticed.  Not scheduled.
* **F-2: both shipped alpha comparators are incomplete in the same way.**
  `tracker/tools/ei-classify.py`'s `match_constraint`/`match_items` and
  `G1Compare.alphaEq`/`matchMultiset` commit to the FIRST bijection a constraint pair admits and
  cannot revisit it, so they report `other` / `differing` on signatures that ARE alpha-equivalent
  — 41 of 47 in §5 and 13 of 14 in §6.  The fix is to make the inner match yield every extension
  (a generator) rather than an `Option`, under a node budget.  Until then a red from either tool
  needs the backtracking re-check by hand.  Both are gate tools, so this is worth a small item.
* **F-3: the canonical key is measured, not proved.**  `ROSE-COMPARISON.md` rank 3 asks for the
  key to be PROVED invariant; `Rowpartition/Canonical.lean` already carries a terminating,
  meaning-preserving non-generative canonicaliser and ROSE §4's `IsCanonicaliser`.  Formalising
  the Scala rule against them is deferred by the user ("formalize more broadly later").

## 15. Review corrections (tracker/loopmodel/E11a-REVIEW.md, ACCEPT WITH FIXES; applied by the orchestrator 2026-09-13)

* **R-1 (blocking) — FIXED in the tree.** The corpus FORM property was red about one run in three: `Canonical.key`
  is name-free but the RENDERING was not — `Pretty.fresh` prefers a variable's name hint, and the solver's minted
  existentials carry different hints run to run (witness `Relation.e:lookbackJoin`, 8 cold checks, 4 keys, three of
  them rendering two ways). Decision (the user): the solver's hints go, positional letters take their place. The
  rule as shipped, after a first version that dropped EVERY existential name and was withdrawn on the g1 diff (it
  turned the class-named constraint variables `AsOp opl` into `b1 opl` and replaced the user's own `exists (t: rho)`
  in declared signatures): `Canonical.scheme(t, dropHints)` drops a LOWERCASE `Local` hint on an INFERRED scheme's
  existentials (`Subst.generalize`, and the 6.2c local-head display); a capitalised hint is a class-named constraint
  variable and is kept (stable: the class name); a DECLARED signature (`inferBindingGroupTypes`'s `el`, and the
  editor's `types` map) passes `dropHints = false` — its names are the user's. Universals keep theirs everywhere. The
  g1 baseline is re-cut a second time (letters only); `.ei` letters move (alpha-only). Gates after the fix: §16.
* **R-6 — FIXED.** `-Dermine.canon=off` now reaches the editor: `TolerantCheck`'s `types` map and `displayScheme`
  call `Canonical.scheme` only under `Canonical.atPublication`.
* **R-2.** §5's "6 genuinely differ" is **4**: `incomplete/TargetList.restrictTo` and `incomplete/RunCalibration.scaledRuns`
  ARE alpha-equivalent (the review's complete matcher: bijections of 74 and 192 nodes, verified by substitution).
* **R-3.** §14's "exact target" moves run to run (the class is itself order-sensitive, §4): six on the run of
  record, 5–8 across runs; the UNION over the review's three runs is eight plus `Layout/Report.drilldownKeyValueTable2`
  and, in `incomplete/`, `RevenueShare.shareOfGroup` and `np01.inferredRestate` — E11b's list is that union.
* **R-4.** "No module slower by > 10 %" is false: `Interp.e` 0.14 → 0.18 s (+29 %, samples overlap) and
  `Ai/ClinicalTrial.e` 0.16 → 0.18 s (+12 %, samples do not) — both under 40 ms absolute.
* **R-5.** §11's two headline movers are measurement variance, not solver work: `Wide/WardRoster.e`'s trace record
  multiset is IDENTICAL before/after across all sixteen kinds and its before-side samples are bimodal
  (`[0.64, 1.47, 1.44]`); `Ai/IncidentSeverity.e` moves by two records of ~11,600. The real work shift in `Wide` is
  `learn` 61,759 → 60,535 and `step` 19,906 → 19,796, in records that carry no module location; covered by
  `KeyedSplit.lean`'s `terminatesOnSatKeyed` (every run order) and `Loop/PolicyTerm.lean`'s `budgetP_terminates`.
* **R-7.** §6's browse.txt classification is 87 order / 7 alpha / 1 SET (`(<=_Predicate)` and `(>=_Predicate)` need a
  renaming), not 89 / 5 / 1; 0 outside the classes.
* **R-8.** §7 undersells: TWO stdlib signatures' sets moved — `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'`
  is stdlib (its before/after admit no bijection: arity profile 3×part/4 + 3×part/5 vs 4 + 2) — and, mitigating, it
  is itself in the SET class (differs between two cold checks of ONE build), so the before/after difference is not
  E11a's. `lookbackJoin`: AFTER = BEFORE minus one conjunct that follows from three survivors by substitution
  (`REquiv`, hand-proved in the review).
* **R-9.** ROSE §4's `OrderIndependent` is NOT claimed and is not required (ROSE §4.3, the P = NP argument); the SET
  class is exactly the `REquiv`-but-not-equal class.
* **R-10.** The caps are never reached on the corpus: colour-refinement rounds `(0: 3570) (2: 468) (3: 7) (4: 2)`,
  tie-fixpoint rounds `(0: 1850) (1: 2169) (2: 26) (3: 2)`, 0 schemes unsettled at either cap — rules 2 and 7
  terminate by fixpoint, not truncation. The rule canonicalises only the OUTERMOST quantifier; a nested rank-N
  `forall`'s binder order is untouched (the review's shuffle probe: 10 mismatches of 6,591, all nested foralls, 0
  under the scoped attack).
* Also from the review: `g1-diff.sh compare old new` reads DIFFERS (13/14 alpha or order + `lookbackJoin`), not
  EQUIVALENT — §6 stands corrected; `ei-classify.py` needs its matcher AND its parser fixed (the parser mis-reads an
  unparenthesised context and alone accounts for 17 of the 47) — filed as a follow-up, not changed here.

## 16. Gates after the fix round (orchestrator, 2026-09-13 14:20-14:53; logs `logs/fix2*.log`)

Run SERIALLY on purpose: a first attempt ran g1-validate beside an interface snapshot and the snapshot's `.ei`
files landed in the build output g1 reads ("130 .ei files, expected 129", double-run self-agreement FAIL) — a
contamination, not a finding; the gates share `core/target` and cannot overlap.

| gate | result | log |
|---|---|---|
| compile + copyResources | clean | `logs/fix-compile.log` |
| `g1-validate.sh`, alone | run 1: self-agreement PASS, drift FAIL (letters); baseline re-cut from `/tmp/g1-selfA` (browse.txt + ei/); run 2: **PASS / PASS** | `logs/fix2-g1-1.log`, `logs/fix2-g1-2.log` |
| `g1-diff.sh compare ORIG new` | DIFFERS on 14 pairs in 5 files (`lookbackJoin`, the three comparison predicates with class-named existentials, row operators) — the comparator's matcher on reordered schemes (review §"The 47"), not drift; the `.ei` classifier on the same change below says alpha-only | `logs/fix2-g1-origvsnew.log` |
| `ei-diff --snapshot` vs the pre-fix after side + `ei-classify` | 274 captured; 25 of 274 differ; **identical 3456, alpha-equivalent 67, other 0** | `logs/fix2-ei.log`, `logs/fix2-ei-classify.log` |
| `lsp-smoke.sh` | PASS lsp (573 checks) | `logs/fix2-lsp.log` |
| `TestTolerantCheck` x3 | **58/58, 58/58, 58/58**; sweep FORM **0 / 0 / 0**, KIND 3 / 2 / 2, SET 6 / 5 / 6 | `logs/fix2-ttc-1..3.log` |
| `.ei` by `find` | 0 | — |
| diff parity, line endings | `--histogram` == `-w` (477/57 over the five sources); `Type.scala`, `Pretty.scala` CRLF | — |

Tier 2 stands at 1070/1070 (§12) from before the fix round; the fix round changed one naming rule and two
`atPublication` guards and is covered by the three property runs, the classifier and the smoke tests above.
