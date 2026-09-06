# L5 review — `LoopStrict`, the loop-level mint bound, and the compiler panic

2026-09-04. Reviewer agent, one round. Brief `tracker/loopmodel/briefs/brief-L5.md` + the protocol
`briefs/brief-review.md`. Report under review: `tracker/loopmodel/L5-TERMINATION.md`.
In scope: `tracker/lean/Rowpartition/Loop/{Strict,StrictStep,StrictBound}.lean`, the three import
lines in `Rowpartition.lean`, the plan's L5 row, the additive `tracker/lean/README.md` block, and
the report. Everything else uncommitted (staged L2; L3's `Loop/{Wf,Order,Refine,RefineConcrete,
RefineLearn}.lean`; L4's test/trace/tool files) is pre-existing and was not reviewed.

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5/`. Nothing else was edited; no commits,
no Lean edits, no Scala edits, no sbt (`ps` showed none running). Two `.ei` files my `bin/ermine`
replays produced landed in my scratch only (not under `core/examples`) and were deleted.

**Verdict: FIX-THEN-ADVANCE** — nothing here is unsound, the compiler bug is real and correctly
reported (and I found its root cause, which is *not* where the report puts it), the Lean builds and
audits exactly as claimed, and the numbers all reproduce. But two of the stage's headline claims are
false as stated, and both are machine-checkable:

* **F1** `LoopStrict`'s three deletion constructors are not "the precise set transformation the
  Scala performs"; they are unconstrained rewrites with a `NoLoss` + `SSat` side condition. From a
  fixed satisfiable system `LoopStrict` reaches systems of **unbounded vocabulary** (I proved it in
  Lean). So the structural blocker the stage exists to remove — "no measure is monotone along its
  runs" — is **not removed**, and no library mint bound transports along `LoopStrictRun` either.
* **F2** "`LoopRel.weaken` appears nowhere in this proof or in anything it depends on"
  (`StrictStep.lean:1077`) and "`step_refines_strict`, `step_noLoss`, and every lemma they use are
  free of it" (report §C1.3) are **false**: I computed the transitive constant closure and every one
  of the strict-refinement theorems reaches `LoopRel.weaken`, through `Refine.step_sat =
  (step_refines _ _ _).sat`. The stage's own acceptance criterion is met only textually.

Neither is a soundness defect. Both need the report and the plan row corrected, and F1 needs the
constructors re-stated before another round of C3 can be worth anything.

---

## 1. Rebuild and re-audit — everything reproduces

| step | command | result |
|---|---|---|
| build | `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH && lake build Rowpartition` | `Build completed successfully (841 jobs)` — **matches** (838 before) |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3003; declarations using a non-standard axiom: 0` — **matches** |
| grep | `sorry`/`axiom`/`partial`/`native_decide`/`implemented_by`/`unsafe`/`opaque`/`Classical`/`admit`/`#exit` over the three modules | **0 hits in all three** |
| `#print axioms` | I re-ran the implementer's `tmp/L5/Axioms.lean` (33 headlines) myself | 32 × `[propext, Classical.choice, Quot.sound]`, 1 × `[propext]`; **no non-standard axiom** |
| line counts | `wc -l` | 225 / 1268 / 230 = **1,723** — matches |
| import lines | `git diff Rowpartition.lean` | +8 lines; **five of them are L3's** (`Wf`, `Refine`, `RefineConcrete`, `RefineLearn`, `Order`) and three L5's. The report says "three import lines"; the diff is +8 because L3's were never staged. Not a defect, but the diff is not what the report describes. |
| README | `git diff --numstat` | **+146 / −0**, purely additive (the report says +144/−0; harmless) |

Build warnings only: three `linter.style.header` complaints on `StrictBound.lean` (author line ends
with a period, second copyright line, module docstring after a section comment) and one long line in
`Rowpartition.lean`. Cosmetic.

## 2. F1 (CONFIRMED, machine-checked) — `NoLoss` licenses arbitrary *addition*, so `LoopStrict` still has no monotone measure

`NoLoss G G' := ∀ c ∈ G, SEntails G' c` (`Strict.lean:41`) unfolds to `Mod(G') ⊆ Mod(G)`.

For `drop : G' ⊆ G → NoLoss G G' → LoopStrict G G'` that is exactly right and exactly tight: with
`G' ⊆ G` we also have `Mod(G) ⊆ Mod(G')`, so `drop` is *model-equivalence-preserving* deletion. A
constraint whose only witness is itself cannot be dropped. **`drop` is a good constructor** and the
reviewer's question ("can `NoLoss` license deleting a constraint whose only witness is itself?") is
answered NO for it.

The other three are a different animal. `emptyRemove`, `instRemove`, `concRemove` place **no
constraint at all** relating `G'` to `G` beyond (i) one membership fact in `G'`, (ii)
`SSat G → SSat G'`, (iii) `NoLoss G G'`. `G'` is otherwise arbitrary — in particular it may be
*larger* and *stronger*. Machine-checked in
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L5/Growth.lean` (compiles clean against the tree):

```lean
def Gg (n : Nat) : System := (Finset.range (n+1)).image (fun k => mk k ∅ (∅ : Row))

theorem strict_grows (n : Nat) : LoopStrict (Gg n) (Gg (n+1)) :=
  LoopStrict.emptyRemove (v := 0) (mem_Gg (Nat.zero_le _))
    (fun _ => sat_Gg (n+1)) (NoLoss.of_subset (Gg_mono n))

/-- **No mint bound transports along `LoopStrictRun`:** from the FIXED satisfiable system
`Gg 0 = {0 <- ()}` the relation reaches systems of unbounded vocabulary. -/
theorem no_mint_bound_along_strict (n : Nat) :
    ∃ G', LoopStrictRun (Gg 0) G' ∧ SSat (Gg 0) ∧ n ≤ (allVars G').card
```

and the same with `instRemove` (`strict_grows_inst`), so it is not an artefact of one constructor.

Consequences, ranked:

1. **`Strict.lean`'s own doc comment is wrong.** Lines 21–23 say `no_loss` is "the reason
   `LoopStrict` is the relation a measure can be monotone along". `hmeas` is not monotone along
   `LoopStrictRun`; neither is `gmeas`; neither is `(allVars ·).card`. The plan's L5 rationale
   ("`LoopRel` has a `weaken` constructor admitting arbitrary deletion, so no measure is monotone
   along its runs and none of the library's mint bounds transports") applies verbatim to
   `LoopStrict`, with "deletion" replaced by "addition".
2. **The brief's C1 was not met.** It asked for the deletions "each stated as the precise set
   transformation the Scala performs (the `empty` dequeue = `makeEmptyE` composed with the `++!`
   `CommonPartition` redirect; the `concrete` dequeue = `concretizeSrs` composed with `keepDefs` and
   `can`; …)". `emptyRemove` is not `makeEmptyE`; it is "some `G'` containing `v <- ()`".
3. **`step_refines_strict` conveys exactly three facts and nothing else.** I checked where each
   constructor is actually applied: the nine RULE constructors appear **only inside
   `LoopStrict.of_rel`** (`Strict.lean:178–187`) and never justify a loop step; the whole `step`
   refinement is `emptyRemove` once (`StrictStep.lean:702`), `instRemove` twice (`:989`, `:1060`),
   `drop` once (`:1040`). So `step_refines_strict` = "`mk v … ∈ sys s'` ∧ `SSat (sys s) → SSat
   (sys s')` ∧ `NoLoss (sys s) (sys s')`", which is `step_noLoss` + `step_sat` + a membership
   lemma. That is a real result — `makeEmpty_noLoss`, `instantiate_noLoss`, `trim_noLoss`,
   `concatP_noLoss`, `sat_of_erase`, `sat_of_replace` are the substance and they are good — but it
   is not a refinement in the sense C3 needs.

The report does not say any of this. §C1.5's "what C1 does NOT do" table lists row 6 and the `learn`
branch as the gaps; the gap that matters more is that the four constructors it *did* land are too
loose to carry a measure.

**Fix**: restate the three constructors as the library's operators applied to `G`, e.g.
`emptyRemove {G v} : mk v ∅ ∅ ∈ G → LoopStrict G (makeEmptyE v G)` (and the concrete/alias twins),
proving the loop's actual `sys s'` equal to — or bracketed by `drop`/additive steps around — that
operator's output. That is what makes `KeyedEmpty.mintsBoundedOnSat_emptyPersisting` and
`KeyedRow.carried_concretizeSrs` applicable, which is the entire point.

## 3. F2 (CONFIRMED, machine-checked) — the weaken-free claim is false

Report §C1.3 and `StrictStep.lean:1077` both claim the strict refinement is free of
`LoopRel.weaken`, evidenced by a `grep` **over the three new modules only**. The dependency is one
file away: `step_strict_empty` (`:702`) discharges `emptyRemove`'s satisfiability premise with
`step_sat hw hlink h hs`, and `Refine.lean:1262` reads

```lean
theorem step_sat {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (step_refines hw hb h).sat
```

— `step_refines` being the L3 theorem whose four `weaken` uses this stage exists to remove. I
computed the transitive constant closure with a Lean metaprogram
(`tmp/review-L5/Deps.lean`):

```
step_refines_strict:  LoopRel.weaken=true   step_refines=true
step_noLoss:          LoopRel.weaken=true   step_refines=true
step_strict_empty:    LoopRel.weaken=true   step_refines=true
step_strict_unify:    LoopRel.weaken=true   step_refines=true
step_strict_common:   LoopRel.weaken=true   step_refines=true
step_noLoss_strict:   LoopRel.weaken=true   step_refines=true
step_learn_sys_mono:  LoopRel.weaken=false  step_refines=false
```

Only `step_learn_sys_mono` is genuinely weaken-free. This is **not** a soundness problem —
`LoopRel.weaken` is sound and `step_sat` is a true theorem — but the brief's C1 acceptance
("`LoopRel.weaken` is used nowhere in the `step` refinement") and the plan's L5 row ("`LoopRel.weaken`
is used in no refinement") are met only in the sense "not textually in my three files".

**Fix**: either prove `step_sat` for the three branches directly (from `makeEmpty_noLoss` etc., which
already give `NoLoss`, plus a model-transfer argument), or restate the claim honestly as "the
`LoopStrict` derivation uses no `weaken` step; the `SSat` side conditions still borrow L3's
`step_sat`, which does."

## 4. The verbatim statements, checked against the modules

Every Lean block quoted in `L5-TERMINATION.md` I diffed against its module. **All are verbatim**
(constructor lines, signatures, doc-comment elisions as declared). `LoopStrict`'s nine rule
constructors are byte-for-byte `LoopRel`'s (`Refine.lean:348–379` vs `Strict.lean:62–92`) — checked.
Findings from the side-by-side reading:

* **`LinkOrEmptyStep` (report accurate).** Defined at `Refine.lean:1137` (pre-existing, L3), it is
  `findRHS.isSome ∨ rhs.isEmpty ∨ rhs.single?.isSome` — i.e. `common`, `empty`, `unify`. `concrete`
  and `learn` are excluded. The report says so plainly and does not claim otherwise;
  `step_refines_strict` is the analogue of L3's `step_refines`, **not** of `step_refines_all`. The
  plan's acceptance clause "every `step` refines it under the same hypotheses as `step_refines_all`"
  therefore **FAILS**, and the report says it fails.
* **"rows 2, 3, 4, 5 discharged, row 7 deletes nothing, row 6 open" — accurate**, given F1's caveat
  about what "discharged" buys. `step_learn_sys_mono : sys s ⊆ sys s'` (`StrictStep.lean:1215`) is a
  real, weaken-free theorem and row 7 is genuinely not a deletion.
* **`step_su`, `step_envNodup`, `env_len_le_allVars` (`StrictBound.lean`) — all real, all about the
  real `step`, no hidden hypotheses.** `step_su` is a disjunction (`s'.su = s.su ∨ IsLearnStep s`),
  which is the right statement. `EnvNodup` is proved preserved on all five branches.
* **`cancellation_bare` — faithful and a real obstacle, not a `sys` artefact.** I checked
  `Constraints.scala:1667–1687`: with `rhs1 = RHSConcr(fs)` and `rhs2 = RHSConcr(cs)`, `xs = ys = ∅`
  so both branches' `size == 1` tests fail and `cancellation` returns `Set()`. `keepDefs`' `defs`
  filter is `abs.size >= 2` (`:1650`), so a bare concrete definition is not kept.
  `ensureSuperset` (`:1608`) permits `C ⊆ fs`. And `sys s'` retains only `mk v ∅ fs` from the
  environment, which does not entail `mk v ∅ C` for `C ⊊ fs` under any faithful notion of the
  system — so it is not an artefact of choosing `sys`. The report's conclusion (row 6's licence must
  become `SSat G → NoLoss G G'`, and `LoopStrict.no_loss` weakens with it) is correct.
* **§C1.5's `conc1` probe is misquoted.** The report says `v <- ((|C|))` with `C ⊊ fs` "makes
  `checkLabel` report *'the whole contains it but no part does'* … (`conc1` probe: `REJECTED … at
  field 'Repro.l101'`)". I re-ran the probes: `conc1` reports **"a part contains it but the whole
  does not"**; it is `conc3` that reports "the whole contains it but no part does". The substantive
  claim — labelCheck rejects the shape before any `step` runs — is CONFIRMED; only the quoted
  message is wrong. `conc2`'s singleton-cancellation claim is CONFIRMED verbatim (trace line
  `step … concrete Cancellation: ^free1 <- (,Repro.l101)`).
* **Constructor-liveness counts:** the report says `split` 2; I count 1 (`Strict.lean:179`). Every
  other count matches, including `concRemove` 0. Trivial.

## 5. C3 — the `qsys` argument

### 5a. The (B) table is prose; `qsys` carries exactly one theorem

`envEmptySys` / `qsys` exist (`StrictStep.lean:1162–1171`) and the **only** theorem about them is
`qsys_subset_sys`. The three (B) arguments (alias elimination, `makeEmpty`, `makeConcrete`) are
sketches and the report says so ("sketched (NOT proved — see C3.4)"). Fair.

The *new* half of §C3.1 — that `sys s` fails (B) at alias elimination because the retained `v <- (u)`
keeps `v` in `allVars` while every carrier for `v` has been rewritten to `u` — is a good observation
and I believe it (it is the `hmeas_increases` phenomenon transposed to the alias case). It is not
proved.

One entry of the table I would not grant without proof: **(B) at `makeEmpty` over `qsys`**.
`makeEmpty` rewrites surviving partitions as `Partition(u, rhs - v, inf)`, so a singleton link
`mk u {v} K` becomes `mk u ∅ K` — a `Resolved (qsys s) u K` witness is *destroyed*, not preserved.
`KeyedEmpty.mintsBoundedOnSat_emptyPersisting` may well absorb this (that is what it is for), but the
report presents it as "ok" in a table cell with no argument.

### 5b. The localisation is prose, and as stated it is both incomplete and imprecise (CONFIRMED)

The blockquote

> The residual mismatch is exactly this: a mint at a key equal to the parent's whole concrete row,
> taken while the environment holds at least one empty-row fact.

is not a theorem, and on the definitions it is not right either. With
`ConcCarried G v K := ∃ C, mk v ∅ C ∈ G ∧ ∃ z, mk z ∅ (C \ K) ∈ G` (`KeyedRow.lean:88`) and
`Resolved G v K := ∃ z, mk v {z} K ∈ G` (`ResGuard.lean:79`):

* `Resolved` genuinely cannot be witnessed by an empty fact (`vset (mk u ∅ ∅) = ∅ ≠ {z}`), so the
  report is right that the whole mismatch lives in `ConcCarried`. Good.
* An empty fact used as the **`z` witness** forces `C \ K = ∅`, i.e. **`C ⊆ K`, not `K = C`**. `K`
  ranges over all subsets of the label set in `uncarried`, so this is `2^{|L\C|}` keys per variable,
  not one. Machine-checked (`tmp/review-L5/Localise.lean`):
  `theorem conc_carried_superset : ConcCarried {mk 7 ∅ {1}, mk 3 ∅ ∅} 7 {1,2}`.
* An empty fact used as the **`mk v ∅ C` witness** — i.e. the *parent* is itself already empty —
  gives `C = ∅`, hence `C \ K = ∅` for **every** `K`, so `ConcCarried (qsys s) v K` holds at every
  key at once. This case is missing from the blockquote. Machine-checked:
  `theorem conc_carried_parent_empty (K : Row) : ConcCarried {mk 7 ∅ ∅} 7 K`.

Case (ii) is only vacuous if no queue partition is ever headed by an environment-bound variable —
and **§0's compiler panic is precisely a witness that that invariant fails** (see §6). The
localisation and the bug are the same object.

Because C4's answer ("with `emptyRow = true` the residual mismatch disappears") rests entirely on
this localisation, C4 is conditional on an unproved and, as written, incorrect statement. Its
*measurements* are solid (see §7).

### 5c. The refutation of the brief's charging argument is sound

§C3.3's arithmetic — `M ≤ hmeas₀ + (#eliminations)·Δ ≤ c + c·(V₀+M)²`, quadratic in `M` on the
right — is correct, and the diagnosis ("the damage per elimination is itself proportional to the
vocabulary, and no per-mint charge fixes that") is the right reading of why approach (a) as the
brief phrased it does not close. Accepted.

### 5d. §C3.4's branch table, and an interaction with the bug fix

The three environment branches are bounded by `(allVars (sys s)).card` **because `makeEmpty` and
`instantiate` DIE on an already-bound variable** — `StrictBound.lean`'s own module doc says so and
cites `Subst.scala:184`, the reinstantiation panic. So:

> **If the fix at `Subst.scala:183` is applied as written (`case Some(t) if e == t => warn`), the
> `empty` and `common`/`unify` rows of §C3.4's table lose their justification**: an `empty` step on
> an already-bound variable would add no binding, so "each such step adds exactly one binding" fails
> and `makeEmpty_env_len` becomes false. Progress would have to be re-argued (the dequeue still
> shrinks `incm` by one in that case, but that is a different lemma).

This is a real coupling between the bug fix and L5's only quantitative result, and it argues for the
root-cause fix I give in §6.3 instead.

### 5e. What I believe the shortest path to T1 is

Not fundamental — the evidence points hard at termination — but it is at least two more rounds, and
in this order:

1. **Re-state the three deletion constructors as the library operators** (F1's fix). Without this,
   nothing in the `KeyedRow`/`KeyedEmpty` bound library can be transported and every further C3 round
   is wasted.
2. **Prove the queue-hygiene invariant** "no partition in `incm ∪ proc` is headed by, or mentions, a
   variable bound in `env`". This is the single lemma that (a) kills §5b's case (ii), (b) makes the
   `qsys`/`sys` gap exactly the alias facts, and (c) is the invariant the compiler panic violates.
   **Fixing `makeEmpty`'s `aux` (§6.3) is what makes it provable.**
3. Then (A) over `qsys` reduces to the `C ⊆ K` case, and either turn `emptyRow` on in the model and
   transport `mintsBoundedOnSatKeyed3E`, or bound the `C ⊆ K` mints by "at most one per `(v, C)`
   pair" — which is `|V|·2^{|L|}` and still circular in `|V|`, so route (1) is the one to bet on.
4. The `concrete` count (§C3.4's last row) remains, and L3 §4c(2)'s `ensureSuperset`-monotonicity
   sketch is still the plan for it.

## 6. THE COMPILER BUG — reproduced, and the report has the wrong root cause

### 6.1 Reproduction (CONFIRMED, independently)

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
SATTERM_OUT=<scratch> ERMINE_JAVA_OPTS="-Dermine.useInterface=false" \
  tracker/repro/satterm/run.sh sweep json:.../tmp/L5/min/panic3.json 0 99 10 200
```

```
SUMMARY … bases=0..99 n=100 SOLVED=89 REJECTED=11 HANG=0 OOM=0
  11 × scalaparsers.Death: panic: reinstantiated type v6^N to ConcreteRho(-,Set())
       but it was already bound to ConcreteRho(-,Set())
```

**89/11 exactly as reported.** The failing bases are `{6,13,30,32,39,45,49,62,85,89,98}`. Control:
`panic2.json` (drop the third constraint) gives `SOLVED=100 REJECTED=0` — the report's control
reproduces. Dependence on the id base: CONFIRMED, and it is not a coincidence of the five bases the
hunt used — my 700-run resample (§7) hit it at bases 3 and 41, which the implementer never ran.

**Cross-check the report did not make:** the Lean model reproduces the *exact same eleven bases*
over 0..99 (I swept `looptrace` 0..99 and got the identical set), not merely "base 6 and base 13
within 0..19". That is a stronger L1/L2 conformance datum than the report claims, at an input no
corpus contains.

**Satisfiability, checked by hand.** The three constraints are
`v7 <- (v4, v6)`, `v6 <- (v6, v7)`, `v9 <- (v5, (|l100|))` (encoding confirmed at
`SatTermRepro.scala:116–117`: `[l, vs, ks] ↦ part(v_l, vs ++ [cr(ks)])`, variables allocated at
consecutive ids in sorted order). Take `ρ(v4)=ρ(v5)=ρ(v6)=ρ(v7)=∅`, `ρ(v9)={l100}`:
c1 `∅ = ∅ ⊎ ∅` ✓ (parts pairwise disjoint ✓); c2 `∅ = ∅ ⊎ ∅` ✓; c3 `{l100} = ∅ ⊎ {l100}` ✓
(disjoint ✓). Satisfiable. The compiler's own 89 successes agree (`v4,v6,v7 := ConcreteRho(-,Set())`,
c3 left residual).

### 6.2 The two steps that bind the variable (traced)

`ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.rowTrace=<file>" … sweep … 6 6`. At base 6 the
ids are v4→6, v5→7, v6→8, v7→9, v9→10, and the whole trace is six steps:

```
step learn  ^free10 <- (^free7,Repro.l100)          incm=2 proc=0
step learn  ^free8 <- (^free8 ^free9,)              incm=1 proc=1   → SelfSubstitution: ^free9 <- (,)
step learn  ^free9 <- (^free6 ^free8,)              incm=1 proc=2   → DeDuplication: ^free8 <- (,)
                                                                     Substitution:  ^free8 <- (^free6,)
                                                                     Substitution:  ^free9 <- (^free6 ^free8 ^free9,)
step empty  DeDuplication: ^free8 <- (,)            incm=3 proc=3   ← BIND #1: makeEmpty(8)
step empty  PartitionEmpty: ^free6 <- (,)           incm=4 proc=1
step empty  PartitionEmpty: ^free8 <- (,)           incm=1 proc=1   ← BIND #2: PANIC
```

**Bind #1** is `makeEmpty(v6)` on the `DeDuplication`-derived `v6 <- ()`.
**Bind #2** is `makeEmpty(v6)` on a `PartitionEmpty: v6 <- ()` **that bind #1 itself manufactured**.

### 6.3 Root cause — `makeEmpty`'s `aux` does not exclude `v` (CONFIRMED)

`Constraints.scala:1562–1566` (the `aux` body; the `abstr.map` is line **1564**):

```scala
def aux(s: Set[Partition], rhs: RHS): Set[Partition] = rhs match {
  case RHSEmpty()      => s
  case RHSAbstr(abstr) => s ++ abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))
  case _               => tml.die("Incompatible instantiations of '" + v + "'")
}
```

The lambda parameter `v` **shadows** the `v` being emptied, and the map ranges over **all** of
`abstr`. So when the queues hold a self-referential partition `v <- (v, …)` — here
`v6 <- (v6, v7)`, which the `learn` branch keeps in `proc` — `makeEmpty(v)` emits
`Partition(v, RHSEmpty(), PartitionEmpty)` **for the very variable it is about to bind**, re-enqueues
it, and a later dequeue calls `makeEmpty(v)` a second time.

Compare `selfSubstitution` twelve lines away (`Constraints.scala:1157`):

```scala
if(concr isEmpty) (abstr - v).map(u => Partition(u, RHS(), SelfSubstitution))
```

— `(abstr - v)`. The asymmetry is the bug. Emitting `v <- ()` is not *wrong* (it is already known);
it is redundant, and the redundancy is what trips the panic.

**It is not confined to self-referential inputs.** Of the 14 distinct hunt seeds that panic, **3 have
no self-referential input constraint** (`e00282`, `e00660`, `e01217`). I traced `e00282` at base 13:
the loop *derives* `SplitKeyed: ^free17 <- (^ambiguous(free)25 ^free16 ^free17,)`, then
`step empty DeDuplication: ^free17 <- (,)` binds free17, and `step empty PartitionEmpty:
^free17 <- (,)` — manufactured by that same `makeEmpty` from the derived self-reference — panics.
Same mechanism, derived premise.

So the report's §0 explanation — "it is the queue's priority order that puts two `makeEmpty` steps
on the same variable" — is **half right**: the priority order decides *whether* the manufactured
`v <- ()` is dequeued before something else removes it (hence the 11% base dependence), but it does
not manufacture it. `makeEmpty` does.

### 6.4 Is uncommenting `Subst.scala:183` the right fix? — No, it is the wrong layer

`instantiateType` (`Subst.scala:182–188`):

```scala
def instantiateType(v: TypeVar, e: Type)(implicit hm: SubstEnv): Unit = hm.types.get(v) match {
  // case Some(t) if e == t => warn(e.report("warning: reinstantiated type " + v + " to the same type " + e))
  case Some(t)           => e.die("panic: reinstantiated type " + v + " to " + e + " but it was already bound to " + t)
```

* Uncommenting **would** stop this panic (both bindings are `ConcreteRho(-,Set())`, so `e == t`), and
  it is harmless *here*.
* But it treats a symptom of a **queue-hygiene** failure — the queues held a partition headed by an
  already-bound variable — and it removes the only enforcement of that hygiene. §5d: it invalidates
  `makeEmpty_env_len` and hence the `empty`/`common`/`unify` rows of L5's own branch table, and it
  would force a matching change to the Lean model (`Loop/Step.lean:132–134` mirrors the die exactly).
* **The right fix is `abstr.map` → `(abstr - v).map` in `makeEmpty`'s `aux`**, matching
  `selfSubstitution`. It is sound (`v <- ()` is already recorded — `v` is being bound to the empty row
  in the same call), it removes the re-entry at its source, it shrinks the queue rather than growing
  it, and it leaves `instantiateType`'s `die` in place as a genuine invariant check, so L5's
  `EnvNodup` / `makeEmpty_env_len` / §C3.4 survive unchanged.
* Keep the `e == t` tolerance as *defence in depth* if wanted, but not as the fix, and not without
  re-deriving §C3.4. The ALIAS form of the panic (`instantiate`'s "reinstantiated type v to u") the
  report flags deserves the same treatment — same question, same answer: find who re-enqueued the
  stale partition.
* No Scala or Lean change was made by me. Both `makeEmpty` implementations (Scala and Lean model)
  would need the `aux` change together, or L2/L4's trace equality breaks.

### 6.5 Can a source-level Ermine program reach it? — not exhibited; the shape is expressible

Attempted with `bin/ermine` (`:load` of modules in my scratch, `-Dermine.rowTrace`,
`-Dermine.useInterface=false`). Partition constraints are surface syntax
(`TypeParsers.scala:121–126`, `a <- (b, c) => …`, as in `Record.appendR : c <- (a,b) => …`), so the
*constraint language* is reachable. But I could not get a **self-referential partition into a
solve's input**: with

```
h : {..a} -> {..b} -> {..a}
h r s = appendR r s
```

the trace shows the solve receiving `part v579387|v579386|v579385` — three *distinct* variables; the
whole is unified with the signature's skolem `a` only *after* `solve` returns. Recursive shapes
(`rec1 r s = rec1 (appendR r s) s`, `rec2 r s = appendR (rec2 r s) s`) likewise produced only
distinct-variable partitions.

That is a negative result for the *easy* route, not a proof of unreachability, and §6.3's finding
cuts against it: the panic does **not** need a self-referential input, only a derived one, and
`SplitKeyed`/`Substitution`/`CommonSubexpression` do derive them (seed `e00282`). My honest position:
**PLAUSIBLE that a source program reaches it, not demonstrated.** Whoever takes this should sweep the
corpus for a `learn` record whose conclusion is self-referential (`^freeN <- (… ^freeN …)`) followed
by an `empty` step on `N` — the corpus traces already exist from L2.

## 7. The hunt's numbers — re-run

| claim | how I checked | result |
|---|---|---|
| 1,500 seeds × 5 bases = 7,500; 7,468 SOLVED, **0 FUEL**, 29 REJECTED, 3 capped | recounted `tmp/L5/fuzz/hunt-shipped.txt` | 29 `REJ`, 3 `OTHER` (all `e00346`), 7,468+29+3 = 7,500 ✓ |
| **my own resample** | 100 seeds (every 15th) × **7** bases — the implementer's 0,1,5,13,97 **plus 3 and 41** | **700 runs, 0 FUEL**, 3 rejections (all the same panic; two at the *new* bases) |
| `e00346` extreme: 1,033 ids at base 1, model = compiler | replayed on the compiler, `run.sh sweep … 0 5 60 6` | `DRAWN min=553 median=690 max=1033`; per-base 623/1033/690/553/731/584 — **model matches the compiler at all six bases exactly**; base 1 `bound=164 residual=6 drawn=1033` in 512 ms (report says 655 ms; timing noise) |
| C4: 3,000 runs a side, 2,986 SOLVED each, mean 10.262 vs 10.270, max 623 both, 14 rejections/caps | recomputed from `hunt-{shipped-sub,emptyrow}.txt.drawn` | `n=2986 mean=10.270 max=623` shipped, `n=2986 mean=10.262 max=623` emptyrow ✓ |
| generator really is satisfiable-by-construction | read `genE.py` | yes — every constraint is `whole <- (pairwise-disjoint parts ⊎ disjoint concrete)` over a fixed valuation ✓ |
| Population 2 (scaling family, quadratic growth) | read `scale.tsv`/`scale.sh`; not re-run | numbers consistent with the report; **not independently re-run** |

The quadratic-growth reading (`7.7·(16/6)² = 54.7` vs measured 59.9) is a two-point fit on six data
points with `max` growing much faster; it is suggestive, not evidence of a quadratic bound, and the
report does not over-claim it.

## 8. Acceptance criteria (plan `LOOP-MODEL-PLAN.md`, L5 section)

| criterion | verdict | evidence |
|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | **PASS literally / FAIL in substance** | no `G' ⊆ G` constructor without a licence, and `drop` is tight (model-equivalence). But three constructors admit arbitrary satisfiability-preserving *additions*: `no_mint_bound_along_strict` (§2). The stage's stated rationale is not achieved. |
| every `step` refines it under the same hypotheses as `step_refines_all` | **FAIL** | `step_refines_strict` holds under `LinkOrEmptyStep` only (`common`/`empty`/`unify`); `concrete` and `learn` are out. Report states this. |
| brief C1: `LoopRel.weaken` used nowhere in the `step` refinement | **FAIL** | machine-checked transitive dependency through `step_sat` (§3). |
| brief C2: `SupOk`/`SupFresh` preserved so `RunSupOk` is a theorem | **FAIL (declared)** | not attempted for `learn`; `step_su`/`step_envNodup`/`env_len_le_allVars` delivered instead. Report states this. |
| `Terminates s₀` for satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | **FAIL (T2, declared)** | no bound, no witness. |
| brief C4: `emptyRow` variant answered | **PASS, conditionally** | answered with a 6,000-run measurement I reproduced; the *argument* rests on §5b's localisation, which is incomplete. |
| audit green | **PASS** | 841 jobs, 3003/0, 0 `sorry`, 33 headlines on standard axioms — all re-run. |
| report keeps original vs proved statements side by side where weakened | **PASS** | §C1.5 and the closing table are honest about row 6, the `learn` branch and C2 — but silent on F1 and F2. |

## 9. Findings, ranked

| # | severity | status | what |
|---|---|---|---|
| **F1** | **major** | CONFIRMED (Lean) | `emptyRemove`/`instRemove`/`concRemove` are unconstrained rewrites; `LoopStrict` reaches unbounded vocabulary from a fixed satisfiable system, so no measure is monotone along it and the stage's structural motivation is unmet. Fix: restate them as the library operators (`makeEmptyE`, `concretizeSrs`, the substitution image). |
| **F2** | **major** | CONFIRMED (Lean metaprogram) | "weaken appears nowhere in this proof or in anything it depends on" is false; `step_sat = (step_refines _).sat`. Fix: reprove `step_sat` for the three branches, or restate the claim. |
| **F3** | **moderate** | CONFIRMED (trace, two seeds) | The panic's root cause is `makeEmpty`'s `aux` mapping over `abstr` including `v` (`Constraints.scala:1564`), where `selfSubstitution` uses `(abstr - v)`. The report attributes it to queue priority order alone. Fix the `aux`, not `instantiateType`. |
| **F4** | **moderate** | CONFIRMED (reading + §5d) | Uncommenting `Subst.scala:183` invalidates `makeEmpty_env_len` and the `empty`/`common`/`unify` rows of L5 §C3.4, and forces a matching Lean-model change. Recommend the `aux` fix instead. |
| **F5** | **moderate** | CONFIRMED (Lean) | §C3.2's localisation blockquote is incomplete (misses the parent-already-empty witness, which carries *every* key) and imprecise (`C \ K = ∅` is `C ⊆ K`, not `K = C`). C4's conclusion inherits the defect. |
| **F6** | **minor** | CONFIRMED | §C3.1's (B) table asserts "ok" for `makeEmpty` over `qsys` without argument; `rhs - v` destroys `Resolved` witnesses (`mk u {v} K ↦ mk u ∅ K`). Needs the `KeyedEmpty` lemma spelled out or a counterexample. |
| **F7** | **minor** | CONFIRMED | §C1.5 misquotes the `conc1` probe's message ("the whole contains it but no part does" is `conc3`'s; `conc1` says "a part contains it but the whole does not"). Substance unaffected. |
| **F8** | **cosmetic** | CONFIRMED | README diff is +146/−0 (report says +144); "three import lines" is a +8 diff because L3's five were never staged; `split` liveness is 1, not 2; three `linter.style.header` warnings on `StrictBound.lean`. |
| **F9** | **information** | CONFIRMED | The Lean model reproduces the panic at the *identical eleven bases* over 0..99 — a stronger conformance result than §0 claims. Worth recording in L4's population notes. |

Nothing found that is unsound, and nothing found in `StrictBound.lean`.

## 10. Round-2 specification (the stage stays PARTIAL)

Send back to the implementer, in this order:

1. **Re-state the three deletion constructors as functions of `G`.** Minimum:
   `emptyRemove {G v} : mk v ∅ ∅ ∈ G → LoopStrict G (KeyedEmpty.makeEmptyE v G)`, and the alias and
   concrete twins, with the loop's real `sys s'` connected to the operator's output by `drop` and the
   additive constructors on either side. Acceptance: `(allVars ·).card` is bounded along
   `LoopStrictRun` from a fixed `G₀` — i.e. `no_mint_bound_along_strict` (my `Growth.lean`) becomes
   unprovable. Keep `NoLoss` and `no_loss`; they are good and they stay true.
2. **Correct F2**: prove `step_sat` for `common`/`empty`/`unify` without `LoopRel`, or restate the
   acceptance claim in the report and the plan row. Re-run the transitive-dependency check
   (`tmp/review-L5/Deps.lean` is reusable) as the evidence, not `grep`.
3. **Prove the queue-hygiene invariant** `∀ p ∈ incm ∪ proc, p.lhs ∉ env ∧ ¬ p.rhs.involves(env)` —
   or exhibit its failure and quantify it. This is the lemma §5b's case (ii), §5a's `qsys` gap and
   the compiler panic all reduce to. It is *not* provable against today's `makeEmpty`; state that as
   the finding if the Scala is not changed.
4. **Turn §C3.2's localisation into a theorem** over `qsys`, in the corrected form (`C ⊆ K`, plus the
   parent-empty case discharged by (3)). Then C4's answer becomes real.
5. Fix F5/F6/F7/F8 in the report and the plan's L5 row; add F9 to it.
6. **Hand the compiler bug to the user with §6.3's root cause and §6.4's recommendation**, not with
   "uncomment line 183". If the `aux` fix is adopted, the Lean model's `makeEmpty`
   (`Loop/Step.lean:126`) changes in lock-step and L2/L4's corpus and property runs must be re-run.

Everything else in the report — `NoLoss`/`no_loss`/`weaken_not_strict`, the six `*_noLoss` licences,
`sat_of_erase`/`sat_of_replace`, `cancellation_bare`, `step_su`/`step_envNodup`/`env_len_le_allVars`,
the refutation of the brief's charging argument, and the whole hunt — I re-ran or re-read and accept.

---

# Round-2 re-review — 2026-09-04 (same reviewer)

Targeted re-review of the implementer's round 2 (report §R2). I re-ran everything; I trusted no
figure in the hand-off note. Scratch unchanged: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5/`.
Nothing outside my scratch and this file was touched; no commits, no sbt, no Lean or Scala edits.
The tree I reviewed does **not** contain the B1 compiler fix or its Lean mirror.

## R-1. Build, audit, hygiene — re-run

| | result |
|---|---|
| `lake build Rowpartition` | `Build completed successfully (841 jobs)` |
| `lake env lean Audit.lean` | `Rowpartition theorems audited: 3058; declarations using a non-standard axiom: 0` |
| `sorry`/`axiom`/`partial`/`native_decide`/`implemented_by`/`unsafe`/`opaque`/`Classical`/`admit` | **0 in all three modules** (the one `Classical` hit is the word inside a prose comment at `Strict.lean:317`) |
| `#print axioms`, 57 headlines (`tmp/L5/Axioms.lean`, re-run by me) | 57 lines, 56 × `[propext, Classical.choice, Quot.sound]`, 1 × `[propext, Quot.sound]` — **no non-standard axiom** |
| module sizes | `Strict.lean` 612, `StrictStep.lean` 1962, `StrictBound.lean` 339 = **2,913** |
| tree scope | only the three L5 modules + plan/handoff/README/`Rowpartition.lean` changed; L3's and L4's files are untouched |

## R-2. F1 — **FIXED**, verified against my own counterexample

`LoopStrict`'s eliminations are now functions of `G`:
`instRemove G (substOut v u G)`, `emptyRemove G (makeEmptyE v G)`, `concRemove G (concretizeSrs v C G)`,
each with a single `NoLoss` premise, plus `drop` (subset + `NoLoss`) and
`requeue : allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → LoopStrict G G'`.

* **My round-1 `Growth.lean` no longer elaborates** — re-run against the new tree, it fails at
  exactly the two places it must: `emptyRemove`'s target is now `KeyedEmpty.makeEmptyE 0 (Gg n)`,
  and `instRemove`'s is `substOut 0 1 (…)`, so neither can be pointed at an arbitrary larger system.
* `LoopStrict.allVars_subset_of_notMint` covers **every** constructor (the four `IsMint` ones
  discharged by hypothesis, the rest proved), and `IsMint = K2SplitStep ∨ ResStep ∨ SplitStep ∨
  K2ResStep` is exactly the four minting relations — nothing that can add a variable is outside it.
  `LoopStrict.allVars_card_le` (≤ +1 per step) and `LoopStrictSteps.allVars_card_le`
  (≤ `|allVars G| + m`) follow, and `no_growth_without_mint` is the direct refutation of my
  round-1 theorem.
* **Strictly stronger than round 1 in a second way I did not ask for**: `LoopStrict.sat` no longer
  takes satisfiability preservation as a *premise* — it is now derived, from
  `substOut_sound`/`makeEmptyE_sound`/`concretizeSrs_sound` and, for `requeue`, from `Conserv`.
* `substOut` checked against the Scala (`Constraints.scala:1523–1539`): the `ruleInvolves(v)`
  partition, `replace`'s `f(z)`/`abs.map(f)` rewriting and the retained link `v <- (u)` are all
  faithfully modelled. The stated reason `instRemove` is not applied — `substOut` omits
  `replace`'s `Partition(u, RHSEmpty(), DeDuplication)` when `abs` contains both `v` and `u`
  (`:1527–1528`) — is **accurate**.

## R-3. F2 — **FIXED**, verified with my own root list

I re-ran my `Deps.lean` transitive-constant-closure check on **23 roots of my own choosing**
(every round-1 root that was `true`, plus the new `step_strict`, `step_conserv_strict`,
`step_models_iff`, `step_sat_strict`, `step_allVars_strict`, `step_steps_strict`,
`step_empty_makeEmptyE`, the four vocabulary theorems and `queueHygiene_no_rebind`):

```
… all 23: LoopRel.weaken=false  step_refines=false
```

Round 1's six `true`s are gone. `step_sat_strict` is now `(step_strict …).1.sat`, and the branch
proofs discharge `Conserv`/`NoLoss`/`VocIn` from the new forward-analysis lemmas. I read those
statements: `makeEmpty_forward` and `instantiate_forward` are generic predicate-propagation
lemmas over an arbitrary `P` with `RedClosed P`, `QOk` well-formedness and the per-rule closure
conditions (`hErase`/`hProp`, `hRep`/`hAlias`) as hypotheses — the natural ones, nothing smuggled.
`replace_forward_sent` carries a genuine `v ≠ u` side condition, which the `unify` branch has
(the `v = u` case is `step_strict_common_eq`).

## R-4. NEW FINDING — `requeue` is tight for the *vocabulary*, not for `hmeas` (CONFIRMED, machine-checked)

This is the one thing round 2 does not say, and it decides where round 3 has to start.

**Where the refinement actually goes.** I counted the constructor applications myself
(`grep -n "LoopStrict.<ctor>"`, all three modules):

| branch | theorem | constructor used |
|---|---|---|
| `common`, equal variables | `step_strict_common_eq` (`:262`) | `drop` (reflexive) |
| `common`, distinct | `step_strict_common` (`:1466`) | **`requeue`** |
| `empty` | `step_strict_empty` (`:1138`) | **`requeue`** |
| `unify` | `step_strict_unify` (`:1580`, plus `drop` at `:1532`) | **`requeue`** |

`emptyRemove` is applied exactly once, at `Strict.lean:560`, inside the auxiliary
`step_empty_makeEmptyE`; `instRemove` and `concRemove` are applied **nowhere**. And
`step_empty_makeEmptyE` is a **leaf**: `grep -rn step_empty_makeEmptyE Rowpartition/` finds no use
of it anywhere. Its statement is `LoopStrict (sys s) (makeEmptyE r.lhs (sys s))` — a step to the
*operator's* output, which is not `sys s'`; nothing composes it with the `requeue` that reaches
`sys s'`. So the report's "the `empty` branch is connected to `makeEmptyE`" is true of a side
theorem, not of the branch's refinement, which is one `requeue`. Worth one sentence of correction;
it does not change the verdict.

**Why that matters.** `requeue`'s three conjuncts are *semantic* (model-set equality) plus a
vocabulary bound; `Carried` is *syntactic*. So `Carried` need not survive a `requeue` step — and it
does not. Machine-checked in `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5/Requeue.lean`
(compiles clean against the round-2 tree, all premises proved, no `sorry`):

```lean
def GG  : System := {mk 1 ∅ ({0, 1} : Row), mk 0 ∅ ({0} : Row), mk 2 ∅ ({1} : Row)}
def GG' : System := {mk 1 {0, 2} (∅ : Row), mk 0 ∅ ({0} : Row), mk 2 ∅ ({1} : Row)}

theorem noLoss  : NoLoss GG GG'
theorem conserv : Conserv GG GG'
theorem voc     : allVars GG' ⊆ allVars GG
theorem rq_step : LoopStrict GG GG' := LoopStrict.requeue voc conserv noLoss

theorem requeue_breaks_carried :
    ∃ G G' : System, LoopStrict G G' ∧ Carried G 1 ({0} : Row) ∧ ¬ Carried G' 1 ({0} : Row)
```

`v1 <- ((|l0,l1|))` re-expressed as `v1 <- (v0, v2)` is the same system logically, over the same
three variables — and it destroys the `ConcCarried` witness for the key `(v1, {l0})`. So
`uncarried` strictly increases and `hmeas` increases along a legal `LoopStrict` step. **Ingredient
(B) of §C3.1 — "every non-mint step preserves `Carried` and adds no variable" — is therefore still
unavailable from the relation**, now for a sharper reason than round 1's: not because the relation
admits arbitrary systems, but because `requeue`'s licence is semantic and the guard is syntactic.

This does not falsify anything the round-2 report claims, and it does not undo F1's fix (the
vocabulary bound is real and is what I asked for in §10 item 1). It is the next obstacle, and it
says a fourth conjunct — a syntactic `Carried`-preservation clause on `requeue`, or replacing
`requeue` by the queue operators the way `emptyRemove` was replaced — is what round 3 needs.

## R-5. §10 items 3–6, checked

* **Queue hygiene (item 3).** `QueueHygiene s := ∀ p ∈ s.parts, ∀ v, s.env.contains v = true →
  p.involves v = false` is **exactly** the invariant §5e named. `queueHygiene_no_rebind` proves the
  reinstantiation panic unreachable under it — correct, and it is the right connective between the
  bug and the bound. `selfSubstitution_excludes_self` (the Scala's `(abstr - v)`,
  `Constraints.scala:1157`) and `makeEmpty_aux_emits_self` (the `abstr.map` over *all* of `abstr`,
  `:1564`) reproduce my §6.3 asymmetry in Lean. **Caveat, stated for the record**:
  `makeEmpty_aux_emits_self` is about the `a.map` fragment in isolation — it does not prove that the
  emitted `v <- ()` survives `trim`/`++!` into `ni`, so the *falsity* of `QueueHygiene` for a
  reachable state still rests on my §6.2 trace, not on a theorem. The report's "so `QueueHygiene` is
  FALSE for the model as it stands" is therefore an empirically-established claim with a
  mechanism lemma beside it, not a proved one. I checked the stated preservation gap is otherwise
  accurate: in the loop only `makeEmpty` and `instantiate` bind, `instantiate`'s `replace` rewrites
  every occurrence of `v` (lhs included) so it leaks none, `makeConcrete`/`destructiveSub` bind
  nothing, and the `learn` rules read only the queues — so `aux` is indeed the only producer.
* **Localisation (item 4).** `concCarried_of_conc_subset` (`C ⊆ K`, not `K = C`),
  `concCarried_parent_empty` (every key at once) and `qsys_concCarried_of_envEmpty` are my two
  round-1 counterexamples turned into the positive theorems, in the corrected form. **DONE.**
* **Items 5 and 6.** F5–F8 are corrected in the report (`split` liveness 1, the +146/−0 README, the
  +8 import diff, the `conc1` message); §0 now carries my §6.3 root cause and my §6.4
  recommendation (`(abstr - v)`, not uncommenting `Subst.scala:183`), with the §5d coupling to
  `makeEmpty_env_len` recorded. **DONE.**
* **Item 1's letter.** Two of the three operator constructors are still declared-but-unapplied, and
  the report says so with accurate reasons (`substOut` omits `replace`'s dedup fact;
  `concretizeSrs` has the `cancellation_bare` gap). Accepted as recorded scope.

## R-6. Acceptance criteria, re-checked

| criterion | round 1 | round 2 |
|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | PASS literally / FAIL in substance | **PASS** — no constructor enlarges the vocabulary except the four minting ones; `no_growth_without_mint`; my `Growth.lean` no longer elaborates |
| every `step` refines it under `step_refines_all`'s hypotheses | FAIL | **FAIL, unchanged** — `LinkOrEmptyStep` only; `concrete` and `learn` still out. Recorded. |
| brief C1: `LoopRel.weaken` nowhere in the `step` refinement | FAIL | **PASS** — 23 roots, machine-checked by me |
| brief C2: `RunSupOk` a theorem | FAIL | **FAIL, unchanged.** Recorded. |
| `Terminates s₀` with a bound, or a witness | FAIL (T2) | **FAIL (T2), unchanged.** Recorded, and R-4 sharpens why. |
| brief C4 answered | PASS conditionally | **PASS** — the localisation it rests on is now a theorem |
| audit green | PASS | **PASS** — 841 / 3058 / 0 / 0 `sorry` / 57 headlines standard-axiom |

## R-7. Verdict — **ADVANCE, with the remaining work carried forward**

Both round-1 majors are fixed, and I verified each with my own artefact rather than the
implementer's: F1 by re-running the counterexample that motivated it (it no longer elaborates, and
`no_growth_without_mint` is its converse), F2 by re-running my dependency metaprogram on a root list
I chose. The audit, the build, the axiom census and the module sizes all reproduce. Nothing unsound;
no statement I checked hides a weakening; the report is candid about every gap I had named.

The stage's own acceptance criteria are still not all met — the refinement covers three of five
branches, C2 is open, and C3 is (T2) with no bound and no witness — but every one of those is
recorded in the report as accepted scope, which is exactly the condition the plan's review protocol
sets for advancing. This is research that is not finished, not a defect list.

**Carried forward to whoever takes C3 (in priority order):**

1. **R-4 is the new front line.** Add a syntactic `Carried`-preservation conjunct to `requeue`, or
   dissolve `requeue` into the queue operators the way `emptyRemove` was dissolved. Acceptance:
   `requeue_breaks_carried` (my `Requeue.lean`) becomes unprovable, and `hmeas` is proved
   non-increasing at every non-`IsMint` step.
2. Make `step_empty_makeEmptyE` load-bearing: compose it with the trailing `requeue` so the `empty`
   branch's refinement actually runs through `makeEmptyE`, and do the same for `common`/`unify` once
   `substOut` is widened with `replace`'s de-duplication fact (that widening is a small,
   well-understood change and would make `instRemove` live).
3. `QueueHygiene` preservation: after the B1 fix lands and the model mirrors it, prove it — or
   prove its failure at the state level rather than at the `a.map` fragment.
4. The `concrete` and `learn` branches (`concRemove`'s conditional licence; `RefineLearn` against
   `LoopStrict`), and C2's `learn` vocabulary lemma. Unchanged.
5. Add R-4 and the `step_empty_makeEmptyE`-is-a-leaf note to `L5-TERMINATION.md`'s closing table so
   the record is complete.

---

# Round-3 review — 2026-09-05 (fresh reviewer)

Review of L5 round 3 against `briefs/brief-L5r3.md`, `briefs/brief-review.md` and the plan's L5
acceptance. Pre-existing baseline `52da5b8` (everything through B1 and L5 round 2 committed);
under review are the five uncommitted modules `Loop/{Carried,Draws,Factor,Hygiene,Residual}.lean`,
`Rowpartition.lean` +5, `tracker/lean/README.md` +28, the plan's L5 row, the handoff paragraph,
and `L5-TERMINATION.md`'s Round 3 section. I read my predecessor's round-1 and round-2 sections
first; this round answers their R-4 and their five-item priority list.

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r3/`. Nothing outside that directory and
this file was edited; no commits, no Lean edits, no Scala edits, no sbt. Two throwaway Lean
witnesses of my own (`B1Bad.lean`, `MintCount.lean`) compile clean against the tree and are cited
below.

**Verdict: ADVANCE, with three corrections and a round-4 specification.** Nothing is unsound. The
build, the audit, the axiom census, the module sizes, the verbatim quotations and the
constructor-use table all reproduce exactly, and I re-derived the two load-bearing claims myself
rather than reading them: the B1 fix IS load-bearing exactly where the report says (I reverted
`.excl v` in a scratch copy of the arm and proved `makeEmpty_avoids` FALSE for it), and the
`carried_step` / `LoopStrictKRun` construction is what it says it is. But three statements are
weaker than the surrounding prose claims, one of them machine-checkably so.

---

## S-1. Rebuild, re-audit, hygiene — everything reproduces

| step | command | result |
|---|---|---|
| build | `lake build Rowpartition` | `Build completed successfully (846 jobs)` — **matches** (841 before) |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3186; declarations using a non-standard axiom: 0` — **matches** |
| audit script | read `Audit.lean` | a real `Lean.collectAxioms` sweep over every non-internal `Rowpartition.*` theorem; `sorryAx` would be reported. Covers the new modules. |
| grep | `sorry`/`axiom`/`partial`/`native_decide`/`implemented_by`/`unsafe`/`opaque`/`Classical`/`admit`/`#exit`/`extern`/`trust` over all five new modules | **0 hits** |
| `#print axioms`, my own list | I extracted **all 121** theorem names from the five modules and ran them (`tmp/review-L5r3/MyAxioms.lean`) | 117 × `[propext, Classical.choice, Quot.sound]`, 2 × `[propext, Quot.sound]`, 1 × `[propext]`, 1 × "does not depend on any axioms". **No non-standard axiom.** |
| `#print axioms`, the implementer's list | re-ran `tmp/L5r3/Axioms.lean` | 49 headlines, 49 × `[propext, Classical.choice, Quot.sound]` — **matches** |
| verbatim | script-checked every ```lean block of the Round 3 section, doc comments stripped, against the five modules | **70 of 70 declarations byte-for-byte present.** (The report says 71 of 71 signatures; the difference is how a `def`+`theorem` block splits. Nothing paraphrased, nothing weakened silently.) |
| line counts | `wc -l` | 391 / 1,496 / 466 / 270 / 252 = **2,875** — matches |
| diff scope | `git status` + `git diff --numstat` | five NEW `Loop/` modules; `Rowpartition.lean` +5/−0; `README.md` +28/−0; plan +1/−1; report +773/−0; handoff +14/−1. `Loop/{Strict,StrictStep,StrictBound}.lean` and every `Refine*`/`Order`/`Wf`/`Step` module and every Scala file **UNCHANGED** — so the round-2 claim that nothing earlier is weakened holds literally. |

## S-2. R3.1 (R-4) — the statements are honest; two counts in the prose are not

`LoopStrict.carried_step` VERBATIM as quoted. Reading it for hidden hypotheses:

* `hm : SModels rho G` — a **model** hypothesis, not merely `SSat`. Used only to discharge
  `emptyRemove` and `concRemove` (both operators lose a fact on unsatisfiable input). Disclosed
  in the doc comment. Fine.
* `hdrop`, `hinst`, `hreq` are the theorem's **conclusion, assumed** at three of the fourteen
  constructors. So `carried_step` proves nothing at `drop`, `instRemove` or `requeue`; it is a
  case dispatch that isolates them. The report says exactly this, and R3.1.2/§3 prove two of the
  three cannot be discharged (`substOut_breaks_carried`, `carried_not_monotone_under_deletion`),
  with the third being my predecessor's `requeue_breaks_carried`. **The negative half of R-4 is
  correctly established.** This is a legitimate research answer, not a dodge.

**F-1 (CONFIRMED, counting).** "The other **ten** constructors need nothing beyond a model"
(`Carried.lean:245`, quoted verbatim in the report) and "for all **ten** constructors that can
have it" (§R3.6) are both wrong, and so is "nine of the fourteen constructors (the rule
constructors) are discharged by **additivity**". I read the fourteen cases of the proof:

| how discharged | constructors | count |
|---|---|---|
| additivity (`CarrPres.of_subset`) | `nongen`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup` | 5 |
| library `Carried` lemma | `emptyRemove`, `concRemove` | 2 |
| **vacuous** — `absurd … hmint` | `split`, `res`, `splitFree`, `kres` | 4 |
| licence assumed | `drop`, `instRemove`, `requeue` | 3 |

So the number of constructors for which `carried_step` proves anything is **seven**, not ten, and
four of the "rule constructors" are discharged by the `¬ IsMint` hypothesis rather than by
additivity. Fix: say "seven proved outright, four vacuous under `¬IsMint`, three passed through".

**F-2 (CONFIRMED, machine-checked) — `LoopStrictKRun.mints_bounded` does not bound the mints.**
Its conclusion does not mention `n` at all:

```lean
theorem LoopStrictKRun.mints_bounded {G₀ : System} (rho : Assign) (hm : SModels rho G₀) :
    ∀ (n : ℕ) (G : System), LoopStrictKRun (labelsOf G₀) n G₀ G →
      (allVars G).card ≤ (allVars G₀).card + hmeas (labelsOf G₀) rho G₀
```

and its doc comment ("the mints themselves are bounded, because each of the `n` counted steps is
the only kind that can enlarge the vocabulary"), the report's §R3.5.2 ("hence on the number of
mints, since only a mint enlarges the vocabulary") and `Residual.lean:234` ("so this bounds the
number of mints of the whole solve") all assert something the theorems do not give. Two reasons,
both structural:

1. `LoopStrictKRun.mint` carries **no progress side condition**, where the library's
   `K2StarLoopRun.tail` carries `G ≠ G'`; and `K2StarStep` includes the NON-generative
   `NonGenStep`, so a counted step need not enlarge anything.
2. `LoopStrictKRun.keep` weakens the library's subset-monotone step to
   `allVars G' ⊆ allVars G`, which permits **strict shrinking**. The library's card bound bounds
   the mints only because its systems grow monotonically; this relation's do not.

Machine-checked in `tmp/review-L5r3/MintCount.lean` (compiles clean, `[propext, Classical.choice,
Quot.sound]`, no `sorry`):

```lean
def G0 : System := {mk 0 ∅ (∅ : Row), mk 1 ∅ (∅ : Row), mk 0 {1} (∅ : Row)}
theorem k2 : K2StarStep G0 G0                                        -- commonPart re-derives v0 <- (v1)
theorem krun_unbounded (L) : ∀ n : ℕ, LoopStrictKRun L n G0 G0
theorem mints_not_bounded :
    ∀ N : ℕ, ∃ (n : ℕ) (G : System), N < n ∧ LoopStrictKRun (labelsOf G0) n G0 G ∧
      (allVars G).card ≤ (allVars G0).card + hmeas (labelsOf G0) (fun _ => (∅ : Row)) G0
```

From the FIXED satisfiable `G0`, `LoopStrictKRun` reaches every `n` with the vocabulary bound
holding. The same defect propagates to the loop-level statement: `QStepDichotomy`'s second
disjunct permits `allVars (qsys s') ⊊ allVars (qsys s)`, and the loop **does** shrink `qsys` — a
`common`/`unify` step writes the alias into `env`, and `qsys` (`StrictStep.lean:1733`) excludes
aliases, so the eliminated variable leaves the queue-visible vocabulary. So a mint(+1) /
elimination(−1) alternation keeps `|allVars (qsys ·)|` flat while minting without limit
(PLAUSIBLE for the loop; CONFIRMED for the relation). This does not make anything false — the
proved statements are correct as written — but it means what round 3 has is a **snapshot bound on
the queue-visible vocabulary, not a mint budget**, and the gap to (T1) is larger than the
narrative suggests.

**F-3 (CONFIRMED) — `LoopStrictKRun` is not connected to the loop.** `grep -rn LoopStrictKRun
Rowpartition/` finds it in `Carried.lean` only (one prose mention in `Residual.lean`). No theorem
derives a `LoopStrictKRun` step from `step`, and by the round's own `substOut_breaks_carried` none
can over `sys`. The report is candid about this in §R3.1.4 and §R3.6 ("for the carried-preserving
fragment"), and the plan row says "along carried-preserving runs" — so the wording is defensible.
Recorded so the record is complete: this is round-2's "`step_empty_makeEmptyE` is a leaf" finding
recurring at round 3's headline, and it is the reason F-2 matters.

## S-3. R3.2 — DONE, verified, and the constructor count is exactly right

I counted the constructor applications myself (`grep -o "LoopStrict\.<ctor>"` over all eight
`Strict*`/new modules) and got the report's table **entry for entry**: `nongen` 3, `split` 2,
`res` 1, `splitFree` 1, `kres` 2, `renameLhs` 1, `linkSymm` 2, `emptyProp` 1, `dedup` 4, `drop` 2,
`instRemove` 2, `emptyRemove` 1, `concRemove` 0, `requeue` 8. **13 of 14 live**, confirmed.

* `step_empty_via_makeEmptyE` genuinely composes round 2's leaf with the `requeue` that reaches
  `sys s'`; the third conjunct is the composite `LoopStrictRun`, so the leaf is no longer a leaf.
  It costs one new hypothesis, `hsat : SSat (sys s)` (needed for `allVars_makeEmptyE_eq` via
  `defs_conc_empty_of_sat`) — a strengthening of the premise the report does not flag, harmless
  because satisfiability is the setting of the whole C3 argument.
* `dedup_entailed` is a real argument, not a re-labelled assumption: `v` and `u` are parts of one
  constraint hence have disjoint rows, the link makes the rows equal, so both are empty. The
  `LoopStrict.dedup` constructor then adds `u <- ()` legitimately and `instRemove` applies.
  `instRemove` is live at BOTH link branches (`step_unify_via_substOut`, `step_common_via_substOut`).
* Caveat worth one line in the report: the factoring interposes the operator but does **not**
  remove the trailing `requeue` — `LoopStrict H (sys s')` is still one semantically-licensed
  requeue, and `step_refines_strict` (the acceptance criterion) still runs through the bare one.
  The report says as much ("Round 2's bare `requeue`s are still there").

## S-4. R3.3 — the strongest result of the round; B1 certification confirmed, with two qualifications

The statements are as quoted and the proof is a genuine five-way case analysis on `step`'s
dispatch (`common`, `empty`, `concrete`, `unify`, `learn`), not a vacuity. It is **not** vacuous:
`queueHygiene_binds_unbound` derives three real facts, and `step_link_no_death` turns them into
"neither link branch can error", using `instantiate_ok_of_unbound` — which I verified against
`Loop/Step.lean:82-94`: `instantiate`'s ONLY error arm is `env.contains v`.

**Hypotheses are strictly weaker than `step_refines_all`'s**, which the report claims and I
confirmed: `step_refines_all` needs `emptyRow = false ∧ disjRule = false ∧ cseMints = false ∧
SupOk ∧ SupFresh` (`RefineLearn.lean`), `step_queueHygiene` needs only `disjRule = false ∧ SupOk ∧
SupFresh`. `Wf` is not needed at all.

**The B1 fix is load-bearing exactly where claimed — CONFIRMED by reverting it.** The brief asked
me to try this; I did, in `tmp/review-L5r3/B1Bad.lean` (compiles clean against the tree):
`makeEmptyBad` is `Loop.makeEmpty` with the single token `p.rhs.abstr.excl v` reverted to
`p.rhs.abstr`, everything else byte-identical. With `proc = {v0 <- (v0, v1)}`, `incm` empty, empty
env:

```
fixed   makeEmpty : Except.ok ([(1, [])], [])          -- emits only  v1 <- ()
reverted makeEmptyBad : Except.ok ([(0, []), (1, [])], [])  -- emits  v0 <- ()  as well
```

and therefore, as theorems:

```lean
theorem good_avoids_v : … ∧ ni.elems.any (fun p => p.involves 0) = false
theorem bad_emits_v   : ∃ x ∈ niBad.elems, x.lhs = 0
theorem makeEmptyBad_avoids_false :        -- the statement of `makeEmpty_avoids`, verbatim,
    ¬ (∀ …, makeEmptyBad ns v incm proc env = .ok (ni, np, e) → …)   -- with makeEmptyBad
```

So the failing lemma is `makeEmpty_avoids` in its propagation case, exactly as
`Hygiene.lean:220-226` and the report say; and I checked that the *other* `SSet.mem_excl_iff` use
in that proof (`:279`) belongs to the erasure arm `p.rhs.erase v`, which pre-dates B1. The Scala
side (`Constraints.scala:1574`, `(abstr - v)`) and the model agree.

**Qualification Q-1 (CONFIRMED).** `run_queueHygiene` and `run_queueHygiene'` carry
`RunSupOk n s` — which `RefineLearn.lean:1499` defines as `SupOk`/`SupFresh` **at every state of
the run**, a per-state hypothesis that L3's own row records is *not* an invariant. So "the panic
has no path from any initial state" is conditional on an unproved supply invariant (plus
`disjRule = false`). The verbatim quotations show it; the prose in §R3.3, the plan row ("R3.3 DONE
and it CERTIFIES B1") and the handoff paragraph do not.

**Qualification Q-2 (CONFIRMED, minor).** `queueHygiene_initial` is stated for a state *literal*
with `env := {}`, `proc := PQueue.empty`. I checked it matches `Seed.lean:135`'s `st0` exactly, so
the coverage is real — but it is "every state `Seed.solve` builds", not "every `Wf` initial state"
as the brief and the handoff phrase it (`Wf` does not constrain `env`; `Wf.lean` is only `QOk` on
both queues plus `LblCoh`). Also, there is no single assembled corollary of the shape
"`run st0 n ≠ .rejected (panic …) s'`"; the pieces are `queueHygiene_initial` +
`step_queueHygiene` + `queueHygiene_binds_unbound`, and the reader composes them. One theorem
would close it. Note the §0 panic is `makeEmpty`'s, which is covered by
`queueHygiene_binds_unbound`'s FIRST conjunct rather than by `step_link_no_death`.

## S-5. R3.4 — `learnPartitions_drawn` verified against the Scala; the plan row overstates `_vocab`

`learnPartitions_drawn : su'.drawn ≤ su.drawn + 1 + proc.elems.length` under `disjRule = false ∧
cseMints = false`. I checked the bound against the shipped Scala rather than the model:
`Constraints.scala:1466` is `proc.foldLeft(splitConcrete(…))`, one `splitConcrete` (≤1 draw,
`:1301`, guarded by `concr.isEmpty || abstr.size < 2`) plus, per `proc` element, either
`resolution` (`:1773`: `val z = fresh(…)` is taken **before** `tops.isEmpty || bots.isEmpty` and
before all three reuse guards — so a reuse costs an id, exactly as the report says) or
`commonSubexpression` + `substitution` (no draw under `cseMints = false`). `cancellation` and
`selfSubstitution` draw nothing. **The bound is right and tight.**

**F-4 (CONFIRMED) — the plan's L5 row overstates C2.** It says "C2's quantitative half PROVED …
and its **vocabulary clause PROVED** (`learnPartitions_vocab`)". The report's own §R3.6 says the
opposite: "`SupOk`/`SupFresh` preservation (the rest of C2) needs the SHARPER vocabulary clause
'or one of the ids this step actually drew', which `learnPartitions_vocab` does not give". Reading
the statement, §R3.6 is right: the conclusion is `(x.lhs ∈ V ∨ Sup.Reach su x.lhs)`, i.e. "in the
old vocabulary or **any** id the supply can ever hand out", which cannot preserve `SupFresh`. The
plan row should say "a vocabulary clause that is not C2's". The brief's R3.4 asked for the lemma
"so `SupOk`/`SupFresh` are preserved by `step`"; that is NOT delivered, and the report says so.

Both refinement branches (`concrete`, `learn`) remain undone, with reasons I find accurate:
`concRemove`'s `NoLoss` premise is still the `cancellation_bare` gap, and the `learn` transfer
needs `RefineLearn`'s `RuleRun` to carry a `LoopStrictRun` alongside its `LoopRun`.

## S-6. R3.5 — the dichotomy is a real Prop, `redirect_breaks_carried` is real, but the framing has two gaps

**Is `QStepDichotomy` a real Prop about the model or a restatement of the goal?** A real Prop. It
is a per-step statement about the actual `step` function; `qstep_pot_le`, `run_qsys_invariant`,
`run_qsys_allVars_card_le` and `run_qsys_bound` are a genuine induction on fuel over `run`, with
`step_wf` threading well-formedness. The reduction from a run-level bound to a step-level
dichotomy is real work, and the bound it yields is explicit and depends on the input alone. I
found no circularity and no hidden hypothesis: `Wf s`, `SModels rho (qsys s)`, `ConcSub L (qsys s)`
are all present in the assembled theorems and all discharged or carried.

**Is the "worse half vacuous at a mint on satisfiable input" theorem stated as claimed?** Yes, with
one unformalised link. `dequeued_not_empty_of_sat` and `concCarried_parent_nonempty` both take
`hconc : r.rhs.conc.isEmpty = false` as a **hypothesis**; nothing in the tree proves that a mint's
dequeued premise has a nonempty concrete part. I verified that side condition against the Scala
myself and it holds: `splitConcrete` returns `Set()` when `concr.isEmpty` (`:1305`) and
`resolution` needs `tops = concr1 -- int` nonempty (`:1777`), so both minting rules require it. So
the claim is TRUE but rests on a Scala-side observation, not on a theorem. Worth one lemma.

**Is `redirect_breaks_carried` a genuine new obstacle?** Yes, and it is correctly stated — a legal
`requeue`-shaped move (same models, `allVars G' ⊆ allVars G`) that destroys a `ConcCarried`
parent, in the specific shape `Q.+!`'s `CommonPartition` redirect produces. But note precisely
what it is and is not: it compares two *hypothetical successors* (plain insertion vs. redirect),
not a state's predecessor with its successor. It is therefore an obstacle to the **covering-lemma
route** §R3.5.2b names, not a counterexample to `CarrPresOn (qsys s) (qsys s')`. §R3.6's phrasing
"`redirect_breaks_carried` shows `Q.+!`'s redirect violates it over `qsys` too" reads as the
latter and should be tightened to the former.

**F-5 (PLAUSIBLE, and the most important item for round 4) — `QStepDichotomy` may be FALSE as
stated, and nothing in the round tries to find out.** It is universally quantified over every `s`
with `Wf s`, and `Wf` (`Wf.lean`) is only `QOk` on both queues plus `LblCoh` — it does not carry
`QueueHygiene`, `NoSelfUnif`, `SupOk` or reachability. The run-level induction only ever applies
the dichotomy at states reachable from `s0`, so the lemma as stated is strictly stronger than the
proof needs, and the redirect mechanism the same round exhibits is exactly the kind of thing that
could refute it at an unreachable-but-`Wf` state. Round 3 spent its evidence budget on hunting a
*divergence witness* (a whole-run property) and none on trying to refute the *step-level Prop* it
nominates as the residual — which is far cheaper, since a single state and a single step suffice.

## S-7. The witness hunt, re-run

I re-ran the hunt independently (regeneration, samples at bases the implementer never used, the
scale families in full, and fresh model-vs-compiler comparisons), and spot-checked the headline
numbers by hand afterwards. **Everything reproduces; no discrepancy anywhere.**

| phase | what I ran | result vs. claimed |
|---|---|---|
| regeneration | `gen.py redirect 2000 <dir> 5 4 14` and the same for `alias`, then `diff -rq` against the shipped `seeds/`; separately I regenerated 40 `alias` seeds and `cmp`-ed each | **byte-for-bit identical**, 2000/2000 files each dir, 40/40 on my own check. The generator is deterministic per seed and its independent satisfiability checker rejected 0. |
| sample, shipped bases | 300 redirect + 300 alias seeds (random sample, seed 20260905) × bases {0,1,5,13,97}, fuel 400,000 | 1500 + 1500 runs, **SOLVED 3000, FUEL 0, REJECTED 0, TIMEOUT 0**; drawn mean 8.06 / 8.21, median 2 — consistent with the full-population 8.93 / 6.84 |
| **bases nobody used** | 200 redirect + 200 alias seeds × bases **7 and 1000** | 800 runs, **SOLVED 800, FUEL 0, REJECTED 0** |
| my own extra bases | `redirect00032` and `alias01349` at bases **2026** and **31337** by hand | SOLVED at all four; drawn 207 / 668 and 275 / 275 — the two- and three-cluster structure the report describes is real |
| scale families | scale18/20/22/24 **re-run in full**, 60 seeds × 3 bases each | 720/720 SOLVED, means **6.34 / 7.93 / 8.89 / 10.00** — exact match, top-10-by-drawn lists identical to the shipped logs |
| model vs. compiler | `cmp.sh` on 8 seeds spread across both populations at bases 0–9, plus `redirect00032` and `alias01349` at bases 0–29 | **140 fresh comparisons of verdict AND ids drawn, 140 identical, 0 differing.** `redirect00032` 30/30 SOLVED, DRAWN min 207 / median 668 / max 688; `alias01349` 30/30 SOLVED, DRAWN 173 / 275 / 287 — the report's 100-base figures reproduce exactly |

The generator's shape is sound for the purpose: a valuation is built first and every constraint is
emitted as `whole <- (pairwise-disjoint parts ⊎ disjoint concrete)` over it, so satisfiability is
by construction and independently re-checked. The two biases do hit their targets (twinned
right-hand sides for the redirect; companion singleton links for the alias elimination).

**Scope of what the hunt establishes, stated plainly.** It is a *whole-run divergence* check, and
it found nothing in 20,720 + my 4,320 runs. It is NOT evidence for `QStepDichotomy`, which is a
per-step Prop: a run can terminate while individual steps violate the dichotomy. The report's
closing line ("the guard's fragility is not the loop's fragility") is the right reading, but the
evidence is aimed at a different proposition from the one nominated as the residual.

## S-8. Acceptance criteria (plan `LOOP-MODEL-PLAN.md`, L5)

| criterion | round 2 | round 3 | evidence |
|---|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | PASS | **PASS**, unchanged | `Loop/Strict.lean` byte-identical (not in `git status`) |
| every `step` refines it under the same hypotheses as `step_refines_all` | FAIL | **FAIL, unchanged** — `common`/`empty`/`unify` only; `concrete` and `learn` still out. Recorded as NOT DONE with reasons. |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | FAIL (T2) | **FAIL (T2)** — and the report says so twice, including "what `QStepDichotomy` does NOT give: `Terminates s₀`". The conditional result is a bound on `|allVars (qsys ·)|`, which by F-2 is not even a mint budget. No witness: 20,720 + 4,320 runs, 0 FUEL. |
| audit green | PASS | **PASS** — 846 jobs, 3186/0, 0 `sorry`, all 121 new theorems on standard axioms |

## S-9. The round-2 priority list, item by item

| # | asked | delivered | my judgement |
|---|---|---|---|
| 1 | R-4: syntactic `Carried` conjunct on `requeue` **or** dissolve it; acceptance `requeue_breaks_carried` unprovable and `hmeas` non-increasing at every non-`IsMint` step | the conjunct proved UNADDABLE (`substOut_breaks_carried`, `carried_iff_of_link_only`, `redirect_breaks_carried`); supplied instead in a new relation `LoopStrictKRun` where it is a hypothesis | **ANSWERED, NEGATIVELY — and that is the right answer.** The acceptance as I wrote it is not met and cannot be met; the impossibility is now a theorem. The consolation prize (`LoopStrictKRun.allVars_card_le`) is not connected to the loop (F-3) and does not bound mints (F-2). |
| 2 | make `step_empty_makeEmptyE` load-bearing; widen `substOut` with the dedup fact so `instRemove` goes live | both, and for both link branches | **DONE**, verified by my own constructor count |
| 3 | `QueueHygiene` preservation after B1 | `step_queueHygiene` + `queueHygiene_initial` + `run_queueHygiene`/`'` + `queueHygiene_binds_unbound` + `step_link_no_death` | **DONE** — the best work in the round; two qualifications (Q-1 `RunSupOk`, Q-2 the initial-state shape and the missing assembled corollary) |
| 4 | `concrete` and `learn` branches; C2's `learn` vocabulary lemma | neither branch; `learnPartitions_drawn` (new, verified against the Scala); `learnPartitions_vocab` which is not C2's clause | **PARTIAL**, honestly reported in §R3.6; the plan row overstates it (F-4) |
| 5 | add R-4 and the `step_empty_makeEmptyE`-is-a-leaf note to the closing table | round 3 is purely additive, so §"Summary of everything not proved" and §R2.6 still read as they did (R2.6 row 3 still says `QueueHygiene` preservation "is FALSE for the model as it stands", now superseded) | **NOT DONE as asked**, superseded in substance by §R3.6. Documentation only. |

## S-10. Findings, ranked

| # | severity | status | finding | fix |
|---|---|---|---|---|
| F-2 | **major** | CONFIRMED (Lean) | `mints_bounded` / `run_qsys_allVars_card_le` bound the vocabulary **snapshot**, not the number of mints; the doc comments and §R3.5.2 claim otherwise. `LoopStrictKRun.mint` has no `G ≠ G'` and `keep` permits `allVars G' ⊊ allVars G`; the loop's `qsys` really does shrink at an elimination. | Rename/reword; state the mint count as an explicit open item; if a mint budget is wanted, add a progress condition or a monotone carrier (see S-11). |
| F-4 | moderate | CONFIRMED | the plan's L5 row says C2's "vocabulary clause PROVED (`learnPartitions_vocab`)"; the report's own §R3.6 says that lemma is not C2's clause. | correct the plan row |
| F-1 | moderate | CONFIRMED | `carried_step` covers **seven** constructors with content, four vacuously and three by hypothesis — not "ten … discharged by additivity". | correct `Carried.lean:245` and §R3.6 |
| Q-1 | moderate | CONFIRMED | `run_queueHygiene` carries `RunSupOk n s`, an unproved per-state hypothesis, so "the panic has no path" is conditional on it (and on `disjRule = false`). Prose and plan row omit this. | add the qualifier wherever B1 "certification" is claimed |
| F-5 | moderate | PLAUSIBLE | `QStepDichotomy` quantifies over all `Wf` states (`Wf` = `QOk` + `LblCoh` only), which is strictly stronger than the induction needs and may well be false; no attempt was made to refute it. | see the round-4 spec |
| F-3 | minor | CONFIRMED | `LoopStrictKRun` appears nowhere outside `Carried.lean`; no `step` is shown to take a `keep` step. Correctly hedged in the report; recorded for the record. | one sentence in the report |
| Q-2 | minor | CONFIRMED | "every `Wf` initial state" (handoff, brief) is really "every state `Seed.solve` builds" (`env = {}`); and the `run … ≠ .rejected (panic …)` corollary is never assembled into one theorem. | one theorem, one word |
| N-1 | minor | CONFIRMED | §R3.6 says `redirect_breaks_carried` "shows `Q.+!`'s redirect violates [`CarrPresOn`] over `qsys` too". It compares two hypothetical successors, so it blocks the *covering-lemma route*, not `CarrPresOn` itself. | tighten one sentence |
| N-2 | minor | CONFIRMED | "the parent-already-empty half is VACUOUS at a mint" rests on `hconc : r.rhs.conc.isEmpty = false` being a hypothesis; nothing proves a mint's premise has a nonempty concrete part. I verified it against the Scala (`splitConcrete:1305`, `resolution:1777`) and it is TRUE. | add the lemma |
| N-3 | minor | CONFIRMED | `step_empty_via_makeEmptyE` adds `hsat : SSat (sys s)` over round 2's `step_empty_makeEmptyE`; harmless but unflagged. The handoff paragraph lists four new modules and omits `Draws.lean`. | one line each |

Nothing in this list is a soundness defect, and none of it invalidates a proved statement: every
theorem I checked says exactly what its text says. F-2 is the one that changes how the result
should be read.

## S-11. Round-4 specification — and whether the gap is fundamental

**It is not fundamental, but it is structural, and round 3 is what made that visible.** All three
destroyers of the syntactic guard (`substOut_breaks_carried`, `carried_not_monotone_under_deletion`,
`redirect_breaks_carried`) are consequences of the loop DELETING, and the choice of carrier system
is a genuine dilemma, now sharp on both horns:

* over a **monotone** carrier (the union of everything ever derived), (B) is free — `Carried` is
  monotone under addition, `CarrPres.of_subset` — and the mint count is exactly the vocabulary
  growth, because a fresh id enters and never leaves. But (A) breaks: the loop's mint guard is a
  lookup over the QUEUES, and a bigger carrier carries more keys, so `¬ Carried (queues) v K` does
  not give `¬ Carried (hist) v K`.
* over the **queue-visible** carrier `qsys`, (A) is within reach (§C3.2's localisation, now
  sharpened by `concCarried_parent_nonempty`) and (B) is what `redirect_breaks_carried` blocks.

That is a real trade-off, not an oversight, and it is the thing round 4 should attack directly
rather than continuing to file down one horn.

In priority order:

1. **Try to REFUTE `QStepDichotomy` before trying to prove it** (F-5). It is one state and one
   step; the counterexample machinery of `Carried.lean`/`Residual.lean` is right there, and the
   redirect is the obvious lever (a `common`/`unify` step whose re-emission of a bare concrete
   definition is redirected onto an existing carrier). Outcome either way is decisive: a
   refutation retires the residual and forces the carrier question; a failed hunt is evidence.
2. **Relativise the residual to reachable states.** `QStepDichotomy` should carry the invariants
   round 3 now supplies — `QueueHygiene` (from `step_queueHygiene`, whose hypotheses are weaker
   than `step_refines_all`'s), `Order.NoSelfUnif`, and `RunSupOk`'s per-state conjuncts — since
   `run_qsys_invariant`'s induction can thread all of them and only ever applies the dichotomy at
   reachable states. This is cheap and materially raises the chance the lemma is true.
3. **Fix F-2 at the source: state and prove a MINT COUNT, not a vocabulary snapshot.** Either add
   a progress condition to the counted step (the library's `G ≠ G'` plus "a mint adds a variable
   that no later step removes"), or count mints against the monotone history and pay for (A)
   separately. Until then, no statement in the tree bounds how many times the loop mints.
4. **Discharge `RunSupOk`** (Q-1) — it now gates the B1 certification as well as C3. It needs the
   `learn` branch's sharp vocabulary clause ("in the old vocabulary or one of the ids THIS step
   drew"), which `learnPartitions_vocab` is one strengthening away from and `learnPartitions_drawn`
   already counts. This is the highest value-per-line item left.
5. **Assemble the B1 corollary** (Q-2): one theorem, `run st0 n ≠ .rejected (panic …) s'` for the
   `Seed`-built initial state, so the certification is a statement rather than a composition the
   reader performs. And add the `hconc`-at-a-mint lemma (N-2).
6. **Corrections**: F-1, F-4, F-3, Q-1, N-1, N-3, and round-2's item 5 (mark §R2.6 row 3 and the
   round-1 closing table superseded).

If (1) refutes the dichotomy, round 5 is a different stage: the measure moves, and §C3.4's
progress table plus a combinatorial mint bound (each mint names a row; `QueueHygiene` plus the
single pass should give at most one per (premise, key)) becomes the main line rather than the
fallback.

## S-12. Verdict — **ADVANCE**

Three of the five checkpoints landed as asked (R3.2, R3.3 in full; R3.1 answered, negatively and
correctly). R3.4 is PARTIAL and says so. R3.5 is (T2) and says so, twice, including that it does
not give `Terminates`. The build, audit, axiom census, module sizes, verbatim quotations,
constructor table, draw bound and the entire witness hunt reproduce under my own re-runs, at bases
and sample points the implementer never used. The two load-bearing claims I re-derived myself
rather than reading — the B1 fix's necessity and the mint-count question — came out one for and
one against the report, and the one against (F-2) is a misreading of the round's own theorems in
the prose, not a false theorem.

The plan's L5 acceptance is still not met on two of four criteria, but every gap is recorded in
the report as accepted scope with a reason, which is the condition the review protocol sets. The
stage advances with F-1, F-2, F-4 and Q-1 to be corrected in the report and the plan row, and the
round-4 specification above.

---

# Round-4 review — 2026-09-05 (fresh reviewer)

Review of L5 round 4 against `briefs/brief-L5r4.md`, `briefs/brief-review.md` and the plan's L5
acceptance.  Pre-existing baseline **`9060fbf`** (rounds 1–3 committed); under review are the
three uncommitted modules `Loop/{Refuted,Supply,Mints}.lean`, `Rowpartition.lean` +3 import
lines, `tracker/lean/README.md` +21, the plan's L5 row, the handoff paragraph, and
`L5-TERMINATION.md`'s Round 4 section.  I read the round-1, round-2 and round-3 review sections
first; the round-3 review's F-5, S-11 and S-12 are this round's specification.

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r4/`.  Nothing outside that directory
and this file was edited; no commits, no Lean edits, no Scala edits, no sbt.

**Verdict: ADVANCE.**  Everything in the round reproduces under my own re-runs, and the two
load-bearing NEGATIVE results — the round is mostly negative results — are real: I re-derived
both refutations by evaluation rather than by reading the proofs, replayed both witnesses on the
shipped compiler at more bases than the report used, and got the compiler's *whole* trace for the
second witness byte-identical to the model's.  The one genuinely positive result, R4.2, I
instantiated myself at a state of my own choosing, including across a step that mints.  Two
documentation findings and one judgement disagreement (§T-9: the round-5 direction the report
names does not close, and I say why and what to do instead).

---

## T-1. Rebuild, re-audit, hygiene — everything reproduces

| step | command | result |
|---|---|---|
| build | `lake build Rowpartition` | `Build completed successfully (849 jobs)` — **matches** (846 before) |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3376; declarations using a non-standard axiom: 0` — **matches** |
| escape hatches | the report's own grep, `\bsorry\b\|\baxiom\b\|\bpartial\b\|native_decide\|implemented_by\|\bunsafe\b\|\bopaque\b\|Classical\|\badmit\b\|#exit` over the three modules | exit 1, **0 hits** (the only near-hit anywhere is the word "counterexample" in a `Mints.lean` comment) |
| line counts | `wc -l` | 574 + 820 + 786 = **2,180** — matches |
| `#print axioms` | my own `tmp/review-L5r4/Axioms.lean`, 39 headline theorems across all three modules | every one `[propext, Classical.choice, Quot.sound]`; **no non-standard axiom** |
| `#print axioms`, exhaustively | I also re-ran the implementer's own `tmp/L5r4/Axioms.lean` | **165 results: 157 × `[propext, Classical.choice, Quot.sound]`, 4 × `[propext, Quot.sound]`, 4 on no axioms** — exactly the report's figures.  (Their saved `axioms.txt` has only 162 lines and is stale; the *report* is right, the artefact is not, which is why re-running mattered.)  And the census is exhaustive: `grep -cE '^(theorem\|lemma) '` over the three modules gives **165**, and the set of names printed is byte-equal to the set declared |
| verbatim | my own mechanical extractor over the Round-4 section's ```lean blocks, doc comments stripped, whitespace normalised | **95 declarations quoted, 89 byte-exact, 6 mismatches — and the 6 are exactly the 6 the report marks with an explicit `…` elision.**  The report's own figure ("89 of 89 … 95 declarations … six with an explicit `…`") is exactly right |
| scope | `git diff --stat HEAD -- tracker/lean/Rowpartition/Loop/` | **empty**: no tracked `Loop/` module changed.  `Rowpartition.lean` +3/−0, README +21/−0, `L5-TERMINATION.md` **+733/−0** (purely additive), plan row, handoff |

## T-2. R4.1 — the refutation is real, and I re-derived it by evaluation

I did not take the proofs on trust.  `Carried`, `ConcCarried`, `Resolved` and `uncarried` are all
decidable/computable, so every number in §R4.1 can be checked by `#eval` against the *definitions*
rather than against the proof scripts (`tmp/review-L5r4/Check.lean`, `Check2.lean`):

| claim | report | my `#eval` |
|---|---|---|
| `Carried (qsys wS) 2 {0}` | true | `true` |
| `Carried (qsys wS') 2 {0}` | false | `false` |
| `2 ∈ allVars (qsys wS')` | true | `true` |
| `\|allVars (qsys wS)\|`, `\|allVars (qsys wS')\|` | 3, 3 | `3`, `3` |
| `uncarried wL (qsys wS) 2` → `(qsys wS') 2` | 1 → 2 | `1` → `2` |
| `hmeas wL wRho (qsys ·)` | 3 → 6 | `3` → `6` |
| `Pot wL (qsys ·)` | 6 → 9 | `6` → `9` |
| `run wS 20` trace | three `step` records | identical, `SOLVED`, `drawn = 0` |

I also checked two things the report does not:

* **the label pool really is the one the bound is stated at**: `labelsOf (qsys wS) = wL = {0}` (`decide`,
  `tmp/review-L5r4/Small2.lean`), so `qstep_pot_increases` is at the pool `run_qsys_bound` would
  take for this input, not at a convenient smaller one;
* **the potential increase is not an artefact of the one-label pool**: `Pot {0,1}` goes 18 → 23
  and `Pot {0,1,2}` goes 66 → 75 at the same step.

**The witness really is an initial state of a real seed.**  The report's `wS` is hand-built, so I
ran the model's own `Seed.solve` driver on `redir.json` at base 0
(`.lake/build/bin/looptrace tmp/review-L5r4/redir.json 0`) and got the *same three `step` records*.
The only difference between `wS` and what `solveSeed` builds is the supply — `wS` uses
`{lo := 100, hi := 100000, blk := 200000}` where `Seed.solveSeed` uses `Sup.ofSeed`.  That
difference is in the report's favour (see T-8): `Sup.ofSeed` has `blk = 0`, so it does *not*
satisfy `SupOk`, and `wS`'s supply is the realistic one for which `wS_invariants` can be proved.

**The compiler takes the same step.**  `tracker/repro/satterm/run.sh sweep json:…/redir.json 0 4 20 10`:
`SOLVED 5/5`, `drawn=0` at every base, `v0 := ConcreteRho(-,Set()); v1 := ConcreteRho(-,Set(l0)); v2 := ConcreteRho(-,Set(l0))`.
With `-Dermine.rowTrace` at base 0 the three `step` records are

```
step  <seed@0>  empty     ^free0 <- (,)                          incm=2  proc=0  t0
step  <seed@0>  unify:2   CommonPartition: ^free1 <- (^free2,)   incm=1  proc=0  t0
step  <seed@0>  concrete  ^free1 <- (,Repro.l0)                  incm=0  proc=0  t0
```

which is `wS_trace` in every field but the trace's own site/location/thread columns, exactly as
the report says.  The second record IS the redirect.

**The mechanism checks out against the Scala.**  `Constraints.scala:491-518`: `insert(p, q, graph,
process=true)` falls through `rhsLookup(p._2, req, process)` to
`insert(Partition(v, RHSAbstr(Set(p._1)), CommonPartition), q, graph, false)` — the inserted
partition `p` is **dropped** and a link into the *original* `q` is inserted instead.
`Loop/Queue.lean:174-180`'s `insertP` is that, with `insertNP` for the `process=false` recursion.
So the carrier deletion is the shipped compiler's, not a modelling artefact.

**Verdict on R4.1: CONFIRMED, and the refutation is as strong as the report claims.**  Both
disjuncts fail for a real reason (`K2StarStep.subset` for the first, `CarrPresOn` at `(v2,{l0})` for
the second); the relativisation `QStepDichotomy'` is a genuine `Prop` whose `run_qsys_bound'` is
re-proved (I read the whole chain — `qstep_pot_le'`, `run_qsys_invariant'`, `run_qsys_bound'` — and
it is the round-3 chain with `Reaches s0 ·` threaded, no weakening); and `qStepDichotomy'_false`
is discharged from `Reaches.refl`, which is the right way to do it.

## T-3. R4.2 — DONE, and I instantiated it myself rather than reading it

The statements are verbatim and the hypothesis set is what the report says.  `step_supFresh`
carries `disjRule = false`, `cseMints = false`, `SupOk s.su`, `SupFresh s.su (sys s)` and the step
— **no `Wf`, no `emptyRow = false`**, so it really is weaker than `step_refines_all`'s hypotheses.
`New Old su w := ¬ Old w ∧ Sup.Reach su w` shrinks along a draw (`New.mono`, from
`reach_fresh_mono`), which is the reason the fold's invariant can be forward-only; that is the
right repair for the fixed-`B` problem the round-3 review's F-4 identified, and `learnPartitions_new`
really is C2's sharp clause.

**Is `New Old su` the right freshness predicate against `scalaparsers.Supply`?**  I read
`parsers/src/main/scala/scalaparsers/Supply.scala` against `Loop/State.lean:178-201`:

* `fresh` returns `lo` and increments while `lo != hi`, else takes `getBlock` and sets
  `hi := result + blockSize - 1`, `lo := result + 1`.  `Sup.fresh` is that, exactly.
* so the ids a supply can still hand out are `[lo, hi)` ∪ (whatever `getBlock` will return),
  and `getBlock` is monotone (`block = result + blockSize`), so `blk ≤ z` is a **sound
  over-approximation of every future block id** — including across threads, since `Supply.block`
  is a process-global counter that only increases and the model's `blk` is a snapshot of it.
  `Sup.Reach su z := (lo ≤ z ∧ z < hi) ∨ blk ≤ z` is therefore correct for freshness (it is an
  over-approximation, which is the safe direction).
* `SupOk`'s `hi ≤ blk` is true of every live `Supply`: `create` gives `(b, b+1023)` with `block`
  already at `b+1024`, `fresh`'s block jump gives `hi = blk_old + bsz - 1 < blk_new`, and `split`
  only narrows.  ✓

**Is the panic corollary genuinely "the die test never fires", and is it vacuous?**
`Subst.scala:182-184`: `instantiateType(v, e)` dies iff `hm.types.get(v)` is `Some(_)`, i.e. iff `v`
is already bound.  The model's two panic sites (`Step.lean:88-90` in `instantiate`,
`Step.lean:137-139` in `makeEmpty`) are guarded by exactly `env.contains v`.  The three variables a
`step` can bind are the dequeued `r.lhs` (`empty`, `common`) and `r.rhs.single?` (`unify`);
`reaches_binds_unbound` gives `env.contains = false` for `r.lhs`, for **every** abstract part (hence
for `single?`), and for the `common` partner.  So yes: the theorem says the die test never fires,
at every reachable state, and `reaches_link_no_death` turns that into `instantiate` returning `.ok`.

Not vacuous — I checked by instantiating it (`tmp/review-L5r4/Vac.lean`), and at a state where
the environment is **non-empty**:

```lean
theorem wS_reaches_wS' : Reaches wS wS' := (Reaches.refl wS).tail wS_step

theorem cert_at_wS' {r : LPart} {rest : PQueue} (hdq : wS'.incm.dequeue = some (r, rest)) : … :=
  initial_binds_unbound wS_initial rfl rfl wS_supOk wS_supFresh wS_reaches_wS' hdq
```

`wS'.env.binds = [(0, .emptyRow)]`, `wS'.env.contains 0 = true`, `wS'.incm.dequeue.isSome = true`
— so the conclusion is a statement about a state that has already bound a variable, and
`#print axioms cert_at_wS'` is standard.  I also checked that the preservation composes **across a
step that mints** (`tmp/review-L5r4/Vac2.lean`): with my own `mS0_supOk` / `mS0_supFresh`,

```lean
theorem supFresh_across_the_mint :
    SupOk mS2.su ∧ (∀ z, Sup.Reach mS2.su z → Sup.Reach mS1.su z) ∧ SupFresh mS2.su (sys mS2) := …
```

goes through, and `mS1 → mS2` is the step that draws the fresh id (`mS1.su.drawn = 0`,
`mS2.su.drawn = 1`).  So `step_supFresh` is load-bearing on the `learn`/minting branch, not only
on the four branches that draw nothing.

**Verdict on R4.2: CONFIRMED.**  The round-3 review's Q-1 is closed.  Q-2's second half is closed
in a *different* and I think better form than I asked for — the corollary is semantic
(`env.contains` false at the three bindable variables) rather than a string non-equality on the
panic message — and the report says so plainly.  Q-2's first half (the scope is states with
`proc` and `env` empty, not every `Wf` state) is unchanged and correctly stated; see T-8 for the
one qualification the report does not make.

## T-4. R4.3 — the count is real, the carrier is real, the second refutation is real

**`KMintRun` is a bookkeeping of the calculus, not a restriction of it.**  This is the thing the
brief asks me to check, and it holds: `KeyedRow.lean:1340`'s `K2StarStep.allVars_cases` says every
`K2StarStep` either fixes `allVars` or adds exactly one fresh variable, and `KMintRun.keep` /
`KMintRun.mint` are precisely those two cases, so `KMintRun.step` extends any counted run by any
`K2StarStep`.  `card_eq` is then immediate and `mints_le` follows from `pot_le` + `card_eq`.  The
round-3 review's `mints_not_bounded` really is unprovable for it (`kmint_bounded` exhibits the
bound).  **What it bounds, stated exactly: the number of generative steps of the ADDITIVE keyed
calculus `K2StarStep` (`nongen`/`split`/`res`) from a satisfiable `G₀` — not of `K2StarLoopStep`
(which has the deleting concretisation), and not of the loop.**  The report is careful about this
throughout; the plan row is too.

**`Trail` and `Trail.carrPres` are what they say.**  `CarrPres.of_subset Finset.subset_union_left`
— one line, and correct, because the history only grows.

**`HistDichotomy` is sufficient**: `trail_kmintRun` → `run_hist_mints_le` → `run_sys_allVars_le`.  I
read the chain; the only subtlety is that `trail_kmintRun` re-derives a model at each step through
`pot_le`, which is legitimate.

**And it is false.**  Again I re-derived the numbers by evaluation rather than reading:

| claim | report | my `#eval` |
|---|---|---|
| `sys mS0 ∪ sys mS1 = mH1` | theorem | `true` |
| `mH1 ∪ sys mS2 = mH2` | theorem | `true` |
| `Carried mH1 1 {0}` | true | `true` |
| `hmeas wL mRho mH1`, `mH2` | 7, 9 | `7`, `9` |
| `\|allVars mH1\|`, `\|allVars mH2\|` | 5, 6 | `5`, `6` |
| `Pot mH1` → `Pot mH2` | 12 → 15 | `12` → `15` |
| `mS2.su.drawn` | 1 | `1` |

and I added the two evaluations that show the *mechanism* rather than the arithmetic:

```
Carried (qsys mS0) 1 {0}  =  true
Carried (qsys mS1) 1 {0}  =  false      -- the redirect really deletes the carrier from the queues
Carried (sys  mS1) 1 {0}  =  false
```

so the loop's own lookups legitimately miss, and the history legitimately carries: the two guards
genuinely disagree, which is `hist_qsys_disagree`.

**The compiler replay is stronger than the report claims.**  The report quotes the first four
records of `mint.json`.  I took the whole `-Dermine.rowTrace` trace at base 0 and compared it with
the model's own `Seed.solve` records: **all 20 records byte-identical** in every field but the
site/location/thread columns (the minted id is `^ambiguous(free)5` on both sides, because the model
driver uses `Sup.ofSeed ns.supplyLo = 5`; the hand-built `mS0` uses 100).  `SOLVED 10/10` on the
compiler at bases 0–9, `drawn = 1` at every base.

**Model-vs-compiler at bases the implementer did not use.**  The report compares the two hunt hits
at bases 0, 1, 2.  I ran both at bases **0–7** on each side (`tmp/review-L5r4/Cmp8.lean` vs
`run.sh sweep … 0 7`):

| seed | bases 0..7, model | bases 0..7, compiler |
|---|---|---|
| `hist44` | 5, 4, 4, 10, 24, 4, 11, 9 | 5, 4, 4, 10, 24, 4, 11, 9 |
| `hist52` | 12, 15, 11, 12, 11, 47, 12, 11 | 12, 15, 11, 12, 11, 47, 12, 11 |
| `mint` | 1 × 8 | 1 × 8 |

verdict `SOLVED` on both sides at all 24 solves, draw counts identical including the two outliers
(24 and 47) that the report's three-base sample never saw.

**Verdict on R4.3: CONFIRMED.**  `resolution_draws` and `step_drawn_le` are correct and the
"`drawn` is not a mint count" note is a genuinely useful clarification.

## T-5. The hunt — regenerated and re-run, including seeds the implementer never ran

`python3 gen.py 200 8 5 10` reproduces `Seeds.lean` **bit-for-bit** against the implementer's copy
(fixed `random.Random(i)` per seed; `seeds=199`).  Lines 1–203 of their `Hunt.lean` are that file.
I read the analyser: at each step it takes `newv = allVars (sys s') \ allVars (sys s)`, and when
that is non-empty it counts successor constraints `c` with `c.lhs = ` the dequeued lhs,
`|vset c| = 1`, exactly one new variable in `vset c`, and `Carried H c.lhs c.conc` — with `H` the
history **before** the step.  That is the right test for "the loop minted at a key the history
already carried", and the `badNamed` column is the `Cut.Named` analogue.  Re-run with my own copy
of the seeds and the same analyser, split three ways:

| population | seeds | steps | minting steps | mints at an already-CARRIED key | mints on an already-NAMED premise | FUEL / died |
|---|---|---|---|---|---|---|
| seeds 0–59 (the report's first row) | 60 | **2,027** | **216** | **2** | **0** | 0 / 0 |
| seeds 60–139 (the report's second row) | 80 | **2,696** | **297** | **13** | **1** | 0 / 0 |
| **seeds 140–198 — the implementer never ran these** | 59 | 1,784 | 194 | **5** | 0 | 0 / 0 |
| total, mine | **199** | **6,507** | **707** | **20** | **1** | **0 / 0** |

The first two rows reproduce the report's table **exactly**, figure for figure, and the two hits of
the first row are the two seeds it names (`(seed 44, step 19, v5, {l0,l2,l3,l4})` and
`(seed 52, step 39, v3, {l0,l1,l2,l3,l4})`).  My third row is new: on 59 seeds the implementer
never ran, the phenomenon reproduces at the same rate (5 of 194 minting steps, 2.6%, against
15 of 513, 2.9%), in three further seeds (145, 146, 193), and again every run terminates.

Two observations from the hit list that the report does not draw, both of which matter for round 5:

* **the same `(v, K)` is re-minted twice within one run** — seed 74 hits at `(step 97, v4, {l0,l1,l2})`
  *and* `(step 100, v4, {l0,l1,l2})`, and again at `(107, v2, {l0,l1,l2,l4})` and
  `(115, v2, {l0,l1,l2,l4})`; seed 139 at `(70, v102, {l0,l1,l3})` and `(80, v102, {l0,l1,l3})`, and
  at `(83, v103, …)` and `(95, v103, …)`.  So the multiplicity per key is already ≥ 2 in the
  measured data.  This is the fact that kills the per-key reading of §R4.4's charging (T-9);
* **the analyser undercounts**, which is in the report's favour: its `hit` filter requires the
  minted constraint's `lhs` to be the DEQUEUED lhs, so it catches `splitConcrete`'s
  `v <- (u, concr)` and `resolution`'s `v <- (z, all)` but misses `resolution`'s other two
  conclusions `x <- (z, bots)`, `y <- (z, tops)` (`Constraints.scala:1806-1808`), whose left-hand
  sides are the premises' lone variables.  The true number of mints into the guard gap is at least
  the number reported.

I also launched a scaled probe (40 seeds at 12 variables / 5 labels / 16 constraints, the same
analyser) to see whether the re-mint rate or the per-key multiplicity grows with input size, and
**cancelled it after an hour** — the model interpreter is too slow at that size for a review
budget.  Nothing in this review depends on it; it is the measurement R5.1 should do properly, with
the compiled `looptrace` executable rather than `#eval`.

## T-6. Things I ran that the implementer did not

1. **The whole compiler trace of the second witness, not the first four records.**  §R4.3.6 quotes
   four records of `mint.json`.  I took the full `-Dermine.rowTrace` trace at base 0 and the model's
   own `Seed.solve` output for the same file, and all **20 records** agree byte for byte in every
   field but the trace's site/location/thread columns — the four `learn` sub-records, the
   `unify:1 CommonPartition: ^free2 <- (^free1,)` redirect, the two `Cancellation` steps and the
   two `PartitionEmpty` steps included.  So the model and the compiler agree on the *whole* solve
   that contains the refuting mint, not just its first two steps.
2. **Bases 3–7 on both sides** for `hist44`, `hist52` and `mint` (T-4's table) — 24 extra solves,
   including the draw-count outliers 24 (`hist44@4`) and 47 (`hist52@5`), all identical.
3. **The intermediate carrier `sys`.**  R4.4 says the two failures are dual — the queue-visible
   carrier too small for (B), the history too big for (A) — and leaves the impression that
   something between them might survive.  The obvious candidate is `sys` (the queues **plus** the
   environment, which is what `step_refines_all` and `LoopStrict` are stated over).  It is refuted
   by the same two witnesses:

   ```
   Carried (sys wS)  2 {0} = true      Carried (sys wS')  2 {0} = false     Pot wL (sys ·) : 6 → 9
   Carried (sys mS0) 1 {0} = true      Carried (sys mS1) 1 {0} = false
   ```

   so **all three natural carriers fail**, and the two that fail on (B) fail at the *same* step,
   the `Q.++!` redirect.  This is in the report's favour and should be one row in §R4.5.
4. **Bigger label pools.**  `qstep_pot_increases` is stated at `wL = {0}`.  I checked
   `labelsOf (qsys wS) = wL` by `decide` (so it is the pool `run_qsys_bound` would take), and then
   that the increase is not an artefact of a one-label pool: `Pot {0,1}` goes 18 → 23 and
   `Pot {0,1,2}` goes 66 → 75 at the same step.
5. **`resolution` draws before its guards, in the Scala.**  `Constraints.scala:1774` takes
   `val z = fresh(...)` before the `tops.isEmpty || bots.isEmpty` test at 1778 and before all three
   reuse lookups at 1781/1789/1797.  `resolution_draws` is exactly that.  For contrast
   `splitConcrete` (`Constraints.scala:1301-1339`) draws only in the last branch, after all four
   lookups — which is why `splitConcrete_su` has six `SupStep.refl` cases before its `Or.inr`.
   Both match.

## T-7. Side by side, for the parts round 4 depends on

| claim | Scala | Lean | verdict |
|---|---|---|---|
| the `CommonPartition` redirect DROPS the inserted partition and inserts a link into the ORIGINAL queue | `Constraints.scala:491-518`: at 514 `rhsLookup(p._2, req, process)` → 516 `insert(Partition(v, RHSAbstr(Set(p._1)), CommonPartition), q, graph, false)`, with `q` (not the sandwiched queue) | `Queue.lean:174-180` `insertP`: `q.insertNP ⟨v, RHS.ofAbstr [p.lhs], some .commonPartition⟩` | **exact** — this is the carrier deletion both refutations turn on |
| `instantiateType` dies iff the variable is already bound | `Subst.scala:182-184`, `hm.types.get(v)` is `Some(_)` | `Step.lean:88-90` (`instantiate`) and `:137-139` (`makeEmpty`), guard `env.contains v` | **exact**; `reaches_binds_unbound` therefore is "the die test never fires" |
| `Supply.fresh` and the block jump | `Supply.scala:22-31` | `State.lean:194-199` `Sup.fresh` | **exact**; `Sup.Reach` over-approximates soundly, `SupOk` true of every live `Supply` |
| `Env.instantiate` = `subType(Map(v→e), hm.types) + (v→e)` | `Subst.scala:185` | `State.lean:340-345` | **exact**; `avoids_env_instantiate` covers both arms of the substitution |
| `splitConcrete` draws only after all four lookups | `Constraints.scala:1301-1339` | `splitConcrete_su`'s six non-drawing branches | **exact** |
| `resolution` draws before its guards | `Constraints.scala:1774` | `resolution_draws` | **exact** |

I re-read `makeEmpty`'s `(abstr - v)` (`Constraints.scala:1574`) and its Lean mirror
(`Step.lean:131`) because R4.1's witness runs the `empty` branch: the B1 fix is present on both
sides and is what makes the witness's first step erase `v0` from `v2 <- (v0, (|l0|))` rather than
loop.

## T-8. Findings, ranked

| # | severity | status | finding | fix |
|---|---|---|---|---|
| U-1 | moderate | CONFIRMED | The report is **purely additive** (+733/−0), so §C3, §"Summary of everything not proved", §R2.6 and above all **§R3.5 still read as live** — §R3.5 presents `QStepDichotomy` as "the exact remaining lemma" and §R3.5.4 as an open item, when R4.1 proves the hypothesis FALSE.  A reader who stops at §R3.5 is misled, and the round-3 review's S-9 item 5 already asked for supersession notes that are now two rounds stale.  (`Residual.lean`'s own docstrings have the same problem — "THE REMAINING LEMMA", "conditional on the remaining lemma" — but the brief forbade editing earlier modules, so that belongs to whoever commits.) | one `**SUPERSEDED BY R4.1**` line under §R3.5, §R3.5.4, §C3.1's table and §R2.6 row 3; and, at commit time, a one-line pointer in `Residual.lean`'s module note |
| U-2 | minor | CONFIRMED | §R4.2.5 says the two input hypotheses hold of "every state the compiler hands `Subst.solve`".  True — but the model's OWN seed driver is outside the theorem: `Loop/Main.lean:183` uses `Sup.ofSeed`, whose `blk = 0` makes **`SupOk` false** (`hi ≤ blk` is `lo+100000 ≤ 0`), and the satterm harness's `sin` record reports `blk = 0` too (I checked: `sin … 3 100003 3 0 1024 3`).  So `initial_binds_unbound` applies to `Replay` states from real compiler traces and to realistic hand-built supplies like `wS`, not to `json:` seed runs.  This is pre-existing and documented on `SupOk` (`RefineLearn.lean:41-44`), and R4.1's `wS` correctly uses a realistic supply — but the report's sentence reads wider than the theorem. | one clause |
| U-3 | minor | CONFIRMED (in the report's favour) | The intermediate carrier `sys` is refuted by the same witnesses (T-6.3) and §R4.5 does not say so; "the two failures are dual" understates what the round removes from the search space. | one row |
| U-4 | **judgement** | see T-9 | The round-5 direction §R4.4 names — "charge each RE-MINT to a DELETION" — does not close, for the reason §C3.3 already gives: eliminations are bounded only by `|allVars| = |allVars₀| + M`, so the inequality stays quadratic in `M` whether the charge is per elimination or per (lost carrier, key) pair.  The report's own hunt data also already refutes the per-key reading: seeds 74 and 139 re-mint at the **same** `(v, K)` twice. | see the round-5 spec in T-9 |
| N-1 | minor | CONFIRMED | `step_link_no_death` assembles "`instantiate` returns `.ok`" for the two link branches, but nothing assembles the same for `makeEmpty`'s panic arm, although `reaches_binds_unbound`'s first conjunct is exactly its guard.  One-line composition, unflagged asymmetry. | one theorem or one sentence |

Nothing in this list is a soundness defect.  Every theorem I checked says exactly what its text
says, and the two headline refutations are stronger than I expected going in.

## T-9. The judgement the brief asks for: is the round-5 direction sound?

**No — not as stated, and the report's own §C3.3 is the reason.**  I want to be precise about
this, because it is the only place I disagree with the round.

Write `M` for the number of minting steps in a run, `V₀ = |allVars (sys s₀)|`, so the vocabulary
ever in play is `V = V₀ + M`.  §R4.4 proposes: a mint at an already-carried key can only happen
once the queues have lost every carrier of that key; carriers leave the queues at a step that
binds a variable (bounded by `|allVars|` through `EnvNodup`) or at a `Q.++!` redirect (bounded by
the insertions); so charge each re-mint to a deletion, sharpened to "at most one re-mint per
(lost carrier, key) pair".  Three objections, increasing in seriousness:

1. **The elimination bound is not input-sized.**  `env_len_le_allVars` gives
   `#eliminations ≤ |allVars (sys s)| ≤ V₀ + M`.  So any charge of the form
   `M ≤ hmeas₀ + c · #eliminations` reads `M ≤ hmeas₀ + c·(V₀ + M)`, which bounds nothing for
   `c ≥ 1`.  This is exactly §C3.3's argument, and sharpening *what* is charged only changes `c`.
   To close, either the charge must be strictly sub-unit, or eliminations must be bounded
   independently of `M` — and nothing in the tree does that.
2. **The (lost carrier, key) reading makes `c` larger, not smaller.**  One elimination removes
   every queue partition mentioning the eliminated variable, and withdrawing one `ConcCarried`
   parent `mk v ∅ C` withdraws carrying for a whole slice of `L.powerset`.  So the pairs per
   elimination are `O(|queue| · 2^{|L|})`, not `O(1)`.
3. **The per-key reading is already refuted by the round's own data.**  The hunt's hit list —
   which I reproduced (T-5) — has `(step 97, v4, {l0,l1,l2})` and `(step 100, v4, {l0,l1,l2})` in
   seed 74, and `(step 70, v102, {l0,l1,l3})` and `(step 80, v102, {l0,l1,l3})` in seed 139:
   **the same `(v, K)` re-minted twice**, four times over.  So "at most one re-mint per key" is
   false in the measured data, and only the reading that objection 2 kills survives.

**And the loop supplies its own fuel.**  The reason no counting argument of this shape closes is
structural, and the two witnesses of this very round show it.  The loop mints a fresh `w` for a
key `(v, K)`; the mint installs the carrier `v <- (w, K)`; eliminating `w` — a *free* elimination,
since `w` did not exist before the mint — withdraws that carrier; and the loop may then mint again
at `(v, K)`.  Each turn of the cycle spends one binding and produces one variable, so nothing
external is consumed.  **That is a pump, and it is what a divergence witness would have to look
like.**  The evidence against it is empirical — 0 `FUEL` in ~29,000 runs across rounds 3 and 4,
plus the whole corpus — not structural; nothing in the tree forbids a third turn, and the hunt has
already measured a second.

So round 5's first job is not to prove the charging.  It is to decide whether the pump runs.

### The round-5 specification

**R5.1 — try to drive the pump; aim for W.**  The two witnesses are the two halves: `redir.json`
is the redirect destroying a carrier at step one, `mint.json` is a mint at a key the history
carries at step two.  Build a family `P(k)` of satisfiable systems in which
*mint a fresh `w_i` at `(v, K)` → eliminate `w_i` (empty or unify) so both queues lose
`v <- (w_i, K)` → mint again at `(v, K)`* repeats `k` times, and push `k` from 2 (measured) to 3
and 4.  Instrument the hunt to report, per run, the **maximum number of mints at one `(v, K)`**,
and scale the generator (8 vars/10 constraints is the current population; 12 vars/16 constraints
is the obvious next probe — T-5).  Acceptance: either a family whose draw count grows without
bound at fixed input size — `run` exhausts any fuel, replayed on the shipped compiler, which
**meets the plan's L5 acceptance by a witness** — or the measurement that the maximum is bounded,
which is R5.2's lemma in empirical form.

**R5.2 — state the charging lemma so that it can be refuted.**  "Between two minting steps at the
same key `(v, K)`, the loop binds a variable occurring in a carrier of `(v, K)` that was present
at the first mint" — prove it or refute it (`Refuted.lean`'s machinery is exactly right for the
refutation).  Then the second clause, which is where the difficulty actually lives: "and that
variable is not one the loop minted for `(v, K)`".  Refuting the second clause **is** R5.1's pump,
so the two checkpoints are the same question from opposite ends and should be run together.

**R5.3 — use the dequeue ORDER, which nothing in L5 has used.**  `LoopStrict`, `Carried`, `hmeas`,
`Pot`, `Trail` are all order-free; the priority-search queue and the type-variable graph — the one
mechanism the compiler relies on for progress — appear nowhere in any of L5's four rounds of measures.
In R4.1's witness the link `v1 <- (v2)` the redirect manufactured is dequeued **immediately** (it
is the very next `step`), so the carrier loss is transient.  If the graph priority guarantees that a
`CommonPartition` link is dequeued before any further `learn` at either endpoint, the redirect's
damage can be excluded by evaluating the potential only at "quiescent" states — states with no
pending link.  `Loop/Queue.lean`'s `dequeue` and `Loop/Order.lean` are where to look.  This is the
cheapest untried lever in the stage and I would spend a checkpoint on it before any further
carrier engineering.

**R5.4 — if neither closes, relativise the goal rather than run the same shape a fifth time.**
Deliver `Terminates` for a stated fragment — `|L| ≤ 1`, or inputs solved with `Q.++` in place of
`Q.++!` (a flag the model can carry and the differential harness can check against the compiler) —
together with the measurement of how far that fragment is from the corpus.  That turns (T2) into a
theorem with a scope instead of a fifth open item.

**Also carry**: U-1 (supersession notes — now two rounds stale), U-2, U-3, N-1.

## T-10. Acceptance criteria (plan `LOOP-MODEL-PLAN.md`, L5)

| criterion | round 3 | round 4 | evidence |
|---|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | PASS | **PASS**, unchanged | `git diff --stat HEAD -- tracker/lean/Rowpartition/Loop/` is **empty**; `Strict.lean` is not in `git status` |
| every `step` refines it under the same hypotheses as `step_refines_all` | FAIL | **FAIL, unchanged** — `common`/`empty`/`unify` only; `concrete` and `learn` still out.  Round 4 does not touch the strict refinement and does not claim to | §R4.5 |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | FAIL (T2) | **FAIL (T2)** — and now with both available routes proved impossible in Lean rather than merely open.  No witness: round 4 adds 140 seeds × ≤300 steps (4,723 steps) and 5 compiler sweeps to round 3's 28,700 runs, and **my re-run adds 59 unseen seeds (1,784 steps) and 67 further compiler solves** — 0 `FUEL`, 0 died on both | §R4.4, my T-5 |
| audit green | PASS | **PASS** — 849 jobs, `3376 / 0`, 0 `sorry`, all 39 headlines I checked on standard axioms | T-1 |

Two of four still fail, and both are recorded in the report as accepted scope with reasons —
which is the condition the review protocol sets for advancing.

## T-11. The round-4 brief's checkpoints, item by item

| # | asked | delivered | my judgement |
|---|---|---|---|
| R4.1 | refute `QStepDichotomy` and relativise, **or** prove it; "do not proceed to R4.3 on an unexamined dichotomy" | refuted over `Wf` states, the relativisation stated AND its consequence re-proved AND refuted, every round-3 invariant proved at the witness, and the potential proved to increase | **EXCEEDED.**  The brief asked for (a) *or* (b); the round delivered (a) plus the relativisation route as a working proof chain plus the stronger `Pot` result |
| R4.2 | discharge `RunSupOk` so B1's certification is hypothesis-free | `New`/`SupStep`, the three drawing rules, `learnPartitions_new`, `step_supFresh` (five branches), `runSupOk_of`, the four run-level theorems, `reaches_*`, `initial_binds_unbound` | **DONE.**  I instantiated it myself, at a state with a non-empty environment and across a minting step |
| R4.3 | a monotone carrier, a productivity condition, `mints ≤ f(s₀)` — **or** the exact blocking lemma with a hunt replayed through the compiler | **both**: the count for the calculus (unconditional), the carrier and (B) free, the loop bound from `HistDichotomy` — and `HistDichotomy` refuted, with the hunt and the replays | **DONE**, and the negative half is the more valuable one |
| R4.4 | assemble `Terminates` | not assembled — (T2), with the position stated exactly | **HONEST.**  The one thing I disagree with is the *direction* named for round 5 (T-9) |

## T-12. Verdict — **ADVANCE**

Three of the four checkpoints landed as asked, one of them beyond what was asked; the fourth is
(T2) and says so.  Nothing is unsound: the build, the audit, the axiom census, the module sizes and
the verbatim quotation count all reproduce exactly, and I re-derived the two load-bearing
refutations by **evaluating the definitions** rather than reading the proofs, replayed both
witnesses on the shipped compiler at more bases than the report used, and found the model and the
compiler agreeing on the whole 20-record solve that contains the refuting mint.  The one positive
theorem of the round, `step_supFresh`, I instantiated myself across a step that mints.

The round is mostly negative results, which is the right outcome for a round whose first
instruction was "attack the residual before relying on it", and the negative results are sharp:
`qStepDichotomy_false` retires round 3's residual at an *initial* state of a satisfiable input, and
`histDichotomy_false` retires the alternative before anyone invests in it.  My own extra checks add
a third carrier (`sys`) to the refuted list, 59 unseen hunt seeds on which the re-mint phenomenon
reproduces at the same rate, and 67 further compiler solves, none of which diverge.

My findings are two documentation items (U-1 is the one that matters — the report is additive, so
§R3.5 still reads as live although its hypothesis is now known false), one minor scope clause
(U-2), one addition in the report's favour (U-3), one one-liner (N-1), and one substantive
disagreement about where round 5 should go (U-4/T-9): the "charge each re-mint to a deletion"
direction does not close, for the reason §C3.3 already gives, and the round's own hunt data refutes
its per-key reading.  I would replace it with R5.1–R5.4 above, whose first job is to decide whether
the re-mint pump can be driven — because if it can, L5's acceptance is met by a witness rather than
a proof.

None of that blocks the round.  **ADVANCE**, with U-1/U-2/U-3/N-1 to be applied to the report and
the round-5 specification of T-9 replacing §R4.4's.

---

# Round-5 review — 2026-09-05 (fresh reviewer)

Review of L5 round 5 against `briefs/brief-L5r5.md`, `briefs/brief-review.md` and the plan's
L5 acceptance.  Pre-existing baseline **`e3cb56a`** (rounds 1–4 committed); under review are
the three uncommitted modules `Loop/{Pump,Dequeue,Fragment}.lean`, the `--mints` mode in
`Loop/Main.lean`, `Rowpartition.lean` +3 imports, `tracker/lean/README.md` +24, the plan's L5
row, the handoff paragraph, `L5-TERMINATION.md`'s Round 5 section, and the hunt tooling under
`/home/dmitry/.claude/jobs/880c725d/tmp/L5r5/`.  I read the round-1 … round-4 review sections
first; the round-4 review's **R5.1–R5.4** (§T-9) are this round's specification.

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r5/`.  Nothing outside that
directory and this file was edited; no commits, no Lean edits, no Scala edits, no sbt.

**Verdict: ADVANCE.**  Every headline reproduces under my own re-runs, and I re-derived the
three load-bearing negatives by *evaluating the definitions* (and, for the two charge
witnesses, a second time through the implementer's Python audit on the compiled model) rather
than reading the proofs.  The instrument is honest: I checked `splitMintKey` line by line
against `learnPartitions`' own call and `carrierKeys` against both minting rules in
`Loop/Rules.lean`, and confirmed against `Constraints.scala` the two structural claims the
round rests on (`destructiveSub` writes no `SubstEnv` entry; `Q.++!` puts the repairing link
at the swallowed variable's *parent*, and `reverseTopSort` serves children first).  The
compiler agrees with the model *drawn-for-drawn at all ten id bases* on the deepest pump
witness.  Findings are five documentation items and one measurement the report does not have
(the `LinkOnly` fragment is **not** empty on the real corpus — 4 of 54,199 stdlib-boot solves
and 5 of 68,533 example solves are in it, all trivially).  None blocks the round.

---

## V-1. Rebuild, re-audit, hygiene — everything reproduces

| step | command | result |
|---|---|---|
| build | `cd tracker/lean && lake build Rowpartition` | `Build completed successfully (852 jobs)` — **matches** (849 before) |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3494; declarations using a non-standard axiom: 0` — **matches** |
| grep | `sorry`/`axiom`/`partial`/`native_decide`/`implemented_by`/`unsafe`/`opaque`/`Classical`/`admit`/`#exit` over `Loop/{Pump,Dequeue,Fragment}.lean` **and** `Loop/Main.lean` | **0 hits**; the one `partial` hit is the word inside a `Main.lean` doc comment ("nothing under `Loop/` may be `partial`") |
| `#print axioms` | my own list of **all 141 declarations** of the three modules (`tmp/review-L5r5/{names.txt,Axioms.lean,axioms.txt}`), not the implementer's | 118 × `[propext, Classical.choice, Quot.sound]`, 4 × `[propext, Quot.sound]`, 5 × `[propext]`, 14 axiom-free. **No non-standard axiom.**  Of these, `theorem`s number **107**, matching the report's "105 standard, 2 axiom-free" |
| line counts | `wc -l` | 488 / 224 / 585 = 1,297 |
| diff scope | `git diff --stat` + `git status` | exactly the six tracked files the report names plus the three new modules; **`Rowpartition.lean` +3/−0** and `Main.lean` +35/−4 (the `--mints` mode only); no other Lean module, no Scala file |
| verbatim | I extracted all 14 declarations quoted in `L5-TERMINATION.md`'s round-5 `lean` blocks and matched each against the modules with whitespace normalised | **14/14 verbatim, 0 mismatches** |

Build warnings only (three `unusedSimpArgs`/`unusedSectionVars` in `Fragment.lean`, one long line
in `Rowpartition.lean`).  Cosmetic.

## V-2. R5.1 — the instrument is the rule, and the numbers reproduce exactly

### V-2a. Does `splitMintKey` count what it claims? (CONFIRMED)

I read it against `learnPartitions` (`Step.lean:264–312`) and `step` (`:319`) line by line.
`splitAt` is `learnPartitions`' own call with the same four lookups over the same queues
(`mkLookups r.lhs rest s.proc`, `findRHS3 rest s.proc SSet.empty`, `findResolvent r.lhs l
SSet.empty`, and the two flag-gated row lookups) — **identical, argument for argument**.
`splitMintKey`'s five guards reproduce `step`'s dispatch (`proc.findRHS`, `isEmpty`,
`abstr.isEmpty`, `single?`) plus `learnPartitions`' own `rhs1.abstr.contains v` self-substitution
guard, in that order.  And "the supply advanced" really is "the mint branch fired": `Sup.fresh`
(`State.lean:193`) increments `drawn` on **both** of its arms, and `splitConcrete`
(`Rules.lean:63`) calls `fresh` in its last branch and nowhere else.  So `splitConcrete_mint_eq`'s
hypothesis `(…).2.drawn ≠ su.drawn` is exactly the mint, and the theorem's conclusion — the pair
`u <- (A)`, `v <- (u, K)` — is `splitConcrete`'s last branch verbatim.

### V-2b. Does `carrierKeys` count what it claims? (CONFIRMED, with one caveat)

The report says it counts the guard keys of BOTH generative rules.  I checked `resolution`
(`Rules.lean:113–150`): its **minting** branch emits *three* partitions, and the first is
`⟨v, ⟨[z], all⟩⟩` with `v` the dequeued left-hand side and `all = C₁ ∪ C₂` — precisely the key
`resolvent all` is looked up at.  (Its three *reuse* branches emit only `x`- and `y`-headed
partitions, which `carrierKeys`' `p.lhs == r.lhs` filter correctly ignores, and they draw an id
anyway — `resolution_draws`, round 4.)  So `carrierKeys` fires on exactly the two rules' guard
keys.

**Caveat (documentation, not a defect):** `carrierKeys` is a *state-difference* detector, so it
is a **lower bound** on mints — a mint whose carrier is immediately removed by `trim` (already in
`proc`) or swallowed by the `Q.++!` redirect in the same step is not counted.  Every `cmax` in
the report is therefore a floor, which is the safe direction for a "the maximum found is 9" claim
and the unsafe direction for the "0 re-mints elsewhere" readings.  The report does not say this.

### V-2c. The measurements, re-run by me

| what | my command | my result | report |
|---|---|---|---|
| round 4's own 199 seeds regenerated | `python3 genjson.py 200 8 5 10 myg4seeds` | **bit-for-bit identical** to `g4seeds` (`diff -rq`, 0 differences) | — |
| the instrument against round 4's detector | `looptrace myg4seeds/*.json 0 3000 --mints` | `cmax = 2` at **exactly `s0074` and `s0139`**, at no other seed | matches, and these are the two the round-4 review's T-9 names |
| population J regenerated | `python3 gen5.py 3000 16 8 28 mypopJ --hubs 1 --w 0.30,0.30,0.30,0.10 --tag J --start 1000` | **bit-for-bit identical** to `popJ` | — |
| the **whole 12,000-solve J hunt**, re-run from my own seeds | `hunt.sh popJ 4 3000 mypopJ.tsv 10` | `cmax` 2:**154** 3:**42** 4:**25** 5:**4** 6:**3** 7:**3** 8:**1**; **FUEL=0, REJECTED=0**, 12,000 solves | 154 / 42 / 25 / 4 / 3 / 3 / 1, 0, 0 — **exact match, every cell** |
| the `cmax = 9` witness | `looptrace climb9.json 0 20000 --mints` | `steps=213 drawn=188 cmax=9`; bases 1,2,3 give **2, 3, 3** | matches, including the per-base figures |
| the most efficient pump | `looptrace popJ/J002680.json 3 20000 --mints` | `steps=75 drawn=24 cmax=8` | "75 dequeues and 24 ids drawn for eight mints at one key" — matches |
| the two `splitConcrete` double-mints | `looptrace popH2/H200{3470,6001}.json {3,2}` | `max=2 remint=1` on both | matches |
| the charge audit | `charge.py min2.json 2`, `charge.py minC1.json 3` | `carr=[8] bound=[8,5] charged=[8] chargedInput=[]` and `carr=[10] bound=[] charged=[] chargedInput=[]` | matches the two Lean theorems exactly |
| the whole charge audit | `tail chargeall.log` | `solves=1692 remintPairs=2743 clauseIfailures=68 clauseIIholds=10` | matches |
| seed/solve inventory | `ls`/`wc -l` over every population and `.tsv` | 199+1600+8000+3000+3000 = **15,799** seeds; 2,388+6,400+48,000+12,000+12,000 = 80,788 recorded solves + ≈19,000 climber solves ≈ **100,000** | matches |
| replay inventory | `wc -l cand-*.txt`, `grep -o 'SOLVED=…' replay-*.tsv` | 186+149+48+1 = **384** seeds, **3,840** solves, `SOLVED=3840 HANG=0 REJECTED=0` | matches |

### V-2d. The compiler, re-run by me — including the differential the report did not do

The harness's cap **does bite**, and I proved it rather than assuming it: `SatTermRepro.runCapped`
is `th.join(capMs)` with a daemon thread that keeps spinning, and

```
ERMINE_JAVA_OPTS="-Dermine.useInterface=false" tracker/repro/satterm/run.sh \
  sweep json:climb9.json 0 2 0.02 20      →  SOLVED=0 REJECTED=0 HANG=3 OOM=0
```

so at a 20 ms cap the deepest witness reports HANG at every base.  The replay script uses
`capSec = 10` (`replay-all.tsv`) and `20` (`replay-deep/J/sc.tsv`) with `maxHung = 20`, so the
sweep never stops early and a genuine hang would have been reported.  Measured wall times on the
deepest witness are 37–1,274 ms, three to four orders below the cap.

My own replays (ten bases each, cap 20 s):

| seeds | solves | SOLVED | REJECTED | HANG | OOM |
|---|---|---|---|---|---|
| `climb9`, `min2`, `minC1` | 30 | 30 | 0 | 0 | 0 |
| ten seeds sampled from `cand-deep.txt` (`popI/I001{104,139,168,177,884,902,945,991},I002037,I001206`) | 100 | 100 | 0 | 0 | 0 |

**And the model matches the compiler `drawn` for `drawn`, at every base.**  This is the check the
brief asks for and the report only did for `climb9` at base 0 and `min2` at base 2.  For `climb9`
the compiler's per-base draw counts are `188 28 81 88 54 19 86 35 106 208` and the model's are
`188 28 81 88 54 19 86 35 106 208` — **identical at all ten bases**.  For my ten sampled seeds I
compared the compiler's `DRAWN` histogram against the model's ten per-base counts as multisets:
**10 of 10 match exactly** (`tmp/review-L5r5/mysample-replay.tsv`, the comparison script in the
same directory).  So there is no base at which the compiler behaves differently from the model on
any deep seed I could find.

### V-2e. What R5.1 delivers, judged

The pump is real, it is nine turns deep, and it stops.  R5.1 asked for either a divergence or the
measurement; it delivered the measurement, with a genuinely new instrument that reads the rule
rather than re-implementing it, and with the *engine* corrected: the round-4 review guessed the
turn is paid for by binding the fresh variable, and the round shows it can also be paid for by
`makeConcrete`, which binds nothing.  **DONE, and the correction is the more valuable half.**

## V-3. R5.2 — the two refutations are of the real lemma, and I re-derived both by evaluation

### V-3a. Is `ChargeI`/`ChargeII` the lemma the round-4 review asked for? (YES)

T-9's R5.2 reads: *"Between two minting steps at the same key `(v, K)`, the loop binds a variable
occurring in a carrier of `(v, K)` that was present at the first mint"* — then *"and that variable
is not one the loop minted for `(v, K)`"*.  `ChargeI` is the first sentence and `ChargeII` the
conjunction, both over `Reaches`, exactly as asked.  Three checks that it is not a strawman:

1. **The existential ranges over `carriersOf s'`, the carriers *after* the first mint**, which
   *includes the freshly minted one.  That is the largest reading of "present at the first mint",
   so it makes the lemma **as easy as possible** to satisfy — the right direction for a
   refutation.  Had the implementer used `carriersOf s` the refutation would have been cheaper and
   weaker.
2. **`MintsAt` really is a minting step.**  `carrierKeys` only fires on a partition whose lone
   abstract variable is absent from `stateVars s`, and a variable absent before the step can only
   have come from `Sup.fresh`.  I confirmed by evaluation that the supply advances at exactly the
   four steps the two witnesses use (`pS0`: `drawn` 0→1 out of `pAt 5`, 3→4 out of `pAt 12`;
   `cS0`: 0→1 out of `cAt 4`, 1→2 out of `cAt 8`).
3. **The pairs are consecutive.**  At `pS0` the key's carrier list is `[8]` at states 6–9, `[]` at
   10–12 and `[11]` at 13 — no third id, so no mint at that key in between; likewise `cS0` is
   `[10]` at 5–6, `[]` at 7–8, `[11]` at 9.  So neither refutation smuggles in a hidden
   intermediate mint.

### V-3b. Re-derived by evaluating the definitions (CONFIRMED, twice over)

`tmp/review-L5r5/Eval.lean` evaluates `carriersOf`, `boundVars` and `su.drawn` at every state of
both witnesses, and `tmp/review-L5r5/Wfck.lean` proves what the report does not claim:

```
pS0:  carriersOf (pAt i) 2 pKey  = [3]·—  … [8] at 6..9, [] at 10..12, [11] at 13
      boundVars   (pAt 6) = [3]      boundVars (pAt 12) = [3, 8, 5]      run pS0 60 = SOLVED
      stateVars pS0 = {5,6,2,7,3,4}   (8 is NOT in it)
cS0:  carriersOf (cAt i) 4 cKey  = [10] at 5..6, [] at 7..8, [11] at 9
      boundVars (cAt 5) = boundVars (cAt 6) = boundVars (cAt 7) = boundVars (cAt 8) = [8]
      run cS0 60 = SOLVED
```

so `chargeII_false` (the only carrier is the mint's own fresh id) and `chargeI_false` (nothing at
all is bound between the two mints) are both real.  A second, independent derivation: the
implementer's own Python audit on the compiled model prints
`pair key=(2,{1,2,4,5}) steps=5->12 carr=[8] bound=[8,5] charged=[8] chargedInput=[]` and
`pair key=(4,{0,1,2,3,4}) steps=4->8 carr=[10] bound=[] charged=[] chargedInput=[]`, which agrees
with the Lean state-by-state.

**And `chargeI_false` is stronger than the report claims.**  The report says the charge fails
because no *carrier* is eliminated.  My evaluation shows the environment is **literally unchanged**
across the four dequeues between the two mints (`[8] → [8] → [8] → [8]`), so even the weakest
imaginable repair — "*some* elimination happens between two mints at one key" — is refuted by the
same witness.  That closes the whole family, not one member of it.

**I also proved the two witnesses are `Wf`** (`tmp/review-L5r5/Wfck.lean`, via `Wf.wf_seed`;
`#print axioms` gives the three standard axioms for both), so the refutations sit at well-formed
initial states of satisfiable inputs — the exact class the plan's L5 acceptance quantifies over.
The report asserts satisfiability and compiler-solvability but never states `Wf`.

### V-3c. "`destructiveSub` withdraws the carrier without a `SubstEnv` entry" — TRUE of the Scala (CONFIRMED)

`Constraints.scala:1610` `makeConcrete` → `:1632` `destructiveSub`.  Neither calls
`instantiateType`; the `implicit hm: SubstEnv` is threaded through and never written.  Compare
`instantiate` (`:1533`, `instantiateType(v, VarT(u))`) and `makeEmpty` (`:1561`,
`instantiateType(v, ConcreteRho(Loc.builtin, Set()))`), which do.  And the carrier really is
deleted: `destructiveSub`'s filter is
`{ case Partition(u, rhs, _) => u != v && !rhs.contains(v) }` (`:1653`), so `v₄ <- (w, K)` goes
when `w` is the concretised variable; `keepDefs`' `defs` filter is `abs.size >= 2` (`:1663`) and a
carrier has `abs.size == 1`, so the exemption does not save it.  On the model side the `concrete`
branch of `step` (`Step.lean:344–347`) changes `incm`/`proc` only and never `env` — faithful.

**This is the round's sharpest result.**  Every counting argument L5 has tried charges a re-mint
to an event that the environment records.  `makeConcrete` withdraws a carrier and records nothing,
so the environment is not a ledger of the loop's eliminations, and `env_len_le_allVars` — the only
elimination bound in the tree — cannot see them.

## V-4. R5.3 — `dequeue_prio_min` is the real `Q.pop`, and the refutation is of the real claim

### V-4a. Side by side with `Constraints.scala:521–560` (CONFIRMED)

`Q.pop` (`:521`) takes `priority = q.measure._1.map(_._1)` — the whole tree's minimum, because
the reducer's monoid appends `(prl min prr, tpr)` (`:449–465`) — and splits on the first prefix
whose accumulated minimum equals it, returning that element.  That is "the first element, in
queue order, of minimal `graph.sort(lhs)`", which is `Queue.lean:189`'s `dequeue` exactly
(`findIdx?` of the first element attaining `foldl Nat.min`).  `dequeue_prio_min` states the
minimality half and `dequeue_not_of_lt` its contrapositive; both are faithful and both are
*weaker* than the full order (they say nothing about the `(rhs.hashCode, lhs.hashCode)`
tiebreak that `insertSorted` maintains), which is honest — nothing in the round needs the tiebreak.

`insertP_redirect` is `PQueue.insertP` unfolded, matching `Q.insert(p, q, graph, process=true)`
(`:491–519`): `if(leq any (p == _)) (q, graph) else rhsLookup(...) match { case Some(v) =>
insert(Partition(v, RHSAbstr(Set(p._1)), CommonPartition), q, graph, false) … }`.  The redirect
inserts the link **at `v`, the variable that already held the right-hand side**, with the swallowed
`p.lhs` in its RHS — so `insertNP_graph` plus `TypeVarGraph.+` (`:408–427`, which adds `u -> vs`
and re-sorts with `reverseTopSort` whenever a child's index is not already below its parent's)
makes `p.lhs` a child of `v`.  `Q.pop` takes the minimum index, and `reverseTopSort` gives children
the smaller index.  **So "the repair is scheduled last" is a property of the Scala, not of the
model** — CONFIRMED at source level, and `rPrio : prio 1 < prio 2` is its instance.

### V-4b. Does `repairBeforeExam_false` refute what R5.3 asked? (YES)

R5.3 asked for "between a carrier's loss at the redirect and the next examination of its key, the
carrier is re-established, or a seed showing it is not".  `RepairBeforeExam` quantifies over *every*
`t` reachable from `s'` whose dequeue is at `v` — so it implies the claim at the *first* such `t`,
and the refutation instantiates `t := s'` itself, which **is** the first examination (`mS1`'s very
next dequeue is `mD` with `mD.lhs = 1`).  I re-derived every ingredient by evaluation:
`carriersOf mS0 1 rKey = [0]`, `carriersOf mS1 1 rKey = []`, `mS1.incm.dequeue` heads at `1`,
`(prio 1, prio 2) = (3, 4)`, `splitMintKey mS1 = some (1, rKey)`, `carriersOf mS2 1 rKey = [100]`,
`run mS0 60 = SOLVED`.  There is no room in the schedule for a repair: the loss and the examination
are adjacent.  **DONE, and the structural reason is real.**

One scope note the report could state more plainly: `RepairBeforeExam` is about *any* carrier loss,
not specifically a redirect loss; the witness happens to be a redirect loss, so the refutation
covers the asked-for claim and more.

## V-5. R5.4 — the fragment is real and non-vacuous, and the corpus distance is understated

### V-5a. The theorems (CONFIRMED)

`step_linkOnly` is a genuine five-branch case analysis: `common` and `unify` go through
`unifyVars_link` → `instantiate_link`; `empty` is excluded by `not_isEmpty_of_link`, `concrete` by
`abstr.elems.length = 1`, and `learn` by `single_of_link` (a lone abstract part with no labels *is*
`single?`).  The strict decrease comes from `dequeue_length_lt` (the premise is gone) plus
`instantiate_link`'s `≤` (at most one re-insertion per removal); preservation survives the redirect
because `link_commonPartition` says the manufactured partition `u <- (p.lhs)` is itself a link.
`Terminates`/`Finished` are `Order.lean:24,30` and mean what they should.

### V-5b. Non-vacuous, and the bound is tight (my own construction)

The report exhibits no `LinkOnly` state, so I built one (`tmp/review-L5r5/Link.lean`): four links
`v0 <- (v1)`, `v1 <- (v2)`, `v2 <- (v3)`, `v4 <- (v1)`.

```
qsize lS0 = 4          lS0.parts.all (link)      = true
run lS0 4 = outOfFuel  run lS0 5 = solved        boundVars = [3, 2, 1, 0]
```

so the fragment is inhabited by a state that really runs four dequeues and binds four variables,
and `linkOnly_run`'s bound `qsize s + 1` is **exactly tight**, not slack.  A second state with two
links sharing a right-hand side (which forces the `Q.++!` redirect) also solves — so the
preservation clause is exercised, not vacuous.

### V-5c. The corpus distance — the report measures its own seeds, not the corpus (FINDING)

The report says "of **15,799** seeds, **0** are `LinkOnly`, and **0** contain even a single link
constraint".  That is true and I reproduce it — but it is a statement about a generator that emits
a nonempty concrete part or ≥2 parts *by construction*.  The plan's L5 acceptance and R5.4's
"distance from the corpus" are about the corpus.  So I measured it, with
`-Dermine.rowTrace -Dermine.loadInSeries=true -Dermine.useInterface=false`:

| corpus | solves | with row constraints | **`LinkOnly`** | ≥1 link | with any concrete label at input |
|---|---|---|---|---|---|
| stdlib boot | 54,199 | 373 | **4** | 5 | **0** |
| boot + ten example modules (`Ai/Common`, `Ai/HeadcountPlan`, `PivotTest`, `GroupBy`, `Accumulate`, `SoftRelation`, `Yahoo`, `Interp`, `Sample`, `Holes`) | 68,533 | 1,895 | **5** | 6 | 1,105 |

(`tmp/review-L5r5/{boot,ex}.tsv`, parsed on `inpart` records — `Subst.scala:1215`, fields
`lhs / abstr / conc`.)  So **the fragment is not empty on real input**: four stdlib solves
(`Relation/Aggregate.e(35:11)`, `Relation/Sort.e(143:14)`, `Relation/Scan.e(132:18)` and
`(138:32)`) are `LinkOnly`, plus one more in the examples.  All five are the *trivial* instance —
one partition `a <- (b)`, one dequeue — so the report's conclusion ("the scope is small") is
right; its *number* is the wrong number and should be the corpus one.  **Documentation finding
W-1**, in the round's favour: 5 of 1,895 row-carrying corpus solves is a better statement than
0 of 15,799 synthetic seeds.

Two by-products of that measurement worth recording, because no round has them:

* **The stdlib boot's input partitions carry no concrete labels at all** (every `(#abstract,
  #concrete)` shape is `(n, 0)`).  So on `boot` neither generative rule can ever fire, and the
  step census bears it out: 228 `CommonSubexpression`, 120 `Substitution`, 28 `Cancellation`,
  16 `PartitionEmpty`, 5 `CommonPartition`, 3 `DeDuplication`, 2 `SelfSubstitution` — **zero
  `Resolution`, zero `SplitConcrete`**.  The pump is a phenomenon of the *examples* corpus and of
  synthetic seeds, not of the standard library.
* Row-carrying solves are rare and small: 1,626 of 1,895 have a single partition; the largest has
  13.

## V-6. Side by side, for the parts round 5 depends on

| claim | Scala | Lean | verdict |
|---|---|---|---|
| the mint installs the carrier of its own key | `Constraints.scala` `splitConcrete`'s last branch | `Rules.lean:63–86`, `Pump.lean:38–72` (`splitConcrete_cases`, `splitConcrete_mint_eq`) | **exact** |
| `resolution`'s mint also emits a carrier at the *dequeued* variable | `resolution`'s minting branch emits three partitions, the first headed by `v` | `Rules.lean:145–148`; `carrierKeys` (`Pump.lean:146–160`) picks up exactly `p.lhs == r.lhs` | **exact** |
| `resolution` draws before its guards, so `drawn` over-counts mints | `val (z, su) = su.fresh` precedes every branch | `Rules.lean:120`; round 4's `resolution_draws` | **exact**, and the reason `max` (splitConcrete-only) ≪ `cmax` |
| `makeConcrete` withdraws a carrier and writes no `SubstEnv` entry | `:1610`/`:1632`, no `instantiateType`; filter `u != v && !rhs.contains(v)`; `keepDefs` needs `abs.size >= 2` | `Step.lean:344–347` (`env` untouched on the `concrete` branch) | **exact** |
| `Q.pop` = first element of minimal `graph.sort(lhs)` | `:521–527` + the reducer `:449–465` | `Queue.lean:189–200`; `dequeue_prio_min` | **exact** (the model's statement is weaker than the full order — honest) |
| `Q.++!` redirects onto the holder `u` and adds the edge `u → p.lhs` | `:491–519` + `TypeVarGraph.+ :408–427` (`reverseTopSort`) | `Queue.lean:174–182`; `insertP_redirect`, `insertNP_graph` | **exact**; children-first is a Scala property |
| the label pool never grows | no rule invents a label (`merge`/`removedAll`/`inter`/`concat` only) | L1/`Wf`'s `InPool`/`LblCoh` (pre-existing) | pre-existing, relied on by the round's "directions" paragraph |

Nothing in the round does anything in a different order or over a different set from the Scala,
as far as I could check it.

## V-7. Things I ran that the implementer did not

1. **12,000 model solves of population J re-run from seeds I regenerated myself** — every cell of
   the report's J row reproduces, `FUEL=0`, `REJECTED=0`.
2. **A ten-base compiler/model draw differential on ten seeds sampled from `cand-deep.txt`** —
   100 compiler solves, all `SOLVED`, and the model's per-base `drawn` matches the compiler's
   histogram as a multiset on 10 of 10 seeds; plus the per-base identity on `climb9` at all ten
   bases.
3. **A direct test that the harness's time cap bites** (20 ms cap ⇒ `HANG=3` on `climb9`).
4. **`Wf pS0` and `Wf cS0` proved** — the report never states that its refutation witnesses are
   well-formed.
5. **A `LinkOnly` state of my own**, showing the fragment is inhabited by a state that runs and
   that `qsize s + 1` is a tight bound.
6. **The corpus measurement of the fragment's distance** (V-5c), which the report replaces with a
   measurement of its own generator.
7. **A label-pool scaling experiment on the pump** (V-8), which is the part of this review I would
   most want carried into round 6.

## V-8. The reviewer's own experiment: **the pump's depth does not scale with the label pool, and it is search-limited**

The report's closing paragraph names two untried directions.  The first is *"a measure that reads
the CONCRETE-LABEL structure of a key (every key measured in rounds 4 and 5 is a subset of the
input's label pool, which never grows, and the deepest pumps all sit at the hub's FULL row)"*.
The report's own data is consistent with a rough scaling `max cmax ≈ |L|` (nl 5→5, 6→6/7, 8→8),
which would make that direction look promising.  **That scaling is an artefact of the search
budget, and I broke it.**

I re-ran the implementer's own hill-climber at *fixed* input size (12 vars, 16 constraints, 1 hub,
4 id bases) with the label pool as the swept parameter, seed 11, ~700 iterations each:

| labels `nl` | best `cmax` found | effective pool at the best input | dequeues | ids drawn |
|---|---|---|---|---|
| **3** | **7** | `{l0,l1,l2}` — **3 labels, 8 possible keys per variable** | 71 | 30 |
| **4** | **10** | `{l0,l1,l3}` — **3 labels in use** | 133 | 51 |
| 6 | 2 (search-starved: longer runs, fewer iterations) | — | 121 | 152 |
| 8, 10 | 1 (same) | — | — | — |

and then five further independent starts at `nl = 4` (seeds 21–25, 20,000 fuel, up to 3,000
iterations), which reached `cmax` = **7, 7, 5, 10, 8** — so **two of six** independent nl=4
climbers reach 10, and none exceeds it.

All three deep witnesses are satisfiable by construction and all are **`SOLVED 10/10` on the
shipped compiler**, with the model matching the compiler's `drawn` multiset over the ten bases
exactly:

```
climb/L4/best11.json  (cmax 10)  model 21 51 28 15 11 32 15 16 10 29  compiler 10 11 15 15 16 21 28 29 32 51  SOLVED=10 HANG=0
climb/L3/best11.json  (cmax  7)  model 16 30 22 41 30 26 44 42 33 21  compiler 16 21 22 26 30 30 33 41 42 44  SOLVED=10 HANG=0
climb/D24/best24.json (cmax 10)  182 dequeues, 92 ids drawn at base 0  compiler 20 25 33 37 40 69 71 72 77 92  SOLVED=10 HANG=0
```

Two consequences, and they matter for round 6.

**(a) `cmax = 10` beats the round's headline of 9 — after twenty minutes of hill-climbing at a
*smaller* input than the round's climbers used.**  Round 4 measured 2; round 5 measured 9; I
measured 10 essentially by accident while testing something else.  The measured maximum has gone
up with every increase in search effort and has never plateaued.  That is the signature of a
search-limited quantity, not of a bounded one, and it is the strongest single piece of evidence in
the whole stage that the pump may be unbounded.

**(b) The naive form of the report's first direction is dead.**  At `climb/L4/best11.json` base 1
the loop mints **ten times at the single key `(hub, {l0,l1,l3})`** — the hub's full row, as the
report predicts — while the entire label pool in play has **three** labels, so the whole lattice of
keys at that variable has 8 elements.  Ten mints at one key with 8 keys available means **no
measure that is a function of the key's concrete-label structure and decreases once per mint can
exist**; the label structure bounds the number of *distinct* keys (correctly, by `2^{|L|}` per
variable — that part is a genuine finite quantity, since `Wf`'s `InPool` keeps the pool fixed), but
not the number of mints at one of them.  Any measure in that family has to be lexicographic with a
second component that handles re-mints at a fixed key — which is precisely the quantity R5.2 just
proved cannot be charged to an elimination.

The report's second direction — *"a bound on the supply of premise PAIRS a key can be resolved on"* —
survives this experiment and is the one I would pursue.  It has a concrete shape: `resolution`
fires on the dequeued premise `v <- (x, C₁)` together with a `proc` premise `v <- (y, C₂)` with
`C₁, C₂` incomparable, and mints at `(v, C₁ ∪ C₂)`; the mint's own carrier `v <- (z, C₁ ∪ C₂)` is
again a lone-abstract premise at `v`, whose concrete part is *strictly larger* than either parent's.
So along any chain in which one mint's carrier is a parent of the next, the key's concrete part
strictly grows and the chain has length `≤ |L|`.  The pump is exactly the case where that chain is
*not* followed — the carrier is destroyed and the same key is re-derived from *other* premises — so
the missing lemma is a bound on the number of *distinct incomparable pairs* `(C₁, C₂)` with
`C₁ ∪ C₂ = K` that are simultaneously available at `v`, together with an argument that each pair is
consumed at most once.  `learnPartitions` puts the dequeued premise into `proc` (`proc :=
s.proc.insertNP r`) and `proc` is a *set*, so a pair, once both members are in `proc`, is
re-resolvable at every later dequeue at `v` — which is where I would expect that route to fail too,
but it has not been tried and it is cheap to test empirically with the existing instrument
(`carr`/`bind` lines already carry what is needed; a `pair` line would finish it).

## V-9. And the deep pumps are **not cycles** — they are one key re-derived from a growing `proc`

The round-4 review's picture of the pump is a *cycle*: mint, free elimination, mint again, nothing
external consumed.  I instrumented what actually happens across the ten turns of my deepest
witness (`climb/L4/best11.json` at base 1; `tmp/review-L5r5/deep-{mints,trace}.txt`), reading
`incm=`/`proc=` off the `step` records:

| turn | dequeue | branch | \|incm\| | \|proc\| | carrier installed | bound since previous turn |
|---|---|---|---|---|---|---|
| 1 | 6 | learn | 10 | 6 | 14 | — |
| 2 | 14 | learn | 9 | 9 | 18 | 14 |
| 3 | 36 | learn | 13 | 13 | 24 | 9, **18**, 8, 22 |
| 4 | 60 | learn | 12 | 15 | 33 | **24**, 11, 31, 32 |
| 5 | 63 | learn | 11 | 16 | 34 | **33** |
| 6 | 67 | learn | 11 | 18 | 36 | **34** |
| 7 | 90 | learn | 7 | 18 | 47 | **36**, 5, 6, 40, 12 |
| 8 | 111 | learn | 3 | 22 | 51 | **47**, 49, 4, 10 |
| 9 | 115 | learn | 2 | 23 | 56 | **51** |
| 10 | 128 | learn | 2 | 22 | 63 | **56**, 25, 61, 62 |

Three things fall out, and none of them is in the report:

* **`proc` grows monotonically (6 → 23) and `incm` drains (10 → 2, ending at 0).**  Over the whole
  run `max|incm| = 20` from 16 input constraints and `max|proc| = 25`; on `climb9` it is
  `max|incm| = 31`, `max|proc| = 76`, `|incm|` finishing at 0.  The incoming queue never runs away
  on any deep witness I measured.
* **The ten turns are ten *different* premise pairs, not one cycle repeated.**  Each turn's
  dequeued premise is a different partition (`^free1 <- (^free2, l1 l3)`, `(^free9, l1 l3)`,
  `SplitConcrete: (^amb23, l0 l1 l3)`, …), drawn from a `proc` that has grown since the last turn.
  So the pump's fuel is `proc` growth, and `proc` grows only by `learn` dequeues, each of which
  consumes an `incm` element.
* **On *this* witness clause I of the charge holds at every one of the nine pairs** — the bolded
  ids are exactly the previous turn's carrier.  `chargeI_false` needs `cS0`'s `makeConcrete` route,
  which is rarer (68 of 2,743 audited pairs).  That is consistent with the report; it is worth
  saying because it means the *typical* pump does pay a binding per turn, and only the atypical one
  does not.

This reframes the open question in a way I think is more tractable than either direction the
report names: **the loop terminates iff the derived-partition set saturates**, and `trim` refuses
what `proc` already holds, so the only thing that can prevent saturation is that a mint's *fresh
name* makes a syntactically new partition out of a semantically old fact.  That is exactly the
pump, and it is exactly what `splitKey`/`resGuard` exist to prevent — which puts the whole question
on the reuse guards' completeness rather than on any measure.

## V-10. Acceptance criteria (plan `LOOP-MODEL-PLAN.md`, L5)

| criterion | round 4 | round 5 | evidence |
|---|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | PASS | **PASS, unchanged** — `Strict.lean` is not touched (`git status` lists no `Loop/Strict*.lean`) | V-1 |
| every `step` refines it under the same hypotheses as `step_refines_all` | FAIL | **FAIL, unchanged** — `concrete` and `learn` are still outside `LinkOrEmptyStep`; round 5 does not touch the strict refinement and does not claim to | §R5.5 |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | FAIL (T2) | **FAIL (T2)** — but the first `Terminates` theorem in the stage now exists (`linkOnly_terminates`, with a tight bound), and both remaining repairs are refuted rather than open.  No witness: ~100,000 model solves + my 12,000 re-run + my ~6,000 climber solves, 0 `FUEL`; 3,840 compiler solves + my 240, 0 `HANG` | §R5.1–R5.4, V-2, V-8 |
| audit green | PASS | **PASS** — 852 jobs, `3494 / 0`, 0 `sorry`, all **141** declarations of the three modules on standard axioms (my own census) | V-1 |

Two of four still fail; both are recorded in the report as accepted scope with reasons, which is
the condition the protocol sets for advancing.  The third criterion has moved from "open" to
"open, with four named routes proved impossible", which is progress of the right kind.

## V-11. The round-5 brief's checkpoints, item by item

| # | asked | delivered | my judgement |
|---|---|---|---|
| R5.1 | drive the pump toward `W`; instrument; generator biased to immediate elimination; replay every `cmax ≥ 3` candidate at ten bases; report hangs at once; prove `not_Terminates` if found | instrument (`splitMintKey`/`carrierKeys`/`pumpRun`/`--mints`) with `splitConcrete_mint_eq` proving it reads the rule; generator + hill-climber; **cmax 9**; ~100,000 solves, 0 FUEL; 384 seeds × 10 bases, 0 HANG; two reduced witnesses in Lean; engine corrected | **DONE**, and the engine correction (`makeConcrete` withdraws with no binding) is the round's best result.  The cap was never approached, and I verified the cap mechanism itself bites |
| R5.2 | the charging lemma over `Reaches`/`Trail`, refuted or proved | `ChargeI`/`ChargeII` stated as T-9 stated them, both refuted on satisfiable inputs the compiler solves, `env_instantiate_boundVars` kept | **DONE**, and stronger than claimed — the `cS0` witness binds *nothing at all* between two mints, so it refutes the whole family, not one member |
| R5.3 | a dequeue-order lemma repairing the redirect, or a seed showing there is none | `dequeue_prio_min`/`dequeue_not_of_lt`/`insertP_redirect`/`insertNP_graph`; `RepairBeforeExam` refuted at the *first* examination, with the graph-direction reason | **DONE.**  I confirmed the children-first property is a property of `Constraints.scala`, not of the model |
| R5.4 | `Terminates` for an explicitly stated fragment, residual stated precisely | `LinkOnly` + `step_linkOnly` + `linkOnly_terminates`/`linkOnly_run`, bound `qsize s + 1`, 21 reusable lemmas | **DONE**; non-vacuous and the bound is tight (my own witness).  The residual is measured against the wrong population (W-1) |

## V-12. Findings, ranked

**W-1 (documentation, PLAUSIBLE→CONFIRMED by my measurement).**  §R5.4 measures the fragment's
distance against the round's own generator ("0 of 15,799 seeds") when the plan and the brief ask
for the distance from the **corpus**.  Measured: **4 of 54,199 stdlib-boot solves and 5 of 68,533
boot+examples solves are `LinkOnly`** (all the trivial one-partition instance), against 373 and
1,895 solves that carry any row constraint at all.  Fix: replace the sentence with the corpus
number; the conclusion ("the scope is small") is unchanged and better supported.  Worth adding
alongside it: **the stdlib boot's input partitions carry no concrete labels at all**, so neither
generative rule ever fires on `boot` — 0 `Resolution` and 0 `SplitConcrete` records in 54,199
solves.

**W-2 (documentation).**  `tracker/lean/README.md`'s new heading reads "the pump DRIVEN (**seven**
turns)" while the body of the same block, the report and the plan row all say **nine**.  One-word
fix.

**W-3 (documentation).**  `carrierKeys` is a state-difference detector and therefore a **lower
bound** on mints: a mint whose carrier is `trim`med (already in `proc`) or swallowed by the
`Q.++!` redirect within the same step is not counted.  Every `cmax` in the round is a floor.  That
is the safe direction for "the maximum found is 9" and the unsafe direction for any reading of the
form "and no re-mint happens anywhere else".  One sentence in `Pump.lean`'s §2 doc comment.

**W-4 (in the round's favour, not stated).**  `Wf pS0` and `Wf cS0` are provable from
`Wf.wf_seed` in three lines each (`tmp/review-L5r5/Wfck.lean`, standard axioms).  Saying so puts
both refutation witnesses inside the exact class the plan's acceptance quantifies over, which is
worth the three lines.

**W-5 (in the round's favour, not stated).**  `chargeI_false`'s witness binds *nothing* between
the two mints, so it refutes not only "an elimination of a carrier is charged" but "any
elimination happens at all".  §R5.2's prose says the weaker thing.

**W-6 (measurement, NEW — see V-8).**  The report's first named direction ("a measure over the
key's concrete-label structure") is dead in its naive form: I found a satisfiable input with a
**three-label** pool on which the loop mints **ten times at one key**, more than the eight keys the
whole lattice admits at that variable.  Both witnesses (`nl = 3` giving 7, `nl = 4` giving 10) are
`SOLVED 10/10` on the shipped compiler with the model matching `drawn` at every base.  **`cmax = 10`
also beats the round's headline of 9**, at a smaller input, after twenty minutes of climbing.

None of W-1 … W-6 is a soundness defect and none blocks the round.

## V-13. The judgement the brief asks for: true, false, or open?

**My answer: genuinely open, leaning "likely true" — and, more usefully, the question has now been
narrowed to one crisp statement that a round 6 can attack directly.**

### The strongest case for TRUE

1. **The empirical base is no longer just large, it is *directed*.**  Rounds 3–5 put ~130,000 model
   solves and ~4,000 compiler solves behind it, but what matters is that round 5's search
   hill-climbs on **exactly the quantity a divergence would have to blow up** (mints at one key) at
   fixed input size.  I re-ran that search at five label-pool sizes and from five further
   independent starts at `nl = 4`, which reached 5, 7, 7, 8 and 10 — so the maximum I could reach
   at all, from six independent starts, is 10, and two starts reach it.  Directed search that plateaus is much better evidence than undirected search that
   finds nothing.
2. **There is a structural reason the loop wins on every witness measured, and it is not a
   measure.**  On the deepest runs `incm` *drains* (10 → 2 → 0 on my witness; peak 20 from 16
   inputs; peak 31 on `climb9` from 16 inputs) while `proc` accumulates monotonically.  Every
   `learn` dequeue moves one partition from `incm` to `proc`, and `trim` refuses anything `proc`
   already holds.  **So termination is exactly saturation of the derived set**, and the only thing
   that can defeat saturation is a *fresh name* turning a semantically old fact into a
   syntactically new partition.
3. **Three independent mechanisms exist precisely to stop that**: `splitConcrete`'s `splitKey`
   reuse, `resolution`'s `resGuard` reuse, and `Q.++!`'s common-right-hand-side redirect.  Round 5
   shows each can be defeated *once* (that is the pump, and that is why `cmax` can reach 10).
   Nothing in five rounds shows they can be defeated in a way that feeds itself.
4. **The additive bound already exists.**  `KMintRun.mints_le` bounds the additive keyed calculus's
   mints by `hmeas L ρ G₀` for every satisfiable `G₀`, and every loop deletion is semantically
   justified (`NoLoss`), so every fact the loop holds lies inside the additive closure.  The only
   gap is re-derivation under new names — i.e. point 2 again.

### The strongest case for FALSE

1. **The same loop provably diverges one flag away.**  `DefaultSatDiverge`'s W2 is a satisfiable
   input on which this loop does not terminate with `-Dermine.emptyRow=true`.  So termination is
   *not* a property of the calculus; it is a property of one particular guard set, and it has to be
   earned rather than assumed.
2. **Every candidate invariant has been refuted, in Lean, at satisfiable well-formed states.**
   `QStepDichotomy` and its relativisation, `HistDichotomy` and its relativisation, all three
   natural carriers (`qsys`, `Trail`, `sys`), `ChargeI`, `ChargeII`, `RepairBeforeExam` — seven
   refutations in two rounds.  When every natural invariant is false, the usual explanation is that
   the theorem is false.
3. **The measured depth has never plateaued across rounds**: 2 (round 4) → 9 (round 5) → 10 (this
   review, at a *smaller* input, in twenty minutes).  And every divergence witness this project has
   ever produced — W2, W3, G7 — was **constructed from the mechanism, not found by search**, so the
   absence of a found witness is weak evidence.
4. **`makeConcrete` withdraws a name for free and records nothing** (V-3c).  A loop that can forget
   names off-ledger admits no accounting, which is why every charge has failed and why no
   accounting-shaped proof can succeed.

### Where that leaves it

Points TRUE-2/TRUE-3 and FALSE-1/FALSE-4 are the same observation seen from two sides: the reuse
guards are the whole of the termination argument, and they are individually defeasible.  I would
put it at roughly **65/35 in favour of termination**, which is not a number anyone should act on;
the honest statement is that the question is open and that five rounds of *measures* have gone as
far as measures can go.

### What a round 6 should do — three items, in order

**R6.1 — search for a STATE CYCLE, not for a bigger `cmax`.  This is the decisive, cheap
experiment, and nobody has run it.**  If two reachable states are equal *up to a renaming that
fixes the input variables and permutes minted ids*, the run diverges and `not_Terminates` follows
by a one-line induction — no fuel exhaustion needed, and it is (W).  Conversely "no canonical state
ever repeats in 100,000 solves" is a far stronger negative than "0 `FUEL`", because it rules out
the *only* shape a divergence of a deterministic loop can have.  The instrument is a small addition
to `pumpRun`: canonicalise the state (both queues plus `env`, with ids replaced by their index in a
canonical traversal), hash it, and keep the set.  **My V-9 table is the pilot** and it already
points the right way: on the deepest witness the states are visibly *not* cycling — `proc` grows
monotonically and `incm` drains, and the ten turns are ten *different* premise pairs at one key
rather than one cycle repeated.

**R6.2 — turn "termination" into "`incm` empties", which is a statement about `trim`, not about a
measure.**  `proc` is monotone except at `instantiate`/`makeEmpty`/`makeConcrete` (all three via
`partition ruleInvolves(v)`), and each `learn` dequeue removes one `incm` element and adds one
`proc` element.  So `Terminates` ⟺ every `learn` step eventually emits only partitions `trim`
refuses ⟺ the reuse guards are eventually complete.  `Fragment.lean`'s `qsize` and its 21 size
lemmas are already the toolkit for this — `qsize` decreases on `LinkOnly` for exactly this reason.
This is the report's second named direction (the supply of premise pairs) with the right target:
not "how many pairs are there" but "does a pair ever yield a partition `trim` does not already
refuse".

**R6.3 — widen the fragment to the one the corpus actually lives in.**  `LinkOnly` covers 4 of
54,199 stdlib solves.  The natural next fragment is **inputs whose partitions carry no concrete
labels**: `splitConcrete` needs a nonempty concrete part and `resolution` needs incomparable
concrete differences, so neither can produce a partition mentioning a fresh variable, and
`makeConcrete`'s branch is unreachable — so the vocabulary never grows.  (`resolution` still draws
an id before its guards — round 4's `resolution_draws` — so the theorem is "no fresh variable
enters a partition", not "no id is drawn".)  I measured that this fragment covers **every one of
the 373 row-carrying stdlib-boot solves**: all their input shapes are `(n abstract, 0 concrete)`,
the step census has **0 `Resolution` and 0 `SplitConcrete`** records in 54,199 solves, and in all
361 solves with a saturated set **the saturated set mentions no variable absent from the input**.
That turns (T2) into "**proved for the whole standard library**, open for the examples corpus",
which is a materially better place for the stage to sit, and the proof should reuse
`Fragment.lean`'s skeleton almost unchanged.

*(I would not spend a sixth round on another measure over the same state.  Rounds 1–5 have refuted
seven of them, and the reason is now understood: every bound in the tree has the form
`X ≤ f(|allVars|)` while `|allVars| ≤ |V₀| + M`, so every charge of `M` against such an `X` is
vacuous.  The only vocabulary-independent quantities in play are the label pool and the model, so
any measure that can work must be **semantic**, and V-8 shows the naive semantic candidate — the
key's label structure — cannot carry a per-mint decrease.)*

## V-14. Verdict — **ADVANCE**

All four checkpoints landed as asked, two of them beyond what was asked (R5.2's clause-I refutation
kills the whole charging family rather than one member; R5.1's engine correction retires the
round-4 review's own guess about how the pump is paid for).  Nothing is unsound: the build, the
audit, the axiom census over all 141 declarations, the 107-theorem count, the verbatim quotation of
all 14 quoted declarations, every population and `.tsv` inventory, the whole 12,000-solve J hunt
re-run from seeds I regenerated bit-for-bit, the round-4 hit list, the charge audit, and the
compiler replays all reproduce exactly.  I re-derived the three load-bearing negatives by
evaluating the definitions and, for the two charge witnesses, a second time through the Python
audit; I confirmed the two structural claims against `Constraints.scala` at source level; I proved
`Wf` at both charge witnesses; I showed the fragment is inhabited and its bound tight; and I found
no base at which the compiler differs from the model on any deep seed — 110 (seed, base) pairs
compared `drawn` for `drawn`, all identical.

My findings are six documentation items (W-1 … W-6), two of which are in the round's favour, plus
one measurement that materially changes what round 6 should do: the report's first named direction
is dead in its naive form, and the deep pumps are not cycles but a growing `proc` re-deriving one
key — which reframes termination as saturation of the derived set rather than as any measure.

**ADVANCE**, with W-1 … W-6 to be applied to the report, the README and the plan row, and V-13's
R6.1–R6.3 offered as the round-6 specification in place of the report's two directions.

---

# Round-6 review — 2026-09-05

Reviewer: fresh agent, brief `tracker/loopmodel/briefs/brief-review.md` at `$STAGE = L5 round 6`,
`$BRIEF = briefs/brief-L5r6.md`, `$REPORT = L5-TERMINATION.md` "Round 6".  Pre-existing: `HEAD
1394df4`.  Under review: `tracker/lean/Rowpartition/Loop/{NoConc,Cycle}.lean`, `Loop/Main.lean`'s
`--cycle`, `Rowpartition.lean` +2 imports, the README block, the plan's L5 row, the new
`ROW-CONSTRAINT-STATE.md` section, the handoff edit, and the report.  Scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r6/`.  **This round claims a CERTIFICATION, so
nothing below is taken from the report: every number is one I produced myself.**

## W-1. Rebuild, re-audit, hygiene — everything reproduces, and the axiom census is mine

| check | command | result |
|---|---|---|
| build | `lake build Rowpartition` | `Build completed successfully (854 jobs)` — the report's 854 |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3611; declarations using a non-standard axiom: 0` — the report's 3611/0 |
| `looptrace` | `lake build looptrace` | `Build completed successfully (1656 jobs)` |
| hygiene | `grep -nE '\bsorry\b\|\baxiom\b\|\bpartial\b\|native_decide\|implemented_by\|\bunsafe\b\|\bopaque\b\|Classical\|\badmit\b\|#exit' Loop/{Cycle,NoConc,Main}.lean` | one hit, `Main.lean:81`, the word `partial` **inside a doc comment saying nothing under `Loop/` may be `partial`**.  Otherwise 0 |
| line counts | `wc -l` | `Cycle.lean` 375 (report: 375), `NoConc.lean` **1722** (report: 1,721 — off by one) |
| declarations | `grep -E '^(theorem\|def\|abbrev\|structure) '` | **128**: 101 `theorem` (88 `NoConc`, 13 `Cycle`), 25 `def`, 1 `abbrev`, 1 `structure`.  The report and the plan row say **127** declarations / 26 defs — off by one (the `structure CycleRep` is not counted) |
| `#print axioms`, all 128 | `tmp/review-L5r6/{decls.txt,Axioms.lean,axioms.txt}` | 99 × `[propext, Classical.choice, Quot.sound]`, 8 × `[propext]`, 4 × `[propext, Quot.sound]`, **17 axiom-free**.  **No non-standard axiom, no `sorryAx`.**  (The report's 16 axiom-free is the same off-by-one.) |
| diff scope | `git diff --stat` | exactly the seven files the report claims; every other Lean module and every Scala file untouched |

The two count slips are documentation, not substance (**W-6c** below).

## W-2. R6.3 — the fragment, checked VERBATIM, then applied to a real boot solve in Lean

### W-2a. All 48 quoted declarations are verbatim (CONFIRMED, checked mechanically)

I did this mechanically rather than by eye: a script extracts every `theorem`/`def` block from
the report's Round-6 section, normalises whitespace, and compares it with the block of the same
name in `NoConc.lean` / `Cycle.lean`.  **48 quoted declarations checked, 0 differences.**  (Two
initially flagged, `run_noConc` and `Runs`, are equation-style definitions my block extractor
mis-terminated on; read by hand they are identical too.)  I then read the load-bearing ones
line by line: `NoConc.lean:75, 125, 134, 450, 532, 573, 664, 696, 749, 1198, 1229, 1268, 1286,
1511, 1583, 1603, 1626, 1658, 1707` and `Cycle.lean:50, 88, 175, 219, 247`.  In particular `noConc_terminates_of_buildQueue`
really is

```lean
theorem noConc_terminates_of_buildQueue {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hconc : ∀ p ∈ q.elems, p.rhs.conc.elems = [])
    (hw : Wf { incm := q, proc := PQueue.empty, env := {}, su := su', ... }) :
    Terminates { incm := q, proc := PQueue.empty, env := {}, su := su', ... }
```

**Hidden hypotheses: there are none.**  I checked each of the five:

* `hdj`/`hcse` are the **shipped defaults**, not a weakening.  `Constraints.scala:768–774`:
  `mode = System.getProperty("ermine.genRules", "cut")`, `cseMints = mode == "all"` (so
  `false` by default), `disjRule = System.getProperty("ermine.disjunction","false")`.  The Lean
  `Flags` defaults (`State.lean:354–368`) agree, and `splitMints`, `resolves`, `resGuard`,
  `splitKey`, `splitRow`, `resRow`, `labelCheck`, `labelCheckEarly` are all left at their
  shipped values — the theorem restricts **nothing else**.
* `hw : Wf` is discharged, not assumed: `Wf.wf_seed` for a `json:` seed, `Wf.wf_replay` for a
  corpus segment (both call `wf_initial`, `Wf.lean:1269`).  `wf_replay`'s extra side condition
  `CsItem.SetsOk` is genuinely **vacuous on the fragment**, and I checked the reason rather than
  taking it: `Json.lean`'s `rhsBuild` folds `concRho s` into the concrete accumulator with
  `c.concat s` and nothing ever removes from it, and `conT n` adds a label, so a built partition
  with `conc.elems = []` forces every `concRho` payload in that part (and, via `rhsBuild [lhs]`,
  in a non-variable left-hand side) to be empty, and `[].Nodup` is trivial.
* `EnvNodup` and the two `KDist`s never appear in the corollary — `noConc_terminates_of_input`
  discharges them at an initial state (`envNodup_initial`, `kdist_ofList`, `PQueue.empty`).
* `Terminates` (`Order.lean:24,30`) is `∃ n, Finished (run s n)` with `Finished` false only on
  `outOfFuel`.  So a `died` counts as terminating — correct for a termination claim, and moot
  on the boot, where nothing dies.

`Runs`, `Reaches`, `Wf`, `procSys`, `sys`, `allVars`, `measure3`, `InVoc`, `KDist` are all
ordinary definitions; none is trivially satisfied.  `step_trichotomy`, `measure3_lt`,
`terminates_of_bounds_aux` and the three bounds (`env_len_le_card`, `procSys_card_le`,
`kdist_length_le`) are real proofs I read line by line, not `sorry`-shaped shells.

### W-2b. THE CHECK THAT MATTERS: the theorem instantiated at a real boot solve (CONFIRMED)

A termination theorem is worth what it can be applied to, so I applied it.
`tmp/review-L5r6/BootCheck.lean` transcribes the **largest stdlib-boot row-carrying solve**
(`modules/Relation.e(231:1)`, 13 input partitions over 30 variables) out of my own fresh trace,
builds it with `buildQueue`, and runs the corollary:

```lean
theorem bS0_terminates : Terminates bS0 :=
  noConc_terminates_of_buildQueue (cs := bParts) (su := bSu) bBuild rfl rfl bS0_conc
    (wf_seed bSeed 0 bBuild bFl bNs "boot" bSu.lo)
```

It type-checks, and

```
'RevCheck.bS0_terminates' depends on axioms: [propext, Classical.choice, Quot.sound]
'RevCheck.bS0_solved'     depends on axioms: [propext, Classical.choice, Quot.sound]
'RevCheck.bS0_nodraw'     depends on axioms: [propext, Classical.choice, Quot.sound]
```

with `bS0_conc : ∀ p ∈ bQ.elems, p.rhs.conc.elems = []` by `decide`, `bS0_size = 13` by
`decide`, `bS0_nodraw : (match run bS0 200 with | .solved s => s.su.drawn | _ => 99) = 0` by
`decide` — so the run really finishes and really draws nothing — and

```
#eval (allVars (sys bS0)).card                                   = 30
#eval measure3 (30*2^30) (30*2^30) 30 bS0 + 1  = 32166509980495978168364
```

against the 31 dequeues the model actually takes.  **The certification is applicable end to end
to real boot input, on standard axioms, and it is not vacuous.**  The bound is ≈ 3.2·10²²
for a 31-step solve, which is exactly the "order `n²·4ⁿ`, not meant to be tight" the report
states — honest, and stated.

### W-2c. "`resolution` never draws on the fragment" — checked against `Constraints.scala` (CONFIRMED)

This is the round's one correction of the round-5 review and it is right.
`Constraints.scala:1772–1775`:

```scala
if (!GenRules.resolves) Set() else (rhs1, rhs2) match {
  case (RHS(Single(x), concr1), RHS(Single(y), concr2)) =>
    val z = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
```

The `fresh` is **inside** the `Single/Single` arm, after the match, so a premise that is not
lone-abstract exits at `case _ => Set()` without drawing.  `Rules.lean:113–150` models exactly
that shape.  Two further links I checked rather than assumed:

* the dequeued premise is always `rhs1`: `Constraints.scala:1471`
  `resolution(v, rhs1, rhs2, findResolvent(s), concRow, emptyRow)` inside
  `proc.foldLeft`, and `Step.lean:283` `resolution fl v rhs1 rhs2 …` — same position, so
  `rhs1.abstrSingle? = none` really does suffice;
* the `learn` branch is reached only when `r.rhs.single? = none` (`Step.lean:343–349`, and
  `Constraints`' dispatch), and on the fragment `single? = abstrSingle?`
  (`single_eq_abstrSingle`), so the premise has ≠ 1 abstract parts.  Round 4's
  `resolution_draws` is untouched — it is about the *guards*, not the pattern — so nothing
  earlier is contradicted.

### W-2d. `unorderedHash_perm` against the real `MurmurHash3` (CONFIRMED at source level)

I extracted `scala/util/hashing/MurmurHash3.scala` from
`scala-library-2.13.18-sources.jar` (the library Scala 3.3.8 uses):

```scala
final def unorderedHash(xs: IterableOnce[Any], seed: Int): Int = {
  var a, b, n = 0 ; var c = 1
  while (iterator.hasNext) { val h = x.## ; a += h ; b ^= h ; c *= h | 1 ; n += 1 }
  var h = seed ; h = mix(h, a) ; h = mix(h, b) ; h = mixLast(h, c) ; finalizeHash(h, n)
}
...
def setHash(xs: scala.collection.Set[_]): Int = unorderedHash(xs, setSeed)
final val setSeed = "Set".hashCode
```

`Hash.lean:96–109` is that, term for term: the same four accumulators in the same order, the
same `mix / mix / mixLast / finalizeHash` tail, `setHash = unorderedHash hs setSeed`.  The three
accumulators are `+`, `^^^` and `*` on a 32-bit word — commutative and associative — which is
what `uh_fold_perm` uses (`List.Perm.foldl_eq'` plus `UInt32.{add,xor,mul}_{comm,assoc}`).  So
`unorderedHash_perm` is a true statement **about the hash the compiler actually computes**, and
`keyEq_of_eqv` (which it feeds) correctly needs the four `Wf` `Nodup`s.

### W-2e. The corpus measurement, RE-DERIVED from traces I generated myself (CONFIRMED, exactly)

I did not use the implementer's traces or scripts.  `tmp/review-L5r6/gentrace-mine.sh`
regenerates all seven groups from scratch
(`-Dermine.rowTrace -Dermine.loadInSeries=true -Dermine.useInterface=false`, one JVM per group)
and `tmp/review-L5r6/mycensus.py` is a census I wrote from `RowTrace.scala:200–250` and
`Subst.scala:1190–1216` — segmenting per THREAD at `sin` boundaries, reading the `inpart`
fields `prov / lhs / abstr / conc`.

| group | segments | row-carrying (`nRows>0`) | built ≥1 partition | **`NoConc`** | with a label | `LinkOnly` |
|---|---|---|---|---|---|---|
| `boot` | **54,199** | **383** | **373** | **373 (100 %)** | **0** | 4 |
| `top` | 92,673 | 5,424 | 5,412 | 1,670 | 3,742 | 5 |
| `Ai` | 83,942 | 4,494 | 4,484 | 1,461 | 3,023 | 5 |
| `shouldfail` | 56,032 | 647 | 605 | 442 | 163 | 4 |
| `bugs` | 54,235 | 383 | 373 | 373 | 0 | 4 |
| `guide` | 54,244 | 383 | 373 | 373 | 0 | 4 |
| `shouldfail-controls` | 54,739 | 447 | 437 | 391 | 46 | 4 |

**Every cell reproduces the report's table**, and every segment count reproduces L2-CORPUS §4a.
Three further checks of my own on the boot:

* the 373 are a **subset** of the 383 (`built but nRows==0` is 0; `rowCarrying with 0 inparts`
  is 10), and **all 383 are `NoConc`**, not just the 373;
* the 373 span **289 distinct source locations**, the largest input is 13 partitions and the
  widest right-hand side has 5 abstract parts — the population is real, not one problem counted
  373 times;
* `satWritten = 361`, `satNoConc = 361`, `satInVocOfInput = 361` — the report's 361/361 for both
  the concreteness clause and the vocabulary clause.

The **example corpus** (`loc` containing `core/examples`, which is what excludes the boot repeats):

```
example-loc solves=48583  built>=1part=9362  NoConc=2388 (25.5%)  withLabel=6974  LinkOnly=0
```

— the report's 48,583 / 9,362 / 2,388 / 6,974 / 0, exactly.  And the R6.3.4a round-7 table,
which I recomputed from the `inpart` records with my own predicates:

```
resolution cannot fire on input : 9362      splitConcrete cannot fire : 9256
NEITHER can fire                : 9256      never fired one (sat provenances) : 9146
```

— the report's 9,362 / 9,256 / 9,256 / 9,146, exactly.

**The independent corroboration is the step census, and it is decisive.**  The `step` records
(`Constraints.scala:1123`) give the DISPATCH histogram, which is a different code path from the
`inpart` records the fragment test reads:

```
boot : learn 1056  unify 38  empty 30  common 19       <- ZERO `concrete` steps
top  : learn 5167  concrete 1305  empty 76  unify 51  common 44
Ai   : learn 8295  concrete 1556  common 566  empty 497  unify 222
```

`step_noConc` predicts the `concrete` branch is unreachable on the fragment, and the boot has
exactly zero of them while the example groups have thousands.  The derived-partition provenance
histogram over the whole boot is `CommonSubexpression 221, Substitution 114, Cancellation 9` —
**0 `Resolution`, 0 `SplitConcrete`, 0 `SplitKeyed`** — against `SplitConcrete 422`,
`Resolution 106`, `SplitKeyed 23`, `SplitRow 1`, `ResolutionRow 6` on the examples.  Every one
of those numbers is the report's.

### W-2f. Ten boot solves replayed through the model and through the COMPILER (CONFIRMED)

`--cycle` and `--mints` are seed-mode only (`Main.lean:199–202`; `--replay` has neither), so I
transcoded the **ten largest distinct-location boot solves** into seeds
(`tmp/review-L5r6/bootseeds/B0*.json`, 6–13 partitions, 11–30 variables) and ran both modes:

* **50 model runs** (10 seeds × bases 0, 1, 7, 100, 999) under `--cycle`: `SOLVED` every time,
  **`drawn=0` every time**, `canon=-` and `exact=-` every time, and `states = steps + 1` in all
  50 — 11 to 38 dequeues each;
* **30 model runs** under `--mints`: `drawn=0 max=0 remint=0 cmax=0 cremint=0` in every one;
* **100 SHIPPED-COMPILER solves** — a differential the implementer did NOT do, since its compiler
  check used only synthetic label-free seeds — `ERMINE_JAVA_OPTS=-Dermine.useInterface=false
  tracker/repro/satterm/run.sh sweep json:<boot seed> 0 9 30 20` on each of the ten:

```
SUMMARY ... bases=0..9 n=10 SOLVED=10 REJECTED=0 HANG=0 OOM=0
DRAWN  min=0 median=0 max=0  histogram 0:x10          (x10 seeds, identical)
```

So on real standard-library input the **shipped compiler draws no id either**, at ten id bases,
on all ten solves.  That is the empirical half of `step_noConc`'s `s'.su = s.su`, measured on
the compiler rather than on the model.

### W-2g. The model on the corpus (CONFIRMED)

```
looptrace --replay <my boot.tsv>
#summary segments=54199 replayed=54199 skipped=0 hashdiff=0 eqdiff=0 nonpart=1009 rejected=0 fuel=0
```

## W-3. R6.1 — the cycle theorem and the search

### W-3a. `not_terminates_of_cycle` is the real lemma, and `run` is deterministic as used (CONFIRMED)

`Cycle.lean:244–258`, verbatim as quoted.  The proof is a strong induction on the fuel:
`Runs.run_eq` moves an answer at `n + k` down to one at `k`, `run_seq` transports it across
`SEq t s`, and `Runs.not_finished` kills everything below `n`.  `run` is a total function of
`step` (`Step.lean:365`) so determinism is definitional; the content is `step_decor`, the
five-branch proof that `trace`, `site` and `su0` are inert, which had to be stated because the
trace grows at every step and literal state equality is therefore vacuous.  `SEq` omits exactly
those three fields and nothing else — I checked the `State` structure against it.  Non-vacuous
and correctly oriented: the theorem needs `SEq`, i.e. an **exact** repeat.

### W-3b. The caveats are stated and correct (CONFIRMED)

Both are in `Cycle.lean`'s header and in R6.1.2, and both are right:

* the supply **must** be quotiented away — `Sup.fresh` advances `drawn` and `lo` on both arms,
  so no state that drew an id can ever recur exactly;
* the renaming quotient is **not a congruence** — `V.hashCode` IS the id, the queue is keyed on
  `(rhs.hashCode, lhs.hashCode)` (`Queue.lean:128–133`) and the dequeue priority is a
  reverse-topological index over a hash-ordered node set, so permuting mints can change the next
  dequeue.  The direction used is the sound one ("no canonical repeat ⇒ no exact repeat"), and
  the report says so rather than hiding it.

### W-3c. The search re-tabulated from the raw `.tsv`, and re-run (CONFIRMED)

I ignored `cycsum.py` and tabulated the fifteen gzipped population files with my own `awk`
(steps/states/drawn/verdict columns, plus the `states == steps + 1` invariant):

```
r5-popA..G  800 each   r5-deep 1830   r5-popH2 48000   r5-popI 12000   r5-popJ 12000
popK 24000  popL 16000  popM 10000    popNC 5244
TOTAL solves=134674  canonical states=3082009  drawn=1128553  fuel=0  rejected=0
canon hits = 0   exact hits = 0   states != steps+1 : 0   (in all 134,674)
```

Every cell of the report's table, including the max-dequeue column (340 on `r5-deep`) and
`popNC`'s **drawn = 0**.  Then I re-ran it:

* `huntc.sh` on round 5's `popA` from the original seed directory produced a file **identical
  after sorting** to the implementer's `r5-popA.tsv.gz` — bit-for-bit reproducible;
* a **fresh hunt of my own** at `--start` values nobody has used (900000/910000/920000), three
  populations with different shapes and biases (`popR1` 1,600 seeds 12/6/16 hubs=1 w=.30/.30/.30/.10 ×4 bases;
  `popR2` 1,200 seeds 14/6/24 hubs=2 w=.40/.25/.20/.15 ×4; `popR3` 800 seeds 18/9/32 hubs=1
  w=.25/.35/.30/.10 ×6 at fuel 5,000), plus the 183 deep candidates at 10 bases re-run.
  Result below in W-5.

## W-4. R6.2 — the recast, the refutation, and how sharp the residual really is

`Stuck`, `step_done_dequeue`, `terminates_iff_stuck`, `terminates_iff_incm_empties`,
`trim_notContains`, `GuardComplete`, `guardComplete_false`, `ProcSaturates`,
`terminates_of_saturation` — all verbatim as quoted (`NoConc.lean:767–880`).

* `terminates_iff_incm_empties` is a genuine iff with one hypothesis, "no reachable state dies",
  which is honestly labelled and is what rounds 3/4 supply on satisfiable input.  (T1) for the
  recast: **agreed**.
* `guardComplete_false` is a one-line application of round 5's own `pStep5`/`pMint5`/`pStep12`/
  `pMint12` at `(v2, pKey)`.  It is the real gap and the report names it as such.
* **`terminates_of_saturation` is NOT sharper than round 5's residual in the general case, and
  the report's own §R6.4 says so only obliquely.**  The lemma carries
  `hnc : ∀ t, Reaches s t → NoConc t` — it is a *fragment* statement, and on the fragment
  `ProcSaturates` is already proved by `procSys_card_le`, so `terminates_of_saturation` adds
  nothing there beyond `noConc_terminates`.  Off the fragment it does not apply at all, because
  `measure3_lt` needs `step_trichotomy` needs `NoConc` to kill the `concrete` branch.  So R6.2's
  "residual, assembled" is a **restatement inside the fragment**, not a general residual.  The
  general residual that survives is the unquantified one in `terminates_of_bounds` (three bounds
  ⇒ `Terminates`, no `NoConc`… except that `terminates_of_bounds` *also* takes `hnc`).  This is
  **finding W-6d**: documentation, in the round's disfavour, and the honest label for R6.2's
  second half is "(T2), and the residual is fragment-relative".

## W-5. Things I ran that the implementer did not

1. **`noConc_terminates_of_buildQueue` instantiated at a real 13-partition stdlib-boot solve**
   (W-2b): `Terminates bS0` on `[propext, Classical.choice, Quot.sound]`, with the run's own
   31 dequeues and `drawn = 0` decided, and the fuel the theorem hands over evaluated
   (3.2·10²² for `n = 30`).  No round has instantiated the certification before.
2. **100 SHIPPED-COMPILER solves on ten real boot inputs** at ten id bases (W-2f):
   `SOLVED=10 HANG=0` and `DRAWN 0:x10` on each.  The round's own compiler check used synthetic
   seeds only.
3. **A census written from the trace format rather than reused** (W-2e), reproducing all 34
   cells of the two corpus tables and both round-7-pointer rows.
4. **The dispatch histogram** — a code path neither the report's census nor mine reads for the
   fragment test — confirming 0 `concrete` steps on the boot against 1,305/1,556 on the examples.
5. **The stdlib-under-user-programs question, measured** (see W-6e): across all six example
   groups, **2,322 row-carrying solves whose `loc` is a stdlib module — 2,322 of 2,322 `NoConc`,
   0 with a label.**  So the certification is not fragile to being reached from user code.
6. **A fresh cycle hunt of my own** at unused `--start` values and different biases, and the
   deep candidates re-run.
7. **The `incomplete/` corpus, which the round skipped**, traced per file under a 90 s cap
   (all 34 `.e` modules, 1.85 M segments) and censused — W-7.
8. **The round-7 pointer put to the test**: 111 corpus solves **refute** the naive widening
   ("neither generative rule can fire on the input" is not closed under `step`), and the honest
   ceiling for a vocabulary-fixed fragment is 97.6 %, not 98.9 % — W-9.
9. **A mechanical verbatim check of all 48 quoted declarations** (W-2a), rather than reading a
   sample of them.
10. **A 10-base compiler/model draw differential on my own deepest witness** — 443 dequeues,
   1,382 draws, ten per-base draw counts identical on both sides (W-8).

## W-6. Findings, ranked

None is a soundness defect; none blocks the round; the certification stands.  W-6a and W-6b are
the two that touch a *claim* rather than a count, and both should be fixed before this is
committed.

* **W-6a (CONFIRMED, a claim that is false as written).**
  `Cycle.lean:315–325` says of `rawState`: *"Two dequeues with the same `rawState` are `SEq` in
  everything `canonState` records plus the supply, which is what `not_terminates_of_cycle`
  needs"*, and R6.1.2(b) says *"an exact repeat (`rawState`) is a proof by
  `not_terminates_of_cycle`"*.  **It is not.**  `rawState` renders `incm.elems`, `proc.elems`,
  `env.binds` and `su.{lo,hi,drawn}` — and `PQueue` is `⟨elems, graph⟩` (`Queue.lean:120–122`)
  with `Graph = ⟨nodes, edges, sort⟩` (`:59–62`), while `SEq` demands `s.incm = t.incm`, i.e.
  **the graph too**; `Sup` also has `blk`/`bsz` (`State.lean:178–186`) and `SEq` also demands
  `flags` and `names`.  The graph is not a decoration: `PQueue.dequeue` reads `graph.sort` for
  the priority, and the graph accumulates nodes and edges that deletions from `elems` do not
  remove — so two states with identical `elems` and different graphs are perfectly possible and
  would be reported as an "exact repeat" that is **not** `SEq`.
  *Impact: none on this round's result*, because the direction the search is used in is the
  other one — `rawState`/`canonState` are functions of the state, so an `SEq` repeat implies a
  `rawState` repeat implies a `canonState` repeat, and **0 hits still means 0 `SEq` cycles**.
  But a hit would have been a candidate needing the graphs compared, not "a proof", and the
  report and the module doc-comment both say "a proof".
  *Fix:* one sentence in R6.1.2(b) and in `rawState`'s doc-comment — "`rawState` omits the
  queue graphs, `Sup.blk/bsz`, `flags` and `names`, so an exact hit is a candidate whose `SEq`
  has to be checked" — or render the graphs (cheap: `graph.sort` is the only part the dequeue
  reads).
* **W-6b (CONFIRMED, a claim that is too strong in four documents).**  "**No id is drawn**"
  is true of the LOOP and false of the SOLVE, on 8 of the 373 boot solves.  `PQueue.build`'s
  `aux` mints a name for a part with a **non-variable left-hand side** — `Constraints.scala:661–662`
  `case Part(loc, lhs, rhs) => // lhs is not a variable / val v = fresh(loc, none, …)`, modelled
  at `Json.lean:155–167` as `| lhs => let (v, su) := su.fresh` — and eight stdlib-boot inputs have
  exactly that shape — a `ConcreteRho` with an EMPTY field set on the left:

  ```
  modules/Relation/Op.e(114:31) (142:43) (1:1) (129:49) (170:21) (165:3)
  modules/Relation.e(85:33) (88:34)          scon payload:  part  c|v111536|v111535
  ```

  I proved it rather than inferred it (`tmp/review-L5r6/BuildDraw.lean`, all on standard axioms):

  ```lean
  theorem cDrawn  : cSu'.drawn = 1 := by decide          -- buildQueue DREW, before the loop
  theorem cDrawn0 : cSu.drawn  = 0 := by decide
  theorem cS0_loop_nodraw : (match run cS0 100 with | .solved s => s.su.drawn | _ => 99) = 1
  theorem cS0_terminates  : Terminates cS0               -- the theorem still covers it
  ```

  **Nothing in the theorem is affected** — `noConc_terminates_of_buildQueue` starts the state at
  `su'`, i.e. *after* the build, and `hconc` is about the built queue, so the 8 are covered like
  the other 365; `NoConc` survives because a `concRho ∅` contributes no label; and `inVoc_self`
  takes the vocabulary of the built state, which already contains the minted name.  It is the
  *prose* that is wrong.  Report R6.3's headline ("so no id is drawn"), the README ("so no id is
  drawn at all"), the plan's L5 row ("**no id is drawn at all**") and the handoff all need the
  qualifier; `ROW-CONSTRAINT-STATE.md`'s "the solver is proved … to draw no id while doing so"
  needs it most, because "the solver" reads as including `PQueue.build`.  R6.3.4's own summary
  sentence ("on those solves **the loop** draws no id") is already correct — that is the wording
  the other four should adopt.  My W-2f measurement is unaffected: those seeds are transcoded
  from post-build `inpart` records, so their left-hand sides are variables and `drawn = 0` there
  is the loop's own figure.

* **W-6c (documentation, minor, CONFIRMED).**  `Loop/NoConc.lean` is **1722** lines, not 1,721,
  and the two new modules hold **128** declarations (101 theorems, 25 defs, 1 abbrev, 1
  structure), not 127 / "26 defs".  The axiom histogram is therefore 99/8/4/**17**, not …/16.
  Report §R6.5 item 2 and the plan's L5 row.
* **W-6d (documentation, in the round's disfavour, CONFIRMED).**  R6.2's residual is
  **fragment-relative**: `terminates_of_saturation` carries
  `hnc : ∀ t, Reaches s t → NoConc t`, and so does `terminates_of_bounds`.  On the fragment
  `ProcSaturates` is already a theorem (`procSys_card_le`), so the "residual, assembled" adds
  nothing there; off the fragment neither lemma applies, because `measure3_lt` needs
  `step_trichotomy` needs `NoConc` to kill the `concrete` branch (`NoConc.lean:1478–1481` is
  literally where the `concrete` case is discharged by `exfalso`).  The report's
  "(T2) for the residual **in the general case**" should read "(T2), and the residual is
  fragment-relative".  It is not sharper than round 4's or round 5's residual off the fragment.
* **W-6e (scope, in the round's FAVOUR — belongs in the certification paragraph, CONFIRMED).**
  `ROW-CONSTRAINT-STATE.md` currently certifies *the boot*.  I measured the stronger reading and
  it holds: across the six example groups there are **2,322 row-carrying solves whose `loc` is a
  stdlib module** (not only the boot's own 373 repeated six times), and **2,322 of 2,322 are
  `NoConc`, 0 with a concrete label**; adding the boot's own 373 and the `incomplete/` group (W-7) makes it **15,377 of
  15,377** across all 41 traces.  So "every row-constraint solve the standard library performs — booting alone, or
  while any corpus program is loaded — is inside the fragment" is a measured statement, and a
  materially better one than the paragraph makes.
* **W-6f (scope caveat the report flags; now closed — see W-7).**  The `incomplete/` group was
  excluded.  I traced all 34 of its `.e` modules and censused them; it does not disturb the
  certification.
* **W-6g (instrument gap, for a round 7).**  `--cycle` and `--mints` exist only on the `json:`
  seed path (`Main.lean:199–202`); `replayMain` has neither, so a corpus segment cannot be
  cycle-searched or draw-counted without transcoding it into a seed (which is what I had to do
  in W-2f).  Wiring `cycleRun` into `replayMain` would let the next round run the cycle detector
  over the 2.3 M corpus segments directly.

## W-7. The `incomplete/` corpus — measured, since the round skipped it


The report excludes `core/examples/incomplete/` ("non-terminating by design, ~8 MB/s of trace")
and says so.  Disk allowed it, so I ran it: `tmp/review-L5r6/genic.sh` traces all **34** `.e`
modules of the group, one JVM per file, 90 s cap, same flags.  **All 34 finished inside the cap,
`rc=0`**, ~17 MB of trace each; `tmp/review-L5r6/inccensus.py` censuses them.

```
files=34  segments=1,851,131  row-carrying=14,315  built >=1 partition=13,965
  NoConc = 13,107   with a concrete label = 858
  of which loc is a STDLIB module : 12,682 built, 12,682 NoConc  (100 %)
  of which loc is under incomplete/: 1,283 built, 425 NoConc, 858 with a label
  dispatch: learn 40,858  unify 1,381  empty 1,283  common 991  concrete 615
  provenances: CommonSubexpression 8,344  Substitution 4,576  Cancellation 346
               SplitConcrete 285  Resolution 91  SplitKeyed 26  ResolutionRow 12
               CommonPartition 1
```

(My 14,315 row-carrying against L2-CORPUS's 14,703 is the 34 `.e` modules against L2's 35-file
group definition; the group also holds 6 `.slow` modules the sweep excludes.)

**Two conclusions, both in the round's favour.**

1. **The stdlib half of the hardest corpus group is 12,682 of 12,682 `NoConc`.**  Nothing in
   `incomplete/` — the star-join blowups, the label-helper modules, the unsoundness witnesses —
   pushes a labelled row constraint into a stdlib-located solve.  With W-6e this makes the
   stdlib figure **15,377 of 15,377 across all 41 traces (the 7 groups + the 34 `incomplete/`
   files).**
2. **The `incomplete/` modules' OWN solves are where the fragment is thinnest** — 425 of 1,283
   (33 %), against 25.5 % on the rest of the examples — and the labelled inputs concentrate in
   the label-heavy modules the group exists for (`RunCalibration.e` 129, `np01_add_or_recompute.e`
   104, `RevenueShare.e` 95, `gu08_label_inline.e` 68).  That is the right shape: the group was
   built to be hard, and it is outside the fragment.

So the caveat the report records is real but harmless to the claim, and the claim's scope is
larger than the report states.

## W-8. The cycle search, re-run from scratch with populations of my own

`tmp/review-L5r6/hunt/fresh.sh`, seeds nobody has used (`--start 900000/910000/920000`), three
shapes and three different bias weights, plus the 183 deep candidates re-run at ten bases:

| population | shape | solves | canonical states | max dequeues | ids drawn | repeats |
|---|---|---|---|---|---|---|
| `popR1` | 1,600 seeds 12 var / 6 lbl / 16 con, hubs 1, w .30/.30/.30/.10, ×4 bases | 6,400 | 135,345 | 184 | 47,755 | **0** |
| `popR2` | 1,200 seeds 14/6/24, hubs 2, w .40/.25/.20/.15, ×4 | 4,800 | 143,334 | 212 | 60,767 | **0** |
| `popR3` | 800 seeds 18/9/32, hubs 1, w .25/.35/.30/.10, ×6, fuel 5,000 | 4,800 | 147,863 | **443** | 89,967 | **0** |
| `mydeep` | the 183 deep candidates × 10 bases | 1,830 | 93,457 | 340 | 54,383 | **0** |
| **total** | | **17,830** | **519,999** | 443 | 252,872 | **0**, 0 `FUEL`, 0 `REJECTED` |

`states == steps + 1` in all 17,830, and `mydeep.tsv` is **identical after sorting** to the
implementer's `r5-deep.tsv.gz`, as `myA.tsv` is to `r5-popA.tsv.gz`.  So the harness is
deterministic and the round's own 134,674 runs are reproducible; mine are 17,830 more, on
populations chosen to be *larger and more label-rich* than any the round used.

**And `popR3` produced the deepest run this stage has ever recorded**, which is worth its own
line because rounds 4 and 5 were a hunt for exactly this:

```
seed R3920797 (18 vars, 9 labels, 32 constraints)
  model  base=0 steps=356 drawn=1382   base=2 steps=443 drawn=1351   (canon=- exact=- in both)
  compiler, bases 0..9: SOLVED=10 REJECTED=0 HANG=0 OOM=0
    DRAWN histogram 3:x1 13:x1 22:x1 104:x1 110:x1 137:x1 153:x1 214:x1 1351:x1 1382:x1
```

The model's ten per-base draw counts are **exactly** the compiler's ten — `{3, 13, 22, 104, 110,
137, 153, 214, 1351, 1382}` on both sides.  Round 5's deepest witness drew 208; this one draws
**1,382** and takes **443** dequeues, and it still terminates on both sides with no repeat of any
kind.  That is the strongest single piece of evidence the negative has: the search was pushed an
order of magnitude past where the previous rounds plateaued, and the answer did not change.

## W-9. The round-7 pointer, evaluated — and the naive fragment is REFUTED by the corpus

R6.3.4a offers a round 7 the target "no generative rule ever fires", pointing at 9,256 of 9,362
(98.9 %) example solves where neither rule can fire **on the input**, and correctly says the gap
is a *preservation* question.  I put a number on it, which the report does not:

```
example row-carrying solves                       : 9,362
  neither generative rule fireable on the INPUT   : 9,256
  ...yet a generative rule FIRED during the run   :   111    <-- the invariant fails, 111 times
  rules that fired anyway: SplitConcrete 230, Resolution 106, SplitKeyed 23, ResolutionRow 6, SplitRow 1
  DERIVED partitions that unblock splitConcrete, by provenance:
      Substitution 164, CommonSubexpression 37
```

So the report's diagnosis is exactly right and now has witnesses: `substitution` and
`commonSubexpression` manufacture partitions with a nonempty concrete part **and** two or more
abstract parts, which is precisely `splitConcrete`'s firing shape, and they do it on **111 real
corpus solves**.  **A round 7 therefore cannot simply widen `NoConc` to the input-only
condition — as an invariant it is false, and the corpus refutes it.**

The honest ceiling for a *closed* fragment is lower than 98.9 %, and I measured that too:

```
example row-carrying solves with a saturated set  : 9,340
  saturated set introduces a variable absent from the input :   220  (2.4 %)
  vocabulary demonstrably NOT grown                          : 9,120  (97.6 %)
```

**97.6 %**, not 98.9 %, is what "the vocabulary is fixed" — the property `noConc_terminates`
actually uses — is worth on the examples.  My recommendation for the round-7 target is therefore
**"no id is ever DRAWN into a partition", i.e. the vocabulary-fixed condition, aimed at 97.6 %**,
rather than "no generative rule fires", and the honest framing is that the missing 2.4 % is
where the whole open problem lives.  Three further observations for whoever writes that brief:

1. The round is right that `measure3_arith`, `env_len_le_card`, every `KDist` lemma,
   `unorderedHash_perm` and `keyEq_of_eqv` are stated for arbitrary states and transfer.
2. It is also right about the three things that do not.  I checked the third one at source:
   `NoConc.lean:1478–1481`, inside `step_kdist`, discharges the `concrete` dispatch branch by
   `exfalso` from `isEmpty_of_nil hrC` — so a wider fragment has to handle `makeConcrete`, which
   `StrictBound.lean` already flags as the unbounded branch.  That is a real obstacle, not a
   formality.
3. **W-6g's instrument gap is the cheapest thing a round 7 could fix first**: with `cycleRun`
   wired into `replayMain` the cycle detector and the draw counter could be run over all
   2,355,430 corpus segments instead of over transcoded seeds.

## W-10. Side by side, for the parts round 6 depends on

| claim | Scala | Lean | verdict |
|---|---|---|---|
| `resolution` draws INSIDE the lone-variable arm, so a non-lone premise costs no id | `Constraints.scala:1772–1775` (`case (RHS(Single(x),c1), RHS(Single(y),c2)) => val z = fresh…`) | `Rules.lean:113–150`; `resolution_noConc` | **exact** — the round's correction of the round-5 review is right |
| the dequeued premise is `resolution`'s `rhs1` | `:1471` inside `proc.foldLeft` | `Step.lean:283` | **exact** |
| `splitConcrete` refuses an empty concrete part at its first guard | `def splitConcrete`'s leading `if` | `splitConcrete_noConc` | **exact** |
| the `learn` branch is entered only when `rhs.single?` is none | `incorporateAll`'s dispatch | `Step.lean:319–360` | **exact**, and `single_eq_abstrSingle` closes the fragment's case |
| `cseMints = false`, `disjRule = false` are SHIPPED, not assumed | `Constraints.scala:768–774` | `State.lean:354–368` | **exact**; no other flag is restricted |
| `MurmurHash3.unorderedHash` = sum / xor / product, `setHash = unorderedHash(_, "Set".hashCode)` | `scala-library-2.13.18-sources.jar`, `MurmurHash3.scala` | `Hash.lean:96–109`; `unorderedHash_perm` | **exact**, checked term for term against the library source |
| `Q.insert` refuses a duplicate at the same search key, one-directionally | `PQueue.+`/`+!` | `Queue.lean:166–188`; `KRel`/`KDist` symmetrised | **exact**; `kdist_insertP` covers the `++!` redirect |
| substituting branches re-establish the queue invariant by RE-INSERTION, not by preservation | `instantiateType` / `makeEmpty` partition-and-requeue | `kdist_instantiate`, `kdist_makeEmpty` (`concatP` over the filtered queue) | **exact**, and the right shape |
| `concRho` payloads are sets, so `CsItem.SetsOk` is vacuous on the fragment | `Json.lean`'s `rhsBuild` accumulates `c.concat s` and never removes | `Wf.lean:1356–1382` | **exact** (I verified the implication rather than taking it) |
| `SEq` = everything `step` reads | `State` has 9 fields; 3 are records-only | `Cycle.lean:50–52`; `step_decor` | **exact** |
| `rawState` determines `SEq` | — | `Cycle.lean:315–325` | **NOT exact — W-6a** |
| "no id is drawn" | `Constraints.scala:661–662`, `PQueue.build`'s `aux` mints for a non-variable lhs | `Json.lean:155–167`; `cDrawn : cSu'.drawn = 1` | model **exact**; the CLAIM is true of the LOOP, false of the SOLVE on 8 of 373 — W-6b |

Nothing in the round does anything in a different order or over a different set from the Scala.

## W-11. Acceptance criteria (plan `LOOP-MODEL-PLAN.md`, L5)

| criterion | verdict | evidence |
|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | **PASS**, unchanged | `Strict.lean` untouched (`git diff --stat`) |
| every `step` refines it under `step_refines_all`'s hypotheses | **FAIL**, unchanged | `concrete` and `learn` are still outside `LinkOrEmptyStep`; round 6 does not touch the strict refinement, and does not claim to |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | **PARTIAL** (was FAIL) | neither disjunct is met in full.  What is met: `Terminates` with an explicit fuel for the `NoConc` fragment, which `ssat_of_no_conc` shows lies **entirely inside** the satisfiable class the criterion quantifies over — so this is a genuine sub-case of the criterion, not a sideways restriction — and which covers **100 % of the standard library's row-carrying solves** (373/373 boot, and by my measurement 15,377/15,377 stdlib-located solves corpus-wide) and 25.5 % of the examples'.  I verified the theorem applies to a real boot solve (W-2b).  No witness; my 17,830 extra runs and the round's 134,674 all terminate |
| audit green | **PASS** | 854 jobs, 3611 theorems / 0 non-standard axioms, 0 `sorry`, all 128 new declarations on standard axioms (my own `#print axioms`) |

## W-12. The round-6 brief's checkpoints, item by item

| checkpoint | asked | delivered | my verdict |
|---|---|---|---|
| **R6.3** | define `NoConc`, prove preservation and termination with an explicit bound, measure the corpus, state the outcome exactly | all of it, plus "no id is drawn" (stronger than the review predicted, and correct), plus the queue bound via `unorderedHash_perm` which nothing in the development had | **DONE, and beyond the ask.**  Every number re-derived by me from my own traces; the theorem instantiated by me at a real boot solve |
| **R6.1** | canonical form, `--cycle`, the lemma, a search over round 5's populations + a fresh 50,000 | all of it; 134,674 solves / 3,082,009 states / 0 repeats, with an independent `states == steps+1` cross-check | **DONE**, quantified negative as specified.  One claim overstated (W-6a); I added 17,830 runs and the deepest witness of the stage |
| **R6.2** | recast as "`incm` empties", say what makes the derived set saturate, find the exact gap, state the residual, attempt it | `terminates_iff_incm_empties` (T1); `GuardComplete` named and refuted; `ProcSaturates` stated, proved sufficient, proved on the fragment | **DONE for the recast and the gap; the residual is fragment-relative** (W-6d) and so is weaker than the brief's "one lemma" for the general case |

## W-13. Verdict — **ADVANCE**

The certification is real, and I checked it at the highest bar the brief asks for.

* The **Lean** rebuilds (854 jobs), the audit is 3611 / 0, the hygiene grep is clean, and all
  **128** declarations of the two new modules print only `propext` / `Classical.choice` /
  `Quot.sound` under my own `#print axioms` run.  **All 48 declarations the report quotes are verbatim** — checked
  mechanically (`tmp/review-L5r6/`: extract every `theorem`/`def` block from the Round-6 section,
  normalise whitespace, compare against the two modules; 48 checked, 0 differences).  `noConc_terminates_of_buildQueue` has **no hidden hypothesis**: the two
  flags are the shipped defaults, `Wf` is discharged by `wf_seed`/`wf_replay`, `EnvNodup` and the
  two `KDist`s are discharged at an initial state, and `wf_replay`'s `SetsOk` really is vacuous
  on the fragment for a reason I verified in `Json.lean` rather than accepted.
* The **theorem applies**: I instantiated it in Lean at the largest stdlib-boot row-carrying
  solve (13 partitions, 30 variables, transcribed from my own trace) and got
  `Terminates bS0` on standard axioms, with the run's 31 dequeues and `drawn = 0` decided and the
  handed-over fuel evaluated at 3.2·10²².  I also instantiated it at the *other* boot input
  shape — the eight solves whose left-hand side is a `ConcreteRho`, where `PQueue.build` mints
  before the loop starts — and it covers those too (W-6b).
* The **measurement reproduces exactly** — all 34 cells of the two corpus tables and both
  round-7-pointer rows — from traces I generated and a census I wrote from the record format.
  The boot's 383 row-carrying segments are **all** `NoConc`, the 373 that build a partition span
  289 distinct source locations, and the dispatch histogram (a different code path) shows
  **0 `concrete` steps on the boot against 1,305 and 1,556 on the example groups** — exactly what
  `step_noConc` predicts.
* The **compiler agrees on real input**: 100 shipped-compiler solves on ten real boot solves at
  ten id bases, `SOLVED=10 HANG=0` and `DRAWN 0:x10` every time.  The round's own compiler check
  used synthetic seeds; this one uses the standard library.
* The **cycle search** reproduces cell for cell from the raw `.tsv`, re-runs bit-for-bit, and I
  added 17,830 runs of my own on larger, more label-rich populations — including the deepest run
  this stage has recorded (443 dequeues, 1,382 draws), whose ten per-base draw counts the shipped
  compiler reproduces exactly. Still 0 repeats, 0 `FUEL`.
* The **caveats the round states are the right ones and are stated honestly** — the quotient is
  not a congruence, the supply must be quotiented, the bound is not tight, nothing is claimed
  about the 6,974 labelled example solves, and the claim is "proved of the model, verified of the
  compiler by L2".

**What is certified, in one sentence, as I would write it after re-running everything:**

> Under the shipped flags, `Rowpartition.Loop.step` — the L2-verified model of
> `Constraints.incorporateAll` — provably reaches `done` or `died` within an explicit fuel from
> any initial state whose input partitions carry no field label; a fresh census puts **every one
> of the 383 row-carrying solves of the 129-module standard-library boot (and every one of the
> 15,377 stdlib-located row-carrying solves across the whole corpus) inside that
> fragment**, so `Subst.solve` terminates on all of them, and its LOOP draws no id while doing
> so (`PQueue.build` draws one on 8 of them, before the loop — W-6b).

**What is NOT certified, and must not be read into it:** the 6,974 example-corpus solves that
carry a concrete label (74.5 % of the examples' row-carrying solves) and the 858 labelled ones in
`incomplete/`; termination in general, which remains open with the same mechanism named since
round 4; and — because the theorem is about the model — anything read directly off `Subst.solve`'s
Scala beyond what L2's 2,355,430-segment record-for-record differential establishes.  "The
standard library" means the standard library's own solves, and I have measured that this holds
whether it boots alone or under any corpus program; it does **not** mean every solve a user
program performs.

**Findings**: **W-6a** (a claim about `rawState` that is false as written, with no effect on the
result) and **W-6b** ("no id is drawn" is true of the loop, false of the solve, on 8 of the 373
boot solves — the theorem is unaffected, four documents' prose is not); W-6c/W-6d (two
documentation corrections); W-6e (a scope statement that should be *strengthened*, from 373 to
15,377); W-6f (a caveat I closed by measuring it); W-6g (an instrument gap for round 7).  None
blocks the round.  **W-6a, W-6b and W-6d should be applied to the report, and W-6b and W-6e to
`ROW-CONSTRAINT-STATE.md`, the README, the plan row and the handoff, before the round is
committed** — W-6b in particular, because that paragraph is the certification the project will
be quoted on.

**ADVANCE.**

# Round-7 review — 2026-09-05 (fresh reviewer)

Reviewer: fresh agent.  Under review: `tracker/lean/Rowpartition/Loop/VocFix.lean` (new),
`Loop/Cycle.lean` + `Loop/Main.lean` + `Rowpartition.lean` (edits), `tracker/lean/README.md`,
the plan's L5 row, `ROW-CONSTRAINT-STATE.md`'s new section, and `L5-TERMINATION.md` "Round 7"
(§R7.1–§R7.6).  Pre-existing at `HEAD 157a3f3`: the handoff's launch note and
`briefs/brief-L5r7.md`.  Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r7/`.
**Nothing below is taken from the report: every number is one I produced myself, from traces I
generated and censuses I wrote.**  Findings are numbered `X-`.

## X-1. Rebuild, re-audit, hygiene, axioms — all mine, all reproduce

| check | command | result |
|---|---|---|
| build | `lake build Rowpartition` | `Build completed successfully (855 jobs)` — the report's 855 |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 3706; declarations using a non-standard axiom: 0` — the report's 3706/0 |
| `looptrace` | `lake build looptrace` | `Build completed successfully (1656 jobs)` |
| hygiene | the report's grep over `Loop/{VocFix,Cycle,Main}.lean` | **one hit**, `Main.lean:118`, the word `partial` inside a doc comment forbidding it.  0 `sorry`, 0 `axiom`, 0 `Classical` *in source*, 0 `native_decide`, 0 `opaque`, 0 `unsafe`, 0 `implemented_by`, 0 `admit`, 0 `#exit`.  (Widening the grep to `Rowpartition.lean` adds two more doc-comment hits, `:24` and `:128`.) |
| size | `wc -l` | `VocFix.lean` **1938** — the report's 1,938, exactly |
| declarations | `grep -E '^(theorem\|def\|abbrev\|structure) '` | **100** in `VocFix.lean`: 86 `theorem`, 14 `def` — the report's 86/14/100, exactly |
| `#print axioms`, my own list | `tmp/review-L5r7/{decls-vocfix.txt,RevAxioms.lean,revaxioms.txt}`, all 100 + `isConcDispatch` + `cycleRun` + `CycleRep` | 97 × `[propext, Classical.choice, Quot.sound]`, 2 × `[propext, Quot.sound]`, **4 axiom-free** (the 4th is the `CycleRep` structure the report does not count).  **0 `sorryAx`, 0 non-standard axiom.**  Excluding `CycleRep` this is the report's 97/2/3 = 102 |
| round-6 definitions unchanged | `git diff` on `Loop/{Order,NoConc,StrictBound,Refuted,Refine,RefineLearn,Wf,Step,Queue,Rules,Hygiene}.lean`, `ResGuardTerm.lean` | **empty** — `Terminates`, `Reaches`, `InVoc`, `ConcSub`, `EnvNodup`, `KDist` are round 6's, untouched |
| diff scope | `git status --short tracker/lean/` | exactly the four files the report claims; no Scala file touched |

## X-2. Verbatim check — 50 quoted declarations, 0 differences (my own, stricter checker)

`tmp/review-L5r7/myverbatim.py` does not reuse the implementer's substring search.  It
extracts every quoted `theorem`/`def` block from the Round-7 section, looks each one up **by
name** across twelve modules, and compares the FULL SIGNATURE up to the top-level `:=`/`by` —
so a dropped *trailing* hypothesis is caught, which a prefix substring match would not catch.

```
checked 50 quoted declarations from the Round 7 section; 0 differing, 0 not found
```

## X-3. The census, re-derived from traces I generated and a census I wrote

`tmp/review-L5r7/gentrace-mine.sh` regenerates all seven groups from scratch (the report's own
flags, one JVM per group, serialised loader, interfaces off) and `runinstr.sh` runs
`--replay --cycle` and `--replay --mints` over every one.  `mycensus2.py` is a census I wrote
from `RowTrace.scala:200–250` and `Subst.scala:1195–1216`, joining the `sin`/`scon`/`inpart`/
`sat`/`step` records with the model's own two reports segment by segment.

| | mine | report |
|---|---|---|
| segments, seven groups | 54,199 / 92,673 / 83,942 / 56,032 / 54,235 / 54,244 / 54,739 = **450,064** | identical |
| example-`loc` solves | **48,583** | 48,583 |
| ...building ≥ 1 partition | **9,362** | 9,362 |
| `NoConc` | **2,388 (25.5 %)** | 2,388 |
| loop drew no id (`drawn − drawn0 = 0`) | **9,117 (97.38 %)** | 9,117 |
| vocabulary fixed (`grew = false`) | **9,118 (97.39 %)** | 9,118 |
| ...and no `concrete` step | **6,763 (72.2 %)** | 6,763 |
| residue | **244 (2.61 %)** | 244 |
| every per-group cell of §R7.2a | **identical** (48/184/8/0/0/4 residue) | — |
| stdlib table §R7.2b | **373/415/415/373/373/373/373 = 2,695**, all vocabulary-fixed, all draw-free, **0** `concrete` steps | identical |
| §R7.2c: canonical repeats / exact repeats / `FUEL` | **0 / 0 / 0** in 450,064 | identical |
| deepest run | **140 dequeues**, `Ai/IncidentSeverity.e(69:15)` | identical |
| `SupOk` on every `sin` record | **450,064 / 450,064, 0 violations** | identical |
| §R7.3a classes A/B/C/D | **173 / 36 / 3 / 32**, summing to 244 | identical |
| §R7.3a sub-classes A1/A2/A3 | **97 / 29 / 47**, summing to 173 | identical |
| A1 shapes `join` / `lone` / `join+lone` | **47 / 28 / 22**; `drawn = 1` and `cmax = 1` in all 97; 3–9 dequeues; 1–4 partitions | identical |
| A2 | **all 29 `bare`, all `cmax = 1`**, drawn 1 on 27 and 2 on 2 | identical |
| A3 | **26 with 5 partitions, 19 with 7, 2 with 2; 45 `bare`; `cmax` 1/2/3 on 24/18/5** | identical |
| D | **all 32 take ≥ 3 `concrete` steps** (3 on 24, 4 on 1, 7 on 6, 8 on 1), drawn 1–8 | identical |
| §R7.3b `--mints`: `max` / `remint` | example **1 / 0**, stdlib **0 / 0** | identical |
| §R7.3b `cmax` histogram | example **0:9118 1:198 2:40 3:5 4:1**, stdlib **0:2695** | identical |
| `cmax = 0` ⇔ vocabulary fixed | **holds on every one of the 9,362**, both sides 9,118 | identical |
| §R7.3b provenance cross-check | residue **SC 418, Res 106, SK 23, SR 1, ResR 6**; all-example **SC 422** and the rest identical | identical |
| max ids drawn in the residue | **73** | 73 |

### X-3a. The residue table, all 244 rows × 9 fields — 0 differences

I did not sample it.  `tmp/review-L5r7/` re-derives the whole of §R7.2d — module(location),
rules in `sat`, ids drawn, new names, max at one key, input key shape, partitions, dequeues,
`concrete` steps — from my own traces, sorts it the way the report does, and diffs it:

```
244 residue rows x 9 fields: 0 field differences
```

The row ORDER reproduces too, which is an extra check on the join.  (I first hand-checked ten
random rows — 22, 27, 70, 81, 122, 132, 149, 151, 184, 230 — field by field, then did all 244.)

### X-3b. `SupFresh`, which the round did NOT measure — it holds too (in the round's favour)

§R7.1d says "`SupOk` and `SupFresh` … a corpus replay reads out of its `sin` record" and then
measures **only** `SupOk`.  `SupFresh su (sys s)` is not a `sin` field: it is
`∀ z, Sup.Reach su z → z ∉ allVars G` (`RefineLearn.lean:39,54`).  I measured it
(`tmp/review-L5r7/supfresh.py`): for each segment, simulate `buildQueue`'s draws (one per `part`
with a non-variable left-hand side) to get `su'`, then test every input variable id (`svar`) and
every id the build minted against `Sup.Reach su'`.

```
segments 450064   SupFresh(su') holds 450064   violations 0
```

So both new hypotheses are discharged on real compiler input, not just the one the report checked.

## X-4. THE CHECK THAT MATTERS: the theorem instantiated at a witness of my own, five `concrete` steps

Round 6's certification was worth what it could be applied to, and so is this one.  The round's
own `vS0` takes the `concrete` branch at its FIRST dequeue and no more.  I built a witness that
takes it **five times in a row**, so `rowSet_lt_concrete` — the whole content of §R7.1c — is what
pays for the run, and checked in Lean that the potential really rises at every one of them
(`tmp/review-L5r7/RevWitness.lean`, compiled with `lake env lean`, then removed from the tree):

```lean
def rSeed : Seed :=                       -- v0 <- ((|l0,l1|)), v1 <- ((|l2|)), v2 <- (v0,v1),
  { name := "revfix",                     -- v3 <- (v2,v4), v4 <- ((|l3|))
    cons := [⟨0,[],[0,1]⟩, ⟨1,[],[2]⟩, ⟨2,[0,1],[]⟩, ⟨3,[2,4],[]⟩, ⟨4,[],[3]⟩], rhoKeys := [] }
def rSu : Sup := { lo := 10, hi := 1000, blk := 1000, bsz := 1024 }   -- the COMPILER's shape

theorem rConc0 : isConcDispatch (rAt 0) = true := by rfl   -- …rConc1 … rConc4, five in a row
theorem rRow0 : (rowSet rV rL (rAt 0)).card < (rowSet rV rL (rAt 1)).card := by decide
theorem rRow1 … rRow4                                       -- the potential rises five times
theorem rS0_notNoConc : ¬ NoConc rS0                        -- round 6's theorem does NOT apply
theorem rS0_terminates : Terminates rS0                     -- this one does
theorem rS0_drawn : (match run rS0 40 with | .solved s => s.su.drawn | _ => 99) = 0 := by rfl
```

```
'Rowpartition.Loop.RevCheck.rS0_terminates' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.RevCheck.rS0_notNoConc'  depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.RevCheck.rRow0' / 'rRow4' / 'rS0_drawn' : the same three
#eval (allVars (sys rS0)).card = 5   #eval rL.card = 4
#eval (rowSet rV rL rS0).card = 0    #eval (rowSet rV rL (rAt 5)).card = 32   (bound |V|·2^|L| = 80)
```

Every hypothesis is discharged, not assumed — `wf_seed`, `envNodup_initial`,
`queueHygiene_of_env_nil`, `kdist_ofList`, and `SupOk`/`SupFresh` proved from the supply's own
numbers.  **The certification applies end to end to a labelled input on which round 6's does not,
on standard axioms, and the new potential is what carries it.**

## X-5. The compiler, on both witnesses, at 22 and 16 id bases

| seed | bases | result |
|---|---|---|
| the round's `vSeed` (`tmp/L5r7/seeds/D.json`) | 0–9 (the report's) | `SOLVED=10 REJECTED=0 HANG=0 OOM=0`, `DRAWN 0:x10` — reproduced |
| the same | **10–21 (mine)** | `SOLVED=12 REJECTED=0 HANG=0 OOM=0`, `DRAWN 0:x12` |
| **my `rSeed`** (`tmp/review-L5r7/seeds/RW.json`) | **10–21** | `SOLVED=12 REJECTED=0 HANG=0 OOM=0`, `DRAWN 0:x12` |
| my `rSeed`, through the MODEL | bases 0, 3, 100, 4096 | `SOLVED steps=5 drawn=0 canon=- exact=-`, `max=0 remint=0 cmax=0 cremint=0` |

`ERMINE_JAVA_OPTS=-Dermine.useInterface=false tracker/repro/satterm/run.sh sweep json:<seed> …`.

## X-6. Side by side — the model, the Scala, and the round's prose

Every fact the round's mathematics rests on, checked in `Constraints.scala` and in the module,
not taken from the report.

| claim | Scala | Lean | verdict |
|---|---|---|---|
| `ensureSuperset` forces every concrete row recorded for `v` inside the new `fs` | `makeConcrete` (`Constraints.scala:1610–1628`) builds `rhss` from **`proc` AND `incm`, every partition with `_._1 == v`** — not only bare rows — and calls `ensureSuperset(v.loc, concr, fs)` on each, which `die`s unless `concr subsetOf fs` (`:312–320`).  Direction: the RECORDED part is the subset | `makeConcrete_superset : ∀ p ∈ proc.elems, p.lhs = v → p.rhs.conc.subsetOf fs = true` | **exact**, and the Lean is the weaker (proc-only) half of what the Scala checks, which is all `rowSet` needs |
| ...so `makeConcrete` cannot DELETE a row of `v` that is not a subset — downward closure is safe | the `rhss.foreach` runs **before** `destructiveSub`, and `ensureSuperset` throws | `rowSet_lt_concrete`'s `hsupN` + the `p.lhs = r.lhs` branch of `hsub` | **exact**.  The brief's question answered: no such deletion is possible without failing the step |
| the dispatch's `findRHS` miss makes the inclusion PROPER | `PQueue.findRHS` (`:591–608`) narrows the priority-search queue by `rhs.hashCode` and then tests `rhs == rhs2`, i.e. **case-class structural equality on `RHS(Set[TypeVar], Fields)`**; equal values have equal hash, so an equal bare row `v <- ((|fs|))` in `proc` CANNOT be missed.  The dispatch uses `proc findRHS(rhs)` only (`:1123`), not the three-way `:1087` version | `hnofind` → `hno` → `makeConcrete_row_mem`; the final `ssubset` witness `(r.lhs, r.toConstraint.conc)` | **exact** |
| `destructiveSub` keeps every partition not mentioning `v` — including another variable's bare row, unchanged | `p = { case Partition(u, rhs, _) => u != v && !rhs.contains(v) }` and `RHS.contains(v) = abstr contains v` (`:333`), so a bare row has `contains = false` and `procd filter p` keeps the ORIGINAL object.  The `keepDefs`/`srs` path only ADDS back `pps.filter(abs.size >= 2)`; the `(srs isEmpty) && keep` path keeps `proc` whole.  **No branch deletes or rewrites another variable's bare row** | `destructiveSub_proc_keep`, used through `makeConcrete_proc_keep` with `RHS.contains` and `ha : abstr = []` | **exact** |
| `resolution` draws INSIDE the lone/lone arm and BEFORE its guards | `:1768–1780`: `case (RHS(Single(x), concr1), RHS(Single(y), concr2)) => val z = fresh(…)` — then `tops/bots`, then `resGuard`, `resRow`, `emptyRow`.  `case _ => Set()` costs nothing | `resolution_noDraw : drawn unchanged → result = SSet.empty` | **exact** |
| `splitConcrete` draws only in its LAST branch, and every reuse branch names a lookup result | `:1301–1341`: `rhss(RHSAbstr(abstr)) → u`; `resolvent(concr) → w`; `concRow(concr) → w`; `emptyRow(concr) → Partition(x, RHSEmpty())` for `x ∈ abstr`; only the final `case None` does `val u = fresh(…)` | `splitConcrete_avoidsV`'s `hr`/`hres`/`hcr` (one per lookup) and `ha` (the `emptyRow` branch names only `abstr`) | **exact**; the hypothesis list is exactly the branch list |
| the `concrete` dispatch is `findRHS` miss + non-empty rhs + no abstract parts | `:1130–1134` `case None => rhs match { RHSEmpty() → empty ; RHSConcr(concr) → concrete ; … }` | `Step.lean:334–342`; `Cycle.isConcDispatch` | **exact** — `nconc` measures the branch it claims to |
| the `learn` step's strict decrease comes from `procSys`, not from the queue | the `learn` branch is reached only after `proc findRHS(rhs)` MISSED, so `r.toConstraint ∉ procSys s`, and `proc.insertNP r` puts it in | `Order.learn_procSys_lt` (unchanged, no fragment hypothesis) via `step_quadrichotomy`'s first disjunct | **exact**, and round 7 **inherits** round 6's answer rather than re-proving it.  A dedup of the dequeued premise is impossible in that branch, so the brief's worry does not arise; the queue may GROW at a `learn` step and the measure does not care |
| the LOOP's own draw count excludes `PQueue.build`'s mints | `Constraints.scala:661–662` mints for a `Part` with a non-variable lhs, before `expand` | `replayCycleOne` sets `su0 := g.sup.lo` and `cycleRun` sets `drawn0 := s.su.drawn` and `mint0 := mintOrder s` at the FIRST dequeue; the census uses `drawn − drawn0` | **exact** — W-6b is correctly handled.  I cross-checked the count: **56 of the 2,695 stdlib solves and 379 of the 9,362 example solves carry a build mint** (56 = the round-6 reviewer's 8 per group × 7), and **145 of the 244** residue solves — the report's 145 |
| `grew = false` is the run-level `VocFixed (allVars (sys s₀))` | — | `mintOrder` (`Cycle.lean:269–278`) collects ids `≥ su0` from `s.parts` and `s.env.binds`; `cycleRun` visits **exactly** the states `Reaches s₀ ·` (it reports at every state on which `step` is invoked and stops at `done`/`died`) | **very slightly WEAKER, and harmlessly so**.  `grew` tracks only ids `≥ su0`; `InVoc V` also forbids a NEW id `< su0`, which the loop cannot produce (every id it writes comes from a premise or from `fresh`, and `fresh` under `SupOk` yields a `Sup.Reach` id) — true, but argued, not measured.  No Lean theorem links `grew` to `VocFixed`; the link is the instrument's doc comment |
| `NoConc` / `Terminates` / `Reaches` / `InVoc` / `ConcSub` / `EnvNodup` / `KDist` are round 6's | — | `git diff` on their modules is **empty** | **exact** |

## X-7. THE `incomplete/` GROUP, WHICH ROUND 7 SKIPPED — and it holds a counter-witness

§R7.5 records `incomplete/` as "NOT MEASURED THIS ROUND".  It is part of `core/examples`, it is
what the user's framing calls the user-facing population, and it is the group built to be hard.
I traced all **34** of its `.e` modules (`tmp/review-L5r7/genic.sh`, one JVM per file, 90 s cap,
the same flags) and ran BOTH round-7 instruments over every segment.

```
files=34  segments=1,851,131  canonical repeats=0  exact repeats=0  FUEL=0
deepest run 281 dequeues at core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)

stdlib-loc   : built 12,682   NoConc 12,682   vocabulary-fixed 12,682 (100 %)   `concrete` steps 0
incomplete-loc: built  1,283   NoConc    425   vocabulary-fixed  1,188 (92.60 %)  residue 95
   residue classes A/B/C/D = 44 / 30 / 1 / 20
   splitConcrete max-at-one-key : 0 on 1,188,  1 on 94,  **2 on 1**
   carrier      max-at-one-key : 0 on 1,188,  1 on 66, 2 on 19, 3 on 5, 4 on 2, 5 on 2, **6 on 1**
   `remint > 0` : **1 solve**       `cremint > 0` : 29 solves
```

(The segment count, the 12,682 and the 1,283/425 all reproduce the round-6 review's W-7 exactly.)

Two things follow, and the first is a **CONFIRMED refutation of a headline sentence**.

**(1) A `splitConcrete` GUARD key IS minted twice in real Ermine code.**

```
mints 54291 trySolveOn core/examples/incomplete/np01_add_or_recompute.e(134:15) SOLVED
      steps=98 drawn=22 max=2 remint=1 cmax=3 cremint=3 keys=5
cycle 54291 … SOLVED steps=98 states=99 drawn=22 grew=true mint0=4 maxmint=17 conc=8 drawn0=4
      nrows=8 canon=- exact=-
```

98 dequeues, 18 LOOP draws, **one `splitConcrete` key minted twice**, three carrier keys
re-minted, `cmax = 3` — and still `SOLVED`, with no canonical and no exact repeat.  This is not a
model artefact: `looptrace --replay` (the L2 differential, not the `--cycle` path) over that file
gives `segments=55015 replayed=55015 skipped=0 hashdiff=0 eqdiff=0 rejected=0 fuel=0`, so the
solve is the SHIPPED COMPILER's and so is the mint count.  The deepest solve in the group,
`gu05_star_join_4dim_concrete_signature.e(62:1)`, takes **281 dequeues** (twice the seven groups'
140), draws **145** ids, reaches `cmax = 6`, and also replays clean (`hashdiff=0 eqdiff=0`).

**(2) The stdlib certification is untouched and, again, complete** — 12,682 of 12,682
stdlib-located solves in the hardest group are `NoConc`, vocabulary-fixed, draw-free and take no
`concrete` step.  With the seven groups' 2,695 that is the round-6 reviewer's 15,377 figure
re-derived through the round-7 instrument.

## X-8. Findings, ranked

Nothing below is a soundness defect: every Lean statement I checked is true, verbatim, on
standard axioms, and every number in the report reproduces on the population it measured.
X-8a is a claim that is **false as written** and must be fixed; X-8b and X-8c change what the
census means; the rest are documentation.

* **X-8a (CONFIRMED, a headline claim refuted by a corpus witness).**
  `ROW-CONSTRAINT-STATE.md`: *"**no `splitConcrete` key is minted more than once anywhere in the
  corpus** — the pump shape the last three rounds hunted does not occur in real code even once"*;
  the plan's L5 row: *"ROUND 5'S PUMP DOES NOT OCCUR: `--mints` over the whole corpus finds **no
  `splitConcrete` key minted more than once, anywhere**"*; §R7.4: *"the corpus never does it even
  twice"*.  **Two things are wrong.**
  1. *Scope.*  "the corpus" is the seven groups; `core/examples/incomplete/` is excluded (§R7.5
     says so) and it is part of `core/examples`.  Measured (X-7): **`core/examples/incomplete/np01_add_or_recompute.e(134:15)`
     mints one `splitConcrete` guard key TWICE** (`max=2 remint=1`), on a solve the compiler
     performs and the model replays record-for-record.  So the sentence is false of the example
     corpus; it is true of the seven groups.
  2. *Which key.*  Round 5's pump is defined on the **carrier** key, not the `splitConcrete`
     guard key: `Pump.lean`'s refutation witness is `cMint4`/`cMint8`, two `MintsAt … 4 cKey`
     where `cKey` comes from `carrierKeys`, and the instrument for it is `ctally`/`cmax`/`cremint`
     (`PumpRep.maxAtCKey`, `.remintCKeys`), not `tally`/`max`/`remint`.  By that counter the
     SEVEN GROUPS already re-mint at one key: **46 of the 9,362 example solves have
     `cremint ≥ 1`** (`cmax` 2 on 40, 3 on 5, 4 on 1; three distinct re-minted keys on
     `Ai/SupplyChainInventory.e(74:20)`), and `incomplete/` adds 29 more, reaching `cmax = 6`.
     So "the pump shape … does not occur in real code even once" is false on the round's own
     seven-group data under round 5's own definition of the shape.
  §R7.3b is careful about (2) ("the wider CARRIER counter … does repeat, but barely") and the
  plan row quotes `cmax ≤ 4`, so the report knows; it is the *conclusion sentence* that
  over-reaches, in the two documents the project will be quoted on.
  **Fix (required):** in the state file and the plan row, say "no `splitConcrete` GUARD key is
  minted more than once in the seven groups (`incomplete/` was not measured; it has one solve that
  does, `np01_add_or_recompute.e(134:15)`), and the CARRIER key round 5's refutation uses is
  re-minted on 46 of the 9,362, up to four times."  Also correct §R7.3b's "the repeats are at
  *different* keys" — true of the guard key, false of the carrier key its own `cmax` column shows.

* **X-8b (CONFIRMED, a scope bias in the census the report does not state).**
  The population predicate is "≥ 1 `inpart` record", and `Subst.scala:1215` writes those records
  **after** `var ps = q.expand.toList` (`:1188`) — i.e. only for solves the compiler COMPLETES.
  So a solve the row solver REJECTS is invisible to the census.  Measured: **19 example-`loc`
  solves** that the model builds a queue for and runs are dropped, **all 19 `REJECTED`**, and
  **3 of them are residue**:

  ```
  shouldfail/der06_shared_two_var_remainder.e(66:7)    grew, 1 draw, 2 `concrete` steps, cmax=1
  shouldfail/der07_shared_three_var_remainder.e(44:7)  grew, 1 draw, 2 `concrete` steps, cmax=1
  shouldfail/der08_shared_remainder_relations.e(42:7)  grew, 1 draw, 2 `concrete` steps, cmax=1
  ```

  The honest example-corpus figures over the solves the MODEL runs are **9,381 built /
  9,134 vocabulary-fixed (97.37 %) / 247 residue**, not 9,362 / 9,118 (97.39 %) / 244.  The
  headline moves by 0.02 points — nothing — but §R7.2d is **three rows short of the brief's
  "for EVERY solve outside it, one row"**, and "Every one of the 244 is `SOLVED` by the model" is
  true only because the census cannot see the rejected ones.  A termination census that
  systematically excludes the failing solves is exactly backwards for this question.
  **Fix:** state the predicate and its bias; add the three rows; or use the model's own
  `steps > 0` as the population and report both figures.

* **X-8c (CONFIRMED, a claim that is vacuous as measured).**  §R7.2c's table row
  "skipped / `hashdiff` / `eqdiff` | **0 / 0 / 0**" and its gloss *"the L2 replay checks
  (`hashdiff`, `eqdiff`, skips) stay at zero throughout, so the model is running the compiler's
  own solves"*, repeated in `ROW-CONSTRAINT-STATE.md` ("0 skipped, 0 `hashdiff`, 0 `eqdiff`") and
  the plan row.  In `--cycle`/`--mints` mode `replayMain` never calls `replay`, so those two
  counters are the literal `0`s of `return (1, 0, 0, 0, …)` (`Main.lean:158, 176`) and **nothing
  is compared**.  Only `skipped` is real.  The differential does hold — I ran the real thing,
  plain `--replay` on `boot`/`top`/`Ai`/`shouldfail`: `hashdiff=0 eqdiff=0 skipped=0` on all four
  (and on the two `incomplete/` files of X-7) — but the round's own run does not establish it.
  **Fix:** one clause, or run plain `--replay` alongside and cite that.

* **X-8d (CONFIRMED, an explanation with the wrong number and a missing term).**  §R7.2a:
  *"The small difference is the proxy's … which is precisely the 32-solve class §R7.3 names."*
  I recomputed the round-6 proxy from my own traces — 9,340 with a saturated set, **9,120 fixed
  (97.64 %), 220 grown**, all three the reviewer's W-9 numbers — and diffed it against the model
  solve by solve:

  ```
  (proxy fixed, model fixed) 9,096   (proxy grew, model grew) 220   (proxy fixed, model GREW) 24
  the 24 are all class D; class D has 32, and the proxy CATCHES 8 of them
  solves with no saturated set at all: 22 — all vocabulary-fixed, and outside the proxy's population
  9,120 + 22 − 24 = 9,118 ✓
  ```

  So the mechanism named is right and the count is not: **24 of the 32**, plus an opposite-signed
  **+22** the report omits.  **Fix:** state both terms.

* **X-8e (CONFIRMED, a misnomer, twice over).**  §R7.3a's sub-class table labels **A1** —
  "one new name, **no** `concrete` step" — "the B1 shape".  The brief's own gloss of that phrase
  is *"single mints that are immediately concretised"*, which is class **A2** ("one mint, then the
  row is concretised"), not A1; and in this tracker `B1` already names the `makeEmpty`
  propagation fix (`LOOP-MODEL-PLAN.md` row `B1`, `tracker/loopmodel/B1-FIX.md`), a different
  thing again.  **Fix:** drop the label, or move it to A2 with a different name.

* **X-8f (documentation, small, CONFIRMED).**  §R7.1d: *"`Wf`, `EnvNodup`, the two `KDist`s and
  `QueueHygiene` are all free at an initial state"* — the `_of_buildQueue` corollaries discharge
  `EnvNodup`, `QueueHygiene` and both `KDist`s but keep **`Wf`** as a hypothesis (as round 6's did;
  it is dischargeable by `wf_seed`/`wf_replay`, and I discharged it in X-4, so the claim is true
  but the corollary does not show it).  And *"`SupOk` and `SupFresh` … a corpus replay reads out of
  its `sin` record"*: `SupOk` is four `sin` fields, `SupFresh` is not a field at all — it is
  `∀ z, Sup.Reach su z → z ∉ allVars G`, and the round measures only `SupOk`.  I measured
  `SupFresh` too and it holds 450,064/450,064 (X-3b), so the claim survives; the sentence should
  not put them in the same breath.

* **X-8g (latent instrument defect, currently harmless, CONFIRMED).**  `replayCycleOne` /
  `replayMintOne` map a `buildQueue` error to `{verdict := "BUILD"}` with the structure's
  DEFAULTS — `steps = 0`, `grew = false`, `drawn = 0`, `cmax = 0` — so a segment the model cannot
  even build would be scored **vocabulary-fixed** by any census reading `grew`.  There is exactly
  one such segment in the seven groups (`shouldfail/dup01_partition_literal.e(25:7)`), and it has
  no `inpart` record, so it is filtered out and no number moves.  It also explains the
  `rejected=31` (`--cycle`) vs `rejected=32` (plain `--replay`) difference on `shouldfail`, which
  is not a disagreement.  **Fix:** print `grew=?` on a BUILD verdict, or exclude it explicitly.

* **X-8h (instrument gap, for round 8).**  The five new `CycleRep` fields and `--mints`' `keys`
  print only on the `--replay` path; the `json:` seed path's `--cycle` line is still
  `steps/states/drawn/canon/exact`, so a hand-built seed cannot be scored for `grew`, `conc`,
  `mint0` or `drawn0` without going through a trace.  I hit this building X-4's witness.

## X-9. Things I ran that the round did not

1. **`incomplete/`, all 34 modules, through BOTH new instruments** (X-7) — 1,851,131 more
   segments, 0 repeats, 0 `FUEL`, and the **counter-witness to the round's pump sentence**.
2. **The round-7 theorem instantiated at a witness of my own with FIVE `concrete` steps** (X-4),
   with `rowSet`'s strict growth `decide`d at each of them — the round's own `vS0` takes the
   branch once.
3. **`SupFresh` measured on the whole corpus** (X-3b) — 450,064/450,064; the round measured only
   `SupOk`.
4. **The genuine L2 differential re-run** on `boot`/`top`/`Ai`/`shouldfail` and on the two
   `incomplete/` files that matter (X-8c) — the check the `--cycle` summary only appears to make.
5. **All 244 residue rows × 9 fields diffed**, not sampled (X-3a).
6. **The round-6 proxy recomputed and diffed against the model solve by solve** (X-8d) — which is
   what shows the 97.6 → 97.39 explanation is 24-of-32 plus an omitted +22.
7. **The shipped compiler at 12 further id bases on the round's witness and 12 on mine** (X-5).
8. **A mint-SITE census** — is the left-hand side of a mint an INPUT variable or one this run
   minted?  This is the round-8 lever and nobody has measured it:

   | population | `splitConcrete`-family mint conclusions | site is an INPUT variable | `resolution` conclusions | site is an INPUT variable |
   |---|---|---|---|---|
   | six example groups | 230 | **227 (98.7 %)** | 112 | 60 (53.6 %) |
   | `incomplete/` | 169 | **147 (87.0 %)** | 103 | 62 (60.2 %) |

   So `splitConcrete` almost never chains on its own output, while `resolution` chains routinely —
   and `incomplete/` is where the split chains at all.  (Read off `sat` provenances, so it sees
   only the mints that survive into the saturated set; class D's do not.)
9. **`drawn` against `concrete` steps over all 339 residue solves of both populations**: `drawn`
   reaches 149 and `drawn > 3·conc + 4` on 15 of them (worst `(149, 29)`), so the tempting
   "charge every mint to a `concrete` step" is not a constant-factor law either.

## X-10. Acceptance criteria (`LOOP-MODEL-PLAN.md`, L5)

| criterion | verdict | evidence |
|---|---|---|
| `LoopStrict` has no arbitrary-deletion constructor | **PASS**, unchanged | `Strict.lean` untouched (`git diff` empty) |
| every `step` refines it under `step_refines_all`'s hypotheses | **FAIL**, unchanged | round 7 does not touch the strict refinement and does not claim to; it uses `step_refines_all` (the `LoopRel` version) only to transport `ConcSub` |
| `Terminates s₀` for every satisfiable `Wf s₀` with an explicit bound, **or** a compiler-reproduced witness | **PARTIAL**, and materially wider than round 6 | neither disjunct in full.  What is met: `Terminates` at an explicit fuel for a fragment that now ALLOWS labels, ALLOWS both generative rules to fire and ALLOWS the `concrete` branch, containing **97.4 % of the example corpus and 100 % of the standard library** — but defined by the RUN, not by the input, which the round states plainly and repeatedly.  I applied the theorem myself to a labelled five-`concrete`-step input (X-4).  Still no witness: 450,064 + 1,851,131 corpus solves and round 6's 134,674 synthetic ones all terminate, 0 repeats |
| audit green | **PASS** | 855 jobs, 3706/0, 0 `sorry`, all 103 new declarations on standard axioms under my own `#print axioms` |

## X-11. The round-7 brief's checkpoints

| checkpoint | asked | delivered | my verdict |
|---|---|---|---|
| **R7.1** define `VocabFixed`, find the strongest INPUT-checkable condition the data supports, prove preservation + `Terminates` with an explicit bound; if only run-level, say so and prove `terminates_of_noMint` | run-level `VocFixed`/`NoDraw` with `vocFixed_terminates`/`noDraw_terminates` at `measure4 … + 1`; the input-checkable widening **searched for and not found**, said so in five places; three genuinely new pieces, of which `rowSet` (the `concrete` branch) is real mathematics with a real Scala reading | **DONE**, and the brief's fallback is exactly what was taken.  The `concrete` branch being *paid for* rather than excluded is the round's substance and it holds up against `Constraints.scala` line by line (X-6) |
| **R7.2** census solve by solve, ≥ 9,120 target, a row for EVERY residue solve, `cycleRun` in `replayMain` | 9,118 (97.39 %); §R7.2d's 244 rows, all nine fields; `--cycle` and `--mints` over `--replay`, closing W-6g | **DONE with one gap.**  Every number reproduces exactly (X-3, X-3a).  The brief's target "≥ 9,120" is missed by 2 on the round's own denominator (9,118 of 9,362) and MET on the wider population that includes the rejected solves (9,134 of 9,381); the two figures count different things (X-8b, X-8d), so the miss is nominal.  "EVERY solve outside it" is **three rows short** (X-8b) and the `incomplete/` group's 95 residue solves were not counted at all (X-7) |
| **R7.3** classify the residue; for each class say what the pump needs and the class lacks; if a class admits a per-class lemma, prove it and report the final certified fraction | four classes + three A sub-classes, all reproducing; `terminates_of_drawsAtMost` — **one cardinal reduction for all five shapes**, and an explicit statement that no structural per-class lemma was found | **PARTIAL, and honestly labelled.**  The reduction does not move a single solve into the certified population, and the report says so (§R7.3c: "the bound is read off the observed run").  The lemma the brief hints at for A1 — "one mint, then `NoConc`" — **is already proved**: `terminates_of_eventuallyNoDraw` is exactly it, and A1's `drawn = 1` makes its hypothesis a finite check (`NoDrawB` from the post-mint state).  But it buys nothing, for the same reason: certifying A1 requires running A1, and a run that finishes already proves `Terminates`.  **The report should make that connection explicitly** rather than leaving `terminates_of_eventuallyNoDraw` unattached to the residue table.  I looked for a structural lemma the round missed and found none; the one that would have worked — "a `splitConcrete` key is minted at most once" — is **refuted** by X-7's witness |
| **R7.4** state the open problem in the state file and the plan row: certified population, residue as a named list with counts, what a divergence must look like | all four, well written, with the run-level caveat carried throughout | **DONE**, subject to X-8a (the pump sentence) and X-8c (the vacuous `hashdiff`/`eqdiff`) |

## X-12. The round-8 pointer

Round 7 leaves the problem in the best shape it has been in: `terminates_of_drawsAtMost` is a
socket that any mint bound plugs into, and `reaches_concSub` — **the label pool is FIXED along
every run, unconditionally, with no fragment hypothesis** — is the first invariant of this stage
that constrains the state space without assuming the answer.  Together they say the whole open
problem is: *the loop mints at keys `(v, C)` with `C` drawn from a FIXED finite set; is the set of
`v` bounded?*

**The single most valuable next step is to measure and then bound the MINT CHAIN DEPTH.**  A
divergence must mint at unboundedly many distinct left-hand sides (§R7.4's own conclusion, now
sharpened by the fixed label pool), and since each `v` beyond the input's own is itself a
minted name, a divergence is an infinite chain `v₀ → v₁ → v₂ → …` in which `vᵢ₊₁` is minted while
a partition of `vᵢ` is dequeued.  Nothing in seven rounds has measured that chain.  My X-9(8)
census is the first datum and it is encouraging in a way the residue table is not: in the six
example groups **227 of 230 `splitConcrete` mint sites are INPUT variables** — the split
essentially does not chain — while `resolution` chains on about half its conclusions, and in
`incomplete/` the split chains 22 times out of 169.  So:

1. **Instrument the chain**: for each mint, record whether its site is an input variable or one
   this run minted, and at what depth; report the depth histogram over both populations.  This is
   a `PumpRep` field and an afternoon's work, and it is the quantity a mint bound has to bound.
   If the depth is bounded by the input's own size (or by `|L|`), that is the missing lemma; if it
   is not, the deep chains ARE the witness candidates and round 8 should drive them.
2. **Do NOT spend a round on "a `splitConcrete` guard key is minted at most once."**  It reads
   like the natural consequence of §R7.3b's `remint = 0` and it is **FALSE**:
   `core/examples/incomplete/np01_add_or_recompute.e(134:15)` mints one twice (X-7), on a solve
   the shipped compiler performs, replayed record-for-record.
3. **Retire the synthetic pump seeds in favour of two real ones.**
   `np01_add_or_recompute.e(134:15)` (98 dequeues, 18 loop draws, `max=2 remint=1 cmax=3
   cremint=3`) is the sharpest real specimen of round 5's pump at the guard key, and
   `gu05_star_join_4dim_concrete_signature.e(62:1)` (**281 dequeues, 145 draws, `cmax = 6`**) is
   the deepest real solve on record — deeper than round 6's best synthetic hunt result by every
   measure except draws.  Both should be transcoded into `json:` seeds, swept at many id bases on
   the shipped compiler, and added to `core/test`'s `TestLoopTrace` corpus.
4. **Measure `incomplete/` as a first-class group from now on.**  It is inside `core/examples`,
   it is 92.6 % vocabulary-fixed against the other groups' 97.4 %, its stdlib half is still
   12,682/12,682 certified, and it is where every interesting counter-example of this round lives.

## X-13. Verdict — **FIX-THEN-ADVANCE**

The mathematics is right and I checked it at the highest bar the brief asks for.

* The **Lean** rebuilds (855 jobs), the audit is 3706/0, the hygiene grep is clean, `VocFix.lean`
  is 1,938 lines and 100 declarations exactly as claimed, and all 100 plus the three
  `Cycle.lean` additions print only `propext` / `Classical.choice` / `Quot.sound` under my own
  `#print axioms`.  **All 50 quoted declarations are verbatim**, checked by name with full-signature
  comparison, which also rules out a dropped trailing hypothesis.  Round 6's definitions —
  `Terminates`, `Reaches`, `InVoc`, `ConcSub`, `EnvNodup`, `KDist` — are untouched.
* The **new mathematics holds against the Scala**.  I read `ensureSuperset`, `makeConcrete`,
  `destructiveSub`, `findRHS`, `RHS.contains`, `resolution`, `splitConcrete` and the
  `incorporateAll` dispatch, and every one of the three facts `rowSet_lt_concrete` rests on is
  exactly what the compiler does — including the two the brief singled out: `ensureSuperset`
  covers **all** partitions with lhs `v` in **both** queues (so `makeConcrete` cannot delete a
  non-subset row without failing), and `findRHS` is hash-narrowed **structural** equality (so an
  equal bare row cannot be missed and the inclusion really is proper).  The `learn` step's strict
  decrease is round 6's `learn_procSys_lt`, inherited unchanged, and the dedup worry the brief
  raises cannot arise in that branch.
* The **theorem applies**: I instantiated it at a labelled input of my own whose run takes the
  `concrete` branch **five times**, `decide`d that `rowSet` rises at each, and got `Terminates` on
  standard axioms with `Wf`/`SupOk`/`SupFresh` discharged from the seed's own numbers — and the
  shipped compiler solves it at twelve id bases drawing nothing.
* The **measurement reproduces exactly**: every cell of §R7.2a/b/c, §R7.3a/b/d, all **244 residue
  rows × 9 fields with zero differences**, `SupOk` 450,064/450,064 — and `SupFresh`, which the
  round did not measure, holds 450,064/450,064 too.
* The **caveats the round states are the right ones**: run-level not input-checkable, said in five
  places; the fuel not tight and stated as such; `terminates_of_drawsAtMost` labelled a reduction
  and not a certification.  That honesty is why this is not a REDO.

**What must be fixed before it is committed** — three of them touch sentences the project will be
quoted on:

1. **X-8a**, required.  "No `splitConcrete` key is minted more than once anywhere in the corpus /
   the pump shape does not occur in real code even once" is **false**: `incomplete/` is inside
   `core/examples` and `np01_add_or_recompute.e(134:15)` does it, and round 5's pump is a CARRIER-key
   pump that 46 of the seven groups' own 9,362 solves already exhibit.  Restate with both
   qualifications, in `ROW-CONSTRAINT-STATE.md`, the plan's L5 row, §R7.3b and §R7.4.
2. **X-8b**, required.  State the census population predicate (`≥ 1 inpart` record, written only
   after a successful `q.expand`) and its bias, and either add the three dropped residue rows or
   report 9,381 / 247 alongside 9,362 / 244.
3. **X-8c**, required.  Drop or qualify "0 skipped, 0 `hashdiff`, 0 `eqdiff`" for the
   `--cycle`/`--mints` runs — those two counters are not computed in that mode.  (The differential
   does hold; cite a plain `--replay`.)
4. **X-8d**, **X-8e**, **X-8f**, **X-8g** — documentation corrections, one or two sentences each.
5. Worth adding, in the round's favour: **X-3b** (`SupFresh` holds 450,064/450,064) and **X-7**'s
   `incomplete/` numbers (stdlib 12,682/12,682; the group's own 1,188/1,283 = 92.6 %).

None of these changes a theorem, a bound, or the certified fraction by more than 0.02 points.
The round is a real advance — the `concrete` branch is genuinely paid for, and the corpus is
measured by running the model rather than by a proxy for the first time.

**FIX-THEN-ADVANCE.**
