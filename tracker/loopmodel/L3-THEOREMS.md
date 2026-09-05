# L3 — theorems about the loop model

Stage L3 of `tracker/LOOP-MODEL-PLAN.md`. Implemented 2026-09-04; **Round 2 (after the L3
review's FIX-THEN-ADVANCE verdict) is the section at the end of this file, and the Round-1 text
below has been corrected in place where the review found it over-claiming.** Round 2's headline:
the `learn` branch is refined too, so `step_refines_all` covers ALL FIVE dispatch branches, and
every constructor of `LoopRel` is used by a theorem about `step`.

**Result.** The loop model has a well-formedness invariant that discharges every hypothesis
`Loop/Bridge.lean` takes, proved for every state `Seed`/`Replay` can start from and preserved
by `step` — checkpoint **(iv), PROVED**. It has a denotation `sys : State → System` and an
abstract step relation `LoopRel`, assembled from the development's own relations plus five
named new constructors, each sound; **four of the five dispatch branches** — every one except
`learn`, the only branch that MINTS — are proved to be runs of it, and the deaths are
classified — checkpoint **(i), PARTIAL**, with the `learn` branch framed but not carried
through and the reason stated exactly. The four order properties the plan names are now
lemmas about `step`, and the single pass is proved with its two exceptions — checkpoint **(iii), DECIDED**; termination is **(T2)**: a quantitative bound
on the `learn` steps, the missing lemma named, no divergence witness found in 2,000 runs.

Nothing here is `sorry`, `Classical`-in-the-model, `axiom`, `partial` or `native_decide`;
`#print axioms` on every headline theorem gives exactly `[propext, Classical.choice,
Quot.sound]` (scratch file `/home/dmitry/.claude/jobs/880c725d/tmp/L3/Axioms.lean`).

| checkpoint | outcome |
|---|---|
| (iv) well-formedness | **PROVED** — `Wf`, `step_wf`, `run_wf`, `wf_seed`, `wf_replay`, bridge restated |
| (i) refinement | Round 1: 4 of 5 branches. **Round 2: PROVED for all five** (`step_refines_all`), at the shipped flags (`emptyRow`/`disjunction`/CSE-mint off) and under the supply hypotheses `SupOk`/`SupFresh`. **Those two are ASSUMED, not established: they are carried along a run by `RunSupOk`, a PER-STATE hypothesis, and are not proved preserved by `step`** (R2.1e says what preservation would cost). 4 of 7 deaths classified as refutations with proofs, one of them (message 4) extracted at the level of `step` |
| (ii) termination | **(T2)** — order lemmas + `learnChain_card`; the missing lemma is the loop-level MINT BOUND (§4c), and Round 2 adds the exact residual specification of the tighter relation it needs (R2.5) |
| (iii) Stage 7b | **DECIDED** — the pair cannot be re-examined while both premises are in `proc`; two escapes, both benign, and Round 2 proves the `NoSelfUnif` invariant that half of the "escape 1 is unreachable" argument needs (R2.4) |

## Build and audit

| | before | after |
|---|---|---|
| `lake build Rowpartition` | 833 jobs | **837 jobs**, success |
| `lake env lean Audit.lean` | `2530; 0` | **`Rowpartition theorems audited: 2834; declarations using a non-standard axiom: 0`** |

Files added (all new; the only edit to an existing file is four `import` lines in
`tracker/lean/Rowpartition.lean`, plus the additive README and plan-row edits this brief
allows):

| file | lines | what |
|---|---|---|
| `tracker/lean/Rowpartition/Loop/Wf.lean` | 1,565 | (iv): `Wf`, `step_wf`, `run_wf`, the initial states, the bridge restated |
| `tracker/lean/Rowpartition/Loop/Refine.lean` | 1,427 | (i): `sys`, `LoopRel` and its soundness, the three ENVIRONMENT branches, the `died` analysis |
| `tracker/lean/Rowpartition/Loop/RefineConcrete.lean` | 723 | (i): the label side of the `SSet → Finset` dictionary, and the `concrete` branch (`subPartitions`, `destructiveSub`, `makeConcrete`) |
| `tracker/lean/Rowpartition/Loop/Order.lean` | 552 | (ii)/(iii): the four order properties, the single pass, `learnChain_card` |
| **total** | **4,267** | |

---

## 1. (iv) Well-formedness — PROVED

### 1a. The invariant, verbatim

```lean
/-- Every partition a state carries: the incoming queue, then the processed queue. -/
def State.parts (s : State) : List LPart := s.incm.elems ++ s.proc.elems

/-- The state's LABEL POOL: every label it mentions anywhere. -/
def State.labels (s : State) : List Lbl := s.parts.flatMap (fun p => p.rhs.conc.elems)

structure COk (L : List Lbl) (s : SSet Lbl) : Prop where
  nodup : s.Nodup
  sub : ∀ x ∈ s.elems, x ∈ L

structure POk (L : List Lbl) (p : LPart) : Prop where
  abstr : p.rhs.abstr.Nodup
  conc : COk L p.rhs.conc

def QOk (L : List Lbl) (q : PQueue) : Prop := ∀ p ∈ q.elems, POk L p

structure Wf (s : State) : Prop where
  /-- Every incoming partition is duplicate-free in both components. -/
  incm : QOk s.labels s.incm
  /-- ... and every processed one. -/
  proc : QOk s.labels s.proc
  /-- The label indices separate the labels of this solve. -/
  coh : LblCoh s.labels
```

`Wf` is exactly the five hypotheses `Bridge.lean`'s `LPart.eqv_iff_toConstraint` takes — its
four `Nodup`s (stated once per partition rather than once per pair) and `LblCoh`.
`wf_of_nodup` shows the pool clause of `POk` is automatic for a partition that is already in
one of the state's own queues, so `Wf` asks for nothing beyond those five.

### 1b. The headline theorems, verbatim

```lean
theorem step_wf {s s' : State} (hw : Wf s) (h : step s = .continue s') : Wf s'

theorem run_wf : ∀ (n : Nat) {s : State} {res : RunResult}, Wf s → run s n = res →
    (∀ s', (res = .solved s' ∨ res = .outOfFuel s') → Wf s')

theorem wf_initial {L : List Lbl} {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    (hcs : ∀ c ∈ cs, CsItem.InPool L c) (hL : LblCoh L)
    (hq : buildQueue cs su = .ok (q, su'))
    (fl : Flags) (ns : Names) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := ns, site := site, su0 := lo }

theorem wf_seed (sd : Seed) (base : Nat) {su : Sup} {q : PQueue} {su' : Sup}
    (hq : buildQueue (seedSystem sd base).1 su = .ok (q, su'))
    (fl : Flags) (ns : Names) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := ns, site := site, su0 := lo }

theorem wf_replay {lines : List String} {g : Segment} (hg : g ∈ parseSegments lines)
    (hsets : ∀ c ∈ g.cons, CsItem.SetsOk c)
    {q : PQueue} {su' : Sup} (hq : buildQueue g.cons g.sup = .ok (q, su'))
    (fl : Flags) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := g.names, site := site, su0 := lo }

theorem LPart.eqv_iff_toConstraint_of_wf {s : State} (hw : Wf s) {p q : LPart}
    (hp : p ∈ s.parts) (hq : q ∈ s.parts) :
    p.eqv q = true ↔ p.toConstraint = q.toConstraint
```

The state in `wf_seed` / `wf_replay` is *verbatim* the `st0` of `Seed.lean`'s `solveSeed`,
which is the only state either entry point hands to `run`. The last theorem is the bridge with
NO side hypotheses, which is what L1 review F6 and L2 review F5 asked for.

### 1c. What the proof establishes on the way

The engine is two facts about every `SSet` operation the loop performs, proved once each and
then threaded through every rule and every dispatch branch:

* **membership** — `SSet.mem_incl/_excl/_filter/_inter/_concat/_removedAll/_ofList/_map/_champ`:
  every element of a result was an element of an argument. `concat`'s CHAMP branch needs
  `champ_perm` (from `Bridge.lean`) and `pickRep`'s two cases;
* **duplicate-freeness** — the `SSet.nodup_*` family already in `Bridge.lean`.

From those come `COk`/`POk` closure lemmas, one lemma per rule (`rhsMerge_ok`,
`rhsSubstitute_ok`, `selfSubstitution_ok`, `cancellation_ok`, `splitConcrete_ok`,
`resolution_ok`, `subBody_ok`, `substitution_ok`, `commonSubexpression_ok`,
`disjunction_ok`), one per step-level operation (`replace_ok`, `instantiate_ok`,
`unifyVars_ok`, `makeEmpty_ok`, `subPartitions_ok`, `destructiveSub_ok`, `makeConcrete_ok`,
`learnPartitions_ok`), and finally

```lean
theorem step_qok {L : List Lbl} {s s' : State} (hi : QOk L s.incm) (hp : QOk L s.proc)
    (h : step s = .continue s') : QOk L s'.incm ∧ QOk L s'.proc
```

— note the **fixed** pool `L`. As a corollary,

> **no rule of the solver ever introduces a label the system did not already have.**

That is worth recording on its own: `resolution`, `cancellation`, `splitConcrete`,
`substitution`, `commonSubexpression`, `disjunction`, `makeEmpty`, `makeConcrete`,
`destructiveSub` and `unify` all build their concrete parts by union, difference and
intersection of the premises' concrete parts. It is the loop-level analogue of
`CutConcrete`'s "the minting branch introduces no concrete label", and it is what bounds the
label half of the vocabulary in §4.

### 1d. Findings

* **F1 — `Replay`'s parser does not check that a `concRho` payload is a set** (input, not a
  defect). `parseTerm` reads the `scon` payload's comma-separated label indices and keeps them
  all (`.concRho ⟨c == 'C', ls.filterMap id⟩`), so a payload with a repeated index would give
  an `SSet` with a duplicate and `Nodup` would fail on the very first partition. On the
  compiler's side the payload is printed from a `scala.collection.immutable.Set`, so this
  cannot happen in a real trace; the model would accept it. `wf_replay` therefore carries the
  hypothesis `∀ c ∈ g.cons, CsItem.SetsOk c`, which is decidable and could be checked inside
  `replay` in one line. The seed path needs no such hypothesis (`seedSystem` builds every
  concrete part with `SSet.ofList`, which de-duplicates).
* **F2 — L2 review F5 discharged: `LblCoh` is a theorem about the parser, not an assumption.**
  `addRecord` accepts an `slbl` record only when its index equals the current table length
  (`slbl out of order` otherwise), so the table is numbered `0, 1, 2, …` by position;
  `lblCoh_of_table` turns that into `LblCoh`. `SegOk` is the invariant (`table`:
  `∀ i (hi : i < g.labels.length), (g.labels[i]'hi).n = i`; `cons`: every constraint read so
  far names only labels of the table), proved for `startSegment`, preserved by `addRecord` and
  `Segment.finish`, hence true of every segment `parseSegments` returns
  (`segOk_parseSegments`). On the seed side `Lbl.repro n` determines every field from `n`, so
  coherence is immediate (`lblCoh_seedPool`).
* **F3 — no hypothesis had to be weakened or dropped.** Every hypothesis the bridge needs is
  preserved by `step` from every initial state.

---

## 2. (i) Refinement — PARTIAL

### 2a. `sys`, verbatim, and why the environment is represented that way

```lean
/-- The fact an environment binding records. -/
def EnvVal.toConstraint (v : Nat) : EnvVal → Constraint
  | .emptyRow => mk v ∅ (∅ : Row)
  | .alias u => mk v {u} (∅ : Row)

def Env.sys (e : Env) : System :=
  (e.binds.map (fun p => EnvVal.toConstraint p.1 p.2)).toFinset

/-- The system a loop state denotes. -/
def sys (s : State) : System := (s.parts.map LPart.toConstraint).toFinset ∪ s.env.sys
```

**Justification.** `instantiateType(v, ConcreteRho(∅))` is `v <- ()` — exactly the constraint
`KeyedEmpty.makeEmptyE` RETAINS, and the precedent the brief names; `instantiateType(v,
VarT(u))` is `v <- (u)`, which is what "`v` is now a name for `u`" means as a partition.
Dropping the environment from `sys` would be wrong in both directions: `makeEmpty` would look
like an unjustified deletion, and `-Dermine.emptyRow`'s lookup, which reads the environment
back (`findEmptyRow`), would consult a fact the denotation does not contain.

### 2b. `LoopRel`, verbatim

```lean
inductive LoopRel : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → LoopRel G G'
  | split {G G' : System} : K2SplitStep G G' → LoopRel G G'
  | res {G G' : System} : ResStep G G' → LoopRel G G'
  | kres {G G' : System} : K2ResStep G G' → LoopRel G G'
  | emptyE {G : System} {v : Var} : mk v ∅ (∅ : Row) ∈ G → LoopRel G (makeEmptyE v G)
  | weaken {G G' : System} : G' ⊆ G → LoopRel G G'
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → LoopRel G (insert (mk b S K) G)
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → LoopRel G (insert (mk b {a} (∅ : Row)) G)
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      LoopRel G (insert (mk x ∅ (∅ : Row)) G)
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      LoopRel G (insert (mk x ∅ (∅ : Row)) G)

abbrev LoopRun : System → System → Prop := Relation.ReflTransGen LoopRel
```

The first five constructors are the development's own relations, imported unchanged:
`SplitNecessary.NonGenStep` (CSE reuse and fold, `splitConcrete`'s syntactic reuse,
cancellation, substitution, self-substitution, common partition), `KeyedRow.K2SplitStep`
(`splitConcrete`'s syntactic / `splitKey` / `splitRow` reuse and its mint), `Cut.ResStep`
(`resolution`'s mint), `KeyedRow.K2ResStep` (`resGuard` and `resRow` reuse), and
`KeyedEmpty.makeEmptyE`.

### 2c. The FIVE new constructors and their soundness lemmas

| constructor | what in the loop | soundness lemma |
|---|---|---|
| `weaken` | every DELETION (`instantiate`'s removal, `makeEmpty`'s erasure, `destructiveSub`) and every DROP (`trim`, `++!`'s already-present test, `insertNP`'s self-unification test) | `SModels.mono` — a subsystem has every model |
| `renameLhs` | `replace`'s `f p.lhs`: an alias rewrites the LEFT-hand side too, which no rule of the calculus does | `renameLhs_sat` |
| `linkSymm` | `unify(u, v)` on a dequeued `v <- (u)` instantiates `u := v`, i.e. reads the link backwards | `linkSymm_sat` |
| `emptyProp` | `makeEmpty`'s `aux`: an empty whole with an all-variable definition forces every part empty — `makeEmptyD`'s `propPart` as a single conclusion | `emptyProp_sat` |
| `dedup` | `RHS.merge`'s returned `es` and `replace`'s two-element queue: a variable that lands twice among the disjoint parts of one partition is empty | `dedup_sat` |

Two candidates the brief lists turned out NOT to need a new constructor:

* **the `common` redirect** (`Q.+!`'s `CommonPartition`) is exactly
  `SplitNecessary.CommonPartStep`: two constraints with the same variable set and the same
  concrete part entail `a <- (b)`. `insertP_run` proves the redirect is that step;
* **`replace`'s right-hand rewrite** is exactly `SplitNecessary.SubstStep` at `d = mk a {b} ∅`
  (`substResult` then reads `mk c.lhs ((vset c).erase a ∪ {b}) (c.conc ∪ ∅)`), and
  `makeEmpty`'s erasure of `v` is the same step at `d = mk v ∅ ∅`.

Soundness of the whole relation, verbatim:

```lean
def SSat (G : System) : Prop := ∃ rho, SModels rho G

theorem LoopRel.sat {G G' : System} (h : LoopRel G G') : SSat G → SSat G'
theorem LoopRun.sat {G G' : System} (h : LoopRun G G') : SSat G → SSat G'
```

One direction only, as the deleting steps of the library have. For the four non-minting new
constructors the model set does not move at all (the proofs produce the SAME `rho`); the
minting constructors reuse `K2SplitStep.extend`, `ResStep.satisfiable_iff` and
`K2ResStep.extend`.

### 2d. What is PROVED about `step`

```lean
/-- The three dispatch branches that write the substitution ENVIRONMENT. -/
def LinkOrEmptyStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ (r.rhs.single?).isSome = true

/-- Every dispatch branch except `learn` -- the only one that MINTS. -/
def NonLearnStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨
    r.rhs.abstr.isEmpty = true ∨ (r.rhs.single?).isSome = true

theorem step_refines {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopRun (sys s) (sys s')

theorem step_refines_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStep s)
    (h : step s = .continue s') : LoopRun (sys s) (sys s')

theorem step_sat_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s')

theorem run_sat_nonlearn : ∀ (n : Nat) {s : State}, Wf s → RunNonLearn n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → SSat (sys s')

theorem run_refutes_nonlearn : ∀ (n : Nat) {s : State}, Wf s → RunNonLearn n s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' → ¬ SSat (sys s') → ¬ SSat (sys s)

theorem step_died_sys {s s' : State} {m : String} (h : step s = .died m s') : sys s' = sys s
```

(`run_sat` / `run_refutes` are the same two run-level statements under the narrower
`RunLinkOrEmpty`.) `step_died_sys` holds for ALL five branches: a death is raised before
either queue or the environment is written.

**Scope of the run-level statements (corrected in Round 2).** `run_sat` / `run_refutes` and
`run_sat_nonlearn` / `run_refutes_nonlearn` require the WHOLE run to avoid the `learn` branch
(`RunLinkOrEmpty` / `RunNonLearn`), which no real solve does. Round 2's `run_sat_all` /
`run_refutes_all` remove that restriction; they carry the supply invariant instead.

Supporting theorems, all proved:

* the queue: `insertP_run` and `concatP_run` (`Q.+!`, redirect included), `mem_insertNP`,
  `mem_concatNP`, `rhsLookup_witness`, `findRHS_witness`;
* the bridge in the form the reverse lookups need: `toConstraint_congr`;
* the VARIABLE side of the `SSet → Finset` dictionary:
  `SSet.fs_concat/_removedAll/_inter/_excl/_incl/_ofList/_map`, from the two-directional
  membership lemmas `SSet.mem_*_iff`;
* the LABEL side: `cfs`, `cfs_concat` (free), `cfs_removedAll` and `cfs_inter` (both under
  `LblCoh`, which is where `Wf` earns its keep a second time), `cfs_eq_empty_iff`;
* `unify`: `replace_run`, `instantiate_run`, `unifyVars_run`, `env_instantiate_alias_run`;
* `makeEmpty`: `makeEmpty_run`, `env_instantiate_empty_run`;
* `makeConcrete`: `eraseAll_run`, `subst_one_run`, `subPartitions_run`, `destructiveSub_run`,
  `cancellation_run`, `makeConcrete_run`.

The `concrete` branch is where the LABEL arithmetic lives, and the correspondence is exact:
`subPartitions` at a definition `v <- (S', K')` is `SubstStep` followed by one `SubstStep`
per variable that lands twice — and each of those is known EMPTY by the new `dedup`
constructor, which is precisely what `RHS.merge`'s returned `es` records; `makeConcrete`'s
`can` fold is `CancelStep`, and only its SECOND branch can fire, because the concrete row's
variable part is empty and the first branch wants exactly one variable left over on that
side. `destructiveSub`'s deletions and its kept two-abstract definitions are `weaken` and
membership.

### 2e. What is NOT proved, stated plainly

The brief asks for `step s = .continue s' → LoopRel* (sys s) (sys s')` for every `Wf s`. What
is proved is that statement with the extra hypothesis `NonLearnStep s`:

| original (brief) | proved |
|---|---|
| `Wf s → step s = .continue s' → LoopRun (sys s) (sys s')` | `Wf s → NonLearnStep s → step s = .continue s' → LoopRun (sys s) (sys s')` |

**One branch is uncovered: `learn`, and it is the one that MINTS.** Three things are missing,
and only the last two are deep:

1. the rule-by-rule assembly itself (`selfSubstitution` is `SelfSubstStep`, `cancellation` is
   `CancelStep`, `substitution` is `SubstStep` + `dedup` + `SubstStep` exactly as
   `subPartitions` is in §2d, `commonSubexpression`'s reuse and fold branches are `CutStep`,
   `splitConcrete`'s syntactic reuse is `SplitReuseStep`) — bookkeeping over the same
   dictionary, not written for time;
2. **fresh-name bookkeeping for the mints.** `Cut.SplitStep` and `Cut.ResStep` require
   `z ∉ allVars G`; the loop's `z` comes from `Supply.fresh`. Threading that through
   `learnPartitions`' fold needs the supply to be injective on its future draws, and
   `Sup.ofSeed lo = ⟨lo, lo + 100000, 0, 1024⟩` sets the global block counter to the
   PLACEHOLDER `0`, so the model's own seed supply is injective only for its first 100 000
   draws (after that `fresh` would hand out `0`, `1`, …). No seed comes near that, and the
   replay supply carries the compiler's real block counter, but the invariant cannot be
   stated unconditionally over `Sup` as it stands. **This is a finding about the model**
   (`Loop/State.lean`'s `Sup.ofSeed`), reported here rather than worked around;
3. ~~the MINT GUARDS~~ — **withdrawn in Round 2 after the review's F1.** `Cut.ResApp` has NO
   guard at all beyond the two premises, the two nonempty differences and freshness, and
   `Cut.SplitApp`'s only guard `¬ Named G (vset c)` IS the syntactic lookup missing
   (`findRHS3` scans both queues, and at `2 ≤ |S|` no environment fact and not the dequeued
   premise itself can have `vset = S` with an empty concrete part). So the guard mismatch does
   NOT block (i); it blocks the (ii) BOUND, where `K2MintApp.uncarried : ¬ Carried G v K` is
   needed and `KeyedRowScala`'s `concRow_none_uncarried` is the obstacle. Round 2 proves the
   `learn` branch and this item is closed.

### 2f. The `died` paths, and which are refutations

`step` can die with exactly seven messages. (`rhsBuild`'s two errors and `labelClash` are
raised by `buildQueue` / `Subst.solve` around the loop, not by `step`.)

| # | message | raised by | branch | refutation? |
|---|---|---|---|---|
| 1 | `Fields appear twice in row: …` | `RHS.merge` (`Rules.lean:43`) | `learn` (via `substitution`), `concrete` (via `subPartitions`) | **YES (system-level)** — `merge_refutes`; no loop-level extraction |
| 2 | `Infinite row partition for 'v'` | `selfSubstitution` (`Rules.lean:56`) | `learn` | **YES (system-level)** — `selfSubst_refutes`; no loop-level extraction |
| 3 | `panic: reinstantiated type v to u but it was already bound` | `instantiate` (`Step.lean:89`) | `common`, `unify` | **no** — internal-invariant failure |
| 4 | `Incompatible instantiations of 'v'` | `makeEmpty` (`Step.lean:127`) | `empty` | **YES (system-level AND loop-level)** — `incompatible_refutes`, `makeEmpty_died`, and `step_died_empty` |
| 5 | `Cannot unify skolem variable with empty relation v` | `makeEmpty` (`Step.lean:131`) | `empty` | **no** — a KINDING error, as the brief says |
| 6 | `panic: reinstantiated type v to ConcreteRho(-,Set()) …` | `makeEmpty` (`Step.lean:133`) | `empty` | **no** — internal-invariant failure |
| 7 | `Row types failed to unify: R1 = … R2 = …` | `ensureSuperset` (`Step.lean:182`) | `concrete` | **YES (system-level)** — `ensureSuperset_refutes`; no loop-level extraction |

The four refutation lemmas, verbatim:

```lean
theorem selfSubst_refutes {G : System} {v : Var} {S : Finset Var} {K : Row}
    (hmem : mk v S K ∈ G) (hself : v ∈ S) (hK : K ≠ ∅) : ¬ SSat G

theorem merge_refutes {G : System} {c v : Var} {S S' : Finset Var} {K K' : Row}
    (h1 : mk c S K ∈ G) (h2 : mk v S' K' ∈ G) (hv : v ∈ S) (hne : (K ∩ K').Nonempty) : ¬ SSat G

theorem incompatible_refutes {G : System} {v : Var} {S : Finset Var} {K : Row}
    (h1 : mk v ∅ (∅ : Row) ∈ G) (h2 : mk v S K ∈ G) (hK : K ≠ ∅) : ¬ SSat G

theorem ensureSuperset_refutes {G : System} {v : Var} {S : Finset Var} {K C : Row}
    (h1 : mk v ∅ C ∈ G) (h2 : mk v S K ∈ G) (hnsub : ¬ K ⊆ C) : ¬ SSat G
```

and the loop-level statement for the branch that is refined, which also says exactly which
deaths are the exceptions:

```lean
theorem makeEmpty_died {G : System} {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {m : String}
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hv : mk v ∅ (∅ : Row) ∈ G)
    (h : makeEmpty ns v incm proc env = .error m) :
    ¬ SSat G ∨
      m = "Cannot unify skolem variable with empty relation " ++ varStr ns v ∨
      m = "panic: reinstantiated type " ++ varStr ns v ++ " to ConcreteRho(-,Set())" ++
          " but it was already bound"
```

**What is and is not proved here (corrected in Round 2 after the L3 review's F2).** The four
lemmas above are SYSTEM-level: they say a system with those premises has no model. Only
message 4 has, in Round 1, a LOOP-level extraction (`makeEmpty_died`, which is about
`makeEmpty`, not about a `step` death); Round 2 adds `step_died_empty`, which is about a
`step` death and plugs into `run_refutes_all`. For messages 1, 2 and 7 the loop-level
extraction — from the internals of `makeConcrete`'s `ensureSuperset` fold and of
`learnPartitions` down to the premises as members of `sys s` — is still NOT written.
`run_refutes` / `run_refutes_all` take `¬ SSat (sys s')` as a HYPOTHESIS: they are contraposed
satisfiability-preservation, and it is `step_died_empty` that discharges the hypothesis for
the one branch where the extraction exists.

Two further remarks, for completeness:

* `rhsBuild`'s build-time `Fields appear twice in row` is also a refutation (an input `Part`
  that lists a label twice makes two parts of one whole overlap), and its `panic: Malformed
  constraint, RHS` is not (it is a shape error). Both are outside `step`.
* `labelClash` — the per-label refutation `Subst.solve` runs before the loop under
  `labelCheckEarly` — is a refutation, and that is `LabelAlgo`'s theorem, not re-proved here.

---

## 3. (iii) The Stage 7b question — DECIDED

**The answer: in the loop the pair cannot fire twice, and the mint cannot chain, unless a
variable of one of the two premises is ELIMINATED in between.**

`resolution` is called from `learnPartitions`' fold over `proc`, with `rhs1` the right-hand
side of the DEQUEUED partition and `rhs2` that of a processed partition at the same left-hand
side. So the premise pair is always `(r, p₂)` with `r` dequeued and `p₂ ∈ proc`. The theorem:

```lean
theorem res_pair_single_pass {s s' : State} {r p₂ : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (hp₂ : p₂ ∈ s.proc.elems) (h : step s = .continue s') :
    r ∈ s'.proc.elems ∧ p₂ ∈ s'.proc.elems ∧
      ∀ x ∈ s'.incm.elems, x ∈ rest.elems ∨ p₂.eqv x = false ∨ IsRedirect x
```

built from

```lean
theorem trim_refuses {ps : SSet LPart} {cs : PQueue} {x : LPart}
    (hx : x ∈ (trim ps cs).elems) : ∀ y ∈ cs.elems, y.eqv x = false

theorem learn_single_pass {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') :
    (∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∧
    r ∈ s'.proc.elems ∧
    (∀ x ∈ s'.incm.elems, x ∈ rest.elems ∨ (∀ y ∈ s.proc.elems, y.eqv x = false) ∨
      IsRedirect x)
```

**So: can a re-derivation of an identical partition pass `trim`?** For any partition that is
in `proc`, **NO** — `trim` filters exactly on `cs.contains`, which is `Partition.equals`
against every element of `proc`, and `++!` then filters again against the incoming queue.
There are exactly two escapes, and both are named in the statement:

1. **the dequeued partition `r` itself.** It is returned to `proc` only AFTER `trim` has run
   (`trim learned s.proc` uses the OLD `proc`; this is also why the trace tags such a record
   `new` rather than `seen`), so a rule that re-derives `r` in the same batch does enqueue it.
   That re-enqueueing is **self-cancelling**:

   ```lean
   theorem common_self_drops {s : State} {rest : PQueue} {x : LPart}
       (hd : s.incm.dequeue = some (x, rest)) (hlhs : s.proc.findRHS x.rhs = some x.lhs) :
       ∃ s' : State, step s = .continue s' ∧ s'.incm = rest ∧ s'.proc = s.proc ∧
         s'.env = s.env
   ```

   — at its next dequeue `proc.findRHS` finds `r`, the COMMON branch fires at `u = r.lhs`, and
   `unify` at equal variables is the identity: the partition is simply dropped, no rule runs.
2. **the queue-level `CommonPartition` redirect** (`IsRedirect x`), which `Q.+!` substitutes
   for an insertion whose right-hand side is already in the queue. It is a NAMING constraint
   `w <- (a)`, not a re-derivation of the premise, and it has a single abstract part, so the
   dispatch sends it to `unify`, never to `resolution`.

**And when CAN the pair be examined again?** Only after one of the two leaves `proc`, and

```lean
theorem step_proc_mono {s s' : State} (h : step s = .continue s') :
    ∃ v : Nat, ∀ p ∈ s.proc.elems, p.involves v = false → p ∈ s'.proc.elems
```

says a partition leaves `proc` only if it MENTIONS the variable the step eliminates — `learn`
removes nothing, and each of `common`, `unify`, `empty`, `concrete` removes exactly the
partitions naming the variable it binds or concretises.

**Scope.** The model carries the `emptyRow` flag (default off) and therefore Stage 7's
`SplitEmpty` / `ResolutionEmpty` branches; it does NOT carry Stage 7b's variant
("reuse if it adds a fact, else the shipped mint"), which lives in the `emptyrow-profiling`
worktree. The lemmas above are about the LOOP's control flow — which premise pairs
`learnPartitions` can present to `resolution`, and what `trim`/`++!` let back into the queue —
and none of them depends on which branch `splitConcrete` or `resolution` takes. So the answer
transfers to the variant without modelling it: **the variant's fallback mint cannot chain
through a repeated firing of the same premise pair**; it can only fire again after an
elimination has removed one of the premises from `proc`. What a faithful answer would still
need, if the question were widened from "can the same pair fire twice" to "can the variant
mint without bound", is the variant itself in the model, because then the question is about
which branch fires, not about the order — that is stated here rather than modelled, as the
brief allows.

---

## 4. (ii) Termination — (T2)

### 4a. The statement

```lean
def Finished : RunResult → Prop
  | .outOfFuel _ => False
  | _ => True

/-- Iterated `step` reaches `done` or `died` within some number of dequeues. -/
def Terminates (s : State) : Prop := ∃ n : Nat, Finished (run s n)

theorem run_mono : ∀ (n : Nat) (s : State), Finished (run s n) → Finished (run s (n + 1))
theorem terminates_of_empty {s : State} (h : s.incm.dequeue = none) : Terminates s
```

### 4b. The four order properties, now lemmas about `step`

| plan's property | theorem |
|---|---|
| single pass | `trim_refuses`, `learn_single_pass`, `step_proc_mono` (§3) |
| eager `makeEmpty` | `step_empty_branch` |
| eager `unify` | `step_unify_branch`, `step_common_branch` |
| names travel with their groups | `step_proc_mono` is the half that matters for the measure: a partition survives a step unless it names the eliminated variable. The complementary half — that after `unify(v,u)` NO partition of either queue still names `v` — is not proved; see §4c(3) |

`step_empty_branch` / `step_unify_branch` / `step_common_branch` each say that `step` reduces
to exactly one call (`makeEmpty`, `unifyVars`) with the queues and environment untouched — so
`learnPartitions` is not reached, which is what "eager" means.

### 4c. The quantitative bound, and the missing lemma

```lean
def procSys (s : State) : System := (s.proc.elems.map LPart.toConstraint).toFinset

theorem learn_procSys_lt {s s' : State} {r : LPart} {rest : PQueue} (hw : Wf s)
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') :
    (procSys s).card < (procSys s').card

theorem learnChain_card : ∀ (n : Nat) {s t : State}, Wf s → LearnChain n s t →
    (procSys s).card + n ≤ (procSys t).card
```

That is the first half of the measure the brief sketches, and it is unconditional: **every
`learn` step is paid for by a genuinely new constraint in the processed queue.** The proof is
where `Wf` earns its keep — `r.toConstraint ∉ procSys s` because otherwise
`LPart.eqv_iff_toConstraint_of_wf` would make `r` `Partition.equals` to a processed partition
and `findRHS` would have hit, taking the COMMON branch instead.

**What is missing, exactly.**

1. **A bound on `(procSys t).card` along a run** — equivalently a bound on the VOCABULARY. The
   LABEL half is proved: §1c shows no rule ever introduces a label, so the concrete parts stay
   inside the initial pool. The VARIABLE half is not: `splitConcrete`'s and `resolution`'s
   mints draw fresh ids. At the RELATION level this is exactly
   `KeyedRow.mintsBoundedOnSatKeyed2Star` (proved) together with
   `KeyedEmpty.mintsBoundedOnSat_emptyPersisting` / `mintsBoundedOnSatKeyed3E`; transporting
   it to the loop needs the `learn` branch of the refinement, which §2e says is open, plus the
   fresh-name bookkeeping §2e blocks on. **The missing lemma is
   `∀ n t, LoopReach n s t → (allVars (sys t)).card ≤ N` for satisfiable `sys s`**, and it
   resists for the reason `KeyedRowScala.concRow_none_uncarried` records: the loop's mint
   guard is a QUEUE lookup and the relation's is a WHOLE-SYSTEM predicate, so the two do not
   line up without re-deriving `KeyedRowScala`'s adequacy against `sys`.
2. **A bound on the NON-`learn` steps.** `common` (at distinct variables), `unify` and `empty`
   each add one binding to the environment, and the model dies with a reinstantiation panic
   if a variable is bound twice — so along a run that does not die they are bounded by the
   number of variables, i.e. again by (1). `concrete` binds nothing: bounding it needs the
   argument that after `makeConcrete v C` the partition `v <- ((|C|))` is in `proc` and that a
   later `concrete` at `v` must have `C ⊊ C'` (by `ensureSuperset`), so at most `|labels|`
   times per variable — which needs `v <- ((|C|))` to survive, i.e. `step_proc_mono` plus the
   fact that `v` is not itself eliminated. Not written.
3. **Name travel, the second half.** `step_proc_mono` gives what the measure needs; the
   stronger statement — after `unify(v,u)` no partition of either queue mentions `v`, so a
   variable can be eliminated only once — is what would turn (2) into a clean count. It is
   provable (the fold in `instantiate` rewrites every partition it removed, and the redirect's
   left-hand side comes from a queue that was already filtered) but was not written.

### 4d. Outcome, and the search for a witness

**(T2).** Not (T1): there is no bound. Not (W): no witness was found, and none is expected.

Evidence, run with `lake exe looptrace`:

| population | result |
|---|---|
| the tracked seeds `W2 W3 W4 G7 H2 NE6 CHAIN COLL LBL RR RE` × bases 0, 3, 7, fuel 2 000 | 33/33 `SOLVED`, 0 `FUEL` |
| 400 randomly generated SATISFIABLE systems (built by unioning pairwise-disjoint label sets, so a model exists by construction), × bases 0 and 5, fuel 3 000 | 800/800 `SOLVED`, 0 `FUEL` |
| the same 400 at `--flags=emptyrow`, `--flags=all` (CSE minting on) and `--flags=nongen` | 1 200/1 200 `SOLVED`, 0 `FUEL` |

The generator and seeds are in the job scratch
(`/home/dmitry/.claude/jobs/880c725d/tmp/L3/fuzz/`). `W2`, `W3`, `W4` and `G7` are the seeds
on which the RELATIONS diverge (`DefaultSatDiverge.not_TerminatesOnSat`,
`KeyedLoop.not_TerminatesOnSatKeyedLoop`, `KeyedRow.not_MintsBoundedOnSatKeyed2`,
`KeyedEmpty.G7_mints`); the loop solves all of them. That is the empirical form of the claim
this whole programme exists to prove, and it is why (T2) rather than (W) is the honest
outcome: the obstacle is the missing bound, not a counterexample.

**Unsatisfiable input, as the brief asks.** Out of scope for the bound, and `not_CRule`
stands. Whether `step` can loop on it is **not decided here**: the 400 generated systems are
satisfiable by construction and no unsatisfiable divergent seed was searched for. The relation
does diverge on unsatisfiable input (`DefaultDiverge`, `ResGuardDiverge`), and nothing proved
here rules the loop out — the `learn`-step bound of §4c is about the growth of `procSys`, and
is indifferent to satisfiability; it is the VOCABULARY bound that needs a model.

---

## 5. Summary of everything not proved

| asked for | delivered | why not more |
|---|---|---|
| (iv) `Wf` for every initial state and preserved by `step` | **all of it** | — |
| (i) `step s = .continue s' → LoopRun (sys s) (sys s')` for every `Wf s` | the same with the extra hypothesis `NonLearnStep s` — the `common`, `empty`, `unify` and `concrete` branches, i.e. everything except the one that MINTS | the `learn` branch needs fresh-name bookkeeping that `Sup.ofSeed`'s `blk = 0` placeholder blocks, and the mint-guard translation `KeyedRowScala` does for a modelled system (§2e) |
| (i) `died` ⇒ input unsatisfiable, for the refuting deaths | all four refutations proved at system level; the loop-level extraction proved for `Incompatible instantiations` and composed into `run_refutes` / `run_refutes_nonlearn` | the other three need the extraction from `ensureSuperset`'s fold (bookkeeping) and from `learnPartitions` (§2e) |
| (ii) `Terminates` for every satisfiable `Wf s₀`, with a bound | the `learn`-step half of the bound, unconditional; the order properties as lemmas | the vocabulary bound (§4c(1)) is the missing lemma |
| (iii) can the 7b mint chain? | decided, with the two escapes from `trim` identified and one of them proved self-cancelling | the variant itself is not in the model; the answer given is about the loop's control flow and transfers without it (§3, Scope) |


---

# Round 2 — 2026-09-04, after `tracker/loopmodel/L3-REVIEW.md` (FIX-THEN-ADVANCE)

The review's verdict was FIX-THEN-ADVANCE with eight findings. This round does the work the
orchestrator specified, in the order specified. Everything below is new since the Round-1 text
above; where Round 1 over-claimed, the Round-1 text itself has been corrected in place and the
correction is marked.

| | before Round 2 | after Round 2 |
|---|---|---|
| `lake build Rowpartition` | 837 jobs | **838 jobs**, success |
| `lake env lean Audit.lean` | `2834; 0` | **`Rowpartition theorems audited: 2935; declarations using a non-standard axiom: 0`** |
| new-module lines | 4,267 | **6,347** |
| `sorry` / `axiom` / `partial` / `native_decide` in the five modules | 0 | **0** |

| file | lines | round |
|---|---|---|
| `Rowpartition/Loop/Wf.lean` | 1,565 | 1 |
| `Rowpartition/Loop/Refine.lean` | 1,478 | 1, edited in 2 (`splitFree` added, `emptyE` removed, one no-op `weaken` removed) |
| `Rowpartition/Loop/RefineConcrete.lean` | 757 | 1, edited in 2 (vocabulary clause on `eraseAll_run` / `subst_one_run`) |
| `Rowpartition/Loop/RefineLearn.lean` | 1,558 | **2** |
| `Rowpartition/Loop/Order.lean` | 989 | 1, extended in 2 (`step_died_empty`, the self-unification invariant, and — after the re-review — `NoInfRow`) |

`#print axioms` for all 31 new headline theorems:
`/home/dmitry/.claude/jobs/880c725d/tmp/L3/Axioms2.lean` — 26 report
`[propext, Classical.choice, Quot.sound]`, 3 report `[propext, Quot.sound]`, 1 reports
`[propext]`, and `noInfRow_initial` depends on no axioms at all; no non-standard axiom.

---

## R2.1 — (i) the `learn` branch: PROVED (review F1)

Done exactly per the review's §6c, in its order.

### R2.1a `LoopRel` gains one constructor

```lean
  /-- `splitConcrete`'s MINT with `Cut.SplitApp`'s SYNTACTIC guard -- which is exactly what
  the loop's `findRHS3` lookup missing gives, and which needs none of `Carried`. -/
  | splitFree {G G' : System} : SplitStep G G' → LoopRel G G'
```

soundness case `| splitFree h => exact h.satisfiable_iff.mp ⟨rho, hm⟩`. `commonSubexpression`'s
MINT is excluded by a flag hypothesis (`fl.cseMints = false`, the shipped `genRules=cut`)
rather than by a `cse` constructor, so that every constructor stays live (R2.2).

### R2.1b The supply invariant, verbatim, with the five lemmas in the review's order

```lean
/-- The ids the supply can still hand out. -/
def Sup.Reach (su : Sup) (z : Nat) : Prop := (su.lo ≤ z ∧ z < su.hi) ∨ su.blk ≤ z

structure SupOk (su : Sup) : Prop where
  lohi : su.lo ≤ su.hi
  ahead : su.hi ≤ su.blk
  bsz : 2 ≤ su.bsz

/-- No id the supply can still produce is already in use. -/
def SupFresh (su : Sup) (G : System) : Prop := ∀ z, Sup.Reach su z → z ∉ allVars G

theorem fresh_reach {su : Sup} (h : SupOk su) : Sup.Reach su (su.fresh).1
theorem fresh_supOk {su : Sup} (h : SupOk su) : SupOk (su.fresh).2
theorem fresh_reach_mono {su : Sup} (h : SupOk su) :
    ∀ z, Sup.Reach (su.fresh).2 z → Sup.Reach su z ∧ z ≠ (su.fresh).1
theorem SupFresh.mono_allVars {su : Sup} {G G' : System} (h : SupFresh su G)
    (hsub : allVars G' ⊆ allVars G) : SupFresh su G'
theorem SupFresh.step {su : Sup} {G G' : System} (hok : SupOk su) (h : SupFresh su G)
    (hv : ∀ w ∈ allVars G', w ∈ allVars G ∨ w = (su.fresh).1) : SupFresh (su.fresh).2 G'
/-- The drawn id is fresh: this is exactly `Cut.SplitApp.fresh` / `Cut.ResApp.fresh`. -/
theorem fresh_notMem {su : Sup} {G : System} (hok : SupOk su) (h : SupFresh su G) :
    (su.fresh).1 ∉ allVars G
```

`SupFresh.mono_allVars` is stated with the vocabulary rather than with `⊆`, because the
non-minting rules GROW the system while leaving `allVars` alone; `SupFresh.sub` is the review's
`SupFresh.mono` as a corollary.

**`Sup.ofSeed` was NOT touched** (review F6). Recorded, as asked: every REPLAY state satisfies
`SupOk` — `Replay.lean`'s `Segment.sup` takes `lo`, `hi`, `blk` and `bsz` from the trace's
`sin` record (`RowTrace.scala`), i.e. the compiler's own `Supply` and its process-global
`Supply.block`, which is always ahead of the block it handed out — while a SEED state does not
past 100 000 draws, because `tracker/repro/nameloss/Replay.scala` builds
`new Supply(lo, lo + 100000)` and `scalaparsers/Supply.scala`'s `private var block: Int = 0`
starts at zero. That is a fact about the repro harness, not a defect of the model.

### R2.1c The rules, in the review's order

Each in the shape `∃ H, RuleRun G S su' H` where

```lean
def RuleRun (G : System) (S : SSet LPart) (su' : Sup) (H : System) : Prop :=
  LoopRun G H ∧ G ⊆ H ∧ (∀ p ∈ S.elems, p.toConstraint ∈ H) ∧ SupOk su' ∧ SupFresh su' H
```

— the supply invariant re-established for the supply the rule RETURNS, which is what lets the
fold thread it.

| Scala rule | theorem | relation used |
|---|---|---|
| `selfSubstitution` | `selfSubstitution_run` | `SelfSubstStep` |
| `cancellation` (general position; `RefineConcrete`'s is the specialised one) | `cancellationG_run` | `CancelStep`, both branches |
| `subBody` / `substitution` | `subBody_run`, `substitution_run` | `SubstStep` + `dedup` + `SubstStep` (via `subst_one_run`) |
| `commonSubexpression` (reuse and both folds) | `commonSubexpression_run` | `CutStep.reuse`, `CutStep.fold` |
| `splitConcrete` (syntactic / keyed / concrete-row reuse, and the MINT) | `splitConcrete_run` | `SplitReuseStep`, `K2SplitStep.key`, `K2SplitStep.row`, `Cut.SplitStep` |
| `resolution` (guarded and concrete-row reuse, and the MINT) | `resolution_run` | `K2ResStep.reuse`, `K2ResStep.row`, `Cut.ResStep` |
| `disjunction` | excluded by `fl.disjRule = false` | — |
| the `emptyRow` branches of `splitConcrete` / `resolution` | excluded by `fl.emptyRow = false` | — (plan's M4) |

The three reverse lookups are proved SOUND on the way, which is the part the review's §6b said
was the safe direction:

```lean
theorem findRHS3_names {L : List Lbl} (hcoh : LblCoh L) {ps cs : PQueue} {S : SSet LPart}
    {a : SSet Nat} {w : Nat} {H : System} (hna : a.Nodup)
    (hQ : ∀ p, (p ∈ ps.elems ∨ p ∈ cs.elems ∨ p ∈ S.elems) → POk L p ∧ p.toConstraint ∈ H)
    (h : findRHS3 ps cs S (RHS.ofAbstr a) = some w) : Rowpartition.Names H w a.fs

theorem findResolvent_sound {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {l : Lookups}
    {S : SSet LPart} {k : SSet Lbl} {w : Nat} {H : System} {Q : List LPart}
    (hlk : LookupsOk Q v l) (hQ : ∀ p ∈ Q, POk L p ∧ p.toConstraint ∈ H)
    (hS : ∀ p ∈ S.elems, POk L p ∧ p.toConstraint ∈ H) (hk : COk L k)
    (h : findResolvent v l S k = some w) : mk v {w} (cfs k) ∈ H

theorem findConcRow_sound {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {l : Lookups}
    {k : SSet Lbl} {w : Nat} {H : System} {Q : List LPart}
    (hlk : LookupsOk Q v l) (hQ : ∀ p ∈ Q, POk L p ∧ p.toConstraint ∈ H) (hk : COk L k)
    (h : findConcRow l k = some w) : ∃ C : Row, mk v ∅ C ∈ H ∧ mk w ∅ (C \ cfs k) ∈ H
```

with `LookupsOk` — every entry of either map, and the recorded own row, comes from a partition
of the two queues — proved for `mkLookups` (`mkLookups_ok`). The lookups consult the BATCH as
well as the queues (`Constraints.scala`'s `findResolvent(s)` and `findRHS(incm, proc, s)`), and
the fold's invariant carries `∀ p ∈ s, p.toConstraint ∈ H` for exactly that reason, as the
review's §6c item 4 warned.

### R2.1d `learnPartitions` and the `learn` branch, verbatim

```lean
theorem learnPartitions_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {fl : Flags}
    {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup}
    {S : SSet LPart} {su' : Sup}
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hok : SupOk su) (hfr : SupFresh su G)
    (hpOk : QOk L proc) (hiOk : QOk L incm) (hrOk : ROk L rhs1)
    (hpG : ∀ p ∈ proc.elems, p.toConstraint ∈ G) (hiG : ∀ p ∈ incm.elems, p.toConstraint ∈ G)
    (hrG : mk v rhs1.abstr.fs (cfs rhs1.conc) ∈ G)
    (hunnamed : cfs rhs1.conc ≠ ∅ → 2 ≤ rhs1.abstr.fs.card →
      findRHS3 incm proc SSet.empty (RHS.ofAbstr rhs1.abstr) = none →
      ¬ Rowpartition.Named G rhs1.abstr.fs)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∃ H : System, RuleRun G S su' H

theorem step_refines_learn {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hb : ¬ NonLearnStep s) (h : step s = .continue s') : LoopRun (sys s) (sys s')
```

`hunnamed` is discharged inside `step_refines_learn` from `findRHS3_none` plus two facts about
`sys s` that only hold in the mint's own branch, which is why it takes the branch's two guards:
the DEQUEUED partition cannot be the `Named` witness because its concrete part is nonempty
there, and no environment constraint can be, because `mk w ∅ ∅` and `mk w {u} ∅` have at most
one right-hand variable while the split guard gives at least two.

### R2.1e The theorem the orchestrator asked for, verbatim

```lean
/-- **Refinement, for EVERY dispatch branch.** -/
theorem step_refines_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : LoopRun (sys s) (sys s')

theorem step_sat_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s')

theorem step_flags {s s' : State} (h : step s = .continue s') : s'.flags = s.flags

def RunSupOk : Nat → State → Prop
  | 0, _ => True
  | n + 1, s => SupOk s.su ∧ SupFresh s.su (sys s) ∧ ∀ s', step s = .continue s' → RunSupOk n s'

theorem run_sat_all : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → SSat (sys s')

theorem run_refutes_all : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' → ¬ SSat (sys s') → ¬ SSat (sys s)
```

The three flag hypotheses are the SHIPPED settings, and `step_flags` shows they survive a step,
so they are stated once at the start of a run rather than at every state.

**What is still a hypothesis rather than an invariant, and why.** `SupOk`/`SupFresh` are
carried along a run by `RunSupOk`, a per-state hypothesis, not proved preserved. Preservation
is available and is bookkeeping, not mathematics: it needs the vocabulary clause
`allVars H ⊆ allVars G` threaded through the `*_run` lemmas of the four NON-minting branches
too (`replace_run`, `instantiate_run`, `makeEmpty_run`, `subPartitions_run`,
`destructiveSub_run`, `makeConcrete_run`, `insertP_run`, `concatP_run`), the way Round 2 added
it to `eraseAll_run` and `subst_one_run`. It was not written for time.

---

## R2.2 — every `LoopRel` constructor is LIVE (review F1, sharpened)

Counted mechanically over `Refine.lean`, `RefineConcrete.lean`, `RefineLearn.lean` and
`Order.lean` (`grep -o "LoopRel\.<ctor>"`; the Round-2 draft's `split` = 3 counted
`LoopRel.splitFree` twice — the re-review's R.4 caught it, and the corrected figure is 2):

| constructor | Round 1 | Round 2 | where it is used now |
|---|---|---|---|
| `nongen` | 9 | **16** | every non-generative rule, all five branches |
| `weaken` | 6 | **6** | the deletions and drops (catalogued in R2.5) |
| `dedup` | 2 | **2** | `replace`'s two-element queue; `RHS.merge`'s `es` |
| `renameLhs` | 1 | **1** | `replace`'s `f p.lhs` |
| `linkSymm` | 1 | **1** | the `unify` branch's swapped arguments |
| `emptyProp` | 1 | **1** | `makeEmpty`'s `aux` |
| `split` (`K2SplitStep`) | **0** | **2** | `splitConcrete`'s `splitKey` and `splitRow` reuse |
| `res` (`Cut.ResStep`) | **0** | **1** | `resolution`'s MINT |
| `kres` (`K2ResStep`) | **0** | **2** | `resolution`'s `resGuard` and `resRow` reuse |
| `splitFree` (`Cut.SplitStep`) | — | **1** | `splitConcrete`'s MINT (new constructor) |
| `emptyE` (`makeEmptyE`) | **0** | **removed** | see below |

**`emptyE` was REMOVED rather than made live**, and the reason is a fact about the loop worth
recording: a single `makeEmptyE` step cannot be the `empty` branch. `makeEmptyE v G` is
`insert (mk v ∅ ∅) (keepPart ∪ erasePart ∪ propPart)`, but the loop re-enqueues the erased
partitions through `++!`, which can turn one of them into a `CommonPartition` REDIRECT
`w <- (a)` — a constraint in none of those three parts. So `sys s' ⊆ makeEmptyE v (sys s)` is
false in general, and the branch has to be assembled from finer steps: `SubstStep` per erased
constraint (at `d = mk v ∅ ∅`, which is exactly `erasePart`'s rewriting), `emptyProp` per
propagated one (`propPart`, one conclusion at a time), `weaken` for the deletions, and the
RETAINED `v <- ()`, which `sys` keeps because `Env.sys` models the substitution environment.
The content of `makeEmptyE` is therefore present; the whole-system constructor is not.

---

## R2.3 — the three over-claims, corrected (review F2)

All three corrections are in the Round-1 text above, marked "corrected in Round 2":

* **(a)** §2f's table now says explicitly that the four "refutation? YES" entries are
  SYSTEM-level lemmas, and that the loop-level extraction exists for message 4 only — now via
  `step_died_empty`, which is about a `step` death rather than about `makeEmpty`;
* **(b)** the word "composed" is gone. In its place is the composition the review said was
  short, and it is now in Lean:

  ```lean
  theorem step_died_empty {s s' : State} {m : String} {r : LPart} {rest : PQueue}
      (hdq : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
      (h2 : r.rhs.isEmpty = true) (h : step s = .died m s') :
      ¬ SSat (sys s') ∨
        m = "Cannot unify skolem variable with empty relation " ++ varStr s.names r.lhs ∨
        m = "panic: reinstantiated type " ++ varStr s.names r.lhs ++ " to ConcreteRho(-,Set())" ++
            " but it was already bound"
  ```

  — stated about `sys s'`, the DYING state, so that it is exactly the hypothesis
  `run_refutes_all` takes;
* **(c)** the report now says plainly that `run_sat` / `run_refutes` and the `nonlearn`
  variants hold only for runs that never take the `learn` branch, and that Round 2's
  `run_sat_all` / `run_refutes_all` remove that restriction. The README says the same.

---

## R2.4 — escape 1 (review F3/F4): half proved, and the remainder stated exactly

**Proved.** The invariant the review's F4 called "worth having on its own":

```lean
def NoSelfUnif (s : State) : Prop := ∀ p ∈ s.parts, p.isSelfUnification = false

theorem step_NoSelfUnif {s s' : State} (h0 : NoSelfUnif s) (h : step s = .continue s') :
    NoSelfUnif s'

theorem proc_no_self_unification {s : State} (h : NoSelfUnif s) :
    ∀ p ∈ s.proc.elems, p.isSelfUnification = false

theorem noSelfUnif_initial {q : PQueue} {ps : List LPart} (hq : q = PQueue.ofList ps) … :
    NoSelfUnif { incm := q, proc := PQueue.empty, … }
```

with the closure lemmas `QNoSelf.insertNP/.insertP/.concatNP/.concatP/.filter/.partition_snd/
.dequeue/.foldl` and the per-operation lemmas `instantiate_noSelf`, `makeEmpty_noSelf`,
`destructiveSub_noSelf`, `makeConcrete_noSelf`. The mechanism is the one the review identified:
`Q.insert` drops `a <- (a)` at every insertion, and every other writer of either queue is a
filter of an existing one.

**Also proved, after the re-review's R-B: the SECOND invariant.** Round 2's first draft said
this one "needs the order argument"; the re-review showed that is wrong, and its four-writer
argument goes through as written:

```lean
/-- The shape `selfSubstitution` dies on. -/
def PInfRow (p : LPart) : Prop :=
  p.rhs.abstr.contains p.lhs = true ∧ p.rhs.conc.isEmpty = false

def NoInfRow (s : State) : Prop := ∀ p ∈ s.proc.elems, ¬ PInfRow p

/-- `learnPartitions` RETURNING already excludes the infinite-row shape. -/
theorem learnPartitions_notInfRow {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ¬ (rhs1.abstr.contains v = true ∧ rhs1.conc.isEmpty = false)

theorem step_NoInfRow {s s' : State} (h0 : NoInfRow s) (h : step s = .continue s') : NoInfRow s'

theorem noInfRow_initial {q : PQueue} … : NoInfRow { incm := q, proc := PQueue.empty, … }
```

The proof is the `NoSelfUnif` induction again plus `learnPartitions_notInfRow`, which is four
lines: `learnPartitions` opens with `if rhs1.abstr.contains v then selfSubstitution … >>= …`
and `selfSubstitution` returns `.error` exactly when the concrete part is nonempty, so `.ok`
already gives the invariant's clause for the partition `proc + r` is about to receive. The
other three writers of `proc` are filters of `proc` (`instantiate`'s `nproc`, `makeEmpty`'s
`procd`, `destructiveSub`'s `nproc0`), the re-added `pps.filter(defs)` draws from `proc`
itself, and `makeConcrete`'s `v <- ((|C|))` has an empty variable part — no rewritten partition
ever enters `proc`, they all go to `incm`. **No order argument is involved, and the Round-2
draft's claim that one was needed is withdrawn.** `noInfRow_initial` depends on no axioms at
all.

**STILL not proved: `learn_no_self_rederive` itself**, i.e.
`… → ∀ p ∈ learned.elems, p.eqv r = false`. Both premises it needs now exist
(`proc_no_self_unification` and `NoInfRow`), so what remains is the seven-way case analysis
over the rules — for a `learn` step at `r = v <- (S, K)` with `v ∉ S`:

* `cancellation`: its conclusions have `lhs ∈ (S₁ \ S₂) ∪ (S₂ \ S₁)`; equality with `r` forces
  the other premise to be `v <- (v)`, which `proc_no_self_unification` excludes;
* `substitution`: equality forces the other premise to be `u <- (u)` — excluded by
  `proc_no_self_unification` — or `u <- (u, C)` with `C ≠ ∅`, which is exactly `PInfRow` and is
  now excluded by `NoInfRow`;
* `commonSubexpression`: equality forces `|int| ≤ 1`, contradicting its own `2 ≤ |int|`;
* `splitConcrete`'s reuse branches contradict their own guards (`|S| ≥ 2` against a
  single-variable result, `K ≠ ∅` against an abstract-only one);
* every MINTING branch of `splitConcrete`, `resolution`, `commonSubexpression` and
  `disjunction` puts a freshly drawn variable in the emitted right-hand side, which `SupFresh`
  excludes from `r`'s;
* the `DeDuplication` and `SelfSubstitution` facts have an empty right-hand side, and
  `r.rhs.isEmpty` is false in the `learn` branch.

That is a bounded piece of work with no missing ingredient; it was not written because Round 2
was told to stop after the closing items. When it is, escape 1 disappears, `common_self_drops`
stops being load-bearing, and (iii) reads: **a `resolution` premise pair is examined exactly
once per solve unless an elimination removes one of the premises from `proc`** — one escape,
and that one benign.

**Meanwhile the prose is softened, as the review recommended.** `common_self_drops` assumes
the lookup returns the SAME left-hand side:

```lean
theorem common_self_drops {s : State} {rest : PQueue} {x : LPart}
    (hdq : s.incm.dequeue = some (x, rest)) (hlhs : s.proc.findRHS x.rhs = some x.lhs) :
    ∃ s' : State, step s = .continue s' ∧ s'.incm = rest ∧ s'.proc = s.proc ∧ s'.env = s.env
```

and `proc` CAN hold two partitions with equal right-hand sides, because `makeConcrete`'s
`nproc + Partition(v, RHSConcr(fs))` and `destructiveSub`'s `nproc0 ++ pps.filter(defs)` use
the NON-processing insert. When the lookup returns a different `u`, the step is a real
`unify` — still not a `resolution` re-examination, so (iii)'s ANSWER is unaffected, but the
step is not the identity. §3 above and the README now say only what is proved.

---

## R2.5 — (ii): every `weaken`, catalogued; and the residual specification

`LoopRel.weaken : G' ⊆ G → LoopRel G G'` is the arbitrary deletion the review's F8 names as
the structural reason no measure is monotone along `LoopRun`. Round 2 removed one use (a
genuine no-op) and catalogued the rest. **Six remain** (rows 2-7 below; the Round-2 draft tabulated only five and the re-review's R-A
caught the omission — the `unify` branch, row 5, was missing), and for each the question is
whether the loop's deletion IS one of the library's deleting steps (`makeEmptyE`,
`concretizeSrs`, a unify/rename step).

| # | site | what is deleted or dropped | is it a library deletion? |
|---|---|---|---|
| 1 | ~~`Refine.makeEmpty_run`, `v ∉ vset x`~~ | nothing — the erase was the identity | **REMOVED in Round 2**: the branch now takes no step at all |
| 2 | `Refine.step_refines`, `common` at `r.lhs = u` | the DEQUEUED partition leaves `incm` and is returned nowhere (`unify` at equal variables is the identity) | **no** — a dequeue-drop; the library has no such step |
| 3 | `Refine.step_refines`, `common` at `r.lhs ≠ u` | `instantiate`'s removal of every partition mentioning `v` from BOTH queues, plus `++!`'s drops | **no** — the nearest library step is `NameLoss.concretizeKeep`, which deletes definitions of a variable and rewrites mentions of it; `instantiate` deletes mentions outright and re-adds them REWRITTEN through `replace`, and `++!` may replace one with a redirect |
| 4 | `Refine.step_refines`, `empty` | `makeEmpty`'s `procd` / `incmg` | **almost `makeEmptyE`** — `keepPart`, `erasePart` and `propPart` match the branch exactly, and `sys` already retains `v <- ()`; what breaks the inclusion is `++!`'s `CommonPartition` redirect, which is in none of the three parts (R2.2) |
| 5 | `Refine.step_refines`, `unify` (the lone-variable branch, `Refine.lean:1256`) | the same `instantiate` removal as row 3, at SWAPPED arguments: `Constraints.scala:1130`'s `case RHSAbstr(Single(u)) => unify(u, v, …)` kills `u`, not `v`, so the partitions removed from both queues are the ones mentioning the RIGHT-hand variable | **no** — same category as row 3, and the swap is why `LoopRel.linkSymm` exists at all |
| 6 | `RefineConcrete.step_refines_nonlearn`, `concrete` | `destructiveSub`'s `filter pred` | **almost `concretizeSrs`** — `concretizeKeep ∪ srsOf` matches the deletion and the `srs` re-expression, but the loop additionally KEEPS `pps.filter (abs.size ≥ 2)` (the 2026-09-02 `keepDefs` repair) and adds `makeConcrete`'s `can` cancellation facts and `v <- ((|C|))`, none of which is in `concretizeSrs`'s image |
| 7 | `RefineLearn.step_refines_learn`, `learn` | nothing is deleted; `trim` and `++!` DROP derived partitions that `proc`/`incm` already hold, that are self-unifications, or that are replaced by a redirect | **no** — every library step is `insert`-shaped (`G ⊆ G'`); "the relation derives it, the loop declines to enqueue it" has no counterpart |

**The residual, i.e. the specification of the tighter relation the review's §6d says (ii)
needs.** `LoopStrict` would replace `weaken` by exactly these five operations:

1. **dequeue-drop** — remove one partition of `incm` (rows 2 and 7);
2. **queue drops** — `trim`'s `Partition.equals` filter, `++!`'s already-present test,
   `Q.insert`'s self-unification test, and `Q.+!`'s redirect REPLACING an insertion (rows 3–7);
3. **`instantiate`'s removal** — delete every constraint mentioning the bound variable, having
   added its image under the substitution; needed at BOTH argument orders, `unify(v, u)` from
   the `common` branch and `unify(u, v)` from the lone-variable branch (rows 3 and 5);
4. **`makeEmptyD`'s erasure** — `keepPart ∪ erasePart ∪ propPart`, available verbatim from
   `KeyedEmpty`, needing only the redirect handled separately (row 4);
5. **`concretizeSrs` plus `keepDefs`** — `concretizeKeep ∪ srsOf` widened by the kept
   two-abstract definitions and the `can` cancellation facts (row 6).

Only (4) and (5) exist in the library today, and neither matches the loop exactly; (1), (2) and
(3) have no counterpart at all. That is the honest measure of what stands between the
refinement proved here and transporting `KeyedRow.mintsBoundedOnSatKeyed2Star` — and it is
consistent with the review's judgement that (ii) is not one round's work.

---

## R2.6 — what Round 2 does NOT do

| asked / hoped for | delivered | why not more |
|---|---|---|
| (i) `learn` | **PROVED**, `step_refines_all` covers all five branches at the shipped flags under `SupOk`/`SupFresh` | — |
| every constructor live | **yes**, ten constructors, all used; `emptyE` removed with a proof-level reason | — |
| F2's three over-claims | **corrected**, and (b) is now a theorem (`step_died_empty`) | — |
| F3/F4 escape 1 unreachable | `NoSelfUnif` and (after the re-review's R-B) `NoInfRow` both **PROVED** and preserved by `step`; `learn_no_self_rederive` NOT proved | both premises now exist; what is left is the seven-way rule case analysis, listed in R2.4, with no missing ingredient |
| `SupOk`/`SupFresh` as an INVARIANT | carried as a per-state hypothesis (`RunSupOk`) | needs the vocabulary clause on eight more `*_run` lemmas; bookkeeping, not mathematics |
| loop-level extraction for deaths 1, 2, 7 | only 4 (`step_died_empty`) | 7 is now bookkeeping (the `concrete` branch is refined); 1 and 2 need the `learnPartitions` / `ensureSuperset` fold analyses |
| (ii) the mint bound | not attempted this round, as instructed; the residual specification is R2.5 | — |
