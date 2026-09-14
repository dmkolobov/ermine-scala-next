# E11c review — the cause of the SET class, flagged fix

Reviewer run 2026-09-13 23:11–23:27, branch `scala3-migration`, HEAD `ebd2de1b` plus the implementer's
uncommitted five-file working tree.  Brief `tracker/loopmodel/briefs/brief-E11c-review.md`; report under review
`tracker/loopmodel/E11c-SOLVEDET.md`.  Implementer scratch `<s>` =
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c/`;
my scratch `<r>` = the sibling `…/scratchpad/e11c-review/`.  Nothing committed, no source/Lean/tracker file
changed but this one, no default flipped, `find core/target core/examples -name '*.ei'` is 0 after my runs.

## Verdict

**ACCEPT WITH FIXES.**  The mechanism is real and correctly identified, the fix is small, flag-gated and
default OFF, and I re-verified the load-bearing gates on the CURRENT tree rather than taking them from the
report: OFF is byte-identical to the pre-change compiler across all 274 interfaces (the report's NOT DONE 2,
now closed), `TestLoopTrace` under ON is 720/720 on the final build, and the corpus output under ON is
identical to OFF on all 168 files down to the blame sentences (only timings differ).  The fixes are wording
and one open question, none blocking, because nothing ships until the user flips the default.

| # | item | blocking |
|---|---|---|
| R-1 | §5's "All figures below are on the FINAL build" is not supported by the file times: `Subst.scala` and `Constraints.scala` were last written 22:16, after the sweeps (22:08), `TestLoopTrace` (22:10), corpus (22:11/22:12) and g1 (22:14/22:15) logs it cites.  I re-ran the two that matter and they hold, so this is a wording fix, not a re-run. | no |
| R-2 | "No rule, guard or verdict reads either order" is too strong in two places (see point 1): `ps` is also consumed by `checkSaturated` (`rssat` is ON at the shipped defaults), whose search order and node count are order-dependent; and the SCC change re-orders bindings WITHIN a component, which re-orders the constraint list handed to `solve` — the report's own audit row 24 says queue insertion order decides definition-vs-unification.  Both are justified empirically by the gates, not structurally; say so. | no |
| R-3 | `ChartsExample.e:stackedPair` publishes THREE FEWER implicit kind binders under ON (`{a a1 b b1 c}` → `{a b}`), i.e. a strictly LESS kind-polymorphic signature.  The report calls it "not the row solver" and the `ei-classify` summary "no published type got weaker" does not cover kind generality.  Decide which inference is intended before any default flip. | no |
| R-4 | `Q.canonLt` ties fall back to `sortWith`'s stability, i.e. to the base-dependent finger-tree order, and `canonKey`'s `canonSep = 1000000000` assumes every id stays below 1e9.  Both bounds are the ones `smallcanon` already lives with, so this is a note for the record rather than a defect. | no |
| R-5 | "SET 5 → 2" is not a subset improvement, and the two are not a fixed pair.  The same-build OFF control's five do NOT include `lookbackJoin`, ON's two DO — and my own run of the CHECKED-IN property under ON produced `cutoffGroupedFldsPosNegRel'` + `Yahoo.e:investmentTableData` instead (point 3), i.e. a binding the report lists as "gone".  The count is 2 in all four ON runs; the membership rotates, and only `cutoffGroupedFldsPosNegRel'` is constant.  The report should say the survivor SET is a count, not a named pair. | no |

## 1. The change itself

Read the whole `git diff` (5 files, 79/7).  Under OFF every touched expression is literally the pre-change
expression in an `else` branch; the flag is a `val` read once at `GenRules` class init next to `tautoDelete`,
and it reaches `Session.interfaceKey` through `GenRules.toString` (`session/Session.scala:184`).  I confirmed
on disk that OFF's key string is byte-identical to the shipped one and ON appends `+solvedet`
(`<r>/rv-ei-classify.log` last line).

**(a) The SCC driver.**  `SCC.tarjan` is correct for any choice of DFS roots, and the roots only pick which of
several valid topological orders of the condensation comes out; a component is still emitted only after
everything it depends on, which is the property `sccs.reverse` relies on.  `comps(i)` on a repeated id is
absorbed by the `index` test, as claimed.  I checked every consumer of the component list for an order
assumption and found none that breaks:

* `Session.writeInterface` (`session/Session.scala:578-585`) sorts the definitions **by name** before
  printing, precisely so interface bytes do not follow an id-keyed iteration — the `.ei` writer is immune.
* `tools/G1Groups.scala:50-56` sorts both within a group and across groups.
* `TolerantCheck`'s per-SCC cache (`session/TolerantCheck.scala:985-1010, 1025`) fingerprints a component from
  spellings **sorted**, plus the upstream fingerprints of its refs — and refs point at dependencies, which any
  valid topological order has already processed.  The old code's comment at :993-997 complains that `comp`
  order "is NOT stable between runs"; ON makes it stable, so this path gets better, not worse.
* `Subst.inferBindingGroupTypes` (`Subst.scala:880-902`) accumulates a `Map` (order-free) and a list `ds`
  whose order is cosmetic.

The one real caveat is R-2(b): the ON branch of `implicitBindingComponents` also sorts the bindings INSIDE a
component into source order, and `inferImplicitBindingTypes` (`Subst.scala:920-940`) accumulates `cs` in that
order, so the constraint list reaching `solve` — and hence the queue's insertion order — changes.  Audit row
24 (`Constraints.scala:547-551`) says insertion order is exactly what decides `CommonPartition` unification
versus a fresh definition.  So this is not a cosmetic re-order; its safety rests on the gates (720/720 model
agreement, corpus output identical), which is a good argument but a different one from "no rule reads it".

**(b) The saturated set.**  `q.expand` has exactly ONE call site in the whole compiler (`Subst.scala:1637`;
`grep -n '\.expand\b'` finds only comments elsewhere), so the sort covers every consumer of that list.  Inside
`solve`, `ps` feeds three things: `reduce` (`:1341`, the non-confluent right fold — the target),
`checkSaturated(ps.map(_.tup))` when `rowSoundSat` is on, and the trace dump.  `rowSoundSat` IS on at the
shipped defaults (`+rssat` in the key), so the sort does change something else: the `LabelSearch` order over
`ps`, which the report's own audit row 51 classifies as "verdict INVARIANT, node count DEPENDENT (can flip a
budget no-verdict)".  Nothing moved in practice — the corpus messages are identical, `NO VERDICT` warnings
included — but the claim in the code comment should be "reduce, plus a search whose verdict is order-invariant
and whose node count is not" (R-2a).

`Q.canonLt` is `intListLt(canonKey(a), canonKey(b))`, `canonKey` being the key `smallcanon` already dequeues
by: sorted rhs var ids, `canonSep`, sorted `lblKey`s of the concrete part, `canonSep`, lhs id
(`Constraints.scala:638-648`).

*Totality.*  `RHS(abstr: Set[TypeVar], concr: Fields)` (`Constraints.scala:347`) and `V.equals` is id equality,
so two partitions with equal `canonKey` have the same abstract set, the same lhs, and concrete parts with equal
`lblKey` multisets.  Distinct partitions can therefore tie only if two distinct `Name`s share a `lblKey`
(same kind tag, module, string and fixity).  On a tie, `sortWith` is stable and falls back to the finger-tree's
base-dependent order — a hole of exactly the size `smallcanon`'s dequeue already has, and one no measurement
here contradicts (R-4).  `intListLt` is a plain lexicographic strict order, so no TimSort contract violation.

*Base invariance.*  Under a constant shift of every var id, each `canonKey` shifts elementwise in its id
positions and is unchanged in its label positions; comparisons between an id and `canonSep` keep their sign as
long as ids stay below `canonSep = 1e9`; comparisons of two ids are shift-invariant.  So the sort is invariant
under any strictly monotone renumbering of ids below 1e9 — the claim holds, with that bound named (R-4).

*The other lists.*  Of the first draft's list, `liveInput` (`Subst.scala:1543`) and `topFamilies`
(`Constraints.scala:2296`, and `topNormalise` aside) read the queue, not `ps`; `resolvents`, `concRows` and
`learnPartitions` (rows 33/35/37) are inside the loop, fold over `Set[Partition]`, and are untouched — see
point 4.  The sort does not reach any of them: it happens after the loop, after every range split, and the
tree itself is not re-keyed, so D1 review T-2's requirement (`PQueue.findRHS`/`contains`/`sandwich` are range
splits on `(rhs.hashCode, lhs.hashCode)`) is respected.

**Premise corrections confirmed.**  `Type.scala:169` is `ProductT.hashCode = 38 + n*17`, base-invariant;
`Vars.scala:109` is `override def hashCode = id.hashCode`, literally the id.  The implementer's correction of
the brief is right.

## 2. NOT DONE 2 and 8 closed

**(a) OFF byte-identity on the FINAL build — CLOSED, empty.**
`tracker/tools/ei-diff.sh --batch --snapshot <r>/ei-off-final "-Dermine.loadInSeries=true"` after
`sbt core/compile core/copyResources` on the current tree (`<r>/rv-compile.log`, `<r>/rv-ei-off.log`:
"274 interfaces captured", rc 0), then `diff -r <s>/ei-pre <r>/ei-off-final` — **0 lines**
(`<r>/rv-eidiff-off-final.log`).  So the default-OFF compiler with all five files edited is byte-identical to
the pre-change compiler over all 274 published interfaces.  The snapshot deletes its own `.ei`; I verified 0
remain.

**(b) `ei-classify.py <s>/ei-pre <s>/ei-on` — reproduced exactly** (`<r>/rv-ei-classify.log`):
`interfaces: A 274 B 274`, 7 of 274 differ, `{'identical': 3516, 'order-only': 1, 'other': 6}`.  Identical to
the implementer's `<s>/g2-ei-classify.log`.  Hand classification of the six `other`:

* `Present/WriterOutputs.e:reportFor` (3 → 1).  ON keeps `a <- ((|pMinValue,pRegion,pTitle|), b)` and drops
  `a <- ((|pMinValue,pRegion|), c)` and `a <- ((|pRegion,pTitle|), d)`.  Both dropped conjuncts follow from the
  survivor by choosing the existential: `c := {pTitle} ⊎ b`, `d := {pMinValue} ⊎ b`.  **Entailed; ON strictly
  smaller and equivalent.**
* `Relation.e:lookbackJoin` (8 → 9).  ON's extra conjunct is `j <- (r, c, k)` alongside `j <- (d, e, k)`,
  with `r1 <- (r, c)` and `r1 <- (d, e)` present on both sides: `j = d ⊎ e ⊎ k = r1 ⊎ k = r ⊎ c ⊎ k`.
  **Entailed by the survivors** — the same B6 argument E11a-REVIEW used.  (The remaining difference, A's
  `j <- (d,k)`/`m <- (h,i)` against B's `l <- (h,i)`/`m <- (e,k)`, is the same content: both `d # k` and
  `e # k` follow from the ternary `(d,e,k)` conjunct each side carries.)
* `Layout/Report.ei:drilldownKeyValueTable2` (5 → 6).  ON's extra `a2 <- (k, v, b1)` follows from
  `a2 <- (k,v,i,r)` and `b1 <- (i,r)`.  **Entailed.**
* `Layout/Report/Relation.ei:cutoffGroupedFldsPosNegRel'`.  Not an order read — see point 4.
* `incomplete/RevenueShare.ei:shareOfGroup`.  Same family (different splits of the same rows); `incomplete/`
  is outside the clean corpus.
* `ChartsExample.ei:stackedPair`.  No row constraint moved; the implicit KIND binder list goes
  `{a a1 b b1 c}` → `{a b}`, i.e. `tdxfyf'`, `tdxfyf` and `sa` lose their kind variables and take `*`.
  This is the `typeDefComponents` half of the change and it makes the published signature LESS general
  (R-3).  No corpus client notices — the whole corpus still loads identically under ON — but "no published
  type got weaker" is a claim about types, not kinds, and this one is about kinds.

## 3. Targeted suites re-run on the FINAL build

* **`sbt -Dermine.solveDet=true 'core/testOnly *TestLoopTrace'` — 720 solves / 720 segments / **720 agree**,
  skipped 0, hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0; `Passed: Total 3, Failed 0`
  (`<r>/rv-looptrace-on.log`).**  This is the figure R-1 doubted; it holds on the current tree.  The
  model-agreement invariant says the change moved an ORDER and not a DECISION on the model's population.
* **`corpus-run.sh --batch` OFF vs ON** (`<r>/rv-corpus-off.log`, `<r>/rv-corpus-on.log`, 168 files each).
  `corpus-verdicts.py` output identical (`<r>/rv-verdict-diff.log`, rc 0).  Stronger: `diff -r` of the raw
  per-file outputs contains only timing lines and progress bars — every remaining differing line is one half
  of a `(N.NN seconds)` pair (`<r>/rv-corpus-out-diff.log`, checked by stripping timings: zero unmatched
  lines).  So every message, including every refutation's blame sentence and every `NO VERDICT` warning, is
  byte-identical under ON.
* **The E11a properties under ON** — `sbt -Dermine.solveDet=true 'core/testOnly *TestTolerantCheck -- -f
  "E11a"'`, i.e. the CHECKED-IN properties, not the transcript (`<r>/rv-e11a-on.log`).  Both pass:
  `Passed: Total 2, Failed 0`.
  * "four cold checks of one module publish ONE form per constraint set": OK.
  * "the corpus sweep — two cold checks publish ONE form": `257 files (1 skipped), 4047 published bindings,
    **4045 identical**; **FORM 0, KIND 0, SET 2**`, the two being **`Relation.e:cutoffGroupedFldsPosNegRel'`
    and `Yahoo.e:investmentTableData`**.
  * **This is a DIFFERENT SET membership from the implementer's three runs** (`cutoffGroupedFldsPosNegRel'` +
    `lookbackJoin`, `<s>/gate2-sweep-true-{1,2,3}.log`), and a different KIND count (0 here, 1 there).  The
    count is 2 in all four ON runs and the ceilings hold, but the MEMBERSHIP rotates: `lookbackJoin` is absent
    from my run and `investmentTableData`, which the report lists as "gone" under ON, is back.  That is
    consistent with point 4's diagnosis — a residual base-dependent read inside the loop lands wherever the
    base falls — and it sharpens R-5: under ON the survivors are not a fixed pair of bindings, only
    `cutoffGroupedFldsPosNegRel'` is constant.

The sweep figures I accept from the implementer's logs rather than re-running three times:
`<s>/gate2-sweep-false-1.log` tail — `257 files (1 skipped), 4047 published bindings, 4039 identical;
FORM 0, KIND 3, SET 5` (`cutoffGroupedFldsPosNegRel'`, `reportFor`, and the three `Yahoo.e` bindings), and
`<s>/gate2-sweep-true-{1,2,3}.log` — `4044 identical; FORM 0, KIND 1, SET 2`
(`cutoffGroupedFldsPosNegRel'`, `lookbackJoin`).  Note R-5: the ON two are not a subset of the OFF five.

## 4. The two survivors

**`Relation.e:lookbackJoin` — one more local read, and it is INSIDE the loop, not a third boundary read.**
The evidence I checked:

* Under ON, six consecutive cold checks of `Relation.e` alone publish ONE key (`<s>/exp-lbj.log`, rounds 1-6
  identical, 9 constraints); as shipped the same six checks publish FOUR distinct keys (`<s>/s4-lbj-false.log`:
  rounds 1, 2≡6, 3≡5, 4).  So both boundary reads really are closed for this binding at this scale.
* The two variants that remain are entailment-equivalent, and the difference is WHICH existential
  decomposition got minted or reused (the `j <- (r,c,k)` conjunct derived in point 2), not how one set is
  rendered.  A mint-vs-reuse difference is what audit rows 33/35/37 produce.
* No third read is needed to explain it: `resolvents` (`:1928`), `concRows` (`:1965`) and the
  `proc.foldLeft` at `:2020-2049` fold over `Set[Partition]`, whose iteration order follows
  `Partition.hashCode` (audit row 28, a composite MurmurHash over raw ids).  A CHAMP trie's shape changes only
  when enough hash bits change, which is why the read is invisible across the small base jumps of six checks
  of one module and visible across the 257-file sweep's jumps.  That is consistent with everything measured.

* And my own ON sweep (point 3) puts `Yahoo.e:investmentTableData` in the class and `lookbackJoin` out of it.
  So the residue is not a property of `lookbackJoin` at all: it is a read that lands on whichever binding the
  base happens to disturb, which is what a `Set[Partition]` iteration inside the loop looks like and is NOT
  what a third fixed boundary read would look like (a boundary read would move the same binding every time).

So: **"one more local read", but one the boundary sort cannot fix** — those sites decide mint versus reuse, so
re-ordering them changes what the solver DERIVES, not the order in which it derives it.  Leaving them alone is
the right call under the brief's STOP POINT, and the implementer's claim that this is not a third read is
supported.  Caveat, and I could not close it inside the budget: nobody has trace-diffed the two ON variants of
`lookbackJoin` at two sweep-sized bases.  Until that exists, rows 33/35/37 are the best-supported explanation,
not a measured one.  It is the one loose end I would put on the follow-up list.

**`Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'` — beyond a solver re-ordering.**  Confirmed from the
`ei-classify` output I produced: the two sides bind a DIFFERENT NUMBER of existentials — 40 (`…j1, k11`)
against 41 (`…k11, l1`) — and carry the rows through different splits (`f <- (k, g, l, m)` against
`f <- (k, d, j, l)`, and so on down the list).  No bijection can exist between sets of different size, so this
is generative, exactly E11b-PROBE §5.4's variable-split case, and no visitation order closes it.

## 5. Adoption readiness

Flipping `solveDet` to default ON is a Tier 2 adoption (`tracker/GATE-POLICY.md`) AND a shipped-behaviour
change: two published signatures move and one loses kind polymorphism.  What the adoption commit would need
that is not yet done:

1. **`sbt core/test` in full under ON.**  The 1070/1070 run (`<s>/g2-coretest-off.log`) is OFF only.
2. **Interleaved perf A/B**: `perf-bench.sh batch -n 3` OFF/ON/OFF/ON, run alone under load < 1.3.  Not run at
   all; the cost is one `sortWith` per solve and one `zipWithIndex.toMap` per binding group, plausibly noise,
   but unmeasured.
3. **g1 baseline re-cut** with the before/after recorded: under ON `g1-validate.sh` reports 2 of 1447
   signatures differing (`<s>/g2-g1-on-cmp.log`).  The baseline must be re-cut in the adoption commit, not
   before.
4. **`looptrace-corpus.sh` ON vs pre-change through `trace-ab.py`** (18 groups) — the brief's Tier 1 item the
   implementer could not run.  The `Relation.e` segment diff is one module.
5. **Checked-in coverage of the 5 → 2.**  Nothing in `core/test` records it: the E11a properties read the SET
   class at the shipped default, so their ceilings would not notice a regression of the new order.  Tighten
   the corpus property's SET ceiling in the same commit that flips the default (and decide what it should be,
   given R-5's membership change).
6. **A decision on R-3** (`stackedPair`'s kind binders) and on the two row-constraint signature changes, since
   both are visible to downstream users.
7. **Interface-key churn**: flipping the default changes `GenRules.toString` for every shipped configuration,
   so every cached `.ei` in every working tree is invalidated at once.  Harmless but worth saying in the
   commit message.
8. Tracker updates the implementer was not allowed to make: ROW-CONSTRAINT-STATE.md's flag table and the
   LSP-ROADMAP E11 entry.
9. The 2.11 back-port branch carries its own copy of `SCC.scala`/`Subst.solve`; decide whether the flag
   travels (out of scope here, but it is a fork that has taken every other solver change).

**Reasons not to adopt, as I see them.**  (i) The class is not closed — SET 2, not 0 — so a consumer still
cannot depend on a stable published set; the user is buying a partial fix at the price of a behaviour change.
(ii) One of the two survivors is NEW to the sweep under ON (R-5), so "more deterministic" is regime-relative,
not absolute.  (iii) R-3 is unexplained.  (iv) The within-component re-order (R-2b) reaches the solver's
insertion order, which is decision-relevant; the evidence that nothing changes is empirical and strong
(720/720, corpus byte-identical) but it is not a structural argument, so the blast radius outside the corpus
is not bounded by anything but measurement.  None of these is a reason to reject the CHANGE as it stands —
default OFF, OFF proven byte-identical — only reasons to keep the default where it is until 1-6 are done.

## What I did NOT check

* I did not re-run the E11a corpus sweep three times, nor at a second base; I accept `<s>/gate2-sweep-*.log`.
* I did not re-run `g1-validate.sh` (OFF or ON), the REPL/LSP smokes, or `sbt core/test`; I accept
  `<s>/g2-g1-off.log`, `<s>/g2-g1-on-cmp.log`, `<s>/g2-repl-smoke.log`, `<s>/g2-lsp-smoke.log`,
  `<s>/g2-coretest-off.log`.  R-1 notes that the g1 logs predate the last source write; the OFF side is
  nevertheless covered by my own 274-interface byte-identity diff.
* I did not re-derive the step-1 trace diff (`<s>/s1-ab-marked.log`, `<s>/s4-ab-on.log`) or re-cut the
  segment dumps; I read the report's argument and checked its code sites.
* I did not trace-diff the two ON variants of `lookbackJoin` at sweep-sized bases (point 4's caveat), and I
  did not audit rows 33/35/37 beyond confirming that they fold over `Set[Partition]`.
* No perf measurement, no `looptrace-corpus.sh`, no Lean.

## Time

23:11 to 23:27 MDT, about 16 minutes of wall clock (the machine was fast tonight; the 1 h budget was not needed).  Roughly: 15 min reading the briefs, report and diff; 10 min code
review of the five sites and their consumers; the OFF snapshot ran in the background throughout (7 min of
that); 10 min on the classification and the two survivors by hand; 10 min re-running `TestLoopTrace` ON, the
corpus A/B and the E11a properties; the rest writing this up.
