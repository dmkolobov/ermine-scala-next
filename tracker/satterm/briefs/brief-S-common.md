# Common brief — `subsume-termination` programme (every agent reads this, then Part B of the prompt, then its stage brief)

**Read first, in this order:** `tracker/PROMPT-subsume-termination.md` Part B (the defect, the evidence, H1/H2/H3,
the rules), `tracker/GATE-POLICY.md` (tiers, parallelism rules), `tracker/satterm/SUBSUME-PLAN.md`, then your
stage brief. For Lean stages also `tracker/lean/README.md` (the per-theorem authority; verify, don't trust) and
`tracker/loopmodel/L1-MODEL.md`.

## Where you work

- Your worktree is named in your stage brief (`~/research/ermine/ermine-scala-wt-subsume-<stage>`, branch
  `subsume-<stage>`). Work ONLY there. Do not touch the main checkout, other worktrees, or `~/research/leanwork`.
- **Do not commit. Never push.** The orchestrator commits. Leave your changes in the working tree and list every
  changed/created path in your report.
- Scratch: `/home/dmitry/research/ermine/scratch-subsume/<stage>/` (create it). Logs, traces, jstack dumps, probe
  modules go there. Gzip traces; a diverging `-Dermine.rowTrace` run writes ~8 MB/s. Disk is tight (13 G free).
- Delete every `.ei` you cause under `core/examples` and `core/src/main/resources` when a gate is done
  (`find core -name '*.ei' -newer <marker> -delete` style; the `-Dermine.useInterface=false` runs write none).

## Toolchain

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH   # JDK 21 + sbt
export PATH=$HOME/.elan/bin:$PATH                                                                # Lean (lake, lean)
export ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4"                                      # every bin/ermine
```
- `sbt core/compile core/copyResources` before any `bin/ermine` or gate (compile alone does not copy the stdlib
  `.e` into the target tree). First compile in a fresh worktree takes several minutes.
- In a WORKTREE `tracker/repl-classpath.txt` points at the MAIN checkout's classes; the smoke/g1/perf scripts read
  it. Regenerate it from your worktree's `target/ermine-classpath` (`cp target/ermine-classpath
  tracker/repl-classpath.txt`) and DO NOT report it as a change (the orchestrator will `git checkout` it).
- Test suites: `sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` runs the B1 suite ALONE (the hang);
  several targets in one invocation run in one JVM. `ErmineFixture` (`scalacheck-binding/src/main/scala/TestErmine.scala`)
  gives `typeChecks`/`no(...)`/`session`; `Supply.create` is per thread (`TestErmine.scala:78`).
- Lean: `cd tracker/lean && lake build` (full default target `Rowpartition`), then `lake env lean Audit.lean`
  (prints `Rowpartition theorems audited: N; declarations using a non-standard axiom: 0`), and `#print axioms`
  for every new or changed declaration (put them in a scratch `.lean` you run with `lake env lean`). Your
  worktree's `.lake` is pre-seeded with a full build, so only your new files rebuild. `Audit.lean` loads the whole
  environment (several GB): check `free -g` first and wait if available memory is under 4 G — another lane may be
  auditing. Never `lake build` while a `looptrace` binary is running in YOUR worktree.
- The `looptrace` binary (for `looptrace-corpus.sh`, if a Scala stage needs Tier 1) already exists at
  `~/research/ermine/ermine-scala-wt-json-wrappers/tracker/lean/.lake/build/bin/looptrace`; point
  `-Dermine.looptrace=` / the script's binary variable at it rather than building another.

## Parallelism and long jobs (GATE-POLICY "Parallelism rules")

- DEFAULT IS PARALLEL: other lanes run JVMs and Lean builds on this machine at the same time; tolerate contention.
  Only a timing that goes into a tracker runs alone and says so.
- Long jobs (anything over a couple of minutes): start them as harness-tracked background commands (the Bash
  tool's `run_in_background`) with a log file under your scratch dir, and poll the log. **Never `nohup`, never
  `setsid`**: a detached job never notifies anyone and cost the JSON programme three idle hours.
- `pkill -f <pattern>` matches its own shell; kill by PID. `jcmd <pid> Thread.print` / `jstack <pid>` for samples.

## Rules

- Trace and instrumentation flags DEFAULT OFF (`-Dermine.<name>=true` to enable), read once into a `val` the way
  `RowTrace.enabled` is; no new dependency; no change to shipped behaviour unless your brief says so, and then
  behind a flag default OFF.
- Every claim in your report carries a log path (under scratch) or a theorem name. A "terminates" claim is a
  theorem, not a timing. A "does not terminate" claim is a witness or a measurement with the sample dumps.
- Prefer a proven negative (a witness, a non-existence) over an asserted limitation. When your result contradicts
  a hypothesis in the prompt or in this brief, the document loses — say so plainly.
- Budget: the hours in your stage brief. At the budget, write up what you have and stop.

## Reporting

Your report file already exists (empty) in your worktree at the path your brief names (`tracker/satterm/
SUBSUME-STAGE<n>.md`); overwrite it. Structure: (1) what was measured, with commands and log paths; (2) what was
proved, theorem names and their `#print axioms` output; (3) what was built, every path; (4) gate numbers with log
paths; (5) SEPARATELY and plainly: what the stage says about the title question — *yes* (the check terminates,
and why), *no* (it does not, with the witness), or *bounded* (only under a budget) — and which of H1/H2/H3
survive; (6) open questions and what the next stage needs from you. Finish by returning a short summary of the
same to the orchestrator in your final message.
