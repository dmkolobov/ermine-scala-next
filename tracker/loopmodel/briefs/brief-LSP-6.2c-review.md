# Review brief: LSP interstage item 6.2c — E14, the constrained local head (Tier 1; Tier 2 owed: shipped hover answers change)

You are reviewing item 6.2c in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `b0eee247`,
code identical to `336b5204`; plus the UNCOMMITTED deliverables: `core/.../ermine/Subst.scala` (45/5),
`core/.../lsp/Resident.scala` (13/2), `core/.../session/TolerantCheck.scala` (153/9),
`scalacheck-binding/src/main/scala/TestTolerantCheck.scala` (161/2), `tracker/tools/lsp-client.py` (44/3), NEW fixture
`tracker/lsp-tests/Heads.e`, report `tracker/loopmodel/LSP-6.2c-HEADS.md`, outcome DONE). Implementer's brief
`tracker/loopmodel/briefs/brief-LSP-6.2c.md`; item of record `tracker/LSP-ROADMAP.md` § "Interstage item 6.2c"; ticket
E14 in `tracker/TICKET-stdlib-findings.md`; the 6.2b report/review (`LSP-6.2b-HOOK.md`, `LSP-6.2b-REVIEW.md`) for the
hook, the 14-site disagreement SET and R-4/R-8/R-9; the 6.2 report `LSP3-6.2-LOCALS.md` for `headType`, the arity split
and Decision (a); Stage-4 item 7.2 (`LSP4-7.2-ANCHORS.md`) for the cache-invisibility property ("warm == cold, positions
included") this item touched; `tracker/GATE-POLICY.md` — its **Parallelism rules** are the rule of record (default
parallel; only timings and the full `core/test` run alone, at load < 1.3, saying so). You edit NOTHING except a scratch
directory `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.2c/`
and your report `tracker/loopmodel/LSP-6.2c-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile core/copyResources` if the E046 quirk bites). No commits, no `git stash` (copy a file
to instrument it, restore by copy, verify by md5). Do not touch `tracker/lean/`. Delete every `.ei` you cause. No lingering
polling shells (never `pgrep -f '<name>'` from a shell whose command line contains `<name>`). The before build is READY at
`/home/dmitry/research/ermine/ermine-scala-wt-62c` (worktree at `336b5204`, compiled, its own `tracker/repl-classpath.txt`
and `target/ermine-classpath` regenerated — the modified `repl-classpath.txt` there is deliberate; do not revert or commit
it). The implementer's logs are under `<scratch>/6.2c/logs/` (cite what you reuse). Wall-clock budget 3.5 hours.

1. **THE MECHANISM — verify the paragraph.** The report says: the head's Lower meta is bound by `subsumeType(tp, rp)` to
   the pre-generalisation rho; `generalize` rewrites only the scheme (and `binderTypes`), never `hm.types`; the scheme
   reaches only the body through the `b.v -> b.v.as(scheme)` map; `restrictTypes` is NOT involved (`tts` empty). Reproduce
   the probe once from `<scratch>/6.2c/` (add the saved probe source under `scalacheck-binding/src/main/scala/` for the
   run and DELETE it after): the `P62C infer`/`P62C publish` lines for `go`. Confirm `metaInTypes=true` and `tts` empty.
   Then the question the report does not ask: could the head's meta have been bound to the SCHEME instead (i.e. is a
   second map the only fix, or was there a one-line alternative — bind/`as` the head `V` itself), and if the alternative
   exists why is the record better? Say which; do not change the code.
2. **THE RECORD — attack it.** `SubstEnv.headTypes`, written at the `generalize` in `inferImplicitBindingTypes` under
   `hm.recordBinders`, eagerly substituted at `instantiateType` ONLY. (a) Every executable added line in `Subst.scala` is
   behind the flag — grep and list them. (b) "Never at `unbind`/`generalize`, which would drag a Bound-var scheme into an
   instance": construct the case that would break if it WERE rewritten there and the case that breaks if a FREE meta in
   a recorded scheme (`let g x = (x, y)` publishes `forall a. a -> (a, b)` before `b := Int`) were NOT rewritten at
   `instantiateType`; both must be covered by a pin — name it or report the gap. (c) `where`-bound heads, nested lets
   (a let inside a let's body and inside a let's binding), mutually recursive local groups, a local group with one
   signed and one unsigned binding: does each head get exactly one record at its def-site, and does the signed one still
   show its declaration verbatim (Decision (a))? (d) Is a head's key `(line, column)` ever shared with a pattern binder's
   (`binderTypes`) — same def-site, two maps — and which wins in `collectLocals`? (e) `Resident.scala` changed 13/2: what
   for, and does fast mode still answer null for heads? (f) The dead-component pin: a component that dies must leave no
   head records in `Result.locals`.
3. **THE TWO DISPLAY RULES — this is where the review earns its keep.** The head now renders the PUBLISHED scheme with
   two transformations: (i) "a constraint quantifying its own existentials is elided", and (ii) quantifier binders are
   re-ordered by first occurrence. Read the code for (i) and state its exact predicate. Attack it: build a local whose
   scheme carries a row constraint that mentions a QUANTIFIED type variable the user needs to see (a `where`-bound
   `f r = r.x + 1` shape, a `{..r}` shape, a derived-column shape) — is anything a user needs elided? Is the predicate
   the same one the `.ei` writer uses (the report says the `.ei` "drops them too" — name the code that does, and say
   whether the two predicates are shared or merely similar; similar-not-shared is a finding)? For (ii): alpha-renaming
   only? Construct a scheme where first-occurrence reordering changes the printed letters of a TOP-level hover vs a
   local hover for the same type and say whether that matters (Decision (a) wants a binding's arguments to agree with
   its head's letters — check `acc : a` under `go : forall a. Num a => List a -> a -> a` and the split's letters
   generally). Then the flicker: the report says 21 local sites in 6 modules flickered between two warm checks before
   rule (i), 12 not alpha-equal, and 7.2's "render a LOCAL differently on two COLD checks" counter went 8 → 0. Reproduce
   the 0 (run the 7.2 property + the implementer's warm probe) and SAY whether rule (i) fixes the flicker or hides it: is
   the elided block the nondeterministic part, and is any non-elided part still order-sensitive?
4. **THE E14 HOVER and the two frames.** Real server (`tracker/tools/lsp-client.py` or the 6.2b review's `hover-probe.py`
   pattern in `<scratch>/review-6.2b/`), `core/examples/guide/LetAndPatternMatching.e` and `tracker/lsp-tests/Heads.e`:
   `go : forall a. Num a => List a -> a -> a` at def and use, `acc : a` (split, the scheme's frame), `h : Int`,
   `t : List Int` (hook, the instance frame). The brief required that these two frames be "explained in the hover text
   or the docs — say which and why". `docs/lsp.md` is NOT in the changed-files list. Check the hover text; if neither
   carries the explanation, that is a finding (R-item) — the fix is a paragraph in `docs/lsp.md`'s local-hover section
   (and, if the implementer proposes it, a one-line note in the hover). Also: every local head now renders with an
   explicit `forall` (two existing pins moved: `idy`/`pl` `a -> a` → `forall a. a -> a`). Confirm that is the TOP-level
   convention (hover `Heads2.mul`/a stdlib binding) so locals now read like top-level ones, and that a MONOMORPHIC local
   (`z : Bool`) still renders without a quantifier.
5. **THE HEAD AGREEMENT SWEEP.** `### 6.2c heads: agreed 231, disagreed 8, requantified 94, constraint elided 57`, SET
   pinned, anti-vacuity ≥ 200. What exactly is compared — the OLD `headType` (meta zonk) against the new record? After
   the fix the head hover READS the record, so state what a disagreement means now (a drift alarm on the meta-vs-scheme
   gap, not a hover defect) and whether the property can go vacuous (if the meta read is removed later, does the pin
   still test anything?). Re-run `*TestTolerantCheck` (55 properties) and quote both sweep lines. Read the 8 def-sites
   at source; confirm each is "a constraint the rho could not carry" and that all 8 now hover WITH the constraint. The
   14-site 6.2b set is reported UNCHANGED with `agreed` 2869 — confirm, and confirm the property comment explains why
   E14's two sites stay (scheme frame vs instance frame).
6. **E15 — the hook's frame drag — confirm it exists and size it.** The report says `generalize` moves a pattern binder's
   record to the scheme's Bound var and `unbind` then drags it to the FIRST instantiation in the body, so `h : Int` is
   "the first use's instance". Build the witness: a generalised local used at two types in its body
   (`let k x = x in (k 1, k True)`) — hover `x`. If it shows `Int` (or `Bool`) rather than `a`, E15 is real and the
   ticket text must say "first instantiation wins", with the witness. If it shows `a`, the report's explanation is wrong
   and the 14-site persistence needs another reason. Either way do not fix it.
7. **TIER 1 — RE-RUN ONCE, in parallel.** `LOOPTRACE_PAR=3 tracker/tools/looptrace-corpus.sh` both sides (before in the
   worktree with `LOOPTRACE_BIN` pointing at the main tree's `tracker/lean/.lake/build/bin/looptrace`), `trace-ab.py`
   per group ALL record kinds after rewriting the worktree path (verify it occurs only in the `loc` column): expect 18
   IDENTICAL, sinmoved 0, 3 210 881 segments. `ei-diff.sh --snapshot --batch` `-Dermine.loadInSeries=true` both sides +
   `ei-classify.py`: `274 captured` BOTH sides, 0 differ. `g1-validate.sh` 9/9 EQUIVALENT.
8. **THE A/Bs — re-measure the editor.** Implementer: batch −0.18 %; editor round trip 0.9095 → 0.9205 s (+1.2 %),
   typecheck 0.5375 → 0.5425 s (+0.9 %), "within noise, not demonstrably zero", high in 3 of 4 rounds. Run FOUR
   interleaved editor rounds yourself (`perf-bench.sh editor -k 15`, debounce pinned 300, alone, load < 1.3, each side
   from its own tree) and report all four measures beside the implementer's; if your after side is also high in ≥ 3 of
   4 rounds, attribute once with a scratch instrumented build (restored by copy + md5): time in the `headTypes` rewrite
   at `instantiateType`, in the head comparison, in the two display rules. Batch: two interleaved rounds.
9. **TIER 0 — RE-RUN ONCE** (parallel where independent): compile + copyResources; `TestLoopTrace` 720/720; targeted
   suites; `corpus-run.sh --batch <outdir>` both sides, VERDICTS identical 89/79/0 of 168 (bytes are not comparable:
   batch-loader nondeterminism, 6.2b review §1.2); `repl-smoke.sh` 8 groups, goldens clean; `lsp-smoke.sh` 573 (list the
   8 new checks and the two moved pins); boot 129; `.ei` 0; `git diff --stat --histogram` == `--histogram -w`; line
   endings preserved (`file` on each touched file).
10. **TIER 2 — full `core/test` ALONE, once, last**: expect 1067 (1063 + 4), 0 failed, 0 errors. E12/E13 get ONE re-run
    of the failing suite alone; anything else red is a finding. Record the wall time.
11. **REPORT** `tracker/loopmodel/LSP-6.2c-REVIEW.md`: verdict first (ACCEPT / ACCEPT WITH FIXES with numbered R-items,
    file:line, one-line change / REJECT); what you refuted with command and output; every gate with figure and log path;
    the display-rule analysis (§3) written so the user can judge whether eliding row residuals from local hovers is the
    right call; the E15 witness; the follow-ups you confirm as real; a NOT CHECKED list. When done: no JVM of yours, no
    `.ei`, no probe source in the tree, the worktree untouched apart from its `repl-classpath.txt`, and `git status
    --short` showing exactly the implementer's files plus your report.
