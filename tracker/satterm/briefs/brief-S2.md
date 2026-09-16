# brief-S2 — the fix (Opus implementer, 5 h; needs S0 + a reviewed S1 theorem)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s2`, branch `subsume-s2` (off `subsume-termination`, which
carries the landed S0 instrumentation and the reviewed S1 Lean). Read `brief-S-common.md`, Part B of the prompt,
then `tracker/satterm/SUBSUME-STAGE0.md` (+ `-REVIEW`), and whichever of `SUBSUME-STAGE1A.md` /
`SUBSUME-STAGE1B.md` (+ `-REVIEW`) is marked as the LICENSING theorem in the "Licence" section below. Report:
`tracker/satterm/SUBSUME-STAGE2.md`.

## Licence (filled in by the orchestrator from the reviewed S1 result)

<!-- ORCHESTRATOR: one of the two paragraphs below stays; name the theorem(s), the file, and the reviewer's
     verdict line. -->

- (A) S1 gives TERMINATION UNDER AN INVARIANT the solver keeps, plus an EQUIVALENCE theorem for the restricted
  walk: theorem(s) `<name>` in `tracker/lean/Rowpartition/<file>.lean`, review `<path>` verdict `<LAND>`.
  You implement the cheaper / memoised escape check at `Subst.scala:648` keeping the verdict BY CONSTRUCTION —
  the equivalence theorem names what may change: nothing observable. The shape it licenses: `<orchestrator
  fills: e.g. restrict the walk to the kinds of sks/sts and the types they occur in; memoise per object
  identity; or a fast path when skss/stss are empty>`.
- (B) S1 gives a REACHABLE VIOLATION (a cyclic binding / an invariant the solver does not keep): witness
  `<name>` in `<file>`, review `<path>`. You fix the BINDING SITE with the theorem's invariant (an occurs check
  or the guard the theorem names) and nothing else; `:648` is left alone.

## What you build

1. The fix, behind a flag `-Dermine.subsumeEscape=<mode>` (default = the SHIPPED behaviour; the new mode selected
   by the flag), read once into a `val` like `RowTrace.enabled`; one-paragraph comment at the site naming the
   theorem that licenses it. Nothing else in `Subst.scala` changes. No new dependency.
2. Pins in `scalacheck-binding/src/main/scala/` (a new `TestSubsumeEscape.scala`, or in `TestDateAndScan.scala`
   next to B1 — say which and why):
   - the B1 program, REJECTED, on a deadline thread that FAILS rather than hangs (the `(iso)` idiom:
     `TestRunner.scala:925-947` on branch `json-encode`, worktree `ermine-scala-wt-json` — a daemon thread joined
     with a deadline, `AtomicReference` for the answer);
   - a GENERATOR of unsatisfiable row programs: random `field`s, a relation missing a random NON-EMPTY subset of
     them, a `combine_Op`/`col_Op` chain over the missing ones, source built the way `TestSchema.shape` does it
     (`scalacheck-binding/src/main/scala/TestSchema.scala` on `json-encode`); each case on a deadline thread,
     required to be REJECTED, never a hang, never an acceptance;
   - the POSITIVE twins (the same programs with the relation carrying every field) required to CHECK;
   - each pin run with the flag ON; and one run with the flag OFF that shows the deadline failing on B1 (skip it
     under a system property so the shipped suite stays green — document the property).
3. Gates, yourself: Tier 0 (compile+copyResources, `TestLoopTrace`, `corpus-run.sh --batch` verdicts against S0's
   baseline listing byte for byte, `repl-smoke.sh`, `lsp-smoke.sh`) and Tier 1 (this touches `Subst.scala`):
   `looptrace-corpus.sh` 18-group differential with `LOOPTRACE_PAR` using the existing looptrace binary,
   `trace-ab.py` (all record kinds) flag ON vs OFF, `ei-diff.sh --batch` with `-Dermine.loadInSeries=true` both
   sides, `g1-validate.sh`. Then the B1 property alone THREE times with the flag ON (each under a deadline) and
   the pin suite. Everything harness-tracked in the background with logs under
   `/home/dmitry/research/ermine/scratch-subsume/s2/`.
4. The perf figure the adoption will need (NOT a gate here, one measurement): the wall clock of a stdlib boot
   with the flag ON vs OFF, twice each, interleaved, load < 1.3 — `:648` runs on every explicit-signature check.

## If the fix is not available

If BOTH S1 lanes came back negative, or the upstream fix is out of reach (say exactly why: which theorem, which
site, what it would take), say so plainly in the report with the theorem names and STOP; S3 follows. Do not
build a budget in this stage.

## Deliverables

`SUBSUME-STAGE2.md` per the common brief: what changed and the theorem it rests on, the pins and their counts,
every gate number with its log, the corpus verdict comparison, the perf figure, the flag and its default (OFF =
shipped behaviour), and the stage's yes / no / bounded answer. List every changed file. No commits.
