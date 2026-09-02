# DONE (2026-09-02): the cumulative default check

Superseded by the **Gates** section of `TICKET-row-solver-8abc.md`, which now carries the
result. Kept only for the correction it produced and the two items still open at the bottom.

## Result

Two 66-file corpus sweeps, one JVM per file, today's defaults against the compiler as it
stood before this line of work (`-Dermine.genRules=all -Dermine.labelCheck=false
-Dermine.resGuard=false` — a configuration that had not been run in this session at all):

    NEW (today's defaults)   23 LOADED, 43 REJECTED, 0 UNKNOWN, 66 total
    OLD (pre-work)           23 LOADED, 43 REJECTED, 0 UNKNOWN, 66 total
    OLD -> NEW               0 of 66 files differ

Every error message byte-identical. The only textual difference anywhere in the 66 pairs is
the boot progress bar's wall-clock timings.

This replaces what had been an inference chained across two sessions on a moving baseline:
`cut` was measured against `all`, `labelCheck` on top of `cut`, `resGuard` on top of both,
and nobody had run the full current stack against the original compiler in one comparison.

## The correction it produced — the reason this file is still here

**This note predicted 15 differing line-pairs. It was wrong, and wrong in an instructive way.**

The prediction was 14 fresh-variable ids (the cut mints fewer, so the `Supply` counter shifts)
plus one field print order. Those 15 came from an **`.ei` diff** and were chained into an
expectation for a **corpus-output diff**. The two instruments do not look at the same surface:

    grep -lE 'forall|rho|<-' cum-new/*.out   ->   0 of 66 files

A module that loads prints exactly one line, `Importing module 'X'`. It never prints a
signature, and `-Dermine.useInterface=false` suppresses the `.ei` where signatures live. **A
corpus sweep is structurally incapable of showing a variable id or a field order.** So 0 was
the correct answer to the question this check actually asks, and 15 was never a prediction
about it.

Generalise: a number is attached to an instrument, not to a compiler. Carrying one across
instruments is the same class of error as the moving baseline this check was built to fix.

## The zero was proved live

Standing rule: a zero is suspect until the instrument is shown capable of a non-zero. Three
times on 2026-09-02 a "0 differ" meant "measured nothing" — once from `.ei` contamination,
once from a missing `PATH`, once from a metric written to the wrong predicate. Positive
control, same normalisation and same classifier, on four modules `labelCheck` is known to flip:

    VERDICT LOADED -> REJECTED   unsound01_keyed_halves.e      24 differing lines
    VERDICT LOADED -> REJECTED   unsound02_three_way_shard.e   4 of 4 files differ
    VERDICT LOADED -> REJECTED   unsound03_inferred_headers.e
    VERDICT LOADED -> REJECTED   unsound04_dead_helper.e

Two harness facts worth keeping:

* `corpus-verdicts.py` reads a live directory, so the file being written classifies as UNKNOWN
  until its last line lands. A sweep in flight always shows exactly one UNKNOWN, tracking the
  write head. Not a timeout, not a finding.
* `corpus-verdicts.py` compares verdict plus the last error line. The full-text diff is a
  separate step and needs the progress bar normalised, or all 66 pairs differ on timings alone.

## Still open, deliberately

* **The cumulative SIGNATURE comparison.** The row above covers verdicts and messages only.
  `tracker/tools/ei-diff.sh <out> "-Dermine.genRules=all -Dermine.labelCheck=false
  -Dermine.resGuard=false"` is the instrument for the surface it cannot see.
* `tracker/TICKET-signature-resolution-fragility.md` — headline claim RETRACTED the day it was
  written; the deciding experiment (perturb something semantically irrelevant, e.g. reorder two
  independent bindings in `tracker/repro/MinReproUse.e`, and see whether resolution flips) is
  NOT RUN. If it comes back clean, WITHDRAW the ticket rather than downgrade it.
* Follow-up item 1 (blame the call site, not the module header) is what unblocks
  `-Dermine.labelCheckEarly`. Measured 2026-09-02: verdicts identical, `shouldfail` 40/40, all
  26 changed messages get better TEXT, but 11 move blame into the stdlib — 7 to `Constraint.e`,
  3 to `Relation/Row.e`, 1 to `Syntax/Relation.e`. Re-measure rather than inherit those
  figures: they were taken before the two dead flags were removed.
