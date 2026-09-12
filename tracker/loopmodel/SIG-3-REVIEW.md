# SIG-3 REVIEW: the signature-entailment check, the flag, the differential, the pins

Reviewer of S3 in `ermine-scala-wt-sig` (branch `sig-entail`, HEAD `6115ed6` + the
implementer's uncommitted tree). Everything below that says "measured" I ran here; scratch
`…/scratchpad/review-S3/`. `tracker/repl-classpath.txt` regenerated for the smokes and
`git checkout`ed back; all 129 `.ei` I caused deleted; no commits.

## VERDICT: FIX-THEN-ADVANCE

The judgement is implemented as §(a) specifies, the engine IS the shipped one, the differential
really drives `SigEntail.check`, the corpus numbers reproduce from an independent sweep, the two
new rejections are real holes, and I could not make the check reject an honest program. Two
fixes are user-visible (D2, M2), one closes a latent false rejection (D4), one is a missing Lean
licence for a rule that decides two rejections (D1). None is a redesign.

### Edit list (FIX before landing; each is one to a few lines)

1. **D2 / M1 `Subst.scala:689`** — `SigEntail.siteOf("sig", binding.v)` puts "declared at" on
   the EQUATION, not the signature. Pass the declared annotation's own `Loc` (`binding.ty.loc`,
   three lines above at `:683`) and widen `siteOf`; re-measure the five pin headers and
   RESULTS.md's positions.
2. **M2 `SigEntail.check`** — sort `qTups`/`wTups` and each `RHS.abstr` canonically (rendered
   name, then id) before constructing `LabelSearch`, so the refuting model, and so the witness
   sentence, is reproducible. Today it is not (item 5).
3. **D4 `SigEntail.scala:551`** — `if (foreign.exists(ones))` → test the model's whole
   vocabulary, not only its 1-bits: `if (m.exists(p => foreign(p._1)))`. Corpus-neutral
   (`foreign` is empty on all 310 groups); removes the one way the conservative reading can
   still report a lie.
4. **D1 Lean + report wording** — add the empty-concrete-lhs lemma beside
   `Basic.Sat.eq_empty_of_dup` (`Sat rho c → rho c.lhs = ∅ ↔ ∀ p ∈ parts, rho p = ∅`), and
   correct `SIG-3-IMPL.md` §5.2/§5.3: `eq_empty_of_dup` licenses only the repeated-part rule.
5. **`SIG-3-IMPL.md` §7.3** — "exactly 24 signatures ... = 24 lines" is wrong; the grep gives
   25. Say "25 rejected SITES = 24 oracle groups (`sig05` is rejected at both annotations,
   which the oracle's `(module, binding, givens)` key merges)"; fix the table's `2` row and
   §5.1's "310 signatures" the same way.
6. **`RESULTS.md`** — "a two-location diagnostic ... whose secondary is the signature" is false
   until edit 1 lands.
7. **D6 `SigEntail.scala:75-76`** — delete the now-dead `val warn` (no reader anywhere in
   `core/ lsp/ scalacheck-binding/`); it is the last trace of the S1 global §(e) 5 required be
   replaced, and its comment claims a use it no longer has.
8. **D3 `SigEntail.scala:531`** — give the obligations' `LabelSearch` the per-CLASS cap, not
   the whole remaining signature budget (`math.min(cap, sigBudget - spent)`).
9. **D7 `SigEntail.scala:71`** — `modeOf` maps an unrecognised value to `Error`, so a typo in
   `-Dermine.sigEntail` silently ships the strictest mode. Fall back to the default and warn.
10. **`sigcheck.py:44`** — `len(c) > 9` drops the `ds` column when the probe writes through
    `RowTrace` (9 columns, no tid); `> 8`. **`lsp-client.py:2748`** — the `else:` block is
    indented one space.

Deferred, not blocking, but name them in S4: D5 (`interfaceKey` reads the PROCESS mode while
the check reads the SESSION mode), the fixture default (item 7), the differential's three blind
spots (item 3).

## 1. Faithfulness to §(a)

Confirmed by reading `SigEntail.check` (`:410-581`) and `Subst.scala:546-587`:
* `F = wv.filter(v => pxsSet(v) && !qv(v))` (`:482`), `wv` = variables of the ENCODED closure,
  `qv` = variables of the ENCODED (Part-shaped) givens — `vars(W) ∩ pxs \ vars(Q)` exactly. `R`
  is the rest: `rigidW = wv -- F`, Q-only variables enter through `qTups`, and
  `extraVars = (rigidW -- qv)` (`:514`) supplies the rigid W-variables the givens never name.
  Dedup projects to `qe.indicesOf(rigidW)` = `vars(W) ∩ R` ✓.
* `W` is a FIXPOINT: the `while (grew)` loop (`:456-479`) recomputes `f` from the current
  `wRows` every round — precisely the oracle fix of §5.2 item 1 ✓.
* Placement: the call is at `Subst.scala:570`, after the `:548` partition and BEFORE
  `restrictTypes(qxs)/(pxs)/restrictKinds(tks)/restrictTypes(tts)` (`:572-575`) ✓; `:587`'s
  `(q, mkSimplified(pz.loc, pxs, ds))` is character-identical to HEAD under every mode ✓, and
  `entails(qs,r)` at `:571` is untouched ✓.
* The App case gets NO `Site`: only `:671` (`ann`) and `:689` (`sig`) pass one; `:835`, `:956`
  (App) and `:1012` (pattern) use the `None` default ✓.

**(i) Foreign skolem — NOT EXHIBITABLE, and the guard is too narrow (D4).** Three attempts.
`review-S3/e/Revfk.e` is the design's own shape — an honest
`outer : forall r t. r <- ((|health|), t) => {..r} -> Int` whose `where`-bound `go : Int` reads
`rec ! health` — and it produced **no probe record at all**: the obligation lands in `ds`,
because when `inferAltTypes` runs the enclosing argument row is still a `Free` meta (the outer
signature is skolemised inside its own `subsumeType`, which runs afterwards). A `where`
signature reusing the outer's variable NAME quantifies it freshly (`Algebra/Signatures.e:288`
`tautHere`); a sibling unsigned binding unifies its meta with the declared type, making the
variable this signature's own skolem. So `foreign` looks unreachable on the shipped pipeline —
consistent with the design's `{S, A}` histogram — and the degradation is untested code. Make
it safe anyway: it fires only when `foreign.exists(ones)`, i.e. when a foreign skolem is set
TRUE, yet a model setting one FALSE is equally unjustified (the enclosing givens are not in `Q`
either way). Design (a) says "if the refuting model **assigns** such a variable". Edit 3.

**(ii) Unsatisfiable givens — EXHIBITED, and correct.** `review-S3/e/Revunsat.e` declares
`vacuous : forall r t. (r <- ((|health|), t), t <- ((|health|), r)) => {..r} -> Int` with body
`rec ! mana`; the givens have no model at the column `health`. Under `warn` (`error` dies with
the same text):
```
.../Revunsat.e:13:1: warning: the signature's constraints have no solution: no call can satisfy them
    given    t^579335B <- ((|Revunsat.health|), r^579374S); r^579374S <- ((|Revunsat.health|), t^579335B)
  at the column `Revunsat.health': two parts of one partition both contain it
  the body is not blamed: this signature cannot be instantiated at all
  declared at .../Revunsat.e:13:1 (sig vacuous)
```
The body is not blamed, the primary position is the signature, and (a2)'s `LabelRefuted`
branch is the one taken. (M5: the stray `'`, and the redundant last line.)

**(iii) The F2 witness as a real program — EXHIBITED, REJECTED.** The `rs`-accepts /
`rs+ds`-rejects shape is exactly `Time/Signatures.e`'s `yearFrac365Simple`/`Full` (item 4
derives both by hand), and `TestSigEntailDiff`'s "the empty row on the left normalises, and
decides" property is that shape at five variables with both halves asserted. The repeated-part
half also holds on a real program (`review-S3/e/Revdup.e`,
`dup : forall b c. c <- (b, b) => {..c} -> Int`, body `rec ! health`) — REJECTED, with `b`
correctly absent from the witness because the normalisation put it in `qv`.

## 2. The engine, and the Lean

`decideLabel` is now a wrapper over `LabelSearch` with `extraVars = Nil`,
`hasLabel = _ contains l`, `searchSat(everyVar)`: the shipped search is the old one line for
line (same first-appearance index order, FALSE-before-TRUE, five propagation rules, same
`verify`; `TestConstraints` 17/17 in the implementer's log). Label classes =
`(qRows ++ wRows).flatMap(_.conc).distinct` plus `None` with `hasLabel = _ => false` —
§(b2)'s construction and Lean's `l₀ ∉ concLabels (Q ++ W)` ✓. REJECT outranks NO VERDICT:
`check` never stops at a no-verdict class and returns `NotEntailed` unconditionally from the
rejecting branch ✓. Two nits: `enumerate` drops a leaf whose `verify()` fails instead of
raising `checkFailed` (correct — `verify` is authoritative — but asymmetric with `searchSat`),
and `found == limit` at the last model reports an incomplete enumeration (unreachable:
`modelLimit` 20 000 vs a measured max of 256).

**Part-shape contract (§(e) 2b).** ≥2 concrete parts → `Unreadable`, naming them, never
merged ✓. A part that is neither `VarT` nor `ConcreteRho` → `Unreadable` ✓. A NON-EMPTY
concrete lhs → `Unreadable` ✓ (which leaves `Relation.largers/.small` honestly undecided).
A repeated variable part → normalised to "that variable is empty", licensed by
`Basic.Sat.eq_empty_of_dup` (`Basic.lean:229`, hypothesis `2 ≤ c.vars.count v`) ✓; the
degenerate cases check out by hand (`v <- (v,v)` → `v <- ()`; `v <- (v,v,(|C|))` →
`v <- ((|C|)) ∧ v <- ()`, unsatisfiable, as it should be).

**The EMPTY concrete lhs is a DEVIATION (D1).** §(e) 2b says "a concrete left-hand side:
**NO VERDICT** with a named reason, never silently merged"; `SigEntail.scala:352-358`
normalises `(||) <- (p1..pk)` to "every part is empty" instead, and that rule decides 2 of the
rejections. The argument is sound — the model's partition is `at-most-one(parts) ∧ (lhs ⟺
exactly one part)`, so `lhs = 0` plus at-most-one forces every part to 0, and the converse is
immediate — but `eq_empty_of_dup` is NOT the licence (the code cites it only for the dup rule;
§5.2 of the report reads as though it covers both) and the equivalence has no Lean statement.

**Does the Lean still match the oracle? YES, and it was right not to change it.**
`sigEntails_of_lsig`, `lsig_of_sigEntails`, `lsig_iff_classes`, `sigDecide_iff` are all about
`List Constraint` with `Constraint.lhs : Var` and one `conc` (`Basic.lean:43-50`). Both oracle
fixes live in the `Type → Constraint` ENCODER, which Lean does not model: the closure is how
`W` is BUILT from the residual, and the empty-lhs rule is a shape Lean cannot express. So no
theorem moved. But the second fix asserts a NEW model-level equivalence that IS statable in
Lean and should be (edit 4), because two of the twenty-four rejections rest on it.
`lake build Rowpartition` (871 jobs) and the audit (4670 theorems, 0 non-standard axioms) I
take from `scratchpad/S3/lake.log` / `audit.log`; the only Lean change is one `import` line.

## 3. The differential test

**It drives the shipped engine.** `verdictOf` and `describe` both call `SigEntail.check(...)`
directly — no re-implementation. It fails loudly: `bad` compares (verdict, label class) per
`(module, binding)` and prints the disagreement with sizes, minted count and witness;
`missing`/`extra` compare the key sets; `expected.size ?= 310` guards the resource; a second
property pins 284/24/2. Re-ran `sbt 'core/testOnly *TestSigEntail *TestSigEntailDiff
*TestInterfaceKey'`: **21/21, 0 failed**, including "all 310 signatures" and "random systems
... passed 2000 tests".

**Provenance and regenerability.** The command is in the test's header and in
`sigcheck.py`'s docstring. Run against my OWN sweep it prints
`310 {'ACCEPT': 284, 'REJECT': 24, 'NOVERDICT': 2}` and the generated `verdicts.tsv`
**diffs empty against the committed one**; `records.tsv` does not (938 vs 937 lines: ids and
`Set` order), exactly as the report warns. `--assert-qsat`: **0** signatures have a class at
which the givens have no model, so (a2)'s completeness hypothesis holds corpus-wide.
**310, not 309**: S1's 309 plus `sig03`, which entered the population when LET-1 merged and its
let-bound signature began reaching `typeCheckExplicitBinding` (`verdicts.tsv` carries
`REJECT shouldfail.sig03_let_bound_signature sig:local`).

**Three blind spots the report should name.** (a) The group key is
`(module, binding, givens)`, so two distinct SITES with the same binding name and givens are
MERGED into one system — `sig05`'s two annotations are (`ann:<annot>` twice), which is the
whole 24-vs-25 discrepancy. Both sides read the same merged input, so it is still a valid
differential of the JUDGEMENT, but not a per-site pin. (b) `pxsOf` = "not Skolem and not
Bound", so bare `Free` counts as MINTED — the PERMISSIVE rule, the opposite of what ships;
corpus-blind (no bare `Free`), but the differential cannot see the ambient-meta decision.
(c) `sksOf` = every skolem, so `foreign` is empty everywhere, and the 2 000 random systems
pass `ds = Nil` — the CLOSURE, where both oracle bugs were, is covered only by the 310 corpus
groups and one hand-written property, not by the generator. Also the resource path is
relative, so the property needs sbt's cwd at the repo root.

## 4. The flag

Default `error`, read once at class init (`SigEntail.defaultMode`); consulted per SESSION
through `SessionEnv.sigEntail → SubstEnv.sigEntail`, and the only production `new SubstEnv`
is `Session.subst` (`Session.scala:60`), which threads it (the other `new SubstEnv()` sites
are all under `core/src/test` and `tracker/repro` and pass no `Site`). The fixture sets it
through `ErmineFixture(sigEntail = …) → new SessionEnv(_sigEntail = …)`: no
`System.setProperty` anywhere ✓. All three S1 globals are REPLACED, not joined (`:672`,
`:690` read `hm.sigEntail.on`; the probe guard moved inside `enforce`) — so `SigEntail.warn`
is dead (edit 7). `interfaceKey` appends `|sigEntail=error` in that mode only, `notInKey`
gains `sigentail` and is checked against the `GenRules` half with the suffix checked exactly;
`TestInterfaceKey` 2/2 green here. **D5**: `interfaceKey` reads the PROCESS mode while the
check reads the SESSION mode, so a session differing from the process default — exactly what
the new mechanism creates — writes a key describing the wrong mode. Harmless today (every
fixture sets `useInterface = false`); comment it and note it in S4.

**Under `off`.** Re-ran `JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/g1-validate.sh`:
every oracle fixture PASS, double-run self-agreement `129 files, 1447 signatures, EQUIVALENT`,
`PASS no drift from tracker/g1-baseline`. The baseline predates S3, so that IS the
`.ei`-byte-identity gate, sharper than a byte diff. `repl-smoke` 8/8 / 66 checks I read from
the implementer's `repl-off.log`; I re-ran `ERMINE_SIGENTAIL=off tracker/tools/lsp-smoke.sh`
myself: **PASS, 546 checks**.

**Under `warn`, reproduced from my own sweep** (`corpus-run.sh --batch`, then
`corpus-verdicts.py` and `sigcheck.py`):

| measurement | mine | implementer's |
|---|---|---|
| corpus verdicts | 91 LOADED / 74 REJECTED / 0 UNKNOWN / 165 | identical |
| `off` vs `warn` verdicts | **0 of 165 differ** (their `corpus-off` vs my `corpus-warn`) | 0 |
| oracle | 310 signatures, 284 / 24 / 2, `verdicts.tsv` byte-identical | same |
| engine's distinct `declared at` lines | **25** | 25 in their own data; report says 24 |
| the 25-site SET | `diff` against theirs EMPTY | — |
| NO VERDICTs | 2 (`Relation.largers` :82:3, `.small` :113:3) | 2 |

So the population is **the design's 17 + the 5 pins + 2 new = 24 oracle groups = 25 sites**,
and nothing outside the design's list is rejected; edit 5 is the only correction needed.
**The two NEW rejections are REAL** — derived by hand, not accepted from the report.
`yearFrac365Simple : Field r Date -> Field r1 Date -> Op out Double` has no row givens;
obligations `out <- (f,e,d)`, `r <- (ro,rs)`, `r1 <- (so,rs)`, and a `ds` half carrying
`(||) <- (f,e)`, `t <- (e,d)`, `t <- (ro,so,rs)`. The closure pulls all three in;
`(||) <- (f,e)` forces `f = e = ∅`, hence `out = d = t = ro ⊎ so ⊎ rs`. Take
`out = 1, r = 0, r1 = 0`: `r = ro⊎rs = 0` and `r1 = so⊎rs = 0` force `ro = so = rs = 0`, so
`t = 0` while `d = out = 1` — refuted. The declared result row is unconstrained although the
body makes it the union of the operand rows: `dayCount`'s hole, in the file that documents
`dayCount`'s hole. `yearFrac365Full` adds only the tautology `out <- (out)`, and the engine's
own witness for it (`r1 = 1, out = 0, r = 0`) checks out by the same algebra. **Why `W = rs`
missed them**: with `rs` alone each obligation is satisfied independently (`f := out,
e = d = ∅`; `ro := r, rs := ∅`; `so := r1`); the three `ds` members are what couple them.
Exactly the stop point (a3) predicted.

## 5. The message and the blame

I ran sig01..sig05 under `warn` and read every message
(`review-S3/corpus-warn/shouldfail_sig0*.e.out`). All carry the wanted, the givens as the
check read them, the model sentence, the ignored givens where (a4) applies, and two
locations; `given (none)` when there are none. The wanted's position is the generating term
every time: sig01 `70:17` / sig02 `45:18` the `!`; sig03 `70:25` the `!` inside the `let`;
sig04 `47:8` `modify`; sig05 `48:19`/`49:19` the `!` inside each annotated lambda. For sig05
the blame is sensible — the `!` and the annotated expression — but it points at the lambda
rather than the type that is wrong; that is what §(d3)'s `e.loc` asks for, so I record it
rather than call it a defect.

**M1 (= D2). "declared at" is NOT the signature line.** Measured — signature line /
equation line / what the message prints: sig01 69 / 70 / `70:1`; sig02 44 / 45 / `45:1`;
sig03 69 / 70 / `70:13`; sig04 46 / 47 / `47:1`. `binding.v.loc` is the EQUATION's head, so
for a one-line body the two locations collapse onto the same line and the secondary tells the
reader nothing. Edit 1; RESULTS.md's "whose secondary is the signature" is false until it
lands.

**M2. The witness sentence is not reproducible.** Normalising ids away, my sweep and the
implementer's final sweep each print 24 prose lines and **5 differ in substance**, e.g.
`Wide.Helpers.melt4`: mine "take a column … to be in out and in key and in r and in **fd**,
and in none of val, fc, fb, fa", theirs "… and in **fc**, and in none of val, fd, fa, fb" —
a different refuting model for the same signature. The same instability shows inside one of
the implementer's own JVMs: `cons_Bracket` prints "to be in rout, and in none of f2, f1, r"
for one `TestTolerantCheck` property and "to be in f2, and in none of f1, rout, r" for the
next (`scratchpad/S3/g-tolerant-default.log:57,66`). Cause: the constraint lists reach
`LabelSearch` in `Set` order, which depends on the ids the run happened to mint, so the
`LinkedHashMap` variable order and hence the first model found change. Consequence: the pins'
and RESULTS.md's "measured message verbatim" cannot be reproduced, and any future golden on
the witness will flake. Edit 2.

**M3.** The `wanted`/`given` columns always carry `^id` + flavour even when the short names are
unambiguous (sig01: `r^1484700S <- ((|ShouldFail.Sig01.health|), _^1484702A)` where §(d3)'s
sketch reads `t <- (fb, s)`); `prose` already disambiguates only on demand (`dupN`), and the
same rule in the two columns would fix the common case. **M4.** The minted list is unbounded —
`Relation.cutoffs` lists 35 variables, `melt4` 32 — truncate it. **M5.** Cosmetic: the
vacuous-givens branch writes `` at the column `X': `` where the rest uses `` `X` ``.

**Readability verdict: good enough to ship, not yet good.** A reader who has not seen the
design gets the load-bearing half — which column, which rows it must be in, which it must be
absent from, that the rest are the compiler's own choice, where both halves live — and the (a4)
ignored-given note is genuinely helpful. Against that: M1 makes the second location useless on
a one-line body, M2 gives two readers two different explanations, M3/M4 bury the sentence in
ids. Edits 1-2 I would not ship without.

**No false rejection.** `review-S3/e/Revhonest.e` — five honest but non-trivial signatures:
two-step transitive (`r <- (a,b), a <- ((|health|), c)`), the same through `Has a (|health|)`,
a rotated right-hand side, a two-column concrete given consumed twice, and an extension
`o <- (r, (|mana|))` — **all five load with zero diagnostics**, six probe records, no NO
VERDICT. With "0 of 165 corpus verdicts differ", that is the evidence against over-rejection.

## 6. The editor

`TestTolerantCheck`'s two new properties construct their own `Error` fixture (both modes in
one JVM) and assert exactly one Error note carrying the message, the `declared at` line and a
position in the file being edited, plus the honest twin's silence and its type; both green
under `off` and at the default. `tracker/lsp-tests/SigEntail.e` + five checks in `lsp-client.py`
pin it over the wire, including `range.start.line == 18`.

**Same position as batch — confirmed, not taken on trust.** `tracker/lsp-tests/SigEntail.e`
imports only `Field` and `Primitive`, so `bin/ermine` checks it even while the Prelude boot is
refused. Under the DEFAULT `error` it prints
`tracker/lsp-tests/SigEntail.e:19:15: the signature does not entail this row constraint` …
`declared at tracker/lsp-tests/SigEntail.e:19:1 (sig tooWeak)` and then
`Unable to load module from '…/SigEntail.e'`. Line 19 (1-based) is the client's 0-based 18 ✓,
and `honest` draws nothing ✓. `lsp-smoke` under `off`: re-ran, **PASS, 546 checks**.

**The default-mode failures have ONE cause, confirmed from the failure text.** All three
`Exception raised` properties in `g-tolerant-default.log` carry the identical
`scalaparsers.Death: …/DrilldownList.e:20:98: the signature does not entail … (sig
cons_Bracket)`; the two `Falsified` ones report "only 0 modules checked cleanly" / "0 clean
modules of 254" — nothing booted at all, and `lsp-smoke` times out at its first check for the
same reason. I did not apply the corrections patch (it would edit the worktree) and did not
need to: the text is decisive, and the `bin/ermine` run above shows a module that does not
import `Prelude` IS checked correctly at the default.

## 7. Landing checklist — what the orchestrator runs when `sig-fixes` merges

Preconditions: `git merge sig-fixes` clean; `sbt core/copyResources` (the `.e` under
`core/src/main/resources` are copied, not read in place); `Relation.e` and `Keyed.e` are CRLF.

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH; S=<scratch>
# 1. the stdlib boots at the DEFAULT, and so does an importer of the corrected modules
bin/ermine core/examples/GridExample.e </dev/null          # expect 129 modules, 0 refusals
# 2+3. corpus verdicts: error == off except the five pins, and NOTHING else is rejected
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=off"   tracker/tools/corpus-run.sh --batch $S/land-off
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=error" tracker/tools/corpus-run.sh --batch $S/land-err
diff <(python3 tracker/tools/corpus-verdicts.py $S/land-off | awk '{print $1,$2}') \
     <(python3 tracker/tools/corpus-verdicts.py $S/land-err | awk '{print $1,$2}')
grep -rh '^  declared at ' $S/land-err | sort -u
#  only sig01..sig05 may differ (LOADED -> REJECTED), and the grep must list exactly the 5 pin
#  sites (6 lines: sig05 twice).  Time/Signatures.e, Time/Helpers.e, Wide/Helpers.e,
#  Wide/Signatures.e, Algebra/Signatures.e must be LOADED on BOTH sides or a correction is missing.
# 4. regenerate BOTH differential resources from ONE warn sweep, then FIX the two hard-coded
#    counts in TestSigEntailDiff (310 / 284-24-2): the corrections remove 17 rejections, so both
#    properties WILL fail until edited -- the one landing step that is not a re-run.
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" tracker/tools/corpus-run.sh --batch $S/land-warn
tracker/tools/sigcheck.py $S/land-warn --assert-qsat \
  --records core/src/test/resources/sigentail/records.tsv --tsv core/src/test/resources/sigentail/verdicts.tsv
# 5. .ei movement, error vs off: expect only the 17 corrected contexts and their importers
tracker/tools/ei-diff.sh $S/land-off $S/land-err
# 6. gates, in parallel sbt invocations (the second now AT THE DEFAULT)
sbt 'core/testOnly *TestSigEntail *TestSigEntailDiff *TestInterfaceKey *TestLetSignatures'
sbt 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestReplDifferential'
sbt 'core/testOnly *TestLoopTrace'
# 7. the smokes AT THE DEFAULT (both were only green under `off` at S3)
cp target/ermine-classpath tracker/repl-classpath.txt
tracker/tools/repl-smoke.sh                   # 8/8, 66 checks
tracker/tools/lsp-smoke.sh                    # PASS, 550 checks (5 SigEntail checks, not 1)
JAVA_TOOL_OPTIONS=-Dermine.sigEntail=off tracker/tools/g1-validate.sh   # no baseline drift
git checkout tracker/repl-classpath.txt; find . -name '*.ei' -not -path './tracker/g1-*' -delete
```

Two landing items that are NOT re-runs. **Flip `ErmineFixture`'s `sigEntail` default from
`Some(Off)` to `None`** (inherit the process default) once the stdlib is honest, and run
`core/test` once: left at `Off`, the escape hatch is the tested configuration and the shipped
default is exercised by three properties and the smokes only. And **`TestSigEntail`'s four
`no(typeChecks(...))` assert only "refused", not "refused by this check"** — give one of them
the message, as the editor properties do. Item 7 is written, not measured: by construction it
cannot be run before the merge.
