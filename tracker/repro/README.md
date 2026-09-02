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
