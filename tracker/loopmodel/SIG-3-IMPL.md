# SIG-3: the signature-entailment check, implemented -- DEFAULT `error`

Stage S3 of `tracker/SIG-ENTAIL-PLAN.md`, worktree `ermine-scala-wt-sig`, branch `sig-entail`
(from `d01a219`). Implements `tracker/loopmodel/SIG-2-DESIGN.md` §(e): the decision procedure
inside `Subst.subsumeType`, the `off | warn | error` flag with **`error` as the shipped
default** (the user's decision of 2026-09-11), the differential test against the committed
oracle, the five pins flipped, and the editor's copy of the diagnostic.

**SCOPE CUT MID-STAGE.** The orchestrator reduced this stage after the check was working
(2026-09-11, ~19:45): items (a) the check, (b) the differential test, (d) the pins, (e)/(f)
gates and this report are mine; **(c) the 17 signature corrections and the positive corpus
example are another agent's, on branch `sig-fixes`**, and so is the class-constraint status
page. The 17 corrections HAD been written and verified green before the cut, and they are
preserved as evidence for that agent -- see §9, which lists every before/after and the
verification. They were then reverted here (`git checkout -- core/src/main/resources/modules
core/examples`), so this branch's stdlib is the uncorrected one, and that single fact governs
how every gate below reads: **under `error` the stdlib boot itself is refused, at
`DrilldownList.cons_Bracket` and `Relation.partialLookup`, so nothing that imports `Prelude`
loads on this branch.** The check is therefore measured on the corpus under `warn` (same
decisions, no refusal) and the pins under both.

## 0. The S3 review's edits, and where each landed

`SIG-3-REVIEW.md` (verdict FIX-THEN-ADVANCE) listed eleven; all eleven are in, plus the two
landing items it flagged as not-re-runs.

| # | edit | landed |
|---|---|---|
| 1 | D2/M1: "declared at" was the EQUATION | `Subst.scala:699` passes `typ.loc` -- the DECLARED TYPE's own position -- and `SigEntail.siteOf` takes it (`:88-100`). Re-measured: the five pin headers, `RESULTS.md`'s table, `lsp-client.py`'s new second-location check, §4.1 here |
| 2 | M2: the witness sentence was not reproducible | `check` sorts the constraint lists, each `RHS.abstr` and the `extraVars` canonically (rendered name, then id) before building `LabelSearch` (`:498-520`); `prose` prints no ids at all (`:665-712`). New property "the message: two sessions, one explanation" |
| 3 | D4: the foreign-skolem guard tested only the 1-bits | `:589-601` tests the model's whole vocabulary; new property "the foreign-skolem guard: a refutation that ASSIGNS one is NO VERDICT", which also pins that the FALSE-bit case is the one the old test let through |
| 4 | D1: the empty-lhs normalisation had no Lean licence | `Rowpartition/SigEntail.lean` §9: `emptyRow`, `sat_emptyRow`, `foldr_union_eq_empty_iff`, `pairwise_disjoint_of_all_empty`, **`sat_of_lhs_empty_iff`**, **`sat_of_lhs_empty_iff_models`**. §5.2/§5.3 corrected |
| 5 | §7.3's "24 lines" | it is 25 SITES = 24 groups; §7.3 and §5.1 say so |
| 6 | `RESULTS.md`'s "secondary is the signature" | true now, and re-worded to say which position it is |
| 7 | D6: the dead `SigEntail.warn` | deleted |
| 8 | D3: the obligation search got the whole remaining budget | `math.min(cap, sigBudget - spent)` (`:561-567`) |
| 9 | D7: `modeOf` mapped a typo to `Error` | it DIES, naming `off, warn, error` |
| 10 | `sigcheck.py`'s `len(c) > 9` | `> 8`, so a `-Dermine.rowTrace` record (9 columns, no tid) keeps its `ds` column |
| 11 | `lsp-client.py`'s one-space indent | fixed, and the block gained the second-location check |
| + | the differential hard-coded 310 / 284-24-2 | the counts come from `verdicts.tsv`; the property compares the ENGINE's tally with the RESOURCE's and prints the split, so the `sig-fixes` merge needs no test edit |
| + | `ErmineFixture`'s default was `Some(Off)` | it is the shipped default now; the twenty fixtures that BOOT the stdlib pass `ErmineFixture.untilSigFixes`, one named value to delete when the corrections land |

## 1. What the check is

At every `subsumeType(declared, inferred, Some(site))` -- a user signature, `sig` or `ann`,
never the `App` case -- with `Q` the signature's row givens, `W` the body's row obligations
and `F` the solver-minted variables of `W`:

    the signature is honest iff for every rho with rho |= Q there is rho' agreeing with rho
    off F such that rho' |= W.

`F = vars(W) ∩ pxs \ vars(Q)` -- rigidity is read off the variable's provenance in THIS
residual (`pxs` is what `unbindExists(Free, substType(pz))` minted at `Subst.scala:548`),
never off the call's skolem list. The judgement is decided LABEL CLASS by LABEL CLASS: one
2QBF per literally mentioned column plus ONE generic class standing for every column mentioned
nowhere, each decided by enumerating the models of `Q` over the rigid variables and asking
whether `W` is satisfiable with the minted bits free. Soundness and completeness of that
decomposition are `sigEntails_of_lsig` / `lsig_of_sigEntails` in
`tracker/lean/Rowpartition/SigEntail.lean` (unchanged this stage; only the `import` line in
`Rowpartition.lean` is new).

## 2. The diff, by site

| file | lines | what |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/SigEntail.scala` | 1-100 (header, `Mode` + `modeOf`'s refusal, `Site` + `siteOf`'s secondary location), 273-297 (`probe`, +`ds` column), 291-382 (`Row`, `Enc`, `encode` -- the encoding contract incl. the empty-left-hand-side normalisation), 384-415 (`Verdict`, the two budgets, `Cost`), 418-625 (`check`: the closure fixpoint, the canonical order, the per-class cap, the foreign-skolem guard), 627-662 (`blame`, `className`), 665-712 (`displayNames`, `prose` -- the id-free witness sentence), 714-730 (`lines`), 731-790 (`enforce`) | the whole check, +620 lines over the S1 probe |
| `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala` | 2746-2781 (`decideLabel`, now a wrapper), 2783-3047 (`LabelSearch`) | the per-label one-hot engine LIFTED out of `decideLabel`: same propagation, same search order, plus `freeze` (a frozen partial assignment), `enumerate` (all models over a variable order), a label PREDICATE instead of a `Name` (so a synthetic generic class is expressible), `extraVars` (variables branched over though no constraint mentions them) and `reset` |
| `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala` | 95-102 (`SubstEnv.sigEntail`), 549-567 (the call, with its placement rationale), 672 (`ann`) and 690-700 (`sig`, now passing the DECLARED TYPE's own `Loc`) | one new call after the `:548` partition; `:555-556`'s class-only `entails` loop, `restrictTypes`, `mkSimplified` and `ds` untouched |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/SessionState.scala` | 3, 109-113, 133-141 | `SessionEnv._sigEntail` / `sigEntail`, carried by `copy` |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/Session.scala` | 59-60, 168-177 | `Session.subst` passes the session mode into `SubstEnv`; `interfaceKey` appends `|sigEntail=error` in that mode only |
| `scalacheck-binding/src/main/scala/TestErmine.scala` | 49-70 | `ErmineFixture(sigEntail = ...)`, the session-option mechanism; fixture default `Off` (§7 says why) |
| `scalacheck-binding/src/main/scala/TestSigEntail.scala` | whole file | the four KNOWN HOLE properties are `no(...)`; the flag group; the `off` fixture |
| `scalacheck-binding/src/main/scala/TestSigEntailDiff.scala` | new, 330 lines | the differential test (§5) |
| `scalacheck-binding/src/main/scala/TestInterfaceKey.scala` | 143-171 | `notInKey` gains `sigentail`, checked against the `GenRules` half; the suffix checked exactly |
| `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` | 30-35, 53-56, 126-146 | the editor's two properties (§6) |
| `core/examples/shouldfail/sig0{1..5}_*.e`, `shouldfail/RESULTS.md` | headers + the class-6 section | the pins, flipped, each with its measured message verbatim (§4) |
| `tracker/tools/sigcheck.py` | new (committed oracle) | S2's procedure, with the `ds` column, `--assert-qsat`, `--records`/`--tsv`, and the two fixes the differential found (§5.2) |
| `core/src/test/resources/sigentail/{records,verdicts}.tsv` | new | the differential's input and expected output, regenerable in one command |
| `tracker/lsp-tests/SigEntail.e`, `tracker/tools/lsp-client.py` | new fixture; +27 lines | the editor check over the wire (§6) |
| `tracker/lean/Rowpartition.lean` | +1 | `import Rowpartition.SigEntail` |

## 3. The flag

`-Dermine.sigEntail=off | warn | error`, DEFAULT **`error`**. Read once per JVM into
`SigEntail.defaultMode`; the mode the checker actually consults is per SESSION
(`SessionEnv.sigEntail` -> `SubstEnv.sigEntail`), so one JVM can hold two modes and a test
fixture needs no `System.setProperty`.

| point | `off` | `warn` | `error` (default) |
|---|---|---|---|
| `Site` allocation (`Subst.scala:672`, `:690`) | none | allocated | allocated |
| the check runs | no | yes | yes |
| the S1 probe records (`sigEntail\t...`) | not printed | printed | not printed |
| an obligation not entailed | -- | `warning:` + the §4 message, load continues | `Death`: the §4 message, module refused |
| the signature's givens have NO MODEL | -- | `warning:` "the signature's constraints have no solution" | `Death`, same wording; the body is not blamed |
| NO VERDICT (budget, an unreadable constraint, a foreign skolem) | -- | one `warning:` line naming the reason, ACCEPT | one `warning:` line naming the reason, ACCEPT |
| `Session.interfaceKey` | `<v>\|<GenRules>` | `<v>\|<GenRules>` | `<v>\|<GenRules>\|sigEntail=error` |
| corpus behaviour (this branch) | identical to pre-S3, 165/165 (§7.2) | identical verdicts, +24 diagnostics | stdlib boot refused (§7.3) |

`error` is not a guarantee: a NO VERDICT accepts, by design, and says so on stderr.

The interface key is APPENDED rather than folded into `GenRules.toString` because the
staleness test is `key contains interfaceKey` (`Session.scala:472`): an `.ei` written under
`error` still matches under `off`, while one written under `off` is rebuilt under `error` --
the direction wanted, and the `off` default's bytes are unchanged from pre-S3.

## 4. The message, and one worked example per rejection class

Schema (design (d3)): the first line is the OBLIGATION's position when it is in the file being
compiled, else the signature's, with the foreign position quoted; then the wanted and the
givens AS THE CHECK READ THEM (`SigEntail.render`, which carries ids and flavours -- `S`
skolem, `A` the existential `unbindExists` minted, `B` a dangling `Bound` -- because
`Pretty.prettyType` restarts its letter supply per call and would print two different `r`s the
same way); then the witness in prose; then any ignored given; then `declared at`.

### 4.1 A literal label class, empty witness -- `shouldfail/sig01` (`sig` site)

```
core/examples/shouldfail/sig01_unconstrained_signature.e:70:17: the signature does not entail this row constraint
    wanted   r^579411S <- ((|ShouldFail.Sig01.health|), _^579413A)
    given    (none)
  no rows satisfying the givens satisfy it: take the column `ShouldFail.Sig01.health` to be in
    none of the signature's rows (r) -- the givens allow that, and no choice of _1 (the
    solver's own, which may be any rows) then satisfies the wanted
  declared at core/examples/shouldfail/sig01_unconstrained_signature.e:69:13 (sig healthOpt)
```

70:17 is the body's `!`; **69:13 is the DECLARED TYPE**, on the signature line -- not the
equation's head, which is where `binding.v.loc` and `binding.ty.loc` both point and which
collapses the two locations onto one line for a one-line body (S3 review M1).  The witness
sentence carries no id and no position: a nameless minted variable is `_1`, `_2`, and the
solver's own copy of a source name is that name with a PRIME (`t'`), so the sentence is a
function of the source rather than of the ids the run minted (review M2).

### 4.2 The GENERIC class, a stdlib case -- `Layout.Report.Keyed.softRelation`

No column occurs literally anywhere in the system, so the whole decision is the ONE generic
class -- the case no refutation-shaped procedure reaches ("`X` meets `sk`" is not "`X` is
inside `sk`"), and where 16 of the 24 corpus rejections are decided:

```
.../modules/Layout/Report/Keyed.e:59:6: the signature does not entail this row constraint
    wanted   o^605241A <- (k^605221S, v^605224S)
    given    (AsPresentation prvd^605223S); (AsPresentation prk^605220S)
  no rows satisfying the givens satisfy it: take a column named nowhere in the signature to be
    in k and in v -- the givens allow that, and no choice of o' (the solver's own, which may be
    any rows) then satisfies the wanted
  declared at .../modules/Layout/Report/Keyed.e:52:1 (sig softRelation)
```

The two givens are class constraints: dropped, because the judgement is row-only by
construction, and the message shows them so the reader can see what was and was not used.

### 4.3 An IGNORED GIVEN -- `DrilldownList.cons_Bracket` (design (a4))

`DrilldownList.e` has no `import Constraint`, so `Has` is closed over as an ordinary type
variable and the three givens constrain nothing. Without the note the rejection is unreadable:

```
.../modules/DrilldownList.e:20:98: the signature does not entail this row constraint
    wanted   rout^434555S <- (f2^434553S, r^434562A)
    given    ((Has^434185B rout^434555S) r^434554S); ((Has^434185B rout^434555S) f2^434553S); ((Has^434185B rout^434555S) f1^434551S)
  no rows satisfying the givens satisfy it: take a column named nowhere in the signature to be
    in rout, and in none of f1, f2, r -- the givens allow that, and no choice of r' (the
    solver's own, which may be any rows) then satisfies the wanted
  ignored given  `((Has^434185B rout^434555S) r^434554S)`: an application of a type VARIABLE,
    which constrains no row here -- is `Has` in scope? `Has` lives in `Constraint`
  ignored given  `((Has^434185B rout^434555S) f2^434553S)`: ... (same for the third)
  declared at .../modules/DrilldownList.e:20:1 (sig cons_Bracket)
```

Note how the prose distinguishes the two `r`s -- the signature's own and the solver's copy of
it, which keeps the name it was refreshed from: the copy gets a PRIME (`r'`).  An earlier draft
disambiguated with `^id`, which made the sentence depend on the ids the run minted; the
`wanted`/`given` columns still carry them, because there they are the unambiguous spelling.

### 4.4 NO VERDICT with a named reason -- a constraint the model cannot state

Two corpus signatures (`Layout.Report.Relation.largers`, `.small`) reach it, verbatim from the
warn sweep:

```
warning: the signature-entailment check gave NO VERDICT at .../Layout/Report/Relation.e:82:3
  (sig largers: every class the check could build is satisfied, but an obligation was dropped
  as unreadable, so the real obligation set may be larger -- the partition has a NON-EMPTY
  literal column set on its LEFT ((|Layout.Report.Relation.cutoff|)), which the decision
  procedure's model cannot state); this signature is accepted on the shipped rules alone
```

and are ACCEPTED. `error` still accepts a no-verdict -- that is the flag table's last row, and
it is why `error` is not a guarantee. The same shape appears as a FOREIGN-SKOLEM no-verdict
(a wanted mentioning an enclosing signature's skolem, whose own row facts are not in `Q`) and
as a BUDGET no-verdict; none of the latter two fires on this corpus.

## 5. The differential test

`scalacheck-binding/src/main/scala/TestSigEntailDiff.scala`, six properties, all green.
The Lean theorems are about `sigDecide`, an enumerating specification; what ships is a third
algorithm (the lifted `LabelSearch` with dedup, propagation, budgets, and a `Type -> RHS`
encoder). It is pinned from two sides.

### 5.1 The corpus: 310 signatures against the committed oracle

Input `core/src/test/resources/sigentail/records.tsv` (937 deduped probe records: module,
binding, wanted, givens, `ds`), expected `verdicts.tsv` (310 lines: verdict, module, binding,
label class). Both regenerate in one command, which is in the test's own header:

```
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh --batch /tmp/corpus-warn
tracker/tools/sigcheck.py /tmp/corpus-warn --assert-qsat \
  --records core/src/test/resources/sigentail/records.tsv \
  --tsv     core/src/test/resources/sigentail/verdicts.tsv
```

**Counts: 310 signatures, 284 ACCEPT / 24 REJECT / 2 NO VERDICT, and the Scala agrees with the
oracle on every one -- verdict AND label class.** Re-measured on a SECOND sweep taken with the
final build: `verdicts.tsv` reproduces byte for byte; `records.tsv` does not and cannot (a
fresh run mints different variable ids and its given sets come out of a `Set` in a different
order), so the two resources must always be regenerated from ONE sweep -- which the command
above does, and the test's header says so. (I chose the committed Python oracle over a
Scala port of `sigDecide`: it is the implementation the S2 reviewer differentially tested
against brute force and an independent DPLL on 36,000 systems, so agreeing with it inherits
that evidence, and a Scala port of `sigDecide` would share the encoder with the thing under
test -- the encoder being where the two implementations actually differed, twice, below.)

`--assert-qsat` checks the design's (a2) hypothesis on the same data: **0 of 310 signatures
have a label class at which the GIVENS have no model**, so the completeness half applies
everywhere on this corpus and the vacuous-givens branch is policy, not throughput.

### 5.2 What the differential caught (both in the ORACLE, which is now corrected)

1. **The closure of design (a3) is a fixpoint in `F`, not one pass with the `F` of `rs`.**
   A `ds` member pulled into `W` can mention minted variables `rs` never did, and a second
   `ds` member sharing one of THOSE constrains the same choice -- the body's residual is one
   conjunction. The S2 oracle closed with the `F` of `rs` alone; the Scala recomputes `F` each
   round. They differ on `Layout.Report.Relation.others`: same REJECT, one label class earlier
   (`cutoff` rather than `cutoffChild`). Fixed in `sigcheck.py`; the fixpoint reading is the
   one the design's own wording implies (`F` is defined from `W`, and `W` from `F`).
2. **`(||) <- (p1..pk)` -- the empty row on the LEFT -- must be normalised, not dropped.**
   269 of the corpus's `ds` constraints have that shape, and TWO verdicts depend on them
   (§7.4). It is equivalent to `p1 <- () & ... & pk <- ()`, and that equivalence now has a
   Lean statement of its own -- **`SigEntail.sat_of_lhs_empty_iff`** (`Sat rho c` with
   `rho c.lhs = ∅` iff `c.conc = ∅` and every variable part is empty, both directions, the
   disjointness half falling out of `pairwise_disjoint_of_all_empty`) and
   **`sat_of_lhs_empty_iff_models`**, which states it against the very list of `v <- ()`
   constraints the encoder emits (`emptyRow`). `Basic.Sat.eq_empty_of_dup` licenses only the
   REPEATED-part rule and was mis-cited for this one in the first draft of this report
   (S3 review D1). The S2 oracle silently dropped these constraints (`parse_constraint`
   returned `None`) and the first Scala draft called them NO VERDICT.

### 5.3 The encoding contract (design (e) 2b), as properties rather than a promise

`Type` is wider than either model: `Part.apply` can leave two OVERLAPPING concrete parts
unmerged (`Type.scala:427-429`) and can build a CONCRETE left-hand side (`:421-424`), while
`Constraints.RHS` has one `concr` field and Lean's `Constraint` one `conc`. The rules
implemented, each with a property of its own (§7.5):

* a REPEATED variable part is normalised to "that variable is empty" and deleted from the
  partition (`Basic.Sat.eq_empty_of_dup`, whose hypothesis is `2 ≤ c.vars.count v`);
* `(||)` on the left is normalised to "every part is empty"
  (`SigEntail.sat_of_lhs_empty_iff` / `sat_of_lhs_empty_iff_models`, added at S3);
* anything else the model cannot state -- a NON-EMPTY literal set on the left, two or more
  literal sets on the right, a part that is neither a row variable nor a literal set -- is
  **DROPPED BY NAME, and the drop forbids exactly one verdict**: a dropped GIVEN forbids
  REJECT (the real context may be stronger), a dropped OBLIGATION forbids ACCEPT (the real
  obligation set may be larger, and rejection is MONOTONE in `W` -- if some model of `Q`
  extends to no model of `W0 ⊆ W`, it extends to none of `W`).

That one-sided rule is a deliberate strengthening of the design's blanket "NO VERDICT": the
design forbids a silent MERGE, and monotonicity licenses keeping the verdict that a smaller
obligation set still justifies. It is what keeps a rejection available when some unrelated
corner of the residual is unreadable, while `Layout.Report.Relation.largers` and `.small` --
whose `ds` half carries `(|cutoff|) <- (e, f)`, a NON-EMPTY literal set on the left -- are
honestly left undecided rather than either accepted or rejected. The proof obligation the
remaining case would need (`C <- parts` iff `∃z. z <- parts ∧ z <- (C)`, `z` fresh and
determined) is the S4 item that would decide those two.

### 5.4 2,000 random systems against exhaustive enumeration

A generator of small systems (≤ 5 variables split rigid/minted, ≤ 2 givens + ≤ 2 wanteds,
≤ 2 literal labels; givens are rebuilt over the rigid variables only, since `F ∩ voc(Q) = ∅`
is an invariant of the judgement) against a brute-force decision written out in the test --
`sigDecide`'s own definition, no propagation, no dedup, no budget. **2,000 tests, 0
disagreements.** This is the property the engine's optimisations could break with no corpus
signature noticing.

### 5.5 Cost, in the ENGINE's own counter (design (b4)'s S3 acceptance item)

The S2 headroom figure compared the oracle's propagation POPS with `rowSoundBudget`'s DECISION
NODES -- 8x in mismatched units. Measured over all 310 corpus decisions with the engine's own
counter (a property, so it cannot go stale):

    ### SIG-3 cost (the engine's own decision-node counter): decision nodes max 259
    median 3 p90 11 total 2323; models of Q at one class max 256 median 4;
    label classes max 7; 310 groups

So the whole corpus costs **2,323 decision nodes**, the worst single signature **259**, against
a per-class budget of 200,000 and a per-signature cap of 1,000,000 -- three decimal orders of
magnitude of headroom, in the SAME unit as the budget. (The oracle's 24,109 "propagation
steps" at its maximum is a different quantity -- queue pops, not case splits -- which is
exactly why the design asked for this measurement before the budget was fixed.) The two
budgets are constants in `SigEntail.scala:396-402`, not system properties and not `GenRules`
fields: nothing may reach the interface key by accident.

## 6. The editor

`session/TolerantCheck.scala` calls `typeCheckExplicitBinding` itself (`:727`, inside
`guard(Error)`), so the diagnostic reaches the editor with no editor-specific code -- and must,
or a file `bin/ermine` refuses would look clean in the IDE. Pinned twice:

* `TestTolerantCheck`: "a signed binding whose context is too weak is one Error note, in the
  editor" and its silent honest twin. The note's BOTH positions are pinned exactly -- it
  starts `TC:10:17:` (the body's `!`) and contains `declared at TC:9:13 (sig healthOpt)` (the
  declared type on the signature line) -- so the review's M1 is pinned on the editor path as
  well as in the pins. Both properties run under a fixture with the session option `Error`,
  beside the suite's `untilSigFixes` fixture, in one JVM.
* `tracker/lsp-tests/SigEntail.e` + 6 checks in `tracker/tools/lsp-client.py`: over the wire,
  one diagnostic, severity 1, the entailment message, the `declared at` line, the range on the
  body's `!` (0-based line 18) and that the second location is `SigEntail.e:18:11`, the
  signature's declared type. The fixture imports `Field` and `Primitive` rather than `Prelude`
  so that it does not depend on the stdlib corrections, and `lsp-smoke.sh` now passes
  `-Dermine.sigEntail=$ERMINE_SIGENTAIL` to the server it spawns so the same fixtures can be
  driven both ways -- under `off` the block asserts the file is CLEAN instead (one check).
  Measured directly with `bin/ermine` (which checks this fixture even while the `Prelude` boot
  is refused): `tracker/lsp-tests/SigEntail.e:19:15: the signature does not entail this row
  constraint ... declared at tracker/lsp-tests/SigEntail.e:18:11 (sig tooWeak)`.

## 7. Gates

All in this worktree, on the working tree of this stage, with
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`.
`tracker/repl-classpath.txt` was regenerated from this worktree's `target/ermine-classpath`
for the smokes and `git checkout`ed back afterwards; every `.ei` any run produced was deleted
(`find . -name '*.ei' -not -path './tracker/g1-*'` = 0).

**Read the `error` rows against §0: this branch's stdlib is the UNCORRECTED one.**

### 7.1 Suites

| gate | command | result |
|---|---|---|
| `TestSigEntail`, the differential, the key, let signatures and `TestLoopTrace` (the main checkout's `looptrace` binary) | `sbt 'core/testOnly *TestSigEntail *TestSigEntailDiff *TestInterfaceKey *TestLetSignatures *TestLoopTrace'` | **36/36 pass, 0 fail** after the review's edits: TestSigEntail 13 (+"the message: two sessions, one explanation"), TestSigEntailDiff 8 (+"the foreign-skolem guard"), TestInterfaceKey 2, TestLetSignatures 10, loop model trace 3 |
| `TestTolerantCheck` + `TestTolerantRead` + `TestReplDifferential` | `sbt -Dermine.sigEntail=off 'core/testOnly ...'` | **61/61 pass, 0 fail** -- including the two new SIG-3 editor properties, which ask for `Error` through the fixture and so run in both modes |
| `TestTolerantCheck` alone AT THE DEFAULT (`error`), re-run after the review's edits | `sbt 'core/testOnly *TestTolerantCheck'` | **44 pass, 2 fail, 3 errors of 49** (unchanged by the edits; both SIG-3 editor properties among the 44).** All five are stdlib-boot casualties: three build a `Resident` (whose `SessionEnv` takes the process default) and two sweep the whole corpus, so they die on `DrilldownList.cons_Bracket` rather than on their own subject. Both SIG-3 editor properties pass here too (they construct their own `Error` session). The five pass under `off` (row above) and will pass at the default once `sig-fixes` lands. NOT a finding about the check |
| the controls, under `warn`, in one JVM | `bin/ermine core/examples/shouldfail-controls/control08_sig_declared.e control09_let_signatures.e core/examples/Lang/LetSignatures.e` | **all three import, and not one diagnostic names them** -- `control08`'s four honest spellings (including the `Has` one, whose alias `substAlias` expands before the check reads it), `control09`'s five let shapes and `Lang/LetSignatures.e`'s row-constrained let signature |
| `TestConstraints` (the engine refactor's own suite) | `sbt -Dermine.sigEntail=off 'core/testOnly *TestConstraints'` | **17/17** |
| the nine suites whose fixtures now say `untilSigFixes` (the fixture-default flip's fallout) | `sbt 'core/testOnly *TestLower *TestNewPipeline *TestScopes *TestTolerantRead *TestEditorBuffers *TestDateAndScan *TestStage1Pins *TestReplDifferential *TestRecordPrims'` | **138/138 pass, 0 fail, 0 errors** (stage-1 pins 34, scoping 30, Lower 28, editor buffers 12, Date/Scan 12, tolerant read 11, record primitives 8, NewPipeline 2, REPL goldens 1). The flip changed only WHICH mode these fixtures ask for -- the same `off` they had before S3 -- so this is a regression check on the mechanical edit, and it is clean |

### 7.2 The corpus, `off` versus `warn`: the check is inert, and changes no verdict

```
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=off"  tracker/tools/corpus-run.sh --batch $S/corpus-off
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" tracker/tools/corpus-run.sh --batch $S/corpus-warn
python3 tracker/tools/corpus-verdicts.py $S/corpus-off      # 91 LOADED, 74 REJECTED, 0 UNKNOWN, 165 total
python3 tracker/tools/corpus-verdicts.py $S/corpus-warn     # identical, file for file
```

* verdicts: **0 of 165 differ** (`diff` of the two verdict listings is empty);
* output: **0 of 165 `.out` files differ** once the probe records, the check's own warnings and
  the wall-clock noise (progress bar, `(N.NN seconds)`) are stripped -- the filter is
  `scratchpad/S3/strip2.py`, and it removes NOTHING else;
* `.ei` under `off`: `JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/g1-validate.sh`
  -- **every oracle fixture PASS, double-run self-agreement PASS, `no drift from
  tracker/g1-baseline` PASS**, 129 modules / 1447 signature lines / 20 s per boot. That
  baseline was recorded before S3, so it IS the "byte-identical to HEAD" gate, and it is the
  sharpest one available: it catches an inference change that still renders alpha-equal.

### 7.3 The corpus under `error`: one cause, 165 modules

```
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=error" tracker/tools/corpus-run.sh --batch $S/corpus-error
```

`batch-split` REFUSES the run ("no 'Loaded N modules' line -- the boot did not finish"), which
is the honest verdict: the standard library itself is refused, so no corpus module is ever
compiled. From `batch.log`: **164 `Unable to load module from ...` (every file), 163
entailment rejections, blamed on `Relation.partialLookup` 162 times and
`DrilldownList.cons_Bracket` once** (the boot dies at whichever of the two the dependency
order reaches first). Movement table, `error` against `off`:

| modules | under `off` | under `error` | why |
|---|---|---|---|
| 91 | LOADED | REFUSED | the stdlib boot is refused before their own code is read |
| 74 | REFUSED (their own error) | REFUSED (the stdlib's) | the message changes, the verdict does not |
| 0 | -- | -- | no module is refused for a signature of its OWN on this branch, because none is reached |

**The check's real corpus verdict is therefore taken under `warn`**, which decides exactly the
same judgement and accepts. Two independent readings of the same sweep agree:
`tracker/tools/sigcheck.py $S/corpus-warn --assert-qsat` (the oracle) reports **310
signatures, 284 ACCEPT / 24 REJECT / 2 NO VERDICT**, and the SHIPPED ENGINE's own diagnostics
in that sweep name **25 rejected SITES = the same 24 oracle groups and no others** (`grep -A14
'warning: the signature does not entail' | grep 'declared at' | sort -u` = 25 lines: `sig05` is
rejected at BOTH of its annotations, which the oracle's `(module, binding, givens)` key merges
into one group) plus **exactly 2 NO VERDICTs**
(`Layout.Report.Relation.largers` at `:82:3` and `.small` at `:113:3`, both the §4.4 message).
The 24 are:

| # | where | signatures |
|---|---|---|
| 7 | **stdlib** (5 modules) | `Relation.UnifyFields.unify1`, `Relation.partialLookup`, `DrilldownList.cons_Bracket`, `Layout.Report.Keyed.softRelation`, `Layout.Report.Keyed.keyValueTabular`, `Layout.Report.Relation.cutoffs`, `Layout.Report.Relation.others` |
| 10 | examples (4 modules) | `Wide.Helpers.melt2/melt3/melt4`, `Wide.Signatures.melt3Simple`, `Algebra.Signatures.runningTotalFullViaWritten`, `Time.Helpers.dayCount/monthsBetween/monthsSince/daysSince/daysUntil` |
| 5 | the PINS | `sig01.healthOpt`, `sig02.wrongLabel`, `sig03.local` (let-bound), `sig04.bump`, `sig05`'s annotation |
| **2** | examples, **NEW** | `Time.Signatures.yearFrac365Full`, `Time.Signatures.yearFrac365Simple` -- §7.4 |

(24 oracle GROUPS; 25 sites, because `sig05` carries two annotations and the group key merges
them.  The differential is a differential of the JUDGEMENT on the merged system, not a per-site
pin -- one of the three blind spots §8 records.)

That is the S2 design's 17 + the 5 pins (S2 had 4: `sig03` joined when LET-1 merged) + 2 new.
Nothing else moved: **no signature outside the design's list is rejected**, which is checklist
item 9's criterion, restated for `W = the closure` as (a3) requires.

### 7.4 The design's predicted stop point, fired: 2 new (c) items

Design (a3) said the 17-signature criterion is valid **for `W = rs`** and that re-stating it
under the closure could move a verdict -- "a new (c) item and a stop point, not a bug". It
moves exactly two, and both are real:

`Time.Signatures.yearFrac365Full` and `.yearFrac365Simple` have NO givens and three
obligations (`out <- (f,e,d)`, `r1 <- (so,rs)`, `r <- (ro,rs)`), and their skolem-free half
carries `(||) <- (f, e)`, `t <- (ro,so,rs)` and `t <- (e,d)`. The closure pulls those in --
they share `f`, `e`, `d`, `ro`, `so`, `rs` with the obligations -- and then `f = e = ∅` forces
`out = d = t = ro + so + rs` while `r = ro + rs` and `r1 = so + rs`: `out` is the UNION of the
two operand rows and nothing constrains it. It is `dayCount`'s hole in the file that documents
`dayCount`'s hole. S2 called `yearFrac365Simple` "the instructive one, ACCEPTED because its
wanteds share one minted variable rather than two" -- true of `rs` alone, false of the
residual. Measured both ways: with `W = rs` the corpus rejects 22 (the 17 + 5 pins, exactly
S2's list); with the closure, 24.

### 7.5 The differential test

| property | result |
|---|---|
| the corpus: 310 signatures against `tracker/tools/sigcheck.py` | **all agree, verdict and label class** |
| the expected counts are 284 / 24 / 2 | pass (a guard on the resource itself) |
| 2,000 random systems against exhaustive enumeration | **2,000 tests, 0 disagreements** |
| encoding contract: a repeated part | pass |
| encoding contract: the empty row on the left normalises AND decides (with/without the `ds` half) | pass |
| encoding contract: a non-empty literal set on the left is dropped and forbids ACCEPT | pass |
| cost, in the engine's counter | pass (§5.5) |

### 7.6 The smokes

| gate | result |
|---|---|
| `JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/repl-smoke.sh` | **PASS 8/8** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 = 66 checks) |
| `ERMINE_SIGENTAIL=off tracker/tools/lsp-smoke.sh` | **PASS, 546 checks** -- 545 as the branch had them plus the one new escape-hatch check (`SigEntail.e` is clean under `off`) |
| `tracker/tools/lsp-smoke.sh` at the default (`error`) | **FAIL, and for the one cause**: the server's session cannot BOOT (`Ermine session failed to boot: DrilldownList.e:20:98 ...`), so the client times out at its first check. The five `SigEntail.e` checks therefore have their `error` evidence from `TestTolerantCheck` (which constructs its own `Error` session) rather than over the wire; re-run this gate after `sig-fixes` |
| `JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/g1-validate.sh` | **PASS** (all fixtures, self-agreement, no baseline drift) |
| `lake build Rowpartition` after adding `import Rowpartition.SigEntail` and §9's five theorems | **success, 871 jobs** |
| `lake env lean Audit.lean` | **4676 Rowpartition theorems audited; 0 declarations using a non-standard axiom** (4613 before the import, 4670 with it, +6 for §9's `emptyRow` lemmas) |
| `.ei` droppings | 0 (the `g1` run's 129 interfaces deleted afterwards) |

### 7.7 What is NOT green, and why -- the whole list

1. `lsp-smoke.sh` at the default, and 5 of `TestTolerantCheck`'s 49 properties at the default
   (3 build a `Resident`, 2 sweep the corpus): the stdlib boot is refused at
   `DrilldownList.cons_Bracket`. ONE cause, another branch's fix, everything green under `off`
   -- and the two SIG-3 editor properties pass in BOTH modes, because they construct their own
   `Error` session rather than inheriting the process default.
2. The five `SigEntail.e` checks in `lsp-client.py` cannot run over the wire on this branch
   (the server cannot boot under `error`); their `off` twin runs, and the diagnostic and both
   its positions are measured directly with `bin/ermine` on the same fixture (§6) and pinned in
   `TestTolerantCheck`. After the merge, `lsp-smoke.sh` at the default is the gate that closes
   this row -- the review's landing checklist expects 550 checks there.
3. Nothing else.

## 8. S4 list

1. **The concrete-left-hand-side encoding.** `C <- (p1..pk)` with `C` non-empty is the only
   shape still dropped (2 corpus signatures, both in `Layout/Report/Relation.e`). The
   encoding is a fresh DETERMINED variable `z` with `z <- (p1..pk)` and `z <- ((|C|))`, `z`
   chosen; it needs one Lean lemma (equivalence, with `z` fresh) and it would decide both.
2. **The ambient-meta measurement** design (a) defers to S4: the per-site flavour histogram of
   `vars(W) \ (pxs ∪ vars(Q))` under `warn` on the EDITOR path, whose ambient environment is
   much richer than a batch build's. The conservative reading (everything not minted here is
   rigid, with a foreign-skolem no-verdict) is what ships; the corpus cannot tell it from the
   permissive one, since no bare-`Free` variable occurs in any wanted.
3. **Editor parity beyond the diagnostic**: quick-fix ("add the constraint the body needs" is
   mechanical -- the check has the wanted in hand), and the hover text for a binding whose
   signature is only accepted by a no-verdict.
4. **The two `Time.Signatures` rejections** the `ds` closure adds (§7.4) are new (c) items for
   whoever owns the corrections; they are NOT in the S2 design's 17.
5. **D5, the interface key reads the PROCESS mode while the check reads the SESSION mode**, so a
   session that differs from the process default -- which is what the new mechanism exists to
   allow -- writes a key describing the wrong mode. Harmless today (every fixture sets
   `useInterface = false`, and no production path sets a per-session mode), and commented at
   `Session.scala:168`; the fix is to thread the session mode into `interfaceKey`, which means
   threading a `SessionEnv` into it.
6. **The differential's three blind spots** (review §3), each cheap to close: the group key
   `(module, binding, givens)` MERGES two sites with the same name and givens (`sig05`), so it
   is not a per-site pin; `pxsOf` in the test counts bare `Free` as minted, the PERMISSIVE
   ambient rule rather than the conservative one that ships (corpus-blind: no bare `Free`
   occurs); and the 2,000 random systems all have `ds = Nil`, so the CLOSURE -- where both
   oracle bugs were -- is covered only by the corpus and one hand-written property.
7. **`ErmineFixture.untilSigFixes`**: delete the value and its twenty uses once `sig-fixes` has
   landed, so every suite runs at the shipped default, and run `core/test` once.
8. `repl-smoke.sh` and `g1-diff.sh` have no way to pass a per-run system property
   (`g1-diff.sh` exports an empty `G1_PROPS`, overwriting the caller's); both were driven here
   through `JAVA_TOOL_OPTIONS`, which works but is a blunt instrument.

## 9. The 17 corrections, verified and handed over

Written and verified before the scope cut, then reverted from this branch. The full patch is
`scratchpad/S3/17-corrections-VERIFIED.diff` (9 files). **Verification: with all 17 applied,
`bin/ermine` under the DEFAULT `error` loads the whole stdlib (129 modules) plus
`GridExample.e` (which imports `Layout.Report.Keyed`), and `Wide/Helpers.e`,
`Wide/Signatures.e`, `Algebra/Signatures.e` and `Time/Helpers.e` each load clean.** Two
cautions for the agent applying them: `core/src/main/resources/modules/Relation.e` and
`Layout/Report/Keyed.e` have **CRLF** line endings (edit byte-wise; a Python text-mode rewrite
converts the whole file), and `.e` files under `core/src/main/resources` must be re-copied with
`sbt core/copyResources` before `bin/ermine` sees them.

| # | signature | before (context only) | after | discharges |
|---|---|---|---|---|
| 1 | `Relation/UnifyFields.e unify1` | `r <- (h,f,t), r2 <- (h,f2,t)` | `r <- (h,f2,t), r2 <- (h,f1,f2,t)` | `f1` is in NO given, yet the body renames it inside `r2 \ f2`. Keeps the body; the unused `f` disappears; `unify1` has no caller |
| 2 | `Relation.e partialLookup` | `RelationalComb rel, PrimitiveAtom a, kv <- (key,val), r <- (key,base)` | `exists r2. ... , r2 <- (key,val,base)` | nothing made `val` disjoint from `base`; at `base = val` the body cannot run. `r2` is EXISTENTIAL (the result row is `r`) |
| 3 | `DrilldownList.e cons_Bracket` | `Has rout f1, Has rout f2, Has rout r` (vacuous: `Has` not in scope) | `rout <- (f1, f2, r)` | the explicit partition, not `import Constraint`: `Has` gives containment, the body needs pairwise DISJOINTNESS |
| 4 | `Layout/Report/Keyed.e softRelation` | `AsPresentation prk, AsPresentation prvd` | `exists o. ..., o <- (k, v)` | the wrapper had dropped `Layout.Report.softRelation`'s own row constraint |
| 5 | `Layout/Report/Keyed.e keyValueTabular` | `Relational rel, Relational rel2` | `exists o. Relational rel, Relational rel2, r2 <- (k,v,i), r2 <- (k,v,i,cid,pid), r2 <- (k,v,i,r), i <- (label,o)` | the body dispatches ONE relation to all four `Layout.Report` key-value tables, so it inherits all four contexts. Written out they say something worth knowing: the three partitions can hold together only with `pid`, `cid` and `r` EMPTY -- the body has always demanded that, and splitting the wrapper is an API change, out of scope |
| 6 | `Layout/Report/Relation.e cutoffs` | result row `r <- (p, v, (\|cutoff\|))` | `r <- (p, (\|cutoff\|))` | the BODY is right and the signature wrong: `except {valueFld}` removes `v`, so `r'' <- (r, v)` was unsatisfiable for every non-empty `v` |
| 7 | `Layout/Report/Relation.e others` | result `Relation r`, `r` in no constraint | result `Relation s`, plus `exists o. o <- ((\|cutoffChild,cutoffCount,cutoffGroup\|), s)` | the body's row IS `s` (the four aggregates joined, then the three private columns removed), and its one caller already forced `r = s` |
| 8 | `Wide/Helpers.e melt2` | `r <- (i,fa,fb), out <- (i,key,val)` | `exists w. ..., w <- (r, key)` | the key column must not already be one of the input's; `melt2 pp vcol pp qq src` failed at run time with `Cannot union columns` |
| 9 | `Wide/Helpers.e melt3` | as above with `fc` | `exists w. ..., w <- (r, key)` | same |
| 10 | `Wide/Helpers.e melt4` | as above with `fd` | `exists w. ..., w <- (r, key)` | same |
| 11 | `Wide/Signatures.e melt3Simple` | as `melt3` | `exists w. ..., w <- (r, key)` | same |
| 12 | `Algebra/Signatures.e runningTotalFullViaWritten` | the 21 constraints the compiler wrote | the 21 **plus** `exists rest. r <- (a, b, rest)` and `d <- (c, r)` | the module's documented claim ("the twenty-one assumed, the two discharged") is FALSE: `a` and `b` occur in none of the 21, and `d <- (c,r)` needs `c = m`, which they do not force. The prose is corrected to say so -- the compiler's own residual is WEAKER than what a person writes, and silent about the columns the function is named after |
| 13 | `Time/Helpers.e dayCount` | (none) | `RUnion2 out r r1` | the file called the hole deliberate and named this fix; `out` unconstrained breaks `dateDiff`'s `RUnion2` |
| 14 | `Time/Helpers.e monthsBetween` | (none) | `RUnion2 out r r1` | same |
| 15 | `Time/Helpers.e monthsSince` | (none) | `Has out r` | one operand is a literal, so the result row need only CONTAIN the column's row |
| 16 | `Time/Helpers.e daysSince` | (none) | `Has out r` | same |
| 17 | `Time/Helpers.e daysUntil` | (none) | `Has out r` | same |

No caller's inferred type moved: every correction ADDS a constraint to a context (1, 2, 3, 4,
5, 7, 8-17) or narrows a declared result row to what the body already returned (6, 7). The
`.ei` consequence is therefore confined to the corrected bindings' own published contexts --
which could not be measured on this branch after the revert, and is `sig-fixes`' gate.

## 10. Reproduce

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
# the corpus under warn (the check's decisions, without the refusal)
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh --batch /tmp/corpus-warn
tracker/tools/sigcheck.py /tmp/corpus-warn --assert-qsat      # 310: 284/24/2
# the suites
sbt 'core/testOnly *TestSigEntail *TestSigEntailDiff *TestInterfaceKey *TestLetSignatures'
sbt -Dermine.sigEntail=off 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestReplDifferential'
sbt 'core/testOnly *TestLoopTrace'
# the pins, all five, in one JVM under warn (they refuse one at a time under error)
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  bin/ermine core/examples/shouldfail/sig0*.e </dev/null
# the smokes (tracker/repl-classpath.txt regenerated from this worktree first)
cp target/ermine-classpath tracker/repl-classpath.txt
JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/repl-smoke.sh
tracker/tools/lsp-smoke.sh
JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/g1-validate.sh
git checkout tracker/repl-classpath.txt
cd tracker/lean && lake build Rowpartition && lake env lean Audit.lean
```
