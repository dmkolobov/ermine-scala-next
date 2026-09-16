# SUBSUME-STAGE1B-REVIEW — Opus reviewer, stage S1b (the rejection-path model, Lean)

Reviewer: a different Opus agent; did not write the stage.  Worktree
`~/research/ermine/ermine-scala-wt-subsume-s1b`, branch `subsume-s1b`, UNCOMMITTED.
Scratch and every log path below: `/home/dmitry/research/ermine/scratch-subsume/review-s1b/`.
Read in full: `briefs/brief-review.md`, `briefs/brief-S-common.md`,
`tracker/PROMPT-subsume-termination.md` Part B, `SUBSUME-PLAN.md`, `briefs/brief-S1b.md`,
`SUBSUME-STAGE1B.md`, both new Lean modules, the `Loop.lean`/`README.md` diffs,
`Loop/{PolicyTerm,Budget,Decide,Residual,PolicyReplay,PolicyStep,Policy,Hygiene,State,NoConc}.lean`,
`Subst.scala` 160-180 / 221-262 / 298-400 / 600-665 / 1411+, `Constraints.scala` 1225-1345 /
2115-2200, and `~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/SUBSUME-STAGE0.md`.

---

## VERDICT: **FIX-THEN-LAND**

Every theorem in both new modules is correct as stated, builds, audits clean, and nothing in
the existing tree was weakened.  The central repair — `budgetSP_terminates` — is real, is
exactly `budgetP_terminates` minus one hypothesis, and closes a hole that was genuinely open
at the shipped defaults.  The findings below are all in the REPORT's and the docstrings'
prose, which claims more coverage than the theorems carry, plus one sentence that is
factually wrong and one three-line corollary that should ship with the repair.  No proof
needs redoing; no `REWORK`.

---

## 1. My re-run numbers

| command | result | log |
|---|---|---|
| `lake build` (default target `Rowpartition`) | **Build completed successfully (873 jobs)**, `EXIT=0`, 0.84 s (a true no-op on the implementer's tree), no `error:` line | `lake-build.log` |
| `lake env lean Audit.lean` | **`Rowpartition theorems audited: 4733; declarations using a non-standard axiom: 0`**, 1.77 s, `EXIT=0` (`free -g` showed 10 G available; run alone) | `audit.log` |
| `#print axioms` on all **44** new declarations | 0 non-standard; output **byte-identical** to the report's §2.3 paste.  I enumerated the 44 independently from the two files (`theorem`/`def`/`inductive` at column 0) and the lists agree exactly | `axioms.log`, `PrintAxioms.lean` |
| `grep -nE "sorry\|partial \|unsafe \|native_decide\|^axiom "` over both new files | no hits (exit 1) | — |
| transitive import closure of `Rowpartition/Loop/Main.lean` | **60 modules; `Loop.RejectTerm`, `Loop.EnvBound` and `Rowpartition.Loop` are NOT among them** — the `looptrace` executable is untouched, so this is **not a Tier 1 trigger** | in-line python, §2(e) |
| implementer's own logs, opened and checked | `s1b/build-full.log` ends `873 jobs` + `EXIT=0`; `s1b/audit.log` = `4733 / 0`; `s1b/build-looptrace.log` ends `1670 jobs`; `s1b/build-deps.log` ends `871 jobs`.  All say what the report says | `~/research/ermine/scratch-subsume/s1b/` |

**Vacuity — five mutations, all FAIL to elaborate** (`mutate.log`, `mutate2.log`).  Every
mutation lives in a scratch file that only IMPORTS the modules, so the worktree was never
edited:

| mutation | result |
|---|---|
| `budgetSP_terminates` with `hb0 : b ≠ 0` deleted, proof verbatim | **error** — `terminatesBP_of_over_any` cannot be applied |
| `chain_blowup`'s exponent `2 ^ (n+1)` → `2 ^ (n+2)`, proof verbatim | **error** — type mismatch against `size_bal` |
| `stepP_env_len_le`'s bound `+ 1` → `+ 0`, proof verbatim (the `common` branch) | **error** — `Nat.le_succ` no longer types |
| `noAliasChain_instantiate` with `u ≠ v` dropped from `hval`, proof verbatim | **2 errors** — `key`'s conjunction cannot be built |
| `stepP_noAliasChain` with `QueueHygiene s` deleted, proof verbatim | **error** — `queueHygiene_binds_unboundP` cannot be applied |

**Worktree left as found**: `git status --short` = the same five paths (`README.md`,
`Loop.lean`, `SUBSUME-STAGE1B.md` modified; `EnvBound.lean`, `RejectTerm.lean` untracked)
plus this review file.  `tracker/repl-classpath.txt` untouched.  No `.ei` written (no JVM).

---

## 2. The six things I was asked to judge

**(a) The `rowSoundBare` claim and the repair — CONFIRMED, with nothing else weakened.**
Side by side from `#check` (`axioms.log`):

```
budgetP_terminates  : b ≠ 0 → s.flags.rowSoundBare = false → s.flags.emptyRow = false →
                      s.flags.disjRule = false → s.flags.cseMints = false → Wf s → EnvNodup s →
                      SupOk s.su → SupFresh s.su (sys s) → QueueHygiene s →
                      KDist s.incm.elems → KDist s.proc.elems → TerminatesBP pol s.su.drawn b a s
budgetSP_terminates : b ≠ 0 →                                  s.flags.emptyRow = false →
                      s.flags.disjRule = false → s.flags.cseMints = false → Wf s → EnvNodup s →
                      SupOk s.su → SupFresh s.su (sys s) → QueueHygiene s →
                      KDist s.incm.elems → KDist s.proc.elems → TerminatesBP pol s.su.drawn b a s
```

Same implicit binders (`{pol} {b} {a} {s}`), same ten remaining hypotheses in the same order,
same conclusion.  Exactly one hypothesis deleted; nothing narrowed, nothing added.

The gap it closes is real.  Model: `Flags.rowSoundBare : Bool := true` (`Loop/State.lean:378`).
Compiler: `rowSoundBare = rowSoundFlag("ermine.rowSound.bare")` whose default comes from the
master `ermine.rowSound`, default `"true"` (`Constraints.scala:1275-1279`).  So at the shipped
configuration `budgetP_terminates`'s hypothesis is FALSE and the theorem says nothing —
and `TerminatesBP` is already about `runSP`, so the driver the corpus replay and every
adopted-default run go through had no termination theorem.  The repair is sound and cheap:
`stepSP_cases` (RejectTerm.lean:68) is a faithful three-way `split` of `stepSP`
(`PolicyReplay.lean:31-41`) — the pre-check either passes, giving `stepP`'s own step, or dies —
and the two transport lemmas are the `PolicyTerm.lean:1002/1018` originals with
`stepSP_of_rowSound_off hrs` replaced by that dichotomy.  Nothing else changed.

`solveSeedP_terminates` also holds up: `seedInit` (RejectTerm.lean:151) is `solveSeedP`'s `st0`
(`PolicyReplay.lean:~112`) field for field, the split structure matches `solveSeedP`'s four
matches, and the fuel is honestly existential.  The three surviving flag hypotheses
(`emptyRow`/`disjRule`/`cseMints = false`) ARE the shipped values (`State.lean:352-356`), and
`effBudget pol bud ≠ 0` holds at the shipped defaults — `dequeuePolicy` defaults to
`smallcanon` and `solveBudget` to 20000 (`Constraints.scala:1338, 1341`) — and fails under
`-Dermine.dequeuePolicy=shipped`, which the report states plainly (§5 point 2).

**(b) The environment bound — CONFIRMED as far as it goes; see finding 3.**  It is about the
model's `Env` as `RunsP pol n` leaves it, and only that: `runsP_env_len_le` is
`t.env.binds.length ≤ s.env.binds.length + n`.  The five `stepP` branches
(`Policy.lean:285-326`: common / empty / concrete / unify / learn) are all covered and only
the two `unifyVars` branches and `makeEmpty` write the environment, which matches
`Constraints.instantiate` (`instantiateType(v, VarT(u))`, **exactly line 2139**) and
`makeEmpty` (`instantiateType(v, ConcreteRho(Loc.builtin, Set()))`, **exactly line 2191**).
And the report DOES say plainly that it says nothing about entries made outside the loop —
§4 "What to compare with what" (*"that is the WHOLE `SubstEnv` of the module's inference, not
one solve's loop"*) and §5's H3 paragraph (*"That is not the row solver, and this model does
not see it"*).  Good.  My objection is only to the §0 table's unqualified "NO" (finding 3).

**(c) `SubstBlowup.chain_blowup` — CONFIRMED reachable.**  `instEnv` is
`Subst.scala:254`'s `hm.types = subType(Map(v -> e), hm.types) + (v -> e)` exactly.  Each step
binds a variable that is unbound (`chain_keys` = `List.range (n+1)`, `Nodup`) to a term that
does not mention it (`chain_values` + `mentions_bal`: every value is a balanced tree over
`n+1`, the one variable not yet bound), so `occursCheckType(v, e)` is FALSE at
`Subst.scala:314` / `:317` and `instantiateType` runs; the range stays fully substituted (third
conjunct); one entry has `2^(n+1) − 1` nodes.  In compiler terms: unify `v_k` with
`AppT(VarT(v_{k+1}), VarT(v_{k+1}))`, `n` times — the classic ML doubling chain.  See nit 7
on which line the report should cite.

**(d) `stepP_noAliasChain` / `noAliasChain_no_cycle` — CONFIRMED per step, from every seed and
replay state's ENVIRONMENT; run-level composition is finding 4.**  Every seed/replay state
starts `env = {}` (`seedInit`, `Seed.solveSeed`, `Loop/Replay.lean`), so
`noAliasChain_of_binds_nil` applies.  The `hlhs` / `hcom` uses in the two `unifyVars` branches
match `queueHygiene_binds_unboundP`'s three conjuncts (`PolicyStep.lean:451-455`) correctly:
the `common` branch needs `env.contains u = false` for the `findRHS` target and gets it from
`hcom`; the `unify` branch needs `env.contains r.lhs = false` and gets it from `hlhs`; the
disequality comes from `unifyVars_env_ne`, which is a genuine strengthening of
`StrictBound.unifyVars_env`.  `noAliasChain_no_cycle` is `Relation.TransGen`, so the
self-loop `v ↦ VarT(v)` is covered.  And the code reading behind it is right:
`Constraints.instantiate` / `makeEmpty` call `instantiateType` directly and never reach
`unifyType`'s `occursCheckType` — so the loop's acyclicity does rest on queue hygiene, not on
an occurs check.

**(e) Not a Tier 1 trigger — CONFIRMED, independently.**  Transitive import closure from
`Rowpartition/Loop/Main.lean` (the `lean_exe` root; imports `Replay`, `Pump`, `Cycle`, `Depth`,
`Policy`, `PolicyReplay`) reaches 60 modules and none of them is `Loop.RejectTerm`,
`Loop.EnvBound` or `Rowpartition.Loop`.  No executable module, rule, queue operation, flag
default or trace record moved.

**(f) The S0 reconciliation (§6) — CONFIRMED accurate.**  S0's report now runs to 433 lines
(§§0-6).  Every number S1b quotes is in it and matches: `hm.types.size` max **1,566** (mean
272.5, p50 64); **0 cycles** in 186,754 identity-marked walks; tree/DAG ratio max **4.39**;
`:648` total **5.50 s** over **93,377** calls; `checkSkolemEscape:365` **2,793 ms** over
**21,936** calls; `rowSoundBudgetHits = solveBudgetHits = 0`, `rowSoundNodes = 10`; 431 s CPU;
the four-different-places sampling.  S0 and S1b agree on substance: H1 and H2 refuted,
`v.extract` is the variable's KIND and not its binding (Part B's H2 wording loses on both
lanes), and the real defect is `ErmineFixture.no` yielding `passed` rather than `proved`, so
ScalaCheck runs 100 complete checks.  One wording collision: finding 8.

---

## 3. Findings (numbered; file:line, failure scenario, fix)

### 1. `SUBSUME-STAGE1B.md:318` (§6 item 2) — the sentence is false, and the question it poses has a worse answer than it expects

> *"The same hypothesis appears nowhere else in `PolicyTerm.lean`, but a reviewer should
> confirm that no OTHER shipped-default theorem is stated only for `rowSoundBare = false`."*

It appears **in `PolicyTerm.lean` itself**, at **`PolicyTerm.lean:1062`** —
`budgetP_terminates_of_buildQueue`, the initial-state corollary of the very theorem this stage
repaired, still carries `(hrs : fl.rowSoundBare = false)`.  And the answer to the question is
"no": the hypothesis also gates **ten** further declarations, the whole `runSP_*` family —
`PolicyStep.lean:2046` (`runSP_eq_runP`), `:2061`, `:2080`, `:2098` (`runSP_noLoss`),
`:2109` (`runSP_sat_all`), `:2120` (`runSP_models`), `:2132` (`runSP_solved_saturated`),
`:2142` (`runSP_rejects_unsat`), `:2182`, `:2209` — plus `NoFalseAccept.lean:791/801`.
`PolicyStep.lean:2037`'s own prose still calls `rowSoundBare = false` *"the shipped setting"*,
which has been wrong since 2026-09-06.

**Failure scenario.** S2 reads "the hole is closed", and then cites `runSP_rejects_unsat`
("the loop rejected ⟹ the input has no model") or `runSP_noLoss` at the shipped defaults,
where neither applies as stated.  That is the exact class of error this stage was right to
catch — repeated one layer down.

**Fix.** (a) Correct the sentence and list the sites above.  (b) Ship the corollary with the
repair: I verified that

```lean
theorem budgetSP_terminates_of_buildQueue {b : Nat} {a : Aux} {cs : List CsItem} {su : Sup}
    {q : PQueue} {su' : Sup} {fl : Flags} {ns : Names} {site : String} {tr : List String}
    {z : Nat} (hb0 : b ≠ 0) (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z)) (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    TerminatesBP pol su'.drawn b a (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact budgetSP_terminates hb0 hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) (by simp [initState, PQueue.empty, KDist])
```

elaborates — it is `PolicyTerm.lean:1059`'s proof verbatim with `hrs` deleted
(`FixCheck.lean`, exit 0).  (c) Record the `runSP_*` soundness family as an OPEN item for the
orchestrator: it is mechanically closable from `stepSP_cases` (layer (i) only adds DEATHS, and
those theorems' hypotheses are about `.solved` / `.outOfFuel` outcomes), but it is out of
S1b's scope and must not be done silently.  (d) Flag the stale comment at `PolicyStep.lean:2037`.

### 2. `EnvBound.lean:159-192` + `SUBSUME-STAGE1B.md` §2.2, §4, §5 — the `escWalk` claims cover half of `:648` and bound the answer, not the work

Three overstatements, all in the same place:

1. **`escWalk` models only the FIRST half of `Subst.scala:648`.**  That line is
   `hm.fskvs.filter(stss.contains) ++ hm.kindVars.filter(skss(_))`, and
   `SubstEnv.kindVars = Kind.kindVars(kinds) ++ Kind.kindVars(types)` (`Subst.scala:169`)
   walks the KIND ANNOTATIONS of every entry through `mapHasKindVars`
   (`Kind.scala:132-134`).  `EnvVal` has no kind component at all, so the kind half is not
   modelled — and it is precisely the half Part B's jstack sits in
   (`Kind$.kindVars:96 ← SubstEnv.kindVars:169 ← subsumeType:648`) and the half S0's largest
   number (35,921 tree nodes) measures.  (The `fskvs` half IS modelled faithfully:
   `mapHasTypeVars.vars` folds over VALUES only — `Type.scala:771` — which is what
   `escWalk`'s `filterMap` over `binds` does.)
2. **`escWalk_length_le` bounds the LENGTH OF THE RESULT**, via
   `List.length_filterMap_le`.  The docstring's *"costs one visit per entry"* (EnvBound.lean:177)
   and §5's *"one visit per entry, no recursion"* are readings of the DEFINITION, not of the
   theorem — the definition is a `filterMap`, so it has no recursion by construction.
3. **There is no equivalence theorem** tying `escWalk` to `:648` or to anything else in the
   loop model.  It is a definition introduced by this stage.

**Failure scenario.** S2 cites `escWalk_length_le` as licence that "the loop's share of `:648`
is already linear, so only the rest of the map needs the memo table" (§6 item 1 says almost
this), skips the `kindVars` half, and memoises the wrong traversal — the one S0 measured at
2,044 ms rather than the one at 3,457 ms.

**Fix.** Say in both the docstring and §5 that `escWalk` is the `fskvs` half ONLY, that the
theorem bounds the answer's size and not the walk's cost, and that the `kindVars` half is
unmodelled because `EnvVal` carries no kind.  The honest supporting argument for "the loop's
entries are cheap to walk" is `envTermSize_eq_len` plus the `EnvVal` faithfulness note
(`State.lean:315-321`), not `escWalk_length_le`; say that instead.

### 3. `SUBSUME-STAGE1B.md:21` (§0 table, row 3) — "Can the loop leave an enormous `SubstEnv`? **NO**" is stronger than the theorems

`runsP_env_len_le` is `≤ |env₀| + n` where `n` is the number of DEQUEUES, and no a-priori
dequeue bound exists: `TerminatesBP` is `∃ n`, and turning the DRAW budget into a dequeue
bound is `L5-TERMINATION.md` §R8.6b, open.  The report says exactly this itself at §5.1
point 1, which makes the table row inconsistent with its own body.  The unconditional "NO"
belongs only to TERM SIZE (`envTermSize_eq_len`).

**Failure scenario.** S2 compares S0's measured `hm.types.size` = 1,566 against "the loop
cannot leave an enormous environment" and concludes the 1,566 must come from elsewhere,
without checking the module's dequeue count — which the formula makes the actual test.

**Fix.** Split the row: *no in TERM SIZE (one node per entry, proved unconditionally); in
CARDINALITY, at most one entry per dequeue, and the dequeue count has no a-priori bound.*

### 4. `SUBSUME-STAGE1B.md:22, 128` — "no cycle at any state reachable from a seed/replay state" is stated as a run-level fact; only the one-step lemma exists

`stepP_noAliasChain` is per step.  There is no `runsP_noAliasChain` in the file, and the
composition is **not free**: `PolicyStep.stepP_queueHygiene` (`:313-315`) itself needs
`disjRule = false`, `SupOk s.su` and `SupFresh s.su (sys s)` — and at the RUN level
`Hygiene.run_queueHygiene` (`:1363-1370`) is explicit that it is conditional on `RunSupOk`,
*"which L3 records is NOT an invariant; it is what the `learn` branch needs, and it is not
discharged anywhere"*.  The report's §0 row (*"at any state a `continue` step reaches from a
seed/replay state"*) and §2.2 (*"hence from every seed/replay state, since `QueueHygiene` is
itself an invariant"*) read as unconditional.

**Failure scenario.** S2 reads "no cyclic binding is reachable, full stop" and removes or
declines to add an occurs check somewhere the side conditions do not hold.  (Substantively the
verdict survives — S0 measured 0 cycles in 186,754 walks and the walk does not follow bindings
at all — but the report must not assert more than the file proves.)

**Fix.** Either add the run-level corollary with its hypotheses named, or state the three side
conditions and the `RunSupOk` caveat at both places.

### 5. `SUBSUME-STAGE1B.md:44` (§1 table, `lake build looptrace` row) — the README comparison is wrong

*"the same job count the README records for the executable"* — `tracker/lean/README.md`
records **24 jobs** for `lake build looptrace` (`README.md:57`) and the string `1670` appears
nowhere in it.  The substantive claim (no executable module changed) is TRUE and I verified it
by transitive import closure (§2(e)), which is a much better argument than a job count.

**Fix.** Drop the README comparison; cite the import graph.

### 6. `SUBSUME-STAGE1B.md:309, 333` — two sections numbered `## 6`

Renumber the reconciliation section to `## 7`.

### 7. (nit) `EnvBound.lean:205-208` and `SUBSUME-STAGE1B.md` §5 — the blow-up's binding site is misattributed

*"`unifyType`'s `AppT` case is the compiler path that does this"* / *"`n` ordinary
unifications through `unifyType`'s `AppT` case"*.  The BINDING happens in the
`case (VarT(v), e) if v.ty != Skolem` / `case (e, VarT(v))` arms at **`Subst.scala:313-318`**,
which is where `occursCheckType` is tested and `instantiateType` (`:254`) is called.  The
`AppT` arm at `:319` is what puts a compound term on the other side and what applies
`substType(t1)` — relevant, but not the binder.  Name `:313-318` so S1a and S2 look at the
right line.

### 8. (nit, cross-report) `SUBSUME-STAGE1B.md` §5, H3 heading — wording collides with S0

*"H3 — the walk is the victim: **REFUTED** ... in both halves"*.  What is refuted is H3's
proposed MECHANISM (*"grows the environment or diverges BEFORE `subsumeType`"*); the "the walk
is only where the thread was sampled" claim SURVIVES and is exactly S0 §5.4's conclusion
(*"H3 — the walk is the victim: **SURVIVES**, with a correction"*).  The report's own §6 then
says the two agree — they do, on substance, but a reader comparing the two headings sees a
contradiction.  Reword to "H3's proposed mechanism is refuted for the row solver; its weaker
half — `:648` is only where the thread was sampled — survives, and S0 measured it."

---

## 4. The answer I would sign

Separately from the verdict, and for the running answer in `SUBSUME-PLAN.md`:

**The loop: BOUNDED.**  Under the configuration the compiler ships — `dequeuePolicy=smallcanon`,
`solveBudget=20000`, `rowSound=true` — every solve's loop stops, under any dequeue policy:
`budgetSP_terminates`.  It is a BUDGET theorem, not a termination theorem for the algorithm
(eight L5 rounds; `L5-TERMINATION.md` §R8.6), the fuel is existential, and it therefore bounds
no wall clock.  Under `-Dermine.dequeuePolicy=shipped` the budget is off (`effBudget = 0`),
the hypothesis `b ≠ 0` fails, and there is **no termination theorem at all** — D1 measured
real divergence there.

**The rest of `Subst.solve`, row fragment: YES** — `solveSeedP_terminates`, conditional on
`buildQueue` succeeding and on a nonzero effective budget.  `buildQueue`, `topNormalise`,
`labelCheckEarly`, `labelDecide` (with its two node budgets) and the late `labelClash` are
total functions of the model — I checked: they are plain `def`s, no `partial`
(`Loop/Decide.lean:213, 240, 265, 335`) — so the loop is the only layer that can fail to stop.
The tie between the model and the compiler is L2's measured differential (2,355,430 corpus
solve segments, 0 mismatches), not a proof, and the report says so.

**`subsumeType`'s post-solve steps: PARTIAL — weaker than the report states.**
`restrictTypes` is a finite map difference (code fact).  `entails` on the row fragment returns
`false` without recursing — I verified it: `unfurlApp` (`Subst.scala:370-374`) returns `None`
for a `Part`, so `byInst` is `None` and, when the givens are also `Part`s, `bySuper` is `Nil`
(`:376-397`); the only recursion is through the class hierarchy, and classes are on HOLD.
`SigEntail.enforce` is not covered.  The escape check at `:648` has a theorem **only for the
`fskvs` half, only over the LOOP's own entries, and only as a bound on the ANSWER's size** —
the `kindVars` half is unmodelled (finding 2).  So: the loop's contribution to `:648` is
bounded; `:648` as a whole is **not** proved bounded by this stage.

**The environment the loop leaves: BOUNDED in term size unconditionally** (one node per entry,
`envTermSize_eq_len`, because the loop's only two writes are `VarT(u)` at
`Constraints.scala:2139` and `ConcreteRho(∅)` at `:2191`), **and in cardinality by the number
of dequeues**, which has no a-priori bound.  It says nothing about entries made outside the
loop, and the report is explicit about that.

**Hypotheses.**  **H2 refuted** for this path, twice over (`stepP_noAliasChain` +
`noAliasChain_no_cycle`; and the walk reads `v.extract`, the KIND, never the binding —
Part B's H2 wording is wrong about the code and the document loses).  **H1 not available to
the row solver**, and located: `SubstBlowup.chain_blowup` shows the exponential belongs to the
general `instantiateType` reached from `unifyType`'s variable arms, with every occurs check
passing — so an acyclicity invariant is not a defence against it.  **H3's proposed mechanism
refuted for the row solver at the shipped defaults**; its weaker half — `:648` is only where
the thread was sampled — survives, and S0 measured it.

**Against the brief.**  All three deliverables of `brief-S1b.md` are answered: (1) what
`budget_terminates` guarantees for this solve at the shipped defaults, stated and repaired,
plus what it does not cover, stated; (2) the environment bound as a formula S2 can compare
with S0's numbers; (3) the cyclic-binding question, answered negatively with an invariant
rather than a witness, plus the note that the walk does not follow bindings anyway.  No
theorem was weakened to pass: `budgetSP_terminates` is strictly stronger than
`budgetP_terminates`, and every other new declaration is additive.

---

# Re-check — 2026-09-16, after the implementer applied all eight findings

Scope: the findings only, as asked.  Logs under
`/home/dmitry/research/ermine/scratch-subsume/review-s1b/`
(`recheck-build-audit.log`, `recheck.log`, `axioms-post.log`, `ReCheck.lean`).

## VERDICT: **LAND**

All eight findings are addressed, two of them better than I asked.  Nothing existing was
touched.  Two cosmetic residuals below, neither blocking.

## My own re-run (not the implementer's logs)

| command | result |
|---|---|
| `lake build` | **873 jobs, `BUILD_EXIT=0`** (the `error: unknown tactic` lines are the style linter reading doc-comment text in pre-existing `NameLoss*`/`KeepInert`/`DefaultDiverge` modules; they were there before this stage and are `info:`-level, not build errors) |
| `lake env lean Audit.lean` | **`Rowpartition theorems audited: 4735; declarations using a non-standard axiom: 0`**, `AUDIT_EXIT=0` — exactly +2 on my pre-fix 4733 |
| `#print axioms` on the two new declarations | both `[propext, Classical.choice, Quot.sound]` |
| **no existing statement changed** | I re-ran my OWN pre-fix `PrintAxioms.lean` (all 44 original declarations' `#print axioms` **plus** eight full `#check` statements — `budgetSP_terminates`, `budgetP_terminates`, `solveSeedP_terminates`, `stepP_noAliasChain`, `noAliasChain_no_cycle`, `chain_blowup`, `runsP_env_len_le`, `envTermSize_eq_len`) and `diff`ed it against my pre-fix output: **IDENTICAL, zero lines**.  No original declaration's statement or axiom footprint moved |
| worktree | still the five expected paths plus this review file; nothing committed; no `.ei` |

## The two new statements, against what I asked for

**`budgetSP_terminates_of_buildQueue` (RejectTerm.lean:157) — verbatim minus `hrs`, confirmed.**
Printed side by side against `PolicyTerm.budgetP_terminates_of_buildQueue` (`recheck.log`): same
twelve implicit binders (`{pol} {b} {a} {cs} {su} {q} {su'} {fl} {ns} {site} {tr} {z}`), same
hypotheses in the same order with exactly `fl.rowSoundBare = false` removed, same conclusion
`TerminatesBP pol su'.drawn b a (initState q su' tr fl ns site z)`.  Nothing else changed.

**`runsP_noAliasChain` (EnvBound.lean:562) — the three side conditions, confirmed.**

```
∀ {pol} (n) {a c} {s t},
  s.flags.disjRule = false → RunSupOkP pol a n s → QueueHygiene s → NoAliasChain s.env →
  RunsP pol n a s c t → NoAliasChain t.env
```

Exactly `disjRule = false`, `RunSupOkP`, `QueueHygiene` as hypotheses, as asked.
`stepP_noAliasChain`'s own statement is byte-identical to my pre-fix `#check` and its docstring
now opens "This is a ONE-STEP statement ... do not read this lemma as 'no cycle is reachable,
full stop'."

**On the `RunSupOk` non-discharge, the implementer is RIGHT and my finding 4 was half-wrong.**
I had quoted `Hygiene.lean:1363`'s *"it is not discharged anywhere"*, which is STALE: round 3's
follow-up added `Supply.runSupOk_of` (`Supply.lean:735`), which discharges `RunSupOk n s` from an
input's own `SupOk`/`SupFresh`, and `Solve.lean:87/106` uses it.  The new docstring says
"DISCHARGEABLE ... **for the shipped order** ... but it is a hypothesis here", which is exactly
accurate: `runSupOk_of` is proved for `step`, and there is **no `runSupOkP_of`** anywhere in the
tree for the policy form — every consumer of `RunSupOkP` (`PolicyStep.lean:1836`-`:1986`) takes
it as a hypothesis.  Good catch against my own text.

## The corrected prose

Read in full: report §0 rows 3-4, §6 item 2, §7, §8, §9; `EnvBound.lean` §3 header and both
`escWalk` docstrings; `stepP_noAliasChain` / `runsP_noAliasChain` docstrings; `RejectTerm.lean`'s
new corollary docstring; the `README.md` S1b diff; `Loop.lean`'s module map.  No remaining
overclaim.  Three things are now stated better than my findings required:

* §6 item 2 names all thirteen sites and adds an explicit **OPEN ITEM for the orchestrator** —
  *"S2 must not cite any `runSP_*` soundness theorem at the shipped defaults"* — which is the
  operative instruction I only implied;
* §6 item 1 now carries a direct warning against the misreading I described as the failure
  scenario (*"Do not read `escWalk_length_le` as a licence to memoise only 'the rest of the
  map'"*, with S0's 3,457 ms vs 2,044 ms split), and §6 item 4 records the `kindVars` half as
  a standing gap no model in this tree covers;
* `EnvBound.lean` §3's header leads with **READ THE SCOPE BEFORE THE THEOREM** and separates a
  fact about the definition from a theorem about the compiler, which is the distinction
  finding 2 was about.

§1's `looptrace` row now cites the import closure and records the earlier draft's error (5);
§5's H3 paragraph is reworded and explicitly reconciled with S0 §5.4 (8); `:313-318` is named
with `:254` and what `:319` does instead (7); the reconciliation is `## 7` (6).

## Residuals — cosmetic, do not block the landing

1. **`SUBSUME-STAGE1B.md:10` and `:29`** still point at "§6" for the S0 reconciliation, which
   finding 6's fix moved to **§7** (*"§6 reconciles the two"* in the header note; *"S0's
   measurements (§6) refute H1 and H2"* under the §0 table).  The other "§6" references in the
   file — §2.2's row, §9's table — correctly mean the Open-questions section and are fine.
   Fix: change those two to §7.
2. **`EnvBound.lean:554`** (`runsP_noAliasChain`'s docstring) says `RunSupOkP` is dischargeable
   "for the shipped order".  True, and correctly qualified — but the ADOPTED default policy is
   `smallcanon`, which is *not* the shipped order, so at the shipped **defaults** this theorem's
   `RunSupOkP` is undischarged.  Worth one clause saying so, since the whole point of
   `budgetSP_terminates` was that "shipped setting" and "shipped defaults" had drifted apart.

## The signed answer is unchanged

§4 above stands as written, with one strengthening: the loop half now has
`budgetSP_terminates_of_buildQueue` at a solve's own initial state as well as
`budgetSP_terminates`, and the no-cyclic-binding half is now a run-level theorem
(`runsP_noAliasChain`) with its three side conditions named rather than a one-step lemma read
as if it were one.
