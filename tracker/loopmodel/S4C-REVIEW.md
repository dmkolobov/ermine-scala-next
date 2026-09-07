# S4c review — the correspondence lemma, and the S2 chain at `topNormalise = true`

**VERDICT: ADVANCE (commit).**  Findings `J-1`…`J-8`, none against the Lean: `J-1` is a
STATEMENT the stage does not make and should have named in its residue list (it is the one
direction the flip newly exercises), the rest are prose and scope notes.  Every gate reproduced
independently, every claim in `S4C-CORRESPONDENCE.md` checked statement by statement, and the
two adversarial questions the brief asks — "is the `rfl` link real?" and "was the S2 chain
weakened?" — answered YES and NO, both mechanically.

**ADOPTION: YES, flip `-Dermine.topNormalise` ON by default — in its own commit, with `J-1`
closed first (one theorem, ≤ 30 lines) and with the four adoption obligations of §5 in the same
commit.**  All FOUR of `S4B-REVIEW.md` §5.2's conditions are now met; this review adds a fifth
that is cheap and belongs before the flip rather than after it.

Reviewed at HEAD `d86682a` plus the UNCOMMITTED S4c deliverables.  Scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-S4c/` (`A_link.lean`, `B_old_from_new.lean`,
`C_adv.lean`, `D_kernel.lean`, `E_reject.lean`, `F_nonvac.lean`, `AxiomsJ.lean`, `axioms-J.out`).
Nothing edited outside that directory and this file; no commits; no `.ei` created.

---

## 1. The statements are the right statements

### 1(a) The `rfl` link is REAL — it is the code `looptrace` runs

CONFIRMED, three ways (`A_link.lean`).

* **Provenance.**  `Rowpartition.Loop.topFamilies` and `Rowpartition.Loop.topNormalise` resolve,
  in the environment, to module `Rowpartition.Loop.Json` — the executable mirror.  The new module
  defines neither; it opens the same namespace and states equations about them.  So
  `topNormalise_ssat_iff` is about the term `Loop/Json.lean:187-232` defines, not a copy.
* **The equations really are `rfl`.**  `#print Rowpartition.Loop.topFamilies_eq` prints
  `@[defeq] theorem … := fun q => rfl`; likewise `topNormalise_eq`.  Their right-hand sides are
  the executable bodies with the helper names `IsRead` / `famOf` / `disOf` / `unionOf` /
  `candOf` / `keepOf` / `tnStep` substituted for the anonymous `let`s, so the naming is a
  refactor of the STATEMENT, not of the code.
* **The code did not move.**  `git diff --stat` touches no executable Lean; I recomputed
  `Rowpartition.Loop.Main`'s transitive import closure (72 modules) and `TopNormalise`,
  `NoFalseAccept`, `PolicyStep` and the root `Rowpartition` are all OUTSIDE it, which is why the
  binary legitimately was not rebuilt (§4).

**`S4Top.lean`'s §0–§5 really are verbatim.**  `diff` of `git show HEAD:tracker/loopmodel/S4Top.lean`
lines 48–304 against `TopNormalise.lean` lines 47–303: **IDENTICAL**, byte for byte.  The pointer
file is honest.

### 1(b) `TnOk`: what is proved and what is assumed

`TnOk L q su` has five fields.  Traced to their sources:

| field | status | source |
|---|---|---|
| `coh : LblCoh L` | **assumed** | `Wf.coh`; the hypothesis `Loop/Reject.lean` and the whole S2 chain already carry |
| `qok : QOk L q` | **from the code**, modulo an input condition | `buildQueue_qok`, which itself needs `hcs : ∀ c ∈ cs, CsItem.InPool L c` |
| `self : ∀ p ∈ q.elems, ¬ isSelfUnification` | **from the code, unconditionally** | `buildQueue_no_self`, proved here from `PQueue.insertNP`'s own guard |
| `sup : SupOk su` | **assumed** | `RefineLearn.SupOk`, `Supply.lean` §4 preserves it |
| `fresh : SupFresh su (sysQ q)` | **assumed** | `RefineLearn.SupFresh` |

The report's claim that `sup`/`fresh` are "the development's standing assumption" is CORRECT and
I checked the citation: `RefineLearn.RunSupOk (n+1) s = SupOk s.su ∧ SupFresh s.su (sys s) ∧ …`
(`RefineLearn.lean:1499-1501`), and `run_noLoss` / `run_sat_all` / `run_ssat_iff`
(`Sound.lean:1016`, `RefineLearn.lean:1504`) all take `RunSupOk n s`.  So `TnOk` asks for exactly
the pair the loop already asks for, one step earlier — before the loop, because the rewrite mints
before the loop.  That is a fair characterisation and §3 of the report states it.

**Are they true of the seeds the compiler emits?**  Yes, and for the reason the report gives.
`Sup.Reach su z := (su.lo ≤ z ∧ z < su.hi) ∨ su.blk ≤ z` (`RefineLearn.lean:38`), so the ids the
supply can still hand out are the unspent tail of the current block plus everything at or above
the global counter; every id already in use is below `lo` or in an earlier block, hence not
`Reach`.  `SupOk` is `lo ≤ hi ≤ blk ∧ 2 ≤ bsz`, true of the real `sin` record (which carries
`Supply.block`) and false only of `Sup.ofSeed`, which the file already documents.  I did not find
this proved from `buildQueue` anywhere and it is not: `tnOk_of_buildQueue` takes it.  That is the
right place for it — `Cut.ResApp.fresh` carries the same premise for the shipped `resolution`
mint — but it is worth being plain that "the carriers are fresh" is CONDITIONAL freshness:
`carriers_notMem` derives each carrier's freshness FROM `TnOk.fresh`, it does not derive
`TnOk.fresh`.  The report's "proved from the `Supply` itself, not assumed" is about the former
and reads a little stronger than the theorem (J-6).

### 1(c) `sysQ` IS the S2 chain's reading

CONFIRMED.  `sysQ q := (q.elems.map LPart.toConstraint).toFinset`, and
`sys_initState_eq : sys (initState q su tr fl ns site z) = (q.elems.map LPart.toConstraint).toFinset`
is UNCHANGED by this stage (`git show HEAD:` and the working copy are identical) — so `sysQ q` is
`sys` at the initial state definitionally, which is why `solve_accepted_faithful_input` can write
`have hinit : sys (initState q su1 …) = sysQ q := sys_initState_eq` with no rewriting.  The S2
chain's LIVE input is one step larger, `((q.elems ++ envFacts).map toConstraint).toFinset`, and
`sys_subset_live` is the step between them; that is where `J-1` lives.

### 1(d) The `nodup` side condition — the Scala's `Set` against the Lean's `List.Nodup`

The condition is real and correctly identified.  `SSet.eqv s t := s.size == t.size && s.subsetOf t`
(`SSet.lean:207-210`) is equality of the underlying sets **only** on duplicate-free lists
(`⟨[a,a]⟩.eqv ⟨[a,b]⟩ = true`), and the fold that builds `disOf` keeps a REPRESENTATIVE, so
`TopFam.sub` genuinely needs it.  I confirmed by reading the proof that `hnd` is used in exactly
one place — `hdisNd`, consumed only in the `sub` branch — which is what the report says.

**Does the Scala guarantee it?**  Yes, and the model already carries the boundary explicitly, so
S4c adds no new obligation:

* the Scala's family selector is `Constraints.scala:2230-2260`; `dis = fam.map(_._2.concr).distinct`
  over `Set[Name]`, whose `==` IS set equality and whose `hashCode` is order-independent (unlike
  S3's `NormalPart`, so `List.distinct` is correct here).  The incomparability guard
  `dis.exists(c => dis.exists(d => c != d && c.subsetOf(d)))` is the exact negation of the Lean's
  `dis.all (fun c => dis.all (fun d => c.eqv d || !(c.subsetOf d)))`;
* in the model, `ITerm.InPool L (.concRho fs) := fs.Nodup ∧ ∀ x ∈ fs.elems, x ∈ L`
  (`Wf.lean:1122-1126`), and `buildQueue_qok` propagates it; the `json:` seed path builds every
  concrete row through `SSet.ofList` (`Seed.lean:80`), which cannot produce a duplicate;
* the one place a non-`Nodup` `SSet` can be constructed is the TRACE parser,
  `Replay.lean:156` (`.concRho ⟨c == 'C', ls.filterMap id⟩`), and `Wf.lean:1343` already says so
  in as many words ("the one thing the parser does NOT establish is that a `concRho` payload is
  duplicate-free … true of every trace the compiler prints").

So: no input where they diverge that is not already the documented `hsets` boundary.  The 3.2M-segment
differential is consistent with that reading and I did not try to beat it.

### 1(e) Non-vacuity

`exQ` is genuine: `exQ_fires` (kernel `decide`) says the selector returns exactly one family at
`v = 1` with three reads and `|F| = 3`; `exSu = ⟨100,200,300,1024,0⟩` satisfies `SupOk`
(`100 ≤ 200 ≤ 300`, `2 ≤ 1024`) and every id of `exQ` is `≤ 4`, so `TnOk.fresh` is real, not
degenerate.  I did better than take the witness on trust and built my own, from `buildQueue`
rather than by hand (§3).

**Can any hypothesis of a main theorem be stated that no real queue satisfies?**  I tried the
three plausible candidates and all three fail to be vacuous:

* `htn : topNormalise fl.topNormalise q0 su0' = (q, su1, rc)` — an equation about a TOTAL
  function with `q`, `su1`, `rc` implicit, so `rfl` supplies it at either flag setting
  (`F_nonvac.lean`).  Never vacuous.
* `TnOk` at ON together with a family that FIRES — discharged in the kernel on seven distinct
  adversarial shapes (§3).
* `hw : Wf (initState q su1 …)` where `q` is the REWRITTEN queue — the one hypothesis of
  `solve_accepted_faithful_input` that is about the rewrite's OUTPUT and is nowhere proved by
  this stage.  I discharged it in the kernel on the ON-rewritten H12 queue (`F_nonvac.lean`,
  `wfON`, standard axioms only), and checked the same solve really runs: `SOLVED` at both flag
  settings, with two `tnorm` records and carriers 7 and 8.  Not vacuous.

---

## 2. No weakening of the S2 chain

**Mechanically checked, not read.**  `B_old_from_new.lean` states all SIX pre-S4c theorems
VERBATIM (copied out of `git show HEAD:…`) and proves each from its post-S4c replacement.  It
elaborates with **zero errors**.  The move in every case is the same one line:

```lean
solveSeed_rejects_of_refuted hq (by rw [htn]; exact topNormalise_off q su1) hearly hflag href
```

and the same for the other five.  So nothing was weakened; the new statements are strictly more
general.

| # | theorem | old premise | new premise | old recovered |
|---|---|---|---|---|
| 1 | `solveSeed_rejects_of_refuted` | `htn : fl.topNormalise = false`, `hq` about `q` | `hq` about `q0`, `htn` = the rewrite's equation | **as a shipped `_off` corollary, TYPE-IDENTICAL** |
| 2 | `solve_noFalseAccept` | same | same | derivable (checked) |
| 3 | `solve_accepted_faithful` | same | same | derivable (checked) |
| 4 | `solveSeedP_rejects_of_refuted` | same | same | **`_off`, TYPE-IDENTICAL** |
| 5 | `solveP_noFalseAccept` | same | same | derivable (checked) |
| 6 | `solveP_accepted_faithful` | same | same | derivable (checked) |

"TYPE-IDENTICAL" is a theorem, not an eyeball: my file closes
`example : @J_old_solveSeed_rejects_of_refuted = @solveSeed_rejects_of_refuted_off := rfl`
and the policy twin, which requires the two Pi-types to be definitionally equal.

**Is `htn` ever vacuous?**  No — see §1(e).  It is an equation about a total function with the
right-hand side's three components implicit; `rfl` instantiates it, and at OFF `topNormalise_off`
(itself `rfl`) forces `q = q0`, `su1 = su0'`, `rc = []`, which is why the other four are literally
the same proposition as before.

**Do the four `_input` theorems say what §2 claims?**  Yes, and they are stronger than the
report's one-line summary:

* `solve_noFalseAccept_input` concludes `SSat (((q0.elems ++ envFacts).map toConstraint).toFinset)`
  — `buildQueue`'s OWN queue plus the environment facts.  The proof does not merely re-derive
  satisfiability: it carries the SAME assignment `rho` back through `tn_models` and splits the
  append, so the model of the live input is a model of the input.  Faithful.
* `solve_accepted_faithful_input` concludes `NoLoss (sysQ q0) (sys s')` together with the models
  and the `SSat` iff, composed by `NoLoss.trans` on `tn_noLoss` and `tn_ssat_iff` exactly as
  claimed.  The `sys (initState q su1 …) = sysQ q` step is `sys_initState_eq`, unchanged.
* Both policy twins are the same statements with `runP`/`RunSupOkP`.

**Are the three no-verdict/budget escapes still stated where they were?**  Yes.  `hbud : ∀ l w,
(labelDecide … ).1 ≠ .noVerdict l w` is present, unchanged, on `solve_noFalseAccept`,
`solveP_noFalseAccept` and both `_input` versions, and `hflag : fl.rowSoundDecide = true` and
`hearly` likewise.  Nothing was moved, dropped or softened.  A grep of the whole library finds
`fl.topNormalise = false` ONLY in the two `_off` corollaries — no residual flag premise anywhere.

---

## 3. Adversarial

I ran the S4B seed shapes through the model's own `buildQueue` and then against the theorems'
hypotheses.  `C_adv.lean` evaluates all **29** seeds (`H1`…`H22` plus `H3U`/`H4U`/`H5U`/`H7S`/
`H8a`/`H8b`/`H8c`/`H12U`); `D_kernel.lean` discharges `TnOk` IN THE KERNEL and applies
`topNormalise_sysQ` and `topNormalise_ssat_iff` on seven of them.

**All 29 satisfy every decidable field of `TnOk`** — concrete and abstract parts `Nodup`, no
self-unification in the queue, and every id strictly below `su.lo` (which gives `SupFresh` via
`supFresh_of_lt`, my own helper).  There is no shape here on which `tnOk_of_buildQueue` cannot be
applied.  The selector's behaviour:

| shape | fires? | what it exercises | `TnOk` in the kernel |
|---|---|---|---|
| `H6` `v<-(x,{a}) v<-(x,{b}) v<-(x,{c})` | **yes**, 1 family, k=3 | THREE reads sharing ONE remainder → three re-expressions at the same lhs | ✔ `tnH6` |
| `H9` four reads, three distinct parts | **yes**, fam=4, `|dis|`=3 | `card` counts DISTINCT parts; two re-expressions coincide | ✔ `tnH9` |
| `H17` fourth read reuses the first's remainder | **yes**, fam=4, `|F|`=4 | two different constraints at one remainder | ✔ `tnH17` |
| `H5` two families SHARING remainder `x1` | **yes**, 2 families | `x1` gains a re-expression from each, with DIFFERENT carriers (7 and 8) | ✔ `tnH5` |
| `H12` second family's lhs is the first's remainder | **yes**, 2 families | one pass over the ORIGINAL families: `v` gets both the first family's re-expression and its own top partition | ✔ `tnH12` |
| `H7` concrete row ONE LINK away | **yes** | the `noConc` guard is syntactic and does not see through `v <- (w)`, `w <- ((\|a,b\|))`; the rewrite is still equisatisfiable | ✔ `tnH7` |
| `H21` self-read `v<-(v,{a})` + three reads | **yes**, k=3 | the self-read is EXCLUDED from the family (FR-3) and SURVIVES in `q'`, so the loop keeps its syntactic death | ✔ `tnH21` |
| `H8`, `H8a`, `H8b` self-read below the trigger | no | k < 3 after excluding the self-read | — |
| `H22` two self-reads of three | no | k = 1 | — |
| `H10` one COMPARABLE part | no | incomparability guard | — |
| `H8c` self-read + three reads | **yes** | same as `H21` at a different order | — |

`eqvH12` and `eqvH21` `#print axioms` to the standard three.  No `sorry`.

Two structural things I checked because they are where a rewrite of this shape usually goes
wrong, and both are handled rather than assumed:

* **an added constraint that is also a deleted read** would break `topNormalise_sysQ`'s
  union-then-difference form.  `adds_notMem_reads` rules it out from freshness, and it is the one
  place `TnOk.fresh` is load-bearing for the STATEMENT rather than for the forward direction.
* **`keepOf` deletes more than the family's members** when some other partition is `eqv`-equal to
  a deleted read.  It denotes the same constraint, so it is in `tnReads`, and `sysQ_keepOf`
  proves the equality in both directions through `eqv_iff_toC`.  Honest.

What the adversarial pass does NOT reach: `topNormalise_sysQ` and `topNormalise_ssat_iff` are
about `Finset`s, so no seed can exercise the QUEUE ORDER the rewrite produces (J-4).

---

## 4. Gates, re-run

Every gate reproduced.  Toolchain `$HOME/.elan/bin` + `$HOME/.local/ermine-toolchain`,
`LEAN_NUM_THREADS=2`, one JVM.

| gate | report | mine |
|---|---|---|
| `lake build` (default target) | GREEN, 868 jobs | **GREEN, 868 jobs** (replayed, 1.0 s) |
| `lake env lean Audit.lean` | 4,282 theorems, 0 non-standard | **4,282 theorems, 0 non-standard** |
| `#print axioms`, new/changed | 123 declarations; 112/6/5; no `sorryAx`, no `nativeDecide` | **REGENERATED INDEPENDENTLY over 225 declarations** — every non-internal theorem AND def of `Rowpartition.Loop.TopNormalise` (158 audited-style theorems + 55 defs + private) plus the 12 new/changed in `NoFalseAccept`/`PolicyStep`: **0 non-standard uses**, 176 standard-three / 7 `[propext, Quot.sound]` / 11 `[propext]` / 31 axiom-free; no `sorryAx`, no `nativeDecide`, no `ofReduceBool`.  The implementer's own 123-row file re-counts to exactly 112/6/5 as claimed and every one of its 123 names is a subset of my 225 |
| `TestLoopTrace` | 720/720, hashdiff 0, eqdiff 0, rejected 36, fuel 0, 9,218 ms; controls 46/58; `Passed: Total 3` | **720/720, 720 agree, skipped 0, hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0, 9,147 ms; controls 46/720 and 58/720; `Passed: Total 3, Failed 0, Errors 0`** |
| no executable Lean changed | claimed | **CONFIRMED by computation**: `Main.lean`'s transitive import closure is 72 modules and contains none of `TopNormalise`, `NoFalseAccept`, `PolicyStep`, `Rowpartition` |
| `looptrace` not rebuilt | mtime 15:12 < edits 16:43 | **CONFIRMED**: binary `2026-09-07 15:12:54`; earliest S4c edit `Rowpartition.lean` `16:43:52`, latest `17:06:23` |
| `.ei` | none created | **CONFIRMED**: `find . -name '*.ei' -newermt '2026-09-07 15:00'` empty; 143 pre-existing |
| commits | none | **CONFIRMED**; `git status` is the six modified files plus the two new ones (plus this review) |

One number I did not re-derive: "(4,119 before S4c)".  Reproducing it needs a rebuild at `HEAD`,
which the disk budget does not justify; arithmetically `4,282 − 158 − 6 = 4,118`, one off, which
changes nothing.  The "111 theorems" of the report/plan/state file is RIGHT: the source has 109
`^theorem` lines plus 2 `@[simp] theorem` lines (the review brief's "109" is the low count).

---

## 5. Prose, the plan row, the state file, and the adoption question

**The report is accurate, statement by statement.**  I checked every claim in §1 and §2 against
the Lean and found two prose slips (`J-2`, `J-6`) and one place where a theorem reads stronger
in the prose than it is (`J-3`).  Everything load-bearing is right, including the parts that are
hard on the work: `Conserv` against the input alone really is false for any mint (`Conserv G G' :=
∀ c ∈ G', SEntails G c`, `Strict.lean:52`, and a fresh carrier is unconstrained), the mint half
really has no `LoopStrict` constructor, and the Scala↔model link really is the differential and
not a proof.  §3's three residues are the right three — and are missing a fourth (`J-1`).

**The plan row is right.**  111 theorems, 868 jobs, 4,282/0, 123 declarations, 720/720, "no
executable Lean changed", "ON differential NOT REQUIRED" — all reproduced above.  Its closing
sentence, "the two Lean prerequisites `S4B-REVIEW.md` §5.2 listed are now MET", is correct.

**The state file's "AT ADOPTION" block is correct**, and correctly scoped: it claims only the two
Lean items and says explicitly that items 1 and 2 (move `proj01_seven_reads.e`, clear the `.ei`
cache) remain the user's.  I checked the other two of `S4B-REVIEW.md` §5.2's four conditions
independently: H-12 (the four unpatched replay call sites) was closed by S4's FR-2, and H-2 (the
self-read) by FR-3 — the exclusion is in BOTH implementations (`Constraints.scala:2245-2248`
`x != v`, and `Loop/Json.lean:194` `x != p.lhs`), and my `H21`/`H8c` runs confirm the self-read
survives the rewrite so the loop keeps its syntactic death.  So §5.2's list is empty.

### Should `-Dermine.topNormalise` be flipped ON by default now?

**Yes — in its own commit, with one theorem added first.**  The case is now as strong as this
programme has ever made for a default:

* the rule is `resolution`'s own k-ary generalisation and the ladder becomes one pre-loop draw at
  every N (ten reads in 0.04 s where seven did not compile);
* the equivalence is proved in both directions **about the executable code**, not about an
  abstract rewrite (`topNormalise_ssat_iff`, with `topFamilies_eq`/`topNormalise_eq` `rfl`);
* the layer that catches the H-2 class — S2's no-false-acceptance chain — is now proved for the ON
  configuration and, in `solve_noFalseAccept_input` / `solve_accepted_faithful_input`, ABOUT THE
  INPUT the compiler was handed rather than about the rewritten queue;
* every previously adopted default in this programme shipped a correspondence lemma, and this one
  now has one of the same shape.

**What must precede the flip**

1. **`J-1`, and it is the only new one.**  With `rowSoundDecide` shipped ON, layer (iii) at
   `topNormalise = true` decides `q'.elems ++ envFacts`, so a REJECTION is a refutation of the
   REWRITTEN live input.  Carrying it back to the input needs `SSat (q0 ∪ E) → SSat (q' ∪ E)`,
   and `topNormalise_ssat_fwd` gives that only for `sysQ q0`: `TnOk.fresh` is `SupFresh su (sysQ q)`
   and says nothing about `envFacts`, while `ssat_addAll` builds its model by UPDATING `rho` at
   the carriers.  One extra hypothesis closes it (`E_reject.lean` sketches the exact shape).  The
   corpus has never produced such a rejection — `corpus-run.sh --batch` moved exactly one module
   and in the ACCEPTING direction — but S4B §5.2 item 2's rule applies: a theorem must say
   explicitly whether it covers the configuration being shipped.
2. **Say, in the adoption note, that the mint half is still not a `LoopStrict` step.**
   `topNormalise_loopStrict` is the DROP; the additive mint has no constructor, so the rewrite is
   two shapes and not a `LoopStrictRun`.  Not a blocker — it runs once, before the loop, and draws
   `k` ids — but it is the one place the relation does not cover the pipeline.
3. **Say that the Scala↔model link is the differential, not a proof.**  S4c proves things about
   `Loop/Json.lean`'s `topNormalise`; that this IS `Constraints.topNormalise` rests on the L2
   corpus differential (3.2M segments, 15 `tnorm` records byte-identical) and on
   `TestLoopTrace` 720/720.  Standing for every stage, and the correspondence lemma is
   ORDER-BLIND (`J-4`), so the differential is the only thing covering the rewritten queue's
   ORDER — which is what fixes the loop's dequeue order and every id minted after it.
4. **The two adoption obligations, in the same commit.**  Move
   `core/examples/Present/shouldfail/proj01_seven_reads.e` out of `shouldfail/` (or give it more
   reads); and carry the "clear the `.ei` cache once" instruction, because nothing keys a
   published interface by `GenRules.toString` and the flag demonstrably changes published bytes.

**What the flip changes for a user.**  Programs that did not compile now compile (the projection
cliff at N ≥ 7).  And, per `S4B-REVIEW.md` H-3: wherever the rule fires on an UNSATISFIABLE
program, the refutation's TEXT moves — 12 of 29 seeds report a different CLAUSE of the same
refutation and five a different FIELD.  The POSITION is preserved, because `rowUnsat` searches
`cs`, which is not rewritten.  No corpus `shouldfail` module has a `k ≥ 3` family, so the corpus
does not show this; a user's will.  That belongs in the release note, not in a tracker file.

---

## 6. Findings

### `J-1` — CONFIRMED, medium.  No-false-REJECTION at ON is not covered, and the residue list does not name it

`Flags.rowSoundDecide` is DEFAULT TRUE (`State.lean:385`), so layer (iii) ships ON.  At
`topNormalise = true` it decides `q.elems ++ envFacts` where `q` is the REWRITTEN queue, and
`labelDecide_refuted_unsat` (`NoFalseAccept.lean:742`) therefore refutes
`((q'.elems ++ envFacts).map toConstraint).toFinset`.  Nothing in S4c carries that back to
`((q0.elems ++ envFacts).map toConstraint).toFinset`.

What is available (both elaborate, `E_reject.lean`):

* `refuted_of_rewritten` — the refutation of the rewritten live input;
* `unsat_input_queue_only : ¬ SSat (sysQ (topNormalise on q0 su).1) → ¬ SSat (sysQ q0)`, from
  `tn_ssat_iff`.  **The QUEUE-only half carries back.**

What is not: the same with `envFacts`.  `topNormalise_ssat_fwd` proves `SSat (sysQ q0) → SSat (sysQ q')`
by `ssat_addAll`, which extends the model with `setVar rho c (rho v \ F)` at each carrier.  A
carrier that occurred in `envFacts` would change `rho` there and the extension need not model
`E` any more.  `TnOk.fresh` is `SupFresh su (sysQ q)`; `envFacts` is a separate `List LPart`
argument to `solveSeed` and is nowhere constrained.  Concretely, `envFacts = [c <- ((|d|))]` for
the carrier `c` the rewrite is about to draw makes `q0 ∪ E` satisfiable and `q' ∪ E` not.

Not a soundness bug in the shipped OFF configuration, not in the brief's list of six, and not
observed on the corpus (which has no `shouldfail` module with a `k ≥ 3` family — S4B H-3).  But
it IS the direction the flip newly exercises for a check that ships ON, and the report's §3
("Nothing that was asked for, and three things worth writing down") does not name it.

**Fix, ≤ 30 lines and no new machinery:** add `freshE : SupFresh su ((envFacts.map
LPart.toConstraint).toFinset)` as a hypothesis (or widen `TnOk.fresh` to the live input) and state
`solve_rejects_input` / `solveP_rejects_input`.  It should land with the flip, in §5's list.

### `J-2` — CONFIRMED, low (prose).  `TopFam` has THIRTEEN fields, the report says fourteen

`S4C-CORRESPONDENCE.md` §1(a): "whose fourteen fields are exactly the brief's list".  The
structure has 13: `eqFam`, `eqF`, `mem`, `lhs`, `read`, `concNe`, `ne`, `noConc`, `card`,
`distinct`, `incomp`, `union`, `sub`.  The table below it is right (12 rows, the first covering
two fields).

### `J-3` — CONFIRMED, low (prose reads stronger than the theorem).  `conserv` and `loopStrict` are `of_subset`

`topNormalise_conserv := Conserv.of_subset (by rw [topNormalise_sysQ H]; exact Finset.sdiff_subset)`
and `topNormalise_loopStrict`'s subset obligation is the same `Finset.sdiff_subset`.  Both say:
`sysQ q'` is a subset of `sysQ q ∪ tnAdds`, where `tnAdds` is DEFINED as the constraints this
rewrite mints.  "Beyond the mint the rewrite invents nothing" is a fair reading, but the content
is subsethood, not an independent conservativity argument; the substance is in
`topNormalise_sysQ`, which the report also states.  The report's own "the MINT half is still the
additive step `LoopStrict` has no constructor for" is the honest half of the same sentence.

### `J-4` — CONFIRMED, low (scope).  The correspondence is ORDER-BLIND

`sysQ` is a `Finset`, so `topNormalise_sysQ` and `topNormalise_ssat_iff` say nothing about the
ORDER of `PQueue.ofList (keep ++ added)` — which is what fixes the loop's dequeue priority, every
id minted downstream, and the `tnorm` records' contents.  The Scala builds `F` as
`dis.reduce(_ ++ _)` and the model as `dis.foldl concat SSet.empty`; these agree as sets and the
model's `SSet` exists precisely to track that they may not agree as ITERATION ORDERS.  Only the
L2 differential covers that.  The report's §3 residue 3 makes the Scala↔model point but not this
one; it belongs beside it.

### `J-5` — CONFIRMED, low.  `sysQ`, `TnOk` and the whole correspondence live in `Rowpartition.Loop`, one import away from the executable closure

`NoFalseAccept.lean` now imports `Loop.TopNormalise`, which imports `Loop.Solve`.  Nothing in
`Main.lean`'s closure imports it today (I checked), so the "no rebuild" claim holds — but the new
module defines `sysQ`, `IsRead`, `famOf`, `disOf`, `unionOf`, `candOf`, `keepOf`, `tnStep`,
`Plan`, `resBlock`, `topBlock` in the SAME namespace as the executable definitions.  A future
`Main.lean` change that pulls in a proof module would silently enlarge the binary's closure and
break the "the binary was not rebuilt" gate.  Nothing to do now; worth knowing.

### `J-6` — CONFIRMED, low (prose).  "proved from the `Supply` itself, not assumed" is about the carriers, not about freshness

`carriers_notMem` derives each carrier's freshness FROM `TnOk.fresh` via `fresh_notMem` and
`SupFresh.step`; it does not derive `TnOk.fresh`.  The report's §3 residue 1 states the
assumption plainly, so the two paragraphs together are accurate — but §1(b)'s phrasing on its own
overstates.

### `J-7` — CONFIRMED, low (prose).  `tnOk_of_buildQueue` also takes `hcs : ∀ c ∈ cs, CsItem.InPool L c`

The report's closing paragraph of §1 says "`qok` is `Wf.buildQueue_qok`", omitting that
`buildQueue_qok` needs the input condition — which carries exactly the `concRho` `Nodup`
requirement §1(a) spends a paragraph on.  The theorem statement shows it; the prose should too.

### `J-8` — observation, not a finding.  "(4,119 before S4c)" not re-derived

`4,282 − 158 − 6 = 4,118`.  Re-deriving the pre-S4c count needs a rebuild at `HEAD`.  Immaterial;
the 4,282 and the 0 are confirmed.

---

## 7. Every number of mine that differs from `S4C-CORRESPONDENCE.md`

| | report | mine | why |
|---|---|---|---|
| `#print axioms` scope | 123 declarations | **225** (whole module incl. defs and private, plus the 12) | broader sweep; same conclusion, 0 non-standard |
| `TestLoopTrace` wall | 9,218 ms | **9,147 ms** | machine noise; identical summary line |
| `TopFam` fields | "fourteen" | **thirteen** | J-2 |
| Audit before S4c | 4,119 | **not re-derived** (arithmetic gives 4,118) | J-8 |

Everything else — 868, 4,282/0, 112/6/5, 111 theorems, 720/720, 46/58, 143 `.ei`, the 15:12
binary mtime — reproduces exactly.
