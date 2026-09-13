# Brief: item E11a — a canonical FORM for published schemes (ADOPTION: batch output changes; Tier 2 + goldens + batch A/B)

You are the implementer for item E11a in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`,
HEAD as of launch — `git log -1`). Item of record: `tracker/LSP-ROADMAP.md` § "Interstage item E11 — canonical
publication"; ticket E11 in `tracker/TICKET-stdlib-findings.md` (read it whole: the repro, the three asks, and the
prohibition "it must NOT be closed by loosening a test to alpha-equivalence — the user sees the rendering"); the design
context `tracker/ROSE-COMPARISON.md` rank 3 (§3, lines ~578-612) and its specification §4 (`Residual`, `REquiv`,
`IsCanonicaliser`, `OrderIndependent`); `tracker/ROW-CONSTRAINT-STATE.md` (`smallcanon`, the A1 movers, the
"complete per-label decision"); the 7.2 review's R-4 (`tracker/loopmodel/LSP4-7.2-REVIEW.md` §R-4, the four renderings);
6.2c's display rules (`TolerantCheck.displayScheme`, `constraintKey`, `varOrder` — the ordering this item moves to
publication); `tracker/GATE-POLICY.md` — Parallelism rules (default parallel; only timings and the full `core/test`
alone, load < 1.3, saying so) and the ADOPTION tier. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile core/copyResources` if the E046 quirk bites). No commits. Do not touch
`tracker/lean/`. Delete every `.ei` you cause (`find . -name '*.ei' -not -path './tracker/g1-*'`; note `core/test`
drops them too). No lingering polling shells (never `pgrep -f '<name>'` from a shell whose command line contains it).
Preserve each file's line endings (`file` before/after); `git diff --stat --histogram` == `--histogram -w`. Wall-clock
budget: 5 hours; at the budget, write up and stop. Report: `tracker/loopmodel/E11a-CANON.md`. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11a/`.

Baselines on this tree: core/test 1067 (+ the 6.2c fix-round pin = 1068 expected; + yours); TestTolerantCheck 56;
TestLoopTrace 720/720; corpus 89/79/0 of 168; 274 interfaces; g1-validate 9/9 EQUIVALENT; repl-smoke 8 groups / 66
checks; lsp-smoke 573; boot 129.

## The defect (E11) and what THIS item takes of it

Four cold checks of an unchanged `core/examples/Present/WriterOutputs.e` in one JVM render `reportFor`'s published
constraint part four ways (7.2 review R-4; repro script saved at `<scratch>/review-7.2/nondet.py` with its `probe.py`
beside it — copy both):

```
0  (exists (b: rho). a <- ((|pTitle, pMinValue, pRegion|), b))
1  (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b))
2  (exists (b: rho) (c: rho). a <- ((|pTitle, pMinValue, pRegion|), c), a <- ((|pRegion, pTitle|), b))
3  (exists (b: rho) (c: rho). a <- ((|pTitle, pMinValue, pRegion|), c), a <- ((|pTitle, pMinValue|), b))
```

TWO causes, and this item takes ONE of them:

* **FORM (this item, E11a):** the printed form of one and the same constraint set depends on ids — label order
  inside a concrete row (0 vs 1: `ConcreteRho.fields` is a `Set[Name]` printed in iteration order), the order of
  constraints in the `Exists`, the order of the existential binders (which is what assigns their letters), and the
  order of the universal binders (`generalize`'s `ts = typeVars(t) -- gs` is a set → id order → `forall b a.`
  vs `forall a b.`). Also the "16 of 249 modules render a published type differently on a reuse with no edit" class.
* **SET (NOT this item — E11b, drafted in the roadmap, not opened):** rounds 0-1 publish one constraint and 2-3
  publish two, the second entailed by the first. That is the solver's order-dependent residual, and removing it
  needs an entailment oracle (ROSE rank 3 pass (ii)). You MEASURE it (below); you do not fix it.

## What to build

1. **Canonical form at publication, in the data, not the printer.** In `Subst.generalize` (the `Forall` it
   returns) when `publishing = true` — the module's top-level group, the ONE place a binding's signature is made —
   apply, after `mkSimplified`: (a) universal binders `nts` ordered by first occurrence in the BODY (then in the
   constraints); (b) constraints ordered by an id-free structural key (6.2c's `constraintKey` is the model: lhs
   position, then concrete labels sorted by name, then rhs variable positions; move/generalise it out of
   `TolerantCheck` into a place both can share — `Type` or `Subst` — and make 6.2c's `displayScheme` USE the shared
   one, so the editor's local heads and the published schemes have one canonical form); (c) existential binders
   ordered by first occurrence in the ordered constraints; (d) each partition's right-hand side ordered: concrete
   row first, then variables by position. The key must not read an id anywhere — grep your key for `.id` and
   justify every hit (a `.id` used only through a position map is fine).
   Then DECIDE, by measurement, whether intermediate (non-publishing) generalisations get the same treatment:
   they are re-instantiated by the inference around them, so their order feeds the solver's queue; try both, and
   report corpus verdicts, the batch A/B and the `TestLoopTrace`/looptrace agreement under each. Default: publishing
   only, unless the measurement says the editor's reuse class needs more.
2. **Row labels print sorted by name.** `Pretty.formatRho`/`ppRho` (and the record form `{...}`): labels in
   name order. This is a PRINTER change and reaches every output (browse, `.ei`, errors, hover, REPL); that is
   intended — say so in the report — and it is why the goldens move (below).
3. **The repro as a test — the FORM half.** A `TestTolerantCheck` (or `TestEditorBuffers`) property: N ≥ 4 cold
   checks of `WriterOutputs.e` in one JVM (didOpen/hover/didClose, or the `Resident` harness the 7.2 sweep uses),
   the rendered published types of `reportFor`, `asDocument`, `writerOutputs` compared AS STRINGS after
   normalising ONLY the residual SET difference that is E11b's (i.e. assert the label order, constraint order and
   letters are identical across rounds, and that the set of constraints differs at most by the E11b class, which
   you name explicitly in the failure message — an assertion that would pass under alpha-equivalence is forbidden by
   the ticket). Plus a corpus property: over the 253 clean modules, two cold checks per module, the count of
   bindings whose published type renders differently — split into FORM (must be 0 after this item) and SET (the
   E11b count, printed and pinned as a ceiling with the def-sites listed). Pre-change numbers first, then post.
4. **Interfaces.** Every published `.ei` moves (order at least). Run `ei-diff.sh --snapshot --batch`
   (`-Dermine.loadInSeries=true` both sides) + `ei-classify.py` against a pre-change build in a worktree
   (`git worktree add ../ermine-scala-wt-e11a <HEAD>`, compile, regenerate its `tracker/repl-classpath.txt` and
   `target/ermine-classpath`; leave it for the reviewer): every binding must classify `identical`, `order-only` or
   `alpha-equivalent` — NOTHING in `concrete->polymorphic`, `polymorphic->concrete` or `other`. Quote the tally.
   Then the STABILITY claim the item is for: two after-side snapshots taken with DIFFERENT id bases (e.g. one
   after a warm-up load of another module, or `-Dermine.loadInSeries=false` vs `true`) must be BYTE-identical for
   every interface whose residual SET does not move (list the exceptions; they are E11b's, and their count is the
   number the roadmap carries).
5. **g1 and goldens (ADOPTION).** `g1-validate.sh`: expect EQUIVALENT (alpha) — if the drift tripwire fires on
   order/alpha only, that is what the normaliser is for; if it fires on anything else, stop and report. REPL goldens
   (`tracker/repl-tests/*.expected`): whichever change, the diff must be label-order / constraint-order / binder-order
   ONLY; re-cut them in the tree with the before/after listed per file in the report, and `TestReplDifferential`
   green. Corpus outputs: verdicts 89/79/0 of 168 identical; diff the `.out` texts after the usual normalisation and
   classify every changed line as order-only.
6. **Traces.** The published order feeds call sites, so the row trace WILL differ from the pre-change run. Run
   `LOOPTRACE_PAR=3 looptrace-corpus.sh` on the AFTER side: every group `rc=0`, `timeouts=0`, `dropped=0`, and the
   Lean model AGREES on every segment (`agree` = `segments`, `skip=0`) — that is the fidelity gate. Run
   `trace-ab.py` against the before traces anyway and REPORT what differs and how much (record kinds, mint counts),
   so the reviewer can see the blast radius; IDENTICAL is not expected and not required. `TestLoopTrace` 720/720.
7. **Performance (ADOPTION).** `perf-bench.sh batch -n 3`, FOUR interleaved rounds, alone, load < 1.3: pooled and
   median-of-medians; the solver's order sensitivity is real (`gu05`, `ROW-CONSTRAINT-STATE.md`), so also report the
   per-file corpus wall times before/after and name any file that moved > 20 %. Editor: two interleaved rounds of
   `perf-bench.sh editor -k 15` (debounce pinned 300), expect within noise.
8. **Tier 0**: compile + copyResources; TestLoopTrace; targeted suites incl. `TestTolerantCheck` (56 + yours; the
   6.2b and 6.2c pinned SETS must not move — if a def-site string changes only because letters were renumbered,
   say so and update the set with the before/after pair listed); corpus; repl-smoke (with re-cut goldens);
   lsp-smoke 573 (+ yours; list moved pins with reasons); boot 129; `.ei` 0; diff parity; line endings.
   Tier 2 (full `core/test` alone, expect 1068 + yours) is the REVIEWER's, but run it yourself once if the goldens
   moved (they will): a red golden is a finding, not a re-cut.

## Report `tracker/loopmodel/E11a-CANON.md`

Outcome first. Then: the canonical form, stated as a rule a reader could apply by hand (with the key); where it
runs and why publishing-only (or not — the measurement); the E11 four renderings before and after (real server,
quoted); the FORM/SET split over the corpus with counts and def-sites; the `ei-classify` tally and the two-base
byte-identity result; g1; every golden that moved with its before/after; the trace blast radius; the A/Bs; files
changed with `--numstat`; follow-ups (E11b's exact target count is the first). Every number from a named log.
