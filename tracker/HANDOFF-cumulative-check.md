# PENDING: the cumulative default check (started 2026-09-02, ~10:30)

Written so this survives a context compaction or the end of the session. Everything
else from this line of work is committed (`637d16f`, `beb3eb3`, `23fd12c`, `f6bb663`,
`cb7fab4`); this is the one measurement still in flight.

## What is running

Two 66-file corpus sweeps, one JVM per file, comparing **today's defaults** against
**the compiler before this line of work began**:

    S=/tmp/claude-1000/-home-dmitry-research-ermine/9284febc-.../scratchpad
    NEW: tracker/tools/corpus-run.sh $S/cum-new
    OLD: ERMINE_JAVA_OPTS="-Dermine.genRules=all -Dermine.labelCheck=false -Dermine.resGuard=false" \
           tracker/tools/corpus-run.sh $S/cum-old

## Why it exists

Each of the three adopted defaults was measured against the config that preceded it —
`cut` against `all`, `labelCheck` on top of `cut`, `resGuard` on top of both. That is
correct practice, but it is a MOVING BASELINE, and nobody had run the full current stack
against the original compiler in one comparison. The cumulative figure was an inference
chained across two sessions, not a measurement. This replaces it.

Note `genRules=all -Dermine.labelCheck=false -Dermine.resGuard=false` over the 66 files
is a configuration that had NOT been run in this session at all — every other sweep here
already had `cut` and `labelCheck` on.

## How to read the result

    python3 tracker/tools/corpus-verdicts.py $S/cum-new | tail -1
    python3 tracker/tools/corpus-verdicts.py $S/cum-old | tail -1
    python3 tracker/tools/corpus-verdicts.py $S/cum-old $S/cum-new | tail -20

Expected, from the previous session's own note plus this session's measurements:
**15 differing line-pairs** attributable to `cut`+`labelCheck` — 14 fresh-variable ids
(the cut mints fewer, so the `Supply` counter shifts) and one field print order on a
provably identical row set — and **0** from `resGuard`. Verdicts should be identical
except the four `Unsound01`-`Unsound04` modules, which `labelCheck` newly REJECTS and
which are in `incomplete/`, not in these 66.

**If it comes back materially different from that, the chained inference was wrong
somewhere and that is the finding.** Do not round it off; write down what moved.

**A zero is suspect until proven.** Three times on 2026-09-02 a "0 differ" meant
"measured nothing" — once from `.ei` contamination, once from a missing `PATH`, once
from a metric written to the wrong predicate. `corpus-verdicts.py` now refuses an
all-UNKNOWN comparison, but check `cum-*/HelloWorld.e.out` actually contains
`Importing module` before believing anything.

## What to do with it

Record the number in `tracker/TICKET-row-solver-8abc.md` under **Gates**, as the
cumulative row, and commit. If it matches expectation that is a one-line addition; if it
does not, it needs its own write-up and probably its own ticket.

## Also left open, deliberately

* `tracker/TICKET-signature-resolution-fragility.md` — headline claim RETRACTED the day
  it was written; the deciding experiment (perturb something semantically irrelevant,
  e.g. reorder two independent bindings in `tracker/repro/MinReproUse.e`, and see whether
  resolution flips) is NOT RUN. If it comes back clean, WITHDRAW the ticket rather than
  downgrade it.
* Follow-up item 1 (blame the call site, not the module header) is what unblocks
  `-Dermine.labelCheckEarly`. Measured today: verdicts identical, `shouldfail` 40/40, all
  26 changed messages get better TEXT, but 11 move blame into the stdlib — 7 to
  `Constraint.e`, 3 to `Relation/Row.e`, 1 to `Syntax/Relation.e`. Re-measure rather than
  inherit those figures: they were taken before the two dead flags were removed.
