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
deletions — `not_TerminatesOnSatKeyedLoop`. §3f is Stage 4: the CONCRETE-ROW reuse restores
the bound for the split fragment but not with `resolution` as shipped. §3g is Stage 5: both
branches are now IMPLEMENTED behind `-Dermine.splitRow` / `-Dermine.resRow` and measured,
**both ADOPTED the same evening, DEFAULT ON** (§3h is the post-flip re-run); coverage is partial — `makeEmpty` deletions are outside the relation, which is Stage 6.)*

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

### 3f. Stage 4 — does the CONCRETE-ROW reuse bound minting under the deletions?  PARTLY (2026-09-03, `tracker/satterm/KEYED-ROW-STAGE4.md`)

**THEOREM (`Rowpartition/KeyedRow.lean`, 94 theorems), outcome (T2): the new clause bounds
the SPLIT and cannot bound the calculus, because guarded RESOLUTION has the same disease.**

The clause.  For a split premise `v <- (S, K)`, `splitConcrete`'s reverse lookups become
three: the shipped syntactic one (`Named G S` -> `v <- (d, K)`), the shipped keyed one
(`mk v {z} K ∈ G` -> `z <- (S)`), and the NEW **concrete-row** one — `v` has a concrete
definition `v <- ((|C|))` and some `z` has `z <- ((|C \ K|))`, so `z` already denotes `v \ K`
and the branch emits `z <- (S)`.  Mint only if all three miss.  The guard is
`Carried G v K := Resolved G v K ∨ ConcCarried G v K`.  Soundness is `conc_lone_sat` (a
concrete definition of `v` plus a concrete definition of the complement row IS the lone
witness `v <- (z, K)`) followed by `ksplit_reuse_sat` unchanged: `concRow_reuse_sat`,
`K2RowApp.models_iff` — the model set does not move.  **Every non-syntactic branch carries
`¬ Named G (vset c)`, so the §3e faithfulness gap (§2.4 of the Stage 3 write-up) is closed for
this relation**: `K2MintApp.toSplitApp` proves that every mint of `K2SplitStep` passes BOTH of
the shipped lookups, i.e. is a mint the shipped rule would take.

The deletion, made faithful.  `concretizeSrs u C G = concretizeKeep u C G ∪ srsOf u C G`,
where `srsOf` carries the fact `makeConcrete`'s own cancellation derives from each ONE-abstract
definition `u <- (z, K)` before `destructiveSub` drops it: `z <- ((|C \ K|))` (`Constraints.scala`,
`makeConcrete`'s `val can`, `destructiveSub`'s `val srs`).  Sound (`concretizeSrs_sound`),
strictly larger than Stage 3's step (`concretizeKeep_subset_srs`), adds no variable and no
label.  The side condition `K ⊆ C` that cancellation's Scala guard imposes is not hidden: it is
`key_subset_of_model`, automatic under a model, and soundness is stated for modelled systems only.

Why it works: **once carried, always carried**.  Stage 3's two failure modes are exactly the
two ways a lone witness BECOMES a concrete-row carrier — the deleted definition leaves
`z <- ((|C \ K|))` next to the new `u <- ((|C|))` (`carried_of_deleted_def`, no model needed),
and the absorbed mention `v <- (u, K)` becomes `v <- ((|K ∪ C|))` next to `u <- ((|C|))`, whose
complement is `C` because a model forces `K ∩ C = ∅` (`carried_of_absorbed_mention`).  Hence
`carried_concretizeSrs`, and hence `ResGuardTerm`'s budget survives the deleting step:
`uncarried` / `hmeas` are `unfired` / `gmeas` with `Carried` for `Resolved`.

    mintsBoundedOnSat_splitFragment : ∀ G₀ rho, SModels rho G₀ →
        ∃ N, ∀ n G, K2SplitLoopRun n G₀ G → (allVars G).card ≤ N
    mintsBoundedOnSatKeyed2Star     : MintsBoundedOnSatKeyed2Star
    not_MintsBoundedOnSatKeyed2     : ¬ MintsBoundedOnSatKeyed2
    keyed2_star_vs_shipped_res      : MintsBoundedOnSatKeyed2Star ∧ ¬ MintsBoundedOnSatKeyed2

with the explicit bound `N = |allVars G₀| + hmeas (labelsOf G₀) rho G₀` in both positive
statements.  Vocabulary, not run length, is the right measure — the any-order relation permits
add/delete cycles — and `K2LoopStep.allVars_cases` licenses the reading: only a MINT enlarges
the vocabulary.

**(W), and it is not about the split.**  `MintsBoundedOnSatKeyed2` — the same statement over
the relation that keeps guarded `resolution` AS SHIPPED — is FALSE.  The witness
`W4 = {v <- ((|a,b,c|)), v <- (x, (|a|)), v <- (y, (|b|))}` is satisfiable
(`v = {a,b,c}, x = {b,c}, y = {a,c}`) and contains **no split premise at all**: every
right-hand side has at most one variable, so `abstr.size >= 2` never holds.  Guarded
resolution mints the resolvent `w`, cancellation gives `w <- ((|c|))`, and `makeConcrete w`
ABSORBS the resolvent `v <- (w, (|a,b|))` back into the already-present `v <- ((|a,b,c|))` —
Stage 3's failure mode 2 again — while the two premises are untouched.  One fresh variable per
round, for ever (`W4_mints_unbounded`).  `srsOf` contributes nothing on this witness
(`srsOf_eq_empty`, `concretizeSrs_eq_concretizeKeep`), so the same three steps are Stage 3's
too and **`W4` refutes `TerminatesOnSatKeyedLoop` as a theorem, with no split step**
(`W4_kloop_mints_unbounded`, `W4_not_TerminatesOnSatKeyedLoop`): no change to `splitConcrete`
alone can make the loop-extended calculus terminate.

**The missing piece, named exactly and closed in Lean.**  Key `resolution`'s mint on `Carried`
as well, with the matching concrete-row reuse branch (`K2ResStep.row`, entailed by
`K2ResStep.row_models_iff`), and the whole loop-extended calculus is bounded
(`mintsBoundedOnSatKeyed2Star`).  Stage 3's own witness dies under the new split rule: at the
system the FAITHFUL `makeConcrete u` reaches, `W3`'s re-mint is refused (`W3_not_mintable`) and
the `row` branch emits `z <- (x, y)` (`W3_row_reuse`) — the constraint the shipped loop obtains
only afterwards, by `common`-unifying the re-minted name with `z` (§3e, 55 of 55 bases).  The
rule does in EVERY order what `common` does in some.

Scope and cost.  No Scala change: the report's §9 writes the exact `splitConcrete` /
`learnPartitions` edit (a `concRows : Map[Fields, TypeVar]` of the bare concrete partitions,
a third lookup before the mint, a `SplitRow` reuse tag) and the matching `resolution` edit,
UNIMPLEMENTED and unmeasured — that is Stage 5.  Nothing here models `common`/`unify`, and
unsatisfiable input is untouched (`hmeas` needs a model).

**`W4` in the real loop (session measurement, 2026-09-03).** `W4` as a `json:` seed for `tracker/repro/satterm/` (`v = {l1,l2,l3}`,
`x = {l2,l3}`, `y = {l1,l3}`), 40 id bases, default flags: **SOLVED 40/40**, fresh ids drawn
0 at 37 bases, 1 at 2, 3 at 1. Traced at base 5 (3 draws, 1 of them a mint): the two
one-part premises are dequeued before the concrete definition, so `resolution` mints the
resolvent once (`v <- (w, l1 l2)`, `x <- (w, l2)`, `y <- (w, l1)`); then `v <- ((|l1,l2,l3|))`
is dequeued, `makeConcrete v` fires, and the cancellations make `w`, `x`, `y` concrete
(`w = {l3}`) — every variable is concrete and the solve ends. At the 37 bases where the
concrete definition is dequeued first, the one-part premises are absorbed and nothing mints.
So in the loop this engine never reaches its second round: the defence is `makeConcrete`'s
own order (concrete facts absorb the premises the next round would need), not `common` —
the agent's argument, confirmed. As with `W3`, that is a property of `incorporateAll`'s
single pass that no relation states.

### 3g. Stage 5 — BOTH concrete-row branches, IMPLEMENTED behind flags, MEASURED and ADOPTED (2026-09-03, `tracker/satterm/KEYED-ROW-STAGE5.md`)

*(ADOPTED 2026-09-03, later the same day: both defaults flipped to ON with the ADOPTED comments of the report's §C.2 plus a COVERAGE paragraph — the bound is against concretisation deletions only; `makeEmpty`/`unify` deletions are outside the relation and the Scala lookup cannot see an emptied carrier (74 of the corpus's 157 kept-definition mints have an empty complement and stay mints). `-Dermine.splitRow=false -Dermine.resRow=false` restores the previous behaviour. Post-flip re-run in §3h. The text below is as written before the decision.)*

The §3f Scala change is written. `-Dermine.splitRow` (`GenRules.splitRow`, `SplitRow` tag, a
FOURTH branch of `splitConcrete` between the keyed reuse and the mint) and `-Dermine.resRow`
(`GenRules.resRow`, `ResolutionRow` tag, a THIRD branch of `resolution` taken when
`findResolvent` misses) are in `Constraints.scala`, **both DEFAULT OFF**, sharing one lazy
lookup built in `learnPartitions` alongside `resolvents`: a single fold over `proc ++ incm`
collecting every BARE CONCRETE partition into `con -> u` and, on the way, `v`'s own row, with
`k ⊆ C` asked explicitly. With both flags off the lambda is a shared constant and the
`lazy val` is never forced.

**The faithfulness note the Lean cannot supply, traced with `-Dermine.rowTrace` BEFORE the
lookup was written.** A NONEMPTY concrete row of `v` is a bare partition in the `proc` queue
and NOWHERE else: `makeConcrete` never calls `instantiateType` and returns the dequeued
partition to `proc`. The EMPTY row is the exception — `makeEmpty` writes `v := ConcreteRho(∅)`
into the `SubstEnv` and DELETES every partition mentioning `v` — and `unify` likewise. So the
Scala lookup is a LOWER bound on the Lean's `mk u ∅ R ∈ G`: it can miss (an emptied or
unified-away carrier), never hit spuriously; and asking `k ⊆ C`, which `K2RowApp` does not,
can only REFUSE a reuse, so no refutation is lost.

**Correspondence proved** (`tracker/lean/Rowpartition/KeyedRowScala.lean`, 33 theorems):
`MyRowSpec` / `ConcRowSpec` state what the fold really meets (ONE `Option` row per variable,
the explicit `k ⊆ C`), `myRowLookup_spec` / `concRowLookup_spec` inhabit them, and
**`scalaRowSplit_step : K2SplitStep`** and **`scalaRowRes_step : K2ResStep`** prove every
firing of either branch is a step of Stage 4's calculus — on a MODELLED system, the model
being used in exactly one place (`concRow_none_uncarried`, via `conc_unique_of_model` and
`conc_key_subset_of_model`) to close the two gaps at the MINT guard. New erase lemmas:
`bare_erase_iff` (the dequeued premise is invisible to this lookup for a third reason — its
witnesses are BARE) and `resolved_erase_iff_row` (resolution's premise has one variable, so
Stage 2's erase lemma does not apply and the argument is about the ROW).

Every gate below is from ONE class set in FOUR configurations (`D` default, `S` splitRow,
`R` resRow, `B` both), each with a positive control:

* seeds: `W2`/`H2`/`NE6`/`W3`/`W4` SOLVED 100/100 in all four; **`W3` mints at 55 of 100 id
  bases under `D` and at NONE under `S`** (`SplitRow: ^free4 <- (^free5 ^free6,)` in the base-3
  trace — `KeyedRow.lean` §10 executed, and the constraint the shipped loop reaches only
  afterwards by `common`-unifying the re-mint with `z`); `NE6` draws one id fewer at 17 of 100
  bases under `S`, same bindings. `W`/`gseed` REJECTED 200/200, byte-identical bar the banner;
  the KeepMint instance still mints on both sides (no carrier exists there).
* **`W4` is NOT changed by `resRow`** — the draw distribution is identical in all four
  configurations. The branch needs a carrier for the resolvent row `F \ (C ∪ D)`, which `W4`
  acquires only in round 2 of the Lean divergence, and the real loop never reaches round 2
  (§3f's own measurement: `makeConcrete`'s order absorbs the premises). The positive control
  is therefore `W4c`, `W4` plus that carrier: at base 37, `D` draws 3 ids and mints the
  resolvent, `R` draws 1 and emits `ResolutionRow` twice, same solved system with one bound
  variable fewer.
* stdlib boot 129 modules, traces **byte-identical** `D` vs `B` (neither `splitConcrete` nor
  `resolution` fires there at all); `core/test` **903/904** in `D` and in `B`, the known
  `disjunction sound` generator starvation; `repl-smoke` 4/4, `lsp-smoke` 98/98.
* corpus verdicts 23/43 and 18/16 in `D`, `S` and `B`; **0 of 66 and 0 of 34 files differ**,
  verdicts and messages; `shouldfail/` **40/40** rejected in every configuration — including
  the two modules where the resolution branch actually fires.
* published types: 188 interfaces / 1,933 bindings, **0 weaker anywhere**. A same-configuration
  control already moves 1 interface; `D` vs `B` moves 3, all stdlib churn and NONE attributable
  (the stdlib boot cannot reach either rule); `D` vs `S` moves 5, of which two bindings are
  attributable — `TargetList.restrictTo` alpha-equivalent and `np01.inferredRestate` **7
  existentials -> 6**, hand-checked equivalent (the removed name is FORCED by the remaining
  constraints), i.e. the OPPOSITE direction from §3c's 7 -> 8.
* timing (one JVM at a time, machine idle, three passes): **nothing moved** — ResStar 5–9,
  RowStress 10/14, CoStar8 and `gu05` are all inside their own run-to-run spread. The
  `ResStar` family cannot reach either branch: no left-hand side there ever becomes concrete.
* population, the honest part: **`SplitRow` fires 4 times in 3 of 110 example modules and
  `ResolutionRow` 19 times in 5**, against `SplitKeyed`'s 77 in 18. Corpus split mints
  637 -> 626, kept-definition mints 157 -> 154 with all **133 consumers still finding a name**
  (the three removed were mints nothing used), resolution conclusions 1,748 -> 1,696 (`R`)
  and 1,644 (`B`). Both branches are RARE because the carrier `w <- ((|C \ K|))` normally
  exists only where a cancellation has just made it — which is the keyed witness's own
  situation, already handled by `splitKey`.

Recommendation in the report: **ADOPT WITH CAVEATS for both, and as ONE decision** — `splitRow`
alone bounds only the split fragment (`mintsBoundedOnSat_splitFragment`) and `resRow` alone
bounds nothing; together they are `mintsBoundedOnSatKeyed2Star`, which
`keyed2_star_vs_shipped_res` says is false without `resRow`. The caveats: the population is
small, so the corpus zeros are weaker evidence than §3c's; no speed win; ids shift and one
`incomplete/` published type changes shape (equivalently); nothing here touches ill-typed
input (`not_CRule` still lives) and the loop's single pass and `common` remain unmodelled.
**Neither default was flipped and nothing was committed**; the two one-line diffs with their
ADOPTED comments are in the report §C.2.

### 3h. Post-flip re-run against the NEW defaults, no flags (2026-09-03 evening, one class set incl. the loader fix)

The restore side is `-Dermine.splitRow=false -Dermine.resRow=false`; the banner reads
`cut+label-early+resguard+splitkey+splitrow+resrow`. The class set also carries the loader's
batch-load fix (`TICKET-editor-and-solver-followups.md` §4), so the corpus gate ran in
`--batch` mode on BOTH sides for the first time.

| gate | new defaults | restore side / expectation |
|---|---|---|
| `sbt core/compile`, `core/test` | clean; **910/911** (904 + 7 new loader properties), the known `disjunction sound` starvation | as before |
| `W2`/`H2`/`NE6`/`W3`/`W4`, 100 bases each | **SOLVED 100/100** each; `W3` draws **0** fresh ids at all 100 bases | `W3` restore side: 55 of 100 mint |
| `W`/`gseed` (unsat), 100 bases each | **REJECTED 100/100** each | same |
| `repl-smoke` / `lsp-smoke` | **4/4 (35 checks)** / **98/98** | same |
| `gu05` module time, 2 runs, idle machine | **1.09 s, 1.04 s** | 1.02 s, 1.04 s (no speed change, as Stage 5 predicted) |
| corpus 66, `--batch` both sides | **23 LOADED / 43 REJECTED**, `shouldfail/` **40/40**; 4 of 66 differ in MESSAGE only | restore 23/43; the 4 are `der01/02/06/07`, a different clause of the same label-check refutation at the same field — re-run PER FILE both sides: identical, so it is batch-session id drift (the documented `--batch` caveat), not the flags |
| `incomplete/` 34, `--batch` both sides | **18 / 16, 0 of 34 differ** | |
| `.ei`, 188 interfaces / 1,933 bindings, per file | **2 of 188 differ**, 4 bindings order-only (`Layout/Chart`, `Layout/Report` — the documented stdlib churn), 1,929 identical, **0 weaker** | |

Housekeeping: `.ei` under `core/examples` deleted; the 129 stdlib interfaces regenerated under
the new defaults.

### 3i. Stage 6 — `makeEmpty` as a deleting step: the bound survives under ONE order hypothesis, or unconditionally with a one-line repair (2026-09-03 evening, `tracker/satterm/KEYED-EMPTY-STAGE6.md`)

THEOREM (`Rowpartition/KeyedEmpty.lean`, 65 theorems; Audit 2329/0, build 819). `makeEmptyD` is
the compiler's `makeEmpty` made faithful (partitions involving `v` leave both queues; mentions
are re-emitted with `v` erased; a bare definition's parts are forced empty; a definition with a
concrete part is a contradiction; `v <- ()` goes to the substitution environment and NOT back into
the system). Stage 4's invariant FAILS at it in exactly one way: the deleted `v <- ()` was the
only carrier of the EMPTY row (`carried_not_invariant`), and Stage 4's potential strictly
INCREASES across one step of a satisfiable three-constraint system (`hmeas_increases`, 52 -> 76)
— the wrong measure, not a missing lemma. Everything else about the step is harmless: an erased
witness becomes a bare concrete definition and IS a carrier for other keys.

* (T2) `mintsBoundedOnSat_emptyPersisting`: Stage 4's bound `|allVars G₀| + hmeas L rho G₀`
  holds verbatim for `K3LoopStep = K2StarLoopStep ∪ makeEmptyD`, in every order, under the
  ORDER hypothesis `K3LoopRunEP` that every `makeEmpty` step leaves an empty-row carrier behind
  (`EmptyKnown`; `emptyKnown_makeEmptyD` gives three necessary and three sufficient syntactic
  conditions, decidable at the step). This is "eager empty propagation", the first of the loop's
  four unformalised defences, stated as a hypothesis on runs — but NOT measured against the
  compiler.
* (T1) for a one-line repair, `mintsBoundedOnSatKeyed3E`: retain `v <- ()` (`makeEmptyE`), i.e.
  let the reverse lookup consult the substitution environment where the compiler already keeps
  the fact, and the bound holds UNCONDITIONALLY. `G7_mints` formalises the corpus's 74-of-157
  empty-complement mints; `G7_blocked` shows one `e <- ()` turns each into a reuse.
* NOT decided: `MintsBoundedOnSatKeyed3` itself (no hypothesis). §10 of the report records where
  both witness constructions die; the brief's T1 sketch was wrong in one step (the premise keeps
  its `2 ≤ |S|` after erasure; what blocks the mint is the propagation acting as the `∅` carrier).

The Scala repair (report §9, UNIMPLEMENTED): seed `concRows` with the environment's empty
instantiations, or have `makeEmpty` return `v <- ()` to `incm`. Same gate set as Stage 5. The
other deletion, `unify`, remains unmodelled.

### 3j. Stage 7 — the repair IMPLEMENTED behind `-Dermine.emptyRow`, MEASURED (2026-09-04, `tracker/satterm/KEYED-EMPTY-STAGE7.md`)

The §3i repair is written.  `-Dermine.emptyRow` (`GenRules.emptyRow`, **DEFAULT OFF**, tags
`SplitEmpty` / `ResolutionEmpty`) adds a FIFTH branch to `splitConcrete` and a FOURTH to
`resolution`, taken when the Stage 5 lookups miss because the complement row (resp. the
resolvent row) is EMPTY and some variable is known to denote `∅`.  The lookup is
`findConcRow` with the complement pinned to `∅` and a SECOND source for the carrier: the
substitution environment, `hm.types.collectFirst { case (z, ConcreteRho(_, fs)) if fs.isEmpty => z }`,
which is where `makeEmpty` leaves the fact — `makeEmptyE` implemented literally, LOOKUP-ONLY
(re-enqueueing `v <- ()` would call `makeEmpty` again and cycle).

**The design decision was made on data.**  Of the two options, seeding from the environment
(a) or threading an `emptied` set alongside the queues (b): replaying the Stage 5 traces
(`stage7/pre-empty.py`) shows that at **74 of 74** empty-complement mints a `makeEmpty` had
already run earlier in the module — so (a) can find a carrier at all of them — while only
**14 of 74** have one in the same solve segment, which is the most (b) could see; and at
**0 of 74** is a bare `x <- ()` still in the queues, which is why Stage 5's lookup misses all
74.  (a) also needs no change to `incorporateAll`'s recursion.

**What the branch emits is NOT the Lean reuse's conclusion, and that is a theorem.**  Traced
on the `G7` instance first: a partition about the emptied carrier would re-enter the queues
and reach `makeEmpty` a second time (`panic: reinstantiated type`), so the branch emits the
PROPAGATION the reuse forces — `x <- ()` for every `x` of the group (resolution: the reuse's
two conclusions with the carrier's row `∅` substituted in, `x <- ((|D \ C|))`,
`y <- ((|C \ D|))`).  `Rowpartition/KeyedEmptyScala.lean` (NEW, 39 theorems):
`emptyReuse_compose` / `resEmptyReuse_compose` prove `makeEmptyE z` applied to the Lean
reuse's conclusion is exactly what the Scala emits, so one Scala step is TWO steps of
`K3ELoopStep` (`splitEmpty_two_steps`, `resEmpty_two_steps`); `scalaEmptySplit_run` /
`scalaEmptyRes_run` are the adequacy for the five- and four-branch rules, and
`scalaEmptySplit_bounded` / `scalaEmptyRes_bounded` state the resulting bound
`|allVars H| + hmeas (labelsOf H) rho H`.  Soundness needs NO carrier at all
(`splitEmpty_models_iff` through `group_forced_empty`, `resEmpty_models_iff` through
`res_empty_forced`); the carrier is asked for because it is what makes the step a step of the
relation that has the bound.  Build 820 jobs, Audit **2378 theorems, 0 non-standard axioms**.


Every gate below is from ONE class set in two configurations (`D` today's default,
`E` `-Dermine.emptyRow=true`), each with a positive control:

* seeds: `W2`/`H2`/`NE6`/`W3`/`W4` SOLVED 100/100 with IDENTICAL draw distributions on both
  sides; the NEW tracked seed **`G7`** (`KeyedEmpty.G7` plus the `e <- ()` of `G7_blocked`,
  ordered so the `empty` step runs FIRST and the carrier is in the environment, not the
  queues) **draws one fresh id at 100 of 100 bases under `D` and NONE under `E`**, same
  solved system, one bound variable fewer; the base-0 traces show `D` minting and then
  reaching the same answer through cancellation plus `makeEmpty` in five more steps, and `E`
  emitting `SplitEmpty: ^free2 <- (,)`, `^free3 <- (,)` directly.  `W`/`gseed` REJECTED
  200/200, byte-identical bar the banner.  The `ResolutionEmpty` control had to be
  synthesised (`stage7/W4e.json`, scratch), as Stage 5's `W4c` was.
* the BARE `G7` (`KeyedEmpty.G7` verbatim, no carrier anywhere) is UNCHANGED by the flag —
  `G7_not_emptyKnown`: where no `makeEmpty` has run there is no fact to retain.
* stdlib boot 129 modules, traces **byte-identical**; `core/test` **910/911** on both sides
  (the known `disjunction sound` starvation); `repl-smoke` 4/4, `lsp-smoke` 98/98.
* corpus verdicts 23/43 and 18/16 on both sides, `shouldfail/` **40/40**; 1 of 66 and 3 of 34
  files differ in MESSAGE only, and all four are IDENTICAL when re-run PER FILE twice per
  side — `--batch` session drift, not the flag (and a later batch pair on the recompiled
  tree shows 0 of 66).
* published types, PER FILE with a same-configuration control: 188 interfaces / 1,933
  bindings, **0 weaker**; the control moves 3 interfaces and one binding
  (`Relation.lookbackJoin`, the documented churn), `D` vs `E` moves 8 and **two attributable
  bindings**, `incomplete/np01.inferredRestate` (7 existentials -> 6, the removed name FORCED
  by the rest) and `incomplete/RunCalibration.scaledRuns` (one order-only duplicate fewer), both
  hand-checked EQUIVALENT.
* population, PER FILE over 110 modules (the batch mode does not survive the `incomplete`
  group under `rowTrace`): **`SplitEmpty` fires 65 times in 16 modules and `ResolutionEmpty`
  183 times in 19**, kept-definition mints **154 -> 82** (of the 154, **73 have an empty
  complement**, and at 73 of 73 a `makeEmpty` had already run), corpus split mints 626 -> 561,
  resolution conclusions **1,644 -> 792**.  The `D` column reproduces Stage 5's `B` column
  exactly.  This is by far the largest population of any flag in the series.
* timing, one JVM at a time on an idle machine: ResStar 5-9, RowStress 10/14, CoStar8 and two
  corpus modules are all inside their own spread (`np01`, where the branch fires most, +7 %)
  — but **`incomplete/gu05` is 1.9x SLOWER** (1.03 s -> 1.96 s, three runs each).  The cause
  was NOT isolated: JFR moves the attribution into the row-constraint QUEUE (`Q.part`, the
  finger-tree monoid, `RHS.hashCode`, `PQueue.foldLeft`), NOT into the environment scan, and
  `gu05` derives LESS under `E` (1,496 -> 1,174 `learn new`) while taking longer.

Recommendation in the report: **DO NOT ADOPT YET — keep the flag, settle `gu05` first.**  The
theorem is the one that was missing and every correctness gate is green, but a 1.9x regression
on the corpus's most expensive module, on the very module `resGuard` (11x) and `splitKey` (5x)
were adopted on, is not a state to make a default in.  **The default was not flipped and
nothing was committed**; the one-line diff with its ADOPTED comment is in the report §C.2.

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
   **Stage 4 — DONE 2026-09-03 (§3f), outcome (T2).** The two-lookup question Stage 3 left
   ranked-first is ANSWERED for the split, in the affirmative and with the `¬ Named` premise
   in the relation: adding a CONCRETE-ROW reuse clause (`v <- ((|C|))` and `z <- ((|C \ K|))`
   name `v \ K`, so emit `z <- (S)`) and making the deletion faithful to the Scala's `srs`
   re-expression makes the guard `Carried` an INVARIANT of the deleting step
   (`carried_concretizeSrs`), so `ResGuardTerm`'s budget survives it and the split mints
   boundedly on satisfiable input in every order (`mintsBoundedOnSat_splitFragment`, bound
   `|allVars G₀| + hmeas L rho G₀`; `Rowpartition/KeyedRow.lean`, write-up
   `tracker/satterm/KEYED-ROW-STAGE4.md`). Stage 3's `W3` dies under it (`W3_row_reuse`,
   `W3_not_mintable`). **But the calculus as a whole is still unbounded**
   (`not_MintsBoundedOnSatKeyed2`): the split-free satisfiable witness
   `W4 = {v <- ((|a,b,c|)), v <- (x, (|a|)), v <- (y, (|b|))}` mints for ever through guarded
   RESOLUTION, whose guard is still keyed on `Resolved` and whose resolvent is absorbed by the
   very concretisation that makes it concrete — Stage 3's failure mode 2, with no split step
   anywhere. `W4` therefore also refutes `TerminatesOnSatKeyedLoop` on its own.
   **The ranked-first question is now**: rekey `resolution` the same way. In Lean that already
   closes it (`mintsBoundedOnSatKeyed2Star`, `keyed2_star_vs_shipped_res`); in Scala neither
   the split's third lookup nor resolution's exists, and neither is measured — Stage 5.
   **Stage 6 — DONE 2026-09-03 evening (§3i), outcome (T2): `makeEmpty` breaks the Stage 4
   invariant only at the EMPTY row's carrier; the bound survives under the eager-propagation
   order hypothesis, or unconditionally with the one-line repair (retain `v <- ()`).**
   **Stage 7 — DONE 2026-09-04 (§3j): the repair is IMPLEMENTED behind `-Dermine.emptyRow`
   (DEFAULT OFF) and gated.** The lookup reads the empty facts from the `SubstEnv`, where
   `makeEmpty` leaves them; the branch emits the PROPAGATION rather than the Lean reuse's
   conclusion, and `Rowpartition/KeyedEmptyScala.lean` proves that is the reuse composed with
   its forced `makeEmptyE` step, so the rule as written is a step-pair of the calculus with the
   bound. Every correctness gate is green and the population is the largest in the series
   (kept-definition mints 154 -> 82, resolution conclusions 1,644 -> 792), but `incomplete/gu05`
   is 1.9x SLOWER with the cause unisolated, so the report recommends NOT flipping yet. **The
   ranked-first question is now that regression** — an instrumented build separating the two
   candidates in §3j — and after it `unify`, the last unmodelled deletion.
   **Stage 5 — DONE 2026-09-03 (§3g), outcome: BOTH branches implemented and measured, both
   DEFAULT OFF.** `-Dermine.splitRow` and `-Dermine.resRow` exist in `Constraints.scala` with
   one shared lazy lookup, the correspondence is proved for the spec the compiler's lookup
   really meets (`Rowpartition/KeyedRowScala.lean`, `scalaRowSplit_step`,
   `scalaRowRes_step`), and every adoption gate is green in four configurations
   (`tracker/satterm/KEYED-ROW-STAGE5.md`). The ranked-first question is therefore
   ANSWERED in Lean and IMPLEMENTED in Scala; what remains is a DECISION, not work:
   the two one-line flips are written out unapplied in the report §C.2, with ADOPT WITH
   CAVEATS for both as ONE decision (the theorem is a property of the pair — `splitRow`
   alone bounds only the split fragment and `resRow` alone bounds nothing). The honest
   caveat the measurement adds: the population is SMALL (`SplitRow` 4 firings in 3 of 110
   example modules, `ResolutionRow` 19 in 5, both zero in a stdlib boot), because the
   carrier `w <- ((|C \ K|))` exists essentially only where `makeConcrete`'s own
   cancellation has just built it — and at 74 of the 157 kept-definition mints the
   complement is the EMPTY row, whose carrier `makeEmpty` has deleted (§3g, report §B7-2).
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
| `tracker/lean/Rowpartition/KeyedRow.lean` | Stage 4: the CONCRETE-ROW reuse (`ConcCarried`, `Carried`, `conc_lone_sat`, `concRow_reuse_sat`, `K2SplitStep`'s four branches with `¬ Named` on the non-syntactic ones), the faithful deletion (`srsOf`, `concretizeSrs`, `concretizeSrs_sound`, `concDef_persists`), the invariant `carried_concretizeSrs` with its two modes (`carried_of_deleted_def`, `carried_of_absorbed_mention`), the budget `uncarried`/`hmeas` and the bounds (`mintsBoundedOnSat_splitFragment`, `mintsBoundedOnSatKeyed2Star`), the split-free divergence `W4` (`W4_mints_unbounded`, `not_MintsBoundedOnSatKeyed2`, `keyed2_star_vs_shipped_res`, and `W4_kloop_mints_unbounded` / `W4_not_TerminatesOnSatKeyedLoop`, which refute Stage 3's statement with no split step) and the Stage 3 re-run (`W3srs_eq`, `W3_carried`, `W3_row_reuse`, `W3_not_mintable`) |
| `tracker/satterm/KEYED-ROW-STAGE4.md` | Stage 4 write-up: the relation verbatim, the invariant, the bound, the `W4` witness and what `common` would do to it, the mechanism notes checked one by one, and the UNIMPLEMENTED Scala change |
| `core/.../Constraints.scala` | Stage 2: `GenRules.splitKey` (ADOPTED, default on since 1e6f52b), `SplitKeyed`, `splitConcrete`'s `resolvent` parameter. Stage 5: `GenRules.splitRow` / `GenRules.resRow` (**both ADOPTED, default on**), the `SplitRow` / `ResolutionRow` tags, `splitConcrete`'s fourth branch, `resolution`'s third, and `learnPartitions`' lazy `concRows` lookup. Stage 7: `GenRules.emptyRow` (**default OFF**), the `SplitEmpty` / `ResolutionEmpty` tags, `splitConcrete`'s fifth branch, `resolution`'s fourth, and `learnPartitions`' `envEmptyRow` / `findEmptyRow` with the `implicit hm: SubstEnv` |
| `tracker/lean/Rowpartition/KeyedRowScala.lean` | Stage 5: the correspondence for the two new branches, as a theorem about the spec the compiler's lookup really meets — `MyRowSpec` / `ConcRowSpec` (one `Option` row per variable, `k ⊆ C` asked explicitly), `myRowLookup_spec` / `concRowLookup_spec`, the erase lemmas `bare_erase_iff` and `resolved_erase_iff_row`, the four-branch `scalaRowSplit` with `scalaRowSplit_step : K2SplitStep` and the three-branch `scalaRowRes` with `scalaRowRes_step : K2ResStep`, `scalaRow_starStep`, and the two model-using lemmas `conc_key_subset_of_model` / `concRow_none_uncarried` that close the MINT-guard gaps |
| `tracker/satterm/KEYED-ROW-STAGE5.md` | Stage 5 write-up: the implementation and its faithfulness note (where the compiler keeps a concrete row), every gate in four configurations with its command, the population figures, the deviations with their mechanisms, and Part C — the gate table, the two UNAPPLIED one-line flips with their ADOPTED comments, the re-run list, the honest scope and the per-flag recommendation |
| `tracker/lean/Rowpartition/KeyedEmpty.lean` | Stage 6: `makeEmptyD`, `carried_not_invariant`, `hmeas_increases`, `mintsBoundedOnSat_emptyPersisting`, `mintsBoundedOnSatKeyed3E`, `G7_mints` |
| `tracker/satterm/KEYED-EMPTY-STAGE6.md` | Stage 6 write-up |
| `tracker/lean/Rowpartition/KeyedEmptyScala.lean` | Stage 7: the transcription of the repair — `SoleFact`, `EmptyRowSpec` / `emptyRowLookup(_spec)` / `emptyRowSpec_toConcRow`, the emitted sets `emptyProp` / `splitEmptyResult` / `resEmptyResult` with their entailment (`splitEmpty_models_iff`, `res_empty_forced`, `res_empty_F`, `resEmpty_models_iff`), the composition theorems `emptyReuse_compose` / `resEmptyReuse_compose` and hence `splitEmpty_two_steps` / `resEmpty_two_steps` (`K3ELoopRun 2`), the five- and four-branch `scalaEmptySplit` / `scalaEmptyRes` with `scalaEmptySplit_run` / `scalaEmptyRes_run` and the explicit bound `scalaEmptySplit_bounded` / `scalaEmptyRes_bounded` |
| `tracker/satterm/KEYED-EMPTY-STAGE7.md` | Stage 7 write-up: the implementation and the two design decisions (which lookup, what to emit), every gate with its command, the population, the `gu05` regression with what was and was not established about it, and Part C — the gate table, the UNAPPLIED one-line flip with its ADOPTED comment, the re-run list, the honest scope and the recommendation |
| `tracker/repro/satterm/seeds/G7.json` | Stage 7's witness as a tracked `json:` seed: `KeyedEmpty.G7` plus the `e <- ()` of `G7_blocked`, ordered so the carrier is in the `SubstEnv` when the split premise is dequeued |
| `tracker/repro/satterm/seeds/W3.json`, `seeds/W4.json` | Stage 3's and Stage 4's witnesses as tracked `json:` seeds for `tracker/repro/satterm/sweep.sh` |
| `tracker/tools/splitkey-counts.py`, `splitkey-sweep.sh`, `ei-classify.py` | Stage 2 instruments: split-branch counts per trace, the 110-module traced sweep, `.ei` signature classification |
