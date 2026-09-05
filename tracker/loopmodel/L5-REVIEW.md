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
