# Item E11b Phase 1 — which entailment oracle should decide deletion at publication?

**EXPLORATION ONLY.  Nothing under `core/src/main`, `session/` or `tracker/lean/` was touched; no
default was flipped; nothing was committed.**  Repo `/home/dmitry/research/ermine/ermine-scala`,
branch `scala3-migration`, HEAD `8cc4d38c`.  Every number below comes from a command whose log is
named in §10 and lives in
`<scratch>` = `/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle/`.
The probe's data (`<prev>` =
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11b/`)
was reused, not re-derived.  `<rev>` is the reviewer's sibling scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle-review/`.
**This document incorporates the fix round of `E11b-ORACLE-REVIEW.md` (ACCEPT WITH FIXES); every figure
below is the re-measured one, and §12 lists what moved.**

## The judgement being decided

For a published residual `R = <ex, sys>` (universals = the scheme's `forall` binders plus the body's
free variables; `ex` = `mkSimplified`'s `pubExts`) and a constraint `c` in `sys`,

    DELETABLE(c)  :=  REntails <ex, sys \ {c}> <ex, sys>                       (ROSE §4.1)

i.e. for every assignment `rho` of the universals that SOME choice of the existentials extends to a
model of `sys \ {c}`, SOME (possibly different) choice extends it to a model of all of `sys`.  The
other direction is trivial, so `DELETABLE(c)` is exactly "deleting `c` is `REquiv`".

---

## 1. Recommendation

**Adopt candidate (A), `SigEntail.check`, with two caller-side corrections and one small extension —
and do not expect it to close the ticket.**  The corrections are load-bearing and both are measured,
not argued.  (i) `pxs` must be **the existentials PRIVATE to the candidate constraint** —
`ex ∩ vars(c) \ vars(sys \ {c})` — and not the whole `pubExts` list the orchestrator's sketch
suggests: with the whole list the check accepts 7 deletions of 751 on evidence it is not entitled to,
because `check` builds `vars(Q)` out of the givens it could READ, so an existential pinned only by an
unreadable given (or by a class constraint) becomes free to re-choose — and the review's residual
`sys = { (|k|) <- (x, y), a <- (x) }` makes that an outright UNSOUND deletion, not merely an
unjustified one (§5.1, `<rev>/synth.txt`, `<scratch>/zfix-synth-all-off-first.log`).  (ii) Only ROW constraints may be
CANDIDATES: `check` returns `Ok` for any obligation it cannot encode when no caveat was raised, so a
class constraint handed to it as `rs` is reported deletable (§5.2, "the `NotRow` trapdoor").  The
extension is the **proxy encoding** that `SigEntail.scala:435-437` already names as an S4 item: rewrite a
concrete left-hand side `(|K|) <- (p1..pn)` as `z <- (p1..pn)` and `z <- ((|K|))` for one fresh
**existential** `z` per distinct `K` — `z` is a DEFINED auxiliary and must be in the pool `pxs` draws
from, which the first measurement got wrong (review R-1, §12).  It is a dozen lines in `encode`, it is
verdict-preserving, and on this corpus it removes **every** no-verdict: 426 of 751 calls are
`NoVerdict` without it and **0** with it (`<scratch>/cost-summary.txt`); with `z` existential it also
raises the acceptances from 394 to **452 of 751**, and from 30 to **88 of the 140** candidates that
have a concrete left-hand side (`<scratch>/zfix-cost-summary.txt`).  The choice rule: E11a's canonical key order over the set, first
deletable goes, restart, to a fixpoint; keep on any no-verdict or budget lapse; run it on
`Canonical.key` order, which means **after** `Canonical.scheme` rather than inside `mkSimplified`
(§9).  Budgets: `SigEntail`'s own `classBudget` 200,000 / `sigBudget` 1,000,000 are ~38x the worst
call measured here (5,265 nodes) and need no change; add a **per-scheme cap of 200 oracle calls**,
which is 7x the worst single pass measured (27).

**THE HEADLINE, under the recommended rule and nothing else** (greedy, first deletable, canonical
order, `pxs` private, proxy encoding with `z` existential; `<scratch>/zfix-first.log`, compared in
`<scratch>/zfix-cmp.txt`).  The rule makes the two variants agree on **9 of the 31 recoverable sweep
pairs**, per binding:

| binding | sweep pairs it appears in | converged under the recommended rule |
|---|---|---|
| `Present/WriterOutputs.e:reportFor` | 5 | **5** — closed |
| `Relation.e:lookbackJoin` | 3 | 1 (`before` only) |
| `Yahoo.e:investmentTableData` | 5 | 1 (`after` only) |
| `Yahoo.e:joinTotalValue` | 5 | 1 (`after` only) |
| `Yahoo.e:joinCumRet` | 3 | 0 |
| `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'` | 5 | 0 |
| `Relation/RTree.e:level1` (not a target; nothing is deletable) | 1 | 1 |
| `Algebra/Signatures.e:runningTotalFull`, `:…ViaWritten` (not targets) | 4 | 0 |

On the RUN OF RECORD — `after3` for five of the six, `after2` for `lookbackJoin`, which `after3` does
not carry — exactly one of the six converges.  **The honest ceiling under the recommended rule is
SET 6 -> 5**, not 6 -> 0 and not the 6 -> 4 an earlier draft claimed: 6 -> 4 needs the backward scan
(`lookbackJoin` 2 of 3) or the exhaustive-minimum rule (3 of 3), and neither is proposed — the
backward scan loses `before:lookbackJoin` in exchange, and the exhaustive rule costs 257,536 oracle
calls and 62 s on one binding and is not even convergent (§6, review R-4).  **What is beyond the
oracle, by name:** `Yahoo.e:joinCumRet` (3 of 3 pairs), `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`
(5 of 5), `Yahoo.e:joinTotalValue` and `Yahoo.e:investmentTableData` (4 of their 5 each), and
`Relation.e:lookbackJoin` (2 of 3).  On those the two variants reduce to irredundant cores that are
still different — in `cutoffGroupedFldsPosNegRel'` the cores even have the same SIZE and a different
SHAPE — so the obstruction is not the oracle's strength and not the visiting rule: **deletion alone
cannot equate them, because the two runs' cores are not isomorphic** (§6).  The roadmap's acceptance
("the corpus SET count goes to 0, or every survivor classified as beyond the oracle") is met only by
its second clause.

**Two scopes for the user to choose between.**  The review's point (a) sharpens what the survivors
need, and `after3:joinCumRet` is the clean specimen: with the encoding corrected both variants reduce
to FOUR constraints, and the two cores differ in exactly one of them —
`t <- ((|adjClose,initValue|), so, rs, b)` on one side against
`t <- ((|adjClose|), so, d, rs, c, b)` on the other, with `(|initValue|) <- (d, c)` surviving on both
(`<scratch>/zfix-first.log`, the `S` lines for `after3:joinCumRet`).  That is one partition written
folded on one side and unfolded on the other, over `t`, which is a **universal** — so no deletion can
remove it from either side and no oracle verdict is relevant.  **E11b-as-specified** (deletion only)
therefore tops out at 6 -> 5.  **E11b-plus-normalisation** — an ORIENTED fold/unfold of the survivors
before the deletion loop, i.e. the "definitional substitution" the probe named (§5.3 of
`E11b-PROBE.md`), always unfolding a concrete group's definition (or always folding it), run to a
fixpoint — would plausibly equate the `joinCumRet`, `joinTotalValue` and `investmentTableData` cores,
because their difference is exactly that in every sweep; it would not touch
`cutoffGroupedFldsPosNegRel'`, whose difference is un-splitting.  Estimated cost: the rewrite itself is
small (it works on `NormalPart` lists, which are Lean's `Constraint` field for field) but it needs an
orientation and a termination argument that the existing measure does not give (folding shrinks a
right-hand side, unfolding grows it), so **one stage to implement and measure, plus one stage of Lean
if the termination is to be proved rather than fuel-capped** — roughly double E11b-as-specified, for a
plausible 6 -> 2.  Both scopes carry the same large `.ei` blast radius (§6).

---

## 2. Comparison table

| | (A) `SigEntail.check` | (B) solver on the negation | (C) saturating decision procedure |
|---|---|---|---|
| **sound for DELETABLE** | YES, with `pxs` = the candidate's PRIVATE existentials and row-only candidates; the sketch's `pxs = pubExts` is NOT sound (7/751 measured) | n/a — the premise fails | YES; every rule is a consequence of the remaining equations |
| **decides on the six** | reportFor 5/5; lookbackJoin 1/3 greedy-first (2/3 greedy-last, 3/3 exhaustive); investmentTableData 1/5; joinTotalValue 1/5; joinCumRet 0/3; cutoff 0/5 | nothing — `¬c` is not expressible | reportFor 5/5; lookbackJoin 3/3; Yahoo/cutoff no (measured with the PRE-R-1 proxy; not re-run) |
| **convergence (31 pairs)** | **9/31** greedy-first, 10/31 greedy-last, 13/31 exhaustive-min (corrected proxy; 7/8/13 with the weaker one) | — | 11/31 first, 9/31 last, 15/31 exhaustive-min (pre-R-1 encoding) |
| **cost / constraint** | measured: max 589 nodes, max 12 models, mean 0.20 ms with the corrected proxy encoding (0.46 ms and max 5,265 nodes without any proxy) | — | ~0.1 ms in PYTHON, bounded BFS depth 4 |
| **determinism given E11a's order** | verdict is a function of the constraint set alone on this corpus; the internal `canonKey` still embeds `v.id` (`SigEntail.scala:653`), which can only matter through a budget lapse, and the margin measured is 38x | — | fully id-free by construction |
| **verdict** | **RECOMMENDED** | **REJECTED** | useful as a fast pre-pass; strictly weaker overall, and not shipped |

---

## 3. How the residuals were built as `Type` values (the measurement's provenance)

The shortest path turned out to be a **throw-away Scala driver in the test tree**, run against the
compiled classes with `sbt core/Test/runMain`.  `sbt core/console` was not needed and no property was
written.  The driver (deleted before this report was written; its source is reproduced in
`<scratch>/OracleDriver.scala.txt`) does this:

1. `<scratch>/mkinput.py` re-parses the probe's 31 raw rendering pairs (`<prev>/pairs/*.txt`) with the
   probe's own scheme parser (`<prev>/conv.py`), and writes `<scratch>/cases.txt` — one block per pair
   per side, carrying the `forall` binders, the `exists` binders and every constraint **including** the
   ones the probe's Lean conversion had to drop or encode away: concrete left-hand sides, several
   concrete parts in one right-hand side, and the 140 class constraints.  Those are exactly the cases
   the oracle's behaviour has to be measured on.
2. The driver builds each side as real `Type` values: `V(Loc.builtin, id, Some(Local(name)), ty, Star)`
   with `ty = Free` for a `forall` binder and `Ambiguous(Bound)` for an `exists` binder — the flavour
   `Subst.generalize:1771` actually mints — `ConcreteRho(Loc.builtin, Set[Name])` for a literal column
   set, and the **smart constructor** `Part(loc, lhs, rhs)` so that `Part.apply`'s normalisations
   (Type.scala:408-431) are the ones the compiler would have applied.  A class constraint is built as
   `AppT(VarT(head), VarT(arg)...)` with `head.ty = Bound`, which is the spelling `SigEntail.alpha`'s
   comment says the renamer really leaves behind; `encode` classifies it `NotRow` either way.
3. For each constraint `i` it calls
   `SigEntail.check(qs = every other constraint, rs = constraint i, ds = Nil, sks = Nil, pxs = …)` and
   logs the verdict, `SigEntail.lastCost` (nodes / models / classes) and wall milliseconds.
   `sks = Nil` is correct here: `sks` is used for exactly one thing, telling this signature's own
   skolems from a foreign one, and at publication **there are no skolems at all** (`generalize` filters
   `_.ty != Skolem` at `Subst.scala:1764` and `:1770`), so `foreign` is empty and no branch of `check`
   depends on it.  `pxs` is the measurement's variable: `all` = every existential, `private` = the
   existentials of `c` that occur in no other constraint.
4. It then runs the deletion fixpoint under a stated choice rule and prints the surviving set;
   `<scratch>/cmpfinal.py` decides whether the two variants' surviving sets are equal up to a
   renaming of existentials (universals matched by name, backtracking bijection, 4M-node budget,
   never hit).

Four configurations were measured — `pxs ∈ {all, private}` x `proxy ∈ {off, on}` — and three choice
rules (`first`, `last`, `min`).  751 oracle calls on row constraints per configuration.

**The three intermittent bindings are NOT recoverable.**  `Layout/Report.e:drilldownKeyValueTable2`
appears in `<prev>/../e11a/logs/sweep-before.tsv` only as a **FORM** record (line 388), i.e. from the
pre-E11a build where its difference was form, not set; `incomplete/RevenueShare.e:shareOfGroup` and
`incomplete/np01_add_or_recompute.e:inferredRestate` appear in none of the five sweeps.  Only the sweep
TSVs carry renderings, so getting their two forms means re-running the E11a property with a patched
printer — a compiler run, outside this phase.  They are unmeasured, not inferred.

---

## 4. Candidate (A) — `SigEntail.check` as it stands

### 4.1 Soundness: does `Ok` imply `DELETABLE(c)`?

`check` decides: *for every `rho` that models `Q`, there is a `rho'` agreeing with `rho` off `F` such
that `rho'` models `W`*, with `W` the encoded obligations and

    F = vars(W) ∩ pxs \ vars(Q)                                   (SigEntail.scala:491)

Take `Q = sys \ {c}`, `W = {c}`, `ds = Nil`.  The orchestrator's sketch is **correct in its core step
and wrong in one premise**.  The core step: if `F ∩ vars(Q) = ∅` then a witness `rho'` differs from
`rho` only on variables `Q` does not mention, so `rho' |= Q` as well as `rho' |= W`, hence
`rho' |= sys`; and if additionally `F ⊆ ex` then `rho'` agrees with `rho` on every universal, so the
same `rho` of the universals is extended.  That is exactly `DELETABLE(c)`.  Both side conditions hold
**by construction of `F`** provided `pxs ⊆ ex`.  Cases:

* **shared existentials between `c` and `Q`** — such a variable is in `vars(Q)`, so it is NOT in `F`:
  it is treated as rigid and the check must prove `c` pointwise.  Conservative and sound.  This is the
  `lookbackJoin` case: every variable of the redundant conjunct occurs elsewhere, `F = ∅`, and the
  check is plain entailment.  Measured `Ok` (§4.2).
* **a fresh existential in `c`** — it is in `F` and may be re-chosen.  This is `reportFor`, and it is
  the only mechanism by which the published `a <- (c) + (|pMinValue,pRegion|)` can go: it is NOT a
  consequence over all variables (the probe's §5.2 counter-assignment) and `Canonical.lean`'s
  model-preserving rules may never delete it.  Measured `Ok`, `Cost(1, 2, 4)` (§4.2).
* **a universal in `c` not in `Q`** — a universal is never in `pxs`, so never in `F`; it is quantified
  the same way on both sides of `REntails` and the pointwise proof is what is needed.  Sound.
* **a concrete left-hand side** — `encode` (`:360`) returns `Unreadable` for a NON-EMPTY literal set
  on the left; the empty row is normalised (`:357`).  As a GIVEN that sets `caveatQ`, which forbids
  REJECT.  **That is not enough for us**, and this is the first of the two corrections: dropping a
  given also drops its variables from `vars(Q)`, which can only make `F` BIGGER, and a bigger `F` makes
  ACCEPT easier.  So `check`'s own discipline ("a dropped given forbids only REJECT",
  `SigEntail.scala:420-431`) is sound for the signature judgement but **unsound for DELETABLE** unless
  the caller keeps the dropped given's variables out of `F`.  Passing `pxs` = the candidate's PRIVATE
  existentials does exactly that, for every unreadable given at once, and needs no change to
  `SigEntail`.  As an OBLIGATION a concrete left-hand side sets `caveatW` and yields
  `NoVerdict("every obligation was dropped as unreadable")` = KEEP, which is right but useless: it is
  why the three `Yahoo` bindings are undecidable as things stand.  The proxy encoding fixes it (§4.3).
* **class constraints** — `mkSimplified` partitions them off at `:2130` but they are still in the
  published `Exists`, so they are part of `sys` and their variables must not be re-chosen.  The
  private-`pxs` discipline covers that too, and the oracle never needs to READ them.  It must never be
  ASKED about one: `encode` returns `NotRow`, `wRows` is empty, and `check` returns **`Ok`**
  (`SigEntail.scala:455-456`) — "nothing to prove" — which as a deletion verdict means "delete this class
  constraint".  Candidates must be filtered to row constraints.  (Measured: with class constraints in
  the candidate list a first run deleted all 140 of them, `<scratch>/run-private.log`.)
* **an unsatisfiable `Q`** — `DELETABLE(c)` is vacuously true (no `rho` has an extension), and `check`
  agrees: `qe.conflicted` at a class means "no model of the givens at this class: nothing to check"
  (`:522`) and the class passes.  So an unsatisfiable residual is fully deletable, which is sound but
  worthless.  **An earlier draft said `mkSimplified` already refuses such a residual at the `extinct`
  solve (`:2136`); that is wrong** (review R-3): `:2136` solves `extinct`, the constraints being THROWN
  AWAY at the `:2131-2133` partition ("solve constraints before throwing them away"), not `dumb`/`pruned`,
  which is what gets published and what the oracle would read.  Nothing on the path refutes an
  unsatisfiable PUBLISHED set, so the case can arise; it is benign in the deletion direction (everything
  is vacuously deletable, and any `c` that contradicts a satisfiable `Q` is refuted rather than accepted),
  but it is not discharged.
* **the satisfiability precondition of ROSE §4.6** — `entails_iff_forall_label` (`Basic.lean:525`) is an
  `iff` only under `∃rho. Models rho G`, and the certificate is S2 layer (iii)'s
  `Loop.solve_noFalseAccept`, on by default since 2026-09-06.  **This report names no discharge site for
  the PUBLISHED set** (review R-3).  `Subst.scala:2136` is not one: it solves the discarded `extinct`
  half.  The residual that becomes `pruned` has passed through `Subst.solve` earlier in inference, and
  S2 layer (iii)'s certificate applies to whatever that solve accepted — but the constraint list handed
  to `Exists` at `:2184` is not re-decided anywhere, so the precondition must be recorded as an
  ASSUMPTION for the deletion pass, with two consequences: the pass should either call the per-label
  decision on the published set itself before deleting anything (one extra `LabelSearch` per scheme,
  cheap by §4.5's numbers) or state that an unsatisfiable published set makes every deletion vacuously
  `REquiv` and is therefore harmless for `faithful` while being useless.  Either way, if `rowSound.decide`
  gave no verdict the pass must keep everything.

**Where the argument fails, and what the oracle must return there**: a dropped given or a dropped
obligation whose variables `pxs` does not already exclude — KEEP; any `NoVerdict` — KEEP; a budget
lapse — KEEP; a candidate that is not a row constraint — KEEP (never ask).

### 4.2 What it decides on the six

Measured; per-constraint verdicts and costs in `<scratch>/v2-private-first.log` (no proxy),
`<scratch>/v2-private-proxy-first.log` (the weaker proxy of the first draft) and
`<scratch>/zfix-first.log` (the CORRECTED proxy, review R-1 — these are the figures of record).  The run
of record is `after3` (E11a's fix round), except `lookbackJoin`, which the `after3` sweep does not carry
— `after`/`after2` are used for it.  Sizes count the class constraints, which are never candidates
(13 of them in `cutoffGroupedFldsPosNegRel'`, 2 in each `Yahoo` binding).

| binding (pair) | the leftover the probe named | (A) with no proxy | (A) with the CORRECTED proxy |
|---|---|---|---|
| `reportFor` (all 5 sweeps) | B's `a <- (c) + (\|pMinValue,pRegion\|)` | **deleted** (`Ok`, `Cost(1,2,4)`) — and B then equals A | same; **converged** |
| `lookbackJoin` (3 sweeps) | one conjunct that follows by associativity | **deleted** — and 3 more redundant conjuncts with it, 8 -> 4 on one side, 9 -> 6 on the other | same; converged in 1 of 3 pairs |
| `joinCumRet` (`after3`) | folded-vs-unfolded `(\|initValue\|) <- (c, d)` group | A: nothing (every call `NoVerdict`, "one given was dropped as unreadable"); B: 1 deletion | A 7 -> 4, B 5 -> 4; two 4-cores differing in ONE folded/unfolded constraint over a universal |
| `joinTotalValue` (`after3`) | the same with `(\|initialInvestment\|)` | nothing on either side | A 6 -> 4, B 6 -> 4, sets still differ |
| `investmentTableData` (`after3`) | the same with `(\|initValue\|)` | A nothing, B 1 | A 13 -> 6, B 11 -> 6, sets still differ |
| `cutoffGroupedFldsPosNegRel'` (`after3`) | a row carried whole vs split in two | A 40 -> 34, B 40 -> 34 | A 40 -> 28, B 40 -> 29 |

Two things to read off this.  First, **the oracle is much stronger than the probe's leftover analysis
suggested**: on `lookbackJoin` it does not merely delete the one extra conjunct, it deletes every
constraint that a private existential makes free (`r2 <- (h, c1)` where `r2` occurs nowhere else,
`o <- (f, g)` likewise, and then `r1 <- (c1, d)` once `c1` and `d` have become private).  That is
`irredundant` (ROSE §4.2) doing its job, and it is a much bigger change to published signatures than
"delete the one conjunct that differs".  Second, **the proxy encoding is what makes the `Yahoo` family
decidable at all**: without it every call on those three is `NoVerdict` for the same reason (an
unreadable given), with it there is not a single `NoVerdict` anywhere in the corpus — and with `z`
EXISTENTIAL rather than rigid it decides 88 of the 140 concrete-left-hand-side candidates instead of 30
(§12, R-1).

### 4.3 The proxy encoding, precisely

`SigEntail.scala:435-437` already names it: "a fresh determined variable `z` with `z <- (parts)` and
`z <- (C)`".  Concretely, in `encode`, `(|K|) <- (p1..pn)` with `K` non-empty becomes two `Row`s over
one fresh `z` (one `z` per distinct `K` per call, so two occurrences of `(|initValue|)` share it).
Verdict-preserving in both directions because `z` is fully determined by `z <- ((|K|))`: the models of
the original variables are unchanged, which is the same argument the probe used for its Lean proxies
(§3.1 of `E11b-PROBE.md`).

**`z` is an EXISTENTIAL and must be in the pool `pxs` is drawn from** (review R-1; the first draft said
the opposite and measured the opposite).  It is a DEFINED auxiliary: for an OBLIGATION, `z`'s definition
`z <- ((|K|))` travels inside `W`, and unless `z` may be chosen, `check` branches over it in `extra`
(`SigEntail.scala:533`) and refutes at the first node — so every candidate with a concrete left-hand
side whose `K` heads no OTHER constraint came back `NotEntailed` at 1-3 nodes although it is entailed.
Soundness is untouched by the correction, because the private-`pxs` filter is computed over the ACTUAL
givens: whenever a given mentions the same `z`, `z` is in `vars(Q)` and stays rigid, exactly as it must.

Measured effect over the 751 row calls (`<scratch>/cost-summary.txt`, `<scratch>/zfix-cost-summary.txt`):

| | `NoVerdict` | `Ok` | `NotEntailed` | of the 140 concrete-lhs candidates, `Ok` | mean nodes | mean ms |
|---|---|---|---|---|---|---|
| no proxy | 426 | 214 | 111 | — | 756 | 0.46 |
| proxy, `z` rigid (first draft) | 0 | 394 | 357 | 30 | 133 | 0.19 |
| proxy, `z` existential (**correct**) | 0 | **452** | 299 | **88** | 133 | 0.20 |

### 4.4 Determinism given E11a's canonical input order

* `canonRows` (`SigEntail.scala:654`) sorts by `canonKey`, and `canonKey` (`:650`) is
  `varShort(v) + "^" + v.id + " <- (" + … + ")"` — **it embeds the id**.  `canonVar` (`:646`) is
  `(varShort(v), v.id)`.  So the order in which constraints and branch variables reach
  `Constraints.LabelSearch` is a function of the source names FIRST and of the ids only as a
  tie-break — which is exactly what S3 review M2 wanted for the diagnostic, and one notch short of
  what E11b wants.
* The tie-break can change only WHICH refuting model or which obligation is found first, never whether
  one exists — so `Ok` / `NotEntailed` is a function of the constraint set alone.  It can change the
  VERDICT only by changing where a budget is exhausted, i.e. by turning a decision into `NoVerdict`.
  Measured margin on this corpus: worst call 5,265 decision nodes against a 200,000 class budget (38x)
  and 20 models against a 20,000 model cap (1,000x); the same call is 190x inside the 1,000,000-node
  per-call signature budget.  (Both budgets are per `check` CALL, not per scheme: a scheme's 27 calls
  each get their own.)  So no lapse is reachable here, and the id-dependence is
  unobservable — but it is a latent id-dependence, and Phase 2 should key the sort on E11a's own
  id-free `Canonical.key` instead (it exists, it is audited id-free, E11a-CANON §1 "Why it is id-free").
* Nothing else in `check` is order-sensitive: `labels` is `.distinct.sortBy(_.toString)` (`:499`),
  `qv`/`wv`/`F`/`rigidW` are `Set`s used only for membership, and `extra` is sorted (`:533`).
* The FIXPOINT's visiting order is the caller's, and that is the whole of §6.

### 4.5 Cost

`<scratch>/cost-summary.txt`, 751 oracle calls on row constraints per configuration, JIT-warm within
one JVM:

| | nodes max | nodes mean | models max | ms max | ms mean |
|---|---|---|---|---|---|
| `pxs=private`, no proxy | 5,265 | 756 | 20 | 54 | 0.46 |
| `pxs=private`, proxy | 589 | 133 | 12 | 45 | 0.19 |

Heaviest single pass: `cutoffGroupedFldsPosNegRel'` side B, 27 calls — 67,367 decision nodes on the
`canonall` pair and 62,690 nodes / 39 ms on the `after2` pair without the proxy encoding; 8,723 nodes
and 13 ms with it.  (The `ms max` of 45-54 is the first call in the JVM and is
warm-up, not work: the same constraint costs under a millisecond on a second pass.)

**Per-scheme total and the corpus projection.**  One fixpoint round is `|row constraints|` calls, and
rounds are at most deletions + 1.  The size distribution over the 1,301 signatures of the checked-in
`tracker/g1-baseline/browse.txt` (`<scratch>/size-distribution.txt`): **86.2 % carry no row constraint
at all**, mean 0.25, median 0, max 9, 325 row constraints in total.  So one pass over that baseline is
325 calls = 62 ms at 0.19 ms, and scaling by 4047/1301 = 3.11 to the corpus's published bindings, **one
pass over the corpus is about 1,000 oracle calls ≈ 0.2 s**; with two or three fixpoint rounds where
anything is deleted, **0.4-0.6 s**.  Against the ~10-14 s batch that is **1.6 % for a single pass and
3-5 % at two or three rounds** — above E11a's ~1 % floor, measurable, and worth an interleaved A/B at
adoption.  The two `cutoffGroupedFldsPosNegRel'`-sized bindings dominate: 27 calls and 39 ms each
without the proxy encoding, 3-13 ms with it.  Three caveats on the extrapolation (review R-6):
(i) the 4047/1301 scale factor assumes `browse.txt`'s six group libraries are representative of the
corpus's published bindings, which is unverified; (ii) the 0.19-0.20 ms mean comes from a set dominated
by the six pathological bindings, so it is pessimistic per call and optimistic about how many rounds an
ordinary binding needs; (iii) the R-1 correction produces MORE deletions and therefore more rounds, so
the upper end of the band is the one to plan against.  **Proposed budgets:** per constraint, leave
`classBudget = 200,000` / `sigBudget = 1,000,000` alone (38x headroom); per scheme, **200 oracle calls**
(7x the worst pass measured) and **a 100 ms wall cap**, either of which lapsing means KEEP EVERYTHING
STILL LIVE — not "keep the current one" — so that a lapse cannot make the result depend on where in the
scan the clock ran out.

---

## 5. The two caller-side corrections, measured

### 5.1 `pxs` must be the candidate's private existentials

Running the identical 751 calls with `pxs = every existential` and with `pxs = the candidate's private
existentials` differs on exactly **7 calls**, all on `cutoffGroupedFldsPosNegRel'`, and in all 7 the
whole-list version is the more permissive (`OK` against `NoVerdict`).  `<scratch>/pxs-diff.txt`.  The
cleanest witness, `after:cutoffGroupedFldsPosNegRel'` side A, constraint 20:

    candidate      t <- (e3, d3, ro1)
    elsewhere      c4 <- (d3, e3)          l <- (m, n, d3)          (|cutoff|) <- (ro1, e3)

`(|cutoff|) <- (ro1, e3)` has a non-empty literal set on the left, so `encode` drops it and `ro1` is
absent from `vars(Q)`.  With `pxs = pubExts`, `ro1` lands in `F` and the check accepts by re-choosing
it — but `ro1` is pinned by the dropped given (`{cutoff} = ro1 ⊎ e3`), so the witness is not a licensed
move and the acceptance is not a proof of `DELETABLE`.  With `pxs` = the private set, `ro1` is excluded
(it occurs elsewhere) and the verdict is `NoVerdict` = KEEP.  This is a hole in the sketch, not in
`SigEntail`: `check`'s own no-verdict discipline reasons about `Q` and `W` but not about the effect a
dropped given has on `F`.

**The review's witness is stronger, and it is the one to quote** (R-5, `<rev>/synth.txt` case
`synth:pxsUnsound`; re-run here as `<scratch>/zfix-synth-all-off-first.log`).  Universals `{a}`,
existentials `{x, y}`,

    sys = { (|k|) <- (x, y),   a <- (x) }

With `pxs = every existential` and no proxy encoding, `check` returns `Ok` on `a <- (x)` in one node
and the fixpoint deletes it.  But the residual before the deletion forces `a ⊆ {k}` (through
`x ⊎ y = {k}`), and after it `a` is unconstrained — so the deletion is **not `REquiv`**.  That is a
real soundness failure of the orchestrator's sketch, not merely an acceptance without a proof; my own
witness above shows only the latter.  With `pxs` = the private set the same call is `NoVerdict` = KEEP
(`<scratch>/zfix-synth-priv-first.log` with the proxy off gives the same shape).  Note the interaction
the first draft did not state: the **proxy encoding closes this particular instance by itself**,
because it makes `(|k|) <- (x, y)` readable and `x` therefore a member of `vars(Q)` — with the proxy on,
both `pxs` modes correctly answer `NotEntailed` (`<scratch>/zfix-synth-all-first.log`,
`zfix-synth-priv-first.log`).  Private `pxs` is still required for the Unreadables the proxy does not
cover (several literal column sets on one right-hand side, `SigEntail.scala:335`) and for class
constraints, which raise no caveat at all.

### 5.2 Only row constraints may be candidates

`check` with an obligation it cannot encode and no caveat returns `Ok` (`SigEntail.scala:455-456`: if
`wRows` is empty, `caveatW.fold(Ok)(...)`).  A class constraint encodes to `NotRow`, which raises no
caveat by design (it is "out of scope", `:367`), so the fold returns `Ok`.  The first run of the driver
did exactly what that implies — it deleted all 140 class constraints of the corpus
(`<scratch>/run-private.log`, e.g. `cutoffGroupedFldsPosNegRel'` 40 -> 20).  Every later run filters
candidates to row constraints.  A Phase-2 implementation must do the same, or better, `check` should
grow a `NotRow`-means-no-verdict mode for this caller.

---

## 6. THE CONVERGENCE QUESTION

**The rule assumed.**  Visit the constraints in E11a's canonical key order; the FIRST deletable one
goes; restart the scan from the top; stop when a whole scan deletes nothing.  On a post-E11a rendering
the printed order IS the canonical key order (E11a-CANON §1 rules 3-4), so the driver uses the printed
order and needs no re-derivation of the key.  Two variations were simulated as well: **last** (the same
scan from the end, i.e. descending canonical key) and **min** (explore every fixpoint reachable by
deleting one deletable constraint at a time, memoised on the surviving set, and take the smallest,
tie-broken by an id-free shape key).

**The answer, per pair**, with the CORRECTED proxy encoding (`z` existential, review R-1).
`<scratch>/zfix-first.log`, `zfix-last.log`, `zfix-min.log`, compared with `<scratch>/cmpfinal.py`:

| pair (5 sweeps x the bindings that appear in them) | first | last | min |
|---|---|---|---|
| `reportFor` x 5 | SAME x5 | SAME x5 | SAME x5 |
| `lookbackJoin` x 3 (`before`, `after`, `after2`) | SAME 1 (`before`) | SAME 2 | SAME 3 |
| `level1` x 1 | SAME (nothing deleted) | SAME | SAME |
| `investmentTableData` x 5 | SAME 1 (`after`) | SAME 1 (`after`) | DIFFERENT x5 |
| `joinTotalValue` x 5 | SAME 1 (`after`) | SAME 1 (`after`) | DIFFERENT x5 |
| `runningTotalFull`, `…ViaWritten` x 2 each | DIFFERENT | DIFFERENT | **SAME x4** |
| `joinCumRet` x 3 | DIFFERENT x3 | DIFFERENT x3 | DIFFERENT x3 |
| `cutoffGroupedFldsPosNegRel'` x 5 | DIFFERENT x5 | DIFFERENT x5 | DIFFERENT x5 |
| **total of 31** | **9** | **10** | **13** |

`pxs=private`, proxy on, `z` EXISTENTIAL.  The same three rules with the first draft's weaker proxy
(`z` rigid, never in `pxs`) gave 7 / 8 / 13 — see §12, R-1; with `pxs=all` the total is 7.  Note that
the three rules' SAME-sets are **not nested**: `first` and `last` converge
`after:investmentTableData` and `after:joinTotalValue`, which `min` does not, while `min` converges the
four `runningTotal*` pairs, which they do not.

**Does the answer depend on the rule?**  Yes — on `lookbackJoin`, on the two `after` Yahoo pairs, and
on `runningTotal*`.  The mechanism is
worth stating because it is the general shape of the problem.  In `after:lookbackJoin` the two variants
are `A` (8 constraints) and `B` (9 = A's information plus the `h`-pair `h <- (r,i,c)`, `h <- (c1,d,i)`
in place of A's `t`-pair).  Scanning forward, B's very first constraint `r1 <- (r, c)` is already
deletable (it follows from the `h`-pair plus `r1 <- (c1,d)`), and deleting it strands the `h`-pair,
which then cannot go; B stops at 6 while A reaches 4.  Scanning BACKWARD, the `h`-pair and the two dead
existentials go first, `r1 <- (c1, d)` follows once `c1`,`d` are private, and B reaches A's 4.  So the
rule that works here is "prefer to delete the LAST constraint in canonical order", and the reason it
works is that E11a's key order puts the small, universal-headed constraints first and the long,
existential-headed ones last, so a backward scan removes the derived material before the material it is
derived from.  **It does not generalise**: on `before:lookbackJoin` the backward rule is the one that
fails and the forward rule succeeds (7 vs 8 in the table is exactly this trade), and neither ordering
helps any other binding.  The exhaustive-minimum rule gets all three `lookbackJoin` pairs, and it costs
**257,536 oracle calls and 62 s on one binding** (`canonall:cutoffGroupedFldsPosNegRel'` A,
`<scratch>/zfix-min.log`) against 27 calls and 3 ms for the greedy rule — four orders of magnitude, for
13 pairs instead of 9.  It is not a shippable rule.

**And `min` is order-free without being convergent** (review R-4, reproduced here as
`<scratch>/zfix-synth-priv-min.log`).  The review's synthetic three-cycle: variant A =
`{x <- (y), y <- (z), x <- (z)}` and variant B = `{x <- (y), y <- (z)}`, equivalent, every variable a
universal.  All three of A's constraints are individually deletable, and the three rules land on three
different fixpoints — `first` deletes `x <- (y)` and lands on `{y <- (z), x <- (z)}`; `last` deletes
`x <- (z)` and lands exactly on B; **`min` deletes `y <- (z)` and lands on `{x <- (y), x <- (z)}`,
which is neither variant**.  So `min`'s 13 of 31 is a property of this corpus and of the shape
tie-break, not a principle: being a function of the set (order-free) says nothing about landing on the
same set as an equivalent input, which is what convergence needs.  Earlier drafts of this report called
`min` "the rule that gets all three"; that is true only of `lookbackJoin` and must be read with this
caveat.

**The 12 CONTROL pairs: the rule is order-robust, and the blast radius is large.**
`<scratch>/ctrl.txt` re-extracts the probe's twelve control bindings — FORM-class records from the
pre-E11a sweep, i.e. ONE constraint set rendered TWO ways (different constraint order, different
right-hand-side order, different letters).  Under the recommended configuration the oracle's fixpoint
lands on the **same set from both forms in 11 of 11** comparable pairs (`<scratch>/zfix-ctrl-first.log`
with the corrected proxy, and `<scratch>/ctrl-private-proxy-first.log` before it — identical outcome;
the twelfth, `stacked1`, has an empty constraint set and nothing to compare).  That is the evidence
that the greedy rule does not CREATE set-class differences — and it is stronger evidence than the
post-E11a case needs, because after E11a two renderings of one set arrive in the SAME order and a
deterministic pass then cannot differ at all.  What the same run shows, and what matters for adoption,
is the **blast radius**: 3 of those 12 ordinary bindings lose constraints — `melt3Full` and
`melt3FullViaDeduped` 23 -> 20 each, `yearFrac365Full` 5 -> 4.  A quarter of the constraint-carrying
bindings in a random sample changes its published signature.  E11b is not a surgical fix to six
bindings; it rewrites the interface of a large fraction of the corpus, and the `.ei` gate has to be
read with that in mind.

**A variant landing on a set that is neither A nor B.**  This is the normal case, not the exception.
`after3:joinTotalValue` under the recommended rule: A 6 -> 4 and B 6 -> 4, and the two 4-constraint sets
are neither the original A nor the original B and are not equal to each other.  `canonall:joinCumRet`
goes A 6 -> 4 and B 6 -> 4, again two different 4-sets.  The pass is a genuine simplifier, and what it
publishes is a third thing.

**Why the survivors cannot be fixed by any choice rule.**  Under the exhaustive-minimum rule — which by
construction is a function of the set and the tie-break — the cores still differ:
`after3:cutoffGroupedFldsPosNegRel'` reaches 25 on one side and 28 on the other, so the cardinalities
themselves differ; `after3:joinCumRet` and `after3:investmentTableData` reach 4 and 4, and 6 and 6, so
there the cardinalities AGREE and the SHAPES do not.  Two `REquiv` residuals can have irredundant cores
of different cardinality, and when they have the same cardinality they can still have different shapes.
That is the P = NP argument of ROSE §4.3 showing up as a measurement: `OrderIndependent` is not
achievable, and pass (ii) alone is not a canonicaliser.  **Deletion is not enough; the survivors have
to be REWRITTEN into a common form** — oriented definitional substitution for the `Yahoo` three
(probe §5.3; and §1's `after3:joinCumRet` specimen, where the one differing constraint is a fold over a
UNIVERSAL and is therefore untouchable by deletion) and un-splitting for
`cutoffGroupedFldsPosNegRel'` (probe §5.4).

---

## 7. Candidate (B) — the row solver on the negation.  REJECTED

The proposal is `solve(Exists(l, Nil, Q ∪ enc(¬c)))` unsatisfiable ⇒ `c` entailed.  It fails at
`enc`, and the failure is not a matter of effort.

* **Which shapes of `c` admit an encoding: essentially none.**  The constraint language has
  partitions and nothing else.  `c = a <- (p1..pn)` is refuted by any of three kinds of witness —
  a column in `a` and in no `pi`, a column in some `pi` and not in `a`, or a column in two different
  `pi` — and each of those is a NEGATIVE fact about one label.  The language can state "label `l` is in
  `a`" (`a <- (z, (|l|))` with `z` fresh) but has **no way to state "`l` is not in `a`"**: the only
  negative facts expressible are `x <- ()` (x empty) and `x <- ((|l|))` (x exactly `{l}`), neither of
  which is the complement of anything.  So `¬c` is a clause over per-label bits, which is what ROSE
  §4.6 says: "`¬c` is not a partition constraint — it is a Boolean clause over the per-label bits".
* **SIG-ENTAIL-PLAN's refutation trick does not do this job.**  `Q ∪ {sk' <- (sk, L)}` unsatisfiable
  iff `L ⊆ sk` (SIG-ENTAIL-PLAN, "The missing judgement") decides ONE positive containment for ONE
  shape, the `concrete-ext` shape, and its own S2 measurement puts that at 4.7 % of the obligations it
  was aimed at.  It decides "`Q` refutes this extension", which is `Q |= ¬c`, not `Q |= c`; the two
  coincide only for the containment shape, where the extension's unsatisfiability IS the containment.
  Nothing in the corpus's leftover constraints has that shape (`lookbackJoin`'s leftover is a
  three-part partition of existentials; `reportFor`'s needs the existential to be projected away, which
  the trick cannot express at all).
* **Refutation incompleteness would make a non-failure meaningless** — `solve` reaching `.done` on a
  residual it never refuted is the documented MIN1 mechanism (ROSE §1.4) — **but the complete per-label
  decision changes that**, and this is the interesting part of the answer: S2 layer (iii)'s
  `rowSound.decide` gives a SOUND satisfiability verdict when it gives one, on by default since
  2026-09-06.  So the objection about incompleteness is answered.  What is NOT answered is the encoding,
  and the engine that would do the work — `Constraints.LabelSearch`, the one-hot per-label search — is
  **precisely the engine `SigEntail.check` already drives**, with the additional machinery (`F`, the
  per-class loop, the no-verdict discipline, the model cap) that (B) would have to grow from scratch.
* **Verdict.** (B) is not a third candidate; it is candidate (A) with the no-verdict discipline
  removed and the existentials forgotten.  Rejected.

---

## 8. Candidate (C) — a small saturating decision procedure

`<scratch>/candC.py`, a Python prototype over the probe's `cases.json` (systems already converted to
`(lhs, vars, labels)` with a proxy variable for every concrete left-hand side; class constraints not
present).  Read `a <- (b, c) + K` as `a = b ⊎ c ⊎ K`.  `DELETABLE_C(c)` is claimed when

* **(0a)** `c`'s left-hand variable is an existential occurring nowhere else — the constraint only
  names a row nothing else refers to;
* **(0b)** every part of `c` is such an existential and there is no literal column demand — a free
  split;
* **(0c)** `c = a <- (privs…, rest) + K` with `privs` private existentials and some `q` in `Q` with the
  same left-hand side whose parts include `rest` and whose literal set includes `K` — a fresh
  existential matches any sub-partition.  **This is `reportFor`.**
* **(1)** some `q` in `Q` with the same left-hand side rewrites to `c` by **definitional substitution**:
  FOLD (a right-hand side containing every part of a definition `d` has them replaced by `d`'s
  left-hand side) and UNFOLD (a variable with a definition is replaced by that definition's parts),
  breadth-first to depth 4 with a 20,000-node cap.  **This is `lookbackJoin`** (`t = c1⊎d⊎h`, fold
  `c1,d` to `r1`, unfold `r1` to `r,c`) **and the `Yahoo` fold/unfold of a concrete group** through the
  proxy (`{initValue} = c ⊎ d`).

**Soundness.**  Every rule derives an equation that is a consequence of the remaining equations, under
the existentials: (0a) and (0b) choose the unconstrained variable, (0c) chooses the private one to be
the complement, (1) is substitution of equals.  Shared existentials are never re-chosen (the privacy
test is exactly "occurs nowhere else").  A universal is never treated as private.  A concrete left-hand
side is a definition like any other, via the proxy.  Class constraints are outside the representation,
so a port must compute "occurs elsewhere" over them too or it will call a variable private that a class
constraint pins — the same trap as (A)'s `pxs`.  An unsatisfiable `Q` is not detected and the rules stay
sound (they derive consequences, and everything is a consequence of an unsatisfiable set).  A depth or
node lapse returns "not deletable" = KEEP.  It is **incomplete** by construction: it cannot see any
consequence that needs case analysis over labels, which is most of what (A) decides.

**What it decides.**  `<scratch>/candC-first.log`, `candC-last.log`, `candC-min.log`.  Over the 31
genuine pairs: **11 converge under `first`, 9 under `last`, 15 under `min`** — slightly better than (A)
on the same rules, because (C)'s rewriting sees folds that (A)'s per-label reasoning also sees but that
(A)'s greedy scan spends differently.  The 12 CONTROL pairs (bindings whose two renderings already
agreed) stay SAME under all three rules — the one piece of evidence available that a deletion pass does
not CREATE set-class differences.  `reportFor` 5/5 by rule (0c); `lookbackJoin` 3/3 by rule (1) under
every choice rule, which is better than (A) manages greedily; the `Yahoo` three and
`cutoffGroupedFldsPosNegRel'`: never.

**Bound and lapse.**  Depth 4 / 20,000 nodes per candidate; measured, no case reached either (the
deepest derivation used is `lookbackJoin`'s, two steps).  A lapse means KEEP.

**Why it is not the recommendation.**  It is a second, unverified implementation of a fragment of what
`SigEntail` already decides, with its own soundness obligation, its own budget and no Lean statement;
it buys 15 pairs where (A)+proxy buys 13; and it would still leave the same four bindings open.  Its
real value is as a **cheap pre-pass**: rules (0a)/(0b) are pure reachability and would delete the bulk
of what is deletable with no solver call at all — `mkSimplified`'s `isolated` already does the
transitive-reachability half of (0a) (`Subst.scala:2087`).  Worth keeping in the drawer, not worth
shipping alone.

---

## 9. Phase 2 sketch (if the user opens E11b)

* **Where the loop goes.**  NOT inside `mkSimplified`.  `mkSimplified` runs at `Subst.scala:1776`
  BEFORE `Canonical.scheme` (`:1793`), so inside it the constraint list is still in id order and the
  visiting rule would not be the canonical one — and §6 shows the visiting rule decides the result.
  The pass belongs in `generalize`, **after** `Canonical.scheme`, guarded by `publishing`, working on
  the canonicalised `Forall`'s `Exists`: delete to a fixpoint, then drop the existentials that no
  surviving constraint mentions, then re-run `Canonical.scheme` on the result (which is what makes it
  idempotent — see below).  The `extinct` solve stays where it is, inside `mkSimplified` — but note it
  covers the DISCARDED constraints only (§4.1, review R-3), so it is not the satisfiability certificate
  the oracle's precondition wants; `deleteTautologies` (`:2060`, publishing-only) stays as the model for
  the guard, not as the site.
* **"Idempotent" in code** means: `F(F(R)) = F(R)` as a rendering.  With deletion to a fixpoint it is
  automatic for the constraint SET (a second pass finds nothing deletable) but NOT for the FORM: the
  binder letters change when an existential disappears, so `Canonical.scheme` must run again after the
  deletions.  The property to test is two passes of the whole pipeline producing byte-identical
  renderings, on the corpus, the way E11a's form property is written.
* **"Keep on lapse" in code** means: any `NoVerdict`, any budget exhaustion, any candidate that is not
  a row constraint, and any per-scheme cap — **abandon the whole scheme's deletions**, publishing the
  set as it was when the pass started, not the partially deleted set.  Otherwise the published set
  depends on where the clock ran out, which re-introduces exactly the run-to-run variation E11 is about.
* **What the `.ei` classification will have to show.**  Every deletion changes an interface.  The gate
  is the complete per-label decision tooling (`ROW-CONSTRAINT-STATE.md` A1): each moved binding must be
  classified EQUIVALENT — `REquiv` both ways, ROSE §4.2 `faithful` — and anything weaker or stronger is
  a stop.  Note the scale: this is not a handful of bindings.  `lookbackJoin` alone goes from 8 or 9
  constraints to 4, `investmentTableData` from 13 to 6 and `joinCumRet` from 7 to 4
  (`<scratch>/zfix-first.log`).  `ei-classify.py` will have to be fixed first
  (E11a-REVIEW's follow-up: its matcher AND its parser are broken on 47 interfaces) or the gate cannot
  be read.  `g1-validate.sh`'s baseline will need a re-cut, and the diff will be large rather than
  alpha-only.
* **A Lean target, if any.**  The one worth stating is small: given an oracle that is sound for
  `REntails`, deleting an entailed constraint preserves `REquiv` — i.e. `faithful` for the deletion
  rule.  In ROSE §4.2's vocabulary it is `REquiv R <R.ex, R.sys.erase c>` from
  `REntails <R.ex, R.sys.erase c> R`, which is one direction by hypothesis and the other by
  monotonicity of `Holds` in the system.  That is a few dozen lines against `Residual`/`Holds`/`REntails`
  as ROSE §4.1 defines them, and it says nothing about the oracle itself.  Proving the ORACLE sound
  (`SigEntail`'s `sigEntails_of_lsig` already exists for the signature judgement; what is missing is the
  bridge from `SigEntails Q W F` with `F` private to `REntails`) is a stage of its own and is the part
  worth doing, because it is precisely the step §5.1 shows is easy to get wrong.  Estimate: the bridge
  lemma one stage; `faithful` for the rule half a stage.
* **The survivors to exempt by name**, in the comparators (`ei-classify`, `g1-diff`, `trace-ab`) and in
  the E11a form test's SET allow-list, after E11b as specified: `Yahoo.e:joinCumRet`,
  `Yahoo.e:joinTotalValue`, `Yahoo.e:investmentTableData`,
  `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`, plus the three intermittent bindings that
  could not be measured here (`Layout/Report.e:drilldownKeyValueTable2`,
  `incomplete/RevenueShare.e:shareOfGroup`, `incomplete/np01_add_or_recompute.e:inferredRestate`), and
  `Relation.e:lookbackJoin`, which the RECOMMENDED greedy-first rule closes in only 1 of its 3 measured
  pairs.  Only `Present/WriterOutputs.e:reportFor` comes off the list under that rule — the exemption
  list shrinks by one, from six to five.
* **The cheap alternative remains on the table.**  The roadmap's own fallback — exempt the SET class by
  name in the comparators and stop hand-classifying it — buys the same review relief as E11b for none
  of the risk, and E11b-as-specified's measured yield under the recommended rule is **1 of 6**
  (`reportFor`), with a further 2 of 6 within reach of E11b-plus-normalisation (§1).

---

## 10. Every claim's log

All under `<scratch>` =
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle/`.

| file | what it is |
|---|---|
| `START-TIME.txt` | the 3 h budget's start |
| `sbt-compile.log` | `sbt core/compile core/copyResources`, exit 0 |
| `mkinput.py`, `cases.txt` | the 31 pairs re-parsed with concrete left-hand sides, multi-concrete parts and the 140 class constraints kept |
| `OracleDriver.scala.txt`, `OracleDriver-zfix.scala.txt` | the throw-away driver's source before and after the R-1 one-line fix, kept for the record (the file under `core/src/test` is deleted) |
| `run-private.log` | first run, `pxs=private`, no proxy, class constraints wrongly offered as candidates — the evidence for §5.2 |
| `run-all.log`, `run-private-proxy.log`, `run-all-proxy.log` | the same first-generation runs in the other three configurations |
| `v2-private-first.log` | the measurement of record: verdict + `Cost` + ms for every row constraint of every pair, `pxs=private`, no proxy, greedy-first fixpoint |
| `v2-private-proxy-first.log` | the same with the proxy encoding — the recommended configuration |
| `v2-private-last.log`, `v2-private-proxy-last.log` | the backward choice rule |
| `v2-all-first.log` | `pxs = every existential`, for §5.1 |
| `v2-private-proxy-min.log` | the exhaustive-minimum rule with the PRE-R-1 proxy (13/31, 257,536 calls, 60 s on the worst binding); superseded by `zfix-min.log` |
| `cmpfinal.py` | final-set comparison up to a renaming of existentials |
| `cost-summary.txt` | the cost table of §4.5 and the verdict counts |
| `pxs-diff.txt` | the 7 calls where `pxs=all` and `pxs=private` disagree |
| `size-distribution.txt` | row-constraint distribution over `tracker/g1-baseline/browse.txt` (1,301 signatures) |
| `candC.py`, `candC-first.log`, `candC-last.log`, `candC-min.log` | candidate (C)'s prototype and its three rules |
| `mkctrl.py`, `mkinput_lib.py`, `ctrl.txt`, `ctrl-private-proxy-first.log` | the 12 FORM-class control pairs and (A)'s run on them |
| **the R-1 fix round** | |
| `zfix-all-runs.log`, `zfix-min-and-synth.log` | the two raw `sbt` invocations of the fix round (seven and two runs), exit 0 |
| `zfix-first.log`, `zfix-last.log`, `zfix-min.log` | the 31 pairs with `z` EXISTENTIAL under the three choice rules — **the figures of record** (9 / 10 / 13 of 31) |
| `zfix-ctrl-first.log` | the 12 controls re-run with the corrected proxy (11 of 11 SAME, unchanged) |
| `zfix-cost-summary.txt` | verdict and cost counts before vs after the correction (Ok 394 -> 452; concrete-lhs Ok 30 -> 88 of 140) |
| `zfix-cmp.txt` | `cmpfinal.py` on the three corrected runs, side by side |
| `zfix-synth-priv-first.log`, `zfix-synth-all-first.log`, `zfix-synth-priv-last.log`, `zfix-synth-priv-min.log`, `zfix-synth-all-off-first.log` | the review's two synthetic residuals re-run here: R-4's three-cycle under all three rules, R-5's soundness witness with the proxy on (closed) and off (`Ok`, deleted, not `REquiv`) |
| `<rev>/` (the reviewer's) | `zfix*.log`, `synth.txt`, `synth-and-rules.log`, `cmpfinal-rerun.txt` — the independent runs this fix round reproduces |

Inputs read, unchanged: `<prev>/pairs/*.txt`, `<prev>/cases.json`, `<prev>/conv.py`, `<prev>/leftover.log`,
`<prev>/../e11a/logs/sweep-*.tsv`, `tracker/g1-baseline/browse.txt`,
`core/src/main/scala/com/clarifi/reporting/ermine/{SigEntail,Subst,Type,Vars}.scala`,
`tracker/{GATE-POLICY,ROSE-COMPARISON,SIG-ENTAIL-PLAN,LSP-ROADMAP,TICKET-stdlib-findings}.md`,
`tracker/loopmodel/{E11b-PROBE,E11a-CANON,E11a-REVIEW}.md`.

**Time spent: about 25 minutes** for the phase itself (`<scratch>/START-TIME.txt`: 19:29:37 to
19:54:25 on 2026-09-13, this machine's clock) against a 3 h budget, of which roughly half was the five
`sbt core/Test/runMain` measurement passes; **plus about 15 minutes for the review fix round**
(20:13:24 to 20:28) against its 45 min budget, almost all of it the two re-measurement invocations.
Nothing was cut for time; the items below are outside what a no-source-change phase can reach.

## 11. NOT DONE

* **The three intermittent bindings were not measured.**  Their two renderings are in no sweep (§3);
  recovering them is a compiler run with a patched printer.
* **No control run on bindings that render IDENTICALLY.**  The twelve controls that were run (§6) are
  FORM-class pairs — one set in two forms — which is the harder test and passed 11/11; but the corpus's
  3,900-odd bindings whose two cold checks already agree were not exercised at all, and their risk is
  the blast radius (§6: 3 of 12 sampled bindings lose constraints), not divergence.
* **No corpus run, no `.ei` comparison, no perf A/B.**  This phase measured the oracle on recovered
  renderings only; nothing was compiled with a deletion pass in it, because nothing was implemented.
* **The proxy encoding was measured as a caller-side rewrite**, not as a change to `encode`.  The two
  are equivalent for these systems, but a real `encode` extension has to decide where `z` comes from
  (a `Supply` reaches `check` only through its callers) and must keep `z` out of `pxs`.
* **No Lean was written or built** (`lake build` was never run, per the brief).
* **Candidate (C) was NOT re-measured with the R-1 correction.**  `candC.py`'s proxy is an ordinary
  variable of its own representation and its (0a)/(0b)/(0c)/(1) rules never quantify over it, so the
  defect does not obviously apply — but its 11 / 9 / 15 figures were produced before the correction and
  are left standing as such.  The reviewer did not read or re-run (C) either.
* **The satisfiability of the PUBLISHED residual is an assumption, not a discharged precondition**
  (§4.1, review R-3).  Deciding it costs one extra per-label search per scheme; that was not measured.

---

## 12. Review corrections (E11b-ORACLE-REVIEW.md, applied)

The review (`tracker/loopmodel/E11b-ORACLE-REVIEW.md`, ACCEPT WITH FIXES) is confirmed on every point;
its logs are in `<rev>` = the sibling scratch `e11b-oracle-review/`.  Everything below was re-measured
here, not taken on trust, with the driver's one-line change (`ex += z`) and the identical `cases.txt`.

* **R-1 (blocking) — CONFIRMED and applied.**  The measured proxy minted `z` as a rigid `Free` variable
  and never added it to `ex`, so `pxs` could never contain it and `check` branched over it in `extra`
  and refuted at the first node; §4.3's verdict-preservation argument needs the proxy to be an
  EXISTENTIAL for an obligation.  Re-measured with `ex += z`: concrete-left-hand-side candidates
  accepted **30 -> 88 of 140**, all row candidates accepted **394 -> 452 of 751**, convergence
  **first 7 -> 9**, **last 8 -> 10**, **min 13 (unchanged)** — every number the review predicted,
  reproduced independently (`<scratch>/zfix-cost-summary.txt`, `zfix-cmp.txt`).  `after:investmentTableData`
  (15 -> 6 and 13 -> 6) and `after:joinTotalValue` (7 -> 4 and 6 -> 4) now converge, and
  `after3:joinCumRet` becomes A 7 -> 4 / B 5 -> 4.  Changed: §1 (recommendation and headline), §2 (all
  three rows), §4.2 (table), §4.3 (rewritten, with the before/after verdict table), §6 (convergence
  table and totals), §9 (the `.ei` scale figures and the exemption list), §10 (new logs), §11.
* **R-2 (blocking) — CONFIRMED and applied.**  "SET 6 -> 4" was not what the recommended greedy-first
  rule achieves.  Replaced in §1 by a per-binding, per-sweep-pair convergence table under the named
  rule (9 of 31 pairs; `reportFor` 5/5, `lookbackJoin` 1/3, `investmentTableData` 1/5,
  `joinTotalValue` 1/5, `joinCumRet` 0/3, `cutoff` 0/5) and by the stated ceiling **SET 6 -> 5 on the
  run of record**.  §9's closing line moves from "2 of 6" to "1 of 6".
* **R-3 — CONFIRMED and applied.**  `Subst.scala:2136` solves `extinct`, the constraints being thrown
  away at the `:2131-2133` partition, not the published `pruned`.  §4.1's two sentences are corrected:
  the ROSE §4.6 satisfiability precondition has **no named discharge site for the published set** and is
  recorded as an assumption, with the cheap remedy (one per-label decision per scheme) and the benign
  failure mode spelled out.  §9's "the `extinct` solve stays where it is" is annotated accordingly.
* **R-4 — CONFIRMED and applied.**  The review's three-cycle re-run here
  (`<scratch>/zfix-synth-priv-{first,last,min}.log`): `first` lands on `{y <- (z), x <- (z)}`, `last`
  lands exactly on variant B, `min` lands on `{x <- (y), x <- (z)}`, which is neither variant.  §6 now
  records that `min` is order-free but **not** convergent and withdraws the phrase "the rule that gets
  all three" except of `lookbackJoin`.  The corrected measurement adds a second reason: the three rules'
  SAME-sets are not nested (`first`/`last` converge two pairs `min` does not).
* **R-5 — CONFIRMED, stronger witness adopted.**  §5.1 now carries the review's
  `sys = { (|k|) <- (x, y), a <- (x) }` alongside the `cutoffGroupedFldsPosNegRel'` one, re-run here
  (`<scratch>/zfix-synth-all-off-first.log`): with `pxs = all` and no proxy the fixpoint deletes
  `a <- (x)`, which is a genuine `REquiv` failure, not merely an unlicensed acceptance.  The interaction
  the review points out is stated too: the proxy encoding closes that instance by itself, and private
  `pxs` remains necessary for the Unreadables the proxy does not cover and for class constraints.
* **R-6 — applied.**  §4.5 now gives the band as "1.6 % for one pass, 3-5 % at two or three rounds" and
  carries the review's three caveats (representativeness of `browse.txt`, the mean being dominated by
  the six pathological bindings, and the R-1 correction implying more rounds).
* **R-7, R-8 — confirmations, no change** beyond R-1/R-3's consequences.  The review re-derived every
  code citation (`F` `:491`, the `Ok` trapdoor `:455-457`, `encode` `:360`/`:367`, budgets `:397-398`,
  `canonKey` `:650` embedding `v.id`, placement `:1776` vs `:1793`) and found them correct.
* **Not re-measured in this round**, and listed in §11: candidate (C) under the corrected encoding;
  the satisfiability decision's cost; everything on the review's own "did NOT check" list.
