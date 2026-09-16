# Review brief (any JSON Stage 2/3 stage)

You are the INDEPENDENT reviewer of one stage. You did not write it. Read
`brief-J-common.md`, `tracker/JSON-STAGE3-PLAN.md`, the stage's brief, and the implementer's
report `tracker/json-stage3/report-<id>.md` in the stage worktree. Budget: under 2 h.

## What you review

The UNCOMMITTED diff in the stage worktree against its base
(`git -C <worktree> diff <base>` plus untracked files; the orchestrator names the base).
For J3a also review the contract commit `a7e8e050` (`git show a7e8e050`) -- it lands with J3a.

## What you check

1. Correctness against the plan's wire contract and the stage brief, line by line. Look for:
   mapping mismatches between encoder, schema, decoder, writer and row encoder (Long, Date,
   Timestamp, GUID, Nullable, Maybe-omission, tag rules, column order, `nullable`);
   error paths; resource handling (connections, threads, caches); thread safety where the
   brief asks for it; stack safety on large inputs.
2. The PROPERTIES: are generators actually random over declarations and values, do they
   reach the interesting cases (look at discard counts and shape distributions in the logs),
   can any property pass vacuously? Where you doubt one, mutate the code under test locally
   (break one case), run that suite, confirm it fails, and REVERT the mutation.
3. Dialect: the Scala must compile unchanged on Scala 2.11 (brief-J-common.md list). Grep
   for `given`, `using`, `enum`, `extension`, `export`, `derives`, `.map`/`.flatMap`/`.foreach`/`.getOrElse`/`.toOption` called directly on an `Either` (2.11's Either is not right-biased: only `.right.x`/`.left.x`/`.fold` -- the P1 porter found a `Zod.render(..) foreach` slip the J3a review's grep missed),
   `LazyList`, `CollectionConverters`, Java 9+ APIs (`List.of`, `isBlank`, `readString`,
   `java.net.http`), top-level defs, `?=>`, `*` wildcard imports, `as` import renames.
4. Scope: nothing outside the stage's files changed without a stated reason; no files under
   `core/examples/`; `tracker/repl-classpath.txt` not modified.
5. Docs: the design note / plan updates are accurate and short.

## What you re-run (and what you cite)

RE-RUN once: `sbt -batch core/compile core/copyResources`, the stage's own suites plus
`TestJson TestSchema TestNamedFields` in one sbt invocation, and anything you dispute (plus
the stage's TS checks when there is a `client/` change). CITE the implementer's logs for
TestLoopTrace, the corpus batch, and the smokes; re-run one of them only if the diff could
plausibly affect it. NEVER run the full `core/test` or a whole-corpus per-file sweep.

## Verdict

Write `tracker/json-stage3/review-<id>.md` and end with exactly one of:
- `LAND` -- no changes needed;
- `FIX-THEN-LAND` -- a numbered list of required fixes, each with file:line, the failure
  scenario, and the fix; small enough that the orchestrator or implementer can apply them
  without another full review;
- `REWORK` -- a design-level problem; say what and why.
Separate REQUIRED fixes from optional suggestions. Do not edit the stage's files yourself
except to try and revert a mutation.
