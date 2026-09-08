# Brief: F3 — the small library and migration fixes from the corpus programme (A1b, B1, A4, A3, C2, C5, K-1)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `490d0e4` (shipped
defaults now include `topNormalise`). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed; long runs under `setsid nohup`
with a log; delete every `.ei` you cause; do not touch `tracker/lean/`; no commits. Work in MAIN (no worktree: none of
these is a solver flag). Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/F3/`. Ticket: `tracker/TICKET-stdlib-findings.md`
(read each item and the report sections it cites); K-1 is `tracker/ROSE-COMPARISON.md` §3 Rank 1's dated correction
(S3 review K-1). Seven items, each small; the point of the stage is that EACH is reproduced before it is fixed and has
a test or a measured gate after.

F3.1 **A1b** — three `MapView` equality/hash sites the Scala 2.13 migration left (`SqlScanner.scala:644` `kr == k`
     against a view: in-memory pivot gives every column its default; `:708` `Tee.hashJoin`'s key is a view: the join
     emits nothing; `relational/package.scala:67` the chunk predicate is always false: `sorting` never groups).
     Reproduce each with a REPL forcing on the in-memory path (record the wrong output), fix with `.toMap`, and add a
     `core/test` property that drives the in-memory pivot, hash join and sort so they cannot regress. Grep for every
     other `MapView`/`view` comparison or hashing site in `core/src` and list what you checked.
F3.2 **B1** — `Relation/Op.e:150` `dateDiff`'s wrapper has no signature (infers `Op r2 Int` with `r2` free). Reproduce
     the deferred failure (`combine_Op (dateDiff …)` over a relation lacking the dates checks, then fails at header
     computation), add the one-line signature, show the same program is now rejected statically with a sensible
     message, and that the corpus still loads.
F3.3 **A4** — `Date.formatQuarter` uses `/ 4` and a 1-based index into a 0-based list ("Q1" unreachable). Reproduce
     (January prints "Q2" under UTC), fix (`/ 3`, 0-based), test all twelve months.
F3.4 **A3** — `Date`'s accessors read the instant in the JVM's default timezone while its formatters use UTC, so
     `getMonth @2011/1/1` is 11 under MDT and 0 under UTC and every `DateRange` period label is machine-dependent.
     Reproduce with and without `-Duser.timezone=UTC`. Fix: ONE timezone (UTC) for both, documented in `Date.e`'s
     header; a test that runs the accessors under a non-UTC default timezone (set it in the test JVM or per test) and
     gets the UTC answer. Say which stdlib and example bindings change published behaviour and check the corpus
     renderings (`tracker/tools/sql-render.sh` where applicable) for any that move.
F3.5 **C2** — `Relation.join1`'s doc comment says "the intersection is nonempty"; it is `joinBy {f}`. Fix the comment.
F3.6 **C5** — `Layout.Scan` omits exactly `removeK`, `removeBy`, `multiply`: add the re-exports (test: they resolve
     from `Layout.Scan`). `Relation.Scan.sumBy'` carries a vacuous `r <- (h, t)`: drop it from the signature and show
     the published residual shrinks and nothing else changes (`.ei` diff). `rename'` is misnamed: do NOT rename the
     API; add a doc line saying what it requires.
F3.7 **K-1** — `Type.scala:414` `case ConcreteRho(lclhs, cs) if ts.isEmpty && ss == cs` compares a `List[Name]` to a
     `Set[Name]` and is dead code, so the concrete identity `(|Foo,Bar|) <- (|Foo,Bar|)` is rebuilt and reaches the
     solver. Fix: `ss.toSet == cs`. THIS ONE IS ON THE PRE-SOLVER PATH and may move the row trace: reproduce first (a
     module whose signature carries the concrete identity; show the constraint reaching the solver in the trace),
     then after the fix run the FULL row-trace gates below; every trace change must be the disappearance of a
     concrete-identity constraint and nothing else — if anything else moves, STOP and report before going on.

## Gates (report every number)
`sbt core/test` (921/922 with the documented `Constraints.disjunction` failure, plus your new tests passing);
`TestLoopTrace` 720/720; `corpus-run.sh --batch` 85 LOADED / 68 REJECTED / 0 UNKNOWN unchanged (or the exact
expected change from B1, named); the 18-group `looptrace-corpus.sh` differential: agree = segments, 0 skipped, and a
diff of the per-group traces against a pre-fix run classified (K-1's deletions only); the `.ei` sweep
(`ei-diff.sh --batch` with `-Dermine.loadInSeries=true` on both sides, `ei-classify.py`): every moved binding is
`sumBy'`'s shorter residual or a K-1 identity deletion, nothing weaker; `repl-smoke.sh` and `lsp-smoke.sh`;
`perf-bench batch -n 3` when the load is < 1.3 (it refuses otherwise). Report `tracker/loopmodel/F3-FIXES.md`
(per item: reproduction before, the diff, the test, the gates), update the seven ticket entries to "FIXED in
<commit>" (the orchestrator fills the hash), a plan row F3, the state file ONLY if K-1 moved anything solver-visible
(then a dated additive note). Outcomes: (GREEN) all seven; (PARTIAL) which items and the obstacle. No silent
weakening; report early; STOP after the report — a reviewer re-runs everything.
