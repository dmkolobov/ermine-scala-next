# Review brief: F4 — the interface round-trip fix (ticket E1)

You are reviewing stage F4 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `96856f6`
plus the UNCOMMITTED deliverables). Implementer's brief `tracker/loopmodel/briefs/brief-F4.md`; report
`tracker/loopmodel/F4-ROUNDTRIP.md`; changes: `parsing/TypeParsers.scala` (new `dottedFieldName` used by `rho`;
`dottedName` untouched for `interfaceCon`), NEW `scalacheck-binding/src/main/scala/TestInterfaceConcreteRow.scala`
(3 properties), ticket E1, plan row F4. You edit NOTHING except a scratch directory
`/home/dmitry/.claude/jobs/880c725d/tmp/review-F4/` and your report `tracker/loopmodel/F4-REVIEW.md`. ONE JVM at a
time (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, sbt allowed); `sbt core/compile core/copyResources`
before any `bin/ermine` gate; delete every `.ei` you cause (never the checked-in `tracker/g1-*`); no commits; do not
touch `tracker/lean/`. Per `tracker/GATE-POLICY.md` you re-run Tier 0 once (the fix is on the READER: no published
byte moves, the row trace cannot move; `g1-validate` too since it is cheap); your numbers go into the trackers.

1. **The cause.** `Pretty.qualifiedGlobal` publishes a concrete row's field label fully qualified
   (`(|Currency.currencyCode|)`); `TypeParsers.rho` read it with `dottedName`, which requires EVERY segment to start
   upper case, so a label whose last segment starts lower case was unreadable → `preCk` `None` → `Full` every load.
   Confirm by building the pre-fix compiler in scratch (`git show HEAD:core/src/main/scala/com/clarifi/reporting/
   ermine/parsing/TypeParsers.scala`, F3's reviewer's recipe) and reproducing the probe; confirm the corrected scope
   (it is the LABEL, not the partition shape: fails as a part, as a `Relation` argument, as a `Record` argument) with
   your own probes; re-derive the census (7,448 dotted-lower / 53 dotted-upper / 34 empty labels; the 70 interfaces
   holding a dotted-lower label = exactly the 70 rewritten every load, no cascade).
2. **The fix is minimal and exact.** `dottedFieldName` = upper-case module path then ONE identifier of any case: can
   it now accept something `dottedName` rightly rejected, or misparse a constructor as a label anywhere `rho` is
   used (the type grammar for SOURCE files uses `TypeParsers` too — does source parsing change? probe a source
   module with a lower-case dotted name in a row and a constructor in a row, before and after). Are the two
   remaining unreadable forms (an abnormal label without back-quotes; an operator-fixity label) really unreachable
   from Ermine source? Try to reach them.
3. **The tests.** Re-run the three properties; confirm the implementer's "RED before" claim on your pre-fix build;
   judge property 3's alpha-equivalence relaxation (byte identity not asserted: `Part.apply` reverses the rhs;
   id-ordered existentials; ticket B3) — is the relaxation the weakest it could be, and does `Prop.collect`'s
   196/245 byte-identical figure reproduce? Is the corpus-staging fixture robust to the process-global dep cache
   (S5 was bitten twice)? Run the new suite 3x alone and once inside the full suite.
4. **Gates, re-run once:** compile+copyResources; `TestLoopTrace` 720/720; `corpus-run.sh --batch` 85 / 69 / 0;
   `lsp-smoke.sh` 185 and boot 129; `repl-smoke.sh`; `g1-validate.sh` 9/9; the corpus double run rewriting 0 of
   241; `sbt core/test` 943/943 (Tier 2 is not required — no default flips — but the suite gained tests, so run it
   ALONE if you have the time and say so either way); the warm-load timing (interleaved old/new) — reproduce the
   ~35 s → ~24 s bands or say what you measured.
5. **Prose:** the ticket E1 corrections, the plan row, the report's printer/parser table (10 `ppType` cases, 8 name
   forms) — spot-check three rows each by construction.

Findings prefixed `R-`, ranked, CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE / REDO.
Write the report early and keep it current.
