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
