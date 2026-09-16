# 2.11 port brief (P1, P2, P3)

Port landed Scala 3 stages from `json-encode` to `json-encode-2.11`, by COPY plus hook sites,
in the worktree `~/research/ermine/ermine-scala-wt-json211` (branch `json-encode-2.11`).
Budget: 3 h per port. Read `brief-J-common.md` (dialect, testing, conduct), `BACKPORT.md` on
the 2.11 branch (the JSON sections: how Stages 0, 1a, 1b were ported and every divergence),
and the Scala 3 reports of the stages you port.

## Toolchain

```
cd ~/research/ermine/ermine-scala-wt-json211
source backport/env-2.11.sh
sbt211 core/compile        # JDK 8, Scala 2.11.5, sbt 0.13.5
sbt211 'core/testOnly com.clarifi.reporting.TestJson'
```
The branch TRACKS `core/target` and `backport/.classpath`: they show as modified after a
build. Never `git add -A`; commit (when told) with explicit paths only, and never commit
build output. The 2.11 build has no new pipeline: the parser is fused
(`StatementParsers`, `ModuleParsers`), there is no LSP, scalacheck is an older version.

## Method

1. For each Scala 3 commit being ported: `git -C ~/research/ermine/ermine-scala-wt-json show
   <commit> --stat`, then copy the new/changed files under `json/`, `modules/`, tests,
   `client/`, `bin/` scripts (2.11 CLI wrappers live under `backport/`, see how
   `backport/ermine-schema` was done). Shared files (`Encode.scala`, `Schema.scala`, ...)
   should end up byte-identical to Scala 3 unless a documented divergence forces otherwise.
2. Hook sites: `Lib.scala` (the `json` primitives), `Session`/Console hooks if touched,
   anything the Scala 3 change did outside `json/`. Apply by meaning; keep the file's line
   endings.
3. Tests: copy the Scala 3 test files; adapt only what the older scalacheck/scalaz or the
   fused parser require, and list every adaptation.
4. `client/` is language-independent: copy it and run its checks against documents produced
   by THIS branch's build (they must be byte-identical to the Scala 3 ones for the same
   inputs; show a diff over a sample).

## Gates

- `sbt211 core/compile`; the ported suites and TestJson/TestSchema/TestNamedFields.
- Full `sbt211 core/test` ONCE at the end of the port (baseline 793 = 792 pass + 1 skip,
  plus additions; report the exact count).
- A REPL smoke: the Scala 3 `tracker/repl-tests/json.in` answers byte-identical (as in
  BACKPORT.md), plus any new smoke the stages added.
- For P2 (runner): start `backport/ermine-serve` on an ephemeral port and replay the Scala 3
  example report's requests; bodies identical modulo tokens.

## Report

Append a section per stage to `BACKPORT.md` (what was copied, hook sites, adaptations,
divergences, gate numbers) and write `tracker/json-stage3/report-P<n>.md` in the 2.11
worktree's copy of the tracker (or the Scala 3 worktree if the 2.11 branch has no tracker
directory -- say which). Do not commit; the orchestrator reviews and commits.
