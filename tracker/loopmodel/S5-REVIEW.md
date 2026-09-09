# S5 review — the tautology deletion (C12, now DEFAULT ON) and the `.ei` solver-configuration key

Independent review of stage S5.  Brief `tracker/loopmodel/briefs/brief-S5-review.md`; implementer's
report `tracker/loopmodel/S5-HYGIENE.md` (§0-§4 plus `## Follow-up: publishing-only deletion`,
which supersedes §0/§4's verdict).  Tree: branch `scala3-migration`, HEAD `5951e73`, plus the
UNCOMMITTED S5 deliverables.  Nothing outside this file and the reviewer's scratch
(`/home/dmitry/.claude/jobs/880c725d/tmp/review-S5/`) was touched; no commits.

**VERDICT: FIX-THEN-ADVANCE.**  The theorem is right, the deletion implements it and nothing wider,
the sweep reproduces to the binding, the key works end to end, and every gate is green including
`core/test` 940/940 and the two row traces byte-identical to a pre-change compiler.  Three things
must be fixed before the commit — one behavioural (**Q-1**: the LSP editor path lost the deletion,
so hover and the compiler now disagree about the same binding, measured through the LSP) and two
that would otherwise be committed as the permanent record of an adoption (**Q-2**: the
`deleteTautologies` scaladoc still says DEFAULT OFF and still carries the caveat the `publishing`
restriction removed; **Q-3**: a necessity witness in `Determined.lean` is attributed to a theorem
that does not support it, and I supply the two that do).  Everything else is prose or tooling.
The fix list is §6.

---

## Findings

Ranked; CONFIRMED means I ran it on this tree.  **None of them is a soundness defect, and no gate
this stage is responsible for is red.**  One gate outside the tiers IS red and has been since F3
(Q-15).

| # | rank | status | finding |
|---|---|---|---|
| **Q-1** | medium | CONFIRMED, **measured through the LSP** | **The editor path lost the deletion, so hover and the compiler now disagree about the same binding.**  `TolerantCheck.checkWith` calls `Subst.inferImplicitBindingTypes` directly (`TolerantCheck.scala:267`) and gets `publishing = false` by default — but `is = m.implicits` there, so the components it passes ARE a module's top-level implicit binding group, split by the same `implicitBindingComponents` that `inferBindingGroupTypes` uses.  Driven with a scripted LSP client against a probe module: hover answers `TautoProbe.pos : forall (r: rho). (exists (h: rho) (t: rho). r <- (t, h)) => Relation r -> Relation r` while the `.ei` the compiler writes for the same binding is `pos : forall (r: rho). Relation r -> Relation r`.  Nothing PUBLISHED is wrong (TolerantCheck never writes an `.ei` — the only `writeInterface` caller is `Session.dep`'s closure) and no gate sees it (`lsp-smoke`'s 181 checks have no hover assertion on a C12-shaped binding).  The fix is one argument, and it is safe: TolerantCheck's SCC loop is structurally the same as `inferBindingGroupTypes`'s. |
| **Q-2** | medium | CONFIRMED | **`Subst.deleteTautologies`'s scaladoc is stale on the two facts the stage turns on.**  It says "BEHIND `-Dermine.tautoDelete`, DEFAULT OFF" (it is ON) and "what is NOT established is that its effect is confined to the signatures C12 names, because this function runs at every generalisation and not only at the one that publishes a binding" — which is exactly what the `publishing` parameter fixed and the reason the flag flipped.  The correct text is already in `Constraints.GenRules.tautoDelete` twenty lines away. |
| **Q-3** | medium | CONFIRMED | **A necessity witness is misattributed.**  Both `Determined.lean`'s new section doc and `S5-HYGIENE.md` §1.1 cite `DeadTwoParts.two_parts_not_deletable` for "a part occurring elsewhere is not allowed".  It is not that theorem's shape: its residual is `⟨{0}, {⟨0,[1,2],∅⟩}⟩` — the deleted constraint's LHS is the existential and both parts are universal — so it cannot be `tauto_delete` with `hfresh` dropped (that would need `ex ∪ P = {0}` with `P = {1,2}`).  `hfresh` IS necessary; I supply the witness, and a second one for the all-parts-existential shape that `DeadTwoParts` is nearest to.  Both machine-checked (`review-S5/Probe.lean`). |
| **Q-4** | low | CONFIRMED | **`hr : r ∉ P` is not necessary.**  `tauto_delete_no_hr` proves the same `REquiv` without it (take the distinguished part `p₀ := r` when `r ∈ P`).  Harmless — the Scala side condition is narrower and derives `r ∉ P` from `!ex(r) && vs.forall(ex)` — but "none of the three hypotheses is decoration" is a claim about a different three, and `hr` is the one hypothesis with no witness. |
| **Q-5** | low | CONFIRMED | **The MULTI-constraint deletion has no Lean statement.**  `deleteTautologies` removes every `dead` candidate in one step; the licence is `tauto_delete` ITERATED, valid because the `occ` test makes distinct candidates' part sets disjoint and forbids a candidate's part from being another's LHS.  Argued in prose only.  Probed both ways (`both`, `sameLhs` fire; `two` does not). |
| **Q-6** | low | CONFIRMED | **`ei-classify.py` now reports "N of 268 interfaces differ" as 268 for every flag A/B.**  A `key-differs` row is appended to `rows`, and `rows` non-empty is what puts a file in `differing_files` — so in any comparison where the flag is in the fingerprint (i.e. every comparison the tool is for) the headline count is the file count.  The implementer's report quotes the two lines that stayed useful and silently drops that one.  Count key differences separately. |
| **Q-7** | low | CONFIRMED | **The WRITE side of the interface cache is still baked into the cached `Dep`.**  `Session.scala:513` freezes `writeInterfaceString` from the session that BUILT the dep, while the read side (`preCk`) was deliberately made call-time-gated with a comment saying why.  That asymmetry is the mechanism behind BOTH of this stage's `core/test` failures.  S5.2 raises its cost: a key mismatch now means a full recheck, and a dep carrying the no-op writeback never re-keys the file. |
| **Q-8** | low | CONFIRMED | `tracker/tools/g1-diff.sh`'s sanity band on non-blank `.ei` lines is `[1300, 1700]`; the keyed tree is `1447 + 129 = 1576`, so the headroom went from 253 to 124.  Not red today. |
| **Q-9** | low | CONFIRMED | Prose: `Session.interfaceKey`'s doc excludes "`ermine.rowSound.budget` / `.solveBudget`" and five lines later lists `solveBudget` among the properties that ARE in the key.  Both are true under the reading that the first means `ermine.rowSound.solveBudget`, but `ermine.solveBudget` is a real and different property that IS in the key, so the abbreviation reads as a contradiction.  Same sentence in `S5-HYGIENE.md` §2.2. |
| **Q-10** | low | CONFIRMED | `tracker/LOOP-MODEL-PLAN.md`'s S5 row still opens "**S5.2 GREEN, S5.1 PARTIAL**" and then says, in the same cell, that the flag is ADOPTED DEFAULT ON.  `S5-HYGIENE.md` §0 already says "both parts GREEN". |
| **Q-11** | info | CONFIRMED | The `foreign.tolerant` exclusion is right for a STRONGER reason than the report gives: the only site that turns it on (`lsp/Resident.scala:105`) also sets `_useInterface = Some(false)`, so a tolerant session can neither read nor write an `.ei` at all. |
| **Q-12** | info | CONFIRMED | The `boot` and `Wide` trace gates cannot see the deletion: nothing in the 129-module stdlib boot imports `Layout.Scan` and no module under `core/examples/Wide/` mentions it (grep).  What DOES exercise it downstream is the corpus run — nine corpus modules import `Layout.Scan` — and the sweep.  The implementer says this; I confirm the reachability, because "IDENTICAL traces" is otherwise easy to read as stronger evidence than it is. |
| **Q-13** | info | — | `Subst.scala:1667`'s `inferBindingGroupTypes(m.loc, Nil, is, es, true, true)` has two positional booleans and no comment; its twin at `Session.scala:971` has one. |
| **Q-16** | low, **not S5's** | CONFIRMED symptom, PLAUSIBLE cause | **A module whose published `.ei` carries a partition with a CONCRETE part never warm-reads.**  Probe `ConcProbe.e` (`cSig : r <- (h, (\|foo\|)) => …`) is fully rechecked and rewritten on every load; the otherwise-similar `TautoProbe2.e` (classes, `exists`, several bindings, no concrete part) warm-reads.  The key matches and the mtime is newer, so the only remaining `None` in `preCk` is the parse.  Not a concrete row as such — 129 of 129 stdlib interfaces warm-read, `Currency.ei`'s `Relation (\|Currency.currencyName, …\|)` included — so the cause is narrowed to the `X <- (…, (\|lbl\|))` form.  **18 of 268 corpus interfaces publish that shape**, `Layout/Report/Relation.ei` among them.  Entirely pre-existing and out of S5's scope, but it is the exact failure mode S5.2's report warns about (a silent full recheck with no test failing), so it belongs in a ticket. |
| **Q-15** | medium, **not S5's** | CONFIRMED | **`tracker/tools/g1-validate.sh`'s baseline-drift check is RED, and has been since F3.**  The tree calls it "a HARD GATE since 2026-08-31 … a Decision 9 stop — explain it or revert it", and it is in no `GATE-POLICY.md` tier, so nobody has run it since.  7 of 1,447 signatures drift from `tracker/g1-baseline`: `Relation/Scan.ei :: sumBy'` (F3's committed source deletion in `775a20f`, which post-dates the baseline `1a18b78`) and three alpha-variants in `Syntax/Relation.ei`.  All seven are byte-identical between my flag-OFF and flag-ON snapshots, so S5 does not touch any of them.  §4.1.  Either re-cut the baseline with an explanation or put the gate in a tier — the current state is the worst of both. |

---

## 1. The theorem

### 1.1 Re-elaborated

`tracker/lean/Rowpartition/Determined.lean`, §8:

```lean
theorem tauto_delete {ex : Finset Var} {G : System} {r : Var} {P : Finset Var}
    (hne : P.Nonempty) (hr : r ∉ P) (hfresh : ∀ p ∈ P, p ∉ allVars G) :
    REquiv ⟨ex ∪ P, insert (mk r P ∅) G⟩ ⟨ex, G⟩
```

Read against the file's own vocabulary (`Residual`, `Holds`, `REntails`, `REquiv` at
`Determined.lean:732-746`; `mk`, `Sat`, `sat_mk_iff`, `allVars` in `Rowpartition/Divergence.lean`),
the statement is exactly what a caller sees: `Holds rho R` says the caller fixes every variable
outside `R.ex` and the callee may choose the rest.  Three things are built into the SHAPE rather
than carried as hypotheses, and it is worth separating them from the hypotheses proper because the
implementer's necessity table conflates them (finding Q-3):

* the parts are ALL existential — that is what `⟨ex ∪ P, …⟩` on the left against `⟨ex, …⟩` on the
  right means;
* the concrete part is EMPTY — `mk r P ∅`;
* the deleted constraint is a single `insert` into the rest of the system `G`.

and three that are hypotheses: `hne`, `hr`, `hfresh`.

The proof is sound and I re-checked every step.  Forwards is not `rEntails_erase` (the existential
set shrinks too), and the witness `fun v => if v ∈ ex then sigma v else rho v` re-ties the dropped
variables to the caller; the `sat_congr_of_agree` step needs `hfresh` to know that no variable of a
surviving constraint is in `P`.  Backwards, `Tauto.wit` gives one distinguished part the whole of
`sigma r` and empties the rest; `hbi` is the `Finset.biUnion` computation, `hr` is what makes
`wit r = sigma r`, and pairwise disjointness holds because at most one part is non-empty.

`lake build` 870 jobs green, `Audit.lean` **4,596 theorems, 0 non-standard axioms**, and
`#print axioms` on all seven new declarations (`tauto_delete`, `tauto_delete_two`,
`ScanCount.count_tautology`, `TautoEmpty.tauto_empty_not_deletable`, `Tauto.wit_p0`,
`Tauto.wit_of_mem`, `Tauto.wit_of_not_mem`) gives `[propext, Classical.choice, Quot.sound]` for
every one.  Scratch: `review-S5/Ax.lean`.

### 1.2 Dropping the side conditions

The brief asks that each be dropped and refuted.  Machine-checked in
`review-S5/Probe.lean` (compiles clean under `lake env lean`, no `sorry`):

| condition | dropped ⇒ | witness | who supplies it |
|---|---|---|---|
| concrete part `= ∅` | `a <- (v, w, (\|Foo\|))` still says `Foo ∈ rho a` | `DeadUndetermined.undetermined_not_deletable` | existing (R3) — and it IS this theorem's orientation: `R.ex = {1,2}`, lhs `0` universal, so it is `tauto_delete` with `∅` replaced by `{0}` |
| `hne` (`k ≥ 1`) | `r <- ()` says `rho r = ∅` | `TautoEmpty.tauto_empty_not_deletable` | new, correct |
| `hfresh` (parts occur nowhere else) | the part is still tied to the rest of the system | **`RevHfresh.hfresh_needed`** — `r=0`, `P={1}`, `G={2 <- (1)}`, `ex=∅`; `rho = [0↦∅, 1↦{0}, 2↦∅]` satisfies the left and not the right | **the reviewer's** — the implementer cites `DeadTwoParts`, which is not this (Q-3) |
| all parts existential (the SHAPE) | a universal part is a real containment | **`RevUnivPart.univ_part_needed`** — `r=0`, parts `{1,2}` with `1` universal, `ex={2}` | the reviewer's; this is the Scala side condition `vs.forall(ex)` |
| `hr` (`r ∉ P`) | — | **not refutable: `tauto_delete_no_hr` PROVES the same conclusion without it** (take `p0 := r` when `r ∈ P`) | Q-4 |

So four of the five are load-bearing and demonstrated; `hr` is used by the proof but is not
necessary for the statement.  That is harmless — the Scala side condition is strictly narrower
still, and `r ∉ P` follows there from `!ex(r) && vs.forall(ex)` — but the report's claim that
"none of the three hypotheses is decoration" is a claim about a different three.

### 1.3 The mirror-image relation to R3

Correct and important: `dead_delete_of_pairwise` / `dead_delete_of_le_one_part` require
`DeadEx R v c`, i.e. `v ∈ R.ex ∧ c.lhs = v`.  Here the LHS is whatever the caller fixes and the
PARTS are the dead existentials.  Neither is an instance of the other; `R3-REVIEW.md` M-3 recorded
the gap and this closes it.

### 1.4 The Scala-only fourth exclusion (a repeated part) is real

`mk r P ∅` takes a `Finset`, so Lean's `{t,t}` IS `{t}`, whereas the surface `r <- (t, t)` asserts
`t` disjoint from itself and forces `rho t = ∅` and `rho r = ∅`.  `freshSplitShape`'s
`vs.distinct.length == vs.length` rejects it.  MEASURED: probe `rep` below publishes
`Relation (||) -> Relation (||)` at BOTH flag settings — the solver forces the row empty long
before a residual, so the shape never reaches `deleteTautologies` and the guard is (as the
implementer says) there because it must be, not because it fires.

### 1.5 Does `deleteTautologies` implement EXACTLY the side condition?  Probed.

Two probe modules (`review-S5/probe/TautoProbe.e`, `TautoProbe2.e`), each binding written twice:
`xSig` with the shape as a WRITTEN signature (explicit bindings publish verbatim and are the
control) and `x = xSig` whose type is INFERRED and therefore published through `mkSimplified`.
Loaded once at the shipped default and once with `-Dermine.tautoDelete=false`, all `.ei` deleted
between runs.  Published type of the INFERRED binding:

| probe | shape | flag OFF | flag ON | verdict |
|---|---|---|---|---|
| `pos`   | `r <- (h, t)`, `h`,`t` fresh existentials | `(exists h t. r <- (t, h)) =>` | **no qualification** | deleted — intended |
| `pos3`  | `r <- (a, b, c)`, k = 3 | `(exists a b c. r <- (c, b, a)) =>` | **no qualification** | deleted — the general `k ≥ 1` form, not just C12's two |
| `pos1`  | `r <- (t)`, k = 1 | already none | none | S3's `a <- (a)` gets there first (the solver substitutes `t := r`) |
| `both`  | two INDEPENDENT candidates | both kept | **both deleted** | intended (the multi-delete, Q-5) |
| `sameLhs` | `r <- (h,t), r <- (u,w)`, same universal lhs | both kept | **both deleted** | intended |
| `conc`  | a CONCRETE part `r <- (h, (\|foo\|))` | kept | **kept** | near miss held |
| `univ`  | a UNIVERSAL part (`h` also in the body type) | kept | **kept** | near miss held |
| `shared`/`two` | a part in ANOTHER row constraint | kept | **kept** | near miss held |
| `lhsElsewhere` | a part that is another constraint's LHS | kept | **kept** | near miss held |
| `exLhs` | the candidate's LHS is itself a published existential | kept | **kept** | near miss held |
| `self`  | `r` itself among the parts, `r <- (r, t)` | already none | none | pre-existing (S3), not C12 |
| `rep`   | a REPEATED part `r <- (t, t)` | forced `Relation (\|\|)` | same | never reaches a residual |
| `cls`   | a part in a CLASS constraint (`Eq (Record h)`) | `(exists h t. r <- (t, h)) =>` — the class constraint was already discharged by `reduce` | **no qualification** | correct: by the time `deleteTautologies` runs the part really does occur nowhere else |

Reading the code against the theorem, the implementation is the side condition and in three places
NARROWER:

1. `!ex(r)` — the theorem allows an existential `r`; the code refuses, so a deletion can never
   leave a binder bound and unmentioned.  (This also makes `hr` automatic: `r ∉ ex` and every part
   `∈ ex`.)
2. `occ` is computed over the WHOLE `pruned` list, class constraints included (`pruned =
   lessComplex ++ dumb`), so a part shared with a class constraint blocks the deletion; the
   theorem's `allVars G` only knows about row constraints.
3. two candidates that share a part delete neither (each is the other's "other constraint").

And it cannot go wrong on the two lists it does not see: the `extinct` constraints removed just
above are all-`iso`, and `pubExts` excludes `iso`, so no part can occur in one; and `exts` is
`typeVars(cs) -- nts -- gs` (`generalize`), so a published existential can never occur in the body
type.  Both checked by reading, and the sweep agrees.

---

## 2. The publishing restriction and the sweep

### 2.1 It is a parameter, and `true` at exactly two sites

Every call site in the tree:

| site | `publishing` |
|---|---|
| `Session.loadModule` (`Session.scala:971`) — the one that calls `writeInterface` | **true** |
| `Subst.checkModule` (`Subst.scala:1667`) | **true** (no in-tree caller; a test/batch entry point) |
| `Subst.inferType`'s `Let` case (`Subst.scala:908`) | default `false` |
| `generalize` at `Let` (910), `App` (925), `Lam` (940), `inferAltTypesPrime` (1034), `trySolveOn` (1564) | default `false` |
| `subsumeType`'s own `mkSimplified` (`Subst.scala:553`) | default `false` |
| `TolerantCheck` → `inferImplicitBindingTypes` (`TolerantCheck.scala:267`) | default `false` — **finding Q-1** |

A parameter, not a thread-local and not a global: correct, and the re-entrancy argument is right
(`inferType`'s `Let` re-enters `inferBindingGroupTypes`, and `Session.loadModules` runs loads on
several threads unless `loadInSeries`).  The `= false` default is the safe direction — a new call
site gets no deletion.

The one that is wrong is `TolerantCheck`, and it is not a `let`: `TolerantCheck.checkWith` is the
LSP editor path and the components it feeds to `inferImplicitBindingTypes` ARE the module's
top-level implicit binding group (`m.implicits`, split by `implicitBindingComponents`, exactly as
`inferBindingGroupTypes` does).  It never writes an `.ei` (verified: the only `writeInterface`
caller is `Session.dep`'s closure), so nothing published is wrong — but its `types` map is what
LSP hover reads, so hover now shows a type the compiler does not publish.  See Q-1.

### 2.2 The sweep, re-run by me — REPRODUCED exactly

Single build, flag A/B, `--batch --snapshot` twice, `-Dermine.loadInSeries=true` on both sides,
stdlib + `core/examples` (198 source files, 268 interfaces):

```
tracker/tools/ei-diff.sh --batch --snapshot <out>/OFF "-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true -Dermine.tautoDelete=false"
tracker/tools/ei-diff.sh --batch --snapshot <out>/ON  "-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true"
python3 tracker/tools/ei-classify.py <out>/OFF <out>/ON
```

```
interfaces: A 268  B 268  only-in-A -  only-in-B -
== bindings by verdict: {'identical': 3477, 'other': 4}
```

**3,477 identical / 0 order-only / 0 alpha-equivalent / 4 other** — the implementer's number, to
the binding.  At the BYTE level with the key header stripped from both sides (`grep -v
'^-- ermine-interface '`, then `diff -rq`): **exactly one of 268 files differs,
`core/target/.../modules/Layout/Scan.ei`, on exactly four lines.**  267 interfaces are
byte-identical.

The one line of the tool's output that is NOT reproducible as reported is `== 268 of 268
interfaces differ` — see Q-6.

### 2.3 The four signatures, before and after

Verbatim from my own snapshots (`Layout/Scan.ei`, the only file that moves):

```
- avgBy' : forall (op: rho -> * -> *) (r: rho) n (r2: rho) z k.
             (exists (AsOp: (rho -> * -> *) -> a) (t: rho) (h: rho).
                AsOp op, r <- (h, t), Builtin.PrimitiveNum n)
           => op r n -> Field r2 n -> Scan z (k, Relation r) -> Scan z (k, Relation r2)
+ avgBy' : forall (op: rho -> * -> *) (r: rho) n (r2: rho) z k.
             (exists (AsOp: (rho -> * -> *) -> a). AsOp op, Builtin.PrimitiveNum n)
           => op r n -> Field r2 n -> Scan z (k, Relation r) -> Scan z (k, Relation r2)

- count  : forall (f: * -> *) z k (r: rho). (exists (h: rho) (t: rho). r <- (t, h))
           => Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, Int)
+ count  : forall (f: * -> *) z k (r: rho).
             Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, Int)

- count' : forall (r2: rho) n z k (r: rho).
             (exists (t: rho) (h: rho). r <- (h, t), Builtin.PrimitiveNum n)
           => Field r2 n -> Scan z (k, Relation r) -> Scan z (k, Relation r2)
+ count' : forall (r2: rho) n z k (r: rho). Builtin.PrimitiveNum n
           => Field r2 n -> Scan z (k, Relation r) -> Scan z (k, Relation r2)

- sumBy  : forall (op: rho -> * -> *) (r: rho) n (f: * -> *) z k.
             (exists (AsOp: (rho -> * -> *) -> a) (h: rho) (t: rho).
                AsOp op, r <- (t, h), Builtin.PrimitiveNum n)
           => op r n -> Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, n)
+ sumBy  : forall (op: rho -> * -> *) (r: rho) n (f: * -> *) z k.
             (exists (AsOp: (rho -> * -> *) -> a). AsOp op, Builtin.PrimitiveNum n)
           => op r n -> Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, n)
```

**Are these the signatures a reader expects?  Yes, and `count` is the case that proves it.**
`count` counts the rows of a relation; the only thing its qualification said was that `r` splits
into two rows nobody names, which every row does.  Losing the `=>` entirely is what
`Relation/Scan.e:113-117` says a person should have been seeing since F3 deleted the same
constraint from `sumBy'` by hand.  `count'` keeps `PrimitiveNum n`, which is the real condition
(the counter's numeric type); `sumBy` and `avgBy'` keep `AsOp op, PrimitiveNum n`, which are the
two real conditions, and drop the one that was not.  The binder lists shorten in step: the two
`(h: rho) (t: rho)` existentials go with the constraint that alone mentioned them, so nothing is
left bound and unmentioned.  Nothing gets weaker: a shorter qualification on a signature you are
CALLING is strictly easier to discharge, and the theorem says the two are equivalent, not merely
that one implies the other.

### 2.4 An independent re-implementation of the criterion, over the whole sweep

To check the deletion fires everywhere it is licensed — the direction the A/B cannot see, because
a missed deletion looks exactly like `identical` — I re-implemented
`freshSplitShape` + `deleteTautologies` in Python against the PRINTED signatures
(`review-S5/candidates.py`: LHS not in the `exists` list, `k >= 1` distinct bare variables all in
the `exists` list, no concrete part, and no other constraint of the same signature mentioning any
of them) and ran it over both snapshots.

```
flag OFF snapshot:  4 bindings with at least one deletable constraint
                    Layout/Scan.ei :: avgBy'  r <- (h, t)
                    Layout/Scan.ei :: count   r <- (t, h)
                    Layout/Scan.ei :: count'  r <- (h, t)
                    Layout/Scan.ei :: sumBy   r <- (t, h)
flag ON  snapshot:  0
```

Across 268 interfaces and 3,481 published bindings the criterion is eligible in exactly the four
places the deletion fires and nowhere else, and the ON snapshot is a FIXPOINT — nothing eligible
survives.  Two in-corpus near misses are visible in the same file and stay:
`Layout.Scan.avgBy` publishes `a1 <- (c1, r)` where `r` is a UNIVERSAL part (kept at both
settings), and `Time/Signatures.ei` publishes three hand-written C12-shaped constraints on
EXPLICIT bindings (kept at both settings — Q-14).

---

## 3. The key

### 3.1 Format, and whether version 2 is earned

`Session.interfaceKey = interfaceFormatVersion + "|" + Constraints.GenRules.toString`, written as
`-- ermine-interface <key>` and, at the shipped defaults,

```
2|cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000+topnorm+tauto
```

Version 2 IS earned by a format change: the file gained a line that the interface grammar cannot
parse, so an old reader handed a new file would fail and a new reader handed an old file must know
that "no header" is a distinct state.  Version `1` never appears in any file, which is the right
design — a missing header and version 1 are the same condition and both are stale — and the doc
says so.  The split between the version and the fingerprint is also right: a solver flag rides in
`GenRules.toString` and needs no bump, and `tautoDelete` demonstrated that on the day.

`splitInterfaceKey` is robust in the two ways that matter: it compares on `.trim`, so a CRLF file's
key still matches, and `Option.contains` makes a missing key false without a special case.  A body
line can never be mistaken for the header (`.ei` lines are `name : type`).

### 3.2 Where it is checked

`Session.dep`'s `preCk`, between `file.interfaceContents` (which has just answered the mtime
question — `Filesystem.interfaceContents` returns `None` unless the `.ei` is newer than the `.e`)
and `interfaceFile.run` (which answers well-formedness).  A mismatch answers `None`, which is what a
newer source answers, which is `CheckMethod.Full`, which calls `writeInterface`.  One path, no
second cache.  Correct.

The consequence for a jar is real and stated: `SourceFile.classloader` answers `Filesystem` for a
`file:` URL (the dev tree) and `Resource` only from a jar, and `Resource.interfaceWriteback` is the
inherited no-op — so a jar shipping `.ei` built at another configuration makes every module in it
recheck on every load and never converges.  Right trade, correctly flagged.

### 3.3 The exclusions

| property | in the key? | verdict |
|---|---|---|
| `ermine.rowTrace`, `.rowTrace.draws` | no | **right**.  `RowTrace` reads the `Supply` reflectively and never writes it, builds no `Type`, and `withSite`/`withBinding` are by-name no-ops when off.  It cannot move a published byte. |
| `ermine.typeCheck` | no | **right**.  `Dep.make`'s `preChecked` answers `Some(untyped)` when it is off, so the module is `CheckMethod.Interface` and `writeInterface` is never called. |
| `ermine.useInterface` | no | **right**, by a different route than the doc gives: the module IS fully checked and `writeInterface` IS called, but `writeInterfaceString` was bound to `(_ => ())` at dep construction (`Session.scala:513`).  Same outcome; see Q-7 for why the difference matters. |
| `ermine.foreign.tolerant` | no | **right, and for a stronger reason** (Q-11): the only site that turns it on, `lsp/Resident.scala:105`, also sets `_useInterface = Some(false)`.  A tolerant session cannot read or write an `.ei` at all, so the doc's "changes whether a module LOADS, never the type published" never even has to be relied on. |
| `ermine.rowSound.budget`, `ermine.rowSound.solveBudget` | no | **right**: a lapse is a missing verdict, not a different published type. |
| `ermine.solveBudget` | **yes** (`+budget:20000`) | right — and the doc's abbreviation makes it look otherwise (Q-9). |
| `ermine.loadInSeries` | no | **right, and the only one that needs the argument the report gives.**  It does reach interface bytes, through `Supply` draw order, i.e. through the NAMES of published existentials.  Keying on it would invalidate every interface an LSP session wrote for a batch build and back again, on every load, to distinguish alpha-variants.  Recorded rather than implied, which is the right standard. |
| the `GenRules` flags | yes | right — they are the string. |

The `notInKey` textual assertion in `TestInterfaceKey` is the regression guard for the direction
that actually fails (somebody putting a non-key flag IN).  It cannot catch a NEW property that
should have been added; nothing can, and the `ANYTHING ADDED HERE THEREFORE INVALIDATES EVERY
CACHED INTERFACE` comment on `GenRules.toString` is the human half of that.

### 3.4 The header-strip trap, and the whole state machine, reproduced end to end

Not with `G1Compare --pair` (which parses line by line with `qtyp` and never runs
`InterfaceParsers.interfaceFile`) but against the real loader, with the observable that
`writeInterface` runs on EVERY `CheckMethod.Full` and on no `CheckMethod.Interface`: **an `.ei`
whose mtime moves was rechecked; one whose mtime stands still was read.**  Probe module
`KeyProbe.e` (two bindings, imports only `Prelude`), the stdlib watched through `Prelude.ei`:

| step | probe `.ei` rewritten | `Prelude.ei` rewritten | reading |
|---|---|---|---|
| (a) cold, all `.ei` deleted | written, header `2|…+topnorm+tauto` | written | Full / Full |
| (b) warm, same configuration | **NO** | **NO** | **Interface / Interface** |
| (c) a blank line inserted after the header | **YES** | NO | the parser rejects a leading blank line — Full |
| (d) header rewritten to `2\|another+configuration` | **YES**, and re-keyed to the running key | NO | stale = Full + rewrite |
| (e) header removed (a pre-S5 `.ei`) | **YES**, and re-keyed | NO | missing = Full + rewrite |
| (f) `-Dermine.loadInSeries=true` (NON-key) | **NO** | **NO** | still Interface |
| (g) `-Dermine.topNormalise=false` (KEY) | **YES**, header now `…+budget:20000+tauto` | **YES**, same | Full + rewrite at the new key |
| (h) back at the shipped default | **YES**, header back to `…+topnorm+tauto` | — | converges |

(c) is the trap, demonstrated rather than asserted: the parser really does reject a leading blank
line, so a `splitInterfaceKey` that BLANKED the header instead of removing it would have made every
module recheck for ever with no test failing.  Removing it is right.

Coverage, measured separately: with all `.ei` deleted, one `bin/ermine` boot writes 129 stdlib
interfaces; the next boot rewrites **0 of 129**.  Every stdlib interface really is read.

### 3.5 The checked-in baselines

* `G1Compare` (`g1-validate.sh`): 7 mutation fixtures PASS, and the two comparisons parse **1,447
  signatures from 129 KEYED files against 129 UNKEYED baselines** without touching either.
  `splitInterfaceKey` does its job on the tool side.  The `FAIL` in that script is the
  baseline-drift check and is pre-existing — §4.1, Q-15.
* `TestTolerantRead`: green, 8 properties.  It sweeps `.e` sources and never opens an `.ei`, as the
  report says.
* No baseline was updated, and none needed to be.

### 3.6 `TestInterfaceKey`'s remaining flake risk

The fixture is sound in the two ways it was bitten.  Both interface properties take
`ErmineFixture.literalLock` for their whole body, so they and `loadStatements` are serialised
against each other; `KeyA` imports nothing and `KeyB` imports only `KeyA`, so the property owns
every interface it depends on; and the three `SessionEnv` properties are asserted TEXTUALLY and
never set.

One process-global flip remains, and it is worth naming rather than leaving implicit:
`withProps("ermine.loadInSeries" -> "true", …)` is read on EVERY `Session.loadModules` call, and
the suites that do not take `literalLock` (`typeOf`/`eval` do not) can load inside that window.
The effect is confined to the loader's schedule, so a concurrent load would draw `Supply` ids in a
different order and publish alpha-variant existential names — which is exactly the class of
difference the sweep sets `loadInSeries` to suppress.  No test in the suite compares a printed type
across two loads outside the lock, so the risk is not live today; it would become live the moment
one did.

Measured: **five consecutive runs alone, both properties green every time**, and green again inside
the full 940-test suite alongside `TestInterfaceRoundTrip`.  No flake observed.

---

## 4. Gates, re-run once by me (adoption commit: Tier 0 + Tier 1 + Tier 2)

`PATH` per the brief, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time,
every `.ei` deleted afterwards.  The "pre-change build" is `git archive HEAD | tar -x` into scratch
(`review-S5/old`) plus `sbt core/compile core/copyResources` — HEAD carries no Scala change of this
stage, so it IS the pre-change compiler.

| gate | tier | my result | implementer's |
|---|---|---|---|
| `lake build` (`LEAN_NUM_THREADS=2`) | 0 | **green, 870 jobs**; the only warnings are the pre-existing `linter.style.header` ones on `Determined.lean:4,8,65,74` (all far above the new §8 section) and `Rowpartition.lean:94`'s long line | 870 |
| `lake env lean Audit.lean` | 0 | **`Rowpartition theorems audited: 4596; declarations using a non-standard axiom: 0`** | same |
| `#print axioms`, all seven new declarations | 0 | `[propext, Classical.choice, Quot.sound]` for every one | same (six; `Tauto.wit_p0` is the seventh and is also clean) |
| `sbt core/compile core/copyResources` | 0 | green | green |
| `sbt 'core/testOnly *TestLoopTrace'` | 0 | **720 / 720** — `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0` | same |
| `corpus-run.sh --batch` + `corpus-verdicts.py`, THIS build | 0 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** | same |
| the same on the PRE-CHANGE build, listing diffed | 1 | **byte-identical, messages included** — the only 8 diff lines are the stdlib PATH embedded in two `shouldfail/sk0*` refusal messages, which is the scratch build root, not a compiler difference | "zero lines differ" |
| `trace-ab.py`, `boot`, pre-change vs this build at the shipped default | 1 | **`segments=54209 IDENTICAL=54209 sinmoved=0`** | same |
| `trace-ab.py`, `Wide`, pre-change vs this build at the shipped default | 1 | **`segments=115874 IDENTICAL=115874 sinmoved=0`** | same |
| `sql-render.sh` (`wide-render-probe.e`), pre-change vs this build | 1 | **`sql/` (30 files) and `out/` (15 files) byte-identical** — `diff -rq` empty on both | same |
| `ei-diff.sh --batch --snapshot` ×2, flag A/B, `ei-classify.py` | 1 | **identical 3,477 / other 4**; byte level with the key stripped, **1 of 268 files differs, on 4 lines** | same |
| `repl-smoke.sh` | 0 | **green** — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23 | same |
| `lsp-smoke.sh` | 0 | **`PASS lsp (181 checks)`** | same |
| `sbt 'core/testOnly *TestInterfaceKey'` ×5 alone | — | **5/5, both properties, every run** | 2 properties |
| `sbt 'core/testOnly *TestTolerantRead'` | — | **green**, 8 properties | unaffected (it reads `.e`, not `.ei`) |
| `sbt core/test` ALONE | 2 | **`Passed: Total 940, Failed 0, Errors 0`** (1314 s); both `Interface key` properties and `Interface round-trip` pass inside the full suite | 940/940 |
| `g1-validate.sh` (this build) | — | **8 PASS / 1 FAIL** | not run |
| `g1-validate.sh` (PRE-CHANGE build) | — | **8 PASS / 1 FAIL, the same 7 signatures** — the FAIL is pre-existing.  §4.1, Q-15 | not run |

Two traces byte-identical to the pre-change compiler is the right result, and it is worth saying
what it does and does not show (Q-12): nothing in the 129-module stdlib boot imports `Layout.Scan`,
and no module under `core/examples/Wide/` mentions it, so those two groups cannot see the deletion
at all.  What DOES exercise it downstream is the corpus run — nine corpus modules import
`Layout.Scan` — whose verdicts and messages are unchanged, and the sweep, where every one of those
nine publishes a byte-identical interface.

**The interleaved perf A/B is not required, and I did not run it.**  Two independent reasons:
`mkSimplified` is post-loop, so nothing the solver does changes; and the only signatures that move
are four in a module the stdlib boot does not load, so the benchmark's hot path is untouched.
`GATE-POLICY.md` already lists it as "not a per-stage gate", and the machine drift it documents
(10.9-13.9 s) exceeds any effect four shorter signatures could have.

### 4.1 The one red gate, and why it is not S5's

`tracker/tools/g1-validate.sh` — not in `GATE-POLICY.md`'s tiers, run here because the brief asks
whether the 143 checked-in UNKEYED baselines still work — comes out **8 PASS / 1 FAIL**:

```
  PASS  fixture diff-collapsed-exists-binder … eq-reordered-forall   (7 mutation fixtures)
  OK: new run — 129 modules, 1576 sig lines, 3 group parse-errors
  g1-compare: 129 files, 1447 signatures, EQUIVALENT
  PASS  double-run self-agreement
  FAIL  drift from tracker/g1-baseline        (129 files, 1447 signatures, 7 differing)
```

**The key half is GREEN and is what the brief asked about**: `G1Compare` reads 129 KEYED `.ei`
against 129 UNKEYED baselines and parses 1,447 signatures on both sides, so `splitInterfaceKey`
does its job and no baseline needed touching.  `TestTolerantRead` is green and does not read `.ei`
at all.

**The drift is pre-existing — measured, not argued.**  I ran the same script on the PRE-CHANGE
build in scratch (its own `repl-classpath.txt` regenerated so it cannot borrow this build's
classes): **8 PASS / 1 FAIL, the same `129 files, 1447 signatures, 7 differing`.**  The pre-change
run also reports `1447 sig lines` where this build reports `1576`, which is Q-8's +129 exactly.
All seven differing signatures are byte-identical between my flag-OFF and flag-ON snapshots, i.e.
the deletion does not touch any of them:

* `Relation/Scan.ei :: sumBy'` — the baseline still carries `r <- (h, t)`; the SOURCE lost it in F3's
  committed `775a20f` (2026-09-08), and the baseline was recorded in `1a18b78`.  So this has been
  red since F3.
* `Syntax/Relation.ei :: (&), (&_Mem), (**)` — the two sides are alpha-variants under the single
  transposition `c ↔ e` (`a <- (e,d), r <- (d,c)` against `a <- (d,c), r <- (e,d)`, with
  `b <- (e,d,c)` fixed), and `G1Compare` reports them as differing anyway; both settings of this
  stage's flag produce the same side.

Two things for the orchestrator, neither of them a reason to hold S5: a gate the tree calls a
"HARD GATE … a Decision 9 stop" has been red for a day and nothing said so, because it is in no
tier; and `g1-diff.sh run`'s sanity band on non-blank `.ei` lines is now `1576` of a `[1300,1700]`
ceiling because of the key line (Q-8).

---

## 5. The adoption

### 5.1 What a user sees

Four stdlib types get shorter, and they are all in `Layout.Scan`:

| | before (`-Dermine.tautoDelete=false`) | after (shipped) |
|---|---|---|
| `count`  | `forall (f: * -> *) z k (r: rho). (exists (h: rho) (t: rho). r <- (t, h)) => Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, Int)` | `forall (f: * -> *) z k (r: rho). Scan (Report f z) (k, Relation r) -> Scan (Report f z) (k, Int)` |
| `count'` | `… (exists (t: rho) (h: rho). r <- (h, t), PrimitiveNum n) => …` | `… PrimitiveNum n => …` |
| `sumBy`  | `… (exists (AsOp: …) (h: rho) (t: rho). AsOp op, r <- (t, h), PrimitiveNum n) => …` | `… (exists (AsOp: …). AsOp op, PrimitiveNum n) => …` |
| `avgBy'` | `… (exists (AsOp: …) (t: rho) (h: rho). AsOp op, r <- (h, t), PrimitiveNum n) => …` | `… (exists (AsOp: …). AsOp op, PrimitiveNum n) => …` |

Full text in §2.3.  `count` is the extreme: the tautology was its only qualification, so the type
loses the `=>` altogether — which is what a reader of `count : Scan z (k, [..r]) -> Scan z (k, Int)`
expects, and what the source comment at `Relation/Scan.e:113-117` says a person should have been
seeing all along.  Nothing gets longer, nothing gets weaker, and no WRITTEN signature moves at all
(explicit bindings publish verbatim; see Q-14).

**How often does this reach user code?**  From the sweep, and from my own independent
re-implementation of the criterion over the whole flag-OFF snapshot (§2.4): **four bindings out of
3,481, in one interface out of 268** — 0.11% of published bindings.  The shape only arises where a
library author writes `r <- (h, t)` to mean "`r` is a row" (the `Relation.Scan` idiom) AND a
downstream binding re-exports it without a signature, so its type is inferred.  A user who writes
signatures never sees it; a user who leans on inference in a module that uses those combinators may
see one qualification disappear.  The honest summary is: rare, and always a shortening.

### 5.2 Rollback

`-Dermine.tautoDelete=false`.  It is a one-line early return inside `deleteTautologies` plus the
`if (publishing)` at the `mkSimplified` call, so with the flag off `mkSimplified` returns
`Exists(l, pubExts, pruned)` exactly as it did before the stage — the ONLY other change to
`Subst.scala` is a parameter being threaded.  Measured on top of that: the `boot` and `Wide` row
traces and the corpus verdict listing are byte-identical between the PRE-CHANGE compiler and this
build at the SHIPPED default (§4), which is a stronger statement than the flag-off comparison and
covers the configuration that actually ships.  Since the key changes with the flag, a rollback also
rebuilds the interfaces by itself.

### 5.3 The first adoption with no manual cache wipe — verified

The claim is that an `.ei` written before the flip is rebuilt on the next load because the key
changed, so `ROW-CONSTRAINT-STATE.md`'s `find . -name '*.ei' -delete` is retired.  Run end to end
on the real tree with `core/examples/GroupBy.e` (which imports `Layout.Scan`):

```
1. all .ei deleted; load at -Dermine.tautoDelete=false
     Layout/Scan.ei header: 2|…+budget:20000+topnorm            <- no +tauto
     count : forall … (exists (h: rho) (t: rho). r <- (t, h)) => …
2. load again at the SHIPPED DEFAULT, nothing cleared by hand
     Layout/Scan.ei REWRITTEN
     header:  2|…+budget:20000+topnorm+tauto
     count : forall (f: * -> *) z k (r: rho). Scan (Report f z) (k, Relation r) -> …
3. load a third time at the default
     Layout/Scan.ei NOT rewritten                                <- and it converges
```

That is the mechanism paying for itself on the first adoption after it landed, exactly as claimed.
The converse is also verified (§3.4 (g)): flipping `topNormalise`, an OLD adoption's flag, now
rebuilds the stdlib by itself too.

### 5.4 The prose

* **Ticket C12** (`TICKET-stdlib-findings.md`): both corrections are there and both are right —
  it is four signatures, not five (F3 hand-fixed `sumBy'` in `Relation/Scan.e` the day after C12
  was written), and the unrestricted deletion moved `cutoffGroupedFldsPosNegRel'` because a
  `let`/`where` group is an intermediate generalisation.  The original claim is kept below the
  `[FIXED]` block, which is the right shape for a ticket.
* **Plan row S5** (`LOOP-MODEL-PLAN.md`): complete and accurate except the headline (Q-10).
* **`ROW-CONSTRAINT-STATE.md`**: three dated notes — the `tautoDelete` adoption, the superseding
  of the `topNormalise` cache-wipe instruction, and the closing of the "No `.ei` cache key for the
  flags" open gap.  All three keep the original text as the record, which is this file's convention.
* **`ROSE-COMPARISON.md`**: rank 6 gets a dated DONE block naming what is and is not in the key,
  and rank 3's risk paragraph gets the note that the manual wipe is retired.  Correct.
* **`Constraints.scala`**: the `dequeuePolicy` OPEN GAP comment becomes CLOSED, and
  `GenRules.toString` gains the warning that anything added to it invalidates every cached
  interface.  That warning is the most valuable line of prose in the stage.
* **`ei-classify.py`**: the crash fix is necessary and correct; the reporting side of it is Q-6.
* **`LOOP-MODEL-HANDOFF.md`**: the 09:08 entry's "S5.1 PARTIAL … DEFAULT OFF" is superseded
  explicitly by the 11:30 entry six lines later, which is how an append-only chronology is
  supposed to work.  Nothing for the reviewer to do; the orchestrator's next entry closes it.


---

## 6. What to fix before the commit

**Must fix (three).**

1. **Q-1** — `TolerantCheck.scala:267`: pass `publishing = true`.  That call IS the module's
   top-level implicit binding group (`is = m.implicits`, `implicitBindingComponents`), it is the
   only reason hover and the compiler disagree, and TolerantCheck's SCC loop is structurally the
   same as `inferBindingGroupTypes`'s.  Re-run `lsp-smoke.sh` and `sbt 'core/testOnly
   *TestTolerantCheck'`; a hover assertion on a C12-shaped binding would be the right regression
   guard but is not required.  If instead the divergence is judged acceptable, it must be WRITTEN
   DOWN at that call site and in `S5-HYGIENE.md` — the one thing it must not be is an accident.
2. **Q-2** — `Subst.deleteTautologies`'s scaladoc: delete "DEFAULT OFF" and the whole final
   paragraph ("what is NOT established is that its effect is confined … runs at every
   generalisation"), which the `publishing` parameter is precisely what removed.  Point at
   `GenRules.tautoDelete`, which already has the correct text.
3. **Q-3** — `Determined.lean`'s §8 section doc and `S5-HYGIENE.md` §1.1: `DeadTwoParts` does not
   witness `hfresh`.  Either say so, or paste in the two witnesses I wrote, which are short and
   check clean at standard axioms (`review-S5/Probe.lean`): `RevHfresh.hfresh_needed`
   (`r=0, P={1}, G={2 <- (1)}, ex=∅`) for `hfresh`, and `RevUnivPart.univ_part_needed`
   (`r=0`, parts `{1,2}`, `1` universal, `ex={2}`) for the all-parts-existential shape that
   `DeadTwoParts` is nearest to.  Adding them would make §8's necessity table complete for the
   first time.

**Should fix (prose and tooling, none of them blocking).**

4. **Q-6** — `ei-classify.py`: do not let a `key-differs` row put a file in `differing_files`;
   report key differences on their own line.  As it stands the headline is `268 of 268` in every
   flag A/B, which is the comparison the tool exists for.
5. **Q-9** — spell `ermine.rowSound.solveBudget` in full in `Session.interfaceKey`'s doc and in
   `S5-HYGIENE.md` §2.2, so it cannot be read against the `solveBudget` two lines below.
6. **Q-10** — `LOOP-MODEL-PLAN.md`'s S5 row headline: "S5.2 GREEN, S5.1 PARTIAL" is superseded by
   its own cell.
7. **Q-14** — `S5-HYGIENE.md` §1.3: `Time/Signatures.e` DOES write C12's shape by hand, three
   times, and the interesting fact is that it does not matter because those are explicit bindings.
8. **Q-13** — a word of comment on `Subst.scala:1667`'s second `true`.

**Tickets, not this stage's work.**

9. **Q-15** — `g1-validate.sh`'s baseline-drift check has been red since F3 and is in no tier.
   Re-cut the baseline with an explanation, or put the gate in `GATE-POLICY.md`; and note that
   `g1-diff.sh run`'s `[1300,1700]` band is now `1576` (Q-8).
10. **Q-16** — an `.ei` publishing `X <- (…, (|lbl|))` does not round-trip, so 18 of 268 corpus
    interfaces are fully rechecked on every load, silently.  Pre-existing, and exactly the failure
    mode S5.2's own report warns about.
11. **Q-7** — gate `writeInterfaceString` at call time the way `preCk` is, and the process-global
    `useInterface` flake class that bit this stage twice goes away.
12. **Q-5** — if the canonical-residual programme leans on the multi-constraint deletion, it wants
    a Lean statement of the iterated form rather than the prose argument.

## 7. Artefacts

`/home/dmitry/.claude/jobs/880c725d/tmp/review-S5/`: `Probe.lean` (the three side-condition
probes), `Ax.lean`, `probe/` (the Ermine near-miss modules), `candidates.py` (the independent
re-implementation of the deletion criterion), `hover-probe.py`, `old/` (the pre-change build),
`eiOFF` / `eiON` / `eiOFFnh` / `eiONnh` (the sweep), `tr/` (four row traces), `corpus-old` /
`corpus-new`, `sql-old` / `sql-new`, `log/` (every gate log), `run1.sh` … `run6.sh`.
Every `.ei` this review caused has been deleted.
