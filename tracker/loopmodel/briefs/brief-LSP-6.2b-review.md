# Review brief: LSP interstage item 6.2b — the pattern-binder hover hook (Tier 1; Tier 2 owed: shipped hover behaviour changes)

You are reviewing item 6.2b in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `2f88b862`
plus the UNCOMMITTED deliverables: `core/.../ermine/Subst.scala` (+33/−0), `core/.../session/TolerantCheck.scala`,
`core/.../lsp/Resident.scala`, `scalacheck-binding/src/main/scala/TestTolerantCheck.scala`, fixtures
`tracker/lsp-tests/Locals.e` and NEW `tracker/lsp-tests/LocalsDo.e`, `tracker/tools/lsp-client.py`, `docs/lsp.md`;
report `tracker/loopmodel/LSP-6.2b-HOOK.md`, outcome PARTIAL). Implementer's brief `tracker/loopmodel/briefs/
brief-LSP-6.2b.md`; item of record `tracker/LSP-ROADMAP.md` § "Interstage item 6.2b"; the 6.2 review
`tracker/loopmodel/LSP3-6.2-REVIEW.md` (R-1 refuted the naive hook; R-5 named the null-pins to flip); the earlier design
`tracker/loopmodel/briefs/brief-LSP4-6.2b-prototype.md`; `tracker/GATE-POLICY.md` (Tier 1 because `Subst.scala` changed;
Tier 2 because the editor's shipped hover answers change; and its **Parallelism rules**, which are the rule of record).
You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.2b/` and your
report `tracker/loopmodel/LSP-6.2b-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile core/copyResources` if the E046 quirk bites). No commits. Do not touch
`tracker/lean/`. Delete every `.ei` you cause (`find . -name '*.ei' -not -path './tracker/g1-*'`). No lingering polling
shells: never wait with `pgrep -f '<script name>'` from a shell whose own command line contains that name (it matches
itself and only exits at the timeout) — poll a results count, or use a self-excluding pattern like `[l]ooptrace`.

**PARALLELISM (GATE-POLICY, 2026-09-11): DEFAULT IS PARALLEL.** Run the identity gates concurrently — the two
looptrace sides, the two `ei-diff` sides, `g1-validate`, the targeted suites — in whatever mix finishes soonest; they
tolerate contention (but a sweep that LOSES CHUNKS to timeouts under load is not a result — the implementer had to
re-run one, §8(b); check `274 interfaces captured` on both sides before classifying). The ONLY things that run alone,
one at a time, after everything else of yours has exited, each round at load < 1.3 (`cat /proc/loadavg`) and saying so:
the two perf A/Bs and the full `core/test`. The user may have an sbt running in another `ermine-scala-wt-*` worktree;
that is fine for identity gates, and for timings you wait for the load figure like everyone else.

**THE BEFORE BUILD IS READY** at `/home/dmitry/research/ermine/ermine-scala-wt-62b` (worktree at `2f88b862`, compiled,
`tracker/repl-classpath.txt` and `target/ermine-classpath` regenerated for that tree — the uncommitted change to
`repl-classpath.txt` there is deliberate; do not revert it, do not commit it). Use it for every before side. Do not
rebuild it unless a gate proves it stale (`git -C ../ermine-scala-wt-62b status --short` should show ONLY
`tracker/repl-classpath.txt`). The implementer's gate logs and both trace sets are under `<scratch>/6.2b/`
(`lt-before/`, `lt-after/`, `trace-ab.log` RAW and `trace-ab2.log` path-normalised, `ei-before/`, `ei-after/`,
`ei-classify.log`, `g1-final.log`, `ab-batch*.log`, `ab-editor*.log`, `tier0-final.log`, `corpus-before/`,
`corpus-final/`, `shape-A-instantiateType.patch`). Cite what you reuse; re-run what the item of record says you re-run.

Wall-clock budget: 3.5 hours. Reaching it, write up what you have and STOP.

1. **THE MECHANISM — read it before you run anything.** `SubstEnv.binderTypes: Map[(Int,Int), Type]` and
   `recordBinders`, written in `inferPatternType`'s `VarP` case and rewritten whole-map at THREE sites beside
   `hm.remembered`: `instantiateType`, `unbind` (`Forall`), `generalize`. (a) Confirm every one of the four is behind
   `hm.recordBinders`, that the flag is set ONLY in `TolerantCheck.checkWith(wantLocals = true)`'s two inference blocks,
   and that no strict entry point (`Session.loadModule`, `readModule`, REPL, `bin/ermine`, the loader, `Resident` fast
   mode, `TolerantCheck.check`) can reach a set flag — grep for every `recordBinders` write. (b) The site audit (§2a):
   eight `hm.remembered =` writes, three mirrored, five per-id `Memory`/`Remember` writes not. Check the five: is there
   ANY path on which a per-id write changes a type that a `binderTypes` entry also mentions, such that the two maps
   drift? (`unifyType`'s `Memory` cases bind metas — those go through `instantiateType`, which IS mirrored; confirm
   that is the whole story.) (c) The `instantiateKind`/`restrictKinds` asymmetry the report names as "harmless because
   the reader zonks through `hm.kinds`": is `TolerantCheck`'s zonk (`Subst.substType`) run BEFORE `restrictKinds` can
   have deleted the kind binding, on every merge path? Build a probe if the argument is not airtight. (d) The
   refutation (§1): reproduce it ONCE with the saved probe source (`<scratch>/6.2b/Probe62b.scala`, add it under
   `scalacheck-binding/src/main/scala/` for the run and DELETE it after) — both builds, the `false &&` toggle at the
   three sites; the naive build must show the bare meta and `hm.types holds it: false`. Do not skip this: it is the
   item's founding claim and the brief demanded it run before the workable shape was built.
2. **THE MERGE AND THE AGREEMENT CHECK — attack them.** `collectLocals.pat`'s new branch: an UNSIGNED `VarP` looks its
   def-site up, zonks, and (i) the split wins where it already recorded that key, the two compared; (ii) otherwise the
   hook's type is recorded unless it is not `mono` (→ `Result.binderRankN`). Attack: (a) `sameUpToVarNaming` /
   `G1Compare.alphaEq` — can it call two DIFFERENT types equal (a false agreement)? Construct one if you can; (b) the
   14 corpus disagreements (§5, three classes) — verify each classification by reading the def-site, and in particular
   the two `LetAndPatternMatching.e` sites where the hook is RIGHT (`Int`) and the shipped split is weaker (`a`): the
   split wins there, so the editor shows the weaker answer; say whether that is acceptable for this item or a
   correctness hole (it was already the shipped 6.2 answer; the question is whether the item should have preferred the
   hook when the split's domain is a bare variable — the implementer's follow-up 1); (c) the ceiling `disagreements <=
   14` — is a pinned ceiling on a drift metric a real test, or would it silently absorb 14 NEW disagreements replacing
   14 old ones? Say what a stronger pin would look like (a set of def-sites, not a count); (d) the rank-N residual: 29
   variables bound to a rank-N constructor field — confirm the sweep asserts the misses are EXACTLY `binderRankN` and
   that `binderRankN` cannot be padded (a hook type that is not `mono` for another reason would hide there); (e) the
   DEAD-COMPONENT pin (`dlam` absent): confirm that a component that dies leaves NO hook entries in `Result.locals`,
   and that a component that succeeds but whose neighbour dies is unaffected; (f) 7.2 anchored positions and the
   fingerprint cache: hook entries are keyed by def-site `(line, column)` from `Lower`'s `Pos` — on a WARM check after
   inserting a line ABOVE the binder, is the hover position shifted correctly (the report claims `warm == cold,
   positions included` over hook entries; reproduce with `lsp-client.py` or `perf-client.py`, not just the unit
   property); (g) a `where`-bound polymorphic local's lambda argument shares the head's letters (§4) — reproduce the
   `topTwo`/`locTwo` probe once; (h) `import Syntax.Do` binders (`LocalsDo.e`) — hover a `do` binder at def and at
   use; (i) fast mode → null for hook binders (two lsp-smoke checks) — confirm.
3. **COVERAGE — reproduce the sweep figure.** 5054/5083 typed after (3079 before), Arg(other) 1776/1804, CaseBound
   116/117, DoBound 31/31, over 253 clean of 257. Run `*TestTolerantCheck` (51 properties) and read the sweep's printed
   line; the numbers must match the report's. Then pick ten binders the hook now types that the split did not (five
   lambda arguments, three `case`, two `do`) and hover them through the real server (`tracker/tools/lsp-client.py`
   against `bin/ermine-lsp` or the smoke harness): def-site AND use-site, rendered strings sane.
4. **TIER 1 — RE-RUN ONCE, in parallel per the rules above.** (a) `LOOPTRACE_PAR=3 tracker/tools/looptrace-corpus.sh`
   both sides (before in the worktree with `LOOPTRACE_BIN` pointing at the main tree's `tracker/lean/.lake/build/bin/
   looptrace`, after in the main tree), then `trace-ab.py` per group, ALL record kinds. THE PATH NORMALISATION: the
   implementer rewrote `ermine-scala-wt-62b` → `ermine-scala` in the before traces because every `loc` carries the
   absolute path. Verify it is the ONLY difference between the raw and normalised before traces (`zcat | diff` on one
   group, or count changed lines == lines containing the path) and that NO OTHER field could contain that substring.
   Expect 18 groups IDENTICAL, `sinmoved 0`, rc 0, 3 159 981 segments. (b) `ei-diff.sh --snapshot --batch` with
   `-Dermine.loadInSeries=true` both sides + `ei-classify.py`: expect `274 interfaces captured` both sides and `0 of 274
   differ`, 3523 identical bindings. (c) `g1-validate.sh` 9/9, EQUIVALENT, no drift.
5. **THE A/Bs — the disputed number is the editor round trip; re-measure it.** Implementer, alone, loads 1.21–1.26,
   `perf-bench.sh editor -k 15` (debounce pinned 300), eight interleaved rounds: round trip 0.9065 → 0.9645 s (+58.0 ms,
   +6.40 %, median of medians; pairwise +48.5 ms / +5.35 %) against the brief's budget of 5 % of the round trip
   (45.3 ms) — OVER; typecheck segment 0.5375 → 0.5725 s (+35.0 ms = +3.86 % of the round trip) — INSIDE; `read` +7.5 ms
   in a phase the flag is armed AFTER. Run at least FOUR interleaved rounds yourself (before = worktree, after = main;
   `perf-bench.sh` reads `tracker/repl-classpath.txt` so run each side from its own tree), report all four measures the
   same way, and say which side of 45.3 ms YOUR round trip lands on. Then ATTRIBUTE, once, with a scratch instrumented
   build you revert afterwards (`git stash` is forbidden — copy the file, edit, restore by copy): count, for one
   Report.e check with the flag on, the `instantiateType` calls with `binderTypes.nonEmpty`, the map size at each, and
   the total time in the three whole-map rewrites. The user has to decide between shipping +35..58 ms and parking the
   item; give them the number that says whether follow-up 2 (a reverse index `TypeVar -> keys`) would recover it. Do
   NOT tune the mechanism yourself. Batch: implementer 4 rounds, −0.12 % pooled / −0.36 % median-of-medians; re-run
   TWO interleaved rounds (`perf-bench.sh batch -n 3`) and report pooled and median-of-medians.
6. **THE BASELINE DISCREPANCY.** The brief said corpus `88/70/0 of 158`; the tree gives `89/79/0 of 168` on BOTH
   builds. `git log --diff-filter=A --format= 775a20f8..HEAD -- core/examples` lists 16 added `.e` files, ten of them
   the LET-1 let-signature examples and controls that landed after the entailment worktree's figure was taken. Confirm
   that `158 + the files corpus-run.sh covers among those additions = 168`, that the +9 REJECTED are the intended
   `shouldfail` cases (`let01..05`, `sig01..05`), and that the +1 LOADED is a control. State the baseline the roadmap
   should carry. This is bookkeeping, but a wrong baseline hides the next regression.
7. **TIER 0 — RE-RUN ONCE** (parallel where independent): compile + copyResources; `TestLoopTrace` 720/720; the targeted
   suites the report lists (157 properties); `corpus-run.sh --batch <outdir>` both sides + byte-identity after removing
   ONLY the checkout path and progress frames (168/168 identical claimed); `repl-smoke.sh` 8 groups, goldens clean
   (`git status` shows no golden); `lsp-smoke.sh` 565 (list the 14 new checks; the two FLIPPED 6.2 pins must be
   `r : Bool`, not null); boot 129 modules; `.ei` by `find` 0; `git diff --stat --histogram` == `--histogram -w`
   (451/92) and every touched file's line endings preserved (`file` on each; the tree is mixed CRLF/LF — a file that
   was CRLF must still be CRLF).
8. **TIER 2 — the full `core/test` ALONE, once, last** (`sbt -batch -J-Xmx3g core/test`; the last landing was
   1061/1061; TestTolerantCheck went 49 → 51 properties, so expect 1063, 0 failed, 0 errors). The documented
   intermittents E12 (`TestInterfaceRoundTrip`, cross-suite depCache race) and E13 (`TestLegend` seed flake) get ONE
   re-run of the failing suite alone; anything else red is a finding. Record the wall time.
9. **REPORT** `tracker/loopmodel/LSP-6.2b-REVIEW.md`: verdict first — ACCEPT / ACCEPT WITH FIXES (list them as
   numbered R-items with file:line and the one-line change) / REJECT; then what you REFUTED in the implementer's report
   with the command and output that refutes it; then every gate you re-ran with its figure and the log path; then the
   editor A/B section written for the user's decision: your round-trip and segment numbers beside the implementer's,
   the attribution, and the exact cost of parking (§10 of the implementer's report: a second `checkWith` parameter or a
   default-off probe, 14 lsp-smoke checks back to null, 1975 binders silent). Say which of the implementer's follow-ups
   1–4 you confirm as real and which are not. No praise, no restating the report; a claim you did not check is listed
   under "NOT CHECKED", not omitted. When done: no JVM of yours running, no `.ei`, no probe source in the tree, the
   worktree untouched apart from its `repl-classpath.txt`, and `git status --short` in the main tree showing exactly the
   implementer's files plus your report.
