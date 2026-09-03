# Stage 3 — does the KEYED split guard survive the loop layer's deletions?

Date 2026-09-03, branch `scala3-migration`, tree at `d736bf9`.
Stage 1 (the additive theorem) is `tracker/satterm/KEYED-SPLIT.md` /
`tracker/lean/Rowpartition/KeyedSplit.lean`; Stage 2 (the flag, adopted as the default the
same day) is `tracker/satterm/KEYED-SPLIT-STAGE2.md`.  This file is Stage 3.

Toolchain for every command below:

```
export PATH=$HOME/.elan/bin:$PATH                                        # Lean 4.33.1, Mathlib v4.33.1
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
cd /home/dmitry/research/ermine/ermine-scala
```

`sbt` was NOT run: the class files under `target/` are the ones commit `d736bf9` built, and
every compiler measurement below is `bin/ermine` or a `dotc`-compiled replay against them.
Raw outputs (not tracked): `/home/dmitry/.claude/jobs/880c725d/tmp/`.

---

## 0. What was asked

`ermine.splitKey` (DEFAULT ON since commit `1e6f52b`) keys `splitConcrete`'s mint guard on
`(lhs, concrete part)`: mint iff `¬ Resolved G c.lhs c.conc`, i.e. unless some
`c.lhs <- (z, c.conc)` with ONE abstract variable is in the system.  `KeyedSplit.lean`
proves the ADDITIVE calculus `KDefaultStep` terminates on every satisfiable input in every
run order (`terminatesOnSatKeyed`, bound `KRun.length_le`).

The real loop is not additive.  `makeConcrete` / `destructiveSub` (Lean:
`NameLoss.concretizeKeep u C G`) DELETES every definition of `u` with fewer than two
abstract parts, REWRITES every mention of `u` by `absorbC`, and keeps `u <- ((|C|))` plus
the definitions of `u` with `2 ≤ |vset|` (`keepDefs`).  Stage 3 asks whether the keyed
guard survives that, and wants one of (T1) a termination theorem, (T2) bounded re-mints, or
(W) a divergence witness.

## 1. The answer: **(W)**, and the brief's mechanism sketch is WRONG in one step

**The keyed guard does not survive the loop layer.**  `Rowpartition/KeyedLoop.lean` adds the
concretisation to `KDefaultStep` and refutes the same termination statement on a
three-constraint satisfiable system, with unbounded MINTING, not merely unbounded run
length:

```
theorem not_TerminatesOnSatKeyedLoop : ¬ TerminatesOnSatKeyedLoop
theorem keyed_additive_vs_loop : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSatKeyedLoop
theorem W3_mints_unbounded (n : ℕ) :
    ∃ G, KLoopRun (3 * n + 1) W3 G ∧ n + 3 ≤ (allVars G).card
```

The Stage 3 brief's sketch said: the re-mint yields `w <- (x, y)` and `u <- (w, K)`;
cancellation makes `w` concrete; `w`'s only kept definition is BARE and therefore inert;
"and `u <- (w, K)` closes the key `(u, K)` again".  **That last step is false.**  `w` occurs
on the RIGHT of `u <- (w, K)`, so concretising `w` does not leave that constraint alone: it
is a MENTION, `absorbC` rewrites it to `u <- ((|K ∪ (C \ K)|))` = `u <- ((|C|))`, which is
already present, and `concretize` keeps only the image.  The key witness the mint had just
installed is destroyed by the very concretisation the sketch invokes, the key is open again,
and the engine runs for ever.

There are exactly two ways a concretisation of `u` can kill a key witness, and the module
proves both unconditionally — one per clause of `concretizeKeep`:

```
theorem notMem_lone_lhs (u z : Var) (C K : Row) (G : System) :
    mk u {z} K ∉ concretizeKeep u C G                       -- DELETION  (keepDefs: |vset| = 1 < 2)
theorem notMem_lone_mention {u v : Var} {C K : Row} {G : System} (hne : v ≠ u) :
    mk v {u} K ∉ concretizeKeep u C G                       -- destructive REWRITE (absorbC)
theorem resolved_of_concretizeKeep {u v z : Var} {C K : Row} {G : System}
    (hw : mk v {z} K ∈ G) (hv : v ≠ u) (hz : z ≠ u) :
    Resolved (concretizeKeep u C G) v K                     -- ... and nothing else is lost
```

The brief names the first.  The second is the one the divergence runs on, and it is invisible
to `KeepInert.lean`, which studies only the kept definitions.  Both are realised in the
witness (`W3_key_deleted`, `key_absorbed`).

**Measured (Part B): the mechanism is real in the compiler, and the loop kills it after one
round, by a defence not on the list of three.**  On the same three constraints replayed
through `Subst.solve` at 100 id bases, `makeConcrete u` runs before the kept split premise is
dequeued at **55 of 100** bases; at all 55 `splitConcrete` MINTS (the re-mint), at all 55 the
cancellation `w <- ((|c|))` predicted by the Lean round fires — and at all 55 the loop then
takes its `common` branch and UNIFIES the fresh name with `z`, the variable of the deleted
witness, because the two now have the same right-hand side.  Round 2 never starts.  The four
loop defences are therefore *name travel*, *eager `unify` of singleton links*, *eager
`makeEmpty`* and — new here — ***`common`: dedup-unification of a re-minted name with the one
the deletion removed***.

## 2. The Lean module `Rowpartition/KeyedLoop.lean`

780 lines, 52 `theorem`s, imported from the root `Rowpartition.lean`.
`lake build Rowpartition` → **Build completed successfully (816 jobs)** (815 before).
`lake env lean Audit.lean` → **Rowpartition theorems audited: 2086; declarations using a
non-standard axiom: 0** (2020 before).  Every headline below was additionally checked one at
a time with `#print axioms` in the scratch file
`/home/dmitry/.claude/jobs/880c725d/tmp/PrintAxiomsStage3.lean` (never inside the module):
all `[propext, Classical.choice, Quot.sound]`.

### 2.1 The relation (§2 of the module)

```
inductive KLoopStep : System → System → Prop
  | additive {G G' : System} : KDefaultStep G G' → KLoopStep G G'
  | concrete {G : System} {u : Var} {C : Row} :
      mk u ∅ C ∈ G → concretizeKeep u C G ≠ G → KLoopStep G (concretizeKeep u C G)

inductive KLoopRun : ℕ → System → System → Prop
  | refl (G : System) : KLoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      KLoopRun n G₀ G → KLoopStep G G' → G ≠ G' → KLoopRun (n + 1) G₀ G'

def TerminatesOnSatKeyedLoop : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KLoopRun n G₀ G → n ≤ N
```

**Productivity — which option was taken and why.**  One uniform side condition, `G ≠ G'`, on
the run's `tail`.  On an additive step it is exactly `KRun`'s and `DefaultRun`'s `G ⊂ G'`,
because `KDefaultStep` is monotone (`KLoopRun.ssubset_of_additive`); on a concretise step it
is the `concretizeKeep u C G ≠ G` the constructor already carries.  Counting additive steps
only was the alternative; it was not needed, because the headline is not the run length but
the vocabulary: `KLoopStep.allVars_cases` says a loop step either shrinks the vocabulary
(the concretisation) or adds exactly one fresh variable (a mint), so `W3_mints_unbounded`'s
`n + 3 ≤ (allVars G).card` counts `n` MINTS and is immune to the objection that `G ≠ G'`
would also count an oscillation between two systems.

`SatStep.concrete` of `Saturate.lean` was NOT used as the substrate: it absorbs one
constraint and retains the premise, so it cannot express `notMem_lone_mention`, which is the
whole engine — the DELETION is the point of Stage 3.

**Soundness** (all one-directional where the deletion makes the converse false):

```
theorem KLoopStep.concrete_models {G : System} {u : Var} {C : Row} {rho : Assign}
    (hmem : mk u ∅ C ∈ G) (hm : SModels rho G) : SModels rho (concretizeKeep u C G)
theorem KLoopStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : KLoopStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v
theorem KLoopStep.sat_mono {G G' : System} (h : KLoopStep G G') :
    (∃ rho, SModels rho G) → ∃ rho, SModels rho G'
theorem KLoopRun.sat_mono {n : ℕ} {G₀ G : System} (h : KLoopRun n G₀ G) :
    (∃ rho, SModels rho G₀) → ∃ rho, SModels rho G
theorem KLoopRun.of_kRun {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) : KLoopRun n G₀ G
```

`concrete_models` is `NameLoss.concretizeKeep_sound`; the converse of `sat_mono` is false in
general, because a concretise step deletes and a model of the successor need not model the
predecessor.  `of_kRun` is the embedding that says `KeyedSplit.KRun.length_le` still bounds
every deletion-free run: all the unboundedness comes from the concretise steps.

### 2.2 The three "worth stating if cheap" lemmas (brief A.3) — all three, proved

```
theorem concretizeKeep_idem (u : Var) (C : Row) (G : System) :
    concretizeKeep u C (concretizeKeep u C G) = concretizeKeep u C G
theorem conc_unique_of_model {u : Var} {C C' : Row} {G : System} {rho : Assign}
    (hm : SModels rho G) (h : mk u ∅ C ∈ G) (h' : mk u ∅ C' ∈ G) : C = C'
theorem resolved_of_concretizeKeep {u v z : Var} {C K : Row} {G : System}
    (hw : mk v {z} K ∈ G) (hv : v ≠ u) (hz : z ≠ u) : Resolved (concretizeKeep u C G) v K
```

Idempotence is what stops "concretise the same variable twice" from being a productive step:
a repeat is a no-op and the run's side condition rejects it.  `conc_unique_of_model` is the
"one concretisation per variable under a model" lemma: the value is read off the model
(`rho u`), so along a run from a satisfiable input a variable has one concrete value.
Together they say the divergence cannot come from re-concretising: it comes from
concretising a fresh variable each round, and fresh variables come from mints.
Supporting: `mem_concretizeKeep` (the membership characterisation, the workhorse),
`absorbC_of_notMem`, `absorbC_lhs`, `vset_absorbC_subset`, `notMem_vset_absorbC`,
`allVars_concretizeKeep_subset` (the concretisation adds no variable),
`subset_concretizeKeep_of_fresh`.

### 2.3 The witness (§3 of the module)

Four variables (`u = 0`, `z = 1`, `x = 2`, `y = 3`), two labels (`fk = 7`, `fc = 8`),
`K = {fk}`, `C = {fk, fc}`, `D = C \ K = {fc}`:

```
def W3conc : Constraint := mk u ∅ C          --  u <- ((|k, c|))     the concrete value
def W3key  : Constraint := mk u {z} K        --  u <- (z, (|k|))     the KEY WITNESS
def W3def  : Constraint := mk u {x, y} K     --  u <- (x, y, (|k|))  the kept split premise
def W3 : System := {W3conc, W3key, W3def}
def W3sat : System := {W3conc, W3def}        --  what makeConcrete u reaches
def rho3 : Assign := fun v => if v = u then C else if v = z then D else if v = x then D else ∅

theorem W3_models : SModels rho3 W3                 -- rho u = {k,c}, z = x = {c}, y = ∅
theorem W3_resolved : Resolved W3 u K               -- the keyed guard is CLOSED at the input
theorem W3_concretize_eq : concretizeKeep u C W3 = W3sat
theorem W3_concrete_step : KLoopStep W3 W3sat
theorem W3sat_inv : W3Inv W3sat
```

The invariant and the round:

```
structure W3Inv (G : System) : Prop where
  intro ::
  conc  : mk u ∅ C ∈ G
  kept  : mk u {x, y} K ∈ G
  unres : ¬ Resolved G u K

theorem W3Inv.round {G : System} (h : W3Inv G) :
    ∃ G', KLoopRun 3 G G' ∧ W3Inv G' ∧ (allVars G).card < (allVars G').card
theorem W3Inv.run {G : System} (h : W3Inv G) (n : ℕ) :
    ∃ G', KLoopRun (3 * n) G G' ∧ W3Inv G' ∧ (allVars G).card + n ≤ (allVars G').card
theorem W3_diverges (n : ℕ) : ∃ G, KLoopRun n W3 G
```

The round is three productive steps, from any system satisfying the invariant, with `w` any
variable outside its vocabulary:

1. **keyed MINT** on `u <- (x, y, (|k|))` — the key `(u, K)` is open, so `KSplitApp` holds;
   emits `w <- (x, y)` and `u <- (w, (|k|))`.  `R1 G w`.
2. **CANCELLATION** of `u <- (w, (|k|))` against `u <- ((|k, c|))` — `K ⊆ C` and the leftover
   is the single variable `w` — emits `w <- ((|c|))`.  `R2 G w`.
3. **`makeConcrete w`** — `concretizeKeep w D (R2 G w)`.  It keeps `w <- (x, y)` (two
   abstract parts) and rewrites the mention `u <- (w, (|k|))` to `u <- ((|k, c|))`, which is
   already there.  The key witness is gone (`key_absorbed`), the invariant holds again
   (`hres3` in the proof: no `mk u {s} K` survives, for ANY `s`), and `w` is in the
   vocabulary for good.

Sharpness, one theorem per failure mode:

```
theorem W3_key_deleted : W3key ∈ W3 ∧ W3key ∉ concretizeKeep u C W3
theorem key_absorbed {G : System} {w : Var} (hwu : u ≠ w) :
    mk u {w} K ∈ R2 G w ∧ mk u {w} K ∉ concretizeKeep w D (R2 G w)
```

### 2.4 What the shipped rule would do — the one faithfulness gap, machine-checked

`KSplitApp` carries ONLY the keyed premise.  The shipped `splitConcrete` asks the SYNTACTIC
lookup `rhss(RHSAbstr(abstr))` first and reaches the keyed lookup only on a miss
(`Constraints.scala`, `def splitConcrete`).  So `KDefaultStep` — the relation
`terminatesOnSatKeyed` bounds — is MORE permissive than the compiler's rule, and this module
refutes the same statement for the same relation.  Four theorems pin exactly where the two
agree on this witness:

```
theorem W3_not_named : ¬ Named W3 {x, y}
theorem W3sat_not_named : ¬ Named W3sat {x, y}
theorem W3sat_remint_enabled :
    SplitApp W3sat (mk u {x, y} K) 9 ∧ KSplitApp W3sat (mk u {x, y} K) 9
theorem named_after_round (G : System) (w : Var) : Named (concretizeKeep w D (R2 G w)) {x, y}
```

* At the INPUT the group is unnamed, so the SYNTACTIC guard would mint; what refuses the mint
  at `W3` is the KEYED guard alone (`W3_resolved`).  `W3` is a system on which Stage 1's
  change is the whole difference.
* After `makeConcrete u`, BOTH lookups miss: `W3sat_remint_enabled` gives `Cut.SplitApp` as
  well as `KSplitApp`.  **The first re-mint is a mint the shipped rule really takes** — and
  Part B finds exactly it, in the real loop, at 55 of 100 id bases.  This is
  `NameLoss.orderB_remint_enabled` for the keyed guard.
* From the SECOND round on the engine is no longer faithful: the round's own mint leaves the
  bare `w <- (x, y)` behind, the round's own concretisation KEEPS it (two abstract parts), so
  the group IS named (`named_after_round`) and the shipped rule would take its syntactic
  reuse branch instead of minting.  **Whether the SHIPPED rule — both lookups, plus
  deletion — terminates on satisfiable input is therefore still open.**  §4 states it.

---

## 3. Measurement (`bin/ermine` and `dotc`-compiled replays only; `sbt` NOT run)

### 3.1 The instance, replayed through the real loop at 100 id bases

The smallest instance of the mechanism (key CLOSED at input, `u` concretised, kept definition
dequeued afterwards) is `W3` itself; `W3M` adds a mention `v4 <- (v0, v5)` so that
`destructiveSub` has a mention to rewrite as well as a definition to delete.  Both are run
through the shipped `Subst.solve` by `tracker/repro/satterm/`, which takes any seed in
`rowclosure.py`'s JSON format (`json:<path>`), so no new harness code was needed.  The two
seeds (scratch, reproduced here in full):

```json
W3.json   {"rho": {"0": [1,2], "1": [2], "2": [2], "3": []},
           "cons": [[0, [], [1,2]], [0, [1], [1]], [0, [2,3], [1]]]}
W3M.json  {"rho": {"0": [1,2], "1": [2], "2": [2], "3": [], "4": [1,2], "5": []},
           "cons": [[0, [], [1,2]], [0, [1], [1]], [0, [2,3], [1]], [4, [0,5], []]]}
```

i.e. `v0 <- ((|l1,l2|))`, `v0 <- (v1, (|l1|))`, `v0 <- (v2, v3, (|l1|))` (+ `v4 <- (v0, v5)`),
with `v0 = u`, `v1 = z`, `v2 = x`, `v3 = y`, `l1 = k`, `l2 = c` — the Lean `W3` exactly.

```
export SATTERM_OUT=<scratch>/satterm-classes
tracker/repro/satterm/sweep.sh json:<scratch>/seeds/W3.json 0 99 10 6                          # default: splitKey ON
ERMINE_JAVA_OPTS=-Dermine.splitKey=false tracker/repro/satterm/sweep.sh json:<scratch>/seeds/W3.json 0 99 10 6
```

| seed / guard | verdicts, bases 0..99 | `drawn` histogram | mints per base (fresh ids in a step/learn record) |
|---|---|---|---|
| `W3`, keyed (default) | **SOLVED 100/100** | 0:x45 1:x55 | **0 at 45 bases, 1 at 55** |
| `W3`, `splitKey=false` | **SOLVED 100/100** | 1:x94 2:x6 | 1 at 100 bases |
| `W3M`, keyed (default) | **SOLVED 100/100** | 2:x45 3:x55 | 1 at 45 bases, 2 at 55 |
| `W3M`, `splitKey=false` | **SOLVED 100/100** | 3:x94 4:x6 | 2 at 100 bases |

(`W3M`'s extra mint is on the rewritten mention `v4 <- (v5, v2, v3, (|l1|))`, whose own key
`(v4, (|l1|))` was never closed; it is not a re-mint.)

Nothing hangs, nothing is rejected.  Then, per base, the kept-definition instrument
(`tracker/tools/keptdef-mints.py` on each base's `-Dermine.rowTrace`):

| seed / guard | bases where a kept definition is dequeued AFTER the concretisation | of those, `splitConcrete` MINTED | the fresh name then cancelled to `((|c|))` | the loop then `common`-unified it with `z` |
|---|---|---|---|---|
| `W3`, keyed | **55 / 100** | **55 / 55** | **55 / 55** | **55 / 55** |
| `W3`, `splitKey=false` | 57 / 100 | 57 / 57 | 55 / 57 | 55 / 57 |
| `W3M`, keyed | **55 / 100** | **55 / 55** | **55 / 55** | **55 / 55** |
| `W3M`, `splitKey=false` | 59 / 100 | 59 / 59 | 57 / 59 | 57 / 59 |

So **the Stage 3 mechanism fires in the shipped compiler**: at 55 of 100 id bases the queue
order puts `makeConcrete u` before the dequeue of the kept `u <- (x, y, (|k|))`, the key
witness `u <- (z, (|k|))` is deleted, and the keyed guard — which refuses the mint at the
input — permits it afterwards.  The two regimes partition the bases exactly:

* the 55 bases with a kept-definition dequeue are exactly the 55 with `mints=1` (set
  intersection, `comm -12`: 55);
* at the other 45 the split premise is dequeued FIRST, the key is still closed, and the KEYED
  REUSE branch fires — `SplitKeyed` appears in the trace at **45 of 45** — so nothing is
  minted.

Under `-Dermine.splitKey=false` the split premise mints whichever way the order falls (43
bases at the first dequeue, 57 after the concretisation), which is the 1-at-100/100 row.

**Why the loop stops after one round** (traced, `W3` base 3, default flags; `^free3 = u`,
`^free4 = z`, `^free5 = x`, `^free6 = y`, `^ambiguous(free)7 = w`):

```
step learn     ^free3 <- (^free4,l1)                      the key witness, dequeued, derives nothing
step concrete  ^free3 <- (,l1 l2)                         makeConcrete u  -- DELETES u <- (z,l1), KEEPS u <- (x,y,l1)
step concrete  Cancellation: ^free4 <- (,l2)              makeConcrete z
step learn     ^free3 <- (^free5 ^free6,l1)               the KEPT split premise, dequeued now
  learn new    SplitConcrete: ^ambiguous(free)7 <- (^free5 ^free6,)     <-- THE RE-MINT
  learn new    SplitConcrete: ^free3 <- (^ambiguous(free)7,l1)
step learn     SplitConcrete: ^free3 <- (^ambiguous(free)7,l1)
  learn new    Cancellation: ^ambiguous(free)7 <- (,l2)   <-- step 2 of the Lean round, exactly
step common:4  Cancellation: ^ambiguous(free)7 <- (,l2)   <-- unify(^free4, ^7): the fresh name IS z
```

The Lean round's step 2 (`w <- ((|C \ K|))`) is performed by the real loop at 55 of 55 bases.
Its step 3 is where the two part company: `incorporateAll` notices that `w <- ((|c|))` has the
same right-hand side as the already-processed `z <- ((|c|))` and takes the `common` branch,
which UNIFIES `w := z` — restoring the key witness `u <- (z, (|k|))` instead of losing it.
`KLoopStep` has no rule that identifies two variables, so its `w` stays distinct and the
round repeats.  This is the `W2` precedent (`empty` then `unify`) with a different pair of
steps: here it is **`makeConcrete` then `common`**.

### 3.2 Kept-definition mints over the 110-module example corpus

Kept-definition mints ARE the loop-layer re-mints this stage is about: a kept definition
`u <- (x, y, (|K|))` dequeued after `u` was made concrete is exactly `W3sat`'s split premise,
and a `SplitConcrete` mint on it is exactly `W3sat_remint_enabled`.  The instrument is
`tracker/tools/keptdef-sweep.sh` + `tracker/tools/keptdef-mints.py` (one serialized
`-Dermine.rowTrace` pass per example module, `-Dermine.loadInSeries=true`,
`-Dermine.useInterface=false`).  Both sides were run from the same class set, concurrently,
with `KEPTDEF_TIMEOUT=300`:

```
KEPTDEF_TIMEOUT=300 <sweep> <out-on>                                        # keyed, the default
KEPTDEF_TIMEOUT=300 KEPTDEF_EXTRA=-Dermine.splitKey=false <sweep> <out-off> # the restore side
```

(`<sweep>` is a scratch copy of `tracker/tools/keptdef-sweep.sh` differing only by a
`${KEPTDEF_EXTRA:-}` in its `ERMINE_JAVA_OPTS`; `diff` against the tracked script confirms
that is the only change.  The tracked script itself was not modified.)

**Instrument change (the one the brief allows), `tracker/tools/keptdef-mints.py`:** the branch
classifier knew `SplitConcrete` only, so every KEYED reuse — the branch `-Dermine.splitKey`
opens, and the default since `1e6f52b` — fell into the `no splitConcrete derivation` bucket.
A `SplitKeyed: w <- (abs,)` case was added (documented in the module docstring), so the three
branch counts now add up: `308 = 157 + 147 + 4 + 0` on the keyed side, `284 = 156 + 128 + 0 + 0`
on the restore side.

| over `core/examples`, 110 modules, 55,338 solve segments | keyed (DEFAULT) | `-Dermine.splitKey=false` | 2026-09-02 baseline |
|---|---|---|---|
| module verdicts | 50 LOADED / 60 REJECTED | 50 LOADED / 60 REJECTED, **0 of 110 differ** | — |
| `makeConcrete` steps | 3617 | 3605 | — |
| kept-definition dequeues | **748** (336 strict, 412 derived) | **715** (329 strict, 386 derived) | 715 (329, 386) |
| ... with a nonempty concrete part (a `splitConcrete` premise) | **308** (47 strict) | **284** (42 strict) | 284 (42) |
| ... `splitConcrete` MINTED — **the loop-layer re-mint** | **157** (23 strict) | **156** (24 strict) | 156 (24) |
| ... `splitConcrete` syntactically REUSED | 147 | 128 | 128 |
| ... `splitConcrete` KEYED-reused | **4** | 0 | (not counted then) |
| ... no `splitConcrete` derivation | 0 | 0 | — |
| modules with such a mint | **27** (12 with a strict one) | **27** (14 with a strict one) | 27 (14) |
| modules with a keyed reuse on a kept definition | 3 (`RevenueShare`, `gu05`, `np01`) | 0 | — |

The restore side reproduces the 2026-09-02 baseline **exactly** in every column it shares with
it (715 / 329 / 386 / 284 / 42 / 156 / 24 / 128 / 27), which is the control: `splitKey=false`
is the old behaviour.

**The headline of this table is that the keyed guard removes none of them.**  The guard that
makes the ADDITIVE calculus terminate (Stage 1) leaves the loop-layer re-mint count where it
was: **157 against 156**, in the same 27 of 110 modules.  That is what
`not_TerminatesOnSatKeyedLoop` predicts — the guard's witness is precisely what
`makeConcrete` deletes — and it is the empirical counterpart of the theorem.

Per module, the two guards are incomparable exactly as `split_mint_not_keyed` says (ten
modules differ, net +1):

| module | keyed | syntactic |   | module | keyed | syntactic |
|---|---|---|---|---|---|---|
| `Ai/IncidentSeverity` | 10 | 9 |  | `Ai/TelescopeTime` | 8 | 11 |
| `Ai/FiscalCalendar` | 4 | 3 |  | `Ai/SalesByRegion` | 8 | 10 |
| `incomplete/np01_add_or_recompute` | 33 | 26 |  | `Ai/SupplyChainInventory` | 9 | 10 |
| `incomplete/np05_label_column_no_escape` | 9 | 5 |  | `Ai/HeadcountPlan` | 9 | 10 |
|  |  |  |  | `incomplete/gu05_star_join_4dim…` | 6 | 8 |
|  |  |  |  | `incomplete/np02_which_table…` | 3 | 6 |

`np01` minting MORE is the same module Stage 2 flagged (§3c: 101 -> 108 split mints overall).
19 of 110 modules differ in some kept-definition column; no verdict differs.
The `.ei` files the sweeps would have written were suppressed by `-Dermine.useInterface=false`
and `find core/examples -name '*.ei' -delete` afterwards reports none (checked: 0).

---

## 4. What is still open

1. **The shipped rule with BOTH lookups, plus deletion.**  `KSplitApp` has no `¬ Named`
   premise; `splitConcrete` checks `rhss(RHSAbstr(abstr))` first.  `W3`'s first re-mint is
   faithful (`W3sat_remint_enabled`), the later ones are not (`named_after_round`).  A
   divergence for the two-lookup rule would need a FRESH, UNNAMED group each round; the
   engine here reuses one group and names it at the first mint.  Not proved, not refuted.
2. **`incorporateAll` itself.**  Everything above quantifies over all orders of an additive
   relation extended with a deleting step.  The real loop examines each partition once, at
   its dequeue, and nothing re-enqueues the kept definition a second time; and when it does
   re-mint, `common` unifies the new name away.  Neither property is stated by any relation
   in the development — the same gap `TICKET-sat-termination.md` §4 items 1–3 record.
3. **A `common`/`unify` step in the Lean.**  The measurement says the defence that kills this
   engine is dedup-unification, which no relation here models (`Saturate.SatStep` has
   `rename`, but unordered and without the "same RHS" trigger).  Adding it is the obvious
   next Lean target, and it would be the first of the loop's defences to be stated.
4. **A quantitative T2.**  A bound of the form "re-mints ≤ f(input) + g(number of concretise
   steps)" was not attempted: `gmeas` is not monotone under the deletion, and repairing it
   quantitatively needs a bound on how much `unfired` a single concretisation can re-open.
   Given (W), such a bound cannot yield T1, but it would say how bad the loop can get.

## 5. Files touched

| file | what | size |
|---|---|---|
| `tracker/lean/Rowpartition/KeyedLoop.lean` | NEW. `KLoopStep` / `KLoopRun` / `TerminatesOnSatKeyedLoop`, the concretisation lemmas (`mem_concretizeKeep`, `notMem_lone_lhs`, `notMem_lone_mention`, `resolved_of_concretizeKeep`, `concretizeKeep_idem`, `conc_unique_of_model`, `allVars_concretizeKeep_subset`, `subset_concretizeKeep_of_fresh`), soundness (`KLoopStep.extend/.sat_mono`, `KLoopRun.sat_mono`, `KLoopRun.of_kRun`), the witness (`W3`, `rho3`, `W3Inv`, `W3Inv.round`, `W3Inv.run`, `W3_mints_unbounded`, `W3_diverges`, `not_TerminatesOnSatKeyedLoop`, `keyed_additive_vs_loop`) and the scope theorems (`W3_not_named`, `W3sat_not_named`, `W3sat_remint_enabled`, `named_after_round`, `W3_key_deleted`, `key_absorbed`) | 780 lines, 52 theorems |
| `tracker/satterm/KEYED-LOOP-STAGE3.md` | NEW. This report | 447 lines |
| `tracker/lean/Rowpartition.lean` | the import and its module-map bullet | +10 |
| `tracker/lean/README.md` | headline figures (33 files, 1722 source theorems, audit 2086), build-status row, module-map row, the 2026-09-03 `KeyedLoop` bullet | +51/−11 |
| `tracker/TICKET-sat-termination.md` | new §3e (the theorem, the corrected mechanism, both measurement tables), §1 note, §4 item 0 -> DONE with the outcome and the new ranked-first question, two §5 rows | +124/−6 |
| `tracker/ROW-CONSTRAINT-STATE.md` | one paragraph at the end of the 2026-09-03 top section | +28 |
| `tracker/tools/keptdef-mints.py` | the `SplitKeyed` reuse count (B.1), documented in the docstring | +10/−2 |

Nothing under `core/src` was touched, `sbt` was not run, and nothing was committed.
Scratch (seeds, sweep wrapper, traces, `#print axioms` file):
`/home/dmitry/.claude/jobs/880c725d/tmp/`.
