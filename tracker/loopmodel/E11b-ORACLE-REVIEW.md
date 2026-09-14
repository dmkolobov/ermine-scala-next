# Review of E11b Phase 1 — `tracker/loopmodel/E11b-ORACLE.md`

Reviewer's scratch and logs:
`<rev>` = `/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle-review/`.
Implementer's scratch `<scratch>` = the sibling `e11b-oracle/`; the probe's pairs `<prev>` as the report names them.
Nothing under `core/src/main`, `session/`, `tracker/lean/` was touched; the throw-away driver I re-created under
`core/src/test/scala/e11btmp/` is deleted and its compiled classes removed; `find core/target -name '*.ei'` = 0;
no `lake build`; nothing committed; `git status` shows the report, the two briefs and this review.

## VERDICT: ACCEPT WITH FIXES

The recommendation itself survives review: candidate (A) `SigEntail.check`, `pxs` = the candidate's PRIVATE
existentials, row constraints only as candidates, the proxy encoding for concrete left-hand sides, greedy fixpoint
in canonical order, KEEP on every lapse, placed after `Canonical.scheme`. Every code citation I checked is correct,
the cost table and the convergence table reproduce from the logs, and (B)'s rejection is well argued.

Two findings block the report's CONCLUSIONS rather than its recommendation: the measured proxy encoding is not the
one §4.3 describes (R-1), and with the encoding corrected the "beyond the oracle" list and the "SET 6 -> 4"
headline both move (R-1, R-2). Fix those two and the document is sound.

### R-items

* **R-1 (BLOCKING).** *The proxy encoding was measured with `z` RIGID, which is not the encoding §4.3 argues is
  verdict-preserving, and it systematically under-deletes.* In the driver (`<scratch>/OracleDriver.scala.txt`
  line ~85) the proxy is minted `fresh("z" + n, Free)` and is **not** added to `ex`, so `pxsFor` can never return
  it and `z` is never in `F`. §4.3 says "`z` must NOT be in `pxs`" — but for an OBLIGATION that is exactly wrong:
  `z` is a *defined* auxiliary, its definition `z <- ((|K|))` travels inside `W`, and unless `z` is free to choose,
  `check` branches over it in `extra` (`SigEntail.scala:533`) and refutes `W` at the first node. Consequence: every
  candidate with a concrete left-hand side whose `K` appears on no OTHER left-hand side is reported `NotEntailed`
  at 1-3 nodes although it is entailed. Worked witness, `after3:joinCumRet` side A constraint 6,
  `(|initValue|) <- (d, c)`: the rest of the set contains `(|adjClose,initValue|) <- ((|adjClose|), d, c)`, from
  which it follows; the log says `NOTENTAILED nodes=1` (`<scratch>/v2-private-proxy-first.log`). Corrected (one
  line: `ex += z`) and re-run on the identical `cases.txt` (`<rev>/zfix-private-proxy-first.log`,
  `<rev>/zfix-last.log`, `<rev>/zfix-min.log`):

  | | concrete-LHS candidates `Ok` | all row candidates `Ok` | converged, first | last | min |
  |---|---|---|---|---|---|
  | as measured in the report | 30 of 140 | 394 of 751 | 7/31 | 8/31 | 13/31 |
  | with `z` existential | **88 of 140** | **452 of 751** | **9/31** | **10/31** | 13/31 |

  and the two new convergences are `after:investmentTableData` (15->6 and 13->6, SAME) and `after:joinTotalValue`
  (7->4 and 6->4, SAME) — two of the four bindings §1 names as beyond the oracle. Also `after3:joinCumRet` becomes
  A 7->4 / B 5->4 instead of 5 / 4. So: re-measure with `z` in `pxs`, or state plainly that the proxy was measured
  in its weaker form and the figures are a lower bound. Soundness is not at risk either way (the error is always in
  the KEEP direction), only the report's conclusions.

* **R-2 (BLOCKING for the headline).** *"SET 6 -> 4" is not what the recommended configuration achieves.* Under the
  recommended rule (greedy, first deletable, canonical order) `lookbackJoin` converges in **1 of its 3 sweep pairs**
  (`before` only) — §1 and §9 both say so, and then §1 counts it closed. The measured ceiling under the
  recommendation is **6 -> 5**; 6 -> 4 needs `last` (2 of 3) or the exhaustive rule the report explicitly does not
  propose (3 of 3). Corrected encoding does not change this (`<rev>/zfix.log`: `after:lookbackJoin` and
  `after2:lookbackJoin` still DIFFERENT under `first`). Conversely R-1 makes the same headline *undersell* the
  Yahoo family. The honest form of the claim is a per-sweep convergence count with the rule named, not a "6 -> N".

* **R-3.** *The satisfiability precondition is not discharged where §4.1 says it is.* `Subst.scala:2136`'s
  `solve(Exists(l, List(), extinct))` runs on `extinct` — the constraints being THROWN AWAY (the partition at
  `:2131-2133`, comment "solve constraints before throwing them away") — not on `dumb`/`pruned`, which is what gets
  published and what the oracle would read. So "`mkSimplified` already refuses such a residual at the `extinct`
  solve (`:2136`) before any deletion pass would run" is unsupported. The failure mode is benign (an unsatisfiable
  `Q` makes every `c` vacuously `REquiv`-deletable, and a `c` that CONTRADICTS a satisfiable `Q` is refuted, not
  accepted), but the sentence must be corrected and the ROSE §4.6 precondition left as an assumption with a named
  discharge site or none.

* **R-4.** *The exhaustive-minimum rule is order-free but not convergent, and I have a counterexample.*
  `<rev>/synth.txt` case `synth:cycle3`: variant A = `{x <- (y), y <- (z), x <- (z)}`, variant B = `{x <- (y),
  y <- (z)}` (equivalent, all three universals). Measured (`<rev>/synth-and-rules.log`): `first` deletes `x <- (y)`
  from A and lands on `{y <- (z), x <- (z)}` (DIFFERENT from B); `last` deletes `x <- (z)` and lands exactly on B;
  **`min` deletes `y <- (z)` and lands on `{x <- (y), x <- (z)}`, which is neither A nor B**. So `min`'s 13/31 is a
  property of this corpus and its shape tie-break, not a principle; §6's "which by construction is order-free" is
  true and irrelevant to convergence. Worth one sentence in §6.

* **R-5 (confirmation, with a stronger witness).** The `pxs` correction is right, and the orchestrator's sketch is
  not merely unjustified but **unsound**. Code: `qv` is built from the readable givens only (`SigEntail.scala:448`)
  and `F = wv.filter(v => pxsSet(v) && !qv(v))` (`:491`), so a variable pinned solely by a dropped given is free to
  re-choose. Executable witness, `<rev>/synth.txt` case `synth:pxsUnsound`: universals `{a}`, existentials
  `{x, y}`, `sys = { (|k|) <- (x, y), a <- (x) }`. With `pxs = all`, `check` returns `Ok` on `a <- (x)` (1 node) and
  the driver deletes it; but before deletion the residual forces `a ⊆ {k}` and after deletion `a` is unconstrained,
  so the deletion is NOT `REquiv` — a real soundness failure, not a gap in the proof. With `pxs = private` the same
  call is `NoVerdict` = KEEP. (§5.1's own witness shows only an unjustified acceptance; this one shows a wrong one.)
  Note the interaction the report does not state: the proxy encoding makes that particular given READABLE and so
  closes this instance by itself; private-`pxs` is still required for the Unreadables the proxy does not cover
  (several literal sets on one right-hand side, `:335`) and for class constraints.

* **R-6 (cost).** Arithmetic checks against `<scratch>/cost-summary.txt` and `<scratch>/size-distribution.txt`:
  325 row constraints over 1,301 signatures, x 3.11 = 1,011 calls, x 0.19 ms = 0.19 s for ONE pass, 0.4-0.6 s at
  2-3 rounds, i.e. **1.6 % for one pass and 3-5 % at 2-3 rounds** against a 10-14 s batch. The report quotes the
  upper band and flags it prominently, which is what the brief asked. Three caveats to add: (i) the 4047/1301 scale
  factor assumes `browse.txt` is representative of the corpus's published bindings — unverified; (ii) the 0.19 ms
  mean comes from a set dominated by the six pathological bindings, so it is if anything pessimistic per call and
  optimistic per round count; (iii) with R-1 fixed there are MORE deletions, hence more rounds, so the upper end of
  the band is the one to plan against. Nothing here changes "measurable, above E11a's 1 % floor, needs an
  interleaved A/B".

* **R-7 (determinism).** Verified against the code: `F` `:491`, the `Ok` trapdoor for an unencodable obligation
  `:455-457` (with `encode`'s `NotRow` at `:367`/`:375-378`), `encode`'s non-empty literal left-hand side
  `Unreadable` at `:360`, budgets `:397-398`, `labels ... .sortBy(_.toString)` `:499`, `extra ... .sortBy(canonVar)`
  `:533`, `canonVar` `:646`, `canonKey` `:650` (it does embed `v.id`), `canonRows` `:654`. Placement: `mkSimplified`
  at `Subst.scala:1776`, `Canonical.scheme` at `:1793` — §9's claim holds. `sks = Nil` is justified: `generalize`
  filters `_.ty != Skolem` at `:1764` and `:1770`, and in any case `foreign` can only downgrade a REJECT, never
  license an ACCEPT. I did not check the `Part.apply` normalisation claim (`Type.scala:408-431`) or the Lean
  citations.

* **R-8 (confirmation).** Correction (ii), row-only candidates, is real and necessary: `wRows.isEmpty` +
  no caveat returns `Ok` (`:455-457`), and a class constraint encodes to `NotRow` which raises no caveat by design.
  `<scratch>/run-private.log` shows the consequence (all 140 class constraints "deleted"). The report's suggestion
  that `check` grow a `NotRow`-means-no-verdict mode for this caller is the better fix.

## Point by point

**1. Breaking the soundness argument.** Attacks run on paper against `SigEntail.check` (`:418-616`, read in full)
and, where they bit, executed through the driver.

* shared existentials — refuted by the argument: such a variable is in `qv`, hence not in `F` (`:491`), hence
  universally quantified in the check's judgement, which is STRONGER than `DELETABLE`. Sound and conservative.
* a fresh existential in `c` — refuted: it is in `F` and re-choice is exactly what `DELETABLE` licenses, provided
  `F ∩ vars(sys \ {c}) = ∅`, which private-`pxs` guarantees syntactically over the WHOLE of `sys \ {c}` (class
  constraints and Unreadables included — the driver's `pxsFor "private"` does compute it over all givens).
* a universal occurring only in `c` — refuted: a universal is never in `pxs`, so never in `F`.
* **a concrete left-hand side — HOLE, and it is the report's own R-5/§5.1 hole, executable** (see R-5). The report
  finds and fixes it; I confirm the mechanism in the code and give a residual where the sketch's verdict is
  genuinely wrong rather than merely unlicensed.
* **the proxy encoding — HOLE in the other direction (R-1)**: as measured, an obligation's proxy is rigid and the
  verdict is a spurious `NotEntailed`. KEEP-side, so not a soundness hole, but it invalidates §4.3's
  "verdict-preserving" as a description of what was run.
* class constraints as candidates — **HOLE, found and fixed by the report** (R-8).
* unsatisfiable `Q` — refuted as a soundness matter (vacuous `REntails`), but the discharge site is miscited (R-3).

**2. Two pairs re-derived by hand.**
`before:lookbackJoin` / `after:lookbackJoin` (`<prev>/pairs/after__lookbackJoin.txt`): I confirm the oracle's
verdicts in `<scratch>/v2-private-proxy-first.log`, including the non-obvious ones — `r2 <- (h, c1)` goes because
`r2` is private; `t <- (c1, d, h)` goes on A only after `r2` has gone; and B's `r1 <- (r, c)` is deletable up front
because the `h`-pair plus `r1 <- (c1, d)` gives it, which is the strand the report describes. The greedy-first
outcome A 8->4, B 9->6 is right, and so is the reason `last` fixes it here and breaks `before`.
`after3:joinCumRet` (`<prev>/pairs/after3__joinCumRet.txt`), by hand: A's `r <- ((|adjClose,initValue|), b, rs)`
and `r <- ((|adjClose|), b, c, rs, d)` entail each other given `(|initValue|) <- (c, d)`, so one goes and the other
then has a private `r` and goes too — matches the log (this is the mutual-entailment pair point 3 asks for).
`(|adjClose,initValue|) <- ((|adjClose|), c, d)` IS entailed by `(|initValue|) <- (c, d)` and the log's
`NOTENTAILED` is wrong — that is how I found R-1; with `z` existential the same call is `Ok` (`<rev>/zfix.log`) and
A reaches 4. A's surviving `t <- ((|adjClose,initValue|), so, rs, b)` and B's `t <- ((|adjClose|), so, d, rs, c, b)`
are then two 4-constraint cores of the SAME size differing only in the folded/unfolded `t`, which no deletion can
equate because `t` is a universal and deletion only removes.

**3. Convergence.** `<scratch>/cmpfinal.py` re-run by me on five of the implementer's logs
(`<rev>/cmpfinal-rerun.txt`): 7/31 first, 8/31 last, 13/31 min, and 7/31 for both `pxs=all` and the no-proxy run —
the report's table reproduces exactly, pair by pair, including `lookbackJoin` 1/2/3 and `runningTotal*` SAME only
under `min`. Break attempt: R-4's three-cycle, which defeats `first` and `min` and is saved by `last`; together
with the report's own `before`-vs-`after` `lookbackJoin` trade this settles that **no scan direction is the rule**,
and that `min` is not a canonicaliser either. I did not find a rule that works.

**4. Cost.** See R-6. Figures read correctly from `<scratch>/cost-summary.txt`; the 28-constraint stress case is
27 row-constraint calls per pass (13 class constraints are never candidates), 8,723 nodes / 13 ms with the proxy,
62,690 nodes / 39 ms without, and the per-scheme extrapolation follows.

**5. Determinism and placement.** See R-7. The `canonKey` id tie-break is real and can only bite through a budget
lapse; the measured 38x margin is on THIS corpus and on the six worst bindings in it, which is reasonable evidence
but not a bound — Phase 2 keying the sort on `Canonical.key` is the right call. Placement claim confirmed
(`:1776` vs `:1793`).

## What I did NOT check

Candidate (C) entirely — `candC.py` was not read or re-run, and its 11/9/15 and its soundness argument are
unreviewed. The 12 control pairs and the "blast radius" claim (`melt3Full` 23->20 etc.) were not re-run. The
claim that the three intermittent bindings are unrecoverable from the sweeps. The `Part.apply` normalisation
provenance (`Type.scala:408-431`) and the fidelity of the rebuilt `Type` values to what the compiler would hand
`check` — the whole measurement rests on that reconstruction and I checked only that the driver's variable
flavours and `pxs` computation match what it claims. The ROSE/Lean citations (`Basic.lean:525`,
`entails_iff_forall_label`, `Loop.solve_noFalseAccept`). The exhaustive-min 257,536-call / 60 s figure. §9's Lean
estimate. No corpus run, no `core/test`, no `.ei` comparison, no perf A/B.

## Logs

* `<rev>/cmpfinal-rerun.txt` — the implementer's `cmpfinal.py` re-run on five of his logs (point 3's confirmation).
* `<rev>/zfix-private-proxy-first.log`, `<rev>/zfix.log` (same, sbt noise stripped) — the corrected proxy
  (`z` existential), greedy-first, all 31 pairs.
* `<rev>/synth-and-rules.log` — six runs in one sbt invocation: the two synthetic cases under
  `pxs=all`/`private` x `first`/`last`/`min`, and the full corpus under the corrected proxy with `last` and `min`.
* `<rev>/zfix-last.log`, `<rev>/zfix-min.log` — those last two, split out for `cmpfinal.py`.
* `<rev>/synth.txt` — the two synthetic residuals (R-4's three-cycle, R-5's soundness witness).

**Time spent: 17 minutes wall clock** (19:56:08 to 20:13 on 2026-09-13, this machine's clock) against a 1 h budget,
of which about 4 minutes was the two sbt invocations. Nothing was cut for time; the "did NOT check" list above is
what a review of this scope deliberately leaves to the report's own logs.
