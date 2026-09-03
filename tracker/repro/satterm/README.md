# `satterm/` — W2, H2 and NE6 (satisfiable, additively divergent) replayed through the shipped `Subst.solve`

**Question.**  `tracker/lean/Rowpartition/DefaultTerm.lean`'s `TerminatesOnSat` — "from every
SATISFIABLE input every productive run of `DefaultStep` is bounded" — is FALSE for the additive
rule set: from the two-constraint satisfiable system

    W2:  p <- (e1, e2, (|k|)),  p <- (e2, (|k|))          model p={k,m}  e2={m}  e1={}  (e1 is forced empty)

a productive run mints forever (round 0 mints `u <- (e1, e2)`, `p <- (u, (|k|))`; every later
round: CANCELLATION `e2 <- (u)`, SUBSTITUTION `p <- (e1, u, (|k|))`, SPLIT MINT `u' <- (e1, u)`,
`p <- (u', (|k|))` — the invariant `W2Inv`).  The theorem is about the ADDITIVE relation; this
directory asks what the SHIPPED worklist `Constraints.incorporateAll` does on the same inputs,
which also has `makeEmpty` (erases a variable derived empty), `unify` (a singleton link
`a <- (b)` is a substitution, not a constraint) and `makeConcrete`.  The brief's PREDICTION, to
be tested: W2 and H2 terminate quickly, killed by `unify` and/or `makeEmpty`; NE6 terminates
after a handful of mints.  A HANG or more than ~50 mints would have been the headline.

**Answer (measured 2026-09-03, branch `scala3-migration`, default flags
`genRules=cut+label-early+resguard`, class files newer than every source).**

* **No seed hangs, none is rejected: 300/300 SOLVED at bases 0..99 (3000/3000 at 0..999).**
* **W2:** exactly **one** split mint at 100/100 bases, then the loop ends in 5–7 dequeues.
  Both defences the brief named fire, in this order, at every base: `Cancellation` derives
  `e1 <- ()` (and, at 33 bases, the link `e2 <- (u)` too), the `empty` branch (`makeEmpty(e1)`)
  erases `e1` from every partition — which turns the mint's own definition `u <- (e1, e2)`
  into the singleton `u <- (e2)` — and that singleton is then dequeued on the `unify:e2` branch,
  which instantiates `e2 := u` destructively.  The Lean's step 2 (substituting the link into
  `p <- (e1, e2, (|k|))`) is never taken: `e1` is gone before any substitution can build the
  group `{e1, u}`, so the second mint has no premise.  Result `e1 := (||)`, `e2 := u`, residual
  `p <- ((|k|), u)`.
* **H2:** the hidden `p <- (e2, (|k|))` is first DERIVED by `Cancellation` from `q <- (p, s)` /
  `q <- (e2, s, (|k|))`, and from there the W2 picture repeats: `empty` at 100/100 bases,
  `unify` at 100/100, 2–3 split mints (measured groups over 100 bases: `{e1,e2}` x100,
  `{e2,s}` x100, and a third name for `{s,u}` at 21 bases or `{e1,e2,s}` at 17), 12–17 dequeues.
* **NE6:** 2–5 split mints + 0–1 guarded `Resolution` mint per base (6 fresh ids in the queue
  at 7 bases, e.g. 8 and 83; never more), 12–45 dequeues; ends through the `concrete` branch (`v1 := (|l1|)`,
  `v4 := (|l2,l3|)`, `v0 := (|l1,l2,l3,l4|)` — the model's values — and the minted names made
  concrete); `unify` fires at 61/100 bases and `empty` at 25/100, and 32/100 bases end with
  neither (43 `unify` only, 7 `empty` only, 18 both).
* Controls: `genRules=nongen` mints nothing and SOLVES all three (10/10 each, `drawn=0`);
  `resGuard=false` changes nothing on W2 (10/10 SOLVED, same types) and only raises NE6's
  worst case to 25 draws / 8 fresh ids (base 8, 65 dequeues); `genRules=all` and
  `labelCheck=false` are also 10/10 SOLVED per seed.

Nothing under `core/src` was modified; this directory is the whole deliverable.

## Files

| file | what |
|---|---|
| `SatTermRepro.scala` | the harness: builds W2 / H2 (hard-coded) / NE6 (from `seeds/NE6.json`, the `rowclosure.py` seed format) with exact ids, runs `Subst.solve` on a fresh daemon thread per base with a wall-clock cap, classifies SOLVED / REJECTED / HANG (/ OOM); `sweep` prints one line per base, `hm.types` for every input variable, the residual and its size, the number of ids the `Supply` handed out; `trace` runs ONE base under `-Dermine.rowTrace` and prints the step-branch sequence, per-branch and per-rule counts, the fresh ids that entered the queue, and the first N / last 20 `step`/`learn` lines |
| `run.sh` | compiles `SatTermRepro.scala` with `../nameloss/Replay.scala` (same dotc recipe as `../crule/run.sh`, `target/ermine-classpath`) and runs one in-process sweep or trace; `-Xmx2g` (`SATTERM_XMX`), extra JVM flags via `ERMINE_JAVA_OPTS`, classes in `SATTERM_OUT` (default `/tmp/satterm-classes`) |
| `sweep.sh` | driver: reruns `run.sh` in a FRESH JVM from the next base whenever the hung-thread limit is hit (exit 3); aggregates a `TOTAL` line |
| `seeds/W2.json`, `seeds/H2.json`, `seeds/NE6.json` | the three seeds in `rowclosure.py`'s format (copied from the session's `satterm/math/` scratch; `NE6.json` is the one the harness loads) |
| `tools/tracestats.py`, `tools/mintprov.py` | the two post-processors for a traced sweep (§3): per-site branch multisets / `unify`+`empty` site counts, and the fresh-id-to-rule attribution |

Seeds as the harness builds them (`INPUT` lines are printed at the first base of every sweep;
`Supply` from `base + #vars`; labels `Global("Repro", ·)`; every `Part` and the `Exists` are
built raw so the RHS order is exactly as written; `tml = Loc.builtin`):

    W2   ids p e1 e2 = base..base+2, Supply base+3
         p <- (e1, e2, (|k|)),  p <- (e2, (|k|))                              model p={k,m} e1={} e2={m}
    H2   ids p e1 e2 q s = base..base+4, Supply base+5
         p <- (e1, e2, (|k|)),  q <- (p, s),  q <- (e2, s, (|k|))            model p={k,m} e1={} e2={m} q={k,m,n} s={n}
    NE6  ids v0..v5 = base..base+5, Supply base+6  (seeds/NE6.json; label n -> Global("Repro","l"+n))
         v0 <- (v1, (|l2,l3,l4|)),  v0 <- (v1, v2, v3, (|l4|)),  v0 <- (v4, (|l1,l4|)),
         v0 <- (v2, v3, (|l1,l4|)),  v0 <- (v1, v4, (|l4|)),  v5 <- (v1, v2, (|l9|))
                                                    model v0={l1,l2,l3,l4} v1={l1} v2={l2} v3={l3} v4={l2,l3} v5={l1,l2,l9}

Outcome classes: SOLVED = `solve` returned (types from `hm.types`, `substType`-resolved; a
bare number such as `e2 := 3` is the VarT with that id, i.e. a MINTED variable); REJECTED = a
`Throwable` escaped; HANG = the cap (10 s) expired, the thread is abandoned; after `maxHung`
(6) of those the JVM exits 3 and `sweep.sh` restarts it.  `drawn` = ids the run's `Supply`
handed out (read reflectively; for a HANG, the value at the cap).  **`drawn` over-counts
mints**: `Constraints.resolution` (Constraints.scala:1199) draws a fresh id for EVERY pair of
single-variable partitions with the same lhs and then discards it when one concrete part
contains the other ("handled by cancellation") or when the guard reuses an existing resolvent —
by design, so guarded and unguarded runs number their variables identically.  The exact mint
count is the number of fresh ids that appear in a `step`/`learn` record (`IDS ... fresh(...)`
in a trace), attributed to the rule that defines them (`SplitConcrete: u <- (group)` on the
LHS, `Resolution: v <- (z, K)` on the RHS).  On the traced 0..99 sweeps every fresh id in the
queue is one of those two (0 unattributed).

## Build

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
    cd ermine-scala                                  # class files (21:22) newer than Constraints.scala (20:53); sbt NOT run
    export SATTERM_OUT=<scratch>/classes             # optional
    tracker/repro/satterm/run.sh sweep W2 0 2        # compiles on first use (~4 s), then runs

`<scratch>` = `/tmp/claude-1000/.../scratchpad/satterm/scala/{out,traces}` (session scratch;
every output below is regenerated in seconds by the command that precedes it).

## 1. Sweeps, default flags, bases 0..99

    tracker/repro/satterm/sweep.sh W2  0 99 10 6 > <scratch>/out/sweep-W2.txt      (real 0.7 s)
    tracker/repro/satterm/sweep.sh H2  0 99 10 6 > <scratch>/out/sweep-H2.txt      (real 1.0 s)
    tracker/repro/satterm/sweep.sh NE6 0 99 10 6 > <scratch>/out/sweep-NE6.txt     (real 1.2 s)

W2 (first five bases shown; the `[bound=.. residual=..]` tail is dropped here — see the summary):

    genRules=cut+label-early+resguard  rowTrace=off  maxHeap=2048M
    SEED W2  model p={k,m} e1={} e2={m}
    INPUT p^0 <- (e1^1, e2^2, (|Repro.k|))
    INPUT p^0 <- (e2^2, (|Repro.k|))
    W2   base=   0 ids 0..2 supply    3: SOLVED   in   224 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 3
    W2   base=   1 ids 1..3 supply    4: SOLVED   in     4 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 4
    W2   base=   2 ids 2..4 supply    5: SOLVED   in     4 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 5
    W2   base=   3 ids 3..5 supply    6: SOLVED   in     4 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 6
    W2   base=   4 ids 4..6 supply    7: SOLVED   in     3 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 7
    ...
    SUMMARY seed=W2 bases=0..99 n=100 SOLVED=100 REJECTED=0 HANG=0 OOM=0
    DRAWN  min=1 median=1 max=2  histogram 1:x67 2:x33
    TIME   min=0 median=1 p95=4 max=224 ms
    TOTAL seed=W2 bases=0..99 SOLVED=100 REJECTED=0 HANG=0 OOM=0

Per-base type pattern over the 100 bases (ids normalised): **100/100** `p := unbound;
e1 := (||); e2 := <mint>` with `bound=2`, residual 1 partition `p <- ((|k|), <mint>)`; `drawn=1`
at 67 bases, `drawn=2` at 33 (the extra draw is a discarded `resolution` draw; the trace shows
one fresh id in the queue at every base).  Time per base 0–5 ms after warm-up.

H2:

    genRules=cut+label-early+resguard  rowTrace=off  maxHeap=2048M
    SEED H2  model p={k,m} e1={} e2={m} q={k,m,n} s={n}
    INPUT p^0 <- (e1^1, e2^2, (|Repro.k|))
    INPUT q^3 <- (p^0, s^4)
    INPUT q^3 <- (e2^2, s^4, (|Repro.k|))
    H2   base=   0 ids 0..4 supply    5: SOLVED   in   217 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 5; q := unbound; s := unbound
    H2   base=   1 ids 1..5 supply    6: SOLVED   in    22 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 6; q := unbound; s := unbound
    H2   base=   2 ids 2..6 supply    7: SOLVED   in    16 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 7; q := unbound; s := unbound
    H2   base=   3 ids 3..7 supply    8: SOLVED   in    21 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 8; q := unbound; s := unbound
    H2   base=   4 ids 4..8 supply    9: SOLVED   in     8 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 9; q := unbound; s := unbound
    ...
    SUMMARY seed=H2 bases=0..99 n=100 SOLVED=100 REJECTED=0 HANG=0 OOM=0
    DRAWN  min=3 median=3 max=3  histogram 3:x100
    TIME   min=1 median=3 p95=11 max=217 ms
    TOTAL seed=H2 bases=0..99 SOLVED=100 REJECTED=0 HANG=0 OOM=0

Type patterns: 72/100 `e2 := <mint>`, 28/100 `e2 := unbound`.  Measured on the traced sweep
(§3): at the 72 bases the first `unify` step dequeues the erased definition `u <- (e2)` (so
`e2 := u`), at the 28 it dequeues the link `e2 <- (u)` itself (so `u := e2`) — the same kill
either way, and the link is what `makeEmpty` left when the definition had already been
processed.  `e1 := (||)` at 100/100; `p`, `q`, `s` unbound; `bound` 2 or 3; residual always 3
partitions, e.g. `q <- ((|k|), u, s), q <- (p, s), p <- ((|k|), u)`; `drawn=3` at 100/100.

NE6:

    genRules=cut+label-early+resguard  rowTrace=off  maxHeap=2048M
    SEED NE6  model v0={l1,l2,l3,l4} v1={l1} v2={l2} v3={l3} v4={l2,l3} v5={l1,l2,l9}
    INPUT v0^0 <- (v1^1, (|Repro.l2,Repro.l3,Repro.l4|))
    INPUT v0^0 <- (v1^1, v2^2, v3^3, (|Repro.l4|))
    INPUT v0^0 <- (v4^4, (|Repro.l1,Repro.l4|))
    INPUT v0^0 <- (v2^2, v3^3, (|Repro.l1,Repro.l4|))
    INPUT v0^0 <- (v1^1, v4^4, (|Repro.l4|))
    INPUT v5^5 <- (v1^1, v2^2, (|Repro.l9|))
    NE6  base=   0 ids 0..5 supply    6: SOLVED   in   231 ms  v0 := ConcreteRho(-,Set(l2, l3, l4, l1)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
    NE6  base=   1 ids 1..6 supply    7: SOLVED   in    24 ms  v0 := ConcreteRho(-,Set(l2, l3, l4, l1)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
    NE6  base=   2 ids 2..7 supply    8: SOLVED   in    23 ms  v0 := ConcreteRho(-,Set(l1, l4, l2, l3)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
    NE6  base=   3 ids 3..8 supply    9: SOLVED   in    11 ms  v0 := ConcreteRho(-,Set(l2, l3, l4, l1)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
    NE6  base=   4 ids 4..9 supply   10: SOLVED   in    27 ms  v0 := ConcreteRho(-,Set(l1, l4, l2, l3)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
    ...
    SUMMARY seed=NE6 bases=0..99 n=100 SOLVED=100 REJECTED=0 HANG=0 OOM=0
    DRAWN  min=2 median=4 max=19  histogram 2:x13 3:x23 4:x15 5:x21 6:x9 7:x5 8:x3 9:x1 11:x1 13:x4 14:x1 15:x2 16:x1 19:x1
    TIME   min=2 median=4 p95=24 max=231 ms
    TOTAL seed=NE6 bases=0..99 SOLVED=100 REJECTED=0 HANG=0 OOM=0

Type patterns: 100/100 `v0 := (|l1,l2,l3,l4|); v1 := (|l1|); v4 := (|l2,l3|)` (the model's
values — the only ones the constraints force), `v3 := unbound`, `v5 := unbound`; `v2 := unbound`
at 89, `v2 := <mint>` at 11; `bound` 5 (x62) / 6 (x22) / 7 (x9) / 8 (x7); residual 3 partitions at
95 bases, 4 at 5.  `drawn`
2–19 (median 4); base 83 is the maximum (19 draws, 6 fresh ids in the queue — traced in §4).

Extended, same command with `0 999`:

    tracker/repro/satterm/sweep.sh W2  0 999 10 6     TOTAL seed=W2  bases=0..999 SOLVED=1000 REJECTED=0 HANG=0 OOM=0   drawn 1:x681 2:x319   TIME min=0 median=0 p95=1 max=221 ms   (real 1.6 s)
    tracker/repro/satterm/sweep.sh H2  0 999 10 6     TOTAL seed=H2  bases=0..999 SOLVED=1000 REJECTED=0 HANG=0 OOM=0   drawn 3:x1000        TIME min=0 median=1 p95=3 max=254 ms   (real 2.5 s)
    tracker/repro/satterm/sweep.sh NE6 0 999 10 6     TOTAL seed=NE6 bases=0..999 SOLVED=1000 REJECTED=0 HANG=0 OOM=0   TIME min=1 median=2 p95=11 max=305 ms   (real 5.4 s)
        drawn 2:x176 3:x150 4:x203 5:x182 6:x89 7:x32 8:x37 9:x18 10:x18 11:x24 12:x11 13:x14 14:x15 15:x11 16:x12 17:x4 18:x3 19:x1

The HANG path of the harness is the one `../crule/` exercised (a 1 ms cap produces HANG lines,
exit 3 and the fresh-JVM restart); it is inherited unchanged and was not needed: no thread hung.

## 2. Traces: base 0 and base 1 of each seed (fresh JVM, `-Dermine.rowTrace`)

    for sd in W2 H2 NE6; do for b in 0 1; do
      ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/traces/trace-$sd-$b.tsv" \
        tracker/repro/satterm/run.sh trace $sd $b 10 40 > <scratch>/out/trace-$sd-$b.txt
    done; done

Record formats (`RowTrace.scala`, `Constraints.incorporateAll`): `step <site> <branch>
<partition> incm=<queue left> proc=<processed>` with branch `learn` (the general rule pass) |
`empty` (`makeEmpty`: the dequeued partition is `v <- ()`) | `concrete` (`makeConcrete`) |
`unify:<id>` (the dequeued partition is the singleton `v <- (id)`; `unify(id, v)` instantiates
`id := v`) | `common:<id>` (a partition with the same RHS is already processed; unify the two
lhs); `learn <site> new|seen <Provenance>: <partition>` for each partition the `learn` branch
derived.  `^freeN` are input ids, `^ambiguous(free)N` minted ones.  The site column is dropped
below; `Repro.` is stripped from labels.  The `POPULATION` records are what `solve` committed
(`inpart` = input, `sat` = the saturated partitions `reduce` sees, `solve` = the summary
record, `concr` / `splice` = concrete instantiations and splices).

### W2, base 0 — 7 steps, 1 mint: `learn learn learn learn empty unify:2 common:0`

    W2   base=   0 ids 0..2 supply    3: SOLVED   in   213 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 3
      [bound=2 residual=1 drawn=2 residual=Exists(-, [],[Part(p^0, List(ConcreteRho(-,Set(k)), 3))])]
    TRACE  records=20 steps=7 (common=1 empty=1 learn=4 unify=1) learn=7 (new=5 seen=2) byRule: Cancellation=3 CommonSubexpression=1 SplitConcrete=2 Substitution=1
    IDS    distinct=4 input=3 fresh(minted, in a step/learn record)=1 3  supply-drawn=2
    BRANCHES learn learn learn learn empty unify:2 common:0

    FIRST 14 of 14 step/learn lines (site column dropped):
        step  learn  ^free0 <- (^free1 ^free2,k)  incm=1  proc=0
        learn  new  SplitConcrete: ^ambiguous(free)3 <- (^free1 ^free2,)
        learn  new  SplitConcrete: ^free0 <- (^ambiguous(free)3,k)
        step  learn  SplitConcrete: ^ambiguous(free)3 <- (^free1 ^free2,)  incm=2  proc=1
        learn  new  CommonSubexpression: ^free0 <- (^ambiguous(free)3,k)
        step  learn  SplitConcrete: ^free0 <- (^ambiguous(free)3,k)  incm=1  proc=2
        learn  seen  Cancellation: ^ambiguous(free)3 <- (^free1 ^free2,)
        learn  seen  Substitution: ^free0 <- (^free1 ^free2,k)
        step  learn  ^free0 <- (^free2,k)  incm=0  proc=3
        learn  new  Cancellation: ^free1 <- (,)
        learn  new  Cancellation: ^free2 <- (^ambiguous(free)3,)
        step  empty  Cancellation: ^free1 <- (,)  incm=1  proc=4
        step  unify:2  SplitConcrete: ^ambiguous(free)3 <- (^free2,)  incm=1  proc=2
        step  common:0  ^free0 <- (^ambiguous(free)3,k)  incm=0  proc=1

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  p^0  e1^1 e2^2  k
        inpart  -  1  INPUT  p^0  e2^2  k
        sat  -  0  SplitConcrete  p^0  ^3  k
        solve  -  2  2  1  1  true  2;3  SplitConcrete:1

Reading: step 1 dequeues `p <- (e1, e2, (|k|))` and `splitConcrete` MINTS `^3 <- (e1, e2)`,
`p <- (^3, (|k|))` (the Lean's round 0).  Step 4 dequeues the second input `p <- (e2, (|k|))`;
`cancellation` against the two processed `p`-partitions derives `e1 <- ()` (from
`p <- (e1,e2,(|k|))`) AND the alias link `e2 <- (^3)` (from `p <- (^3,(|k|))` — the Lean's
round-1 step 1).  Step 5 dequeues `e1 <- ()`: **`empty`** — `makeEmpty(e1)` instantiates
`e1 := (||)` and rewrites every partition mentioning `e1` (`proc` drops from 4 to 2): the
mint's definition `^3 <- (e1, e2)` becomes `^3 <- (e2)` and `p <- (e1, e2, (|k|))` becomes a
duplicate of `p <- (e2, (|k|))`.  Step 6 dequeues that rewritten definition, now a singleton:
**`unify:2`** — `e2 := ^3` everywhere; the link `e2 <- (^3)` becomes the self-unification
`^3 <- (^3)` and is dropped.  Step 7: `p <- (^3, (|k|))` finds its own RHS already processed
(`common:0`).  Queue empty; 7 dequeues, 1 fresh id, `drawn=2` (the second draw was
`resolution` on `p <- (^3,(|k|))` / `p <- (e2,(|k|))`, discarded — equal concrete parts).

### W2, base 1 — 5 steps, 1 mint: `learn learn empty unify:3 learn`

    W2   base=   1 ids 1..3 supply    4: SOLVED   in   208 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 4
      [bound=2 residual=1 drawn=1 residual=Exists(-, [],[Part(p^1, List(ConcreteRho(-,Set(k)), 4))])]
    TRACE  records=14 steps=5 (empty=1 learn=3 unify=1) learn=3 (new=3 seen=0) byRule: Cancellation=1 SplitConcrete=2
    IDS    distinct=4 input=3 fresh(minted, in a step/learn record)=1 4  supply-drawn=1
    BRANCHES learn learn empty unify:3 learn

    FIRST 8 of 8 step/learn lines (site column dropped):
        step  learn  ^free1 <- (^free3,k)  incm=1  proc=0
        step  learn  ^free1 <- (^free2 ^free3,k)  incm=0  proc=1
        learn  new  SplitConcrete: ^ambiguous(free)4 <- (^free2 ^free3,)
        learn  new  SplitConcrete: ^free1 <- (^ambiguous(free)4,k)
        learn  new  Cancellation: ^free2 <- (,)
        step  empty  Cancellation: ^free2 <- (,)  incm=2  proc=2
        step  unify:3  SplitConcrete: ^ambiguous(free)4 <- (^free3,)  incm=1  proc=1
        step  learn  SplitConcrete: ^free1 <- (^ambiguous(free)4,k)  incm=0  proc=0

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  p^1  e2^3  k
        inpart  -  1  INPUT  p^1  e1^2 e2^3  k
        sat  -  0  SplitConcrete  p^1  ^4  k
        solve  -  2  2  1  1  true  2;3  SplitConcrete:1

Here `p <- (e2, (|k|))` is dequeued first (queue order is by id), so when `p <- (e1, e2, (|k|))`
arrives the mint and `e1 <- ()` come out of the same `learn` step and the link `e2 <- (u)` is
never derived at all: `empty` erases `e1`, the definition `^4 <- (e2)` is unified, and the
last dequeue `p <- (^4, (|k|))` learns nothing new.

### H2, base 0 — 13 steps, 2 mints: `learn x8 empty unify:2 common:0 learn learn`

    H2   base=   0 ids 0..4 supply    5: SOLVED   in   229 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 5; q := unbound; s := unbound
      [bound=2 residual=3 drawn=3 residual=Exists(-, [],[Part(q^3, List(ConcreteRho(-,Set(k)), 5, s^4)), Part(q^3, List(p^0, s^4)), Part(p^0, List(ConcreteRho(-,Set(k)), 5))])]
    TRACE  records=47 steps=13 (common=1 empty=1 learn=10 unify=1) learn=21 (new=13 seen=8) byRule: Cancellation=7 CommonSubexpression=3 SplitConcrete=5 Substitution=6
    IDS    distinct=7 input=5 fresh(minted, in a step/learn record)=2 5,6  supply-drawn=3
    BRANCHES learn learn learn learn learn learn learn learn empty unify:2 common:0 learn learn

    FIRST 34 of 34 step/learn lines (site column dropped):
        step  learn  ^free0 <- (^free1 ^free2,k)  incm=2  proc=0
        learn  new  SplitConcrete: ^ambiguous(free)5 <- (^free1 ^free2,)
        learn  new  SplitConcrete: ^free0 <- (^ambiguous(free)5,k)
        step  learn  SplitConcrete: ^ambiguous(free)5 <- (^free1 ^free2,)  incm=3  proc=1
        learn  new  CommonSubexpression: ^free0 <- (^ambiguous(free)5,k)
        step  learn  SplitConcrete: ^free0 <- (^ambiguous(free)5,k)  incm=2  proc=2
        learn  seen  Cancellation: ^ambiguous(free)5 <- (^free1 ^free2,)
        learn  seen  Substitution: ^free0 <- (^free1 ^free2,k)
        step  learn  ^free3 <- (^free2 ^free4,k)  incm=1  proc=3
        learn  new  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free4,)
        learn  new  SplitConcrete: ^free3 <- (^ambiguous(free)6,k)
        step  learn  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free4,)  incm=2  proc=4
        learn  new  CommonSubexpression: ^free3 <- (^ambiguous(free)6,k)
        step  learn  SplitConcrete: ^free3 <- (^ambiguous(free)6,k)  incm=1  proc=5
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free4,)
        learn  seen  Substitution: ^free3 <- (^free2 ^free4,k)
        step  learn  ^free3 <- (^free0 ^free4,)  incm=0  proc=6
        learn  new  Substitution: ^free3 <- (^free4 ^free1 ^free2,k)
        learn  new  Cancellation: ^free0 <- (^free2,k)
        learn  new  Substitution: ^free3 <- (^free4 ^ambiguous(free)5,k)
        step  learn  Cancellation: ^free0 <- (^free2,k)  incm=2  proc=7
        learn  new  Cancellation: ^free1 <- (,)
        learn  new  Cancellation: ^free2 <- (^ambiguous(free)5,)
        learn  seen  Substitution: ^free3 <- (^free4 ^free2,k)
        step  empty  Cancellation: ^free1 <- (,)  incm=3  proc=8
        step  unify:2  SplitConcrete: ^ambiguous(free)5 <- (^free2,)  incm=2  proc=6
        step  common:0  Cancellation: ^free0 <- (^ambiguous(free)5,k)  incm=2  proc=3
        step  learn  SplitConcrete: ^ambiguous(free)6 <- (^ambiguous(free)5 ^free4,)  incm=1  proc=3
        learn  new  Substitution: ^free3 <- (^ambiguous(free)5 ^free4,k)
        step  learn  Substitution: ^free3 <- (^free4 ^ambiguous(free)5,k)  incm=0  proc=4
        learn  seen  SplitConcrete: ^free3 <- (^ambiguous(free)6,k)
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free4 ^ambiguous(free)5,)
        learn  seen  Cancellation: ^free0 <- (^ambiguous(free)5,k)
        learn  new  CommonSubexpression: ^ambiguous(free)6 <- (^ambiguous(free)6,)

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  p^0  e1^1 e2^2  k
        inpart  -  1  INPUT  q^3  e2^2 s^4  k
        inpart  -  2  INPUT  q^3  p^0 s^4
        sat  -  0  SplitConcrete  q^3  ^6  k
        sat  -  1  SplitConcrete  p^0  ^5  k
        sat  -  2  INPUT  q^3  p^0 s^4
        sat  -  3  SplitConcrete  ^6  ^5 s^4
        sat  -  4  Substitution  q^3  ^5 s^4  k
        solve  -  3  3  5  4  true  2;3;3  SplitConcrete:3,Substitution:1
        splice  -  6  2  0  SplitConcrete  true  true  true  true

Steps 1–6 mint `^5 <- (e1, e2)` for `p` and `^6 <- (e2, s)` for `q`; step 7 dequeues
`q <- (p, s)` and `cancellation` against `q <- (e2, s, (|k|))` DERIVES the hidden
`p <- (e2, (|k|))` (`Cancellation: ^free0 <- (^free2,k)`); step 8 dequeues it and derives
`e1 <- ()` and `e2 <- (^5)` exactly as in W2; then `empty`, `unify:2`, `common:0`, and two
`learn` steps that only rename the `q`-side name's group to `{^5, s}`.

### H2, base 1 — 14 steps, 3 mints: `learn x8 empty unify:3 common:1 common:7 learn learn`

    H2   base=   1 ids 1..5 supply    6: SOLVED   in   237 ms  p := unbound; e1 := ConcreteRho(-,Set()); e2 := 6; q := unbound; s := unbound
      [bound=3 residual=3 drawn=3 residual=Exists(-, [],[Part(q^4, List(ConcreteRho(-,Set(k)), 6, s^5)), Part(q^4, List(p^1, s^5)), Part(p^1, List(ConcreteRho(-,Set(k)), 6))])]
    TRACE  records=56 steps=14 (common=2 empty=1 learn=10 unify=1) learn=29 (new=19 seen=10) byRule: Cancellation=7 CommonSubexpression=10 SplitConcrete=7 Substitution=5
    IDS    distinct=8 input=5 fresh(minted, in a step/learn record)=3 6,7,8  supply-drawn=3
    BRANCHES learn learn learn learn learn learn learn learn empty unify:3 common:1 common:7 learn learn

    FIRST 40 of 43 step/learn lines (site column dropped):
        step  learn  ^free1 <- (^free2 ^free3,k)  incm=2  proc=0
        learn  new  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free3,)
        learn  new  SplitConcrete: ^free1 <- (^ambiguous(free)6,k)
        step  learn  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free3,)  incm=3  proc=1
        learn  new  CommonSubexpression: ^free1 <- (^ambiguous(free)6,k)
        step  learn  SplitConcrete: ^free1 <- (^ambiguous(free)6,k)  incm=2  proc=2
        learn  seen  Substitution: ^free1 <- (^free2 ^free3,k)
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free3,)
        step  learn  ^free4 <- (^free1 ^free5,)  incm=1  proc=3
        learn  new  Substitution: ^free4 <- (^free5 ^ambiguous(free)6,k)
        learn  new  Substitution: ^free4 <- (^free5 ^free2 ^free3,k)
        step  learn  Substitution: ^free4 <- (^free5 ^free2 ^free3,k)  incm=2  proc=4
        learn  seen  CommonSubexpression: ^free1 <- (^ambiguous(free)6,k)
        learn  new  SplitConcrete: ^free4 <- (^ambiguous(free)7,k)
        learn  new  CommonSubexpression: ^ambiguous(free)6 <- (^ambiguous(free)6,)
        learn  seen  Cancellation: ^free1 <- (^free2 ^free3,k)
        learn  new  SplitConcrete: ^ambiguous(free)7 <- (^free5 ^free2 ^free3,)
        learn  new  CommonSubexpression: ^free4 <- (^free5 ^ambiguous(free)6,k)
        step  learn  SplitConcrete: ^ambiguous(free)7 <- (^free5 ^free2 ^free3,)  incm=3  proc=5
        learn  new  CommonSubexpression: ^ambiguous(free)7 <- (^free5 ^ambiguous(free)6,)
        learn  new  CommonSubexpression: ^ambiguous(free)6 <- (^ambiguous(free)6,)
        learn  new  CommonSubexpression: ^free4 <- (^ambiguous(free)7,k)
        learn  seen  CommonSubexpression: ^free1 <- (^ambiguous(free)6,k)
        step  learn  CommonSubexpression: ^ambiguous(free)7 <- (^free5 ^ambiguous(free)6,)  incm=3  proc=6
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free3,)
        learn  seen  Substitution: ^ambiguous(free)7 <- (^free5 ^free2 ^free3,)
        step  learn  ^free4 <- (^free3 ^free5,k)  incm=2  proc=7
        learn  new  SplitConcrete: ^free4 <- (^ambiguous(free)8,k)
        learn  new  Cancellation: ^free2 <- (,)
        learn  new  CommonSubexpression: ^ambiguous(free)7 <- (^free2 ^ambiguous(free)8,)
        learn  new  Cancellation: ^free1 <- (^free3,k)
        learn  new  SplitConcrete: ^ambiguous(free)8 <- (^free3 ^free5,)
        step  empty  Cancellation: ^free2 <- (,)  incm=6  proc=8
        step  unify:3  SplitConcrete: ^ambiguous(free)6 <- (^free3,)  incm=7  proc=4
        step  common:1  Cancellation: ^free1 <- (^ambiguous(free)6,k)  incm=6  proc=3
        step  common:7  SplitConcrete: ^ambiguous(free)8 <- (^ambiguous(free)6 ^free5,)  incm=5  proc=3
        step  learn  Substitution: ^free4 <- (^free5 ^ambiguous(free)6,k)  incm=1  proc=3
        learn  new  SplitConcrete: ^free4 <- (^ambiguous(free)7,k)
        learn  seen  Cancellation: ^free1 <- (^ambiguous(free)6,k)
        learn  new  CommonSubexpression: ^ambiguous(free)7 <- (^ambiguous(free)7,)
    LAST 3 step/learn lines:
        step  learn  SplitConcrete: ^free4 <- (^ambiguous(free)7,k)  incm=0  proc=4
        learn  seen  Substitution: ^free4 <- (^free5 ^ambiguous(free)6,k)
        learn  seen  Cancellation: ^ambiguous(free)7 <- (^free5 ^ambiguous(free)6,)

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  q^4  p^1 s^5
        inpart  -  1  INPUT  q^4  e2^3 s^5  k
        inpart  -  2  INPUT  p^1  e1^2 e2^3  k
        sat  -  0  SplitConcrete  p^1  ^6  k
        sat  -  1  INPUT  q^4  p^1 s^5
        sat  -  2  CommonSubexpression  ^7  ^6 s^5
        sat  -  3  Substitution  q^4  ^6 s^5  k
        sat  -  4  SplitConcrete  q^4  ^7  k
        solve  -  3  3  5  4  true  2;3;3  CommonSubexpression:1,SplitConcrete:2,Substitution:1
        splice  -  7  2  0  CommonSubexpression  true  true  true  true

### NE6, base 0 — 21 steps, 3 mints (2 split + 1 resolution): `learn x5 common:6 learn x4 concrete empty concrete learn learn concrete common:6 concrete common:6 learn learn`

    NE6  base=   0 ids 0..5 supply    6: SOLVED   in   250 ms  v0 := ConcreteRho(-,Set(l2, l3, l4, l1)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
      [bound=6 residual=3 drawn=6 residual=Exists(-, [],[Part(v5^5, List(ConcreteRho(-,Set(l1, l9)), v2^2)), Part(ConcreteRho(-,Set(l2, l3, l4, l1)), List(ConcreteRho(-,Set(l1, l2, l3, l4)))), Part(ConcreteRho(-,Set(l2, l3, l4, l1)), List(Conc...]
    TRACE  records=79 steps=21 (common=3 concrete=4 empty=1 learn=13) learn=30 (new=18 seen=12) byRule: Cancellation=7 CommonSubexpression=5 Resolution=5 SplitConcrete=5 Substitution=8
    IDS    distinct=9 input=6 fresh(minted, in a step/learn record)=3 6,7,11  supply-drawn=6
    BRANCHES learn learn learn learn learn common:6 learn learn learn learn concrete empty concrete learn learn concrete common:6 concrete common:6 learn learn

    FIRST 40 of 51 step/learn lines (site column dropped):
        step  learn  ^free0 <- (^free1,l2 l3 l4)  incm=5  proc=0
        step  learn  ^free0 <- (^free2 ^free3,l1 l4)  incm=4  proc=1
        learn  new  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free3,)
        learn  new  SplitConcrete: ^free0 <- (^ambiguous(free)6,l1 l4)
        step  learn  SplitConcrete: ^ambiguous(free)6 <- (^free2 ^free3,)  incm=5  proc=2
        learn  new  CommonSubexpression: ^free0 <- (^ambiguous(free)6,l1 l4)
        step  learn  ^free0 <- (^free4,l1 l4)  incm=4  proc=3
        learn  new  Resolution: ^free0 <- (^ambiguous(free)7,l1 l4 l2 l3)
        learn  new  Resolution: ^free4 <- (^ambiguous(free)7,l2 l3)
        learn  new  Resolution: ^free1 <- (^ambiguous(free)7,l1)
        learn  new  Cancellation: ^free4 <- (^free2 ^free3,)
        step  learn  Resolution: ^free1 <- (^ambiguous(free)7,l1)  incm=7  proc=4
        learn  new  Substitution: ^free0 <- (^ambiguous(free)7,l2 l3 l4 l1)
        step  common:6  Cancellation: ^free4 <- (^free2 ^free3,)  incm=6  proc=5
        step  learn  Resolution: ^ambiguous(free)6 <- (^ambiguous(free)7,l2 l3)  incm=5  proc=4
        step  learn  Resolution: ^free0 <- (^ambiguous(free)7,l1 l4 l2 l3)  incm=4  proc=5
        learn  seen  Cancellation: ^free1 <- (^ambiguous(free)7,l1)
        step  learn  SplitConcrete: ^free0 <- (^ambiguous(free)6,l1 l4)  incm=3  proc=6
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free3,)
        learn  seen  Resolution: ^free1 <- (^ambiguous(free)7,l1)
        learn  seen  Resolution: ^ambiguous(free)6 <- (^ambiguous(free)7,l2 l3)
        learn  seen  Substitution: ^free0 <- (^free2 ^free3,l1 l4)
        learn  seen  Substitution: ^free0 <- (^ambiguous(free)7,l1 l4 l2 l3)
        step  learn  ^free0 <- (^free1 ^free2 ^free3,l4)  incm=2  proc=7
        learn  new  SplitConcrete: ^ambiguous(free)11 <- (^free1 ^free2 ^free3,)
        learn  new  CommonSubexpression: ^ambiguous(free)6 <- (^ambiguous(free)6,)
        learn  new  Cancellation: ^free1 <- (,l1)
        learn  new  SplitConcrete: ^free0 <- (^ambiguous(free)11,l4)
        learn  new  Substitution: ^free0 <- (^free2 ^free3 ^ambiguous(free)7,l4 l1)
        learn  new  CommonSubexpression: ^free0 <- (^free1 ^ambiguous(free)6,l4)
        step  concrete  Cancellation: ^free1 <- (,l1)  incm=5  proc=8
        step  empty  Cancellation: ^ambiguous(free)7 <- (,)  incm=8  proc=6
        step  concrete  Resolution: ^ambiguous(free)6 <- (,l2 l3)  incm=4  proc=4
        step  learn  SplitConcrete: ^ambiguous(free)11 <- (^free2 ^free3,l1)  incm=3  proc=4
        learn  new  SplitConcrete: ^ambiguous(free)11 <- (^ambiguous(free)6,l1)
        learn  new  CommonSubexpression: ^ambiguous(free)6 <- (^ambiguous(free)6,)
        learn  new  CommonSubexpression: ^free0 <- (^ambiguous(free)6,l1 l4)
        step  learn  SplitConcrete: ^ambiguous(free)11 <- (^ambiguous(free)6,l1)  incm=4  proc=5
        learn  seen  Substitution: ^ambiguous(free)11 <- (^free2 ^free3,l1)
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free3,)
    LAST 11 step/learn lines:
        learn  new  Substitution: ^ambiguous(free)11 <- (,l1 l2 l3)
        step  concrete  Substitution: ^ambiguous(free)11 <- (,l1 l2 l3)  incm=4  proc=6
        step  common:6  Cancellation: ^ambiguous(free)6 <- (,l2 l3)  incm=3  proc=6
        step  concrete  ^free0 <- (,l2 l3 l4 l1)  incm=2  proc=6
        step  common:6  Cancellation: ^ambiguous(free)6 <- (,l2 l3)  incm=2  proc=7
        step  learn  CommonSubexpression: ^free0 <- (^ambiguous(free)6,l1 l4)  incm=1  proc=7
        learn  seen  Substitution: ^free0 <- (^free2 ^free3,l1 l4)
        learn  seen  Cancellation: ^ambiguous(free)6 <- (^free2 ^free3,)
        learn  seen  Cancellation: ^ambiguous(free)6 <- (,l2 l3)
        learn  seen  Substitution: ^free0 <- (,l1 l4 l2 l3)
        step  learn  ^free5 <- (^free2,l9 l1)  incm=0  proc=8

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  v0^0  v1^1  l2,l3,l4
        inpart  -  1  INPUT  v5^5  v1^1 v2^2  l9
        inpart  -  2  INPUT  v0^0  v2^2 v3^3  l1,l4
        inpart  -  3  INPUT  v0^0  v4^4  l1,l4
        inpart  -  4  INPUT  v0^0  v1^1 v4^4  l4
        inpart  -  5  INPUT  v0^0  v1^1 v2^2 v3^3  l4
        sat  -  0  INPUT  v1^1    l1
        sat  -  1  INPUT  v5^5  v2^2  l1,l9
        sat  -  2  SplitConcrete  ^6  v2^2 v3^3
        sat  -  3  INPUT  ^11    l1,l2,l3
        sat  -  4  INPUT  v0^0  v2^2 v3^3  l1,l4
        sat  -  5  SplitConcrete  ^11  v2^2 v3^3  l1
        sat  -  6  INPUT  v0^0    l1,l2,l3,l4
        sat  -  7  CommonSubexpression  v0^0  ^6  l1,l4
        sat  -  8  INPUT  ^6    l2,l3
        solve  -  6  6  9  3  true  2;2;3;3;3;4  CommonSubexpression:1,SplitConcrete:2
        concr  -  6  2  INPUT
        concr  -  v0^0  4  INPUT
        splice  -  11  2  1  SplitConcrete  true  true  true  true
        concr  -  11  3  INPUT
        splice  -  6  2  0  SplitConcrete  true  true  true  true
        concr  -  v1^1  1  INPUT

No `unify` here; the run ends through `concrete`: `v1 <- ((|l1|))` (cancellation of
`v0 <- (v1, v2, v3, (|l4|))` against `v0 <- (^6, (|l1,l4|))` with `^6 <- (v2, v3)`), the
resolvent `^7 <- ()` (**`empty`** — NE6's "first mint is an EMPTY resolvent"), the split name
`^6 <- ((|l2,l3|))`, `v0 <- ((|l1,l2,l3,l4|))`, `^11 <- ((|l1,l2,l3|))`.

### NE6, base 1 — 16 steps, 3 split mints, no resolution: `learn x8 common:8 concrete common:7 common:1 concrete concrete concrete learn`

    NE6  base=   1 ids 1..6 supply    7: SOLVED   in   255 ms  v0 := ConcreteRho(-,Set(l2, l3, l4, l1)); v1 := ConcreteRho(-,Set(l1)); v2 := unbound; v3 := unbound; v4 := ConcreteRho(-,Set(l2, l3)); v5 := unbound
      [bound=6 residual=3 drawn=3 residual=Exists(-, [],[Part(v5^6, List(ConcreteRho(-,Set(l1, l9)), v2^3)), Part(ConcreteRho(-,Set(l2, l3, l4, l1)), List(ConcreteRho(-,Set(l1, l2, l3, l4)))), Part(ConcreteRho(-,Set(l2, l3, l4, l1)), List(Conc...]
    TRACE  records=67 steps=16 (common=3 concrete=4 learn=9) learn=24 (new=18 seen=6) byRule: Cancellation=6 CommonSubexpression=7 SplitConcrete=7 Substitution=4
    IDS    distinct=9 input=6 fresh(minted, in a step/learn record)=3 7,8,9  supply-drawn=3
    BRANCHES learn learn learn learn learn learn learn learn common:8 concrete common:7 common:1 concrete concrete concrete learn

    FIRST 40 of 40 step/learn lines (site column dropped):
        step  learn  ^free1 <- (^free2 ^free5,l4)  incm=5  proc=0
        learn  new  SplitConcrete: ^ambiguous(free)7 <- (^free2 ^free5,)
        learn  new  SplitConcrete: ^free1 <- (^ambiguous(free)7,l4)
        step  learn  SplitConcrete: ^ambiguous(free)7 <- (^free2 ^free5,)  incm=6  proc=1
        learn  new  CommonSubexpression: ^free1 <- (^ambiguous(free)7,l4)
        step  learn  SplitConcrete: ^free1 <- (^ambiguous(free)7,l4)  incm=5  proc=2
        learn  seen  Substitution: ^free1 <- (^free2 ^free5,l4)
        learn  seen  Cancellation: ^ambiguous(free)7 <- (^free2 ^free5,)
        step  learn  ^free1 <- (^free3 ^free4,l1 l4)  incm=4  proc=3
        learn  new  SplitConcrete: ^ambiguous(free)8 <- (^free3 ^free4,)
        learn  new  SplitConcrete: ^free1 <- (^ambiguous(free)8,l1 l4)
        learn  new  Cancellation: ^ambiguous(free)7 <- (^free3 ^free4,l1)
        step  learn  Cancellation: ^ambiguous(free)7 <- (^free3 ^free4,l1)  incm=6  proc=4
        learn  new  SplitConcrete: ^ambiguous(free)7 <- (^ambiguous(free)8,l1)
        learn  seen  Substitution: ^free1 <- (^free3 ^free4,l4 l1)
        learn  new  CommonSubexpression: ^free1 <- (^ambiguous(free)8,l1 l4)
        step  learn  SplitConcrete: ^ambiguous(free)8 <- (^free3 ^free4,)  incm=6  proc=5
        learn  new  CommonSubexpression: ^ambiguous(free)7 <- (^ambiguous(free)8,l1)
        learn  new  CommonSubexpression: ^free1 <- (^ambiguous(free)8,l1 l4)
        step  learn  SplitConcrete: ^ambiguous(free)7 <- (^ambiguous(free)8,l1)  incm=5  proc=6
        learn  seen  Substitution: ^ambiguous(free)7 <- (^free3 ^free4,l1)
        learn  seen  Cancellation: ^ambiguous(free)8 <- (^free3 ^free4,)
        learn  new  Substitution: ^free1 <- (^ambiguous(free)8,l4 l1)
        step  learn  ^free1 <- (^free2 ^free3 ^free4,l4)  incm=4  proc=7
        learn  new  SplitConcrete: ^free1 <- (^ambiguous(free)9,l4)
        learn  seen  CommonSubexpression: ^ambiguous(free)7 <- (^ambiguous(free)8,l1)
        learn  new  CommonSubexpression: ^free1 <- (^free2 ^ambiguous(free)8,l4)
        learn  new  CommonSubexpression: ^ambiguous(free)8 <- (^ambiguous(free)8,)
        learn  new  SplitConcrete: ^ambiguous(free)9 <- (^free2 ^free3 ^free4,)
        learn  new  Cancellation: ^free5 <- (^free3 ^free4,)
        learn  new  Cancellation: ^ambiguous(free)7 <- (^free2 ^free3 ^free4,)
        learn  new  Cancellation: ^free2 <- (,l1)
        step  common:8  Cancellation: ^free5 <- (^free3 ^free4,)  incm=9  proc=8
        step  concrete  Cancellation: ^free2 <- (,l1)  incm=8  proc=6
        step  common:7  SplitConcrete: ^ambiguous(free)9 <- (^free3 ^free4,l1)  incm=5  proc=6
        step  common:1  SplitConcrete: ^free1 <- (^ambiguous(free)7,l4)  incm=3  proc=6
        step  concrete  ^free1 <- (,l2 l3 l4 l1)  incm=2  proc=6
        step  concrete  Cancellation: ^ambiguous(free)8 <- (,l2 l3)  incm=3  proc=7
        step  concrete  Cancellation: ^ambiguous(free)7 <- (,l2 l3 l1)  incm=1  proc=7
        step  learn  ^free6 <- (^free3,l9 l1)  incm=0  proc=7

    POPULATION records (solve / inpart / sat / concr / splice):
        inpart  -  0  INPUT  v0^1  v1^2 v4^5  l4
        inpart  -  1  INPUT  v0^1  v2^3 v3^4  l1,l4
        inpart  -  2  INPUT  v0^1  v1^2 v2^3 v3^4  l4
        inpart  -  3  INPUT  v0^1  v1^2  l2,l3,l4
        inpart  -  4  INPUT  v5^6  v1^2 v2^3  l9
        inpart  -  5  INPUT  v0^1  v4^5  l1,l4
        sat  -  0  INPUT  v5^6  v2^3  l1,l9
        sat  -  1  INPUT  v1^2    l1
        sat  -  2  INPUT  ^7    l1,l2,l3
        sat  -  3  SplitConcrete  ^8  v2^3 v3^4
        sat  -  4  Cancellation  ^7  v2^3 v3^4  l1
        sat  -  5  INPUT  v0^1    l1,l2,l3,l4
        sat  -  6  INPUT  v0^1  v2^3 v3^4  l1,l4
        sat  -  7  INPUT  ^8    l2,l3
        solve  -  6  6  8  2  true  2;2;3;3;3;4  Cancellation:1,SplitConcrete:1
        concr  -  8  2  INPUT
        concr  -  v0^1  4  INPUT
        splice  -  7  2  1  Cancellation  true  true  true  true
        splice  -  8  2  0  SplitConcrete  true  true  true  true
        concr  -  7  3  INPUT
        concr  -  v1^2  1  INPUT

## 3. Which defence fires — every base, not just 0 and 1

The same 0..99 sweeps run in ONE JVM under `-Dermine.rowTrace` (one site per base), then the
trace file is summarised per site (`tools/tracestats.py <tsv> <nVars>` and
`tools/mintprov.py <tsv> <nVars>` — 40 lines of Python over the TSV; the numbers below are what
they print):

    for sd in W2 H2 NE6; do ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/traces/sweep-$sd.tsv" \
      tracker/repro/satterm/run.sh sweep $sd 0 99 10 6 > <scratch>/out/tsweep-$sd.txt; done

    W2   sites=100  steps: min=5 median=6 max=7    branch totals: learn=356 empty=100 unify=100 common=33
         sites with a unify step: 100/100   sites with an empty step: 100/100
         fresh ids in the queue per site: 1:x100   (all SplitConcrete)
         branch multiset per site:  x44 learnx3 empty unify   |  x33 learnx4 empty unify common  |  x23 learnx4 empty unify

    H2   sites=100  steps: min=12 median=13 max=17  branch totals: learn=1011 empty=100 unify=135 common=170
         sites with a unify step: 100/100   sites with an empty step: 100/100
         fresh ids in the queue per site: 2:x62 3:x38   (all SplitConcrete; 238 in total)
         branch multiset per site (top):  x43 learnx10 empty unify common  |  x14 learnx8 empty unify commonx2
                                          x12 learnx10 empty unifyx2 commonx4  |  x8 learnx13 empty unifyx2 common  |  ... (14 patterns)

    NE6  sites=100  steps: min=12 median=20 max=45  branch totals: learn=1532 concrete=402 common=158 unify=68 empty=25
         sites with a unify step: 61/100   sites with an empty step: 25/100   sites with concrete steps: 100/100 (4 at 98, 5 at 2)
         fresh ids in the queue per site: 2:x31 3:x46 4:x11 5:x5 6:x7
            by rule: SplitConcrete 286, Resolution 25 (0 unattributed);  split mints per site min=2 median=3 max=5
            x38 split=3 res=0 | x31 split=2 res=0 | x8 split=2 res=1 | x7 split=5 res=1 | x6 split=4 res=0 | x5 split=3 res=1 | x5 split=4 res=1
         branch multiset per site (top): x5 learnx14 common concretex4 | x4 learnx9 unify concretex4 | x3 learnx11 common concretex4 | ... (80 patterns)

So on W2 and H2 the kill is the SAME at every one of 100 bases: exactly one `empty` step
(`e1 <- ()`), at least one `unify` step (the singleton the erasure leaves behind — `u <- (e2)`
at 100/100 W2 bases and 72/100 H2 bases — or the link `e2 <- (u)` itself, 28/100 H2 bases),
never more than 3 split mints, never a second mint for `p`'s group (`{e1,e2}` is named exactly
once at every base of both seeds).  On NE6 the kill is `makeConcrete`: four (or five)
`concrete` steps at every base; 32/100 bases end with neither `unify` nor `empty`.

## 4. The heaviest NE6 bases

    ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/traces/trace-NE6-83.tsv" tracker/repro/satterm/run.sh trace NE6 83 10 60
      NE6 base=83 ids 83..88 supply 89: SOLVED in 499 ms  v0 := (|l2,l3,l4,l1|); v1 := (|l1|); v2 := 92; v3 := unbound; v4 := (|l2,l3|); v5 := unbound  [bound=8 residual=3 drawn=19]
      TRACE records=201 steps=45 (common=8 concrete=4 empty=1 learn=31 unify=1) learn=122 (new=65 seen=57)
            byRule: Cancellation=37 CommonSubexpression=27 Resolution=7 SplitConcrete=14 Substitution=37
      IDS   distinct=12 input=6 fresh(minted, in a step/learn record)=6 89,90,91,92,94,107  supply-drawn=19
      BRANCHES learn x23 common:94 common:94 learn learn learn common:90 learn learn learn concrete empty unify:85 common:89 common:88 common:94
               concrete concrete common:90 common:83 concrete learn learn
    ERMINE_JAVA_OPTS="-Dermine.rowTrace=<scratch>/traces/trace-NE6-8.tsv" tracker/repro/satterm/run.sh trace NE6 8 10 60
      NE6 base=8 ids 8..13 supply 14: SOLVED in 438 ms  ... v2 := 17 ...  [bound=8 residual=3 drawn=16]
      TRACE records=212 steps=45 (common=8 concrete=4 empty=1 learn=31 unify=1) learn=133 (new=64 seen=69)
            byRule: Cancellation=41 CommonSubexpression=30 Resolution=6 SplitConcrete=15 Substitution=41
      IDS   distinct=12 input=6 fresh(minted, in a step/learn record)=6 14,15,16,17,19,29  supply-drawn=16

Both are the same size — 5 split mints and 1 guarded resolution mint (`z`, from
`v0 <- (v1,(|l2,l3,l4|))` vs `v0 <- (v4,(|l1,l4|))`: `v0 <- (z,(|l1,l2,l3,l4|))`, `v4 <- (z,(|l2,l3|))`,
`v1 <- (z,(|l1|))`), 45 dequeues — with different groups (from the `SplitConcrete` definitions in
the two traces): base 83 names `{v1,v2}`, `{v1,v2,v3}`, `{v2,z}`, `{v3,u92}`, `{v2,v3}`; base 8
names `{v1,v2}`, `{v1,v2,v3}`, `{v2,z}`, `{v2,v3,z}`, `{v1,u19}`.  The tail is `concrete` /
`empty` / `unify` / `common` all the way (base 8's last 20 lines, from the trace output):

    step  concrete  Cancellation: ^free9 <- (,l1)  incm=10  proc=28
    step  empty  DeDuplication: ^ambiguous(free)16 <- (,)  incm=13  proc=21
    step  unify:10  SplitConcrete: ^ambiguous(free)17 <- (^free10,)  incm=10  proc=12
    step  common:14  SplitConcrete: ^ambiguous(free)14 <- (^ambiguous(free)17,l1)  incm=9  proc=12
    step  common:13  ^free13 <- (^ambiguous(free)17,l9 l1)  incm=8  proc=12
    step  common:19  Cancellation: ^ambiguous(free)19 <- (^ambiguous(free)17 ^free11,)  incm=7  proc=12
    step  concrete  Cancellation: ^ambiguous(free)19 <- (,l2 l3)  incm=6  proc=12
    step  concrete  Cancellation: ^ambiguous(free)15 <- (,l2 l3 l1)  incm=5  proc=11
    step  common:15  Cancellation: ^ambiguous(free)29 <- (,l2 l3 l1)  incm=4  proc=11
    step  common:15  SplitConcrete: ^ambiguous(free)15 <- (^ambiguous(free)17 ^free11,l1)  incm=3  proc=11
    step  concrete  Substitution: ^free8 <- (,l4 l2 l3 l1)  incm=2  proc=11
    step  common:15  Cancellation: ^ambiguous(free)15 <- (,l2 l3 l1)  incm=2  proc=12
    step  learn  SplitConcrete: ^free8 <- (^ambiguous(free)15,l4)  incm=1  proc=12
    (6 `seen` learn records)
    step  common:8  ^free8 <- (^ambiguous(free)17 ^free11,l1 l4)  incm=0  proc=13

(`DeDuplication: z <- ()` is `RHS.merge`'s rule: a variable occurring twice after a
substitution is forced empty.)  The 13 remaining draws at base 83 (19 − 6) and 10 at base 8
(16 − 6) are `resolution` draws that emitted nothing (7 and 6 `Resolution` learn records
respectively, from one resolvent each).

## 5. Controls (`sweep.sh <seed> 0 9 10 6`, fresh JVM per flag set; raw in `<scratch>/out/<tag>-<seed>.txt`)

**(c1) `-Dermine.genRules=nongen` — no mints at all, must SOLVE.**  W2 10/10 SOLVED (2 ms
median), H2 10/10 (5 ms), NE6 10/10 (11 ms); `drawn=0` everywhere.  Types: W2 `e1 := (||)`,
`e2 := unbound`, `p := unbound` (`bound=1`, residual 1 — `cancellation` of the two inputs
derives `e1 <- ()` without any name); H2 `e1 := (||)`, the rest unbound (`bound=1`, residual 3);
NE6 `v0 := (|l1,l2,l3,l4|); v1 := (|l1|); v4 := (|l2,l3|)` (`bound=3`, residual 3) — the
same pinned values as the default flags.

**(c2) `-Dermine.resGuard=false` (unguarded resolution) — expected not to matter on W2.**
W2 10/10 SOLVED, types and `drawn` histogram (1:x7 2:x3) identical to the default run: no
resolution premise ever has two different concrete parts.  H2 10/10 SOLVED, `drawn=3` x10,
same type patterns.  NE6 10/10 SOLVED, `drawn` 2:x1 3:x2 5:x1 6:x2 7:x1 9:x1 21:x1 25:x1 —
the worst base (8) goes from 16 draws / 6 fresh ids / 45 dequeues to **25 draws / 8 fresh ids
(5 split + 3 resolvents `z16`, `z23`, `z30`, where the guarded run mints only `z16`) / 65
dequeues** (`unify` x4: `unify:16 ... unify:23 ... unify:10 ... unify:38`), still SOLVED
in 424 ms with the same types (`trace NE6 8` under the flag; `<scratch>/out/trace-NE6-8-rgoff.txt`).

**(c3) `-Dermine.genRules=all` (the pre-`cut` rule set, CSE mints).**  W2 10/10, H2 10/10
(`drawn` identical to `cut`), NE6 10/10 (`drawn` 2:x1 3:x2 5:x1 6:x3 7:x1 13:x1 18:x1).

**(c4) `-Dermine.labelCheck=false`.**  10/10 SOLVED per seed, `drawn` histograms identical to
the default (W2 1:x7 2:x3; H2 3:x10; NE6 2:x1 3:x2 5:x1 6:x3 7:x1 13:x1 16:x1) — the label
check never fires on a satisfiable input, as it must not.

## 6. Verdicts

| seed | 0..99 (0..999) | mints per base | dequeues | what ends the loop | Lean round-n steps taken? |
|---|---|---|---|---|---|
| W2 | 100 SOLVED (1000) | 1 split, always | 5–7 | `empty` on `e1 <- ()` (100/100), then `unify` on `u <- (e2)` (100/100) | step 1 (the link) at 33/100 bases; step 2 never (0 records of the shape `p <- (e1, u, ...)` in 100 traces); step 3 never (1 fresh id per base) |
| H2 | 100 SOLVED (1000) | 2–3 split | 12–17 | `empty` (100/100) + `unify` (100/100), `common` | the hidden `p <- (e2,(|k|))` is derived first, then as W2 |
| NE6 | 100 SOLVED (1000) | 2–5 split + 0–1 resolution (max 6 ids) | 12–45 | `concrete` x4–5 (100/100); `unify` 61/100, `empty` 25/100, neither 32/100 | n/a (different seed); no run exceeds 6 fresh ids |

**Relation to the Lean.**  The trace of W2 base 0 IS the Lean's derivation up to and including
round 1's cancellation (`e2 <- (u)` is derived), and then diverges from it because
`incorporateAll` is not the additive relation: `e1 <- ()` is a `makeEmpty`, which DELETES `e1`
from every partition — including the mint's own definition — and the singleton that leaves
behind is a `unify`, which DELETES `e2`.  After those two steps the system has no constraint
with `e1` in it, so the group `{e1, u}` the next mint needs cannot arise, and the substitution
step of `W2Inv` is never enabled.  This is exactly the mechanism the brief's docstring note
names ("the real loop unifies the singleton link ... and makeEmpty erases e1 once cancellation
derives e1 <- ()"), measured: the refutation of `TerminatesOnSat` is a statement about
arbitrary productive runs of the ADDITIVE relation, and the shipped worklist's run on the same
input is not one of them.  What this directory does NOT show is a theorem — 1000 id bases of
three seeds, one loop, one flag set (plus four control sets) is the whole evidence.

## Deviations from the brief's expectations

None.  The prediction ("W2 and H2 terminate quickly, killed by unify and/or makeEmpty; NE6
terminates after a handful of mints") is what was measured, with the refinement that on W2/H2
it is BOTH defences, in the order `makeEmpty` (on `e1 <- ()`) THEN `unify` (on the singleton
`makeEmpty` leaves), at every base; and that NE6's handful is 2–6 fresh ids (max 8 with the
resolution guard off), ended by `makeConcrete`.  No seed hung and none minted more than 8 ids.
