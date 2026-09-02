# Reproducers for `tracker/TICKET-signature-resolution-fragility.md`

NOT under `core/examples/` on purpose: `TestSurfaceParsers` has a hard-coded corpus
count, and adding a file there breaks it (`ROW-CONSTRAINT-STATE.md`, Traps).

Run one with:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
    rm -f tracker/repro/*.ei
    bin/ermine tracker/repro/MinRepro.e </dev/null >/dev/null
    grep '^derived' tracker/repro/MinRepro.ei

| module | differs by | published type of `derived` |
|---|---|---|
| `MinRepro.e` | nothing downstream uses `derived` | `forall t. (exists so rs a. ..4 constraints..) => Relation t` |
| `MinReproUse.e` | adds `use : [a,b,c,extra]; use = derived` | `Relation (\|b, a, c, extra\|)` |

Both are STABLE under `-Dermine.spliceGuard=true` — the flag does not flip them.
That is the point: they isolate the two published FORMS and show what selects between
them (a downstream use that pins the row), but they do NOT yet reproduce the
FRAGILITY, which is the flag flipping the real modules AGAINST that rule.

## `nameloss/` — the substitution gap is a race on the variable ids

For `tracker/PROMPT-substitution-gap.md` (answered 2026-09-02; the write-up is
`tracker/TICKET-substitution-gap.md`, the proof `tracker/lean/Rowpartition/NameLoss.lean`).
This is a PARTITION-LEVEL reproducer: it calls `Subst.solve` directly on exact constraint
lists with exact variable ids, because the ids -- through the priority-queue key -- are what
decide the outcome, and no `.e` source controls them.

    sbt -batch core/compile                       # once; writes target/ermine-classpath
    tracker/repro/nameloss/run.sh                 # exact HeadcountPlan replays + id sweeps
    tracker/repro/nameloss/run.sh 1 0             # ...and replay the minimal instance at id bases 1 (fails) and 0 (pins)
    ERMINE_JAVA_OPTS="-Dermine.rowTrace=/tmp/tr.tsv" tracker/repro/nameloss/run.sh 1 0  # step traces (`step`/`learn` records)

What it showed on the DELETING solver (the numbers the ticket rests on; under the fixed
solver -- definitions kept, 2026-09-02 -- every row pins, and this script is a regression
check; to see the race again set `val keepDefs = false` in `destructiveSub`):

| input | result |
|---|---|
| regime A's exact 3 partitions, ids 615048.. | `t` pinned to the 9-field row |
| regime B's exact 4 partitions (with the redundant one), ids 506328.. | unpinned |
| B minus either copy of the redundant partition | still unpinned |
| A plus a redundant partition | still pinned |
| A's shape with B's ids / B's shape with A's ids | both unpinned |
| A's shape, 200 contiguous id bases | 103 pin |
| B minus dup, 200 bases | 90 pin |
| A's shape, fixed input ids, only the MINT ids varied | 45 of 50 pin |
| minimal instance `(|k,c|) <- ((|k|),x,y); (|d|) <- (x,z); t <- (x,y,z)`, 200 bases | 90 pin |
| same, but the name `(|c|) <- (x, y)` given as an input | 200 pin |
| anything above with the definitions kept (now unconditional) | everything pins |

The `.e`-level reproducer remains `core/examples/Ai/HeadcountPlan.e` under the two build
orders of the brief (regime A: `Common.e HeadcountPlan.e` on a clean tree; regime B: after
`Accumulate.e`, `Ai/ClinicalTrial.e`, `Ai/IncidentSeverity.e`), which only differ in the ids
`Supply` has reached.
