# brief-P211 — port the programme's Scala to `backport-2.11`, then merge into `json-encode-2.11` (Opus porter, 4 h; reviewer 1.5 h)

Worktree `~/research/ermine/ermine-scala-wt-backport`, branch `backport-2.11` (tip bec47958 at the time of writing).
Read `backport/BACKPORT.md` (JDK 8 + sbt 0.13 recipe, `backport/env-2.11.sh`), `backport/brief-BP-*.md` and
`backport/CORRECTIONS.md` (how earlier ports were done and reviewed), and on `scala3-migration` (main checkout
`~/research/ermine/ermine-scala`): `tracker/satterm/SUBSUME-PLAN.md` (closing sequence), `SUBSUME-STAGE0.md` §3
(what S0 built), `SUBSUME-STAGE2.md` §3 (what S2 built), and the diffs of the landing commits (`git log
5557ba39..scala3-migration -- core scalacheck-binding tracker/tools`). Report: `backport/SUBSUME-2.11.md`.

## The user's instruction (2026-09-16)

"I would want a similar process for 2.11": port the same changes onto `backport-2.11` by copy in the 2.11-and-3
dialect (the way the JSON stages were ported: Scala 3 first, then 2.11 by copy + hooks), reviewed, full 2.11 test,
then merge `backport-2.11` into `json-encode-2.11` with a full test there. Nothing pushed.

## What to port (and what not)

- **S0 instrumentation** (`Subst.scala` +157/−2: `SubsumeTrace` counters, nanosecond accumulators at the `:365`
  and `:648` equivalents, `inline def` entry points): port with the 2.11 dialect (`inline def` is Scala 3 — use
  a plain `def` guarded by the same `if (!enabled)` first line and note the `Function0` cost is accepted on 2.11,
  or `@inline final def`; say which). Flag `-Dermine.subsumeTrace` default OFF; one flag-OFF run must show zero
  records.
- **S2 harness**: `ErmineFixture.rejects`, `bounded(ms)`, `loadNamed`/`outcomeOf` in `TestErmine.scala`; convert
  every live `no(` site on 2.11 whose body is deterministic (do the census on 2.11 yourself: it has its own set —
  `TestErmine.scala:194-196` and others; keep any `forAll`-bodied site); port `TestRowRefusals.scala`; port the
  `(B1-bound)` pin ONLY if `json-encode-2.11` carries `TestDateAndScan.scala` (backport-2.11 does not; check
  `git cat-file -e json-encode-2.11:scalacheck-binding/src/main/scala/TestDateAndScan.scala`) — if it lives only
  on the JSON 2.11 branch, port that pin in the merge step there, not on backport-2.11.
- **NOT ported**: the LSP smoke case and `lsp-client.py` (no language server on 2.11); the Lean (`tracker/lean` is
  documentation; copy the three new `.lean` files and the README/report/plan docs under `tracker/` verbatim only
  if backport-2.11 carries a `tracker/` tree — check; if it does not, cite the scala3-migration paths in
  `backport/SUBSUME-2.11.md` instead).
- scalacheck 1.11 on 2.11: `Prop.secure` is EAGER (JSON P2 finding) — a lazy `secure` shadow exists in the ported
  suites; `Prop.proved`/`Proof` status exist in 1.11 — verify `rejects` compiles and `OK, proved property` appears.
- The 2.11 worktrees show tracked files under `core/target/` and `backport/.classpath` as modified/deleted in
  `git status` — pre-existing noise; do NOT stage anything under `target/` or `.classpath`. Commit nothing; list the
  explicit path list for the orchestrator's commit (the JSON P3 idiom).

## Gates (2.11, JDK 8 + sbt 0.13 per BACKPORT.md)

Compile; the converted suites alone; `TestRowRefusals` alone; flag-OFF run zero records; full 2.11 `core/test` in
the background (backport-2.11 baseline 735/735 per the sig-entail back-port; json-encode-2.11 858/858 at 2de40034)
with count and wall clock before/after. Then the merge step: in `~/research/ermine/ermine-scala-wt-json211`
(`json-encode-2.11`), `git merge backport-2.11`, resolve conflicts (list them), port the `(B1-bound)` pin if
`TestDateAndScan.scala` is there, lift any `dateDiffReject`-style gate if one was ported to 2.11, full 2.11
`core/test` there. Every number with a log under `~/research/ermine/scratch-subsume/p211/`. No nohup; kill by PID.

## Report

`backport/SUBSUME-2.11.md`: the census of `no(` sites on 2.11 with before/after; each ported file with its
scala3-migration source commit; dialect changes; gates with logs on both branches; the explicit path list to
commit on each branch. The reviewer re-runs the converted suites alone and TestRowRefusals on both branches and
reads the full-run logs.
