## 3. The answer: `TerminatesOnSat` is FALSE -- a satisfiable 2-constraint seed with an infinite productive run

### 3.1 The seed (`twodecomp`, family (i): two decompositions of one variable with a concrete part)

    a <- (e, y, (|1|))          a = 0, e = 1, y = 2
    a <- (e, (|1|))
    rho a = {1},  rho e = {},  rho y = {}          (both constraints hold: {1} = {} u {} u {1}, parts disjoint)

Seed file: `scratchpad/satterm/explorer/seeds/twodecomp.json`.  `y` is forced empty by the
two decompositions (cancellation derives `y <- ()`), but the chain below never uses that.

### 3.2 The infinite run (three DefaultSteps per level, only CancelStep, SubstStep, SplitStep)

Write u_0 := e.  Level 0 is one step, every later level is three:

    L0   SplitStep      premise a <- (e, y, |1|)              [conc = {1} != {}, |{e,y}| = 2, not Named G {e,y}, u_1 fresh]
                        emits  u_1 <- (e, y),  a <- (u_1, |1|)
    Ln   CancelStep     c = a <- (e, |1|),  d = a <- (u_n, |1|)      [c.lhs = d.lhs, c.conc = {1} <= {1} = d.conc, vset c \ vset d = {e}]
         (n >= 1)       emits  e <- (u_n)                             [mk e (vset d \ vset c) (d.conc \ c.conc) = mk e {u_n} {}]
         SubstStep      c = a <- (e, y, |1|),  d = e <- (u_n)          [d.lhs = e in vset c]
                        emits  a <- (u_n, y, |1|)                     [mk a ((vset c).erase e u {u_n}) (c.conc u {}) ]
         SplitStep      premise a <- (u_n, y, |1|)                    [conc != {}, |{u_n, y}| = 2, not Named G_n {u_n, y}, u_{n+1} fresh]
                        emits  u_{n+1} <- (u_n, y),  a <- (u_{n+1}, |1|)

The first two levels, fully explicit (fresh ids as the explorer allocates them: u_1 = 3, u_2 = 4, u_3 = 5):

    step 1  split.mint   [a <- (e,y,|1|)]                        =>  v3 <- (v1 v2),  v0 <- (v3 (|1|))
    step 2  cancel       [v0 <- (v1 (|1|)) ; v0 <- (v3 (|1|))]    =>  v1 <- (v3)
    step 3  subst        [v0 <- (v1 v2 (|1|)) ; v1 <- (v3)]       =>  v0 <- (v2 v3 (|1|))
    step 4  split.mint   [v0 <- (v2 v3 (|1|))]                    =>  v4 <- (v2 v3),  v0 <- (v4 (|1|))
    step 5  cancel       [v0 <- (v1 (|1|)) ; v0 <- (v4 (|1|))]    =>  v1 <- (v4)
    step 6  subst        [v0 <- (v1 v2 (|1|)) ; v1 <- (v4)]       =>  v0 <- (v2 v4 (|1|))
    step 7  split.mint   [v0 <- (v2 v4 (|1|))]                    =>  v5 <- (v2 v4),  v0 <- (v5 (|1|))
    ...

**Invariant** (G_n = the system after level n, n >= 1):

    G_n = G_0  u  { u_k <- (u_{k-1}, y) : 1 <= k <= n }  u  { a <- (u_k, |1|) : 1 <= k <= n }
              u  { e <- (u_k) : 1 <= k <= n-1 }  u  { a <- (u_k, y, |1|) : 1 <= k <= n-1 }
    rho u_k = {}  for every k (the split child denotes the union of its group; both members are empty)

* Every premise of level n+1 is in G_n (the two seed constraints, `a <- (u_n, |1|)` from the
  level-n mint, and the level's own cancel and subst outputs).
* The split guard holds: the bare (conc = {}) constraints of G_n are the two seed-independent
  families `u_k <- (u_{k-1}, y)` and `e <- (u_k)`, whose vsets are `{u_{k-1}, y}` (k <= n) and
  `{u_k}`; none equals `{u_n, y}`.  So `not Named G_n {u_n, y}`, and the mint fires; it is
  the mint itself that names `{u_n, y}` (by u_{n+1}), which is why the next group `{u_{n+1}, y}`
  is unnamed again.
* Every step is PRODUCTIVE (G ⊂ G'): u_n is fresh at its mint, so every constraint that
  mentions u_n is new when emitted (the cancel output `e <- (u_n)`, the subst output
  `a <- (u_n, y, |1|)`, and the two mint outputs).  Hence `DefaultRun (3n+1) G_0 G_n`
  and `|G_n| = 2 + 2n + 2(n-1) + 2 = 4n + 2`.
* Every constraint is satisfied by the extended rho (checked on every insertion by the
  explorer's model check): rho a = {1} = {1} u rho u_n u rho y, parts disjoint because
  rho u_n = rho y = {}.

Therefore, with G_0 satisfiable, `∀ N, ∃ n > N, ∃ G, DefaultRun n G_0 G`: **`DefaultTerm.TerminatesOnSat` is false**,
and `DefaultDiverge.Diverges G_0` holds for this satisfiable G_0 (each step adds >= 1 constraint, so
`G_0.card + n <= G.card`).

Machine check: `scratchpad/satterm/explorer/witness_check.py 6` applies exactly these steps (nothing
else) to the explorer's System, asserting per step that the premises are present, the rule's side
conditions hold, the guard `not Named` holds at that moment, the emitted constraint is the one above,
the step is productive, and the model check passes:

    level 0: minted v3 <- {v1,v2}, a <- (v3,|1|); |G| = 4 after 1 steps; ranks: a=1, u=0
    level 1: minted v4 <- {v2,v3}, a <- (v4,|1|); |G| = 8 after 4 steps; ranks: a=1, u=0
    ...
    level 5: minted v8 <- {v2,v7}, a <- (v8,|1|); |G| = 24 after 16 steps; ranks: a=1, u=0
    OK: 6 levels, 16 DefaultSteps, every step productive; every emitted constraint satisfied by rho

### 3.3 Where the König argument breaks

Every child u_k has rank 0 < 1 = rank a (`mintParent_rank_lt` holds, as it must), and every child's
parent is the same variable `a`: **one parent acquires infinitely many split children**, one per
distinct group `{u_n, y}`, and the groups are manufactured exactly as the obstruction (5) predicted:
substitution puts the name minted at level n (u_n, through `e <- (u_n)`) into the constraint
`a <- (e, y, |1|)`, and the empty-row variable y recurs in every group without violating
disjointness.  `namedGroupsAt a G_n` grows with n; nothing computed from G_0 bounds it.

Only three rules are involved.  The explorer confirms the rule dependence on this seed
(strategy `chase`, mint cap 200):

    --rules cancel,subst,split                  con-cap at 100 mints    (diverges)
    --rules subst,split                         fixpoint, 1 mint
    --rules cancel,split                        fixpoint, 1 mint
    all rules but cancel                        fixpoint, 1 mint
    all rules but subst                         fixpoint, 1 mint
    all rules, --scala-dedup                    con-cap at 100 mints    (diverges; dedup emissions do not block it)

### 3.4 Variants (all machine-checked to diverge under `chase`; seeds under `seeds/`)

* `emptypair` -- no cycle and no self-partition in the seed or its closure's first level:
  `a <- (e, y, |1|)`, `a <- (|1|)`, `y <- ()`; four steps per level (Cancel -> `u_n <- ()`;
  CommonPart with `y <- ()` -> `y <- (u_n)`; Subst -> `a <- (e, u_n, |1|)`; Split mint).
  Machine check: `witness_check2.py` (21 DefaultSteps for 6 levels).  Chase: 200 mints, 4777
  constraints (LINEAR in the mints: 4 constraints per level plus the pairwise `u_i <- (u_j)` names).
* `selfloop` -- `a <- (a, e)`, `a <- (e2, |1|)` (a self-partition, satisfiable since rho e = {}):
  two steps per level (Subst of the mint output into the self-partition, then Split).
* `copycycle` -- `b <- (a, e)`, `a <- (b)`, `a <- (e2, |1|)` (two equal-row variables in a cycle):
  three steps per level.
* The random search's growing candidates (section 5) are all of this kind: the busiest parent's
  children all have rank 0 -- the chain always runs through EMPTY names.  A chain through
  non-empty names would need two distinct fresh names with the same non-empty row inside one
  group, which disjointness forbids; so with a fixed parent row the only unbounded ingredient is
  the supply of empty names, and every empty name is a copy of every other (CommonPart /
  cancellation make them interchangeable).

### 3.5 What this does and does not say about the shipped solver

The witness is a run of the ADDITIVE relation `DefaultStep`, i.e. of the rule set as formalised.
Its order is legal (every step's premises are present and its guard true when it fires) but it is
a particular order: the breadth-first strategy of the explorer (all non-generative consequences of
a round before the round's mints) reaches a 13-constraint fixpoint on the same seed, because the
name `u_n <- (u_n, y)` (Subst of `e <- (u_n)` into `u_n <- (e, y)`) is derived in the same round
as the split premise and blocks the mint.  The real `incorporateAll` loop is a worklist with
deletions: `e <- (u_n)` is a rename (`unify`), `u_n <- ()` / `y <- ()` trigger `makeEmpty`, which
ERASES the empty variable from every group -- exactly the steps `Saturate.SatStep` models and this
tool does not.  So this refutes the rule-set theorem (`TerminatesOnSat`), not the loop; whether the
loop's deletions always cut the chain is a separate question (the DefaultTerm docstring already
says the loop is not a sub-relation of `DefaultSteps`).
