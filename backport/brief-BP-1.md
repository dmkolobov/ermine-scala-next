# Brief: BP-1 -- back-port the signature-entailment check to Scala 2.11 (branch backport-2.11)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-backport`, branch `backport-2.11` (HEAD 774daa1). No
commits; never `git stash`; never touch `../ermine-scala` (read-only `git show` of its commits is how you get
the source to port: the landed work is scala3-migration `5162945`). Parallel by default: another agent (BP-2)
is editing `core/src/main/resources/modules/*.e`, `core/examples/shouldfail*/` and `backport/CORRECTIONS.md`
in this SAME worktree -- do not touch those. Budget 6 hours wall clock; write up and stop at the budget.
Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/BP1/`.
All files on this branch are CRLF where they were CRLF: edit byte-wise, and check `git diff` shows no
line-ending churn.

## 0. Toolchain (first; the recipe is `BACKPORT.md` "Building this branch today")
JDK 8 via `~/.local/ermine-toolchain/cs java-home --jvm adoptium:8`; sbt-launch 0.13.5 (download to
`~/.local/ermine-toolchain/bin/sbt-launch-0.13.5.jar` if absent); the repositories file; the `hg` shim; the three
libraries are already in `~/.ivy2/local` (com.clarifi f0, machines, scala-parsers) -- verify, publishLocal
from `~/.local/ermine-toolchain/upstream/` only if missing. WRITE the working pieces INTO THE BRANCH this time:
`backport/env-2.11.sh` (exports JAVA_HOME/PATH, defines `sbt211` = the java -jar command with the -D flags),
`backport/repositories`, `backport/hg` (the shim). `core/target` etc. exist from the 2026-09-09 build; a clean
`sbt211 core/compile` must succeed before you port anything. Record the exact commands in the report.

## 1. The port (from 5162945; `git -C ../ermine-scala show 5162945:<path>`)
- `core/.../ermine/SigEntail.scala` (791 lines, Scala 3): port to 2.11 syntax (no `enum`/`given`/`extension`/
  `then`/quiet syntax; sealed trait + case objects for `Mode`; explicit implicits). Keep names and structure so
  the two files diff cleanly.
- `Constraints.scala`: `LabelSearch` (main :2783-3047) and the `decideLabel` wrapper change (:2746-2781). This
  branch HAS `labelDecide`/`decideLabel`/`propagate` (:2715/:2754/:2815) from the solver back-port, so the
  engine should drop in; diff main's Constraints against this branch's around those lines first.
- `Subst.scala`: `SubstEnv.sigEntail` (:95-102 on main), the call after the partition in `subsumeType`
  (main :549-567; here `subsumeType` is at :527 with the same body -- `:536 entails(qs,r)`, `:553` return),
  the two `Site` allocations at the `ann` and `sig` checks (main :672/:690; here :638/:655 region), and the
  "declared at" = `typ.loc` fix. `:553`'s return stays untouched under every mode.
- `session/SessionState.scala` + `Session.scala`: the per-session mode (main SessionState :109-113/:133-141,
  Session :59-60/:168-177) and `interfaceKey` with the flag APPENDED (here `Session.scala:158`; `:435` uses
  `contains`, same as main). Default `error`.
- `TyLower`/renamer sites do not exist here (fused pipeline): the `ann` site is `Subst.typeCheck`; find how the
  fused parser attaches the annotation's `Loc` so "declared at" points at the signature/annotation, not the
  equation. `TolerantCheck`/lsp do not exist here: nothing to port for the editor.
- The oracle: copy `tracker/tools/sigcheck.py` from 5162945 to `backport/sigcheck.py`.

## 2. Tests (scalacheck-binding; `ErmineFixture` in `TestErmine.scala` -- port the session-option mechanism
main added at `TestErmine.scala:49-70`, never `System.setProperty` a per-call flag)
- `TestSigEntail.scala` from 5162945 (13 properties; the annotation pin uses `Prop.throws` shape).
- `TestSigEntailDiff.scala`: the differential vs `backport/sigcheck.py` over records REGENERATED here (run the
  corpus under `warn` -- this branch's corpus is the 21 files under `core/examples` plus the stdlib boot --
  and commit `core/src/test/resources/sigentail/{records,verdicts}.tsv` for 2.11) and 2,000 random systems.
  Expect fewer signatures than main's 314 (no example corpus here); the engine must agree with the oracle on
  all of them.
- `TestInterfaceKey` is DROPPED on this branch (loader deadlock, BACKPORT.md) -- do not add it; assert the key
  suffix in a one-line property inside `TestSigEntail` instead.
- BP-2 delivers the pins `core/examples/shouldfail/sig01..05` and `control08`; when they exist, run each
  through the 2.11 REPL at the default and record the messages (they are BP-2's headers to fill).

## 3. Gates (with BP-2's corrections in place -- coordinate by checking `git status` for its files;
if they are not in yet when you reach this step, run once without and once with)
`sbt211 core/test` (baseline 713/713 on this branch + the new suites, all green); stdlib boots at the default
(`bin/ermine` equivalent on 2.11 -- BACKPORT.md says how the REPL is run here); every `core/examples/*.e` under
`off` vs `error`: only sig01..05 may differ; `.ei` under `off` byte-identical to HEAD's, under `error` = `off`
modulo the key line and BP-2's corrected contexts. No perf gate; note the boot time (~23 s on this branch).

## 4. Report
`backport/SIG-ENTAIL-2.11.md`: the toolchain commands; the port diff by file with what changed for 2.11; the
differential counts; the corpus and `.ei` results; gate numbers; anything left out and why.
