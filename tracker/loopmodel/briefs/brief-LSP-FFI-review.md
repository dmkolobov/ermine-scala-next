# Review brief: LSP-FFI — tolerance to missing or mismatched FFI bindings in the language server

You are reviewing stage LSP-FFI in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD
`2121d0c` plus the UNCOMMITTED deliverables). Implementer's brief `tracker/loopmodel/briefs/brief-LSP-FFI.md`; report
`tracker/LSP-FFI-TOLERANCE.md`; changes: 12 Scala files (`parsing/ForeignClasses.scala`, `session/Session.scala`,
`session/SessionState.scala`, `session/TolerantCheck.scala`, `session/Console.scala`, `Type.scala`, `Subst.scala`,
`rename/NewPipeline.scala`, `rename/Renamer.scala`, `syntax/Statement.scala`, `lsp/Diagnostics.scala`,
`lsp/Resident.scala`), 13 fixtures `tracker/lsp-tests/Ffi*.e`, `tracker/tools/lsp-client.py` (+52 checks),
`tracker/tools/repl-smoke.sh` (per-case `.opts`), two new `tracker/repl-tests` cases, `tracker/LSP-ROADMAP.md` log
entry. You edit NOTHING except a scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-LSP-FFI/` and your
report `tracker/loopmodel/LSP-FFI-REVIEW.md`. ONE JVM at a time (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`,
sbt allowed); `sbt core/compile core/copyResources` before any `bin/ermine`/LSP gate; the LSP classpath is
`tracker/repl-classpath.txt`; delete every `.ei` you cause; no commits; do not touch `tracker/lean/`. Gate policy:
`tracker/GATE-POLICY.md` — you re-run Tier 0 and the LSP suites ONCE; your numbers are the ones that go into the
trackers. The user's ask: the LSP will be used with an OLDER Scala-2 fork of Ermine whose FFI (the writer trait)
changed, so its modules reference classes/members this JVM lacks; the editor must keep checking those modules and
everything that imports them.

1. **The nine kinds, each probed by you.** Build your own minimal module per kind (class missing; class present but
   unlinkable; method missing; arity mismatch; return type not assignable; field missing; constructor missing;
   `foreign subtype` of a missing class; `foreign data` of a missing class) and check, in the LSP (drive it with
   `tracker/tools/lsp-client.py`'s machinery or a scratch client): the diagnostic count, severity 2, the RANGE (class
   literal for 1/2, member literal for 3-6/9, declared name for 7/8), the message text; that the rest of the module
   is checked (put a genuine type error elsewhere in the same module and confirm it is ALSO reported); that a
   DEPENDENT module using the stub-typed binding well-typed is clean and ill-typed gets one error at the use site.
2. **The judgement calls (report §2.2) — decide them.** (a) `foreign data` of a missing class NEVER warns: is silence
   right for the user's scenario (a fork module whose writer class is absent), or should there be an
   information-level note? Say which and why. (b) `foreign subtype` over such a type warns but keeps the identity.
   (c) The stub is `Bottom` at the declared type: what does a user see if they evaluate it in the REPL with the flag
   on, and can `IO.catch` catch it (report A7 notes foreign exceptions become Bottom)? (d) `classLookup` now catches
   `Throwable` minus `VirtualMachineError`/`InterruptedException`/`ControlThrowable` — is that list right, and is the
   `NoClassDefFoundError` case now a positioned error in BOTH modes (verify batch: before it was an uncaught crash)?
3. **Default OFF is byte-identical.** With the option off: `repl-smoke.sh`'s pre-existing goldens byte-unchanged;
   `corpus-run.sh --batch` 85 / 69 / 0 over 154 with outputs identical to a pre-change run (build the pre-change
   compiler in scratch from `git show HEAD:<path>` as F3's reviewer did, or diff against the F3 review's saved
   outputs in `/home/dmitry/.claude/jobs/880c725d/tmp/review-F3/`); `TestLoopTrace` 720/720. Any batch difference
   other than the `NoClassDefFoundError` crash becoming a diagnostic is a finding.
4. **The `.ei` claim.** The report says `loadModule` runs the foreign statements from source on every load, so an
   interface read reproduces the warnings and the stub: verify on a two-module fixture with `-Dermine.useInterface`
   on (cold then warm), in tolerant mode.
5. **Coverage.** Sweep every foreign loader and every `catch` of a foreign `Death` (list them); the `TolerantCheck.Note`
   `Option[Span]` change — do the 98 pre-existing lsp-smoke checks still assert the same positions? The kind-2
   fixture depends on `log4j-core` shipping a class whose Jackson superclass this build lacks — fragile; say whether
   a self-contained fixture is feasible (a tiny class compiled into a test jar with a missing dependency) and
   recommend.
6. **Gates, re-run once:** `sbt core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch`;
   `lsp-smoke.sh` 150 checks; `repl-smoke.sh` 7/7; `sbt core/test` 938/0/0 (the disjunction quarantine); LSP boot
   129 modules and its time; prose: report, roadmap entry, the three defaults recorded.

Findings prefixed `P-`, ranked, CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE / REDO.
Write the report early and keep it current.
