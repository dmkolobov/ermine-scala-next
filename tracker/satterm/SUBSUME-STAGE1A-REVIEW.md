# SUBSUME-STAGE1A-REVIEW — Opus reviewer, stage S1a (the substitution model, Lean)

Reviewer: a different Opus agent from the implementer. Brief: `tracker/satterm/briefs/brief-review.md`.
Stage worktree `~/research/ermine/ermine-scala-wt-subsume-s1a`, branch `subsume-s1a`, UNCOMMITTED.
Reviewer scratch and every log path below: `/home/dmitry/research/ermine/scratch-subsume/review-s1a/`.
Nothing was committed; the worktree was left byte-identical to how it was found (see §5).

---

## VERDICT: **FIX-THEN-LAND**

The Lean is sound, builds, audits clean, is demonstrably non-vacuous, and is a faithful
transcription of the Scala on every point I checked independently. **No theorem was weakened
and no theorem needs re-proving.** All four findings are corrections to PROSE that the S2
implementer will read as a licence — one of them (Finding 1) would, if implemented as written,
turn a rejection into an acceptance, which is the single outcome this programme forbids.

Re-check after the fixes: re-read the corrected prose plus one `lake build` + `lake env lean
Audit.lean` (editing a doc comment inside `SubsumeEscape.lean` forces its module to rebuild).
No re-proof, no new theorem.

---

## 1. Re-run numbers (all mine, not cited)

| what | command | result | log |
|---|---|---|---|
| build | `lake build` (in `tracker/lean`) | `Build completed successfully (872 jobs).` 0.8 s (no-op) | `lake-build.log` |
| build, module removed | import commented out, `lake build` | `Build completed successfully (871 jobs).` | `baseline.log:21119` |
| audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 4936; declarations using a non-standard axiom: 0` | `audit.log` |
| audit, module removed | same | `Rowpartition theorems audited: 4676; … non-standard axiom: 0` | `baseline.log:21121` |
| audit, restored | same | `4936; … 0` (and `Rowpartition.lean` md5 back to `f18b184e…`) | `baseline.log:42678` |

The baseline pair matters for more than the +260 arithmetic: it proves `Audit.lean` actually
*sees* the new module (the count moves by exactly its contribution), so "0 non-standard" is not
vacuous for these declarations. Every number in the report's §1 reproduced exactly.

**`#print axioms`, all 55 named theorems** (`axioms-thms.lean` → `axioms-out.txt`, 55 lines):

```
  36  [propext, Quot.sound]
  12  [propext, Classical.choice, Quot.sound]
   7  [propext]
```

0 non-standard, no `sorryAx`. Identical to the report's distribution. I also ran `#print axioms`
over all **56** `def`/`inductive`/`structure` declarations (`axioms-defs.lean`): every one is
"does not depend on any axioms" or a subset of the same three. `grep -nE
'#eval|sorry|partial|unsafe|native_decide|^axiom |admit'` over the file: no hits (the single
`admit` hit is the English word inside a doc comment at :43). Every witness is `decide`
(kernel-checked): `many_can_duplicate`, `escs_total_on_cyclic`, `verdict_total_on_cyclic`,
`escs_cyclic_other`, `kind_half_not_reducible_to_type_skolems`, `kindOnly_verdictR`.
**There is no `#eval` in the shipped file and no "terminates" claim rests on one.**

**Vacuity — four mutations, all four fail the build, all four reverted:**

| # | mutation | result | log |
|---|---|---|---|
| 1 | `escs1_iff`'s `(h : SkolemCoherent Γ sts)` → `(h : True)` | 4 errors ("Function expected at `h`", unsolved goals) | `mut1.log` |
| 2 | `escs_total_on_cyclic … = [1]` → `= [2]` | `Tactic 'decide' proved that the proposition … is false` | `mut2.log` |
| 3 | drop the `Con` case of `kvarsT` (`.con ks => kvarsKS ks` → `.con _ => .nil`) | `kind_half_not_reducible_to_type_skolems` AND `kindOnly_verdictR` both become false under `decide` | `mut3.log` |
| 4 | drop the kind conjunct of `Untouched` | `escs_restrict_untouched` fails (invalid projection `h.2`) | `mut4.log` |

Mutation 3 is the interesting one: it shows the kind-half counterexample is genuinely carried by
the `Con` → `KindSchema` case, i.e. the witness is not an artefact of the encoding.

---

## 2. Faithfulness of the model to the Scala — the first thing to judge

I re-read `Type.scala:640-720`, `Kind.scala:1-145`, `KindSchema.scala`, `Vars.scala`,
`ForeachIterable.scala`, `Subst.scala:85-180, :180-270, :355-368, :595-700` and checked the model
case by case. Everything below I verified myself; none of it is cited from the report.

- **`v.extract` is the kind annotation and no binding is followed — CONFIRMED.** `VarT(v: TypeVar)`
  (`Type.scala:238`), `TypeVar = V[Kind]` (`ermine.scala:18`), `V.extract: A` (`Vars.scala:100`),
  `Kind.scala:65` `VarK(v).vars = Vars(v)` emits and stops. Neither `vars` recursion reads
  `hm.types`/`hm.kinds`. H2's premise is false about the code, and the report's pair
  (`follow_diverges` vs. `escs_total_on_cyclic`) is the right way to show it: the hypothesis is
  refuted by exhibiting the function it describes and showing the shipped one is not it.
  Independently corroborated by S0 §2.1 and its `IdentityHashMap` back-edge instrumentation
  (0 cycles in ~548,000 marked walks).
- **`Vars.apply` / `++` / `--` — CONFIRMED.** `.app x y` running left-then-right is right:
  `Vars.scala:22-24` is `w(that(s,f), f)` with `that` the LEFT operand, so the left runs first and
  threads its seen set into the right. `.minus`'s `(runV x (s ++ t)).2.filter(∉t) ++ t.filter(∈s)`
  is `Vars.scala:30-31` term for term. `.many` not updating its own seen set inside the loop is
  `Vars.scala:59-63`, and `many_can_duplicate` is a fair refutation of the class docstring at
  `:8-12` — a genuine (harmless here) defect found by the model, which is the sort of thing this
  method is for.
- **`SubstEnv.kindVars`'s `++` at `Subst.scala:169` resolves to `Vars.++`, not `Iterable.++`.**
  Both are applicable (`Traversable` is the 2.13 alias for `Iterable`); `Vars[J]` is the more
  specific parameter type, so overload resolution picks `Vars.++` and the model's seen-set
  threading across `kinds` and `types` is correct. (It would not have mattered for the verdict —
  threading only suppresses duplicates — but the model is right either way.)
- **Both `Map` instances fold over VALUES only** (`Kind.scala:124-126`, `Type.scala:770-772`); the
  model's `kvarsKinds`/`kvarsTypes`/`tvarsTypes` do the same. The map's KEYS are never walked, so
  a skolem that appeared only as a key would be invisible — which is harmless, because keys are
  bound metas and skolems are never bound.
- **All ten `Type` constructors are covered.** `ConcreteRho` (:141) and `ProductT` (:160) are the
  two the Scala sends to `Vars()`, and `opaqueT` stands for exactly them; `Arrow` (:177),
  `AppT` (:213), `VarT` (:238), `Exists` (:259), `Forall` (:326), `Part` (:385), `Memory` (:435),
  `Con` (:556) each have their own case with the right shape. `Forall`'s deliberate exclusion of
  `q` (`Type.scala:654`) is modelled (`allT`'s `_q` is unused by `kvarsT`).
- **`escs` is observed only through `nonEmpty` at `:648-658` — CONFIRMED.** `:650-656` prints
  `e1`/`e2`; `:657`, the one line that printed `escs`, is commented out; `:658` returns without
  touching it. The report's central "nothing observable may change" rests on this and the reading
  is correct. (But see Finding 4: it is correct at `:648` and FALSE at `:365-367`.)
- **`instantiateType` runs a whole-map substitution pass per binding — CONFIRMED at
  `Subst.scala:254`**, `hm.types = subType(Map(v -> e), hm.types) + (v -> e)`; `subType`'s
  empty-map fast path (`Type.scala:670`) does not fire on a singleton, and `mapHasTypeVars.sub`
  rewrites every value. `:255` adds two more passes over `hm.remembered`. So the report's cost
  comparison is against a real per-binding cost, and if anything understates it.
- **`subPass`'s per-constructor counts.** `AppT.subst` (`:227-230`) recurses into both children
  unconditionally (`this` is returned only after both recursions), so the node count is the full
  tree — right. `VarT.subst` (`:241-250`) runs `subKind(ks, v.extract)` even under an empty kind
  map (`Kind.subKind` has no empty-map fast path, deliberately — `Kind.scala:96-98`), so
  `subPass (.var v) = 1 + treeK v.kind` is right. `Con.subst` (`:567`) walks the schema body;
  `+ ks.forallK.length` over-counts, which only loosens a `≤` bound. No under-count found.

**Conclusion on faithfulness: the model is an honest transcription.** The only omissions are
disclosed in the report's §6.1/§6.5 and they are cost-model omissions, not semantic ones
(Finding 2).

---

## 3. Theorem statements against the brief's wording — nothing weakened

The brief offered two routes and pre-authorised the pivot: *"If no binding is followed … the
theorem to prove is the COST bound … plus the equivalence of the restricted walk; say so and
prove that instead."* The stage took that route and delivered **more** than the first bullet
asked for, not less:

- **Termination**: unconditional, with NO invariant (`runV_steps` + the fact that `runV`, `kvarsT`
  and `tvarsT` are structural recursions Lean accepts). The brief asked for termination *under an
  invariant*; a theorem with no hypothesis is strictly stronger. Not weakened.
- **Cost**: `kvars_cost_le`, `tvars_cost_le`, `escs_cost_le_subPass` — the tree-size bound the
  brief named, universally quantified over `Ty` / `Env`, no side conditions.
- **Sharing witness**: `walk_exp_in_dag` gives the brief's "family of size n whose walk cost is
  exponential in n", with the cost function (`costV`) stated and the bound proved (`2^(n+1) - 1`
  against a DAG of `4n+1` nodes) — and `subst_pays_the_same` is the matching negative, which the
  brief did not ask for and which is the most useful thing in the file for S2.
- **Equivalence**: `verdict_eq` is universally quantified over `Γ`, `sks`, `sts` with the single
  hypothesis `SkolemCoherent`. No quantifier is narrowed.

**Is `SkolemCoherent` the right side condition, and does the solver keep it? YES to both.**
It is needed for exactly one thing: `escs`'s type half goes through `Type.fskvs`, which filters
`_.ty == Skolem` (`Type.scala:666`), so the equivalence needs "anything in the environment
carrying one of `sts`'s ids really is a Skolem". `sts` come from `unbind(Skolem, e1)` at `:614`,
i.e. `refreshList(Skolem, …)` at `:687-689`, so they carry `ty = Skolem`; `V` ids are globally
unique (`Vars.scala:91-99`) and every copy route preserves `ty` (`V.at`/`V.map`/`V.extend`,
`Vars.scala:102-104`). I searched for a route that changes a `V`'s `ty` while keeping its id and
found none: every `Ambiguous(…)` site (`Subst.scala:577, :671, :1779`, `Constraints.scala:829`
etc.) goes through `refreshList`/`fresh` and draws a FRESH id. `skolemCoherent_of_unique` is the
right shape for that argument. Two notes, neither a defect:

- The hypothesis quantifies over `occE`, which includes `--`-bound occurrences — strictly stronger
  than `fvE` needs, and still discharged by global id uniqueness. Conservative in the safe
  direction.
- The model folds `Ambiguous(t)` into `free` (`SubsumeEscape.lean:100-103`). That is also the safe
  direction: a hypothetical `V` with `ty = Ambiguous(Skolem)` fails `_.ty == Skolem` in Scala and
  is `free` in the model, so the model does not paper the case over — and it cannot arise for
  `sts` anyway.

---

## 4. Findings

### Finding 1 — the `Untouched` discharge is FALSE as written, and the mechanism the report suggests would turn a rejection into an acceptance. **(must fix)**

*Where.* `tracker/lean/Rowpartition/SubsumeEscape.lean:1017-1018` (§7 sub-header prose),
`:1064-1065` (`escs_restrict_untouched` docstring), `:1127-1129` (`verdict_restrict_untouched`
docstring); `tracker/lean/README.md:1315`; `tracker/lean/Rowpartition.lean:294`;
`tracker/satterm/SUBSUME-STAGE1A.md:242`, `:256`, `:276`.

*The claim.* "The skolems are drawn FRESH at `Subst.scala:614`, so **no entry the environment held
before that draw can mention them**" / "every entry older than the fresh draw at `:614` is such an
entry", and — in the report's §4 item 3 — that the mechanism S2 needs is "a **generation stamp**,
or an index of which skolem ids the environment currently contains".

*Why it is false.* `instantiateType` (`Subst.scala:254`) does not merely ADD an entry; it rewrites
**every value in `hm.types` in place**: `hm.types = subType(Map(v -> e), hm.types) + (v -> e)`.
An entry whose key AND value both predate `:614` therefore acquires whatever later bindings
substitute into it — skolems included. Age of the key is not a proxy for the CONTENT of the value.

*Failure scenario, and it is the canonical escape rather than an exotic one.* Let `u` be a free
meta from an enclosing scope and let `a ↦ F(u)` be an entry present in `hm.types` before `:614`.
At `:616` `unifyType` binds `u ↦ G(t)` for some `t ∈ tts` minted at `:615` (rewriting `a` to
`a ↦ F(G(t))`), and then binds `t ↦ H(sk)` for `sk ∈ sts` (rewriting `a` to `a ↦ F(G(H(sk)))`
and `u` to `u ↦ G(H(sk))`). `:645` `restrictTypes(tts)` deletes `t ↦ H(sk)`. At `:648` the
surviving witnesses of the escape are the entries keyed by `a` and `u` — **both keys inserted
before `:614`**. An S2 implementation that stamps an entry when its KEY is first inserted and
skips "entries older than the draw" computes `escs` empty, does not `die`, and **accepts a program
with an escaping skolem**. That is precisely the outcome the prompt's gate policy forbids
("a rejection that becomes an acceptance … is the one thing this work must not do").

*Fix (prose only; the theorem is correct and needs no change).* `Untouched` is a hypothesis about
the **content of `old` at the moment of the check**, not about its age. In all six places, replace
the age claim with: *"`Untouched` is not discharged by insertion order. `instantiateType`
(`Subst.scala:254`) rewrites every value in `hm.types` on every binding, so an entry older than the
draw can still mention a skolem drawn at `:614`. Age is a sound proxy only for a mechanism that
RE-STAMPS an entry whenever `subType` changes its value (or that tracks the skolem ids each entry
currently contains); proving that update law is S2's obligation, and the Lean statement says
exactly what it must deliver."* In the report's §4 item 3, drop the bare words "a generation
stamp" or qualify them with the re-stamp law in the same sentence.

### Finding 2 — the "constant factor of one substitution pass" headline is a bound on NODE VISITS, not on time. **(qualify)**

*Where.* `tracker/satterm/SUBSUME-STAGE1A.md` §0 bullet 3 ("the cost is exactly one substitution
pass, up to a constant of 4") and §5's H3 row ("it explodes exactly as fast as the unifier already
does"); `tracker/lean/README.md:1311` (the `escs_cost_le_subPass` row);
`tracker/lean/Rowpartition.lean:288-291`.

*Why.* `costV` (`SubsumeEscape.lean:558-565`) charges ONE step per `VarsE` node, `minus` included.
In the JVM a `minus` node runs `s ++ t`, `… -- t` and `t intersect s` over an immutable `Set`
whose size grows with the number of distinct variables seen so far (`Vars.scala:28-32`); a `one`
node runs `s(v)` and `s + v` (`Vars.scala:54-58`); and `Vars.filter`/`nonEmpty` go through
`ForeachIterable.iterator` (`ForeachIterable.scala:17-21`), materialising a `Vector` per half.
`Type.subst`'s per-node cost is a singleton-map lookup. So the real ratio carries a `log |seen|`
factor and, at `minus` nodes, a `|binders| · log |seen|` one. The report DOES disclose this in
§6.1 and §6.5 — but §0 and the H3 row, which are what a downstream agent will quote, do not.

*Failure scenario.* S0 or S2 reads "a constant factor of ONE unification step", concludes `:648`
cannot be a hot spot, and stops instrumenting it — when a bound on node visits does not by itself
forbid `:648` being several times more expensive per node than the substitution passes it is
compared with. (S0's independent measurement has since been CORRECTED — `:648` is 45 s of a 184 s
suite, 25 %, not 2.2 s (`SUBSUME-STAGE0.md` §0.2) — which makes this wording fix MORE
important, not less: a bound on node visits must not be read as a bound on time.)

*Fix.* In §0 bullet 3, the H3 row, and the README row, say "node visits, not time" and name the two
omissions (`Vars.--`'s immutable-`Set` operations; `Vars.filter`'s `Vector` materialisation) in the
same sentence rather than only in §6.

### Finding 3 — "the brief's candidate `X` is unsound for the KIND half" is stated more broadly than the witness supports. **(qualify)**

*Where.* `tracker/lean/Rowpartition/SubsumeEscape.lean:1137-1141`; `tracker/lean/README.md:1319`;
`tracker/satterm/SUBSUME-STAGE1A.md` §0 and §3.6's last row.

*Why.* The witness `kindOnlyEnv` (`:1150`) is `wTV ↦ con ⟨[], varK uKV⟩` — the skolem KIND variable
`uKV` **does** occur in that entry's type, inside the `Con`'s kind schema. So under the reading
where "the types they occur in" includes kind-level occurrence, the entry IS in the brief's `X` and
the witness does not refute `X`. What it actually refutes is the narrower statement the report's §4
item 4 gets right: *the kind half cannot be restricted to the entries the skolem TYPE variables
occur in.*

*Failure scenario.* S2 reads the broad wording and abandons a kind-half restriction that is in fact
open to it (one keyed on kind-level occurrence), or — worse — treats the negative as covering more
ground than it does when arguing a fix is unavailable.

*Fix.* Use §4 item 4's wording verbatim in the Lean `§7` sub-header and the README row; rename
nothing (the theorem name `kind_half_not_reducible_to_type_skolems` is already precise, and it is
the prose that overreaches).

### Finding 4 — `escs`'s elements are dead at `:648` but LIVE at `Subst.scala:365-367`; S2 must be told. **(add)**

*Where.* `tracker/satterm/SUBSUME-STAGE1A.md` §4's opening paragraph and §4 item 2's parenthetical;
`tracker/lean/README.md`'s "stated on paper" list, item (i).

*Why.* `checkSkolemEscape` (`Subst.scala:361-367`) runs the SAME `Type.fskvs` walk —
`val hescs = fskvs(hm.types -- mask).filter(ss(_))` at `:365` — and at `:367` it **prints**
`hescs.mkString(", ")`. The report's "the elements are dead, the verdict is all that reaches the
program" is true of `:648` and false of `:365`. The only warning in the report is item 2's
parenthetical "other callers are not covered", which does not name the site. S0's CORRECTED measurements make
this urgent rather than pedantic: in the 12-property suite `:365` costs **3.7 s** against `:648`'s
**45 s** — the ordering is the OPPOSITE of the figure this review was given
(`SUBSUME-STAGE0.md` §0.2) — and two of the six RUNNABLE stack samples land there — so `:365` is the site S2 will be
most tempted to transform, and it is the one where a verdict-only equivalence is not enough.

*Fix.* Name `Subst.scala:361-367` explicitly in §4 (both in the opening "elements are dead" sentence
and in item 2) as the site where the verdict-only argument does NOT apply, and note that `:365` also
allocates a whole new map (`hm.types -- mask`) before walking it.

---

## 5. Worktree left as found

`git status --short` at the end is identical to the start:

```
 M tracker/lean/README.md
 M tracker/lean/Rowpartition.lean
 M tracker/satterm/SUBSUME-STAGE1A.md
?? tracker/lean/Rowpartition/SubsumeEscape.lean
```

plus this review file. `md5sum` after all four mutations and the baseline experiment:
`SubsumeEscape.lean` = `a5057532b091c1232e87520bee365637` (unchanged), `Rowpartition.lean` =
`f18b184ec2f87d43f2745a4a9ec58fe7` (unchanged), and the final `lake build` / `Audit.lean` in the
restored tree give 872 jobs / 4936 theorems / 0 non-standard. No commits, no `nohup`; the two long
jobs ran as harness-tracked background commands with logs under the reviewer scratch dir.

---

## 6. The answer I would sign, for the walk

**Restricted to the walk at `Subst.scala:648`: YES — it terminates, and the answer needs no
budget and no invariant.** The walk is a structural recursion over the terms `hm.types`/`hm.kinds`
already hold; it consults no binding; its step count is `costV e`, a number fixed by the expression
alone (`runV_steps`), bounded by `4·subPassEnv Γ + kindPassEnv Γ + 2|types| + |kinds| + 4`
(`escs_cost_le_subPass`). There is no hypothesis under which it could fail to return, so the
"acyclic substitution" invariant the brief asked to be stated is vacuous here — and the residual
risk, a cyclic term GRAPH, is closed by `Type`/`Kind`/`V` being strict case classes with no by-name
or mutable structural field (a reading, correctly declared as such by the report, and independently
measured by S0 as 0 back-edges in ~548,000 marked walks).

**Not bounded, not no.** H2 is refuted as a reading of the code — the prompt's Part B loses on this
point, as its own rule requires, and the stage refutes it in the right way (by exhibiting H2's
function, `follow_diverges`, and showing the shipped one returns on the same input,
`escs_total_on_cyclic`). H1 survives only in the sharpened form "linear in the environment's
unfolded tree size, super-linear in `hm.types.size` only because entries can be large". **H3 is the
live hypothesis**, and this stage's contribution to it is a proof, not a guess: `:648` costs a
small multiple of one `instantiateType` pass, and `instantiateType` runs such a pass on every
binding. S0's independent measurement agrees (`:648` = 2.2 s of a 184 s suite; the property that
does not return is ScalaCheck running the whole check 100 times, not one check failing to return).

**One thing the report should say more plainly, and the orchestrator should carry into S2's brief.**
After Finding 1, S1a licenses **no asymptotic improvement to `:648` at all**:
`verdict_eq` and `skolem_filter_redundant` are verdict-preserving tidying (`verdictR` still walks
the whole environment — `occursTV` is `memN n (fvId … (envTypeVars Γ))` — and
`no_early_exit_on_empty` proves the short-circuit never fires on a no-escape run, which is every
successful signature check), and `verdict_restrict_untouched` is the only asymptotic licence but now
requires S2 to build and PROVE a re-stamping mechanism rather than to test an entry's age. Combined
with S0's measurement that `:648` is ~1 % of the hang, the honest reading is that **S2's brief should
not be "make `:648` cheaper"** — this stage's real deliverable for S2 is the proof that making it
cheaper cannot be the fix.

---

## 7. Re-check — 2026-09-16, after the implementer's fixes

Scope: ONLY the four findings of §4. I re-read the report's new §7 "Review fixes", the corrected
passages in `SUBSUME-STAGE1A.md` (§0 bullet 3, §3.6, §4 in full, §5's H1/H3 rows, §6 items 1/3/4),
the two README rows plus the "stated on paper" block, the `Rowpartition.lean` root entry, and the
`SubsumeEscape.lean` module header and docstrings.

### VERDICT: **LAND**

All four findings are addressed, in every location named, and the corrections are accurate. Two
residual nits below, neither blocking and neither touching the audited artifact.

### No theorem statement was touched — verified mechanically

`SubsumeEscape.lean` is untracked, so `git diff` does not show it; I diffed it against the copy I
took before the review (`scratch-subsume/review-s1a/SubsumeEscape.lean.orig`). Then I stripped all
Lean block comments (`/- … -/`, `/-! … -/`, `/-- … -/`) and line comments from both versions and
diffed the remainder:

```
code lines: pre=756  post=756
NON-COMMENT DIFF LINES: 0
```

Every one of the ~90 changed lines is inside a doc comment. `git diff --stat` on the tracked files
touches only `README.md` (+73), `Rowpartition.lean` (+38) and the two `.md` reports. The two
renamed names in the module header (`kvars_cost_le_subPass` → `kvars_cost_le`,
`tvars_cost_le_subPass` → `tvars_cost_le`) are inside that doc comment and are a real improvement:
the old names never existed as declarations, so the header had been citing two dangling references.
Both new names resolve (`:662`, `:703`).

### Re-run (minimal, per the scope)

- `lake build` → `Build completed successfully (872 jobs).` — green after the doc edits (which do
  force the module and the root to re-elaborate).
- `lake env lean Rowpartition/SubsumeEscape.lean` → exit 0, **no output**: no new warnings, and no
  line over 100 characters was introduced.
- **Full audit deliberately not re-run** (the diff shows no non-comment change, per the coordinator's
  instruction). I did check the implementer's evidence rather than take it: `audit-postreview.log`
  reads `Rowpartition theorems audited: 4936; declarations using a non-standard axiom: 0`, and
  `axioms-postreview.txt` is 55 lines that are **byte-identical, after sorting, to my own pre-fix
  `#print axioms` run** (36 `[propext, Quot.sound]`, 12 `[propext, Classical.choice, Quot.sound]`,
  7 `[propext]`). Nothing moved.

### Finding by finding

1. **`Untouched` discharge — FIXED, and fixed well.** All six places carry the correction, and four
   of them carry the failure scenario in full (`a ↦ F(u)` → `u ↦ G(t)` → `t ↦ H(sk)` →
   `restrictTypes(tts)` deletes the introducing entry) rather than a bare warning. "Generation stamp"
   is gone from §4 item 3; the re-stamp law is named as S2's proof obligation in the Lean §7 header,
   both theorem docstrings, the README row, the root entry and §3.6/§4/§6. The `Untouched` definition
   and both theorems are unchanged.
2. **Cost bound qualified — FIXED.** "NODE VISITS, not time" now appears in §0 bullet 3, the H1 and
   H3 rows, the README `escs_cost_le_subPass` row, the root entry's cost clause and the module
   header's §5 bullet, each naming `Vars.--`'s immutable-`Set` operations and `Vars.filter`'s
   `Vector` materialisation in the same sentence.
3. **Kind-half negative narrowed — FIXED.** §4 item 4's wording is adopted verbatim in the Lean §7
   sub-header, the README row and §3.6's last row, and each says explicitly that a restriction keyed
   on kind-level occurrence stays open to S2. The theorem name was already precise and is unchanged.
4. **`Subst.scala:361-367` — ADDED.** Named, with the `hm.types -- mask` allocation and the `:367`
   print, in §4's opening, §4 item 2, §6 item 4, the README's `verdict_iff`/`verdict_eq` row and
   "stated on paper" item (i), the root entry, and a new module-header paragraph "Where the
   verdict-only argument does NOT apply".

Also carried, as asked: the plain conclusion at the head of §4 and repeated in §6 item 3 — after
Finding 1, **S1a licenses no asymptotic improvement to `:648` at all**, and "make `:648` cheaper" is
not a brief this stage supports.

### Residual (non-blocking; fix in passing whenever the report is next touched)

1. **The word "freshness" survives in two summary positions, where Finding 1 says it is wrong.**
   `SUBSUME-STAGE1A.md` §0 bullet 2 still describes `Untouched` as an invariant "about FRESHNESS",
   and §3.6's quoted Lean block prefixes the definition with `/-- Freshness: entries that cannot
   mention this call's skolems. -/` — a docstring that does **not** exist in the file
   (`SubsumeEscape.lean:1057` has none), so it is an editorial gloss that contradicts the corrected
   paragraph two lines below it. Both are report-only; the audited artifact is clean. Replace with
   "CONTENT" / drop the invented docstring.
2. **§0's last bullet** still reads "the equivalence S2 needs is proved … and what may change is
   nothing observable" without the `at :648` qualifier that §4, the README and the root entry now
   all carry (Finding 4). One clause.

Neither residual can mislead an S2 implementer who reads §4 — which every downstream reader is
pointed at — so they do not hold the stage. **LAND.**
