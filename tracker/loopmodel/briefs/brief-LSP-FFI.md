# Brief: LSP-FFI — the language server tolerates missing or mismatched FFI bindings of every kind

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `4380ae3`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed; `sbt core/compile
core/copyResources` before any `bin/ermine` or LSP gate (compile alone does not copy the stdlib `.e` into the target
tree); the LSP classpath is `tracker/repl-classpath.txt` (regenerate with `sbt -batch 'export core/fullClasspath' |
tail -1 > tracker/repl-classpath.txt` if you change the build); delete every `.ei` you cause; no commits; do not
touch `tracker/lean/`. GATES per `tracker/GATE-POLICY.md` Tier 0 (this change is on the LOAD path, not the solver;
Tier 1 only if the row trace moves, which it must not). Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/LSP-FFI/`.

THE USER'S ASK (2026-09-08): "make sure we are tolerant to missing FFI bindings of various kinds. We will be using the
LSP with an older fork of Ermine which does not have Scala 3. The primary work that has happened there is changes to
the FFI interface (the writer trait)." The fork's `.e` modules (Layout/Writer/*.e and their users; the sibling repo
`~/research/ermine/ermine-writers` has a few `foreign data` declarations of that shape) reference Scala classes and
members the LSP's JVM does not have, or has with other signatures. Today ANY foreign resolution failure `die`s the
module (`ForeignClasses.classLookup` -> `Class.forName`, `Left`; `Session.scala` ~1032-1230 `foreignLift`,
`getMethods.find` by name+arity, `getMethod`, `isAssignableFrom` return check at ~1181-1188, `getField` at ~1214) and
the LSP turns the `Death` into ONE diagnostic for the file (`lsp/Diagnostics.scala:117`) — so the module and EVERY
dependent go unchecked in the editor. Note `classLookup` catches `Exception` only: a class that is present but whose
own dependency is missing throws `NoClassDefFoundError` (an Error) and is UNCAUGHT today.

## Decisions (the orchestrator's defaults; the user may override — record any override in the report)
- SEVERITY: warning (LSP severity 2) at the declaration; everything else in the module and its dependents is checked
  normally. Not an error, not silent.
- SCOPE: a session option (`SessionEnv` field, e.g. `_foreignTolerant: Option[Boolean]`, system property
  `ermine.foreign.tolerant`), DEFAULT OFF for `bin/ermine`/the REPL/`core/test` (batch builds keep today's hard
  failure, byte-identical messages), DEFAULT ON in the LSP `Resident` only.
- CORPUS: synthetic fixtures (the fork's checkout is not on this machine); make them mimic the writer-trait shape.

## What to build
L1 The FAILURE KINDS, one code path each, each tolerated: (1) class missing (`ClassNotFoundException`); (2) class
   present but unloadable (`NoClassDefFoundError` / `LinkageError` — catch `Throwable` where the JVM can throw an
   Error, never swallow `OutOfMemoryError`/`StackOverflowError`: rethrow those); (3) member (method) missing;
   (4) arity mismatch; (5) return type not assignable to the declared codomain; (6) field missing (`foreign value`);
   (7) constructor missing (`foreign constructor`); (8) `foreign subtype` of a missing class; (9) `foreign data` of a
   missing class (an opaque type: must type-check with NO warning if nothing needs the class, and a warning only at
   the site that needs it — say precisely which operations need the class). Use the six surface forms
   (`SForeignData/Function/Method/Value/Constructor/Subtype` in `surface/Surface.scala:213-218`, each with a
   className span and/or member span) so the diagnostic lands on the CLASS NAME for (1)(2)(8)(9) and on the MEMBER
   for (3)-(7).
L2 THE STUB: on a tolerated failure the binding is installed at its DECLARED type (every foreign term form carries
   `ty`), bound to a value that raises an Ermine error when EVALUATED — "unresolved foreign binding `name`: <kind>:
   <class>[.<member>] — <JVM message>" — so type-checking, navigation and hover work, and only running it fails.
   `foreign data` of a missing class registers the type with no backing class. Say what happens on a `.ei` read of a
   module whose interface mentions such a binding (the tolerant path must apply there too, or state why not).
L3 THE NOTE: each tolerated failure records a positioned note the LSP publishes as a warning (the `Checked.notes`
   path with severity 2, `fromReport`), text naming the binding, the kind, the class and member and the JVM cause.
   With the option OFF the behaviour and messages are byte-identical to today (repl-smoke goldens must not move).
L4 FIXTURES in `tracker/lsp-tests/` and checks in `tracker/tools/lsp-client.py`: one module per failure kind
   (1)-(9), each with the expected diagnostic count (exactly one warning, severity 2), its position (the class/member
   span) and message substring; a DEPENDENT module importing one of them and USING the stub-typed binding in a
   well-typed way (must be clean: zero diagnostics) and in an ill-typed way (one type error at the use site, proving
   the declared type is live); a writer-trait look-alike (`foreign data "com.clarifi.reporting.writers.Writer" Writer`,
   `foreign function "..." "render"` over it, a module that calls it) — clean apart from the warnings; and one
   `foreign data` fixture with no warning. Then `lsp-smoke.sh` green: the old 98 checks plus the new ones (count
   them). REPL side: a `repl-tests` case showing the default (non-tolerant) still dies with today's message, and one
   with `-Dermine.foreign.tolerant=true` showing the stub's evaluation-time error.
L5 Sweep every `foreign` loader for the pattern (list what you checked) and every place `Death` from a foreign
   failure is caught; the `NoClassDefFoundError` gap is fixed in BOTH modes (it is a crash today, not a diagnostic).

## Gates (Tier 0 + the LSP's own): `sbt core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh
--batch` 85 / 69 / 0 over 154 (unchanged — the option is off there); `lsp-smoke.sh` all checks incl. the new ones;
`repl-smoke.sh` goldens byte-unchanged plus the two new cases; `sbt core/test` unchanged except any test you add;
the stdlib boot in the LSP (`Resident.boot`) still 129 modules and its time within noise. Report
`tracker/LSP-FFI-TOLERANCE.md` (design, the nine kinds with their probes before/after, the diffs, every gate), a
dated additive entry in `tracker/LSP-ROADMAP.md`'s iteration log ("detour, not Stage 3"), and the user's three
decisions recorded as defaults taken. Outcomes: (GREEN) all nine kinds; (PARTIAL) which kind and why. No silent
weakening; report early; STOP after the report — a reviewer re-runs the gates once.
