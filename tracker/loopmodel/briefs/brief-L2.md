# Brief: L2 — trace equivalence of the Lean loop model against the compiler over the WHOLE corpus

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`; the tree carries
uncommitted work (Stage 7 + L1): `git status` lists it — do not modify those files except where
this brief says (the L1 modules under `tracker/lean/Rowpartition/Loop/` and
`tracker/tools/looptrace-diff.py` are yours to extend; `RowTrace.scala` may gain records as
described below; nothing else). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`);
Scala toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`.

READ FIRST: `tracker/LOOP-MODEL-PLAN.md` (L2's acceptance criteria are the contract),
`tracker/loopmodel/L1-MODEL.md` (the model, its dequeue-order statement §3, the correspondence
table §8, the "not modelled" list §7, the L2 risks §10) and `tracker/loopmodel/L1-REVIEW.md` (the
reviewer's findings; anything it lists as accepted scope stays scope, anything it required fixed is
fixed), then `RowTrace.scala` (record formats), `tracker/tools/keptdef-mints.py` (how a serialized
trace is segmented per `solve` and how `inpart` records are parsed), `tracker/tools/keptdef-sweep.sh`
and `corpus-run.sh --batch` (how to trace the corpus with `-Dermine.loadInSeries=true`), and
`tracker/repro/satterm/SatTermRepro.scala` (how a seed becomes a system at an id base).

## The question
Does the L1 model reproduce the compiler's trace on EVERY solve the compiler performs on real
code — the 110-module example corpus and the 129-module stdlib boot — and on 2,000 random
systems from `rowclosure.py`'s generator? Acceptance: 0 unexplained mismatches, every explained
class either fixed in the model or recorded as a deliberate abstraction with its scope.

## Deliverables

1. **Per-solve inputs from the compiler.** The serialized `rowTrace` already carries `inpart`
   records (input partitions with variable ids and label names) and a `solve` terminator per
   segment. Determine what else the model needs to replay a solve exactly — at least the id
   supply's next value at solve start, the variables' kinds/flavours if they affect hashing or
   dispatch (`Ambiguous(Free)`, skolems), and whatever the label hash needs (the queue order
   depends on `rhs.hashCode`, i.e. on the real hash of label and variable objects; the L1 model
   pinned it for `Repro.lN` labels and integer ids — corpus labels are qualified `Global` names,
   check what their `hashCode` is built from and whether the trace records enough to recompute
   it). If the trace lacks something, ADD a record type to `RowTrace.scala` (inert unless
   `-Dermine.rowTrace` is set, same as the others; document it in the file header), recompile
   ONCE (`sbt -batch core/compile`; one sbt at a time; never during a sweep), and re-trace.
2. **A batch mode for the model**: `lake exe looptrace --replay <trace.tsv>` that reads a
   serialized compiler trace, reconstructs each solve's input from its records, runs the model,
   and emits the model's trace per segment in the same format — one process per corpus file,
   not per solve. Performance is an acknowledged risk (L1 §10: the model is list-based; the
   corpus's largest solve saturates 1,372 partitions): measure first; if a solve takes more than
   a few seconds, improve the model's data structures WITHOUT changing its behaviour — every
   `Conformance.lean` guard must still pass and the L1 sweep (240/240) must still agree — and
   report the before/after.
3. **The corpus sweep** (`tracker/tools/looptrace-corpus.sh`, new): trace the examples
   (`--batch`, `-Dermine.loadInSeries=true`, `-Dermine.useInterface=false`) and the stdlib boot,
   replay every segment through the model, diff per segment with `looptrace-diff.py`, and
   classify: AGREE / mismatch class. Long runs under `setsid nohup` with a log (background
   shells here are capped at ten minutes). Delete `.ei` files under `core/examples` afterwards.
4. **Random systems**: 2,000 seeds from `rowclosure.py`'s generator (read its `--help`; it writes
   the `json:` format), each replayed through the harness at one id base and compared; keep the
   generator's parameters in the report.
5. **Mismatch triage**: for every mismatch class, the FIRST differing record on each side, the
   Scala and Lean code responsible, and the resolution: model fixed (then re-run everything), or
   accepted abstraction (state exactly which solves it affects and why the theorems in L3 do
   not depend on it — e.g. a message text, a post-loop `reduce`, a skolem `die`). "Unexplained"
   is a failure of the stage, not a category.
6. **Report** `tracker/loopmodel/L2-CORPUS.md` (write EARLY, keep current): the counts (segments,
   agree, per-class), the triage table, the performance numbers, the exact commands, and the
   accepted-abstraction list carried forward to L3. Update `tracker/LOOP-MODEL-PLAN.md`'s L2
   status row and `tracker/lean/README.md`'s Loop section (additively).

## Constraints
`lake build Rowpartition` and `lake env lean Audit.lean` green at the end (no non-standard axioms;
no `sorry`/`Classical`/`partial` in `Loop/`); never `lake exe cache get`, no new `require`, no new
Lean project, `CutSearch.lean` stays out of the root import list; disk is tight — gzip traces,
scratch only under `/home/dmitry/.claude/jobs/880c725d/tmp/L2/`; no commits; `pkill -f` matches
itself. Do not claim agreement you did not run.

## Report back
Segment counts and agreement per corpus and for the random systems; the mismatch classes with
their resolutions; the trace-record additions if any; performance before/after; build/audit
figures; files with line counts; anything you could not do, plainly.
