Review of the 2.11 back-port of the signature-entailment check (BP-1 + BP-2)
===========================================================================

Reviewer, 2026-09-12. Branch `backport-2.11`, HEAD `134b566` + BP-1's and BP-2's
uncommitted changes. Nothing committed, nothing stashed, nothing edited but this file.
Reference: `git show 5162945:<path>` from `../ermine-scala`.

VERDICT: **FIX-THEN-ADVANCE** -- two documentation edits, no code change, no gate re-run.

    E1 (REQUIRED) SigEntail.scala:13-15.  The BACKPORT paragraph says the two files "differ
       in exactly two places, each marked `SCALA 2.11` below (`Iterator.nextOption`,
       `ThreadLocal.withInitial`)".  There are THREE such marks (:262, :420, :487); the
       third, the `f` -> `freeNow` rename, is missing.  The marks exist so a merge can diff
       the two files and account for every hunk; an undercount defeats exactly that.  Say
       "three places" and add ", the `freeNow` rename".  CRLF file -- edit byte-wise.

    E2 (REQUIRED) backport/SIG-ENTAIL-2.11.md:282-283 names `Yahoo.e` as *the* example that
       "fails IDENTICALLY in both modes".  FOUR do (§5).  The differential claim is
       unaffected, but a later reader will think three files regressed.  Name all four.

    N1 (optional) TestSigEntail.scala:83-89 still asks which of the two refusals this branch
       produces.  BP-1 measured it and I reproduced it (`sig local`); state the answer.

Everything I attacked held. `Constraints.scala`'s `LabelSearch` lift and `Subst.scala`'s
SIG-3 logic are byte-identical to main's; the corrections and `SoftRelation.e` hash to
main's landed blobs; all five pins reproduce BP-1's positions and sites exactly.

1. `SigEntail.scala` vs `5162945` -- every hunk
-----------------------------------------------
CRLF-normalised `diff -u` (this file 813/813 CRLF, main's LF): **8 hunks**, +34/-13. Three
are the marked 2.11 edits, five are comment/line-number only. All benign.

| # | at | what | benign? |
|---|---|---|---|
| 1 | :9 | BACKPORT paragraph + `Subst.scala:534`->`:541` | comment only -- but see **E1** |
| 2 | :88 | `:651`/`:669` -> `:671`/`:689` | comment only |
| 3 | :254 | **`Iterator.nextOption()` -> private `nextOption(it)`** | yes |
| 4 | :279 | `:541` -> `:548` | comment only |
| 5 | :378 | `Subst.scala:389` -> `:405` | comment only |
| 6 | :417 | **`ThreadLocal.withInitial` -> anonymous subclass** | yes |
| 7 | :484 | **local `val f` -> `val freeNow`** | yes |
| 8 | :772 | `Subst.scala:1477` -> `:1508` | comment only |

**#3.** `if (it.hasNext) Some(it.next()) else None` is 2.13's `nextOption()` verbatim.
Laziness preserved and it matters: 2.11's `Iterator.flatMap.hasNext` advances the source
only to the first non-empty sub-iterator, so `perm` still short-circuits its backtracking
search. Evaluation order unchanged (iterator built eagerly, driven only by `hasNext`, in
both spellings), and no new stack exposure -- that `hasNext` recursion is main's too.

**#6.** Java 8's `withInitial(sup)` returns a `SuppliedThreadLocal` whose `initialValue()`
is `sup.get()`; overriding `initialValue()` is the same object with the same
per-thread-first-`get` semantics. `Cost` is immutable.

**#7.** The reference's `val f` has exactly TWO uses (`rws.exists(_.vars.exists(f))`,
`Type.typeVars(d).exists(f)`); both renamed, nothing else. The `F` three lines below
(`val F = wv.filter(...)`, `rigidW = wv -- F`) is a different val and untouched -- the
whole point. Verified against the reference's entire closure loop, not just the hunk.
No fourth divergence: the 8 hunks are the complete diff.

2. `Subst.scala` -- placement and sites
---------------------------------------
Whole-file diff vs main: **5 hunks** -- three comment/line-number only, two the deliberate
non-ports (§3). So every line of SIG-3 logic here is byte-identical to main's.

* **Placement CONFIRMED.** `sig.foreach(s => SigEntail.enforce(s, qs, rs, ds, sts, pxs))`
  sits immediately after the `:548` partition and BEFORE `for (r <- rs) entails(qs,r)`
  (:568-569) and `restrictTypes(qxs)` (:570).
* **Return untouched CONFIRMED.** `:586` is still `(q, mkSimplified(pz.loc, pxs, ds))`; no
  hunk goes near it, and the class-only `entails` loop is unchanged. The check only reads.
* **Exactly two `Site` allocations CONFIRMED.** Of six `subsumeType` call sites, only
  :672 `siteAt("ann", e.loc)` (the :671 call) and :700 `siteOf("sig", binding.v, typ.loc)`
  (the :689 call) pass one. :846, **:967 the App case** and :1023 pass no argument, hence
  `None`. No site at the App case.
* **`off` is inert by construction.** Both sites guard on `hm.sigEntail.on`, and
  `Mode.on = this != Off` (:71): no `Site` allocated, `sig` is `None`, `foreach` a no-op.
* **"declared at" = the signature line.** Opened the files rather than trusting the pins.
  sig01 :112 is `healthOpt : forall r. {..r} -> Int` and col 13 is where `forall` starts --
  the declared type's own loc, not the `:` and not the binder; :113 is the body, col 17 the
  `!`. sig03 :108 is `crash = let local : forall r. ...`, col 21 `forall`; :109 col 25 the
  `!`. Both pins are the signature; `binding.v.loc`/`binding.ty.loc` would both have given
  the equation head, so `typ.loc` is right.

3. The two hunks deliberately NOT ported
----------------------------------------
Both are real, both are the only non-SIG-3 divergence in `Subst.scala`, both correct to
omit -- one forced, the other required for consistency.

* **`:1566` `ps.filter(_._3.isDefined)` (main) vs `_.inf.isDefined` (here).** Not a feature
  declined: `Partition` is declared *identically* on both branches
  (`case class Partition(_1: TypeVar, _2: RHS, inf: Option[Inference])`,
  `Constraints.scala:1582` on both), so `._3` and `.inf` are the SAME third field -- Scala
  3 synthesises `_1.._N` on case classes and 2.11 does not, so main's spelling would not
  compile here. It lives in a `RowTrace.log` block (diagnostics only) and is already at
  HEAD, i.e. pre-existing. **The engine does not depend on it**: `grep` finds ZERO
  `Partition`, `.inf`, `_3` or positional `_._` in `SigEntail.scala` -- `encode` consumes
  `Type` (`Part`/`ConcreteRho`/`Con`), never a `Partition`. BENIGN. (Bookkeeping: BP-1
  files this as "not ported ... neither is SIG-3", which reads as a feature declined; it is
  really a third 2.11-forced spelling, unmarked, which is why E1's undercount matters.)
* **`:1809` the LSP-FFI `TypeConDecl` tolerance.** Main builds the decl from
  `clazz.failure`; this branch's `ForeignClass` (`Statement.scala:142`) has no `failure`,
  so it is unportable as written. More to the point, main's own comment says the code
  "mirrors `Session.processForeignDataStatement`", and this branch's `Session.scala:1386`
  builds plain `TypeConDecl(clazz.cls, true)` -- porting the hunk would have BROKEN that
  mirror. `TypeConDecl`'s third parameter (`unresolved: Option[String] = None`) is already
  here, identical to main's, so the types agree and only the unused path is absent.
  Foreign-data class resolution shares nothing with row entailment. BENIGN.

4. Corrections -- byte comparison
---------------------------------
`git hash-object` vs `git rev-parse 5162945:<path>`:

    Relation/UnifyFields.e       7bab327 == 7bab327   IDENTICAL to main's landed blob
    DrilldownList.e              38f8e01 == 38f8e01   IDENTICAL
    Layout/Report/Keyed.e        dc0e5a2 == dc0e5a2   IDENTICAL
    Layout/Report/Relation.e     03615e9 == 03615e9   IDENTICAL
    Relation.e                   6319415 vs 0df68ca   DIFFERS (prose only)
    core/examples/SoftRelation.e 052ecdb == 052ecdb   IDENTICAL  <- the date-drilldown fix

c1/c3/c4/c5/c6/c7, the `cutoffDrilldownRel` cascade and the `SoftRelation.e` fix are
main's exact bytes; nothing was ported "by meaning". `Relation.e`'s residual diff is
**exactly two prose comment blocks** -- main's stage-F3 paragraphs on `rename'` (C5) and
the rewritten `join1` comment (C2), both ~50 lines below `partialLookup`, neither a
signature, `join1`'s own signature identical. Matches CORRECTIONS.md §2. `SoftRelation.e`
hashing to main's closes CORRECTIONS.md §4.3's open risk: the module loads (§5).

Line endings, per file (CR vs LF, HEAD in parens): CRLF with no bare LF --
`Relation.e` 267/267 (264/264), `UnifyFields.e` 8/8, `Keyed.e` 144/144 (135/135),
`SoftRelation.e` 117/117 (109/109); LF with zero CR -- `DrilldownList.e` 0/23,
`Layout/Report/Relation.e` 0/199 (0/198). Every file kept its own ending, none is mixed,
and the net deltas match `--numstat` (+24/-11 over the five modules): no conversion churn.
All eight touched `.scala` are fully CRLF (CR == LF: SigEntail 813, Subst 2056,
Constraints 3048, Session 1495, SessionState 141, TestErmine 419, TestSigEntail 161,
TestSigEntailDiff 442); `records.tsv` 0/246 and `verdicts.tsv` 0/106 are LF as generated.
All six pins are **code-identical** to main's (stripping `{- -}` and `--`); only header
prose differs, and only where the branch legitimately differs.

5. Gates I measured
-------------------
`source backport/env-2.11.sh`, JDK 8 / sbt 0.13.5, one JVM at a time.

* `core/compile` + `scalacheckBinding/compile`: rc 0.
* **`core/test`: Total 735, Failed 0, Errors 0, Passed 735**, 91 s. Per-suite tally sums to
  exactly 735; the new suites are 14 + 8 = 22, so the baseline was 713 -- BP-1's arithmetic
  confirmed. Inside it: `Ermine` 27, `Ermine scoping` 28, `Ermine library` 3,
  `Constraints` 17. Those construct `ErmineFixture()` with `sigEntail = None`, i.e. the
  shipped `error` default (`untilSigFixes` is `None`), so they boot the corrected stdlib
  under the enforced check -- a stronger gate than the count suggests.
* **`TestSigEntailDiff`**: 8/8 proved. `106 signatures (ACCEPT,101), (REJECT,5)`;
  `decision nodes max 10 median 3 p90 5 total 326; models of Q at one class max 7 median 3;
  label classes max 3`; `2000 random systems, 0 discarded, Passed`. BP-1's numbers exactly.
* **`TestSigEntail`**: 14/14, rc 0.
* **stdlib boots at the DEFAULT**: `Loaded 129 modules (20.63 seconds)` under `error`,
  `129 modules (20.57 s)` under `off`; wall 21.23 s / 21.17 s. Zero `warning`, zero
  `NO VERDICT`, zero `signature-entailment` on either stream in either mode; the
  transcripts differ only in progress-bar timings.
* **`core/examples` `off` vs `error`**, all 25 `.e`, one session per mode: outcome differs
  on **exactly five files -- sig01..sig05** (`Importing module 'ShouldFail.Sig0N'` ->
  `Unable to load module`). `control08_sig_declared.e` and `SoftRelation.e` LOAD in both.
  **Four files fail IDENTICALLY in both modes** -- all pre-existing 2.11 *parse* errors,
  none type-related (this is E2): `guide/HelloWorld.e:44:20` (record comprehension `=>`),
  `Interp.e:24:29` (`(z -> k == (fst z))`), `Sample.e:4:13` (`field Table a : a;`),
  `Yahoo.e:46:30` (`liftA2 maybeAp (++) a b`).
* **The five pins re-measured at the default**, reproducing BP-1 character for character:
  sig01 `:113:17` / `declared at :112:13 (sig healthOpt)` / `given (none)`;
  sig02 `:81:18` / `:80:14 (sig wrongLabel)`, given prints
  `r^S <- ((|ShouldFail.Sig02.mana|), t^B)`;
  **sig03 `:109:25` / `:108:21 (sig local)` -- the site IS `sig local`, the ENTAILMENT
  CHECK AT THE SIGNATURE**, not the pre-LET-1 refusal at the call, and the message is not
  `Row partitions are unsatisfiable at field ...`. CONFIRMED;
  sig04 `:87:8` / `:86:8 (sig bump)`, minted variable prints `t'`;
  sig05 `:100:19` / `:100:12 (ann <annot>)`, naming `crash2`.
* NOT RE-MEASURED (outside the brief's gate list): BP-1 §3's `.ei` publication analysis and
  the `warn` sweep that generated the resources. The resources are gated by
  `TestSigEntailDiff`; `interfaceKey`'s expression is byte-identical to main's
  (`5162945:Session.scala:184-185`) and asserted by `TestSigEntail`'s key property.

6. Other findings from the adversarial pass
-------------------------------------------
* `Constraints.scala` whole-file diff vs main is **2 hunks**, both the known pre-existing
  Scala-3-only ones (`PQueue extends ForeachIterable` vs `Traversable`; `Tag.unwrap` for
  scalaz 7.1 vs bare for 7.0). Neither is in BP-1's diff, i.e. both were already at HEAD.
  So **the `LabelSearch` lift is byte-identical to main's**; BP-1's diff is 14 hunks at
  `-U0`, exactly as reported, all inside :2742-3046.
* Every new constructor parameter is LAST and DEFAULTED -- `SubstEnv.sigEntail`,
  `SessionEnv._sigEntail` (with `copy` passing `Some(that.sigEntail)` as its 14th
  positional argument), `ErmineFixture.sigEntail` -- so the three other
  `new SubstEnv`/`new SessionEnv` sites (`Console.scala:794`, `Session.scala:1483`,
  `TestConstraints.scala:21`) and the four other `ErmineFixture()` sites are unaffected.
* `TestSigEntailDiff`'s scalacheck-1.11.3 adaptation is the one edit with real failure
  modes, and it is safe: the self-checking property asserts `res.succeeded ?= 2000`
  SEPARATELY from `res.passed`, so a `Proved`-after-one-case or an early stop FAILS rather
  than passing vacuously -- and the run printed `2000 random systems, 0 discarded, Passed`.
  `withWorkers(1)` is safer than main's default given that `lastCost` is a `ThreadLocal`.
  Every other property in the suite is `secure`/`proved` (all 8 report "proved property"),
  so dropping `overrideParameters` loses no coverage.
* `.view.mapValues(_.size).toMap` -> `.map { case (k,v) => (k, v.size) }` is strict on both
  sides, so `?=` compares maps not views; the 2.11 lazy-`mapValues` trap is real.
  `Source -> IoSource` and `label -> labelOf` are forced (a package-level
  `com.clarifi.reporting.Source`; `Prop.label(String): Prop`, which the private helper
  would override with weaker access), and compilation proves no use was missed -- a
  surviving bare `Source.fromFile` or `map(label)` would not type-check.
* `TestSigEntail`'s let-bound property is `no(typeChecks(...))`, which passes whether the
  refusal comes from the check or from inference at the call. That is main's own shape, so
  not a regression; the site is pinned by measurement, not by the property. Asserting the
  `sig local` site would be a real improvement and is the only coverage gap I found (N1).
* `Session.interfaceKey`'s S3 review D5 (process default vs session mode) is carried with
  main's comment and is harmless here for main's reason, which I verified holds: the only
  fixtures that set a session mode (`TestSigEntail`'s two) also set `_useInterface = false`.
