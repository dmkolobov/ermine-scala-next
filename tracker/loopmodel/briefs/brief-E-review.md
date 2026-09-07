# Review brief (template) for an E-series example group — judge the examples as PROGRAMS and as CORPUS

You are reviewing stage `$STAGE` (group `core/examples/$GROUP/`) in `/home/dmitry/research/ermine/ermine-scala`
(branch `scala3-migration`). The implementer's briefs are `tracker/loopmodel/briefs/brief-E-common.md` and
`brief-$STAGE.md`; its report is `tracker/loopmodel/$STAGE-EXAMPLES.md`; its changes are `core/examples/$GROUP/**`
(uncommitted) and one plan row. Other agents are writing other groups on this machine: you do NOT edit anything
except a scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-$STAGE/` and your report
`tracker/loopmodel/$STAGE-REVIEW.md`. ONE JVM at a time, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`;
long runs under `setsid nohup` with a log (background shells are capped at ten minutes); `pkill -f` matches
itself (kill by PID); delete every `.ei` you cause; no commits; never `lake build` (others run the built
`looptrace` binary) — `lake exe looptrace --replay …` and `lake env lean` only.

The user's ask (2026-09-06): "develop the examples directory even further … different under-exampled aspects
of ermine … many examples of interesting generic helpers." Two audiences: a USER who learns the language from
these files, and the row solver's certification CORPUS. Review both.

1. **As programs.** Read every module in full. For each: is it a realistic report a user would recognise, with
   data that makes sense, a header that says what it exercises and how to run it, helpers with explicit and
   honest signatures and doc comments? Is anything contrived, misleading, wrong (a helper documented as doing
   X that does Y), or duplicated across modules? Would you learn the feature from it? Name the three best and
   the three weakest modules and say why. Check every negative module's expected diagnostic against the real
   one.
2. **Re-run the gates**: every module per file and in one batch (`bin/ermine` with the library first), the
   negatives, `sbt core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead` (these walk every
   `.e`; the file-count constant in `TestSurfaceParsers.scala` is expected to trip until the orchestrator
   updates it — report the count), the L2 differential on the group (compiler `-Dermine.useInterface=false
   -Dermine.loadInSeries=true -Dermine.rowTrace=<file>`, model `lake exe looptrace --replay <file>`: 0 skipped /
   0 hashdiff / 0 eqdiff), the census (`--depth`, `--cycle`, the `rsound` records) — reproduce the report's
   table; the `.ei` residuals of the helpers (deterministic loader); the renderings by whatever route the
   report used (the REPL harness, or E1's `tracker/tools/sql-render.sh` if present — say which relations it
   cannot render and why).
3. **The findings about Ermine itself.** Every stdlib or language finding the report makes (a helper that
   cannot do what it is named for, a doc comment that is wrong, a syntax trap, a claim in an older README that
   does not reproduce): CONFIRM or refute each with a minimal module of your own, and say which deserve a
   ticket entry (`tracker/TICKET-editor-and-solver-followups.md` or a new `tracker/TICKET-stdlib-findings.md`
   — recommend, do not write).
4. **Coverage.** Against the brief's list of under-exampled modules/functions: which are now exercised, which
   the group missed and why (the report's "could not write" list — is each really inexpressible, or missed?),
   and what a follow-up module would add.
5. **The census claim.** Does the group reach shapes the old corpus did not (the report's G3 comparison)? Say
   precisely what moved and what did not; if the group is gentler on the solver than the old corpus, say so
   plainly — that is a finding, not a failure.

Findings ranked by severity, each CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE (commit the group) /
FIX-THEN-ADVANCE (list the required fixes) / REDO. Then the wiring lines the orchestrator must add, checked
against the report's. Write the report early and keep it current.
