# Rules for every SQL-audit agent

Read first: `tracker/sql-audit/PLAN.md`, then your own brief, then `docs/gate-policy.md` §1-3.
Skim `tracker/db/OBSERVABILITY.md` §9 (the one engine finding so far) and
`scalacheck-binding/src/main/scala/TestInMemoryScan.scala`'s header (how a silent breakage was found
and written up).

## Toolchain

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt -batch core/compile core/copyResources        # compile alone does NOT copy the stdlib .e
sbt -batch 'core/testOnly *TestSqlEmitters* *TestInMemoryScan*'
bin/ermine                                        # REPL, ~7 s boot; :load file.e; :type expr
```

- Machine: 12 cores, 15 GB RAM, the SQL Server container holds ~1 GB. **At most two sbt JVMs
  alive on the box at once, and one per worktree.** Before every `sbt`: run
  `/home/dmitry/research/ermine/scripts/liveness.sh` and, if it shows `sbt=2` or
  `mem-avail` under 3G, wait (`sleep 60` in a loop) rather than start a third.
- Auditors (read-mostly roles) do not run sbt at all. To see the SQL a relation compiles to,
  write a small Ermine module and dump it through the REPL in `ermine-scala-wt-sql-audit`
  (compiled for you; wait until `scratch-sql-audit/logs/compile-audit.log` ends with `success`):
  `Scanners.dumpQuery sqlite rel` / `dumpQuery sqlServer rel` (see `tracker/tools/sql-render.sh`
  for the idiom and the `.in` self-labelling trick). Run the REPL under
  `flock /home/dmitry/research/ermine/scratch-sql-audit/repl.lock bin/ermine ...` so only one
  REPL JVM runs at a time across the fleet. Never a bare `let`/`case` line into a piped REPL.
- The live SQL Server: `scripts/db.sh status|sql ErmineSales "..."`. It holds the Sales corpus at
  tier s (1,000 order lines). Read-only use for auditors. Do not `load`/`unload`/`down`.
  The password lives only in `~/.config/ermine/db.env`; never print it, never put it on a
  command line; tests take it from `ERMINE_DB_PASSWORD` in the environment
  (`tracker/tools/db-reports.sh` shows how a script reads it).
- Files are LF; some old `.scala`/`.e` are CRLF: `file` first, keep a file's endings.
- Scala dialect: this code is copied to a Scala 2.11 branch. Implicit parameters only; no
  `given`/`using`/`enum`/`extension`/`export`, no top-level definitions, no `LazyList`,
  no `Using`, JDK 8 APIs only. Write it the way the surrounding file is written.
- The 2.13 collections hazard: `Map#filterKeys`/`mapValues` give lazy views with `Object`
  equality. Any new code that compares or hashes one must `.toMap` it. Hunt for this.

## Findings format (`tracker/sql-audit/FINDINGS-<role>.md`)

One table row per finding, then a section per finding:

`| id | severity | where (file:line) | one-line claim | repro | proposed fix | blast radius |`

- severity: `WRONG` (produces wrong rows, wrong values, an exception, or SQL a live dialect
  rejects), `WASTE` (correct but needlessly expensive: extra scans, rows fetched to be dropped,
  temp tables, DISTINCT or subqueries that a rewrite removes), `FRAGILE` (correct today by luck:
  unspecified order, driver quirks, unchecked casts), `NOTE` (worth knowing, no action).
- repro: the smallest Ermine relation (or Scala `Relation` value) that shows it, the SQL it
  produced, and what should have happened. For WRONG: the observed vs expected rows. Say
  which dialect(s) and whether you ran it live (SQLite in-memory / SQL Server) or reasoned
  from the code. "MEASURED" vs "READ" on every claim, as the DB programme's docs do.
- Rank the table: WRONG first, then WASTE by estimated cost on the Sales corpus at tier l
  (2 M fact rows), then the rest.

## Conduct

- Work only where your brief says. Auditors write only under `tracker/sql-audit/` and
  `scratch-sql-audit/`. Implementers work in their own worktree and never commit; the
  orchestrator commits after review. Never push, never merge, never touch another worktree,
  never `git stash`.
- The board `scratch-sql-audit/BOARD.md` is append-only: `[YYYY-MM-DD HH:MM] [role]
  [decision|question|finding|handoff|blocked] text`. Read it before starting and before any
  claim about another role's area. Post a finding that another role should know about as soon
  as you have it (a `WRONG` that the oracle should target, a rewrite the emitter must
  support). Do not wait for the end. Post questions and continue; never block on the
  orchestrator.
- Budget: your brief gives hours. At the budget, write up what you have and stop. A partial
  findings file with repros beats a complete one without.
- Your final message to the orchestrator is at most 40 lines: counts by severity, the top
  five findings in one line each, the path of your findings file, anything the orchestrator
  must decide. Everything else goes in the file.
