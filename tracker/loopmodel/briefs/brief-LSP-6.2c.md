# Brief: LSP interstage item 6.2c — E14, the local head that hovers a type the checker did not settle (Tier 1 if `Subst.scala` changes; Tier 2 owed at the commit because shipped hover answers change)

You are the implementer for item 6.2c in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`,
HEAD `336b5204`: interstage item 6.2b shipped — the pattern-binder hook is ON in the editor). Item of record:
`tracker/LSP-ROADMAP.md` § "Interstage item 6.2c"; ticket `tracker/TICKET-stdlib-findings.md` E14; the 6.2b
report `tracker/loopmodel/LSP-6.2b-HOOK.md` §5 (the 14 split-vs-hook disagreements, class 3) and its review
`tracker/loopmodel/LSP-6.2b-REVIEW.md` §3 ("THE `LetAndPatternMatching.e` PAIR IS A CORRECTNESS HOLE") and §8 R-8;
the 6.2 report `tracker/loopmodel/LSP3-6.2-LOCALS.md` (the arity split, `headType`, Decision (a)); the gate policy
`tracker/GATE-POLICY.md` — its **Parallelism rules** (2026-09-11) are the rule of record: DEFAULT IS PARALLEL, and the
only things that run alone, after everything else of yours has exited, each waiting for load < 1.3 and saying so, are
timings written into a tracker. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`core/clean core/compile core/copyResources` if the E046 cyclic-reference quirk bites). No commits. Do not
touch `tracker/lean/`. Delete every `.ei` you cause (`find . -name '*.ei' -not -path './tracker/g1-*'`). No lingering
polling shells: never wait on `pgrep -f '<name>'` from a shell whose own command line contains `<name>` — poll a results
count or use a self-excluding pattern (`[l]ooptrace`). Files under `core/` and `scalacheck-binding/` touched by 6.2b are
LF; preserve whatever each file has (`file` before and after); `git diff --stat --histogram` must equal
`--histogram -w`. Wall-clock budget: 4 hours; at the budget, write up and stop. Report:
`tracker/loopmodel/LSP-6.2c-HEADS.md`. Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.2c/`.

Baselines on this tree (all must hold at the end): core/test 1063 (+ whatever you add); TestTolerantCheck 51 (+ yours);
TestLoopTrace 720/720; corpus `corpus-run.sh --batch <outdir>` 89 LOADED / 79 REJECTED / 0 UNKNOWN of 168 with verdicts
identical to a pre-change run; 274 interfaces, 0 differ; g1-validate 9/9 EQUIVALENT; repl-smoke 8 groups, goldens
untouched; lsp-smoke 565 (+ yours); boot 129.

## The defect, as observed (do not take the mechanism from anyone — measure it)

`core/examples/guide/LetAndPatternMatching.e`:

```
product xs =
  let go []     acc = acc
      go (h::t) acc = go t (h * acc)
  in go xs 1
```

The editor hovers `go : List a -> a -> a` and `acc : a` (6.2's head hover and its arity split) beside `h : Int`,
`t : List Int` (the 6.2b hook) and `xs : List Int`. Facts established by the orchestrator, with the commands:

1. `:type (*)` in the REPL is `forall n. Num n => n -> n -> n`. The local is CONSTRAINED.
2. `:type (xs -> let { go [] acc = acc ; go (h::t) acc = go t (h * acc) } in go xs 1)` is `List Int -> Int`;
   `... in (go xs 1, go xs 1.5)` FAILS ("failed to unify type Int with type Double"); `... in go` is
   `forall a b. Num b => a -> List b -> b -> b`. So the local is not used polymorphically in the body; whatever the
   let-group generalisation did with the `Num` variable, the checker's END state for this component has the binder's
   variable at `Int` (the hook's `acc : Int` and `xs : List Int` both say so) and the head hover does not.
3. The head path is NOT generally stale. Hover probe (`<scratch>/e14/Heads.e`, `<scratch>/e14/probe.py`, run as
   `python3 probe.py java -Dermine.lsp.log=... -cp "$(cat tracker/repl-classpath.txt)" com.clarifi.reporting.ermine.lsp.Main`):
   `pairUp y = let g x = (x, y) in (g 1, y + 1)` hovers `g : a -> (a, Int)` — a head mentioning a variable fixed AFTER the
   let renders the settled type; `later y = let z = y in (z, y && True)` hovers `z : Bool`. Only the constrained shape
   misrenders. Copy that fixture, fix its `import` line if needed (it wants `import Prelude hiding product` + `import Int`;
   `map` needs `import List`), and extend it.
4. Where the head's type comes from: `TolerantCheck.collectLocals.headType` = `Subst.substType(i.v.extract)` for an
   implicit local — the binding's OWN `V`'s annotation meta, zonked at collect time (after the component). The let
   group's generalisation (`Subst.inferImplicitBindingTypes`, the `generalize(omg, csp, substType(t).forget, publishing)`
   at the end, `publishing = false` for a local group) returns NEW `V`s carrying the scheme (`b.v.as(...)`, the `m` map
   the `Let` case substitutes into the BODY with `subTerm(m, body)`); the head hover never reads those. Before that,
   `subsumeType(tp, rp)` binds the old `V`'s meta to `rp`, the `unbind`-instance of the raw inferred type, and
   `restrictTypes(tts)` follows. Somewhere in there is why the head renders a scheme-shaped type with a variable the
   checker later fixed. FIND IT FIRST with a probe (a scratch `runMain` under `scalacheck-binding/src/main/scala/`, like
   6.2b's `Probe62b.scala` — source saved at `<scratch>/6.2b/Probe62b.scala`; delete yours before the gates): for the
   E14 component, print the head `V`'s meta, what `hm.types` binds it to at the end, the scheme the group published for
   `go` (constraints included), what the hook recorded for `acc`, and whether the head meta or the scheme's variables
   were ever passed to `restrictTypes`. State the mechanism in one paragraph with the line numbers. The fix follows from
   it; a fix written before this paragraph is not accepted.

## What "fixed" means (acceptance)

- **A local head hovers the type the checker settled for it, up to renaming, constraints included.** For E14 that is
  whichever of these the probe shows the checker holds at the end of the component: the generalised scheme
  (`forall b. Num b => List b -> b -> b` — then render it WITH its constraint, the way a top-level constrained binding's
  hover renders its `published` scheme; check how `Definitions.scala` prints a top-level `mul a b = a * b`), or the
  settled monotype (`List Int -> Int -> Int`). It is NOT acceptable to keep `List a -> a -> a` and only change what the
  split hands out; the head is the defect and the argument follows from it (Decision (a): a head's argument letters
  agree with the head's own hover).
- **The split inherits.** `acc` renders from the corrected head; if the head is a constrained scheme, `acc : b`
  beside `h : Int` is then two frames of one truth and must be explained in the hover text or the docs — say which and
  why; if the head is the monotype, `acc : Int`.
- **Heads are cross-checked at corpus scale, the way equation arguments are.** Extend the 6.2b agreement machinery:
  record what the checker settled for every implicit local head (the eager path — the same `binderTypes` map or a
  sibling keyed by the head `V`'s def-site, written where the checker finalises the binding's type, behind the same
  `recordBinders` flag, OFF on every strict path) and compare it with what `headType` renders, for every `let`/`where`
  head in the 253 clean corpus modules. Print the count and the def-sites. The property asserts the disagreement SET
  (not a count — review R-4), and anti-vacuity (heads compared ≥ 200). If the set is non-empty after your fix, every
  member is classified with the def-site read at source and a one-line reason, and the classification says whether it
  is a further defect (ticket) or a legitimate second frame.
- **The 6.2b disagreement set moves by exactly what you explain.** `TestTolerantCheck`'s `knownDisagreements` (14
  def-sites) loses `LetAndPatternMatching.e:8:17` and `:9:17` if the split now agrees with the hook there, or keeps
  them with the reason stated in the property's comment if the head is a constrained scheme and the hook is its
  instance. Any OTHER movement of that set is a finding you report, not a pin you adjust silently.
- **Pins.** A `TestTolerantCheck` property on a fixture with the E14 shape (constrained local, defaulted at the top)
  asserting the head's rendered string and `acc`'s, plus the two control shapes from fact 3 (unchanged renderings);
  `tracker/lsp-tests/Locals.e` (or a new fixture beside it — adding an import to `Locals.e` moves every 6.2 pin) hovered
  through the real server in `tracker/tools/lsp-client.py`: head at def and at a use, `acc` at def; lsp-smoke grows.
- **Decision (a) holds:** an EXPLICIT (signed) local head still shows its declaration verbatim — add that to the
  fixture as a control.
- **The strict path observes nothing.** Every new line in `Subst.scala` is behind `hm.recordBinders`. Tier 1 proves it.

## Gates

Tier 0 (parallel where independent): compile + copyResources; `TestLoopTrace` 720/720; `TestTolerantCheck` (51 + yours)
with the sweep lines quoted; `corpus-run.sh --batch <outdir>` both sides — a pre-change build in a worktree
(`git worktree add ../ermine-scala-wt-62c 336b5204`, compile it, regenerate ITS `tracker/repl-classpath.txt` and
`target/ermine-classpath` per GATE-POLICY's worktree note; leave the worktree in place for the reviewer) — verdicts
89/79/0 of 168 identical (the `.out` text is NOT byte-identical across runs: batch-loader nondeterminism, 6.2b review
§1.2; compare verdicts, not bytes); `repl-smoke.sh` 8 groups, goldens untouched (`git status`); `lsp-smoke.sh`
565 + yours; boot 129; `.ei` 0; diff-stat parity; line endings.

Tier 1, if `Subst.scala` changed (it will if the record lives there), both sides in parallel: `LOOPTRACE_PAR=3
tracker/tools/looptrace-corpus.sh` (before in the worktree with `LOOPTRACE_BIN` pointing at the main tree's
`tracker/lean/.lake/build/bin/looptrace`; after in the main tree) + `trace-ab.py` per group, all record kinds, after
rewriting the worktree path in the before traces (only the `loc` column carries it — say you checked); expect 18 groups
IDENTICAL, sinmoved 0, 3 210 881 segments. `ei-diff.sh --snapshot --batch` with `-Dermine.loadInSeries=true` both sides +
`ei-classify.py`: `274 interfaces captured` on BOTH sides (a side that captured fewer lost chunks to timeouts and is
re-run, not reported) and 0 differ. `g1-validate.sh` 9/9.

A/Bs, ALONE, last, load < 1.3 per round: `perf-bench.sh batch -n 3`, two interleaved rounds (expect inside the ~1 %
floor: the strict path pays one boolean test per new site); `perf-bench.sh editor -k 15` (debounce pinned 300), four
interleaved rounds, both round trip and typecheck segment, against 6.2b's after-side figures (reviewer: round trip
0.913 s, typecheck 0.530 s) — this item adds a per-head record and a comparison, which must cost less than the noise
you measure; report all four measures the 6.2b way.

Tier 2 is the REVIEWER's (full `core/test` alone, expect 1063 + yours).

## Report `tracker/loopmodel/LSP-6.2c-HEADS.md`

Outcome first (DONE / PARTIAL with the residual named). Then: the mechanism paragraph with line numbers and the probe
output that proves it; what you changed and why that site; the head agreement sweep before and after (count, set,
classifications); the 6.2b disagreement set before and after; the E14 hover before and after (real server, quoted);
every gate with its figure and log path; the A/B tables; files changed with `--numstat`; follow-ups you found and did
not take. Every number in the report must come from a command whose output is in a log you name. No praise.
