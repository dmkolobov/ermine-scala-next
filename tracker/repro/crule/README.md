# `crule/` — the Lean witness W replayed through the shipped `Subst.solve`

**Question.** `tracker/lean/Rowpartition/ResGuardDiverge.lean` proves that the additive rule
set admits derivations of every length from the unsatisfiable four-constraint gadget `gSeed`,
and that the per-label check (`Constraints.labelClash`, run on the INPUT partitions) refutes
`gSeed` itself.  The eight-constraint system W below hides `gSeed` behind two folds, so the
label check provably does NOT refute W as an input, while the additive calculus still derives
`gSeed` from it.  Does the shipped `Constraints.incorporateAll` — a single-pass worklist —
walk into the mint loop (HANG), terminate with an answer (SOLVED), or throw (REJECTED)?

    a  <- (p, (|l1|))          b  <- (q, (|l4|))
    w2 <- (a, s2)              w2 <- (q1, q2, s2, (|l2|))      q <- (q1, q2)
    w3 <- (b, s3)              w3 <- (p1, p2, s3, (|l3|))      p <- (p1, p2)

**Answer (measured 2026-09-02, branch `scala3-migration`, default flags
`genRules=cut+label-early+resguard`).**  W is **REJECTED at every one of 1000 contiguous
id bases** — never a hang, never an acceptance — by `RHS.merge` (`Constraints.scala:341`):

    scalaparsers.Death: Fields appear twice in row: Set(Repro.l1)     (or l2 / l3 / l4)

in 2–75 ms per base after JIT warm-up (median 5–8 ms).  The saturation does enter
`resolution` (13 fresh `Resolution` partitions, 4 Resolution-minted ids at base 0), but
`substitution` spreads the multi-label concrete parts the mints create, and a merge with a
repeated label is reached after ~50 dequeues.  The source-level module `CRuleHang.e` is
rejected the same way (`Fields appear twice in row: Set(Repro.CRuleHang.l1)`), loads under
`-Dermine.genRules=nongen` (an unsatisfiable module compiles), and the label check plays no
role either way (`-Dermine.labelCheck=false` changes nothing on W).

Nothing under `core/src` was modified; this directory is the whole deliverable.

## Files

| file | what |
|---|---|
| `CRuleRepro.scala` | the harness: builds W / gseed / G4 / Wsat with exact ids, runs `Subst.solve` on a fresh daemon thread per base with a wall-clock cap, classifies SOLVED / REJECTED / HANG (/ OOM), prints one line per base and a histogram |
| `run.sh` | compiles `CRuleRepro.scala` together with `../nameloss/Replay.scala` (same dotc recipe, `target/ermine-classpath`) and runs one in-process sweep; `-Xmx2g` by default (`CRULE_XMX`), extra JVM flags via `ERMINE_JAVA_OPTS` |
| `sweep.sh` | driver: reruns `run.sh` in a FRESH JVM from the next base whenever the in-process hung-thread limit is reached (exit code 3), aggregates a `TOTAL` line |
| `CRuleHang.e` | the source-level reproducer (item 7) |

Ids: `a b p q p1 p2 q1 q2 w2 s2 w3 s3 = base .. base+11`, `Supply` from `base+12`, labels
`Global("Repro", "l1".."l4")`.  Every run is a fresh `SubstEnv`; the `Exists` is built raw
(`new Exists(Loc.builtin, List(), parts)`) and each `Part` raw (`new Part`), so the RHS order
is exactly the one above (the harness prints the input partitions as `INPUT` lines at the
first base of a sweep).  `tml` is `Loc.builtin`, so the label-check blame falls back to it.
Outcomes: SOLVED = `solve` returned (reports `hm.types` for a, b, p, q and the residual);
REJECTED = a `Throwable` escaped `solve` (class + message; `tml.die` throws
`scalaparsers.Death`, whose `getMessage` is the rendered document); HANG = the cap (default
10 s) expired — the thread is abandoned and keeps spinning; after `maxHung` (default 6) of
those the JVM exits 3 and `sweep.sh` continues in a fresh one.  Under `-Dermine.rowTrace` a
HANG line also reports the `step` count and the largest variable id this site has written.

## Build

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    cd ermine-scala
    sbt -batch -J-Xmx2g core/compile        # the single sbt run: "[success] Total time: 1 s", nothing recompiled
                                            # (zinc matches by content hash; the class files, 15:54:26, are newer
                                            #  than the source mtime 15:54:01; the last commit touching
                                            #  Constraints.scala, b88d869 16:11, committed that already-compiled source)
    export CRULE_OUT=<scratch>/classes      # optional; default /tmp/crule-classes

`<scratch>` below was a session scratch directory under `/tmp` that did not survive a machine
restart on 2026-09-02; the raw outputs named below are therefore GONE, but every one of them
is regenerated in seconds by the command that precedes it (the whole 1000-base sweep takes
8 s), and the numbers quoted here were independently re-measured by a second agent from a
fresh shell before the restart.

## 1–3. The sweep: W at bases 0..99

    tracker/repro/crule/sweep.sh W 0 99 10 6 > <scratch>/sweep-W.txt

    TOTAL sys=W bases=0..99 SOLVED=0 REJECTED=100 HANG=0 OOM=0
      x28  scalaparsers.Death: Fields appear twice in row: Set(Repro.l1)
      x26  scalaparsers.Death: Fields appear twice in row: Set(Repro.l2)
      x24  scalaparsers.Death: Fields appear twice in row: Set(Repro.l4)
      x20  scalaparsers.Death: Fields appear twice in row: Set(Repro.l3)
      x1   scalaparsers.Death: Fields appear twice in row: Set(Repro.l2, Repro.l3)
      x1   scalaparsers.Death: Fields appear twice in row: Set(Repro.l3, Repro.l2)

One JVM, no restarts (no thread ever hung).  (The HANG path itself was exercised separately, by
forcing a 1 ms cap — `sweep.sh W 0 5 0.001 2` — which produces HANG lines, the hung-thread
limit with exit 3, and the fresh-JVM restart; so the harness CAN report a hang, and did not.)  Per-base wall time: min 5 ms, median 8 ms,
p95 26 ms, max 375 ms (base 0, JIT warm-up).  Every base is REJECTED; no base is SOLVED or
HANG, so there is no per-base mix to report — which label is blamed does vary with the ids
(the priority-queue order), the outcome class does not.

Extras, same harness (`<scratch>/extra-*.txt`):

    tracker/repro/crule/sweep.sh W 0 999 10 6 > <scratch>/extra-W-0-999.txt
      TOTAL sys=W bases=0..999 SOLVED=0 REJECTED=1000 HANG=0 OOM=0      (real 7.9 s for all 1000)
      x261 l1  x243 l4  x240 l3  x215 l2  x20 {l2,l3}  x11 {l3,l2}  x7 {l4,l1}  x3 {l1,l4}
      per base: min 2 ms, median 5 ms, p95 12 ms, max 546 ms (base 0)
    ERMINE_JAVA_OPTS="-Dermine.genRules=all" tracker/repro/crule/sweep.sh W 0 99 10 6 > <scratch>/extra-W-genall.txt
      TOTAL sys=W bases=0..99 SOLVED=0 REJECTED=100 HANG=0 OOM=0       (the pre-cut shipped rule set;
      histogram identical to `cut`: 28/26/24/20/1/1)
    ERMINE_JAVA_OPTS="-Dermine.labelCheck=false" tracker/repro/crule/sweep.sh G4 0 4 10 6 > <scratch>/extra-G4-nolabel.txt
      TOTAL sys=G4 bases=0..4 SOLVED=0 REJECTED=5 HANG=0 OOM=0         (all "Fields appear twice": l4 x2, l1, l2, l3)

## 4. Controls

All under `sweep.sh <sys> <from> <to> 10 6`; `ERMINE_JAVA_OPTS` as shown (each is a fresh
JVM, so `GenRules`' class-init read of the properties applies).  Raw: `<scratch>/c1..c6-*.txt`.

**(c1) gseed, default flags, bases 0..4 — EXPECTED REJECTED by the label check.**  Observed 5/5
REJECTED, all `Row partitions are unsatisfiable at field '<l>': <reason>` (`Subst.scala:1178`,
blame falls back to `Loc.builtin` since nothing has a source position):

    base 0: l4 "the whole contains it but no part does"      203 ms
    base 1: l2 "the whole contains it but no part does"        4 ms
    base 2: l4 "the whole contains it but no part does"        2 ms
    base 3: l2 "a part contains it but the whole does not"     5 ms
    base 4: l2 "the whole contains it but no part does"        3 ms

**(c2) gseed, `-Dermine.labelCheck=false`, bases 0..4** (`genRules=cut-early+resguard`).
Observed 5/5 REJECTED by `RHS.merge`, no hang: `Fields appear twice in row: Set(Repro.l4)`
(base 0, 255 ms), `Set(Repro.l3)` (bases 1, 2, 3: 14 / 15 / 29 ms), `Set(Repro.l2)` (base 4,
9 ms).  So on the bare gadget, without the check, `incorporateAll` also dies rather than loops.

**(c3) G4 = W + {a <- (q,(|l2|)), b <- (p,(|l3|)), w2 <- (q,s2,(|l2|)), w3 <- (p,s3,(|l3|))},
default flags, bases 0..4 — EXPECTED REJECTED by the label check.**  Observed 5/5 REJECTED by
the label check: base 0 l4, base 1 l2, base 2 l3, base 3 l2, base 4 l2, all "the whole
contains it but no part does" (225 / 14 / 9 / 8 / 7 ms).  With the derived edges explicit the
check sees the contradiction; on W itself it never fires (every W rejection above is from
`RHS.merge`, and c5/`labelCheck=false` on the source module confirm it).

**(c4) Wsat = W minus `b <- (q,(|l4|))`, default flags, bases 0..9 — EXPECTED SOLVED.**
Observed 10/10 SOLVED in 337 / 57 / 35 / 30 / 25 / 20 / 19 / 16 / 18 / 19 ms.  `hm.types` is
empty (`bound=0`; a, b, p, q "unbound") — nothing in Wsat has a concrete left-hand side, so
nothing pins — and the returned residual is an `Exists` over the input plus derived
partitions (e.g. `Part(w3^10, [(|l3|), s3^11, p2^5, p1^4])`, `Part(a^0, [(|l1|), p^2])`, ...).

**(c5) W, `-Dermine.resGuard=false` (unguarded resolution), bases 0..9** — the brief expected
HANG.  Observed 10/10 REJECTED, 0 HANG: `Fields appear twice in row: Set(Repro.l1)` (bases
0, 8), `l4` (1, 6, 7), `l3` (2, 5, 9), `l2` (3, 4); 406 / 112 / 23 / 19 / 35 / 17 / 39 / 18 /
40 / 24 ms.

**(c6) W, `-Dermine.genRules=nongen`, bases 0..9.**  Observed 10/10 SOLVED in 307 / 31 / 22 /
16 / 18 / 14 / 12 / 15 / 9 / 10 ms, `hm.types` empty, residual = the input partitions (plus
non-minting consequences): the unsatisfiable W is ACCEPTED without complaint — no rule mints,
the label check cannot see it, so nothing refutes it.

## 5. Trace of one base (there is no hanging base; base 0 is traced as the REJECTED case)

    ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/trace-W0.tsv" timeout 8 tracker/repro/crule/run.sh sweep W 0 0 1000
      W base=0: REJECTED in 416 ms  scalaparsers.Death: Fields appear twice in row: Set(Repro.l1)
    ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/trace-W1.tsv" timeout 8 tracker/repro/crule/run.sh sweep W 1 1 1000
      W base=1: REJECTED in 407 ms  scalaparsers.Death: Fields appear twice in row: Set(Repro.l3)

`trace-W0.tsv`: 265 records = **50 `step` + 215 `learn`**, nothing else (`in`/`inpart`/`sat`/
`solve` are written after `q.expand`, which threw).  All 50 steps took the general `learn`
branch (no `common`/`unify`/`concrete`/`empty`); all 8 inputs were dequeued.  `learn`
provenance (total / of which `new`, i.e. not already in the processed set):

    Substitution 76 / 56   CommonSubexpression 55 / 29   Cancellation 47 / 3
    SplitConcrete 22 / 16  Resolution 15 / 13            (new 117, seen 98)

Distinct variable ids in the trace: **22** — 0..13, 17, 19, 22, 23, 25, 26, 27, 31; the
Supply (from 12) reached 31, i.e. 20 fresh ids drawn, 10 of them appearing in learned
partitions: 12, 17, 19, 22, 23, 25 minted by `SplitConcrete`, **13, 26, 27, 31 by
`Resolution`**.  8 of the 50 dequeued partitions carry `Resolution` provenance.  The queue
was still growing when the merge died (last step: `incm=26 proc=49`).  Base 1 is the same
picture: 57 steps, 240 learn (Substitution 84, CSE 59, Cancellation 55, SplitConcrete 27,
Resolution 15), 23 distinct ids up to 32, 3 Resolution-minted (15, 26, 27).

The ids do NOT grow without bound: the run dies ~50 dequeues in.  What the trace shows is
the Lean's first round — folds by `Substitution`, remainders named by `SplitConcrete` (the
`^ambiguous(free)NN` variables), `Cancellation`, then `Resolution` mints — and then a
`Substitution` of a two- or three-label concrete part into a row that already carries one of
those labels, which `RHS.merge` refuses.

First 40 `step`/`learn` lines of `trace-W0.tsv` (site column dropped; `^freeN` are the input
ids, `^ambiguous(free)N` the minted ones; `seen` = already in the processed set):

    step   learn  ^free2 <- (^free4 ^free5,)                                 incm=7  proc=0      [p <- (p1,p2)]
    step   learn  ^free0 <- (^free2,Repro.l1)                                incm=6  proc=1      [a <- (p,l1)]
    learn  new    Substitution: ^free0 <- (^free4 ^free5,Repro.l1)
    step   learn  Substitution: ^free0 <- (^free4 ^free5,Repro.l1)           incm=6  proc=2
    learn  seen   SplitConcrete: ^free0 <- (^free2,Repro.l1)
    learn  new    CommonSubexpression: ^free2 <- (^free2,)
    learn  seen   Cancellation: ^free2 <- (^free4 ^free5,)
    step   learn  ^free3 <- (^free6 ^free7,)                                 incm=5  proc=3      [q <- (q1,q2)]
    step   learn  ^free1 <- (^free3,Repro.l4)                                incm=4  proc=4      [b <- (q,l4)]
    learn  new    Substitution: ^free1 <- (^free6 ^free7,Repro.l4)
    step   learn  Substitution: ^free1 <- (^free6 ^free7,Repro.l4)           incm=4  proc=5
    learn  seen   SplitConcrete: ^free1 <- (^free3,Repro.l4)
    learn  seen   Cancellation: ^free3 <- (^free6 ^free7,)
    learn  new    CommonSubexpression: ^free3 <- (^free3,)
    step   learn  ^free10 <- (^free4 ^free5 ^free11,Repro.l3)                incm=3  proc=6      [w3 <- (p1,p2,s3,l3)]
    learn  new    SplitConcrete: ^free10 <- (^ambiguous(free)12,Repro.l3)
    learn  seen   CommonSubexpression: ^free0 <- (^free2,Repro.l1)
    learn  new    SplitConcrete: ^ambiguous(free)12 <- (^free4 ^free5 ^free11,)
    learn  new    CommonSubexpression: ^free2 <- (^free2,)
    learn  new    CommonSubexpression: ^free10 <- (^free11 ^free2,Repro.l3)                     [the fold: w3 <- (p, s3, l3)]
    step   learn  SplitConcrete: ^ambiguous(free)12 <- (^free4 ^free5 ^free11,) incm=5 proc=7
    learn  new    CommonSubexpression: ^free10 <- (^ambiguous(free)12,Repro.l3)
    learn  new    CommonSubexpression: ^ambiguous(free)12 <- (^free11 ^free2,)
    learn  seen   CommonSubexpression: ^free0 <- (^free2,Repro.l1)
    learn  new    CommonSubexpression: ^free2 <- (^free2,)
    step   learn  CommonSubexpression: ^ambiguous(free)12 <- (^free11 ^free2,) incm=5 proc=8
    learn  seen   Substitution: ^ambiguous(free)12 <- (^free11 ^free4 ^free5,)
    learn  seen   Cancellation: ^free2 <- (^free4 ^free5,)
    step   learn  SplitConcrete: ^free10 <- (^ambiguous(free)12,Repro.l3)    incm=4  proc=9
    learn  seen   Cancellation: ^ambiguous(free)12 <- (^free4 ^free5 ^free11,)
    learn  new    Substitution: ^free10 <- (^free11 ^free2,Repro.l3)
    learn  seen   Substitution: ^free10 <- (^free4 ^free5 ^free11,Repro.l3)
    step   learn  CommonSubexpression: ^free10 <- (^free11 ^free2,Repro.l3)  incm=3  proc=10
    learn  seen   SplitConcrete: ^free10 <- (^ambiguous(free)12,Repro.l3)
    learn  seen   Cancellation: ^free2 <- (^free4 ^free5,)
    learn  new    CommonSubexpression: ^ambiguous(free)12 <- (^ambiguous(free)12,)
    learn  seen   Substitution: ^free10 <- (^free11 ^free4 ^free5,Repro.l3)
    learn  seen   Cancellation: ^ambiguous(free)12 <- (^free11 ^free2,)
    step   learn  ^free10 <- (^free1 ^free11,)                               incm=2  proc=11     [w3 <- (b,s3)]
    learn  new    Substitution: ^free10 <- (^free11 ^free3,Repro.l4)

The last 20 trace lines before the rejection (the `Resolution` mints and the substitutions
that spread their two- and three-label concrete parts; the exception is raised inside the
`learnPartitions` of the final step, which is why no `learn` follows it):

    learn  new    Substitution: ^free2 <- (^ambiguous(free)26,Repro.l2 Repro.l4)
    step   learn  Substitution: ^free2 <- (^ambiguous(free)26,Repro.l4 Repro.l2)     incm=22 proc=47
    learn  new    Substitution: ^free8 <- (^free9 ^ambiguous(free)26,Repro.l1 Repro.l4 Repro.l2)
    learn  new    Substitution: ^free0 <- (^ambiguous(free)26,Repro.l1 Repro.l4 Repro.l2)
    learn  new    Substitution: ^free10 <- (^free11 ^ambiguous(free)26,Repro.l3 Repro.l4 Repro.l2)
    learn  seen   Cancellation: ^ambiguous(free)27 <- (^ambiguous(free)26,Repro.l4)
    learn  new    Substitution: ^ambiguous(free)12 <- (^free11 ^ambiguous(free)26,Repro.l4 Repro.l2)
    learn  seen   Cancellation: ^ambiguous(free)13 <- (^ambiguous(free)26,Repro.l2)
    learn  new    Substitution: ^free1 <- (^ambiguous(free)26,Repro.l3 Repro.l4 Repro.l2)
    learn  new    Substitution: ^ambiguous(free)23 <- (^free9 ^ambiguous(free)26,Repro.l4 Repro.l2)
    step   learn  Resolution: ^free3 <- (^ambiguous(free)27,Repro.l1)                incm=21 proc=48
    learn  new    Substitution: ^ambiguous(free)19 <- (^free11 ^ambiguous(free)27,Repro.l1)
    learn  new    Resolution: ^free3 <- (^ambiguous(free)31,Repro.l1 Repro.l3)
    learn  new    Substitution: ^free3 <- (^ambiguous(free)26,Repro.l1 Repro.l4)
    learn  new    Resolution: ^ambiguous(free)27 <- (^ambiguous(free)31,Repro.l3)
    learn  new    Substitution: ^free10 <- (^free11 ^ambiguous(free)27,Repro.l4 Repro.l1)
    learn  new    Substitution: ^free1 <- (^ambiguous(free)27,Repro.l4 Repro.l1)
    learn  new    Substitution: ^free0 <- (^ambiguous(free)27,Repro.l2 Repro.l1)
    learn  new    Resolution: ^ambiguous(free)13 <- (^ambiguous(free)31,Repro.l1)
    step   learn  Resolution: ^ambiguous(free)13 <- (^ambiguous(free)31,Repro.l1)    incm=26 proc=49
    --> scalaparsers.Death: Fields appear twice in row: Set(Repro.l1)

## 6. Memory / time growth

Not applicable: no base of W hung under any flag combination measured (default, `resGuard=
false`, `genRules=all`, `labelCheck=false` on G4, `nongen`), so there is no hanging run whose
growth could be measured.  For scale, a whole base (≈50 dequeues, ≈215 learned partitions)
costs 2–12 ms at steady state in the 1000-base sweep, i.e. on the order of 5–10 k dequeues
per second; the traced single-base runs (416 / 407 ms) are dominated by JVM class loading and
are not a rate.  Peak heap was never an issue (`-Xmx2g`, one JVM per sweep, 1000 bases in
7.9 s).

## 7. Source-level reproducer

`CRuleHang.e` carries the eight constraints in one signature (syntax from
`core/examples/shouldfail/der06_shared_two_var_remainder.e`), with a trivially typeable body
and two use sites:

    wit : forall a b p q p1 p2 q1 q2 w2 s2 w3 s3.
          ( a <- (p, (|l1|)), b <- (q, (|l4|))
          , w2 <- (a, s2), w2 <- (q1, q2, s2, (|l2|)), q <- (q1, q2)
          , w3 <- (b, s3), w3 <- (p1, p2, s3, (|l3|)), p <- (p1, p2) )
       => Row a -> Row b -> Int
    wit _ _ = 0
    bad = wit
    bad2 r s = wit r s

    ERMINE_JAVA_OPTS=-Dermine.useInterface=false timeout 90 bin/ermine tracker/repro/crule/CRuleHang.e </dev/null
      Loaded 129 modules (13.69 seconds)
      tracker/repro/crule/CRuleHang.e:1:1: Fields appear twice in row: Set(Repro.CRuleHang.l1)
      module Repro.CRuleHang where
      ^
      Unable to load module (0.06 seconds)                 (real 14.8 s; exit 0 as always; no .ei written)

Accepted on the first try; **REJECTED**, by `RHS.merge`, blamed at the module header (1:1).
Variants (copies under `<scratch>/`, outputs `source-CRuleHang-v*.out`):

| variant | command | result |
|---|---|---|
| signature + body only (no use site) | `bin/ermine <scratch>/CRuleHangSigOnly.e` | **LOADED** — `Importing module 'Repro.CRuleHang' (0.04 seconds)`: an annotation's constraints are never solved |
| `wit` + `bad = wit` only | `bin/ermine <scratch>/CRuleHangBad.e` | REJECTED, same message (0.06 s) |
| `wit` + `bad2 r s = wit r s` only | `bin/ermine <scratch>/CRuleHangBad2.e` | REJECTED, same message (0.07 s) |
| full file, `-Dermine.genRules=nongen` | `ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.genRules=nongen" bin/ermine tracker/repro/crule/CRuleHang.e` | **LOADED** — `Importing module 'Repro.CRuleHang' (0.07 seconds)`: the unsatisfiable module compiles |
| full file, `-Dermine.labelCheck=false` | `ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.labelCheck=false" bin/ermine tracker/repro/crule/CRuleHang.e` | REJECTED, same message (0.06 s): the label check is not what rejects W |

No `.ei` files were produced (`useInterface=false`); none to delete.

## Deviations from the brief's expectations

* The brief anticipated HANG for W (and "expected HANG too" for c5).  **Nothing hung.**  W is
  REJECTED at 1000/1000 bases under the default rule set, at 100/100 under `genRules=all`,
  and at 10/10 with the resolution guard off.  The rule set admits infinite chains; the
  worklist does not follow one, because `substitution` propagates the resolvents' multi-label
  concrete parts into rows that already carry one of the labels, and `RHS.merge` throws
  `Fields appear twice in row` before the second round of mints is dequeued (base 0 dies on
  the 50th dequeue with 4 Resolution-minted ids in play).
* The label check never fires on W (as the Lean says); every W rejection is `RHS.merge`'s.
  It does fire on gseed (c1) and on G4 (c3), with the field and the reason in the message.
* Under `nongen` W is SOLVED / the module LOADS — an unsatisfiable system accepted — which is
  the documented reason `nongen` is not the default.
