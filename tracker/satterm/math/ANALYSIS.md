# Does the shipped additive rule set terminate on satisfiable input? -- paper analysis (key: math)

Date 2026-09-02.  Object: `Rowpartition.DefaultStep` (DefaultDiverge.lean:84) =
`NonGenStep` + `SplitStep` (split-concrete MINT) + `GResStep` (guarded resolution), and the
question `TerminatesOnSat` as stated in DefaultTerm.lean:74:

    ∀ G₀ rho, SModels rho G₀ → ∃ N, ∀ n G, DefaultRun n G₀ G → n ≤ N

where `DefaultRun` (DefaultTerm.lean:20) is a chain of `DefaultStep`s each of which strictly
enlarges the system.  No Lean was run; every Lean fact cited below was read in the files
(line numbers given).  The Python under `scratchpad/satterm/math/` (`rules.py`, `witness.py`,
`experiments.py`, `greedy.py`, `probe.py`, `seeds_out.py`) is MINE and UNVERIFIED; it only
checks my own hand constructions against the rule definitions as I transcribed them from
the Lean.  Seeds for the explorer: `W2.json`, `H2.json`, `NE6.json` (rowclosure format).

## 0. Headline

**`TerminatesOnSat` is FALSE.**  The two-constraint SATISFIABLE system

    W2 = { p <- (e1, e2, (|k|)),   p <- (e2, (|k|)) }      model: rho p = {k, m}, rho e2 = {m}, rho e1 = {}

admits productive `DefaultStep` chains of every length (three steps and one split mint per
round, §3).  The orchestrator's structural argument (§1) is right in every step it makes --
an unbounded run must mint unboundedly, mint-parents form a forest of strictly decreasing
rank, resolution children are bounded per parent by the guard -- and the step it flags as
unproved, "split children per parent are bounded", is exactly the step that fails.  It
fails through the EMPTY-ROW loophole and nothing else: `W2` forces `rho e1 = ∅`, and
`{e1, u_n}` is a new unnamed group at `p` for every fresh name `u_n`, because an empty variable
may sit next to a name whose expansion already contains it.  The engine needs no
resolution, no common-subexpression, no name-of-name coarsening: cancellation of two
single-variable definitions of `p` with equal concrete parts yields the alias link
`e2 <- (u_n)`; substitution of that link into `p <- (e1, e2, k)` yields `p <- (e1, u_n, k)`; the
split mint names it.

Two refinements decide what this means in practice.

* **Chains, not saturations.**  Under a SATURATING strategy (every non-generative
  conclusion added before a mint) `W2` reaches a fixpoint after ONE mint: substituting the
  same alias link into the name's own definition `u_1 <- (e1, e2)` produces the bare
  constraint `u_1 <- (e1, u_n)`, which is a `Named` witness for precisely the group the next
  mint needs.  "Names travel with their groups under substitution" is the mechanism that
  saves saturating runs (§3.4); it is not proved, and it is now the real open question
  for the additive calculus (Conjecture S).
* **The loop.**  `incorporateAll` unifies every singleton link `e2 <- (u_n)` (rename) and
  erases every DETECTED empty (`makeEmpty`), so it kills `W2` twice over (§4).  But
  resolution can mint an empty resolvent that no rule exposes as `z <- ()` until further
  derivation (seed `NE6`, §3.5), and the loop's protection is then only the name-travel
  mechanism -- a claim about the order in which the single-pass loop processes
  substitution results, which nothing proves.  The transfer question of §4 inverts: there
  is no proof for `DefaultStep` to transfer; the question is which of the loop's deleting
  and renaming behaviours are load-bearing for its termination on well-typed input.  The
  answer: `unify` of singleton links and `makeEmpty`, plus the name-travel order property
  -- none of which any Lean relation states.

## 1. The mint-parent tree argument, formalised

### 1.1 Definitions

* A **run** is `DefaultRun n G₀ G`.  An **infinite run** is `G₀ ⊂ G₁ ⊂ ...` with
  `DefaultStep Gᵢ Gᵢ₊₁` for all `i`.
* **Vocabulary** `allVars G` (Divergence.lean:198).  Every step either keeps it or is a mint
  inserting exactly one fresh variable (`DefaultStep.allVars_eq_or_mint`, DefaultTerm:713).
* **Labels**: `ConcSub L G` (ResGuardTerm:44); no rule invents a label
  (`DefaultRun.concSub`, DefaultTerm:317).
* **Forced extension.**  From `SModels rho G` and `DefaultStep G G'` there is `rho'` modelling
  `G'` and agreeing with `rho` on `allVars G` (`DefaultStep.extend`, DefaultTerm:627).  It is
  UNIQUE: a split mint inserts `c.lhs <- (u, c.conc)`, which by `sat_lone_iff`
  (ResGuard.lean:157) forces `rho' u = rho c.lhs \ c.conc`; a resolution mint inserts
  `v <- (z, C ∪ D)`, forcing `rho' z = rho v \ (C ∪ D)`.  (Uniqueness is not stated in Lean; it
  is one line from `sat_lone_iff`.)  Along an infinite run there is therefore a unique
  limit model `rho_∞`, and a variable's value never changes after its creation.
* **Rank** `rk v := |rho_∞ v|`.  Every value is a subset of an input row (split child: union
  of part of its parent's row; resolution child: subset of its parent's row), so ranks are
  bounded by the input and the set of VALUES ever occurring is finite (subsets of
  `U := ⋃ rho(allVars G₀)`) although the set of VARIABLES need not be.
* **Parent** `MintParent G G' p c` (DefaultTerm:674): `c` the fresh variable, `p` the premise's
  lhs (split) or the variable both premises partition (resolution); `p` is in the old
  vocabulary (`MintParent.parent_mem`).  Over an infinite run the parent relation is a
  forest whose roots are input variables.
* **Rank decrease** `mintParent_rank_lt` (DefaultTerm:731): `rk c < rk p` for both mints
  (`split_rank_lt` :604, `res_rank_lt` :618 = `ResGuardTerm.mint_rank_lt` :204).

### 1.2 The claim, step by step, with status

**Claim.**  In an infinite productive run some variable has infinitely many SPLIT children.

1. *Infinitely many mints.*  If only finitely many steps mint, the vocabulary is eventually
   a fixed `V`; every later constraint is canonical (`DefaultRun.canonical`, DefaultTerm:471)
   over `V` and `L`, hence in the finite `forms V L` (:335); productive steps add distinct
   constraints; contradiction.  STATUS: proved in finite form
   (`DefaultRun.length_le_forms` :512, `unbounded_vocab_of_unbounded_run` :553); the
   infinite form is immediate.
2. *König.*  The parent forest is infinite with finitely many roots; if every node had
   finitely many children there would be an infinite path, along which `rk` strictly
   decreases in `ℕ` -- impossible.  So some node `p` has infinitely many children.  STATUS:
   unproved in Lean; routine.  It needs an INFINITE run: `TerminatesOnSat` talks about
   runs of every finite length, and passing to an infinite run is König again on the tree
   of runs, finitely branching only MODULO the choice of fresh name (fix
   `fresh := max allVars + 1`; every run is a renaming of a canonical one).  For the negative
   result of §3 none of this is needed.
3. *Resolution children per parent ≤ 2^|L|.*  Distinct resolution children of `v` carry
   distinct keys `K = C ∪ D ⊆ L` (guard `¬ Resolved G v K` before the mint, `Resolved` after,
   monotone by `Resolved.mono` ResGuard:98); the reuse branch mints nothing.  STATUS:
   ingredients proved (`unfired_le_pow`, ResGuardTerm:129); the count itself unstated.
4. *Hence `p` has infinitely many split children*, with pairwise DISTINCT groups
   (`¬ Named G (vset c)` before, `Named` after, `Named.mono` Cut:110), all in constraints
   `p <- (S, K)` with `K ≠ ∅`, `|S| ≥ 2`, `K ⊆ L`; some single `K` occurs with infinitely many
   groups.  STATUS: immediate from 2 and 3.
5. *Are the groups at a fixed `p` finitely many?*  NO -- §3.

### 1.3 Adversarial remarks on the orchestrator's argument

* "(2) every mint's child has a strictly smaller row than the premise's lhs": true, and it
  bounds DEPTH only.  In `W2` every child of `p` has rank 1 while `rk p = 2`; the forest is a
  star of infinite degree.
* The example given for (5), `a <- (x, y, K)` with `x <- (x1, x2)` giving `{x1, x2, y}`, is a
  REFINEMENT and is harmless: refinements and coarsenings of groups of NONEMPTY
  variables are bracketings over finitely many atoms (§2.1).  The harmful step is the
  ALIAS LINK `e2 <- (u_n)` -- an OLD variable defined by a NEW name, obtained by cancellation
  of two single-variable definitions of the parent -- substituted into a group that also
  contains an EMPTY variable.  Without the empty variable the substituted group `{e1, u_n}`
  would violate disjointness (`rho e1 ⊆ rho u_n`), so no satisfiable system derives it.
* "EMPTY-ROW variables may repeat inside groups": exactly the mechanism.  In `W2` the
  expansion `u_{n+1} = (e1, (e1, (e1, ... (e1, e2))))` contains `e1` `n+1` times.
* "(1) between mints the vocabulary is fixed": true; `W2` mints once per three steps, so
  the mint-free stretches are as short as they can be.

## 2. The split-branching question, rule by rule

Fix a parent `p`.  Which steps add a constraint `p <- (S, K)`, `|S| ≥ 2`, `K ≠ ∅`, not present
before, and what must exist first?

| rule | new `p`-constraint | needs first |
|---|---|---|
| `SubstStep` (SplitNecessary:388) | `p <- ((S₀ \ x) ∪ T, K₀ ∪ K_x)` from `p <- (S₀, K₀)` and `x <- (T, K_x)`, `x ∈ S₀` | a `p`-constraint and ANY definition of one of its members.  REFINEMENT if `|T| ≥ 2` or `K_x ≠ ∅`; ALIAS SWAP if `T = {t}`, `K_x = ∅`; from a singleton `p <- (x, K₀)` every group of `x` becomes a group of `p` (upward propagation; `K` grows). |
| `CancelStep` (:287) | `p <- (B \ A, K_d \ K_c)` from `q <- (A ∪ {p}, K_c)`, `q <- (B, K_d)`, `p ∉ B`, `A ⊆ B`, `K_c ⊆ K_d` | `p` on the right of a `q`-constraint and a second decomposition of `q` refining the `p` slot.  The only rule producing a `p`-constraint from constraints with another lhs (TRANSFER). |
| `CutStep.reuse` (Cut:149) | `p <- ((S₀ \ B) ∪ {z}, K₀)`, `B = S₀ ∩ vset c₂`, `|B| ≥ 2`, `Names G z B` | a bare definition `z <- (B)` (from a split mint, the input, cancellation or substitution) and a second constraint with another lhs sharing exactly `B`; new only if `S₀ ⊋ B`.  COARSENING. |
| `CutStep.fold` | same, with `c₂ := z <- (B)` itself | as above without the second constraint. |
| `SplitReuseStep` (:115) | `p <- (u, K)` | never a candidate. |
| `SplitStep` mint (Cut:1009) | `p <- (u, K)`, `u <- (S)` | never a candidate at `p` (`SplitStep.cands_lt` Cut:1063); supplies the NAME `u` and the singleton `p <- (u, K)` -- the raw material for alias links (cancellation) and for upward propagation (substitution). |
| `GResStep` mint / reuse (ResGuard:127) | `v <- (z, C ∪ D)`, `x <- (z, D \ C)`, `y <- (z, C \ D)` | never candidates.  Supplies a fresh ATOM `z` and singleton definitions of the OLD `x`, `y` in terms of it; substitution then replaces `x` by `z` in every group containing `x`, the conc growing by `D \ C`. |
| `CommonPartStep` (:553) | `p <- (q)` | never a candidate; an alias link after which `p` inherits every group of `q`. |
| `SelfSubstStep` (:497) | `v <- ()` | never a candidate; substituting it into `p <- (v, T, K)` gives the ERASURE `p <- (T, K)`. |

New groups at `p` therefore come from (i) refinement by a member's definition,
(ii) coarsening by an existing name, (iii) transfer from a sibling decomposition of an
ancestor `q`, (iv) alias swaps.  The supply question is whether (i)-(iv) produce
infinitely many groups from finitely many input variables.

### 2.1 Atoms, names, bracketings, and the invariant that holds

Call input variables and resolution children ATOMS, split children NAMES.  A name `u` is
born with `u <- (S)`; let `exp(u)` be the multiset union of the expansions of `S` (an atom
expands to itself).  Under the model `rho u = ⋃ rho(exp u)`.  If `x ≠ y` are members of one
group then `rho x ∩ rho y = ∅`, so any atom in `exp x ∩ exp y` has empty row:

> **Invariant (holds).**  Members of any derived group have pairwise disjoint NONEMPTY
> atom supports; the nonempty part of a name's expansion is a bracketed set partition over
> the atoms, and refinements/coarsenings by names are re-bracketings of it.

Over NONEMPTY atoms this bounds the names (finitely many bracketings of a finite set).
It says nothing about EMPTY atoms and cannot: an empty atom may lie in `exp x` and in
`exp y` for group-mates `x`, `y`, hence with any multiplicity inside a nested name, and no
resource is consumed by repeating it.

### 2.2 Decision

**The number of distinct groups per parent is NOT finite given finitely many atoms.**
`W2` (§3) has three input variables, no resolution mint, and infinitely many split
children of `p`, with groups `{e1, e2}, {e1, u_1}, {e1, u_2}, ...`, `u_{n+1}` the name of
`{e1, u_n}`.  The bracketing intuition fails precisely by repetition of the empty atom `e1`.

### 2.3 What survives as a conjecture: empty-free runs

Call a run EMPTY-FREE if `rho_∞ v ≠ ∅` for every variable of the run, input or minted.
This is a property of the model along the run, not of the input: a resolution mint at `v`
with `C ∪ D = rho v` creates an empty child from nonempty premises (seed `NE6`, §3.5, does
so on its first step), and those empties drive the same engine.

> **Conjecture N.**  Every empty-free run from a satisfiable `G₀` has length bounded by a
> function of `(G₀, rho)`.

Sketch and gap.  For a value `r ⊆ U` let `A(r)` be the variables with value `r`.  The
infinitely many split children of `p` (§1.2) have groups whose members carry pairwise
distinct nonempty values partitioning `rho p \ K`; finitely many value-partitions, so some
block value `r` has `A(r)` infinite.  Members of `A(r)` are input variables (finite), split
names of groups with union `r` (distinct names, distinct groups, finitely many
value-partitions of `r` into `≥ 2` nonempty blocks, so some block `r' ⊊ r` has `A(r')` infinite
-- RANK DOWN), or resolution children `z = rho v \ (C ∪ D)` (at most `2^|L|` per parent, so
infinitely many parents in `A(r ∪ C ∪ D)` -- RANK UP).  The explanation graph on the finite
set of values, `r ← r' ⊊ r` (split) and `r ← r ∪ E` (res), can CYCLE (`r ← r ∪ E ← r`), so a
rank induction does not close by itself.  What breaks every cycle I tried is the CONC
CLIMB: a resolution child `z` of `v` (premises `v <- (x, C)`, `v <- (y, D)`) enters groups only
through `x <- (z, D \ C)`, `y <- (z, C \ D)` or `v <- (z, C ∪ D)`, each moving a nonempty label
set into the concrete part of the receiving constraint, and cancellation subtracts a
concrete part only through a decomposition of the same lhs whose concrete part is disjoint
from the parent's row -- never `D \ C ⊆ rho v`.  So at a fixed parent the concrete part of
the constraints an engine cycles through grows strictly, and `L` is finite.  I could not
turn this into one invariant covering the coarsening and transfer sources (ii)-(iii); that
is the open core of Conjecture N.  Evidence (mine, small): 150 random satisfiable seeds
with all-nonempty input rows reached fixpoints under saturation, and the mint-greedy
chains that did run away on that population (`NE6`) all went through an empty resolvent.

## 3. A satisfiable diverger for the shipped additive rules

### 3.1 The invariant (analogue of `ResGuardDiverge.GInv`)

    structure W2Inv (G : System) (p e1 e2 u : Var) (K : Row) : Prop where
      base     : mk p {e1, e2} K ∈ G        -- p <- (e1, e2, K)
      single   : mk p {e2} K ∈ G            -- p <- (e2, K)
      cur      : mk p {u} K ∈ G             -- p <- (u, K)   (u = the latest name)
      K_ne     : K ≠ ∅
      distinct : p, e1, e2, u pairwise distinct
      u_fresh  : ∀ c ∈ G, u ∈ vset c → c = mk p {u} K     -- u on a right-hand side only in cur

`u_fresh` gives `¬ Named G {e1, u}`: a bare `d` with `vset d = {e1, u}` has `u ∈ vset d`, so
`d = mk p {u} K`, whose conc is `K ≠ ∅` and whose vset is `{u} ≠ {e1, u}`.

### 3.2 One round: three productive steps, each checked against the model

Model, for any row `R` disjoint from `K` (e.g. `R = ∅` or `R = {m}`): `rho p = K ∪ R`,
`rho e2 = R`, `rho e1 = ∅`, `rho u = R` for every name `u`.

1. **Cancellation** (`CancelApp G c d z`, SplitNecessary:270): `c := mk p {e2} K` (`single`),
   `d := mk p {u} K` (`cur`), `z := e2`.  `c.lhs = d.lhs`; `c.conc = K ⊆ K = d.conc`;
   `vset c \ vset d = {e2}`.  Emits `mk e2 (vset d \ vset c) (d.conc \ c.conc) = mk e2 {u} ∅`:
   **`e2 <- (u)`**.  Model: `R = R`.  New: `u` on the right and not `cur`.  (Scala
   `cancellation`, Constraints.scala:1153: `abs1 = {e2}`, `abs2 = {u}`, `xs = {e2}`, `fs = ∅`.)
2. **Substitution** (`SubstApp G c d`, :375): `c := mk p {e1, e2} K` (`base`), `d := mk e2 {u} ∅`;
   `d.lhs = e2 ∈ vset c`.  Emits `mk p (({e1, e2}.erase e2) ∪ {u}) (K ∪ ∅) = mk p {e1, u} K`:
   **`p <- (e1, u, K)`**.  Model: `K ∪ R = K ∪ ∅ ∪ R`, parts disjoint because `rho e1 = ∅`.  New:
   `u` on the right, vset `≠ {u}`.
3. **Split mint** (`SplitApp G c u'`, Cut:1009) on `c := mk p {e1, u} K`, `u'` fresh: `c.conc = K ≠ ∅`;
   `|{e1, u}| = 2`; `¬ Named G {e1, u}` by `u_fresh` (the constraints added in 1-2 have vsets
   `{u}` and `{e1, u}`, the latter with conc `K ≠ ∅`); `u' ∉ allVars G`.  Emits **`u' <- (e1, u)`**
   and **`p <- (u', K)`**.  Model: `rho u' := rho e1 ∪ rho u = R`; `K ∪ R = K ∪ R`.  Both new.

Afterwards `W2Inv G' p e1 e2 u' K`: `base`, `single` persist; `cur' = mk p {u'} K`; `u'` differs
from everything; `u'` is on a right-hand side only in `cur'` (its definition has it on the
LEFT).  Growth per round: **+4 constraints, +1 variable, 3 productive steps, one split
child of `p` with the new group `{e1, u}`**; the groups `{e1, e2}, {e1, u_1}, {e1, u_2}, ...` are
pairwise distinct because the `u_i` are.

Seed: `G₀ = W2`.  Round 0 is the split mint on `base` (`W2` has no bare constraint, so
`{e1, e2}` is unnamed), yielding `W2Inv` with `u = u_1`.  So for every `n`,
`DefaultRun (1 + 3n) W2 G` with `|G| = 4 + 4n`; also `Diverges W2` (DefaultDiverge.lean:137).
`witness.py`: 5 rounds = 16 steps, every conclusion modelled under `R = {m}` and `R = ∅`,
six distinct groups at `p`.

### 3.3 Why exactly these ingredients

* Two single-variable decompositions of `p` with the same conc `K`: `cur`, supplied by every
  split mint, and `single`, through an old representative.  They give the alias link
  old-in-terms-of-new, `e2 <- (u)`.  Without `single`, the only cancellation at `p` is `cur`
  against `base`, returning `u <- (e1, e2)` (new-in-terms-of-old) -- nothing.
* A group at `p` with the same conc containing the old representative AND an empty
  variable (`base`).  The empty is forced: `p <- (e1, u, K)` with `rho u = rho e2` is satisfiable
  only with `rho e1 = ∅`; and since every derived constraint is entailed over the input
  vocabulary (`NonGenStep.models_iff`, `split_mint_conservativeExt`), any diverger of this
  shape has an atom FORCED empty by the input.
* `W2` is the smallest engine I found.  `{p <- (e1, k), p <- (e2, k), p <- (e1, e2, k)}` works
  as well; the single may be hidden one level up:
  `H2 = { p <- (e1, e2, k), q <- (p, s), q <- (e2, s, k) }` reaches `W2 ∪ H2` by one cancellation
  (`q <- (p, s)` against `q <- (e2, s, k)` gives `p <- (e2, k)`).

### 3.4 The saturation caveat -- names travel with their groups

The chain must NOT substitute the link into the name's definition.  In round `n`,
`SubstStep` with `c := u_1 <- (e1, e2)`, `d := e2 <- (u_n)` emits the bare `u_1 <- (e1, u_n)`, i.e.
`Names G u_1 {e1, u_n}`; with it present, the round's mint is replaced by `SplitReuseStep`
emitting `p <- (u_1, K)` (already present), and the engine stops.  Every
substitution-closed strategy derives it in the same round as `p <- (e1, u_n, K)` (both are
one-step consequences of the link).  Accordingly:

* my saturating closure (`experiments.py`: non-generative rules to a fixpoint before each
  mint) reaches a FIXPOINT on `W2` after one mint, 13 constraints;
* my mint-greedy chain explorer (`greedy.py`: one random non-generative conclusion when
  no mint is available) dies on `W2` in 8/8 trials -- with probability 1/2 per round it adds
  the spoiler first, and afterwards every link/name pair it forms is already named;
* the hand chain of §3.2, which orders steps deliberately, does not die.

This is DefaultDiverge's SCOPE distinction ("the loop takes only some of the available
steps") on the positive side: `TerminatesOnSat` quantifies over ALL runs and is refuted;
the statement that matters for a solver is about SATURATING (or fair) runs.  The
protecting mechanism, in general form:

> Whenever the link `e2 <- (X)` is derivable, the receiving group `S ∋ e2` at `p` and, if `S` is
> named by `n <- (S)`, the name's definition both contain `e2`; substitution rewrites both,
> and `n <- (S[e2 := X])` names the rewritten group no later than the rewritten group
> appears as a mint premise.

I checked the other vehicles of §2 against this.  TRANSFER (`q <- (p, A)`, `q <- (p, e1, A)`,
cancellation bringing `{e1, u_n}` down to `p`) also produces, through the substituted
decompositions of `q`, the link `e2 <- (u_n)` and hence the spoiler.  A NON-SINGLETON link
`e2 <- (u_n, T)` (from `r <- (e2, K')` against `r <- (u_n, T, K ∪ K_r)`, with `T` forced empty)
rewrites `u_1 <- (e1, e2)` into `u_1 <- (e1, u_n, T)`, again the next group.  Hence:

> **Conjecture S.**  Every run in which the system is closed under `SubstStep` before each
> mint is bounded from every satisfiable input.

No proof; no counterexample.

### 3.5 Empties from resolution: `NE6`

`NE6` (six constraints, all six INPUT rows nonempty; `NE6.json`): its first available mint
is a resolution at `0` with `C = {2,3,4}`, `D = {1,4}`, `C ∪ D = rho 0`, so the resolvent `z` is
EMPTY.  Mint-greedy chains then run the empty engine at parents `8`, `9`, `13` with groups
`{4, z}`, `{6, z}`, `{z, z'}`, ... (`probe.py`: 40 mints, 8 empty variables among 46; 8/8 trials
past 12 mints in `greedy.py`; two longer chains reached 80 mints, 613 and 804 constraints,
86 variables).  Under saturation `NE6` reaches a fixpoint (113 constraints,
5 mints) and `z <- ()` IS derived -- but only via `4 <- (|2,3|)` (cancellation) and then
`4 <- (z, (|2,3|))` against it.  So: the loophole is reachable from inputs with no empty row,
and the empty variable is exposed only after further derivation, which a chain need not
perform and a single-pass loop performs only in its own order.

## 4. The second layer: the loop (`Saturate.SatStep`) against the guards

`incorporateAll` (Constraints.scala:857) dequeues by priority
`(graph.sort(lhs), (rhs.hash, lhs.hash))`, `graph.sort` a reverse topological index of the
dependency graph `lhs -> rhs vars` (`Q.TypeVarGraph`, :407; leaves first).  The dequeued
partition is compared once against `proc`; consequences go to `incm`.

| behaviour | removes a `Named` witness (bare `≥2`-abstract definition)? | removes a `Resolved` witness `v <- (z, K)`? | can the loop take the re-enabled mint? |
|---|---|---|---|
| `makeEmpty v` (:1047): every partition mentioning `v` rewritten with `v` erased, originals deleted | A name `n <- (S)`, `v ∈ S`, becomes `n <- (S \ v)`; every premise `c <- (S, K)` becomes `c <- (S \ v, K)` in the same pass, and its group is named by the rewritten name.  Consistent; nothing re-enabled. | `v <- (z, K)` with `z` empty becomes `RHSConcr(K)` and triggers `makeConcrete v`. | -- |
| `makeConcrete v` / `destructiveSub` (:1086 / :1108), with `keepDefs` | Definitions `v <- (S)`, `|S| ≥ 2`, are KEPT.  A name `n <- (S)` with `v ∈ S` is rewritten to `n <- (S \ v, fs)` -- no longer bare -- while a premise `c <- (S, K)` becomes `c <- (S \ v, K ∪ fs)`: `S \ v` is UNNAMED, a NEW split premise (`KeepInert.keep_mints`).  Not a repeat of an additive mint; a mint on a group the additive calculus never forms (it has no erasure). | Every single-variable definition `v <- (x, C)` is deleted (re-expressed by cancellation as `x <- (fs \ C)`); the `ResPair` premises vanish with the witness. | Yes, if the rewritten premise is dequeued (it is re-enqueued: `nincm ++! trim(srs, nproc)`). |
| `unify` / `instantiate` / `replace` (:1006-1025) on `v <- (u)`: rename in every partition involving the variable, RE-ENQUEUE them | Names and premises are renamed together; a bare name stays bare.  No witness lost. | `v' <- (z, K)` renamed is still a witness. | Renaming re-enqueues, so the loop is not single-pass across renames.  This is what kills `W2`: `e2 <- (u_n)` is `RHSAbstr(Single)` and is unified, never substituted; `p <- (e1, e2, k)` becomes `p <- (e1, u_n, k)` but so does `u_1 <- (e1, e2)` become `u_1 <- (e1, u_n)`, a reverse-lookup hit. |
| `dedup` (`replace` / `subPartitions`, `w <- ()` on a duplicated variable) | Emits an empty, handled by `makeEmpty`. | -- | -- |
| `weaken` (dequeued rule dropped on the common / empty / concrete / singleton branches) | The dropped rule is `v <- (u)`, `v <- ()` or `v <- (fs)` -- never a name.  On the common-partition branch `v <- rhs` is dropped while `u <- rhs` stays and `v := u`: a bare `rhs` is still named (by `u`). | If `rhs = (z, K)`, `u <- (z, K)` remains. | -- |

So two behaviours carry the loop's termination on satisfiable input, and both are
DEFENCES the additive calculus lacks:

* **Rename of singleton links** removes the `W2` vehicle outright -- no `SubstStep` of a
  `Single` definition ever happens in the loop (the `RHSAbstr(Single(u))` branch pre-empts
  `learnPartitions`).  What the loop does instead, rewriting `u_1 <- (e1, e2)` together with
  `p <- (e1, e2, k)`, is the name-travel mechanism of §3.4 performed by `instantiate`.
* **`makeEmpty`** erases a DETECTED empty from every group, so an empty drives the engine
  only while undetected.  Detection: `cancellation` with an empty leftover (`W2`'s own input
  pair yields `e1 <- ()`), `selfSubstitution`, `dedup`, `makeEmpty` propagation.  In `NE6` the
  resolvent is undetected until `4 <- (|2,3|)` is derived.

**Transfer.**  `TerminatesOnSat` is false, so nothing transfers; the question becomes
which loop behaviours a termination theorem for the LOOP must model.  Minimum: a relation
with (a) `SatStep.rename` applied EAGERLY (every `v <- (u)` consumed before any
substitution), (b) `SatStep.empty` / `eraseEmpty` applied eagerly, and (c) the name-travel
property -- whenever a substitution rewrites a group at a mint premise, every bare
definition with that vset has already been rewritten.  With (a)-(c), Conjecture S is the
right target.  (c) is what a single-pass loop can violate by queue order (a name still in
`incm` when the rewritten premise is dequeued); that costs one extra mint per race, not a
divergence -- but that is an argument about orders, not a theorem.  The extra lemma a
positive result needs: a strategy-restricted run predicate (`SatRun`) and the invariant
"a mint premise's group is unnamed only if it contains a variable minted since the last
substitution closure", from which the alias-count induction of §2.3 might close.

The loop's remaining exposure: an UNDETECTED forced-empty atom reachable by
non-singleton links, or a resolution-minted empty (as in `NE6`) entering groups through
`x <- (z, D \ C)` substitutions before anything exposes `z <- ()`.  I could not build a chain
of that kind that survives name-travel, and could not prove none exists.

## 5. What to prove next, ranked

1. **`not_TerminatesOnSat`** (easy, ~200 lines, DefaultTerm.lean or a new
   `DefaultSatDiverge.lean`): `W2Inv` (§3.1), the round lemma (§3.2) in the style of
   `GInv.round` / `GInv.diverges_exact`, the seed with its model, and
   `W2_witness : (∃ rho, SModels rho W2) ∧ Diverges W2 ∧ ¬ TerminatesOnSat`.  `u_fresh` carries
   the guard; `cr_decide` / `nl_decide` settle the `mk` arithmetic.
2. **Name-travel lemma** (medium, pure syntax): if `SubstStep` with definition `d` turns a
   premise `c` with `Names G n (vset c)` into `c'` (`d.lhs ∈ vset c`, `d.lhs ≠ n`), then `SubstStep`
   with the same `d` turns `n`'s definition into a constraint naming `vset c'`.  The invariant
   Conjecture S rests on.
3. **Conjecture S for a restricted strategy** (hard): a `LazyRun` predicate
   (substitution-closed before each mint) and boundedness from a model; needs 2, the
   alias-count induction of §2.3, and the conc-climb lemma for resolution children.  A
   counterexample search (explorer, below) should precede it.
4. **König infrastructure** (medium; positive results only): the parent forest as an
   object, rank decrease along a run, and "some parent has infinitely many split children"
   from `DefaultRun.length_le_forms`.
5. **A loop-shaped relation** (hard; where the compiler's guarantee actually lives): eager
   rename and eager `makeEmpty`, and the theorem that `W2`-type engines are impossible under
   it (every alias link is consumed by a rename before it can be substituted).
   `Saturate.SatStep` is too permissive for this (unrestricted `weaken`, no eagerness).

For the explorer (key: explorer), in order of value:

* Feed `W2.json`, `H2.json`, `NE6.json` to the real `Subst.solve` at many id bases
  (`tracker/repro/crule` harness shape); record which defence fires first (`makeEmpty` after
  `e1 <- ()`, or `unify` of `e2 <- (u_1)`) and confirm termination.  Prediction: terminates at
  every base; on `W2` the leaf priority of `e1 <- ()` makes `makeEmpty` fire before a second mint.
* In `rowclosure.py` add a mint-greedy strategy (non-generative conclusions applied one at
  a time, mints taken as soon as available, as `greedy.py` does) and rerun `search` /
  `families`.  The existing `bfs` / `lazy` / `mintfirst` strategies are substitution-closed per
  round and cannot see this class.  Population target: seeds with a FORCED-empty variable
  (two decompositions of one variable differing in one slot; a resolution pair with
  `C ∪ D` equal to the model row).
* Search for a forced-empty atom that no rule exposes (`e <- ()` absent from the saturated
  closure) together with a non-singleton old-in-terms-of-new link `e2 <- (u, T)`; that is the
  only shape that dodges both loop defences, and I could not build it by hand.
* In the 27 example modules where `splitConcrete` mints on kept definitions
  (ROW-CONSTRAINT-STATE, Q2), look in the `rowTrace` for Resolution-minted ids whose every
  partition carries the parent's whole concrete part -- resolution-minted empties in real
  code.
