# Does the shipped row rule set terminate on WELL-TYPED input?

Exploration of 2026-09-02/03, Lean-first, following `tracker/PROMPT-default-termination.md`
(answered the same day: the "complementary defences" claim is false, `DefaultDiverge.lean`).
Every result below is labelled THEOREM (Lean, `tracker/lean/Rowpartition/`), MEASUREMENT
(the real `Constraints.incorporateAll`, instrument named) or ANALYSIS (paper, `tracker/satterm/math/`).

## 1. The answer

*(Update 2026-09-03, later: the keyed split guard of §3b is ADOPTED as the default,
`ermine.splitKey`; §3c is its measurement, §3d the post-flip re-run. The answer below is about
the syntactic guard, now `-Dermine.splitKey=false`. §3e is Stage 3: the keyed guard's
termination theorem is about the ADDITIVE relation and does NOT survive the loop layer's
deletions — `not_TerminatesOnSatKeyedLoop`.)*

**For the additive rule set with the syntactic split guard: NO.** `TerminatesOnSat` — every
productive run of the shipped-until-today rule set `DefaultStep` (`cut` + guarded resolution)
from every satisfiable input is bounded —
is refuted by a two-constraint satisfiable system (`Rowpartition/DefaultSatDiverge.lean`,
`not_TerminatesOnSat`):

    W2 :  p <- (e1, e2, (|k|)),   p <- (e2, (|k|))        model  p = {k, m},  e2 = {m},  e1 = ∅

`e1` is forced empty. Round 0 mints a name for `{e1, e2}`. Every later round is three
productive steps: cancellation of `p <- (e2, k)` against `p <- (u, k)` gives the alias link
`e2 <- (u)`; substituting it into `p <- (e1, e2, k)` gives `p <- (e1, u, k)`; the group `{e1, u}`
is unnamed, so `splitConcrete` mints `u' <- (e1, u)` and `p <- (u', k)`. The empty `e1` recurs
in every group without violating disjointness, so one parent (`p`, rank 2) acquires
infinitely many split children (all rank 1). That is exactly the gap `DefaultTerm.lean` §9
had isolated: the rank argument bounds depth, the resolution guard bounds resolution
branching, and nothing bounds split branching per parent.

**For the shipped loop: no counterexample, three defences, no theorem.** The loop is not the
additive relation. On `W2` it mints ONCE and stops (MEASUREMENT, 1000 of 1000 id bases,
`tracker/repro/satterm/`): cancellation derives `e1 <- ()`, `makeEmpty` erases `e1` from every
partition — which turns the mint's own definition into the singleton `u <- (e2)` — and that
singleton is UNIFIED (`e2 := u`), never substituted. The Lean's substitution step is never
enabled. The same happens to `H2` (the single decomposition hidden one level up) and to
`NE6` (all input rows nonempty; the empty is a resolution mint that nothing exposes at once):
3000 of 3000 runs solve, at most 8 fresh ids. What protects the loop is therefore:

1. **names travel with their groups** — a substitution-closed run rewrites the name's own
   definition with the same link, which names the next group before the mint can fire
   (`subst_names_travel`, a one-step lemma; the run-level statement is Conjecture S below);
2. **eager unification** of every singleton link `a <- (b)` (the `RHSAbstr(Single)` branch
   pre-empts `learnPartitions`), so a link is never a substitution premise;
3. **eager `makeEmpty`** of every DETECTED empty, which removes the recurring variable.

None of these is stated by any Lean relation; `Saturate.SatStep` is too permissive (unordered
`weaken`, no eagerness). The loop's termination on well-typed input is therefore an
unproved property of the ORDER in which the single-pass worklist applies its deleting and
renaming steps — supported by every measurement, refuted by none.

## 2. What is proved (THEOREM)

`Rowpartition/DefaultTerm.lean` (82 theorems, verified independently):

* `DefaultRun` (productive runs), `TerminatesOnSat` (the question).
* No non-generative rule touches the vocabulary; each mint adds exactly one fresh variable;
  no rule invents a label (`NonGenStep.allVars_eq`, `DefaultStep.allVars_cases`,
  `DefaultStep.concSub`).
* Over a vocabulary `V` and labels `L` there are at most `|V|·2^|V|·2^|L|` `mk`-shaped
  constraints and every rule emits `mk`-shaped ones, so a run is no longer than the shapes
  over its FINAL vocabulary (`DefaultRun.length_le_forms`); an unbounded run mints without
  bound, and mints are exactly the vocabulary growth (`CountRun.mints_eq_allVars_growth`).
* The model extends along a run, forced at the mint (`DefaultStep.extend`,
  `DefaultRun.extend`); every mint's child has strictly smaller rank than its parent
  (`mintParent_rank_lt`, `split_rank_lt`, `res_rank_lt`); rows shrink down the parent
  relation, so every rank is bounded by the largest input row (`DefaultRun.rank_le`).
* Resolution branching per parent is at most `2^|L|` (`CountRun.res_branching_le`); split
  branching per parent is bounded only by the named groups of the FINAL system
  (`CountRun.split_branching_le`) — the gap.

`Rowpartition/DefaultSatDiverge.lean` (40 theorems, verified independently):

* `W2Inv` (the invariant), `W2Inv.round` (three productive steps, +4 constraints,
  +1 variable, invariant re-established), `W2Inv.run`, `W2Inv.run_exact`.
* `SatDiverge.W2`, `W2_models`, `W2_sat`, `W2_unbounded`, `W2_diverges : Diverges W2` (the
  exact-length form of `DefaultDiverge`), `W2_witness`, **`not_TerminatesOnSat`**.
* `subst_names_travel`: substituting a bare link into the definition of a name yields a bare
  definition naming the rewritten group — the mechanism of defence 1, stated for one step.

Axioms: every headline theorem uses only `propext`, `Classical.choice`, `Quot.sound`
(`#print axioms`, both modules); `Audit.lean` after integration: **1929 theorems audited, 0 using a non-standard axiom** (`lake build` 813 jobs).

## 3. What is measured (MEASUREMENT)

* `tracker/repro/satterm/` (real `Subst.solve`, exact ids, default flags): `W2`, `H2`, `NE6`
  SOLVED at 1000/1000 bases each; `W2` one mint, killed by `empty` then `unify` at 100/100
  traced bases; `H2` 2–3 mints; `NE6` 2–6 fresh ids (8 with `resGuard=false`), ending through
  `makeConcrete`. Controls: `nongen` mints nothing and solves all three; `resGuard=false`,
  `genRules=all`, `labelCheck=false` all solve.
* `tracker/satterm/measure/` (generator families and the six `.slow` well-typed divergers,
  default flags, verified by nine fresh re-runs): nothing diverges. `RowStress` is exactly
  quadratic in saturated partitions (`1.5N² + 5.5N − 7`, zero mints); the `gen-row-overlap`
  family derives NOTHING under `cut`; the `.slow` modules load in 0.08–0.33 s, `gu05` in 7 s
  (corpus maximum: one solve of 1,372 partitions and 436 fresh ids). **`ResStar`** (m
  single-label projections of one row, satisfiable) is EXPONENTIAL: saturated partitions grow
  as `3^m` (ratios 3.14 → 3.04 for m = 2..9), surviving minted ids are `2^m − m − 1` exactly —
  the guard's per-variable bound attained — module time rises about 6× per label (m = 9:
  92 s; m = 10 exceeds 120 s), and 77 % of the derivations at m = 9 are re-derivations of
  present `Resolution` conclusions. Termination is not in question there; work is.
  `core/examples/incomplete/README.md`'s per-file timings are stale (they were measured under
  `genRules=all`).
* `tracker/tools/rowclosure.py` (faithful additive-closure explorer; calibrated on `gSeed`,
  `CRule.W`, `resSeed`; cross-checked against a naive implementation on 734 closures):
  UNVERIFIED — the explorer agent's two runs were killed (session limit, then a server
  overload) before its report was returned or audited. What survives are its draft reports
  and search log (`tracker/satterm/explorer/`): it found the same engine independently
  (seed `twodecomp`: `a <- (e, y, (|1|))`, `a <- (e, (|1|))`, all parts empty, machine-checked
  for six levels), reports the mint cap hit on 939 of 5,000 random satisfiable seeds
  (~18 %), every one through an empty-row variable (of the seed or a resolution mint), and
  fixpoints under its breadth-first strategy on every seed. Treat those numbers as a draft
  until the tool's rule-by-rule faithfulness audit is done; the theorem above does not
  depend on them.

## 3b. The repair, proved (THEOREM, Stage 1 — `Rowpartition/KeyedSplit.lean`, 57 theorems)

The loophole is the split guard's KEY. `splitConcrete` asks "does anything name this
GROUP" (`¬ Named G (vset c)`), and groups are what the `W2` engine manufactures. Under a
model the minted variable's row is forced by `(lhs, concrete part)` alone — `rho u = rho p \ K`
— which is exactly how `resolution`'s guard is keyed (`Resolved G v K`). `KSplitStep` keys the
split the same way: mint iff `¬ Resolved G c.lhs c.conc`; otherwise emit `u <- (S)` for the
existing name `u` (entailment: `ksplit_reuse_sat`, `KSplitStep.reuse_models_iff`; the mint is
unchanged and a conservative extension, `ksplit_mint_conservativeExt`). The keyed witness
`p <- (u, K)` has resolution's shape, so `ResGuardTerm.unfired`/`gmeas` is a budget for BOTH
mints, every non-generative and reuse step is non-increasing, and the run bound follows
with no new idea and no König:

    KRun.length_le : KRun n G₀ G → SModels rho G₀ → ConcSub L G₀ →
                     n ≤ M · 2^M · 2^|L|,   M := |allVars G₀| + gmeas L rho G₀
    terminatesOnSatKeyed : TerminatesOnSatKeyed
    keyed_vs_syntactic   : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSat

On `W2` the keyed guard refuses even round 0 (`SatDiverge.W2_not_keyed_mint0`: `W2`'s own
second constraint already resolves the key; the reuse emits the self-partition
`e2 <- (e1, e2)`, from which self-substitution exposes `e1 <- ()`). Explorer check
(`rowclosure.py --split-key`, default off, byte-identical baselines): `W2`, `H2`, `NE6` reach
verified fixpoints under all eight strategies; 2,000 random satisfiable seeds, breadth-first
and mint-greedy: 0 mint-cap hits, max 11 mints (183 cap hits under the shipped guard).
Honest limits: the two calculi are incomparable, not nested (`split_mint_not_keyed`);
unsatisfiable input is untouched (`gSeed` still diverges under guarded resolution); the
compiler flag is `-Dermine.splitKey`, implemented and measured in §3c. Write-up:
`tracker/satterm/KEYED-SPLIT.md`.

### 3c. Stage 2 — the flag, MEASURED (2026-09-03, `tracker/satterm/KEYED-SPLIT-STAGE2.md`)

`-Dermine.splitKey` is implemented in `Constraints.scala` (`GenRules.splitKey`, default OFF;
`SplitKeyed` provenance tag; `splitConcrete` takes `learnPartitions`' resolvent lookup and,
on a hit `v <- (w, concr)`, emits `w <- (abstr)` and mints nothing). The Scala guard is the
Lean guard exactly: the lookup omits the dequeued premise, which cannot witness its own key
(a witness has one abstract variable, the premise has two or more). Every gate was run flag
off vs on from ONE compiled class set, each with a positive control:

* seeds: `W2`/`H2`/`NE6` SOLVED 300/300 on both sides; `W2` draws no fresh id with the flag
  on (1–2 off), and its trace is `SplitKeyed: e2 <- (e1, e2)` then `SelfSubstitution: e1 <-
  ()` — `KEYED-SPLIT.md` §6 executed; `W`/`gseed` REJECTED 200/200, output byte-identical
  bar the banner; the KeepMint instance still mints 16/16 on both sides (its key is open).
* stdlib boot 129 modules, traces byte-identical (the split never fires there); `core/test`
  903/904 on both sides (the known `disjunction sound` generator starvation); `repl-smoke`
  4/4, `lsp-smoke` 98/98.
* corpus verdicts 23/43 and 18/16, 0 of 66 and 0 of 34 files differ; `shouldfail/` 40/40.
* published types: 188 interfaces / 1,932 bindings, 0 weaker. Two flag-OFF runs of one build
  already differ on 4 of 188 (control); only two bindings are attributable to the flag, one
  alpha-equivalent (`RunCalibration.scaledRuns`) and one with an extra FORCED existential
  (`np01.inferredRestate`, 7 -> 8 constraints).
* timing: `ResStar` 5–9, `RowStress`, `CoStar` unchanged (ratios 0.81–1.09); `gu05` 6.1 s ->
  1.2 s of module time (3 runs each; re-measured independently 6.06 -> 1.31 s), because five
  keyed reuses take its large solve from 1,372 to 458 saturated partitions and its `learn`
  records from 103,258 to 19,022.
* population: 77 keyed firings in 18 of 110 example modules, split mints 692 -> 637 under the
  serialized loader (a lower bound; the parallel loader gives `gu05` alone 69 mints and 5
  reuses); one module, `np01`, mints MORE (101 -> 108) — the calculi are incomparable.

Recommendation in the report: ADOPT WITH CAVEATS. The caveats: it is a behaviour change (ids
shift, one forced existential appears, one module mints more); it does nothing for ill-typed
input, where `not_CRule` still lives; the theorem is about the additive relation, and whether
the keyed guard survives `destructiveSub`'s deletions (which absorb exactly the `p <- (z, K)`
witnesses the key needs) is a Stage 3 question in the shape of `KeepInert.lean`. The one-line
flip (`"false"` -> `"true"` at the `splitKey` definition, plus an ADOPTED comment) is written
in the report §C.2. **ADOPTED 2026-09-03: the flip is applied** (`GenRules.splitKey` defaults
to `true`, `-Dermine.splitKey=false` restores the syntactic guard), re-run against the new
default in §3d, and committed.

**Correspondence lemma DONE 2026-09-03** (`tracker/lean/Rowpartition/KeyedSplitScala.lean`,
20 theorems). The "the Scala guard is the Lean guard exactly" sentence above was prose; it
is now checked. `resolved_erase_iff` : `Resolved (G.erase c) v K ↔ Resolved G v K` given
`2 ≤ |vset c|` — the dequeued premise cannot witness its own key — with
`ksplit_guard_erase_iff`, `ksplitApp_erase_iff`, `ksplitReuseApp_erase_iff` in the rules'
own vocabulary. The SYNTACTIC lookup, which the sentence never checked, closes the same way
for a different reason: `named_erase_iff` / `names_erase_iff` (its witnesses are bare,
`conc = ∅`, and the rule runs only when `concr ≠ ∅`). Adequacy: `scalaSplit` mirrors the three
branches in the source's order with both lookups as arguments meeting `RhssSpec` /
`ResolventSpec` on `G.erase c`, and `scalaSplit_step` / `scalaSplitOf_step` prove every
system it returns is a `KDefaultStep` of `G`; `scalaSplit_eq_none_iff` pins the only no-op
to the `concr.isEmpty || abstr.size < 2` early return. Scope: `splitKey`/`splitMints` at
their shipped default `true`, and the additive relation only — the loop layer is still Stage
3 (§4 item 0).

### 3d. Post-flip re-run against the NEW default, no flags (2026-09-03, one class set)

The restore side is `-Dermine.splitKey=false`; the banner reads `cut+label-early+resguard+splitkey`.

| gate | new default | restore side / expectation |
|---|---|---|
| `sbt core/compile`, `core/test` | clean; **903/904**, the known `disjunction sound` starvation | as before |
| `W2`/`H2`/`NE6`, 100 bases each | **SOLVED 100/100** each; `W2` draws **0** fresh ids at all 100 bases | 1-2 draws under the old guard |
| `W`/`gseed` (unsat), 100 bases each | **REJECTED 100/100** each | same |
| `repl-smoke` / `lsp-smoke` | **4/4 (35 checks)** / **98/98** | same |
| `gu05` module time, 2 runs | **1.21 s, 1.25 s** | 6.13 s, 6.03 s with the old guard |
| corpus 66 | **23 LOADED / 43 REJECTED, 0 of 66 differ** vs restore side | `shouldfail/` **40/40** rejected |
| `incomplete/` 34 | **18 / 16, 0 of 34 differ** vs restore side | |
| `.ei`, 188 interfaces / 1,933 bindings | 5 interfaces differ; bindings 1,906 identical, 21 order-only, 4 alpha-equivalent, 2 other, **0 weaker** | the 2 "other" are `np01.inferredRestate` (8 -> 7, the forced existential of §3c, now on the default side) and `Relation.lookbackJoin` (the documented same-configuration stdlib churn) |

Housekeeping: the `.ei` files the sweeps wrote under `core/examples` were deleted and the 129 stdlib
interfaces regenerated under the new default.

### 3e. Stage 3 — does the keyed guard survive the LOOP layer?  NO (2026-09-03, `tracker/satterm/KEYED-LOOP-STAGE3.md`)

**THEOREM (`Rowpartition/KeyedLoop.lean`, 52 theorems): it does not.**  `KLoopStep` is
`KDefaultStep` (§3b's calculus, the shipped additive rule set) plus the loop's own
concretisation `NameLoss.concretizeKeep u C G` — `makeConcrete`/`destructiveSub`, which
DELETES the definitions of `u` with fewer than two abstract parts, REWRITES every mention of
`u` by `absorbC`, and keeps `u <- ((|C|))` and the definitions with `2 ≤ |vset|` (`keepDefs`).
`KLoopRun`'s side condition is one uniform `G ≠ G'`, which on an additive step is exactly
`KRun`'s `G ⊂ G'` (`KLoopRun.ssubset_of_additive`) and on a concretise step is the
constructor's own productivity test.  Soundness: `KLoopStep.concrete_models` (=
`concretizeKeep_sound`), `KLoopStep.extend`, `KLoopStep.sat_mono`, `KLoopRun.sat_mono` — one
direction only, since a deleting step cannot preserve satisfiability backwards.

    not_TerminatesOnSatKeyedLoop : ¬ TerminatesOnSatKeyedLoop
    keyed_additive_vs_loop       : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSatKeyedLoop
    W3_mints_unbounded (n : ℕ)   : ∃ G, KLoopRun (3 * n + 1) W3 G ∧ n + 3 ≤ (allVars G).card

The witness is three constraints on four variables and two labels, satisfiable (`rho3`,
`W3_models`), on which the KEYED guard is CLOSED at the input (`W3_resolved`) — the additive
theorem applies and no mint is possible:

    W3 :  u <- ((|k, c|)),   u <- (z, (|k|)),   u <- (x, y, (|k|))
          model  u = {k, c},  z = x = {c},  y = ∅

One `makeConcrete u` deletes the key witness `u <- (z, (|k|))` (one abstract part) and keeps
`u <- (x, y, (|k|))` (`W3_concretize_eq : concretizeKeep u C W3 = {u <- ((|k,c|)), u <- (x,y,(|k|))}`),
and from there each round is three productive steps: the keyed MINT (`w <- (x, y)`,
`u <- (w, (|k|))`), the CANCELLATION against `u <- ((|k, c|))` giving `w <- ((|c|))`, and
`makeConcrete w` — which absorbs the mention `u <- (w, (|k|))` back into the already-present
`u <- ((|k, c|))`, so the key is open again, while `keepDefs` keeps `w <- (x, y)`.  One fresh
variable per round, for ever.

**The Stage 3 brief's mechanism sketch is wrong in exactly one step.**  It expected
`u <- (w, K)` to survive `makeConcrete w` and close the key for good.  `w` is on the RIGHT of
that constraint, so it is a MENTION and `absorbC` destroys it.  There are precisely two ways a
concretisation kills a key witness, one per clause, and both are proved unconditionally:
`notMem_lone_lhs : mk u {z} K ∉ concretizeKeep u C G` (the DELETION the brief names) and
`notMem_lone_mention : v ≠ u → mk v {u} K ∉ concretizeKeep u C G` (the destructive REWRITE,
which `KeepInert.lean` cannot see because it studies only the kept definitions).  Everything
else survives: `resolved_of_concretizeKeep`.  Also proved, all three of the "cheap if
possible" items: `concretizeKeep_idem`, `conc_unique_of_model` (one concrete value per
variable under a model), `resolved_of_concretizeKeep`.

**Scope, machine-checked.**  `KSplitApp` carries only the keyed premise; the shipped
`splitConcrete` consults the SYNTACTIC lookup `rhss(RHSAbstr(abstr))` FIRST, so `KDefaultStep`
is more permissive than the compiler's rule and this refutation is about exactly the relation
§3b's theorem bounds.  The FIRST re-mint is faithful — at the concretised system both lookups
miss (`W3sat_remint_enabled : SplitApp .. ∧ KSplitApp ..`, the keyed analogue of
`NameLoss.orderB_remint_enabled`) — and the measurement below finds it in the real compiler.
From the second round on it is not: the round's mint leaves the bare `w <- (x, y)` and the
round's concretisation keeps it, so the group is named (`named_after_round`) and the shipped
rule would take its syntactic reuse.  **Whether the SHIPPED rule — both lookups, plus
deletion — terminates on satisfiable input is open** (§4 item 0).

**MEASUREMENT — the mechanism is real, and the loop kills it after one round by a FOURTH
defence.**  The Lean `W3` as a seed for `tracker/repro/satterm/` (its `json:` seed format;
`W3M` adds a mention `R <- (u, q)` so `destructiveSub` has one to rewrite), 100 id bases,
default flags vs `-Dermine.splitKey=false`:

| seed / guard | verdicts | mints per base | kept-def dequeued after the concretisation | of those, MINTED | fresh name cancelled to `((|c|))` | then `common`-unified with `z` |
|---|---|---|---|---|---|---|
| `W3`, keyed (default) | SOLVED 100/100 | 0 at 45, **1 at 55** | **55/100** | 55/55 | 55/55 | 55/55 |
| `W3`, `splitKey=false` | SOLVED 100/100 | 1 at 100 | 57/100 | 57/57 | 55/57 | 55/57 |
| `W3M`, keyed (default) | SOLVED 100/100 | 1 at 45, 2 at 55 | 55/100 | 55/55 | 55/55 | 55/55 |
| `W3M`, `splitKey=false` | SOLVED 100/100 | 2 at 100 | 59/100 | 59/59 | 57/59 | 57/59 |

At 55 of 100 bases the queue order really does put `makeConcrete u` before the dequeue of the
kept `u <- (x, y, (|k|))`, the key witness is deleted, and `splitConcrete` mints — the mint the
keyed guard refuses at the input.  At the other 45 the split premise is dequeued first and the
KEYED REUSE fires (`SplitKeyed: z <- (x, y)`), which is why the keyed guard mints 0 there while
the syntactic guard mints at 100/100.  The Lean round's second step is performed too
(`Cancellation: w <- ((|c|))`, 55 of 55).  What the Lean has no rule for is the third: the loop
notices `w <- ((|c|))` has the same right-hand side as the already-processed `z <- ((|c|))` and
takes its `common` branch, UNIFYING `w := z` — restoring the deleted witness instead of losing
it, at 55 of 55.  So the loop's defences are four, not three: name travel, eager `unify` of
singleton links, eager `makeEmpty`, and **`common`, the dedup-unification of a re-minted name
with the one the deletion removed**.  None is stated by any relation in the development.

MEASUREMENT, the corpus (`tracker/tools/keptdef-sweep.sh` + `keptdef-mints.py`, one serialized
`-Dermine.rowTrace` per example module; a `SplitKeyed` reuse count was added to the instrument
for this stage, so its three branch counts now add up).  Kept-definition mints ARE the
loop-layer re-mints: a kept `u <- (x, y, (|K|))` dequeued after `u` was made concrete is
exactly `W3sat`'s premise.  110 modules, 55,338 solve segments, both sides from one class set:

| over `core/examples` | keyed (DEFAULT) | `-Dermine.splitKey=false` | 2026-09-02 baseline |
|---|---|---|---|
| verdicts | 50 LOADED / 60 REJECTED | same, 0 of 110 differ | — |
| `makeConcrete` steps | 3617 | 3605 | — |
| kept-definition dequeues | **748** (336 strict, 412 derived) | **715** (329, 386) | 715 (329, 386) |
| ... with a nonempty concrete part | **308** (47 strict) | **284** (42 strict) | 284 (42) |
| ... **`splitConcrete` MINTED** | **157** (23 strict) | **156** (24 strict) | 156 (24) |
| ... syntactically REUSED | 147 | 128 | 128 |
| ... KEYED-reused | **4** | 0 | (not counted then) |
| modules with such a mint | **27** (12 strict) | 27 (14 strict) | 27 (14) |

The restore side reproduces the baseline exactly in every shared column — the control.  **The
keyed guard removes none of the loop-layer re-mints: 157 against 156, in the same 27 modules.**
That is what §3e's theorem predicts, since the guard's witness is precisely what `makeConcrete`
deletes.  Per module the two are incomparable as `split_mint_not_keyed` says (ten modules
differ; `np01` 26 -> 33 and `np05` 5 -> 9 up, `TelescopeTime` 11 -> 8, `np02` 6 -> 3,
`gu05` 8 -> 6 down); 19 of 110 modules differ in some column, no verdict does.  The sweeps ran
with `-Dermine.useInterface=false` and `core/examples` was checked clean of `.ei` afterwards.

## 4. What stays open, ranked

0. **Stage 2 — DONE and ADOPTED 2026-09-03** (§3c, §3d). Items 1–3 below are now moot for the
   shipped compiler as far as the ADDITIVE relation goes (the theorem covers every run order);
   they stay as questions about the syntactic guard, `-Dermine.splitKey=false`.
   **Stage 3 — DONE 2026-09-03 (§3e), outcome (W): the keyed guard does NOT survive the loop
   layer.** `makeConcrete`/`destructiveSub` deletes a key witness `v <- (z, K)` two different
   ways — as a definition of `v = u` (`notMem_lone_lhs`) and as a MENTION of `z = u`
   (`notMem_lone_mention`, the mode the brief's sketch missed) — and the second drives a
   three-step round that mints for ever from a satisfiable three-constraint input
   (`not_TerminatesOnSatKeyedLoop`, `W3_mints_unbounded`, `Rowpartition/KeyedLoop.lean`;
   write-up `tracker/satterm/KEYED-LOOP-STAGE3.md`). MEASURED: the first re-mint happens in
   the shipped compiler at 55 of 100 id bases, and the loop stops there because its `common`
   branch unifies the re-minted name with the deleted witness's variable.
   **What Stage 3 leaves open, and is now the ranked-first question:** the SHIPPED rule
   consults the syntactic lookup FIRST, and `KSplitApp` does not; the witness's first re-mint
   passes both lookups (`W3sat_remint_enabled`) but its later ones do not
   (`named_after_round`). Does the two-lookup rule plus deletion terminate on satisfiable
   input? A divergence would need a fresh UNNAMED group every round.
1. **Conjecture S** — every substitution-closed run (all non-generative consequences taken
   before each mint) is bounded from every satisfiable input. The explorer's breadth-first
   strategy reaches fixpoints on every seed; `subst_names_travel` is the one-step mechanism;
   the run-level invariant ("a mint premise's group is unnamed only if it contains a variable
   minted since the last substitution closure") is unproved.
2. **A loop-shaped relation** — eager rename and eager `makeEmpty` as ORDERED steps, and the
   theorem that `W2`-type engines cannot run under it. `Saturate.SatStep` cannot express it.
3. **Undetected empties** — `NE6` shows resolution mints an empty resolvent from all-nonempty
   inputs that nothing exposes as `z <- ()` until later derivation; mint-greedy chains on it
   reach 80 mints in the additive explorer, the loop stops at 8. A chain that survives name
   travel with an undetected empty was not found and its impossibility is not proved.
4. **The `ResStar` cliff** — a performance problem, not a termination one: the per-key lattice
   `2^m − m − 1` is attained and three quarters of the time is re-derivation. If real code
   projects one relation onto ~9 single labels, the practical cliff is there. A cheaper
   duplicate check (the `seen` derivations) is the obvious lever; not measured here.

## 5. Files

| file | what |
|---|---|
| `tracker/lean/Rowpartition/DefaultTerm.lean` | the question and the structural chain (§2) |
| `tracker/lean/Rowpartition/DefaultSatDiverge.lean` | `not_TerminatesOnSat`, `W2Inv`, `subst_names_travel` |
| `tracker/tools/rowclosure.py` | additive-closure explorer, seed format, strategies, search |
| `tracker/satterm/math/ANALYSIS.md` (+ seeds, scripts) | the paper analysis: obstruction, `W2`, `H2`, `NE6`, the loop layer, ranked next steps |
| `tracker/satterm/measure/REPORT.md` (+ tables) | compiler growth on the generator families and the `.slow` corpus |
| `tracker/repro/satterm/` | `W2`/`H2`/`NE6` replayed through the real solver, with traces |
| `tracker/lean/Rowpartition/KeyedSplit.lean` | the repair: `KSplitStep`, `terminatesOnSatKeyed`, `keyed_vs_syntactic`, `split_mint_not_keyed` |
| `tracker/satterm/KEYED-SPLIT.md` | Stage 1 write-up of the keyed guard |
| `tracker/lean/Rowpartition/KeyedSplitScala.lean` | the correspondence, as a theorem: `resolved_erase_iff`, `named_erase_iff`, `scalaSplit_step`, `scalaSplitOf_step` |
| `tracker/satterm/KEYED-SPLIT-STAGE2.md` | Stage 2: the flag, every gate off vs on, the gate table, the unapplied flip, the recommendation |
| `tracker/lean/Rowpartition/KeyedLoop.lean` | Stage 3: `KLoopStep` (the additive calculus + `concretizeKeep`), the two ways a concretisation kills a key witness (`notMem_lone_lhs`, `notMem_lone_mention`) and what survives (`resolved_of_concretizeKeep`), `concretizeKeep_idem`, `conc_unique_of_model`, and the refutation `not_TerminatesOnSatKeyedLoop` / `W3_mints_unbounded` with its scope theorems `W3sat_remint_enabled`, `named_after_round` |
| `tracker/satterm/KEYED-LOOP-STAGE3.md` | Stage 3 write-up: the theorem verbatim, the corrected mechanism, the 100-base replay of `W3`/`W3M` and the corpus re-run of the kept-definition instrument |
| `core/.../Constraints.scala` | `GenRules.splitKey` (default off), `SplitKeyed`, `splitConcrete`'s `resolvent` parameter |
| `tracker/tools/splitkey-counts.py`, `splitkey-sweep.sh`, `ei-classify.py` | Stage 2 instruments: split-branch counts per trace, the 110-module traced sweep, `.ei` signature classification |
