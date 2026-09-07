# S4c — the correspondence lemma, and the S2 chain at `topNormalise = true`

**OUTCOME: GREEN.**  S4c-1 (the correspondence lemma) and S4c-2 (the six no-false-acceptance
theorems restated without `htn`) are both closed, and S4c-3 (a `LoopStrict` account of the
rewrite) fell out.  LEAN ONLY: no Scala change, no example change, no executable Lean change —
the `looptrace` binary was not rebuilt because nothing in its import closure moved.

Stage S4c of `tracker/LOOP-MODEL-PLAN.md`, from commit `c48f178` (S4: the written-partition
normalisation behind `-Dermine.topNormalise`, DEFAULT OFF).  Brief
`tracker/loopmodel/briefs/brief-S4c.md`; the two items are the ones `S4B-REVIEW.md` §2.2, §5.2
and H-9 named as conditions of ever flipping the flag ON.

## 0. Where the work landed

| file | what |
|---|---|
| `tracker/lean/Rowpartition/Loop/TopNormalise.lean` | **NEW, 1,476 lines, 111 theorems.**  Carries `S4Top.lean`'s §0–§5 verbatim (namespace `Rowpartition.S4`) plus the whole correspondence (namespace `Rowpartition.Loop`) |
| `tracker/lean/Rowpartition.lean` | root import list + doc bullet, so `Audit.lean` covers it |
| `tracker/lean/Rowpartition/Loop/NoFalseAccept.lean` | imports the new module; `solveSeed_rejects_of_refuted`, `solve_noFalseAccept`, `solve_accepted_faithful` restated without `htn`; three new theorems (`…_off`, `…_input` ×2) |
| `tracker/lean/Rowpartition/Loop/PolicyStep.lean` | the three twins restated without `htn`; three new (`…_off`, `…_input` ×2) |
| `tracker/loopmodel/S4Top.lean` | **replaced by a one-line pointer.**  Its content now lives in the library file above, so the 18 theorems are inside the project-wide axiom audit instead of beside it |

The executable definitions are untouched: `topFamilies_eq` and `topNormalise_eq` are `rfl`, so
every theorem below is about the term `Loop/Json.lean` defines and `looptrace` runs.  Nothing was
restructured, so the brief's byte-identity obligation is discharged by construction (§4, G-5).

## 1. S4c-1 — the correspondence lemma, statement by statement

The vocabulary: `sysQ q := (q.elems.map LPart.toConstraint).toFinset` is the system a QUEUE
denotes (`sys_initState_eq` says it is `sys` at an initial state, so it is the object S1's and
S2's theorems are already about).  `TopFam ps v fam F` is the selector's guarantee; `TnOk L q su`
is the side-condition bundle; `tnAdds` / `tnReads` are the multi-family `⋃ topAdds` / `⋃ topReads`.

### (a) every family the selector returns meets the abstract theorems' hypotheses

**`topFamilies_spec (hnd : ∀ p ∈ q.elems, p.rhs.conc.Nodup) (h : (v, fam, F) ∈ topFamilies q) :
TopFam q.elems v fam F`**, whose fourteen fields are exactly the brief's list:

| field | what is proved | discharged from |
|---|---|---|
| `eqFam` / `eqF` | `fam` IS `famOf q.elems v`, `F` IS `unionOf (disOf fam)` | the `filterMap`'s own `some` branch |
| `mem` | every member is a partition of the queue | `List.mem_of_mem_filter` |
| `lhs` | every member has left-hand side `v` | the filter's `p.lhs == v` |
| `read` | every member is `v <- (x, F_i)` with a LONE abstract part and `x ≠ v` | `IsRead`'s `abstrSingle?` match and its `x != p.lhs` |
| `concNe` | every `F_i` is non-empty | `IsRead`'s `!p.rhs.conc.isEmpty` |
| `ne` | `fam ≠ []` | from `card` (an empty family has no distinct parts) |
| `noConc` | `v` carries no concrete row of its own | the `ps.any (… && p.rhs.abstr.isEmpty)` guard |
| `card` | `3 ≤ (disOf fam).length` — the `k ≥ 3` trigger | the `dis.length < 3` guard |
| `distinct` | the distinct parts are pairwise non-`eqv` (`List.Pairwise`) | `disOf_pairwise`, the de-duplicating fold's invariant |
| `incomp` | pairwise INCOMPARABLE: `c.eqv d ∨ ¬ c.subsetOf d` | the `dis.all (… ‖ !subsetOf)` guard |
| `union` | `F = ⋃ F_i`: every label of `F` comes from a member | `disOf_sub` + `mem_unionOf` |
| `sub` | `F_i ⊆ F` | `disOf_covers` + `SSet.eqv_iff_mem` |

**The one hypothesis**, `hnd`, is `Wf`'s (`POk.conc.nodup`, i.e. `Wf.incm`): it is needed
because Scala's `Set` equality is `size == size && subsetOf`, which is equality of the underlying
sets only on duplicate-free lists — the `sub` clause is the one that needs it, since the
de-duplicating fold keeps a REPRESENTATIVE `d` with `d.eqv F_i` rather than `F_i` itself.

Two further selector facts, both proved: `tnCarriers_length` (one carrier per family) and
`recsOf_carriers` (the `tnorm` trace records carry exactly those carriers, in order).

### (b) the carrier is fresh for the WHOLE system, one per family, all distinct

**`carriers_spec (H : TnOk L q su)`** gives all three at once:

* `carriers_notMem` — every carrier is `∉ allVars (sysQ q)`.  Proved from the `Supply` itself,
  not assumed: `RefineLearn.fresh_notMem` for the first draw and `SupFresh.step` to carry
  `SupFresh` across it, so the `n`-th carrier is fresh for the whole INPUT system.  This is the
  premise `S4Top.ssat_rewrite_fwd` needs and the one `Cut.ResApp.fresh` carries for the shipped
  `resolution` mint.
* `tnCarriers_length` — `|carriers| = |plans|`: one draw per family, from the fold's shape.
* `carriers_nodup` — pairwise distinct, from `fresh_reach_mono` (an id drawn later is still
  reachable from the later supply, hence different from the one already drawn).

Freshness *within* the growing system (family `j`'s carrier fresh for `G` plus families
`1..j-1`'s blocks) is handled inside `ssat_addAll` by `allVars_topAdds_sub`: a block's vocabulary
is `allVars G ∪ {c}`, so `SupFresh.step` applies at each step.

### (c) the returned queue, read as a system

**`topNormalise_sysQ (H : TnOk L q su) : sysQ (topNormalise true q su).1 =
(sysQ q ∪ tnAdds (topFamilies q) su) \ tnReads (topFamilies q)`.**

* the multi-family composition is stated and proved: `tnAdds_eq` says the added partitions
  denote `⋃_t S4.topAdds t.1 c_t (cfs F_t) (famRows t.2.1)` (via `toFinset_topBlock`, which is
  where `cfs_removedAll` turns the Scala's `F -- F_i` into the abstract `F \ F_i`), and
  `tnReads_eq` says the deleted reads denote `⋃_t S4.topReads t.1 (famRows t.2.1)`;
* **one pass over the ORIGINAL families** is not an assumption but the shape of the statement:
  `topFamilies q` is computed once from `q` and both sides quantify over that list;
* the union-then-difference form is legitimate because **adds and reads are disjoint**
  (`adds_notMem_reads`): every added constraint mentions a carrier in its `vset`, every deleted
  read is a constraint of `sysQ q`, and the carriers are `∉ allVars (sysQ q)`.  That is what makes
  the rewrite order-independent, and it is exactly (b) doing work;
* the two things `PQueue(ps)` drops are handled rather than assumed: a DUPLICATE leaves an
  `equals`-equal representative behind (`ofList_repr`, and `LPart.eqv_iff_toConstraint` says
  `equals` IS equality of the constraints), and a SELF-UNIFICATION cannot occur — for the input by
  `buildQueue_no_self` (`TnOk.self`), for the added block by `topBlock_not_self`, whose whole
  content is that the right-hand side carries the FRESH carrier while a self-unification's carries
  the left-hand side, a variable of the system.

### (d) the executable rewrite is satisfiability-equivalent

* **backwards** — `topNormalise_models` : `SModels rho (sysQ q') → SModels rho (sysQ q)`.  A
  deleted read is recovered by `S4Top.read_of_top` from the written partition and its
  re-expression, both of which are in `sysQ q'` by (c) and `adds_notMem_reads`; every other
  constraint survives the filter.  Hence **`topNormalise_noLoss : NoLoss (sysQ q) (sysQ q')`** in
  `Loop/Strict.lean`'s own vocabulary, which is `noloss_of_top` made concrete.
* **forwards** — `topNormalise_ssat_fwd`, from `ssat_addAll`, which is one
  `S4Top.ssat_rewrite_fwd` per family threaded through the supply.  `F ⊆ rho v` is not assumed: it
  follows from the reads (`conc_subset_lhs` at each `F_i`, plus `TopFam.union`).
* **together** — **`topNormalise_ssat_iff : SSat (sysQ q) ↔ SSat (sysQ q')`**.
* **`Conserv`** is stated honestly: `Conserv (sysQ q) (sysQ q')` is FALSE for any mint (the
  carrier is unconstrained by `G`; `S4Top.topAdd_escapes` is the reason).  What holds and is
  proved is `topNormalise_conserv : Conserv (sysQ q ∪ tnAdds …) (sysQ q')` — beyond the mint the
  rewrite invents nothing.  The introduced name is FORCED (`S4Top.top_forced`), which is why this
  is a conservative extension rather than an arbitrary addition.

### S4c-3 (optional in the brief) — it fell out

**`topNormalise_loopStrict : LoopStrict (sysQ q ∪ tnAdds …) (sysQ q')`**: the DELETION is a
`LoopStrict.drop`, with its `NoLoss` premise discharged by the written partition.  No new
constructor was added to the inductive: the MINT half is still the additive step `S4Top` §5
describes and `LoopStrict` has no constructor for (it is shaped like `res`).  Adding one is a
one-line change to the inductive and was deliberately not made — it is not needed by any theorem
here and it would touch a definition thirty other modules pattern-match on.

### Not vacuous, checked in the kernel

`exQ` is three reads at one left-hand side with distinct singleton parts — the smallest shape the
`k ≥ 3` trigger accepts, and the shape `S4-DESIGN.md` §1 measured off the compiler's `scon`
records.  `exQ_fires` (`decide`) says the selector returns exactly one family, at `v = 1`, with
three reads and `|F| = 3`; `exQ_tnOk` discharges every side condition at a concrete supply; and
`exQ_sys` / `exQ_equiv` are (c) and (d) instantiated on it.  So neither the hypotheses nor the
conclusions are empty.

`tnOk_of_buildQueue` shows how a caller gets `TnOk` from the code: `qok` is `Wf.buildQueue_qok`,
`self` is `buildQueue_no_self` (proved here), and what remains is `LblCoh` (`Wf.coh`) and the
supply invariant `SupOk`/`SupFresh`, which is the hypothesis every run-level theorem in this
development already carries and `Supply.lean` proves is preserved by `step`.

## 2. S4c-2 — the S2 chain at `topNormalise = true`

**All six `htn : fl.topNormalise = false` premises are gone**, and no statement was weakened.

The move is the one the brief prescribes: the theorems used to name `buildQueue`'s queue and
then assume the rewrite could not have changed it; they now name **the queue the checks actually
read**, and `htn` becomes the rewrite's OWN EQUATION, which holds at either setting of the flag:

```lean
(hq  : buildQueue cs su0 = .ok (q0, su0'))
(htn : topNormalise fl.topNormalise q0 su0' = (q, su1, rc))
```

| theorem | before | after |
|---|---|---|
| `solveSeed_rejects_of_refuted` | `htn : … = false` | `htn` = the rewrite's equation; conclusion unchanged |
| `solve_noFalseAccept` | same | same; concludes `SSat` of the LIVE input (queue read by the checks, plus `envFacts`) |
| `solve_accepted_faithful` | same | same; the S1 half is about `initState q su1 …`, the state the loop really starts from |
| `solveSeedP_rejects_of_refuted` | same | same |
| `solveP_noFalseAccept` | same | same |
| `solveP_accepted_faithful` | same | same |

**No silent weakening**, and it is a theorem, not a claim: `solveSeed_rejects_of_refuted_off` and
`solveSeedP_rejects_of_refuted_off` are the S4 statements recovered verbatim, proved by handing
the general theorem `topNormalise_off` (which is `rfl`).  At OFF the rewrite is the identity and
`q = q0`, so the other four are literally the same proposition as before.

**And the statement about the input the compiler was HANDED** — the thing that actually matters
at ON, because with the flag ON the three checks decide the REWRITTEN queue — is four new
theorems, each `htn`-free and each using S4c-1(d) as the bridge:

* `solve_noFalseAccept_input` / `solveP_noFalseAccept_input` : a solve that does not reject says
  **`buildQueue`'s own queue** (plus the environment facts) has a model.  Via `tn_models`.
* `solve_accepted_faithful_input` / `solveP_accepted_faithful_input` : an accepted solve is
  faithful **to the input**: `NoLoss (sysQ q0) (sys s')`, every model of the output is a model of
  the input, and `SSat (sysQ q0) ↔ SSat (sys s')`.  Via `NoLoss.trans` on `tn_noLoss` and
  `tn_ssat_iff`.

`tn_models` / `tn_noLoss` / `tn_ssat_iff` are the flag-parametric bridge: each is a case split on
`fl.topNormalise`, with the OFF branch closed by `topNormalise_off` (`rfl`) and the ON branch by
S4c-1(d).  They take `TnOk L q0 su0'` — which the OFF branch does not use at all.

## 3. What remains

Nothing that was asked for, and three things worth writing down:

1. **The `_input` theorems carry `TnOk L q0 su0'`.**  Two of its five fields are proved from the
   code (`buildQueue_qok`, `buildQueue_no_self`), one is `Wf.coh`, and two are the supply
   invariant `SupOk`/`SupFresh` at `su0'` — the same pair `run_noLoss`, `run_ssat_iff` and
   `vocFixed_terminates_of_buildQueue` already require, discharged the same way (`Supply.lean`
   §5).  This is not a new assumption; it is the development's standing one, now also needed
   *before* the loop because the rewrite mints before the loop.
2. **No `LoopStrict` constructor for the additive mint.**  S4c-3 asked only "if it falls out";
   the DROP half did and is proved, the MINT half would need a new constructor in the inductive.
   Stated as a fact about the adoption, not hidden: the rewrite is TWO steps of the relation and
   the relation currently has a constructor for only one of them.
3. **The correspondence is about the MODEL's `topNormalise`, not about the Scala's.**  That link
   is the L2 corpus differential, which S4 ran and which this stage re-ran (720/720 at the
   shipped defaults; the ON differential was S4's, `S4-CHANGE.md` §5).  This stage changed no
   executable Lean, so that evidence stands unchanged.

## 4. Gates

| gate | result |
|---|---|
| `lake build` (full default target) | **GREEN, 868 jobs** (867 before; the new module is the extra job) |
| `lake env lean Audit.lean` | **4,282 theorems audited, 0 declarations using a non-standard axiom** (4,119 before S4c) |
| `#print axioms`, every new/changed theorem | **123 declarations**: 112 `[propext, Classical.choice, Quot.sound]`, 6 `[propext, Quot.sound]`, 5 `[propext]`.  No `sorryAx`, no `nativeDecide`.  Saved at `/home/dmitry/.claude/jobs/880c725d/tmp/S4c/axioms.out` |
| `lake build looptrace` | up to date, **not rebuilt** — the binary's mtime (15:12) predates every edit in this stage (16:43 onwards), because nothing in `Main.lean`'s import closure (`Json`, `Seed`, `Replay`, `PolicyReplay`, `Policy`, `Depth`, `Pump`, `Cycle`) changed |
| `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'` | **720/720 segments agree**, 720 solves, hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0, 9,218 ms (re-run on the final tree; 9,149 ms on the first); controls still disagree (46/720 at id base +1, 58/720 at `--flags=nongen`); `Passed: Total 3, Failed 0, Errors 0` |
| ON differential on `Present` + `Lang` | **NOT REQUIRED and not run**: the brief conditions it on "if any executable Lean changed", and none did — `git status` shows the only modified files are `Rowpartition.lean` (import list), `NoFalseAccept.lean` and `PolicyStep.lean` (proof modules, in no executable's import closure), plus the new `TopNormalise.lean` (imported by `NoFalseAccept`, not by `Main`) |
| `.ei` files | **none created**: `find . -name '*.ei' -newermt '2026-09-07 15:00'` is empty; the 143 pre-existing files are untouched |
| commits | **none**, as instructed |

The adoption itself — flipping the flag, moving `core/examples/Present/shouldfail/proj01_seven_reads.e`,
clearing the `.ei` cache — is the user's, and is unchanged by this stage except that the two Lean
prerequisites `S4B-REVIEW.md` §5.2 listed are now met.
