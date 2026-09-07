# Common brief for the E-series example stages (E2–E5): conventions, rules, gates

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, at `2dd7dc3` or later (the
three row-solver defaults ADOPTED: `-Dermine.rowSound` ON, `-Dermine.dequeuePolicy=smallcanon`,
`-Dermine.solveBudget=20000`). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"` on EVERY `bin/ermine` (other agents share this machine: 12
cores, ~9 GB free; you get ONE JVM at a time); long runs under `setsid nohup` with a log (background shells are
capped at ten minutes) with a driver that fails on a non-zero build; `pkill -f` matches itself (kill by PID);
disk tight — gzip traces, delete every `.ei` you cause under `core/examples` when a gate is done; scratch under
`/home/dmitry/.claude/jobs/880c725d/tmp/<STAGE>/`; no commits; never touch `tracker/lean/` (the model replays a
new group without change), `~/research/leanwork`, or any file outside your own group directory except the
report and the plan row named below.

THE USER'S ASK (2026-09-06): "develop the examples directory even further … do this with background agents.
Attempt to find different under-exampled aspects of ermine. Develop a corpus. Try to have many examples of
interesting generic helpers." Ermine is a REPORTING language. The examples are both documentation a user learns
from and the certification corpus for the row solver: every solve of every example is traced and replayed
through the Lean model (`tracker/tools/looptrace-corpus.sh`), and the termination/soundness census is measured
over them. The import census says where the gaps are: of the stdlib's ~160 modules the examples import ~40;
`Prelude`/`Syntax.Relation`/`Relation.Op`/`Layout`/`Relation.Predicate`/`Relation.Row` dominate; whole families
have ZERO example uses.

## Conventions (read the models first)

* `core/examples/Ai/README.md` and three Ai modules in full (`SupplyChainInventory.e`, `FiscalCalendar.e`,
  `ClinicalTrial.e`): self-contained realistic reports, data inline (`relation [...]`/`mem [...]`), a header
  block per file (subject; the tables and their fields; the helpers used; WHICH SOLVER OR LANGUAGE SHAPES it
  exercises; `>> :load` / `render` recipe), a group `Common.e`/`Helpers.e` holding the row-polymorphic helpers
  with EXPLICIT signatures and doc comments (the Ai README's lesson: a helper is only useful if its call sites
  check; measure the RUnion pitfall if you hit it — at the new defaults, report whether it still bites).
* `core/examples/incomplete/README.md`: the `.slow` convention — a module that does not type-check in
  reasonable time is named `.slow`, NEVER left as `.e` (`core/test` type-checks every `.e` it finds). At the new
  defaults the draw budget should stop any runaway solve with a diagnostic: if a module of yours hits it, that
  is a FINDING (record the diagnostic and the module) and the module becomes `.slow`.
* `core/examples/incomplete/Signatures.e`: how a residual signature is hand-written and proved equivalent — do
  this for at least two of your helpers (an `xFull`/`xSimple` pair).
* One `shouldfail`-style negative module per group in `<Group>/shouldfail/`, misusing a helper, with the
  EXPECTED diagnostic recorded in its header.
* Every helper: explicit signature, a doc comment naming the row constraint it carries and why, a call site on a
  table with at least a dozen fields somewhere in the group.

## Wiring (do NOT edit shared tooling yourself — record what is needed)

Another stage (E1) is editing `tracker/tools/corpus-run.sh`, `tracker/tools/looptrace-corpus.sh` and
`core/examples/README.md` for its own group; to avoid collisions you do NOT edit those. Instead your report
lists exactly the lines to add (the `Ai)`-style rule that puts your `Helpers.e` first; the group name in the
default list). The orchestrator wires every group at the end. For your OWN gates, drive the tools with explicit
file lists: `bin/ermine core/examples/<Group>/Helpers.e <the rest>`; `LOOPTRACE_GROUPS` is not needed — trace
your group directly: `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false
-Dermine.loadInSeries=true -Dermine.rowTrace=<scratch>/<Group>.tsv" bin/ermine <files>`, then in `tracker/lean/`
(`export PATH=$HOME/.elan/bin:$PATH`) `lake exe looptrace --replay <scratch>/<Group>.tsv` (0 skipped / 0
hashdiff / 0 eqdiff), `--depth` and `--cycle` for the census; the `rsound` records for the decision's cost.

## Gates and measurements (every number with its command, in `tracker/loopmodel/<STAGE>-EXAMPLES.md`)

G1 Every module type-checks (LOADED) per file and in one batch; the negative module REJECTED with the expected
   message; per-file wall clock (name anything over 30 s; `.slow` anything that does not finish, with the
   budget diagnostic if it fired). `sbt core/test` stays 913/914 (or 912 with the known `TestInterfaceRoundTrip`
   flake) and its wall clock grows by no more than your modules' own check time.
G2 The L2 differential on your group: every solve replayed, 0 skipped / 0 hashdiff / 0 eqdiff. A disagreement is
   a FINDING about the model — report it at once with the segment, do not paper over it.
G3 The census over your group vs the old corpus (round 7/8 figures: chain depth ≤ 4, per-key mints ≤ 11, 97.4 %
   of solves vocabulary-fixed, generative rules on ~2.6 %, `concrete` branch on ~25 %): per solve draws, depth,
   per-key mints, dequeues, generative rules, `concrete` steps, decision nodes; the largest draw count against
   the 20,000 budget; which shapes your group reaches that the old corpus did not.
G4 `render` every report through the REPL harness (`tracker/tools/repl-smoke.sh` shows how the REPL is driven
   non-interactively): no errors; one trimmed rendering per report in the report. The `.ei` for every module
   (`-Dermine.useInterface=true` load): list the residual constraints each helper publishes.
G5 Report: the file table (module, subject, fields per fact row, helpers used, shapes exercised, check time),
   the helper signatures verbatim with residuals, the gates, the census table, renderings, the wiring lines,
   and — precisely — what you could NOT express in Ermine and why (a language limit hit while writing a helper
   is a finding worth recording exactly). Add a status row for your stage to `tracker/LOOP-MODEL-PLAN.md`
   (append after the E1 row; do not edit other rows). A reviewer re-runs everything and judges the examples as
   programs a user would learn from.

Outcomes: (GREEN) everything loads, differential clean, census reported; (RED) something does not load or the
model disagrees — report, do not paper over. No silent weakening; report early and keep it current.
