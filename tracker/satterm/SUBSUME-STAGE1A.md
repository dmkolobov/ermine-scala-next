# SUBSUME-STAGE1A — the substitution model: the kind-variable walk over a substitution

Stage S1a of `tracker/PROMPT-subsume-termination.md`; brief `tracker/satterm/briefs/brief-S1a.md`.
Worktree `~/research/ermine/ermine-scala-wt-subsume-s1a`, branch `subsume-s1a`. Opus Lean prover.
Nothing committed. Scratch: `/home/dmitry/research/ermine/scratch-subsume/s1a/`.

S0's report (`~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/SUBSUME-STAGE0.md`)
was still the empty stub at every point during the stage proper (82 bytes, checked three
times), so nothing proved here is conditioned on S0's numbers; everything is a reading of the
source or a theorem. It landed before the review, and the **Review fixes** section (§7) cites
it where the reviewer required.

**Reviewed FIX-THEN-LAND** (`tracker/satterm/SUBSUME-STAGE1A-REVIEW.md`). All four findings are
prose corrections; **no theorem changed, none needed re-proving**. §7 lists each finding and
where it was fixed, with the post-fix build and audit lines.

---

## 0. THE ANSWER, up front

**The walk at `Subst.scala:648` TERMINATES — unconditionally, on every input, with no
well-formedness hypothesis whatever.** *Yes*, for the walk.

The brief anticipated this and told me what to do instead: *"If no binding is followed, the
'acyclic' invariant is vacuous for termination and the theorem to prove is the COST bound ...
plus the equivalence of the restricted walk; say so and prove that instead."* That is what this
stage did.

* **H2 is FALSE as a reading of the code, and that is proved two ways.**
  `Type.scala:653` is `case VarT(v) => v.extract.vars`. `v : V[Kind]`, so `extract` is the type
  variable's **kind annotation** (`Vars.scala:99-112`, the `extract` field of `V`), not its
  binding; `Kind.scala:65` is `case VarK(v) => Vars(v)`, which emits and stops. Neither
  `hm.types` nor `hm.kinds` is consulted anywhere on the path. `follow_diverges` shows that
  H2's *function* — the binding-following variant — really does diverge on the environment
  `a ↦ a a`; `escs_total_on_cyclic` shows that the *shipped* one returns on exactly that
  environment, with `escs = [1]`. The orchestrator's code-reading note in `SUBSUME-PLAN.md`
  (2026-09-16, "as read, the kind-variable walk follows no binding at all") is confirmed.
* **The acyclicity invariant is therefore vacuous.** Not one of the 55 theorems in the new
  module carries an acyclicity, occurs-check or well-formedness hypothesis. The invariants that
  *do* carry weight are about variable IDENTITY (`SkolemCoherent`) and about the CONTENT of
  skipped entries (`Untouched` -- not their age; review Finding 1), both stated precisely in §3 below.
* **The cost is exactly one substitution pass, up to a constant of 4 — in NODE VISITS, not in
  time.** `escs_cost_le_subPass`. `instantiateType` runs such a pass over the *whole* of
  `hm.types` on **every** binding it makes (`Subst.scala:254`). So `:648` cannot be
  asymptotically worse *in node visits* than the work that built the environment it walks.
  The qualification is not cosmetic (review Finding 2): `costV` charges one step per `VarsE`
  node, but in the JVM a `minus` node runs `s ++ t` / `-- t` / `t intersect s` over an
  immutable `Set` whose size grows with the distinct variables seen (`Vars.scala:28-32`), and
  `Vars.filter`/`nonEmpty` materialise a `Vector` per half through `ForeachIterable.iterator`
  (`ForeachIterable.scala:17-21`), against a singleton-map lookup per node in `Type.subst`. The
  real ratio therefore carries a `log |seen|` factor. S0's independent measurement vindicates
  the conclusion anyway (`:648` = 2.2 s of a 184 s suite), but the bound alone does not. **This is the stage's most consequential result for S2 and for S1b:
  if `:648` takes 28 CPU-minutes, so does every unification binding, and the hang is not
  located at `:648` — it is located in whatever made `hm` that large.** That points at H1/H3,
  and S1b's rejection-path question, not at the escape check.
* **The walk is nevertheless exponential in the size of a SHARED representation**
  (`walk_exp_in_dag`): a DAG of `4n+1` nodes whose walk costs `2^(n+1) − 1`, because `vars` has
  no memo table and visits every path. But the matching negative `subst_pays_the_same` says
  `Type.subst` unfolds the same DAG the same way, so such an environment cannot be reached
  cheaply through `instantiateType`. **Memoising `:648` on physical identity therefore removes
  an exponential the unifier is already paying.** The win has to come from the walk's DOMAIN.
* **The equivalence S2 needs is proved** (`verdict_eq`, `verdict_restrict_untouched`) and **what
  may change is nothing observable AT `:648`** (`:365-367` prints `escs`; see §4).

---

## 1. What was built

| path | what |
|---|---|
| `tracker/lean/Rowpartition/SubsumeEscape.lean` | **NEW**, 1201 lines (1165 before the review fixes, which touched only doc comments), 55 named theorems (49 plain + 6 `@[simp]`), all 55 audited |
| `tracker/lean/Rowpartition.lean` | `import Rowpartition.SubsumeEscape` + a 31-line root doc-comment entry |
| `tracker/lean/README.md` | new subsection `### 2026-09-16: SubsumeEscape — the escaping-skolem check at Subst.scala:648` under "Later additions" (theorem table; Lean vs. paper) |
| `tracker/satterm/SUBSUME-STAGE1A.md` | this report |

No Scala was touched. No flag was added. No default was changed.

Scratch (evidence, not deliverables):
`/home/dmitry/research/ermine/scratch-subsume/s1a/{build-baseline.log, axioms.lean, axioms-out.txt,
audit.log, audit-baseline.log, audit-final.log, eval.lean, eval-out.txt}`.

### Build and audit

```
$ export PATH=$HOME/.elan/bin:$PATH; cd tracker/lean
$ lake build
Build completed successfully (872 jobs).                 # 4.9 s; 871 before this stage
$ lake env lean Rowpartition/SubsumeEscape.lean
(exit 0, no output, 3.5 s)
$ lake env lean Audit.lean
Rowpartition theorems audited: 4936; declarations using a non-standard axiom: 0
```

Baseline for comparison, taken by deleting the import, rebuilding and re-auditing, then
restoring (`scratch-subsume/s1a/audit-baseline.log`):

```
Rowpartition theorems audited: 4676; declarations using a non-standard axiom: 0
```

so the module contributes 260 audited theorems (55 named in source, the rest generated equation
and match-arm lemmas, which the audit checks too).

Hygiene: `grep -nE 'sorry|partial|unsafe|native_decide|axiom '` over the new file returns
nothing. The only warning `lake build` prints is the pre-existing `Rowpartition.lean:94` long
line, which is in a doc comment I did not touch (`git show HEAD:tracker/lean/Rowpartition.lean |
sed -n 94p` is byte-identical).

---

## 2. What was measured (code reading, with line numbers)

Not a timing — a reading of the five files the brief names, recorded so the reviewer can check
the model against the source rather than against this prose.

| fact | where |
|---|---|
| `escs = hm.fskvs.filter(stss) ++ hm.kindVars.filter(skss)` | `Subst.scala:648` |
| `escs` is observed **only** through `nonEmpty`; the message at `:650-656` prints `e1`/`e2`, and the one line that printed `escs` is **commented out** at `:657` | `Subst.scala:649-658` |
| `fskvs = Type.fskvs(types)`; `kindVars = Kind.kindVars(kinds) ++ Kind.kindVars(types)` | `Subst.scala:168-169` |
| `VarT(v) => v.extract.vars` — `v : V[Kind]`, `extract` is the **kind annotation** | `Type.scala:653` |
| `VarK(v).vars = Vars(v)` — emits and stops; `ArrowK.vars = i.vars ++ o.vars`; default `Vars()` | `Kind.scala:65, 59, 16` |
| `Con(_,_,_,k) => kindVars(k)`, `k : KindSchema`; `KindSchema.vars = kindVars(body) -- forall` | `Type.scala:652`, `KindSchema.scala:26` |
| `Forall`'s `vars` **deliberately excludes** its constraint `q` | `Type.scala:654` |
| the map instance right-folds `A.vars(x._2) ++ ys` over the map's **values** | `Kind.scala:124-126` |
| `Vars.++` is `w(that(s,f), f)` with **by-value** arguments, so building a `Vars` is already a full structural walk | `Vars.scala:22-24` |
| `Vars.--` is `(that(s ++ t, f) -- t) ++ (t.map(...) intersect s)` | `Vars.scala:28-32` |
| `V.equals`/`hashCode` use the **id alone** | `Vars.scala:105-107` |
| `Vars.filter` goes through `ForeachIterable.iterator`, which materialises a `Vector` — so both halves of `:648` are strict | `ForeachIterable.scala:18-22` |
| `instantiateType` runs `subType(Map(v -> e), hm.types)` over the **whole** map on every binding | `Subst.scala:250-254` |
| `AppT.subst` recurses into both children unconditionally, returning `this` only when **nothing** changed | `Type.scala:227-230` |
| `VarT.subst` returns **the same object** `t` for every occurrence it replaces — the one sharing-creating step | `Type.scala:245-246` |
| `VarT.map` (the `instantiateKind` path) allocates a fresh `V` unconditionally — it does **not** preserve sharing | `Type.scala:239` |
| `sks`/`sts` are freshly minted by `unbind(Skolem, e1)` | `Subst.scala:614, 682-695` |
| `Kind.scala:96-98` already carries a P7 roadmap note about this walk ("NO empty-map fast path here, deliberately") | `Kind.scala:96` |

**The one inference these support and the report rests on.** Both `Type.subst` and
`typeHasKindVars.vars` are unmemoised structural recursions over the same term; the first is run
over the whole environment on every binding, the second once at `:648`. Whatever the walk costs
at `:648`, the unifier has already paid a constant multiple of it, once per binding.

---

## 3. What was proved

`tracker/lean/Rowpartition/SubsumeEscape.lean`, namespace `Rowpartition.SubsumeEscape`.
55 named theorems; every one's `#print axioms` output is in
`scratch-subsume/s1a/axioms-out.txt` (55 lines, one per declaration). Distribution of axiom sets:

```
   7  [propext]
  36  [propext, Quot.sound]
  12  [propext, Classical.choice, Quot.sound]
```

— i.e. **every declaration's axiom set is a subset of Lean's three standard axioms; 0
non-standard; `sorryAx` appears nowhere.** The per-theorem list follows; the axiom column is
`p` = `propext`, `c` = `Classical.choice`, `q` = `Quot.sound`.

### 3.1 The model (what the theorems are about)

* **Syntax.** `VTy` (`Vars.scala:76-86`), `KVar` = `V[Unit]`, `Knd` (`Kind.scala:20-67`),
  `KSchema` (`KindSchema.scala:7`), `TVar` = `V[Kind]` with its `kind` field = `extract`,
  and a mutual `Ty`/`TyList` with exactly the constructors the two `vars` functions dispatch on
  (`arrowT`, `app`, `con`, `var`, `allT` carrying `vs`/`ts`/`q`/`b`, `exT`, `part`, `mem`,
  `opaqueT`). `Env` is `SubstEnv` cut down to `types` and `kinds`.
* **`Vars` itself** is `VarsE` (`nil`/`one`/`many`/`app`/`minus`) plus `runV`, which *is*
  `Vars.apply(s, f)`: it threads the seen set and returns what the callback was called with.
  `minus` carries a list of **ids** because `Vars.--` does `w.toSet` and `V.equals` is id
  equality.
* **The walks** `kvarsK`, `kvarsKS`, `kvarsTVars`, `kvarsT`/`kvarsTL`, `tvarsT`/`tvarsTL`,
  `kvarsKinds`, `kvarsTypes`, `tvarsTypes`, `envKindVars`, `envTypeVars`, `fskvs`, `escs`,
  `verdict` are a case-for-case transcription of the Scala cited in §2.
* **Cost.** `costV` counts `apply` invocations; `subPass`/`subPassL` count the nodes ONE
  substitution pass visits.

### 3.2 `Vars.scala`, as a function

| theorem | statement | axioms |
|---|---|---|
| `memN_iff` | `memN n s = true ↔ n ∈ s` | p q |
| `memN_false` | `memN n s = false ↔ n ∉ s` | p q |
| `mem_map_filter` | `b ∈ (l.filter p).map f ↔ ∃ a, a ∈ l ∧ p a ∧ f a = b` | p q |
| `fvId_nil` / `fvId_one` / `fvId_many` | `fvId idOf nil = []`, `… (one a) = [idOf a]`, `… (many as) = as.map idOf` | p q |
| `fvId_app` | `fvId idOf (app x y) = fvId idOf x ++ fvId idOf y` | p q |
| `mem_fvId_minus` | `n ∈ fvId idOf (minus x t) ↔ n ∈ fvId idOf x ∧ n ∉ t` | p q |
| `fvE_subset_occE` | `a ∈ fvE idOf e → a ∈ occE e` — `--` only ever removes | p q |
| **`runV_seen`** | `∀ e s n, n ∈ (runV idOf e s).2 ↔ n ∈ s ∨ n ∈ fvId idOf e` — **the seen set out is the seen set in plus the free variables**, for `++` by construction and for `--` because `(s \ t) ∪ (t ∩ s) = s` is precisely what `Vars.scala:31`'s last term recovers | p c q |
| **`runV_emitted_id`** | `∀ e s n, n ∈ (runV idOf e s).1.map idOf ↔ n ∈ fvId idOf e ∧ n ∉ s` — **it emits exactly the free ids not already seen.** Unconditional | p c q |
| `runV_emitted_subset` | `a ∈ (runV idOf e s).1 → a ∈ fvE idOf e` — the element-level direction needing no hypothesis | p c q |
| **`many_can_duplicate`** | `(runV id (many [7,7]) []).1 = [7,7]` — **refutes `Vars`'s own docstring** ("designed to avoid duplicates", `Vars.scala:13`): `Vars(vs: Iterable)` (`:60-65`) tests each element against the seen set it was *entered* with and never updates it inside its own loop. Harmless on this path (`Kind.vars`/`Type.vars` build only `Vars(v)` singletons) but it is a defect of the class | p q |
| `runVC_val` | the instrumented run returns what `runV` returns | p q |
| `runVC_steps` | `(runVC idOf e s).2 = costV e` | p q |
| **`runV_steps`** | both at once — **the cost model is measured, not asserted**: one run makes exactly `costV e` invocations, **a number fixed by the expression alone**, hence by the terms the environment stores and never by what their variables are BOUND to. *This is the precise form of "termination" for this walk, and the precise sense in which the acyclicity invariant is vacuous* | p q |

### 3.3 H2, refuted — and its function exhibited (the `DefaultSatDiverge` half)

| theorem | statement | axioms |
|---|---|---|
| **`follow_diverges`** | `∀ f, kvarsFollow cyclicEnv f (var a) = none ∧ kvarsFollow cyclicEnv f (app (var a) (var a)) = none` — the **binding-following** reading of `Type.scala:653` returns for no fuel at all on `cyclicEnv = { a ↦ a a }`. H2 is a coherent hypothesis about a coherent function | p |
| **`escs_total_on_cyclic`** | `escs cyclicEnv [] [aVar] = [1]` — **the shipped reading returns on the same environment**, by `decide`. An environment `occursFail` (`Subst.scala:228-229`) exists to prevent is not a problem for this walk | p q |
| `verdict_total_on_cyclic` | `verdict cyclicEnv [] [aVar] = true` | p q |
| `escs_cyclic_other` | `escs cyclicEnv [] [] = []` — the cyclic binding is not what decides the verdict either; non-vacuity of the pair | p q |

### 3.4 Cost: the walk against one substitution pass

| theorem | statement | axioms |
|---|---|---|
| `costK_eq` | `costV (kvarsK k) = treeK k` — the kind walk costs exactly the kind's node count | p |
| `costTV_le` | `costV (kvarsTVars ts) ≤ 2 * sTV ts` | p q |
| `subPass_pos` | `1 ≤ subPass t` | p q |
| **`kvars_cost_le`** | `∀ t, costV (kvarsT t) ≤ 2 * subPass t` — **the kind-variable walk over a type costs at most twice one substitution pass over it** | p q |
| `kvarsL_cost_le` | the same over `TyList` | p q |
| **`tvars_cost_le`** | `∀ t, costV (tvarsT t) ≤ 2 * subPass t` — the same for the walk behind `Type.fskvs` | p q |
| `tvarsL_cost_le` | the same over `TyList` | p q |
| `cost_tvarsTypes_le` | `costV (tvarsTypes l) ≤ 2 * Σ subPass + \|l\| + 1` | p q |
| `cost_kvarsTypes_le` | `costV (kvarsTypes l) ≤ 2 * Σ subPass + \|l\| + 1` | p q |
| `cost_kvarsKinds_le` | `costV (kvarsKinds l) ≤ Σ treeK + \|l\| + 1` | p q |
| **`escs_cost_le_subPass`** | `escsCost Γ ≤ 4 * subPassEnv Γ + kindPassEnv Γ + 2 * \|Γ.types\| + \|Γ.kinds\| + 4` — **the whole escaping-skolem check costs at most four substitution passes over `hm.types`, one over `hm.kinds`, and a per-entry constant.** `instantiateType` runs one such pass on *every* binding (`Subst.scala:254`), so `:648` is a constant factor of ONE unification step | p q |

### 3.5 Sharing: the exponential witness, and why it is not reachable

| theorem | statement | axioms |
|---|---|---|
| `powD_size` | `dsize (powD n) = 4n + 1` — the shared representation is linear | p q |
| `powD_unfold` | `∀ env, unfoldD env (powD n) = dbl n` — it unfolds to the `n`-fold doubling | p |
| `cost_dbl` | `costV (kvarsT (dbl n)) + 1 = 2^(n+1)` | p q |
| `subPass_dbl` | `subPass (dbl n) + 1 = 3 · 2^n` | p q |
| **`walk_exp_in_dag`** | `dsize (powD n) = 4n+1 ∧ costV (kvarsT (unfoldD [] (powD n))) + 1 = 2^(n+1)` — **the walk is EXPONENTIAL in the size of a shared representation**, because `vars` has no memo table and visits every path. This is the brief's "cost exponential in n via sharing" witness | p q |
| **`subst_pays_the_same`** | `subPass (unfoldD [] (powD n)) + 1 = 3 · 2^n` — **and the matching negative.** `Type.subst` unfolds the same DAG the same way (`Type.scala:227-230`: both children always, `this` only when nothing changed), so an environment on which the walk is exponential **cannot be reached cheaply through `instantiateType`**. Memoising `:648` alone removes an exponential the unifier is paying anyway | p q |

`#eval` of the family (`scratch-subsume/s1a/eval-out.txt`), `(n, dsize, walk cost, subst pass)`:

```
[(0, 1, 1, 2), (1, 5, 3, 5), (2, 9, 7, 11), (3, 13, 15, 23), (4, 17, 31, 47), (5, 21, 63, 95)]
```

### 3.6 The equivalence — the S2 licence

**The invariants, stated precisely.** Neither is acyclicity.

```lean
/-- Global id uniqueness, in the only form the equivalence needs. -/
def SkolemCoherent (Γ : Env) (sts : List TVar) : Prop :=
  ∀ v ∈ occE (envTypeVars Γ), v.id ∈ sts.map TVar.id → v.ty = VTy.skolem

def Untouched (old : List (TVar × Ty)) (sks : List KVar) (sts : List TVar) : Prop :=
  (∀ v ∈ occE (tvarsTypes old), v.id ∉ sts.map TVar.id) ∧
    (∀ u ∈ occE (kvarsTypes old), u.id ∉ sks.map KVar.id)
```

`SkolemCoherent` is discharged by `Vars.scala:92-95`'s global id uniqueness together with
"`unbind(Skolem, e1)` mints skolems" (`skolemCoherent_of_unique`).

`Untouched` is a statement about the **content** of `old` at the moment of the check and is
**not** discharged by insertion order — see §4 item 3 (review Finding 1). `instantiateType`
(`Subst.scala:254`) rewrites every value in `hm.types` on every binding, so an entry that
predates the `:614` skolem draw can still come to mention a skolem drawn there; discharging
`Untouched` needs a mechanism that re-stamps an entry whenever `subType` changes its value, or
that tracks the skolem ids each entry currently contains, and proving that law is S2's
obligation.

| theorem | statement | axioms |
|---|---|---|
| `skolemCoherent_of_unique` | id uniqueness + "the signature's variables are skolems" ⟹ `SkolemCoherent` | p q |
| `isEmpty_false_iff`, `any_congr_mem`, `tvarsTypes_append`, `kvarsTypes_append`, `occE_tvarsTypes_append`, `occE_tvarsTypes_right` | list plumbing | p / p c q |
| `escs1_iff` | the **type half** of `escs` is nonempty iff one of the call's skolem type variables occurs in the environment (needs `SkolemCoherent`) | p c q |
| `escs2_iff` | the **kind half**, with **no hypothesis at all** — `hm.kindVars.filter(skss(_))` carries no `Skolem` test | p c q |
| **`verdict_iff`** | `SkolemCoherent Γ sts → (verdict Γ sks sts = true ↔ verdictR Γ sks sts = true)` | p c q |
| **`verdict_eq`** | `SkolemCoherent Γ sts → verdict Γ sks sts = verdictR Γ sks sts` — **THE EQUIVALENCE.** The restricted check `verdictR Γ sks sts = sts.any (occursTV ·.id Γ) \|\| sks.any (occursKV ·.id Γ)` gives the SAME verdict as the whole-environment collect-and-filter | p c q |
| **`skolem_filter_redundant`** | under the same invariant, `Type.fskvs`'s `_.ty == Skolem` filter (`Type.scala:666`) may be deleted: the id test already implies it | p c q |
| `skolemCoherent_shrink` | the invariant survives dropping entries | p |
| **`escs_restrict_untouched`** | `Untouched old sks sts → verdictR ⟨old ++ new, kinds⟩ = verdictR ⟨new, kinds⟩` | p c q |
| **`verdict_restrict_untouched`** | the same on the SHIPPED `verdict`, under `Untouched` + `SkolemCoherent` — **entries whose CONTENT cannot mention this call's skolems may be skipped entirely.** The only restriction in the file that could make the check asymptotically cheaper rather than merely tidier — and the hypothesis is about content, never about age (§4 item 3) | p c q |
| **`no_early_exit_on_empty`** | `verdictR Γ sks sts = false → (∀ w ∈ sts, occursTV w.id Γ = false) ∧ (∀ w ∈ sks, occursKV w.id Γ = false)` — **the limit.** On a run where nothing escapes, every skolem is still tested against the whole environment: **short-circuiting is not the fix** | p q |
| **`kind_half_not_reducible_to_type_skolems`** | `(runV TVar.id (envTypeVars kindOnlyEnv) []).1 = [] ∧ escs kindOnlyEnv [uKV] [] = [2] ∧ verdict … = true` — **one restriction that is NOT available: the kind half cannot be restricted to the entries the skolem TYPE variables occur in.** A one-entry environment binding a FREE type variable to a `Con` whose kind schema mentions a skolem kind variable has **no** skolem type variable anywhere, and the check still (correctly) reports an escape. This does **not** refute the brief's candidate `X` read so that "the types they occur in" includes KIND-LEVEL occurrence — in `kindOnlyEnv` the skolem `u` does occur in the entry's type, inside the `Con`'s kind schema — so a restriction keyed on kind-level occurrence stays open to S2 (review Finding 3) | p q |
| `kindOnly_verdictR` | …and `verdictR` agrees with it, as `verdict_eq` requires | p q |

---

## 4. What the S2 implementer MAY and MAY NOT change

**Read this first: after review Finding 1, S1a licenses NO asymptotic improvement to `:648`
at all.** `verdict_eq` and `skolem_filter_redundant` are verdict-preserving *tidying* —
`verdictR` still walks the whole environment (`occursTV` is `memN n (fvId … (envTypeVars Γ))`)
— and `no_early_exit_on_empty` proves the short-circuit never fires on a no-escape run, which
is every successful signature check. `verdict_restrict_untouched` is the only asymptotic
licence, and it now requires S2 to build **and prove** a re-stamping mechanism rather than to
test an entry's age. S0's cost measurement has been CORRECTED (S0 review finding 1; `SUBSUME-STAGE0.md` §0.2):
the first figure was a floor-sum of integer milliseconds and `:648` in fact costs 45 s of a
184 s suite run (25 %), about 12 times `checkSkolemEscape:365`. The honest reading is
unchanged and rests on this stage's THEOREM rather than on that number: **S2's brief should
not be "make `:648` cheaper"**, because making it cheaper cannot be the fix for a check that
terminates — this stage's real
deliverable for S2 is the proof that making it cheaper cannot be the fix.

**May change — nothing observable is at stake, AT `:648`.** `escs`'s elements are dead there:
`:649` reads only `nonEmpty`, the message at `:650-656` prints `e1`/`e2`, and the only line
that ever printed `escs` is commented out at `:657`. The equivalence theorems are therefore
about the *verdict*, and at `:648` the verdict is all that reaches the program.

**But the elements are LIVE at `Subst.scala:361-367`** (review Finding 4). `checkSkolemEscape`
runs the SAME `Type.fskvs` walk — `val hescs = fskvs(hm.types -- mask).filter(ss(_))` at
`:365`, over a **freshly allocated** `hm.types -- mask` — and at `:367` it **prints**
`hescs.mkString(", ")`. Nothing in this stage licenses a transformation of `:365`: a
verdict-only equivalence is not enough where the elements are printed. S0 measures `:365` at
**3.9 s** against `:648`'s **2.2 s** in the 12-property suite, with two of its five RUNNABLE
samples landing there — so `:365` is both the costlier site and the one S1a does not cover.

1. **Replace collect-and-filter by per-skolem occurrence tests.** `verdict_eq`. Hypothesis:
   `SkolemCoherent` — global id uniqueness plus "`unbind(Skolem, …)` mints skolems". Nothing
   about acyclicity.
2. **Delete `Type.fskvs`'s `_.ty == Skolem` filter at this call site.** `skolem_filter_redundant`,
   same hypothesis. **At `:648` only.** Do not delete `Type.fskvs` itself and do not carry the
   change to `checkSkolemEscape` (`Subst.scala:361-367`): `:365` runs the same walk and `:367`
   prints its elements, so a verdict-preserving rewrite is not element-preserving there.
3. **Skip environment entries that cannot mention this call's skolems.** `verdict_restrict_untouched`.
   Hypothesis: `Untouched` — a statement about the **content** of the skipped entries at the
   moment of the check. This is the only one of the three that changes the asymptotics.

   **`Untouched` is NOT discharged by insertion order, and reading it that way would turn a
   rejection into an acceptance** (review Finding 1; the earlier version of this report said
   the opposite, and was wrong). `instantiateType` (`Subst.scala:254`) is
   `hm.types = subType(Map(v -> e), hm.types) + (v -> e)`: it rewrites **every value** in
   `hm.types` on every binding, so an entry whose key and value both predate the `:614` draw
   can still come to mention a skolem drawn there. The canonical escape is exactly of this
   shape: let `a ↦ F(u)` predate the draw; `:616`'s `unifyType` binds `u ↦ G(t)` for a `t`
   minted at `:615`, rewriting `a` to `a ↦ F(G(t))`, then binds `t ↦ H(sk)` for `sk ∈ sts`,
   rewriting `a` to `a ↦ F(G(H(sk)))` and `u` to `u ↦ G(H(sk))`; `:645`'s `restrictTypes(tts)`
   deletes `t ↦ H(sk)`, and the surviving witnesses of the escape are the entries keyed by `a`
   and `u`, **both inserted before `:614`**. An implementation that stamps an entry when its
   KEY is inserted and skips "entries older than the draw" computes `escs` empty, does not
   `die`, and **accepts a program with an escaping skolem** — the one outcome this programme
   forbids.

   Age is a sound proxy only for a mechanism that **re-stamps** an entry whenever `subType`
   changes its value, or that tracks the skolem ids each entry currently contains. **Proving
   that update law is S2's obligation**, and the Lean statement says exactly what it must
   deliver: for the skipped prefix, `occE` of its type walk contains no id of `sts` and `occE`
   of its kind walk contains no id of `sks`, *as the prefix stands at the check*.

**May NOT change / must not be believed.**

4. **Do not restrict the KIND half to the entries the skolem TYPE variables occur in.**
   `kind_half_not_reducible_to_type_skolems` is a counterexample. That is the whole of the
   negative: it does **not** refute the brief's candidate `X` read so that "the types they
   occur in" includes kind-level occurrence — in `kindOnlyEnv` the skolem kind variable does
   occur in the entry's type, inside the `Con`'s kind schema — so a restriction keyed on
   kind-level occurrence remains open to S2 (review Finding 3).
5. **Do not sell short-circuiting as the fix.** `no_early_exit_on_empty`: on a run where nothing
   escapes — which includes every successful signature check — the short-circuit never fires and
   the full walk is paid. Whatever S2 measures, it must measure the *no-escape* case.
6. **Do not expect a memo table on `:648` to fix a hang.** `escs_cost_le_subPass` +
   `subst_pays_the_same`: the walk costs a constant times one substitution pass, and
   `instantiateType` runs such a pass on every binding. A memo table removes an exponential that
   the unifier is paying anyway, on the same terms, in the same shape.
7. **Do not add an occurs check at the binding site on the strength of this stage.** It would be
   harmless, but this walk is not why it would be wanted: the walk returns on cyclic input
   (`escs_total_on_cyclic`). If an occurs-check violation is reachable, S1b's rejection-path
   model is where that shows up, not here.

---

## 5. The title question, and H1/H2/H3

**Restricted to the walk at `Subst.scala:648`, the answer is YES: the check terminates.**
It is an unmemoised structural recursion over the terms the environment holds; it consults no
binding; its step count is `costV e`, a number fixed by the expression alone (`runV_steps`); and
that number is at most `4 · subPassEnv Γ + kindPassEnv Γ + 2|types| + |kinds| + 4`
(`escs_cost_le_subPass`). Termination needs no invariant, and no invariant could make it fail.

It is not *bounded* in the sense of the prompt's deliverable (2): no budget is involved, and none
is needed for this walk.

| hypothesis | verdict from this stage |
|---|---|
| **H1** — finite but explosive: `hm.types` enormous, the walk super-linear on it | **SURVIVES, in a sharpened form.** The walk is linear in the environment's *unfolded tree* size and at most a constant times one substitution pass. It is super-linear in `hm.types.size` only because each entry can be large. So "finite" is a theorem; "explosive relative to the rest of the checker" is *refuted in node visits* — it visits nodes at most a constant times as fast as the unifier already does (the bound is on node visits, not time; see §0 bullet 3) |
| **H2** — cyclic substitution makes `vars` non-terminating | **REFUTED, as a reading of the code.** `Type.scala:653` reads the variable's kind annotation, not its binding (`follow_diverges` vs. `escs_total_on_cyclic`). Part B of the prompt loses on this point, as its own rule requires. A cyclic *map* is invisible to this walk; a cyclic *heap graph* is impossible, since `Type`/`Kind` are immutable case classes built bottom-up |
| **H3** — the walk is the victim; the divergence is upstream and `:648` is only where the thread was sampled | **STRENGTHENED, and this stage's evidence points at it.** `escs_cost_le_subPass` says `:648` costs one substitution pass **in node visits** (not in time — `Vars.--`'s immutable-`Set` operations and `Vars.filter`'s `Vector` materialisation are one step each in the model, so the real ratio carries a `log |seen|` factor); `instantiateType` runs one such pass per binding. A thread that is genuinely stuck inside `:648` for 28 CPU-minutes implies an environment so large that every binding took comparably long — i.e. the cost is in the loop that built `hm`, not in the check that walks it. Sampling bias is the natural explanation for the frames, since `:648` is a long stretch of straight-line, allocation-heavy work on a thread with GC idle. **S1b's question is the live one** |

---

## 6. Open questions, and what the next stage needs from me

1. **For S0 (when it lands).** The number that discriminates H1 from H3 is
   `subPassEnv Γ` — the summed tree size of `hm.types`'s values — at the moment `:648` is
   entered, measured against the number of `instantiateType` calls that preceded it. If the walk
   is ~1/N of the total work for N bindings, the model is confirmed and `:648` is a symptom. If
   `:648` is measurably *more* than one substitution pass, my `escs_cost_le_subPass` is being
   violated by something the model omits, and the reviewer should hear about it: the most likely
   omissions are `Vars.filter`'s `Vector` materialisation (`ForeachIterable.scala:18-22`, one
   `Vector` per half, not modelled) and the immutable-`Set` operations inside `Vars.--`
   (`Vars.scala:30-31`, counted as one step here).
2. **For S1b.** This stage hands you a negative you can use: the escape check is not a divergence
   source, so a rejection path that does not terminate does not terminate *before* `:648`.
   `follow_diverges` also gives you the shape of an occurs-check violation, should you find one
   reachable — but note that such a violation would *not* manifest here.
3. **For S2.** Items 1–3 of §4 are licensed; items 4–7 are forbidden or futile — and after
   review Finding 1 item 3 is the only one of the three with any asymptotic content, so, and — notwithstanding S0's
CORRECTED measurement that `:648` is 25 % of a suite run, not ~1 % (`SUBSUME-STAGE0.md` §0.2) —
**"make `:648` cheaper" is still not a brief this stage supports**, because it is a performance
item and not a fix. The one hypothesis you must discharge in Scala, `Untouched`, is
   about the CONTENT of the entries you skip; discharging it needs a re-stamping law
   (`instantiateType` rewrites every value on every binding) and that law needs its own proof.
   Note also that `checkSkolemEscape` (`Subst.scala:361-367`) — the costlier site by S0's
   measurement — is **not** covered by any theorem here, because `:367` prints the elements.
4. **Not proved, and I would not claim it.** That the Scala's `escs` value is observed only
   through `nonEmpty` is a reading of `:649-658`, not a theorem — and it is a reading of `:648`
   ONLY: at `checkSkolemEscape` `:365-367` the same walk's elements are printed; that `Type.subst`'s recursion
   visits exactly the nodes `subPass` counts is a reading of
   `Type.scala:215-250, 263, 333, 387, 441, 566`; that `sks`/`sts` are fresh for `hm` at `:614`
   is a reading of `refreshList`/`Supply`. All three are recorded as "stated on paper" in the
   README entry. A reviewer who disputes any of them disputes a citation, not a proof.
5. **Deliberately out of scope.** The cost of `Vars.filter`'s materialisation and of the
   immutable-`Set` operations in `--` (both constant-per-node in the model, both real in the
   JVM); `hm.remembered`, `binderTypes`, `headTypes`, which `:648` does not read; and the LSP
   dispatch-thread question, which the prompt tickets out.

---

## 7. Review fixes (2026-09-16, after `SUBSUME-STAGE1A-REVIEW.md`, verdict FIX-THEN-LAND)

**No Lean statement was changed.** Every edit below is to a doc comment, a README row, or this
report. The reviewer's own re-run reproduced every number in §1 exactly and found the model a
faithful transcription on every point checked independently; the four findings are corrections
to prose that the S2 implementer would read as a licence.

### Finding 1 (MUST FIX) — the `Untouched` discharge was FALSE as written

The report claimed `Untouched` is discharged by the fresh skolem draw at `Subst.scala:614`
("no entry the environment held before that draw can mention them") and proposed a *generation
stamp* as the S2 mechanism. Both are wrong: `instantiateType` (`Subst.scala:254`) is
`hm.types = subType(Map(v -> e), hm.types) + (v -> e)` — it rewrites **every value** in
`hm.types` on every binding, so an entry whose key and value both predate `:614` can come to
mention a skolem drawn there. The reviewer's scenario is the canonical escape, and an
age-stamping implementation would compute `escs` empty and **accept an escaping skolem** — the
one outcome this programme forbids. The theorem is correct and unchanged (`Untouched` is a
hypothesis about the **content** of the skipped entries); only the discharge and the proposed
mechanism were wrong. Fixed in all six places, with the failure scenario and the re-stamp law
named as S2's obligation:

| file | where |
|---|---|
| `tracker/lean/Rowpartition/SubsumeEscape.lean` | §7 sub-header "The untouched-entry licence" (rewritten, with the scenario) |
| `tracker/lean/Rowpartition/SubsumeEscape.lean` | `escs_restrict_untouched` docstring |
| `tracker/lean/Rowpartition/SubsumeEscape.lean` | `verdict_restrict_untouched` docstring |
| `tracker/lean/Rowpartition.lean` | root doc entry, the `escs_restrict_untouched` clause |
| `tracker/lean/README.md` | the `escs_restrict_untouched` table row |
| `tracker/satterm/SUBSUME-STAGE1A.md` | §3.6 (the invariant block), §3.6's `verdict_restrict_untouched` row, §4 item 3 (rewritten, scenario in full, "generation stamp" removed), §6 item 3 |

### Finding 2 (QUALIFY) — `escs_cost_le_subPass` bounds NODE VISITS, not time

`costV` charges one step per `VarsE` node, but a `minus` node runs immutable-`Set` operations
over a seen set that grows with the distinct variables (`Vars.scala:28-32`) and
`Vars.filter`/`nonEmpty` materialise a `Vector` per half (`ForeachIterable.scala:17-21`),
against a singleton-map lookup per node in `Type.subst`; the real ratio carries a `log |seen|`
factor. The report disclosed this in §6 only, not in the places a downstream agent quotes.
Qualified, with the two omissions named in the same sentence, in: **§0 bullet 3**, **§5's H1
and H3 rows**, `tracker/lean/README.md`'s `escs_cost_le_subPass` row,
`tracker/lean/Rowpartition.lean`'s cost clause, and `SubsumeEscape.lean`'s module-header §5
bullet (which also had two wrong theorem names, `kvars_cost_le_subPass` /
`tvars_cost_le_subPass`, now `kvars_cost_le` / `tvars_cost_le`).

### Finding 3 (NARROW) — the kind-half negative was stated more broadly than the witness supports

`kindOnlyEnv`'s skolem kind variable **does** occur in the entry's type, inside the `Con`'s kind
schema, so the witness does not refute the brief's candidate `X` read with kind-level
occurrence; it refutes only the narrower *"the kind half cannot be restricted to the entries the
skolem TYPE variables occur in"*. §4 item 4's wording adopted verbatim, and the non-refutation
made explicit, in: `SubsumeEscape.lean`'s §7 "One restriction that is NOT available" sub-header,
`tracker/lean/README.md`'s `kind_half_not_reducible_to_type_skolems` row, this report's §3.6
last row and §4 item 4. **The theorem name was already precise and is unchanged.**

### Finding 4 (ADD) — `escs`'s elements are dead at `:648` but LIVE at `Subst.scala:365-367`

`checkSkolemEscape` (`Subst.scala:361-367`) runs the SAME `Type.fskvs` walk —
`val hescs = fskvs(hm.types -- mask).filter(ss(_))` at `:365`, over a freshly allocated
`hm.types -- mask` — and **prints** `hescs.mkString(", ")` at `:367`. The verdict-only argument
therefore does not cover `:365`, which S0 measures as the costlier site (**3.9 s** against
`:648`'s **2.2 s** in the 12-property suite, with two of five RUNNABLE samples there). Added,
naming the site and the extra map allocation, to: §4's opening, §4 item 2, §6 item 4,
`tracker/lean/README.md`'s "stated on paper" item (i), `tracker/lean/Rowpartition.lean`'s root
doc entry, and `SubsumeEscape.lean`'s module header (a new "Where the verdict-only argument does
NOT apply" paragraph).

### Also required: the plain conclusion

Stated at the head of §4: **after Finding 1, S1a licenses no asymptotic improvement to `:648`
at all.** `verdict_eq` and `skolem_filter_redundant` are verdict-preserving tidying (`verdictR`
still walks the whole environment); `no_early_exit_on_empty` proves the short-circuit never
fires on a no-escape run, which is every successful signature check; and
`verdict_restrict_untouched`, the only asymptotic licence, now requires S2 to build **and
prove** a re-stamping mechanism. S0's measurement has been corrected to 25 % of a suite run (§0.2 there), which
strengthens the PERFORMANCE case and changes nothing here: S2's brief should still not be
"make `:648` cheaper" — this stage's deliverable for S2 is the proof that
making it cheaper cannot be the fix. Repeated in §6 item 3.

### Post-fix build and audit

Doc-comment edits force `Rowpartition.SubsumeEscape` and the root to rebuild; both were re-run.

```
$ export PATH=$HOME/.elan/bin:$PATH; cd tracker/lean
$ lake env lean Rowpartition/SubsumeEscape.lean
(exit 0, no output)
$ lake build
Build completed successfully (872 jobs).                      # 4.9 s — unchanged
$ lake env lean Audit.lean
Rowpartition theorems audited: 4936; declarations using a non-standard axiom: 0   # unchanged
$ lake env lean <scratch>/axioms.lean          # all 55 named theorems
   7  [propext] / 36  [propext, Quot.sound] / 12  [propext, Classical.choice, Quot.sound]
0 non-standard, no sorryAx                                    # unchanged
```

Logs: `/home/dmitry/research/ermine/scratch-subsume/s1a/build-postreview.log`,
`audit-postreview.log`, `axioms-postreview.txt`. Nothing committed.
