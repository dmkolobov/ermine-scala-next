# S5 — residual hygiene: the tautology deletion (ticket C12) and a solver-configuration key on the `.ei` cache

Stage S5 of `tracker/LOOP-MODEL-PLAN.md`; brief `tracker/loopmodel/briefs/brief-S5.md`.
Branch `scala3-migration`, from `fbab51b`.  Nothing committed by this stage.

## 0. Outcome

> **SUPERSEDED BY THE FOLLOW-UP SECTION AT THE END OF THIS FILE (2026-09-09).**  The
> deletion was confined to the generalisation that publishes a MODULE's signatures, criterion
> (c) is then MET — **identical 3,477, other 4**, and with the interface key stripped exactly
> one file of 268 differs on exactly four lines — and **`-Dermine.tautoDelete` is DEFAULT ON**.
> §1 below is the record of the first, unrestricted implementation and its measurement; read
> it for the theorem and the criterion, and read "Follow-up: publishing-only deletion" for
> what shipped.

**S5.1 — as first implemented: PARTIAL, by the brief's own rule.**  The theorem is proved and
the deletion is implemented at exactly its side condition, but the brief's adoption criterion
(c) — *"EXACTLY the five signatures shorten and every other interface is byte-identical"* —
was **not met by the unrestricted deletion**, which is why it first shipped behind
`-Dermine.tautoDelete` DEFAULT OFF.  Three things the measurement says that the ticket did not:

1. It is **four** signatures, not five.  `Layout.Scan.sumBy'` no longer publishes the
   tautology: stage F3 deleted it **by hand** from `Relation/Scan.e`'s written signature
   (the comment at `Relation/Scan.e:113-117` names C12 as the general fix).  C12's text was
   written in R3's commit `a79dd6f` (2026-09-07) and F3's hand fix landed the day after in
   `775a20f`, so the list of five was one out of date before this stage started.
2. A **fifth stdlib signature moves anyway**: `Layout.Report.Relation.cutoffGroupedFldsPosNegRel'`
   goes from 40 constraints / 40 published existentials to 38 / 37 — and **not** by deleting
   any constraint of its own published set (no constraint there satisfies the criterion).
   `mkSimplified` runs at EVERY generalisation, not only at the one that publishes a binding,
   so an intermediate residual loses a tautology and the final one comes out a different
   shape.  Each individual deletion is licensed by the theorem; what is **not** established
   is that the composite is confined to the signatures C12 names.
3. Behind those, 13 further bindings across five interfaces move as alpha-variants or
   constraint-order churn — the ordinary id-shift a change in minting produces.

**S5.2 — GREEN.**  A published `.ei` is now keyed by `<interface format version>|<GenRules>`,
written as the file's first line and checked on the same path that already decides currency.
A mismatched or missing key is stale exactly as a newer source is: full recheck, rewrite.

**Final state of the stage: both parts GREEN.**  S5.2 as below; S5.1 adopted DEFAULT ON after
the publishing-only restriction.  Gate numbers for the first implementation are in §3 and for
the adopted one in the follow-up section; every one of them is green — `lake build` 870 jobs and 4,596
theorems at 0 non-standard axioms, `TestLoopTrace` 720/720, `corpus-run --batch` 85/69/0 at
BOTH flag settings, `core/test` 940/940, the `boot` and `Wide` row traces byte-identical to the
pre-change compiler, `sql-render` byte-identical, `repl-smoke` and `lsp-smoke` (181 checks)
green.  The S5.1 verdict is a **criterion** judgement, not a failed gate.

---

## 1. S5.1 — the tautology deletion (ticket C12)

### 1.1 The theorem

`tracker/lean/Rowpartition/Determined.lean`, new section at the end of §8, in that file's
own `Residual` / `Holds` / `REquiv` vocabulary.

```lean
theorem tauto_delete {ex : Finset Var} {G : System} {r : Var} {P : Finset Var}
    (hne : P.Nonempty) (hr : r ∉ P) (hfresh : ∀ p ∈ P, p ∉ allVars G) :
    REquiv ⟨ex ∪ P, insert (mk r P ∅) G⟩ ⟨ex, G⟩
```

The GENERAL form the brief asked for: `k = P.card ≥ 1` existential parts, no concrete
labels (`mk r P ∅`), every part fresh with respect to the rest of the system, and the
left-hand side outside the parts.  The two-part instance C12 states is derived as

```lean
theorem tauto_delete_two {ex : Finset Var} {G : System} {r t h : Var}
    (hrt : r ≠ t) (hrh : r ≠ h) (ht : t ∉ allVars G) (hh : h ∉ allVars G) :
    REquiv ⟨ex ∪ {t, h}, insert (mk r {t, h} ∅) G⟩ ⟨ex, G⟩
```

C12's `t ≠ h` is **not** a hypothesis, and that is a fact rather than an omission: in the
`Finset` formulation `{t, h}` with `t = h` IS the singleton `{t}`, i.e. the `k = 1` case the
same theorem covers.  Note what that does *not* say — see the fourth exclusion below: a
SURFACE `r <- (t, t)` is a different constraint from `mk r {t} ∅` and is not a tautology.

**The witnesses.**  Backwards (the direction that does the work) the caller's assignment is
extended by `Tauto.wit`: one distinguished part `p₀` takes the whole of `rho r`, every other
part is `∅`.  That satisfies `mk r P ∅` by `sat_mk_iff` — the union is `rho r` because only
`p₀` is non-empty, the empty concrete part is disjoint from everything, and any two distinct
parts have at least one of them `∅`.  Forwards is **not** `rEntails_erase`: the existential
set shrinks as well as the system, so the dropped variables must be re-tied to the caller,
which the witness `fun v => if v ∈ ex then sigma v else rho v` does.

**How it relates to R3.**  `dead_delete_of_pairwise` and `dead_delete_of_le_one_part` are the
MIRROR IMAGE: there the dead existential is the LEFT-hand side of the deleted constraint
(`DeadEx R v c` requires `v ∈ R.ex ∧ c.lhs = v`).  Here the left-hand side is a row the
caller fixes and the PARTS are the dead existentials.  Neither theorem implies the other and
neither is an instance of the other; `R3-REVIEW.md` M-3 is the observation that R3 left this
case open, and it is why C12 could not simply be implemented in stage R3.

**None of the three hypotheses is decoration**, and §8's existing refutations are two of the
three witnesses:

| hypothesis | dropped ⇒ | witness |
|---|---|---|
| no concrete labels | `a <- (v, w, (\|Foo\|))` still says `Foo ∈ rho a` | `DeadUndetermined.undetermined_not_deletable` (R3) |
| parts occur nowhere else | a part is still asserted disjoint from the others | `DeadTwoParts.two_parts_not_deletable` (R3) |
| `P.Nonempty` (`k ≥ 1`) | `r <- ()` says `rho r = ∅` | **`TautoEmpty.tauto_empty_not_deletable`** (new) |

A fourth exclusion lives only on the Scala side and is worth naming because the theorem cannot
see it: **a repeated part**.  `mk r P ∅` takes a `Finset`, so Lean's `{t, t}` IS `{t}` — but the
surface constraint `r <- (t, t)` asserts `t` disjoint from itself, which forces `t` and hence `r`
empty.  `freshSplitShape` therefore rejects a repeated part outright.  (The solver collapses a
repeat before it can get this far — `RHS.build`, `LoopRel.dedup` — so the case is excluded
because it must be, not because it is expected.)

**The corpus shape, in Lean.**  `ScanCount.count_tautology : REquiv ⟨{1,2}, {mk 0 {1,2} ∅}⟩ ⟨∅, ∅⟩`
is `Layout.Scan.count`'s whole published qualification, proved equivalent to the empty
residual — which is what `mkSimplified` publishes for it with the flag on.

**Axioms.**  `lake env lean` on each new declaration: `tauto_delete`, `tauto_delete_two`,
`ScanCount.count_tautology`, `TautoEmpty.tauto_empty_not_deletable`, `Tauto.wit_of_mem`,
`Tauto.wit_of_not_mem` — all `[propext, Classical.choice, Quot.sound]`, saved at
`/home/dmitry/.claude/jobs/880c725d/tmp/S5/axioms-S5.txt`.

### 1.2 The deletion

`Subst.scala`, two private members beside `NormalPart` and one call at the end of
`mkSimplified`.

* `freshSplitShape(t)` matches `r <- (t1, .., tk)` with `k ≥ 1`, no concrete part (or an
  EMPTY one), and every `ti` a distinct bare variable.  Anything else — a concrete label, a
  repeated part, a non-variable part, `k = 0` — is rejected, and the table above is why.
* `deleteTautologies(ps, pubExts)` keeps a constraint unless its left-hand side is a variable
  that is NOT a published existential, every part IS a published existential, and no OTHER
  published constraint (row or class) mentions any part.  It deletes those parts from the
  published binder list at the same time, so no binder is left bound and unmentioned.

**It is the theorem's side condition, and in one place narrower.**  The theorem allows any
`r ∉ P`, including an existential one; the code requires `r` not to be a published
existential.  The reason is bookkeeping rather than soundness: deleting when `r` is itself a
dead existential would leave `r` bound by the `exists` and mentioned nowhere.  Two candidates
that share a part delete neither — each is the other's "other constraint".

**Why it is not inside `normalPart` beside S3's `a <- (a)` case.**  That case is a property of
ONE constraint; this one is a property of the whole published set, which `normalPart` cannot
see.  It runs at the end of `mkSimplified` instead, and the position is chosen:

* AFTER the `mkSimplified-extinct` solve, so a deleted constraint can never hide an
  unsatisfiable set;
* AFTER the R3 `ramb` trace record, which measures the residual **as the loop left it** —
  that is what the L2 differential and `trace-ab.py` compare, and moving it would move the
  trace for a reason that has nothing to do with the loop.

**The flag.**  `-Dermine.tautoDelete`, `Constraints.GenRules.tautoDelete`, **default OFF**, and
IN the interface key (`+tauto`).  `GenRules` is not where a post-loop simplification naturally
lives — but it is what a published `.ei` is keyed by since S5.2, and this flag changes
published bytes, so it has to be there.  `topNormalise` is the precedent.

### 1.3 The signatures, before and after

Measured on `core/target/scala-3.3.8/classes/modules/Layout/Scan.ei`, `-Dermine.loadInSeries=true`.

| binding | constraints | before | after |
|---|---|---|---|
| `count`   | 1 → **0** | `(exists (h: rho) (t: rho). r <- (t, h)) => Scan (Report f z) (k, Relation r) -> …` | `Scan (Report f z) (k, Relation r) -> …` |
| `count'`  | 2 → **0** | `(exists (t: rho) (h: rho). r <- (h, t), PrimitiveNum n) => …` | `PrimitiveNum n => …` |
| `sumBy`   | 3 → **2** | `(exists (AsOp: …) (h: rho) (t: rho). AsOp op, r <- (t, h), PrimitiveNum n) => …` | `(exists (AsOp: …). AsOp op, PrimitiveNum n) => …` |
| `avgBy'`  | 3 → **2** | `(exists (AsOp: …) (t: rho) (h: rho). AsOp op, r <- (h, t), PrimitiveNum n) => …` | `(exists (AsOp: …). AsOp op, PrimitiveNum n) => …` |
| `sumBy'`  | — | already free of it | unchanged |

`count` is the extreme case: the tautology was its ONLY qualification, so the published type
loses the `=>` entirely.

**The fifth signature, and the hand-written certificate that is now redundant.**  C12 lists
`sumBy'` as the fifth.  It no longer publishes the constraint, because stage F3 (ticket C5)
deleted it from the SOURCE — `Relation/Scan.e:113-117` is the comment that did it, and it says
in as many words that `sumBy`, `avgBy'`, `count` and `count'` "still carry it; deleting theirs
is ticket C12's job, in `Subst.mkSimplified`, where it can be done for every signature at
once".  That hand deletion is the corpus's ONLY certificate of THIS tautology; with
`tautoDelete` on it becomes redundant as a TECHNIQUE (the compiler now does it for every
signature), though the source no longer carries the constraint, so nothing about `sumBy'`
changes either way and the deletion should stay where it is.

The `Signatures.e` modules do carry tautology certificates, and they are all about a
DIFFERENT shape, which is worth being exact about because it is the reason C12 exists at all:

* `incomplete/Signatures.e`'s `topRowsByFull` (`h <- (h), b <- (h, c)`) and `orZeroFull`
  (`v <- (v)`) are **S3's `a <- (a)`**, and both already say in the file that the compiler
  produces the deduped form itself since S3.  They are unaffected by this stage.
* `Time/Signatures.e`'s `freshLhsFromWider` (`t <- (a, b, c), exists u. u <- (a, b)`) is
  **R3's shape** — the dead existential is the LEFT-hand side — which is what
  `dead_delete_of_pairwise` is about and what this stage does not touch.
* **`Time/Signatures.e` DOES write C12's shape by hand, three times** — corrected by the
  S5 review, Q-14; the sentence that stood here said nothing in the corpus did.  What makes
  those three uninteresting is not the shape but the BINDING: they are EXPLICIT bindings, so
  the written signature is published verbatim and `mkSimplified` never sees it.  They are
  byte-identical at both flag settings, which is the measurement that says so.
* In `Wide/Signatures.e`'s `(exists o. …, r <- (v, o), …)` the other part `v` is universal,
  which is a real containment and not a tautology — a genuine near miss, kept at both
  settings.

The five `Signatures.e` modules the corpus runner covers — `Algebra`, `Lang`, `Present`,
`Time`, `Wide` — are LOADED in both runs, flag OFF and flag ON.  (`incomplete/Signatures.e`
is outside the runner's set by design, like the rest of `incomplete/`.)

### 1.4 The sweep

`tracker/tools/ei-diff.sh --batch --snapshot`, `-Dermine.loadInSeries=true` on both sides,
classified with `tracker/tools/ei-classify.py`.  Full output:
`/home/dmitry/.claude/jobs/880c725d/tmp/S5/ei-classify.txt`.

```
interfaces: A 268  B 268   only-in-A -   only-in-B -
bindings by verdict: identical 3463, order-only 10, alpha-equivalent 3, other 5
== 7 of 268 interfaces differ
```

**The A side really is the pre-change compiler, and that is measured, not argued.**  A third
snapshot was taken with the FINISHED build at the shipped default (`tautoDelete` off) and
compared to side A file by file: with the S5.2 key header stripped, **all 268 interfaces are
BYTE-IDENTICAL**.  So the only change the shipped default makes to a published `.ei` is the one
header line, the flag-off path is the old compiler exactly, and the A/B below varies one thing.

The five `other` bindings:

| interface | binding | verdict |
|---|---|---|
| `Layout/Scan.ei` | `count` | 1 → 0 constraints — **intended** |
| `Layout/Scan.ei` | `count'` | 2 → 0 — **intended** |
| `Layout/Scan.ei` | `sumBy` | 3 → 2 — **intended** |
| `Layout/Scan.ei` | `avgBy'` | 3 → 2 — **intended** |
| `Layout/Report/Relation.ei` | `cutoffGroupedFldsPosNegRel'` | 40 → 38 constraints, 40 → 37 existentials — **NOT intended** |

and the 13 remaining movers are `order-only`/`alpha-equivalent` in
`Present/WriterOutputs.ei` (3), `Time/Signatures.ei` (6), `incomplete/RecalibratedColumns.ei` (1),
`incomplete/TargetList.ei` (1), `incomplete/RunCalibration.ei` (2).

**The one that matters is `cutoffGroupedFldsPosNegRel'`, and it is worth being precise about
why.**  Applying the deletion criterion to that signature's PUBLISHED constraint set finds two
candidates (`c <- (d3, e1)` and `c <- (d5, e5)`, `c` universal, all four parts existential) and
rejects BOTH, because every one of those parts occurs in another constraint.  So the change did
not delete anything from what that signature publishes.  It came from an INTERMEDIATE
`mkSimplified`: the function runs at every `Subst.generalize` (including the ones inside
`App`/`Lam`) and in `subsumeType`, and a local scheme that loses a tautology sends a
differently-shaped — but equivalent — residual into the enclosing inference.  Each step is
`tauto_delete`; the composite is not "delete the published tautology", and the brief asked for
exactly that and no wider.  Hence the flag.

**Corpus and other checks with the flag ON** (all in §3): verdicts identical, 85 / 69 / 0;
all five corpus `Signatures.e` modules — `Algebra`, `Lang`, `Present`,
`Time`, `Wide` — are LOADED in both runs; 11 refusal MESSAGES change, all inside `shouldfail/`, all of them the
same field-clash refutation reported at a different field or with the other of the two
`labelClash` reasons — the same class of message churn `labelCheckEarly`'s adoption produced.

**What a stage 2 would need.**  Restrict the deletion to the ONE `mkSimplified` call that
publishes a binding's signature (`RowTrace` already distinguishes it) and re-run the sweep;
if that leaves the four signatures and nothing else but downstream alpha-variants, criterion
(c) is met and the flag can flip.  That is a measurement, not a redesign, and it is deliberately
not done here.

---

## 2. S5.2 — the `.ei` solver-configuration key

### 2.1 The key

`Session.interfaceKey = <interface format version>|<Constraints.GenRules.toString>`.  At the
shipped defaults:

```
2|cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000+topnorm+tauto
```

(The trailing `+tauto` arrived with the follow-up section's default flip.  Before it the shipped
key ended `+topnorm`, which is why every `.ei` written earlier in this stage is stale and rebuilt
without anyone clearing anything.)

`interfaceFormatVersion` is `2`.  `1` is reserved for the UNKEYED format every `.ei` written
before this stage carries; since no such file has a key, "missing key" and "version 1" are the
same condition and both are stale.  The version is what to bump when the published FORM changes
for a reason that is not a solver flag; `tautoDelete` is a solver flag and rides in the
fingerprint as `+tauto`, so flipping it needs no bump.

### 2.2 What is deliberately NOT in it

Only things that cannot change the bytes of a **successfully published** interface.

| property | why it is out |
|---|---|
| `ermine.rowTrace`, `ermine.rowTrace.draws` | pure instrumentation |
| `ermine.foreign.tolerant` | decides whether an unresolvable `foreign data` is a refusal or keeps its declared name; changes whether a module LOADS, never the type published for one that does.  **And for a stronger reason (S5 review Q-11): the only site that turns it on, `lsp/Resident.scala:105`, also sets `_useInterface = Some(false)`, so a tolerant session can neither read nor write an `.ei` at all** |
| `ermine.typeCheck` | with it off the module is answered by `untyped` and reaches `CheckMethod.Interface`, so `writeInterface` is never called — an unchecked session cannot write an `.ei` at all |
| `ermine.useInterface` | with it off `Dep.writeInterfaceString` is the no-op |
| `ermine.rowSound.budget`, `ermine.rowSound.solveBudget` (spelt in full: `ermine.solveBudget` is a different property and IS in the key, as `+budget:20000`) | a lapse in either means NO VERDICT, so they can change whether a module is REFUTED, never the bytes of one that is published |
| `ermine.loadInSeries` | a LOADER schedule, not a solver rule — see below |

`loadInSeries` is the only one that needs an argument rather than a statement, because it DOES
reach interface bytes: a parallel load draws `Supply` ids in thread-timing order, which is the
whole reason the G1 oracle and every sweep set it (`Session.scala:557`).  What it moves is the
NAMES of published existentials — two sides are alpha-variants, which type-check identically
and which the canonicaliser of `ROSE-COMPARISON.md` rank 3 is what actually removes.  Keying on
it would invalidate every interface an LSP session (parallel) wrote for a batch build, and
every interface a batch build wrote for an LSP session, on every load, for no soundness gain.
Recorded here so the decision is visible rather than implied.

### 2.3 Where it is written and where it is checked

* **Written** in `Session.Dep.writeInterface` (`Session.scala`): `interfaceHeader + "\n"` in
  front of the existing name-sorted signature block.  The sortedness and the bytes below the
  header are untouched.
* **Checked** in `Session.dep`'s `preCk` — the closure `Dep.readInterface` is built from, and
  the same expression that already decides currency: `file.interfaceContents` has just answered
  the mtime question (interface newer than source) and `interfaceFile.run` answers the
  well-formedness one.  The key sits between them.  A mismatch or a missing key logs at debug
  and answers `None`, which is what a newer source answers, which means a full check — and the
  full check calls `writeInterface`, so the file is rewritten with the running key.  There is
  no separate path and no separate cache.

**One thing the parser forced.**  The header is an Ermine line comment, but
`InterfaceParsers.interfaceSigs` is a `laidout` block run straight off the file with no
`phrase` wrapper and it accepts **neither** a leading `--` comment **nor** a leading blank line
— both facts measured directly, with `G1Compare --pair` on a hand-made keyed file and on a
hand-made blank-first-line file, against the same file with neither.  So
`Session.splitInterfaceKey` REMOVES the header line rather than blanking it, and the body the
parser sees is byte-identical to what an unkeyed `.ei` held.  The cost is that a parse error's
line number is one less than the file's; nothing surfaces that number (the failure is
`_log.debug` plus a recheck).  The first version of this change blanked the line instead, and
the symptom was silent: every module was fully rechecked, every warm load cost its cold time,
and no test failed.

**A second, pre-existing trap of the same shape, found by the review (Q-16) and now ticketed.**
An `.ei` publishing a partition with a CONCRETE part — `X <- (…, (|lbl|))` — does not parse
back, so those modules are fully rechecked and rewritten on EVERY load and never converge.
**18 of 268 corpus interfaces publish that shape**, `Layout/Report/Relation.ei` among them.
It is entirely pre-existing (the printer and the parser have disagreed on that form since
before this stage) and it is deliberately NOT fixed here, but it is exactly what this section
warns about: a silent full recheck that no test fails.  Ticket
`TICKET-stdlib-findings.md` **E1**, with the reproduction, the 18 files and acceptance
criteria; **E2** is its sibling, the write side of the cache being frozen into the cached
`Dep` while the read side is gated at call time.

**A consequence worth stating.**  A `SourceFile.Resource` — an `.ei` read out of a jar — has no
writeback (`interfaceWriteback` is the inherited no-op).  So a jar that ships interfaces built at
another configuration now makes every module in it recheck in full, every load, instead of
loading a mixed tree silently.  That is the right trade (correct and slow beats fast and wrong)
but it is a behaviour change for a packaged distribution, and whoever packages one should build
the `.ei` at the configuration they ship.

**The other reader.**  `G1Compare.parseEi` now reads through `Session.splitInterfaceKey` too,
so the tool compares a fresh (keyed) tree against the 143 UNKEYED `.ei` checked in under
`tracker/g1-baseline` and `tracker/g1-oracle-tests` without touching them.  Verified:
`G1Compare --pair <unkeyed> <keyed> --expect equal` → `pair EQUIVALENT … OK` on
`Layout/Scan.ei`.  `TestTolerantRead` does not read `.ei` at all (it sweeps `.e` sources), so
it is unaffected.  **No baseline was updated**: no test requires it.  `tracker/tools/g1-diff.sh`
counts non-blank lines in an `.ei` tree as a sanity check and will now count one more line per
file; it is a script, not a gate, and nothing in it compares that count across a keyed and an
unkeyed tree.

### 2.4 Tests

`scalacheck-binding/src/main/scala/TestInterfaceKey.scala`, in `TestInterfaceRoundTrip`'s
style: its own temp workspace, `Session.depCache.clear()` under `ErmineFixture.literalLock`.

1. **`key is <format version>|<GenRules>, and holds no non-key flag`** — the key equals
   `interfaceFormatVersion + "|" + GenRules.toString`, is unchanged when `ermine.rowTrace`,
   `ermine.rowTrace.draws`, `ermine.loadInSeries`, `ermine.foreign.tolerant`, `ermine.typeCheck`
   and `ermine.useInterface` are all flipped, and the header is the marker plus the key.  This
   is the regression guard: putting a non-key property into the key fails here.
2. **`cold write keys, warm read matches, a wrong or missing key is stale`** — five steps in
   one session sequence: (1) cold load = `Full`/`Full`, both `.ei` written, each opening with
   `Session.interfaceHeader`; (2) warm load = `Interface`/`Interface`; (3) warm load with
   `ermine.loadInSeries=true`, `ermine.rowTrace=false`, `ermine.foreign.tolerant=true` — still
   `Interface`/`Interface`, and `loadInSeries` genuinely changes how the session loads, so this
   is a behaviour change that does not invalidate the cache; (4) both headers rewritten to
   `2|another+configuration` = `Full`/`Full` and both files come back carrying the running key;
   (5) both headers stripped (a pre-S5 `.ei`) = `Full`/`Full` and both are re-keyed.

**How configuration B is varied, and why not with a property.**  Every key-bearing flag is a
`val` of `GenRules` read once at class-initialisation time, so a second configuration cannot be
produced inside one JVM.  What the mechanism rests on is the comparison of the key in the FILE
with the key of the RUNNING compiler, so B is produced where it is observable — the file's key
is rewritten, which is exactly what a tree built partly elsewhere looks like.  Step (5) is the
same test for the case a real tree will actually hit first.

**Outside the suite**: the LSP `Resident` boots and `lsp-smoke.sh` is green; `repl-smoke.sh`
goldens are unchanged; a cold/warm pair on `core/examples/GroupBy.e` goes 16.2 s → 9.9 s with
`Layout/Scan.ei`'s mtime unmoved (the interface was read, not rewritten), and re-keying that one
file to `2|another+configuration` makes the next load rewrite it.

---

## 3. Gates

Every gate below was run by the implementer on this tree at commit `fbab51b` plus the changes
of this stage.  `PATH` per the brief; `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`;
one JVM at a time; every `.ei` this stage caused was deleted afterwards.

| gate | tier | result |
|---|---|---|
| `lake build` (`tracker/lean`, `LEAN_NUM_THREADS=2`) | 0 | **green**, 870 jobs.  The only warnings are the pre-existing `linter.style.header` ones on `Determined.lean`'s own header and one long line in `Rowpartition.lean` |
| `lake env lean Audit.lean` | 0 | **`Rowpartition theorems audited: 4596; declarations using a non-standard axiom: 0`** |
| `#print axioms` on every new declaration | 0 | `tauto_delete`, `tauto_delete_two`, `ScanCount.count_tautology`, `TautoEmpty.tauto_empty_not_deletable`, `Tauto.wit_of_mem`, `Tauto.wit_of_not_mem` → all `[propext, Classical.choice, Quot.sound]` |
| `sbt core/compile core/copyResources` | 0 | **green** (no new warnings) |
| `sbt 'core/testOnly *TestLoopTrace'` | 0 | **720 / 720**: `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls fire (id base +1 → 46 of 720 disagree, `--flags=nongen` → 58) |
| `corpus-run.sh --batch` (default, flag OFF) | 0 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `corpus-run.sh --batch` with `-Dermine.tautoDelete=true` | — | **85 / 69 / 0** — verdicts identical.  11 refusal MESSAGES differ, every one inside `shouldfail/`, every one the same field-clash refutation at a different field or with the other `labelClash` reason |
| `trace-ab.py`, group `boot`, OLD build vs THIS build at DEFAULT flags | 1 | **`segments=54209 IDENTICAL=54209 sinmoved=0`** — byte-identical |
| `trace-ab.py`, group `Wide`, OLD build vs THIS build at DEFAULT flags | 1 | **`segments=115874 IDENTICAL=115874 sinmoved=0`** — byte-identical |
| `ei-diff.sh --batch --snapshot` ×2, `-Dermine.loadInSeries=true` both sides, `ei-classify.py` | 1 | 268 interfaces each side; **identical 3463, order-only 10, alpha-equivalent 3, other 5**; 7 of 268 interfaces differ.  §1.4 |
| the same sweep a THIRD time, finished build at the shipped default, against side A | 1 | **all 268 byte-identical** with the key header stripped — the flag-off path IS the pre-change compiler, and the only default-configuration change to a published `.ei` is the header line |
| `sbt core/test` (full) | 2 | **940 / 940**, 0 failed, 0 errors (1500 s).  See below — it took two runs, and the first failure was the test's own fault, not the change's |
| `repl-smoke.sh` | 0 | **green**: aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23 — goldens unchanged |
| `lsp-smoke.sh` | 0 | **`PASS lsp (181 checks)`** |
| `sql-render.sh` (`wide-render-probe.e`), OLD build vs THIS build | 1 | **`sql/` and `out/` byte-identical** (`diff -rq` empty on both); only `probe.out`'s progress-bar and per-module timing lines differ |

**The two trace comparisons are the ones the brief asked for and they say what it wanted them
to say**: at the shipped default the row trace does not move at all, because `deleteTautologies`
returns its argument before touching anything when the flag is off.  For completeness the same
comparison with `-Dermine.tautoDelete=true` is *not* identical and was never going to be —
`boot` gives `CONTENT-DIFFERS=423 KINDCOUNT-DIFFERS=4 PERMUTATION-ONLY=1939 IDENTICAL=51843
sinmoved=2361` and `Wide` gives `CONTENT-DIFFERS=10448 KINDCOUNT-DIFFERS=13962
PERMUTATION-ONLY=38759 IDENTICAL=52705 sinmoved=63147`.  That is not the loop behaving
differently: `mkSimplified` is post-loop, so what moves is the INPUT to every LATER solve that
instantiates a signature the deletion shortened.  The direction is worth recording — the `Wide`
trace is **10% smaller** with the deletion on (71.6 MB against 79.6 MB), i.e. the corpus's
downstream solves really are being handed less to do.

### `sbt core/test`

**`sbt core/test` — 940 / 940, 0 failed, 0 errors, 1500 s.**  That is 939 pre-existing plus
`TestInterfaceKey`'s two, minus the `TestConstraints."disjunction sound"` quarantine, and no
documented flake fired: `TestInterfaceRoundTrip` passes.

It did NOT pass the first time, and the reason is worth recording because it is a trap for
anyone writing a test near this code.  `TestInterfaceKey`'s first draft demonstrated "a non-key
flag does not invalidate the cache" by setting `ermine.typeCheck`, `ermine.useInterface` and
`ermine.foreign.tolerant` around a load.  All three are **`SessionEnv` defaults read from the
system property at construction time** (`SessionState.scala:119`, `:121`, `:130`), ScalaCheck
runs properties concurrently, and `System.setProperty` is process-global — so the flip reached
`TestInterfaceRoundTrip`'s session and made it fail (940 total, 1 failed).  The test now names
those three but never sets them: it asserts textually that the key mentions none of them, and
flips only `ermine.rowTrace` / `ermine.rowTrace.draws` (read once into a `val` at `RowTrace`
class-initialisation, so inert) and `ermine.loadInSeries` (read on every `Session.loadModules`
call, so a real behaviour change, and harmless to a concurrent load either way).  Both interface
properties then pass together and the full suite is green.

---

## 4. What a reviewer re-runs, and the one decision this stage leaves open

**Re-run (Tier 0 + the Tier 1 items S5.1 touches).**

```
cd tracker/lean && lake build && lake env lean Audit.lean
sbt core/compile core/copyResources
sbt 'core/testOnly *TestLoopTrace'
tracker/tools/corpus-run.sh --batch <out> && python3 tracker/tools/corpus-verdicts.py <out>
tracker/tools/repl-smoke.sh ; tracker/tools/lsp-smoke.sh
sbt core/test                                       # Tier 2, ALONE on the tree

# the S5.1 sweep, now a ONE-BUILD flag A/B.  Use --snapshot TWICE, not the two-sided form:
# `ei-diff.sh`'s own side A runs with NO flags, which would leave it parallel-loaded against a
# serial side B and put id-shift churn in the answer.
F="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true"
tracker/tools/ei-diff.sh --batch --snapshot <out>/OFF "$F -Dermine.tautoDelete=false"
tracker/tools/ei-diff.sh --batch --snapshot <out>/ON  "$F"          # ON is now the DEFAULT
python3 tracker/tools/ei-classify.py <out>/OFF <out>/ON
```

Note that block: because S5.1 is behind a flag, the sweep no longer needs two builds.  The
implementer measured it as two `--snapshot` runs (the flag did not exist when the first side was
taken) and then took a THIRD snapshot with the finished build at the shipped default, which is
byte-identical to side A over all 268 interfaces once the key header is stripped.  Together with
the byte-identical `boot` and `Wide` row traces, the byte-identical `sql-render` output and the
identical corpus verdicts and messages, that establishes the flag-off path IS the pre-change
compiler, so the A/B varies exactly one thing.

Artefacts, if the reviewer wants to look rather than re-run, are under
`/home/dmitry/.claude/jobs/880c725d/tmp/S5/`: `eiA` (pre-change build), `eiB` (deletion on),
`eiOFF` (finished build, default), `ei-classify.txt`, `axioms-S5.txt`, `tr/` (six row traces),
`corpus` and `corpus-on`, `sql-old` and `sql-new`, `coretest2.log`.

**The decision this stage did not take when §4 was written, and took afterwards.**  Whether
`-Dermine.tautoDelete` should be ON.  §4's recommendation was "do not flip it; do the stage-2
measurement first (restrict the deletion to the publishing `mkSimplified` call and re-sweep) —
that is one short stage and it converts a judgement into a number."  **That measurement was
then done, in this stage, and the number says flip**: see "Follow-up: publishing-only deletion"
below, which supersedes this paragraph.  The reviewer's re-run should use the flag A/B in the
block above, against the SHIPPED default, which is now ON — i.e. side A is
`-Dermine.tautoDelete=false`.

---

## Follow-up: publishing-only deletion

Added 2026-09-09, same stage, on the coordinator's instruction, before review.  §4 above
recommended one measurement: confine the C12 deletion to the generalisation that produces a
binding's PUBLISHED signature and re-sweep.  It was done, it took **two** attempts, the second
meets criterion (c), and **`-Dermine.tautoDelete` is now DEFAULT ON**.

### How "publishing" is distinguished — a parameter, never a global

Three signatures gained a `publishing: Boolean = false` and one call site passes `true`:

```
Session.loadModule / Subst.checkModule
  -> Subst.inferBindingGroupTypes(l, g, is, es, slv, publishing = TRUE)   <- only here
       -> Subst.inferImplicitBindingTypes(..., publishing)
            -> Subst.generalize(..., publishing)
                 -> Subst.mkSimplified(..., publishing)
                      -> deleteTautologies, iff publishing && GenRules.tautoDelete
```

A parameter and not a thread-local or a system property, for the reason `RowTrace`'s own
`withBinding` is thread-local: generalisation is re-entrant (a `let` inside a binding
re-enters `inferBindingGroupTypes`) and the loader runs it on several threads at once.  A
global would be wrong in both directions.

Everything else keeps the default `false`: `inferType`'s `Let`, `Lam` and annotation
generalisations, `trySolveOn`, and `subsumeType`'s own `mkSimplified`.

### Attempt 1 — "the binding's own generalisation" is not enough

The first restriction set `publishing = true` at `inferImplicitBindingTypes`'s per-binding
`generalize` — the call `RowTrace.withBinding` names as "the one call that publishes a
binding's signature".  That is not the same predicate, and the sweep said so:

| variant | identical | order-only | alpha-eq | other |
|---|---|---|---|---|
| unrestricted (every generalisation) | 3463 | 10 | 3 | **5** |
| attempt 1 (`inferImplicitBindingTypes`) | 3476 | 0 | 0 | **5** |
| attempt 2 (module top-level group only) | **3477** | 0 | 0 | **4** |

Attempt 1 removed **all 13** alpha-variant and order-only movers — those really were caused by
`mkSimplified` running inside expression inference — but `cutoffGroupedFldsPosNegRel'` still
moved 40 → 38.  The reason is that `inferImplicitBindingTypes` is reached by a **`let` group
too** (`Subst.inferType`'s `Let` case calls `inferBindingGroupTypes`), and
`Layout.Report.Relation.cutoffGroupedFldsPosNegRel'` is one big `let`: `f`, `zero`,
`cutoffPredicate`, `largeEnough`, `tooSmall`, `tooSmallRel`, `relWithCutoff` are all local
implicit bindings, each generalised by that same function.  Simplifying a LOCAL scheme is
sound but the enclosing signature is inferred FROM it, so the published form moves.  §1.4's
diagnosis ("an intermediate residual loses a tautology") was right; its identification of
which call was intermediate was not, and this is the correction.

### Attempt 2 — the module's top-level binding group, and the sweep that decides it

`publishing` is now set at `inferBindingGroupTypes`'s **two module-level call sites only** —
`Subst.checkModule` and `Session.loadModule` — which are exactly the groups whose generalised
types are written to the `.ei`.  A local `let` binding's signature is never published, so it
is never simplified.

Sweep, ONE build, flag A/B, `-Dermine.loadInSeries=true` on both sides, stdlib + `core/examples`:

```
tracker/tools/ei-diff.sh --batch --snapshot <out>/OFF "-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true"
tracker/tools/ei-diff.sh --batch --snapshot <out>/ON  "-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true -Dermine.tautoDelete=true"
python3 tracker/tools/ei-classify.py <out>/OFF <out>/ON
```

```
interfaces: A 268  B 268  only-in-A -  only-in-B -
bindings by verdict: identical 3477, other 4
```

| interface | binding | verdict | before → after |
|---|---|---|---|
| `Layout/Scan.ei` | `count` | other | `(exists (h: rho) (t: rho). r <- (t, h)) => …` → no qualification at all (1 → 0 constraints) |
| `Layout/Scan.ei` | `count'` | other | `(exists (t: rho) (h: rho). r <- (h, t), PrimitiveNum n) => …` → `PrimitiveNum n => …` (2 → 0 row constraints) |
| `Layout/Scan.ei` | `sumBy` | other | `(exists (AsOp: …) (h: rho) (t: rho). AsOp op, r <- (t, h), PrimitiveNum n) => …` → `(exists (AsOp: …). AsOp op, PrimitiveNum n) => …` (3 → 2) |
| `Layout/Scan.ei` | `avgBy'` | other | `(exists (AsOp: …) (t: rho) (h: rho). AsOp op, r <- (h, t), PrimitiveNum n) => …` → `(exists (AsOp: …). AsOp op, PrimitiveNum n) => …` (3 → 2) |
| every other binding on every other interface | — | **identical** | — |

And at the BYTE level, with the S5.2 key header stripped from both sides (the ON side's key
carries `+tauto`, which is the mechanism working, not a difference in content): **exactly one
of 268 files differs — `Layout/Scan.ei` — on exactly four lines.**  267 interfaces are
byte-identical.

**Criterion (c) is met.**  Per the decision rule the flag is flipped:
`GenRules.tautoDelete` is now `System.getProperty("ermine.tautoDelete", "true") == "true"`.
`-Dermine.tautoDelete=false` restores the previous behaviour exactly.

### One thing the flip demonstrates for free

The shipped key is now
`2|cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000+topnorm+tauto`.
Every `.ei` written before the flip ends in `+topnorm`, so **every one of them is stale and is
rebuilt on the next load, automatically** — the manual `find . -name '*.ei' -delete` that
`ROW-CONSTRAINT-STATE.md` documented for `smallcanon`, `solveBudget` and `topNormalise` is not
needed for this adoption.  That is S5.2 paying for itself on the first flip after it landed.

### Gates re-run at the new default (`tautoDelete` ON)

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | green |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 / 720** — `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls still fire (46 / 720 at id base +1, 58 / 720 at `nongen`) |
| `corpus-run.sh --batch` + `corpus-verdicts.py` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, and the verdict listing is **byte-identical to the pre-change run — zero lines differ**, messages included.  (The unrestricted variant changed 11 refusal messages; the publishing-only one changes none.) |
| `trace-ab.py`, group `boot`, PRE-CHANGE build vs this build at the new default | **`segments=54209 IDENTICAL=54209 sinmoved=0`** |
| `trace-ab.py`, group `Wide`, PRE-CHANGE build vs this build at the new default | **`segments=115874 IDENTICAL=115874 sinmoved=0`** |
| `repl-smoke.sh` | green — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23 |
| `lsp-smoke.sh` | **`PASS lsp (181 checks)`** |
| `sql-render.sh` vs the pre-change build | `sql/` and `out/` **byte-identical** |
| `sbt core/test` (Tier 2 — a default flips) | **940 / 940**, 0 failed, 0 errors (1500 s), with the self-contained fixture below.  The run before it was 939 / 940 — see below, the failure was the test's own |

The row-trace result deserves a sentence, because it is not obvious that it should hold now
that the deletion is ON by default.  It holds because `mkSimplified` is post-loop and the only
signatures that move are `Layout.Scan`'s four; `Layout.Scan` is not among the 129 modules the
stdlib boot loads, and no module under `core/examples/Wide/` imports it.  A group that DOES
use them would see its downstream solves change — that is a smaller input, not a different
loop — and the L2 model differential is unaffected either way (`TestLoopTrace` 720/720).

### One test fix this required, and it is the same trap twice

The first Tier 2 run at the new default was **939 / 940**, the single failure being
`TestInterfaceKey`'s own warm-read step: `Expected (Some(Interface),Some(Interface)) but got
(Some(Full),Some(Full))`.  Not the flip — a race, and the documented `TestInterfaceRoundTrip`
flake class seen from the other side.  `preChecked` answers `Interface` only when EVERY import
was itself interface-checked, the test's `KeyA` imported `Primitive` and `Function`, and
`Session.depCache` is process-global while ScalaCheck runs properties concurrently: a sibling
suite that builds the `Primitive` dep in a `useInterface=false` session between this property's
cold and warm loads bakes the no-op writeback into it, no `Primitive.ei` is written, and the
warm load is `Full` through no fault of the mechanism under test.  The fixture now uses modules
with **no imports at all** (`KeyA` imports nothing, `KeyB` imports only `KeyA`), so the only
interfaces the property depends on are the two it writes in its own temp directory.  It is also
several seconds faster.  Both interface properties then pass, alone and in the full suite.

Twice now this stage has been bitten by the same thing — the first `core/test` failure was this
test setting process-global system properties, this one is it depending on process-global
interface state — so it is worth stating as a rule: **a property that exercises the interface
cache must own every file it depends on.**

### The orchestrator's file

`tracker/LOOP-MODEL-HANDOFF.md` was modified at 09:08 by this stage, before the coordinator's
instruction not to.  What was done, exactly: **twenty lines APPENDED at the end** (after the
file's last line, 1171), in its existing append-only chronological style, recording the S5
delivery — S5.2 green and the retired cache-wipe instruction, S5.1 partial and behind a flag,
the `InterfaceParsers` header gotcha, the next step, and the gate numbers.  `git diff` on that
file is `20 insertions(+), 0 deletions(-)`: **no existing line was changed or removed.**  It has
not been touched since, and the S5.1 half of that entry is now out of date — the flag is ON —
which the orchestrator will want to correct when it next writes there.

### One tool fix this required

`tracker/tools/ei-classify.py` crashed on a keyed `.ei` (`AttributeError: 'list' object has no
attribute 'strip'`): the header line has no `" : "`, so it collected into the `<<unparsed>>`
bucket as a LIST and `classify` was handed a list where it expected a signature string.
`read_ei` now recognises the header and stores it as a `<<key>>` pseudo-binding, and `main`
reports `key-differs` for it instead of classifying it.  Without this the reviewer's own
re-run of the sweep would not complete.

---

## Fix round (S5 review)

`tracker/loopmodel/S5-REVIEW.md`, 619 lines, Q-1…Q-16, verdict **FIX-THEN-ADVANCE**.  Every
finding below is dispositioned; nothing is left unanswered.  The three MUST-FIXes are done, and
the two pre-existing reds the reviewer surfaced (Q-15, Q-16) are handled here rather than
deferred.

| # | rank | disposition | what was done |
|---|---|---|---|
| **Q-1** | medium, MUST | **FIXED** | `TolerantCheck.scala:267` passes `publishing = true`.  §A below: the full caller audit, the isolated measurement, and the two new regression guards. |
| **Q-2** | medium, MUST | **FIXED** | `Subst.deleteTautologies`'s scaladoc: "DEFAULT OFF" and the "not established that its effect is confined" paragraph are gone, replaced by the follow-up's facts (publishing-only; 268 interfaces / 3,481 bindings; four move; 267 of 268 byte-identical) and by the three ways the code is NARROWER than the theorem, which is the reviewer's own §1.5. |
| **Q-3** | medium, MUST | **FIXED** | `RevHfresh.hfresh_needed` and `RevUnivPart.univ_part_needed` adopted into `Determined.lean` **verbatim from `review-S5/Probe.lean`, namespaces and names kept** so the review's `#print axioms` lines reproduce against the library.  §8's section doc is rewritten: it now separates the three conditions carried by the SHAPE from the three hypotheses, and says which are necessary. |
| **Q-4** | low | **FIXED** | `tauto_delete_no_hr` adopted, with a docstring saying why `tauto_delete` keeps `hr` anyway (shorter proof; every use has `r ∉ P` on hand, and on the Scala side it FOLLOWS from `!ex(r) && vs.forall(ex)`). |
| **Q-5** | low | **PARTLY, and the rest declined with a reason** | The iteration argument is now written where it belongs — in `deleteTautologies`'s scaladoc: `occ` makes distinct candidates' part sets disjoint and forbids a candidate's part from being another's left-hand side, so deleting one leaves every other still satisfying the side condition against the smaller system.  The LEAN statement of the iterated form is **declined for this stage**: it is the reviewer's own item 12, conditional on the canonical-residual programme leaning on it, and adding a theorem nothing yet consumes is the wrong order. |
| **Q-6** | low | **FIXED** | `ei-classify.py`: a `key-differs` row no longer puts a file in `differing_files`; the key is reported on its own line with both values.  The headline for the flag A/B goes from the useless `268 of 268 interfaces differ` to **`1 of 268`**, which is the true answer. |
| **Q-7** | low | **DECLINED here, TICKETED** | Gating `writeInterfaceString` at call time changes the semantics of the process-global dep cache for every session, which is a loader change and not this stage's.  `TICKET-stdlib-findings.md` **E2**, with the evidence (it is the mechanism behind both of this stage's `core/test` failures), why S5.2 raises its cost, and acceptance criteria including a property that fails before the fix. |
| **Q-8** | low | **FIXED** | `g1-diff.sh` counts SIGNATURE lines, excluding the S5.2 key header.  `1576` → **`1447`**, i.e. the number is comparable to every pre-S5 run again and the `[1300,1700]` band has its headroom back. |
| **Q-9** | low | **FIXED** | `ermine.rowSound.solveBudget` spelt in full in `Session.interfaceKey`'s doc and in §2.2, with the note that `ermine.solveBudget` is a different property and IS in the key. |
| **Q-10** | low | **FIXED** | The plan row's headline is now "BOTH PARTS GREEN", and the row gained its reviewer column. |
| **Q-11** | info | **FIXED** | §2.2 now gives the stronger reason: `lsp/Resident.scala:105`, the only site that turns `foreign.tolerant` on, also sets `_useInterface = Some(false)`, so a tolerant session can neither read nor write an `.ei`. |
| **Q-12** | info | **FIXED** | Already stated; now with the number.  **Eight** corpus modules mention `Layout.Scan` (`Ai/FiscalCalendar`, `Algebra/Comprehensions`, `Algebra/Helpers`, `Algebra/LedgerScan`, `GroupBy`, `Lang/TreeAndMap`, `Present/SalesDashboard`, `Time/CohortRetention`) — none of them under `Wide/` and none in the stdlib boot, which is why the two trace groups cannot see the deletion and why the corpus run and the sweep are what exercise it. |
| **Q-13** | info | **FIXED** | `Subst.scala`'s `inferBindingGroupTypes(m.loc, Nil, is, es, true, true)` has a comment naming both booleans. |
| **Q-14** | low | **FIXED** | §1.3 corrected: `Time/Signatures.e` DOES write C12's shape by hand, three times, and what makes them uninteresting is that they are EXPLICIT bindings — the written signature is published verbatim and `mkSimplified` never sees it, which is why they are byte-identical at both flag settings. |
| **Q-15** | medium, not S5's | **FIXED** | §B below. `g1-validate.sh` is **9 PASS / 0 FAIL**. |
| **Q-16** | low, not S5's | **TICKETED** | `TICKET-stdlib-findings.md` **E1**, with the reviewer's reproduction, the 18 files and four acceptance criteria; noted in §2.3 beside the header-strip trap it is a sibling of. |

### A. Q-1 — the editor path, audited, fixed, isolated and guarded

**The audit.**  Every caller of the two entry points, and what each passes:

| site | what it generalises | `publishing` |
|---|---|---|
| `Session.loadModule` (`Session.scala:971`) | a module's top-level group — the one that writes the `.ei` | **true** |
| `Subst.checkModule` (`Subst.scala:1667`) | the same, from the batch entry point | **true** |
| `Subst.inferType`'s `Let` (`Subst.scala:908`) | a `let`/`where` group | false — correct |
| `Subst.inferBindingGroupTypes` → `inferImplicitBindingTypes` (`Subst.scala:762`) | threads its own argument | — |
| **`TolerantCheck.checkWith` (`TolerantCheck.scala:267`)** | `m.implicits`, split by the same `implicitBindingComponents` — the EDITOR's copy of the module's top-level group | **was false, now true** |

Those are all of them; `grep` for both names over the tree finds no other call.

**Isolated, not assumed.**  With `publishing = false` restored at that one line and everything
else unchanged, exactly ONE of the three new LSP checks fails:

```
hover pos has no vacuous row constraint (C12):
  Tauto.pos : forall (r: rho). (exists (h: rho) (t: rho). r <- (t, h)) => Relation r -> Relation r
```

and `hover Layout.Scan.count agrees with its .ei` still PASSES — because that type comes from
the session's loaded `Layout.Scan`, i.e. from the compiler's publishing path, not from
TolerantCheck.  That is the divergence the reviewer measured, reproduced and then closed.

**Nothing on disk moves.**  The editor path never writes an interface (the only
`writeInterface` caller is `Session.dep`'s closure), and that is now measured rather than
argued: the whole 268-interface snapshot at the shipped default is **byte-identical before and
after the Q-1 change** (`diff -rq`, 0 files differing).

**The guards.**  A regression here is invisible to every existing gate, so both were added.

* `tracker/lsp-tests/Tauto.e` + three checks in `lsp-client.py`: hover on `pos` (C12's shape,
  INFERRED through TolerantCheck) must carry no `<-` and no `exists`; hover on `conc` (a
  CONCRETE part) must KEEP its constraint, so the guard fails if the deletion ever over-fires;
  hover on the imported `Layout.Scan.count` must agree with the `.ei`.  Plus a diagnostics
  check that the fixture is clean.  `lsp-smoke.sh` **181 → 185 checks**.  Negative control: with
  `-Dermine.tautoDelete=false` the first and third fail and the `conc` one still passes.
* `tracker/repl-tests/Tauto.e` + `tauto.in`/`tauto.expected`: `:type` on a deleted case (`pos`),
  the general `k = 3` case (`pos3`) and two near misses (`conc`, `shared`).  `repl-smoke.sh`
  gains a case: **`PASS tauto (5 checks)`**, eight cases in all.  The suite runs with
  `-Dermine.useInterface=false`, so these types come from real inference and the check is that
  inference and the published form agree.  The golden discriminates in both directions: a
  deleted type prints on ONE line, a kept one wraps, and the harness's `grep -v '^  '` (which
  discards `:import`'s module listing) keeps only the first — which is why the probe uses short
  synthetic types and the full-width `Layout.Scan` signatures are checked by hover instead.

### B. Q-15 — the g1 baseline, re-cut on an explanation

`g1-validate.sh` said a red here "is a Decision 9 stop — explain it or revert it".  The
explanation, and the re-cut, are in `tracker/g1-baseline/README.md` (a dated section, appended).

**Exactly what drifted, first — the reviewer's count needed one correction.**  `G1Compare`
prints `129 files, 1447 signatures, 7 differing`, and that **7 is FILES, not signatures**: the
tally is of files with at least one differing signature.  The real numbers are **22 differing
signatures in 7 files**, and at the byte level **13 of 129 `.ei` (70 lines)** plus **46 of 1,301
`browse.txt` lines**; `groups.txt` is byte-identical.

**Which, and why each is intended.**  Two classes, both from adoptions COMMITTED after the
baseline was recorded in `7ebcbfa` (2026-08-31):

* `Relation/Scan.ei :: sumBy'` — F3 (`775a20f`, 2026-09-08) deleted a vacuous `r <- (h, t)`
  from the WRITTEN signature in `Relation/Scan.e` by hand.  The baseline still carried it.
  This is the one the drift check was really reporting, and it is C12's own shape — the
  hand-fix S5 generalises.
* the other 21 — `(&)`, `(&_Mem)`, `(**)`, `dateDiff`, `dateRange`, `lookbackJoin`,
  `setColumn`, `maxRowBy`, `minRowBy`, the `Predicate` comparisons, four `Layout/Report`
  drilldowns and so on: alpha-variants and part-order differences, the churn `smallcanon`
  (A1, `fe024a7`, 2026-09-06) and `topNormalise` (S4c, 2026-09-08) produce and which both
  adoptions measured and accepted.

**S5 changes none of them, verified before the re-cut.**  `Layout/Scan.ei` — the only file S5
moves — is not among the 13, and all 13 are byte-identical between S5's flag-OFF and flag-ON
snapshots.

**Form of the re-cut.**  From a fresh `g1-diff.sh run new`, with the S5.2 key header stripped,
so the baseline stays in the unkeyed form it has always had and its `git diff` is exactly the
type drift: **14 files, 116 insertions, 116 deletions**.  `G1Compare` reads through
`Session.splitInterfaceKey`, so it compares a keyed tree against this unkeyed baseline with
neither side touched.

**After:** `tracker/tools/g1-validate.sh` → **7 fixture PASS + double-run self-agreement PASS +
no drift from `tracker/g1-baseline` PASS = 9 PASS / 0 FAIL**, and the run reports `1447 sig
lines` again (Q-8).

### C. Gates, re-run after the fix round

| gate | result |
|---|---|
| `lake build` | **green, 870 jobs** |
| `lake env lean Audit.lean` | **`Rowpartition theorems audited: 4613; declarations using a non-standard axiom: 0`** (4,596 + the 17 new declarations of Q-3/Q-4) |
| `#print axioms`, all ten `tauto*` declarations | `[propext, Classical.choice, Quot.sound]` for every one |
| `sbt core/compile core/copyResources` | green |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 / 720** — `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0` |
| `corpus-run.sh --batch` + `corpus-verdicts.py` | **85 / 69 / 0 over 154**, listing **byte-identical to the pre-change run** |
| `ei-diff.sh --batch --snapshot` ×2, flag A/B, `ei-classify.py` | **`1 of 268 interfaces differ`**, `identical 3477, other 4`; byte level with the key stripped, **1 file, 8 diff lines (4 each side)** |
| the same ON snapshot, before vs after the Q-1 change | **268 of 268 byte-identical** — the editor path publishes nothing |
| `trace-ab.py`, `boot`, pre-change build vs this build at the shipped default | **`segments=54209 IDENTICAL=54209 sinmoved=0`** |
| `trace-ab.py`, `Wide`, same | **`segments=115874 IDENTICAL=115874 sinmoved=0`** |
| `repl-smoke.sh` | **green, 8 cases** — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, **tauto 5** |
| `lsp-smoke.sh` | **`PASS lsp (185 checks)`** (was 181) |
| `g1-validate.sh` | **9 PASS / 0 FAIL** (was 8 / 1, red since F3) |
| `sbt core/test` | **940 / 940**, 0 failed, 0 errors (1372 s), run alone on the tree |
