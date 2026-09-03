# measure: does the shipped row solver show any sign of non-termination on WELL-TYPED input, and how does its work grow?

Date 2026-09-02, machine shared (12 cores, 15 GB). Everything below was measured from scratch in this run; nothing is inherited from the interrupted first attempt (its scratch directory had been wiped; `tracker/tools/rowclosure.py` and `tracker/lean/Rowpartition/DefaultTerm.lean` on disk belong to other task keys and were not touched).

## 0. Setup (every command)

Toolchain and flags, identical for every run (the shipped defaults: `genRules=cut`, `labelCheck=true`, `labelCheckEarly=true`, `resGuard=true`, all read from `Constraints.GenRules`, Constraints.scala:715-777; nothing overridden):

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Xmx2g -Dermine.rowTrace=runs/<tag>.tsv" \
  timeout 120 bin/ermine <file> </dev/null > runs/<tag>.out 2>&1        # one JVM at a time
```

* Runner `run.sh` (this directory): waits until `free -g` reports >= 4 GB available, refuses if another `java … ermine.session.Console` is running, deletes only `.ei` files the run created (none were: `useInterface=false`), records wall / rc / verdict / boot seconds / module seconds to `runs/RUNS.tsv`. Verdict from the output text: `Unable to load module` = REJECTED, `Importing module 'X' (s seconds)` = LOADED, rc 124 = TIMEOUT.
* Driver `driver.sh`: sequential, 120 s timeout per run, stops walking a family once a run's wall exceeds 90 s.
* Instances: `python3 tracker/tools/gen-row-stress.py --out rowstress --from 2 --to 14`; `python3 tracker/tools/gen-row-overlap.py --out rowprobe --costar-to 9`; `python3 tracker/tools/gen-res-star.py --out resprobe --star-to 10`.
* Baseline boot with no file: wall 13.98 s, `Loaded 129 modules (12.79 seconds)`, 54,199 `solve` records, 373 of them with a partition. Per-run boots ranged 10.91–12.79 s; "wall−boot" = wall minus the program's own boot figure, "module s" = the `Importing module 'X' (s seconds)` figure for the file (this is the number to compare across sizes; it excludes JVM start, boot and exit).
* Trace analysis `analyze.py` / `table.py` / `dump.py` / `fit.py` (this directory). A segment = all `step`/`learn`/`in`/`ex`/`inpart`/`sat` records up to a `solve` record; a segment belongs to the module iff the solve's `loc` names the module file. Cross-check column `unattributed` = (post-boot solves with >0 partitions whose loc does NOT name the module) / (post-boot solves): it is `0/…` for every run, so no constrained solve escaped attribution. Columns:
  * `input parts / saturated / derived` = sums of the `solve` record's `nParts / nSat / nDerived` (nSat is the size of `q.expand`, i.e. the saturated set after all deletions);
  * `Resolution firings (new)` / `SplitConcrete firings (new)` = `learn … new` records by provenance (rule applications whose conclusion was not already present); "seen" firings (re-derivations, discarded) are reported in the text where they matter;
  * `MINT Res` / `MINT Split` = fresh ids: an id that first appears in a `learn` record (not in the inputs, not in any earlier step/learn record), attributed to the provenance of the record that introduced it (within one `learnPartitions` batch — a Set logged in arbitrary order — minting provenances are ordered first; before that fix 5 SplitConcrete ids were being credited to the CSE-reuse record that consumed them). `resolution` calls `fresh` even in its reuse branch (Constraints.scala:1199); an id that never enters a partition is not counted;
  * `ids in sat` = distinct variable ids in the module's `sat` records, `new ids in sat` = those not among the inputs (= minted ids that survive to the saturated set);
  * `dequeues` = `step` records = `incorporateAll` iterations (the work measure); `max solve sat / mints` = the largest single solve.
* Machine conditions: during the first four runs another agent's `rowclosure.py` held 9–11 GB and one core (my driver waited in the memory guard for ~2 min; `avail` column of `runs/RUNS.tsv`); afterwards ≥ 8 GB were free. Timing noise from repeats: gu05 7.06 → 7.68 s, ResStar8 15.46 → 17.69 s, with bit-identical counts (the solver is deterministic; treat module times as ±15 %).

## 1. Generator families under the default flags

Column legend as above. Tables are generated from `runs/ALL.tsv` (`python3 table.py <tags>`); the verdict is the program's own text.

### 1.1 RowStress (gen-row-stress.py: N left-nested `join`s, no concrete labels)

All 13 sizes LOADED, module time 0.02 s (N=2) → 0.55 s (N=14). Zero mints at every N (no concrete labels: `splitConcrete` and `resolution` have no premise; CSE's fresh branch is off under `cut`, and its reuse/fold branches fire — 16 new CSE derivations at N=3 — without minting). Growth of the saturated set is EXACTLY quadratic: 10, 23, 39, 58, 80, 105, 133, 164, 198, 235, 275, 318, 364 has first differences 13,16,19,…,40 and constant second difference 3, i.e. nSat(file) = 1.5N² + 5.5N − 7 (residual 0 at all 13 sizes); the largest single solve is (3N+4)(N−1)/2: 5, 13, 24, …, 299, second difference 3. Dequeues equal nSat (each partition is processed once). Module time: log-log slope 1.66 (upper half 1.85), successive ratios 1.15–1.50 and falling — polynomial, between quadratic and cubic. (`fit.py "2:10 3:23 … 14:364"`, `fit.py "2:0.02 … 14:0.55"`.)

### 1.2 gen-row-overlap.py (CoStar m = 3..9, PartStar 4..6, Overlap1/2, OverlapHalf, Chain4/8; no concrete labels)

All 15 LOADED in 0.04–0.08 s of module time. Under `cut` this whole family derives NOTHING: `derived = 0` for every CoStar/PartStar/Overlap probe, the saturated set is the input (nSat = nParts = 2m for CoStar m: the m per-call signature solves of `g` at one partition each, plus the probe's m constraints at `inferImplicitBindingTypes`; see table), zero mints, dequeues = inputs. Reason: the co-star right-hand sides share subsets that nothing names (the probe has no constraint whose RHS is exactly a shared set), so CSE's reuse/fold branches have no `Names` witness and the only branch that would fire — the fresh mint — is the one `cut` removed. Chain4/Chain8 (disjoint joins) derive 8/16 CSE reuse partitions, no mints. Growth in m: linear (successive nSat differences 2, log-log slope 1.00). CoStar8, 175.7 s under `genRules=all` in the docstring's 2026-08-31 table, is 0.06 s here; CoStar9 0.07 s. The family was walked to 9 without triggering the stop rule; walking further is pointless — the rule set does nothing on it.

### 1.3 ResStar (gen-res-star.py: m single-label projections of one row `a <- (x_i, (|f_i|))`, satisfiable) — THE HEADLINE

| m | module s | saturated (single probe solve) | Resolution firings new / seen | Substitution new / seen | Cancellation new / seen | fresh ids (Res) | surviving new ids | 2^m − m − 1 |
|---|---|---|---|---|---|---|---|---|
| 2 | 0.05 | 5 | 3 / 0 | 2 / 0 | 0 / 2 | 1 | 1 | 1 |
| 3 | 0.04 | 19 | 12 / 11 | 14 / 4 | 2 / 15 | 4 | 4 | 4 |
| 4 | 0.07 | 65 | 44 / 112 | 89 / 21 | 2 / 95 | 11 | 11 | 11 |
| 5 | 0.22 | 211 | 119 / 815 | 421 / 157 | 23 / 473 | 27 | 26 | 26 |
| 6 | 0.63 | 665 | 344 / 4,969 | 1,992 / 715 | 76 / 2,250 | 61 | 57 | 57 |
| 7 | 2.55 | 2,059 | 859 / 28,433 | 8,145 / 4,054 | 357 / 9,463 | 125 | 120 | 120 |
| 8 | 15.46 | 6,305 | 2,424 / 158,489 | 35,161 / 20,374 | 1,283 / 40,887 | 320 | 247 | 247 |
| 9 | 91.67 | 19,171 | 6,449 / 825,557 | 144,669 / 78,763 | 3,442 / 168,843 | 519 | 502 | 502 |
| 10 | TIMEOUT (120 s; 107.9 s after boot) | mid-solve: 19,325 dequeues | 796,893 learn records | 220,782 | 170,857 | ≈509 so far | – | 1,013 |

(Firing counts are per file = the probe solve, since the m helper-signature solves derive nothing; full rows in section 6.)

Growth, from `fit.py` on the file totals:
* saturated partitions 7, 22, 69, 216, 671, 2066, 6313, 19180: successive ratios **3.14, 3.14, 3.13, 3.11, 3.08, 3.06, 3.04** — exponential with base 3 (nSat ≈ c·3^m; log-log slope 5.3 and rising, so not polynomial);
* surviving minted ids 1, 4, 11, 26, 57, 120, 247, 502 = **2^m − m − 1 exactly** — one fresh variable per concrete key K ⊆ {f_0..f_{m−1}}, |K| ≥ 2, on the lhs `a`: the guard's per-variable bound is attained;
* fresh ids 1, 4, 11, 27, 61, 125, 320, 519: the excess over 2^m−m−1 (0, 0, 0, 1, 4, 5, 73, 17) are resolutions whose lhs is one of the x_i (e.g. `x2 <- (z', f1 f3)` at m=4) minting a name for a row already named under `a`; they are identified later by cancellation/unify (`unify: 2`, `common: 249` step branches at m=9). The guard's lookup is keyed per lhs and covers `proc`, `incm` and the current batch (Constraints.scala:941-951), so these are not guard misses on `a`;
* dequeues 7, 22, 69, 222, 691, 2112, 7436, 19467 (≈ 3^m) but derivations ≈ 3^m · 2^m: at m=9 the 19,458-step solve produced 154,560 new and 1,073,163 "seen" (already present, discarded) derivations, 77 % of them Resolution re-derivations. Re-derivation is where the time goes: module time ratios 0.8, 1.75, 3.1, 2.9, 4.1, 6.1, 5.9 → asymptotically ≈ 6× per extra label, i.e. time ≈ nSat^1.6;
* SplitConcrete: 0 firings at every m (no constraint ever has two abstract parts — every RHS is a single variable plus labels — so its premise never occurs).
* ResStar10, run with the 120 s cap after the family stopped at 9 (91.7 s > 90 s), TIMES OUT mid-solve: 19,325 dequeues, 1,188,532 learn records (Resolution 796,893, Substitution 220,782, Cancellation 170,857), ≈509 fresh ids so far against 1,013 expected — the continuation of the same curve (projection ≈ 6 × 92 s ≈ 550 s), not a new phenomenon. `runs/ResStar10.tsv` is the unterminated trace (171 MB).
* Gadget (the unsatisfiable seed, not well-typed): REJECTED in 0.86 s after boot — refuted by the early label check before saturation, as designed. Included only for completeness; the task is about satisfiable input.

### 1.4 What this is and is not
Everything the default rule set did on these three families is bounded by the label lattice on one variable: 2^m keys → 2^m − m − 1 minted names, 3^m partitions (pairs (K, J ⊆ K)), and ~6^m work from re-checking. There is no run whose derivation count kept growing without the saturated set growing, and no run in which SplitConcrete minted at all. Growth is exponential in the NUMBER OF LABELS projected from one row (m = |L| here) and polynomial (quadratic) in the number of chained joins. I make no claim about termination from this; the numbers are what they are.

## 2. The six `.slow` divergers plus gu01/gu05 (core/examples/incomplete), default flags, re-measured

All eight LOADED. Module times: gu02 0.16 s, gu03 0.18 s, gu07 0.33 s, gu09 0.23 s, np05a 0.08 s, np05c 0.26 s, gu01 0.15 s, gu05 7.06 s (repeat 7.68 s). The README's figures (>60 s / >60 s / >60 s / >60 s / 280 s / – / 23 s / 24 s) were under `genRules=all`; under the shipped defaults the star-join chains (gu01/02/03/09, np05a) mint nothing at all — they are exactly the RowStress shape (gu02 = RowStress8's numbers 133/91, gu03 = RowStress9's 164/116, gu01 = RowStress7's 105/69, gu09 240/168) — and the label-carrying modules mint modestly: gu07 17 Res + 33 Split fresh ids over 93 constrained solves (largest solve 107 partitions, 21 mints), np05c 10 Res + 29 Split over 31 solves (largest 73 partitions, 16 mints). gu05 is the corpus maximum: one `mkSimplified-extinct` solve at gu05…e(62:1) with 12 inputs (18 partitions) saturating to 1,372 partitions after 3,199 dequeues, 436 fresh ids (367 Resolution, 69 SplitConcrete) of which only 60 survive to the saturated set (the rest are concretised/unified away: 81 `concrete`, 346 `empty`, 380 `common`, 12 `unify` dequeues), with 50,062 new Substitution, 3,145 new CSE-reuse, 1,483 new Resolution, 661 Cancellation and 554 SplitConcrete derivations, and 45,694 "seen" re-derivations. That 7 s is the price of the same per-key lattice on a 4-dimensional concrete signature: 23 Resolution and 156 SplitConcrete partitions survive.

## 3. Per-solve maxima over everything run ("distance from the cliff")

* Largest single solve by saturated size: **ResStar9, 19,171 partitions** (from 9 inputs) at `resprobe/ResStar9.e(1:1)`, site `inferImplicitBindingTypes`; then ResStar8 6,305; ResStar7 2,059; **gu05 1,372** (corpus maximum, `core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)`, site `mkSimplified-extinct`); ResStar6 665; RowStress14 299.
* Largest single solve by fresh ids: **ResStar9, 519** (502 survive); then **gu05, 436** (60 survive); ResStar8 320; ResStar7 125.
* Largest corpus solve by dequeues: gu05 3,199; next gu03 124, gu07 178 (within-file max), np05c 140.
* Everything else in the corpus and the two label-free families stays under 300 saturated partitions and 21 mints per solve.

## 4. The headline, isolated and traced

The only super-polynomial growth under the default flags is ResStar's, and the only time-out is ResStar10 (its predictable continuation). Smallest instances: ResStar3 (3 inputs → 19 partitions, 4 mints, 77 step/learn records, complete trace in `trace-ResStar3.txt`) and ResStar4 (4 inputs → 65 partitions, 11 mints; first 60 of 428 step/learn lines in `trace-ResStar4.txt`; produced with `python3 dump.py runs/ResStar4.tsv ResStar4.e 60`). Reading the ResStar3 trace (`^F` = free input variable, `^A` = ambiguous fresh variable):

```
step  learn  a <- (x0, f0)                      incm=2 proc=0
step  learn  a <- (x2, f2)                      incm=1 proc=1
learn new  Resolution: a  <- (z1, f2 f0)        <- MINT z1 (key {f0,f2})
learn new  Resolution: x2 <- (z1, f0)
learn new  Resolution: x0 <- (z1, f2)
step  learn  Resolution: x2 <- (z1, f0)          -> Substitution: a <- (z1, f2 f0)   (seen later)
step  learn  Resolution: x0 <- (z1, f2)          -> Substitution: a <- (z1, f0 f2)
step  learn  Resolution: a <- (z1, f2 f0)        -> Cancellation x0/x2 (seen)
step  learn  a <- (x1, f1)                      incm=0 proc=5
learn new  Resolution: x2 <- (z3, f1)          |
learn new  Resolution: z1 <- (z2, f1)          |  three pairs (x1 vs x0, x2, z1)
learn new  Resolution: x0 <- (z4, f1)          |  -> MINT z2 {f0,f1,f2}, z4 {f0,f1}, z3 {f1,f2}
learn new  Resolution: a  <- (z2, f1 f2 f0)    |
… (from this dequeue on, every dequeue is a Resolution/Substitution/Cancellation conclusion re-deriving
   the others: dequeues 5–19 of 19 produce 23 new vs 30 seen learn records)
```

Where the growth is: **Resolution** mints — exactly one name per key, 2^m − m − 1 — and the **non-generative rules** (Substitution 9,523 and Cancellation 3,322 of the 19,162 surviving derived partitions at m=9, against 6,317 Resolution) fill in `x_J <- (z_K, K \ J)` for every J ⊂ K, which is the 3^m; the re-derivation of all of those against each new partition is the ~6^m time. **SplitConcrete contributes nothing** on this family, and on the corpus it is the minor minter (gu05 69 vs 367; gu07 33 vs 17 — the only file where split out-mints resolution, at 33 fresh ids total).

## 5. Files

All under `/tmp/claude-1000/-home-dmitry-research-ermine/8ad54026-1a3a-4b68-a018-ea52aca01453/scratchpad/satterm/measure/`: `run.sh`, `driver.sh`, `analyze.py`, `table.py`, `dump.py`, `fit.py`; instances `rowstress/`, `rowprobe/`, `resprobe/`; `runs/RUNS.tsv` (49 runs incl. boot0 and the two repeats), `runs/ALL.tsv` (the full table), `runs/<tag>.{out,txt,tsv}` (824 MB of traces; ResStar9.tsv 181 MB, ResStar10.tsv 171 MB), `runs/DRIVER.log`; `table-rowstress.tsv`, `table-rowprobe.tsv`, `table-resstar.tsv`, `table-corpus.tsv`; `trace-ResStar3.txt`, `trace-ResStar4.txt`; `tables.md`. Nothing in the repository was modified (the `M` entries in `git status` predate this task and belong to other work); no `.ei` files were created.

## 6. Full run tables (from `runs/ALL.tsv`)

### rowstress

| tag | wall s | wall−boot s | module s | verdict | solve calls | …w/ parts | input parts | saturated | derived | Resolution firings (new) | SplitConcrete firings (new) | MINT Res | MINT Split | ids in sat | new ids in sat | dequeues | max solve sat | max solve mints | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RowStress2 | 13.4 | 1.17 | 0.02 | LOADED | 10 | 2 | 6 | 10 | 4 | 0 | 0 | 0 | 0 | 12 | 0 | 10 | 5 | 0 | 0/14 |
| RowStress3 | 13.2 | 0.91 | 0.03 | LOADED | 16 | 3 | 12 | 23 | 11 | 0 | 0 | 0 | 0 | 23 | 0 | 23 | 13 | 0 | 0/22 |
| RowStress4 | 14.0 | 1.27 | 0.04 | LOADED | 22 | 4 | 18 | 39 | 21 | 0 | 0 | 0 | 0 | 34 | 0 | 39 | 24 | 0 | 0/30 |
| RowStress5 | 12.9 | 0.90 | 0.05 | LOADED | 28 | 5 | 24 | 58 | 34 | 0 | 0 | 0 | 0 | 45 | 0 | 58 | 38 | 0 | 0/38 |
| RowStress6 | 12.7 | 0.94 | 0.07 | LOADED | 34 | 6 | 30 | 80 | 50 | 0 | 0 | 0 | 0 | 56 | 0 | 80 | 55 | 0 | 0/46 |
| RowStress7 | 12.9 | 1.01 | 0.13 | LOADED | 40 | 7 | 36 | 105 | 69 | 0 | 0 | 0 | 0 | 67 | 0 | 105 | 75 | 0 | 0/54 |
| RowStress8 | 13.0 | 0.99 | 0.15 | LOADED | 46 | 8 | 42 | 133 | 91 | 0 | 0 | 0 | 0 | 78 | 0 | 133 | 98 | 0 | 0/62 |
| RowStress9 | 12.2 | 0.99 | 0.18 | LOADED | 52 | 9 | 48 | 164 | 116 | 0 | 0 | 0 | 0 | 89 | 0 | 164 | 124 | 0 | 0/70 |
| RowStress10 | 12.4 | 1.08 | 0.22 | LOADED | 58 | 10 | 54 | 198 | 144 | 0 | 0 | 0 | 0 | 100 | 0 | 198 | 153 | 0 | 0/78 |
| RowStress11 | 13.0 | 1.11 | 0.27 | LOADED | 64 | 11 | 60 | 235 | 175 | 0 | 0 | 0 | 0 | 111 | 0 | 235 | 185 | 0 | 0/86 |
| RowStress12 | 12.9 | 1.18 | 0.36 | LOADED | 70 | 12 | 66 | 275 | 209 | 0 | 0 | 0 | 0 | 122 | 0 | 275 | 220 | 0 | 0/94 |
| RowStress13 | 13.6 | 1.32 | 0.45 | LOADED | 76 | 13 | 72 | 318 | 246 | 0 | 0 | 0 | 0 | 133 | 0 | 318 | 258 | 0 | 0/102 |
| RowStress14 | 12.9 | 1.42 | 0.55 | LOADED | 82 | 14 | 78 | 364 | 286 | 0 | 0 | 0 | 0 | 144 | 0 | 364 | 299 | 0 | 0/110 |

### overlap

| tag | wall s | wall−boot s | module s | verdict | solve calls | …w/ parts | input parts | saturated | derived | Resolution firings (new) | SplitConcrete firings (new) | MINT Res | MINT Split | ids in sat | new ids in sat | dequeues | max solve sat | max solve mints | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CoStar3 | 12.7 | 0.87 | 0.05 | LOADED | 46 | 4 | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 15 | 0 | 6 | 3 | 0 | 0/58 |
| CoStar4 | 13.2 | 1.16 | 0.04 | LOADED | 74 | 5 | 8 | 8 | 0 | 0 | 0 | 0 | 0 | 24 | 0 | 8 | 4 | 0 | 0/90 |
| CoStar5 | 12.5 | 0.86 | 0.04 | LOADED | 110 | 6 | 10 | 10 | 0 | 0 | 0 | 0 | 0 | 35 | 0 | 10 | 5 | 0 | 0/130 |
| CoStar6 | 12.3 | 0.86 | 0.05 | LOADED | 154 | 7 | 12 | 12 | 0 | 0 | 0 | 0 | 0 | 48 | 0 | 12 | 6 | 0 | 0/178 |
| CoStar7 | 12.4 | 0.90 | 0.07 | LOADED | 206 | 8 | 14 | 14 | 0 | 0 | 0 | 0 | 0 | 63 | 0 | 14 | 7 | 0 | 0/234 |
| CoStar8 | 12.6 | 0.90 | 0.06 | LOADED | 266 | 9 | 16 | 16 | 0 | 0 | 0 | 0 | 0 | 80 | 0 | 16 | 8 | 0 | 0/298 |
| CoStar9 | 12.5 | 0.90 | 0.07 | LOADED | 334 | 10 | 18 | 18 | 0 | 0 | 0 | 0 | 0 | 99 | 0 | 18 | 9 | 0 | 0/370 |
| PartStar4 | 12.6 | 0.88 | 0.05 | LOADED | 130 | 5 | 8 | 8 | 0 | 0 | 0 | 0 | 0 | 44 | 0 | 8 | 4 | 0 | 0/154 |
| PartStar5 | 12.5 | 0.85 | 0.04 | LOADED | 164 | 6 | 10 | 10 | 0 | 0 | 0 | 0 | 0 | 53 | 0 | 10 | 5 | 0 | 0/190 |
| PartStar6 | 13.6 | 0.95 | 0.05 | LOADED | 198 | 7 | 12 | 12 | 0 | 0 | 0 | 0 | 0 | 62 | 0 | 12 | 6 | 0 | 0/226 |
| Overlap1 | 12.9 | 0.88 | 0.05 | LOADED | 104 | 9 | 16 | 16 | 0 | 0 | 0 | 0 | 0 | 41 | 0 | 16 | 8 | 0 | 0/138 |
| Overlap2 | 12.6 | 0.88 | 0.05 | LOADED | 134 | 9 | 16 | 16 | 0 | 0 | 0 | 0 | 0 | 50 | 0 | 16 | 8 | 0 | 0/170 |
| OverlapHalf | 12.5 | 0.92 | 0.08 | LOADED | 170 | 9 | 16 | 16 | 0 | 0 | 0 | 0 | 0 | 56 | 0 | 16 | 8 | 0 | 0/202 |
| Chain4 | 12.0 | 0.92 | 0.04 | LOADED | 42 | 1 | 12 | 20 | 8 | 0 | 0 | 0 | 0 | 24 | 0 | 20 | 20 | 0 | 0/66 |
| Chain8 | 11.8 | 0.86 | 0.06 | LOADED | 74 | 1 | 24 | 40 | 16 | 0 | 0 | 0 | 0 | 48 | 0 | 40 | 40 | 0 | 0/122 |

### resstar

| tag | wall s | wall−boot s | module s | verdict | solve calls | …w/ parts | input parts | saturated | derived | Resolution firings (new) | SplitConcrete firings (new) | MINT Res | MINT Split | ids in sat | new ids in sat | dequeues | max solve sat | max solve mints | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ResStar2 | 12.0 | 0.86 | 0.05 | LOADED | 32 | 3 | 4 | 7 | 3 | 3 | 0 | 1 | 0 | 8 | 1 | 7 | 5 | 1 | 0/38 |
| ResStar3 | 12.2 | 0.86 | 0.04 | LOADED | 46 | 4 | 6 | 22 | 16 | 12 | 0 | 4 | 0 | 14 | 4 | 22 | 19 | 4 | 0/54 |
| ResStar4 | 12.1 | 0.90 | 0.07 | LOADED | 60 | 5 | 8 | 69 | 61 | 44 | 0 | 11 | 0 | 24 | 11 | 69 | 65 | 11 | 0/70 |
| ResStar5 | 12.6 | 1.03 | 0.22 | LOADED | 74 | 6 | 10 | 216 | 206 | 119 | 0 | 27 | 0 | 42 | 26 | 222 | 211 | 27 | 0/86 |
| ResStar6 | 12.7 | 1.47 | 0.63 | LOADED | 88 | 7 | 12 | 671 | 659 | 344 | 0 | 61 | 0 | 76 | 57 | 691 | 665 | 61 | 0/102 |
| ResStar7 | 14.4 | 3.39 | 2.55 | LOADED | 102 | 8 | 14 | 2066 | 2052 | 859 | 0 | 125 | 0 | 142 | 120 | 2112 | 2059 | 125 | 0/118 |
| ResStar8 | 27.4 | 16.27 | 15.46 | LOADED | 116 | 9 | 16 | 6313 | 6297 | 2424 | 0 | 320 | 0 | 272 | 247 | 7436 | 6305 | 320 | 0/134 |
| ResStar9 | 103.6 | 92.47 | 91.67 | LOADED | 130 | 10 | 18 | 19180 | 19162 | 6449 | 0 | 519 | 0 | 530 | 502 | 19467 | 19171 | 519 | 0/150 |
| ResStar10 | 120.1 | 107.85 | ? | TIMEOUT | 102 | 10 | 10 | 10 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 10 | 1 | 0 | 0/124 |
| Gadget | 12.1 | 0.86 | ? | REJECTED | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 |

### corpus

| tag | wall s | wall−boot s | module s | verdict | solve calls | …w/ parts | input parts | saturated | derived | Resolution firings (new) | SplitConcrete firings (new) | MINT Res | MINT Split | ids in sat | new ids in sat | dequeues | max solve sat | max solve mints | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gu02 | 12.1 | 0.98 | 0.16 | LOADED | 46 | 8 | 42 | 133 | 91 | 0 | 0 | 0 | 0 | 78 | 0 | 133 | 98 | 0 | 0/62 |
| gu03 | 12.4 | 0.99 | 0.18 | LOADED | 52 | 9 | 48 | 164 | 116 | 0 | 0 | 0 | 0 | 89 | 0 | 164 | 124 | 0 | 0/70 |
| gu07 | 12.3 | 1.14 | 0.33 | LOADED | 448 | 93 | 173 | 426 | 261 | 53 | 96 | 17 | 33 | 313 | 25 | 622 | 107 | 21 | 0/590 |
| gu09 | 12.2 | 1.04 | 0.23 | LOADED | 68 | 11 | 72 | 240 | 168 | 0 | 0 | 0 | 0 | 131 | 0 | 240 | 124 | 0 | 0/96 |
| np05a | 11.8 | 0.88 | 0.08 | LOADED | 20 | 3 | 16 | 36 | 20 | 0 | 0 | 0 | 0 | 37 | 0 | 36 | 22 | 0 | 0/30 |
| np05c | 12.4 | 1.09 | 0.26 | LOADED | 163 | 31 | 95 | 284 | 203 | 31 | 74 | 10 | 29 | 165 | 23 | 451 | 73 | 16 | 0/226 |
| gu01 | 12.1 | 0.96 | 0.15 | LOADED | 40 | 7 | 36 | 105 | 69 | 0 | 0 | 0 | 0 | 67 | 0 | 105 | 75 | 0 | 0/54 |
| gu05 | 19.0 | 7.89 | 7.06 | LOADED | 26 | 5 | 30 | 1392 | 1304 | 1483 | 554 | 367 | 69 | 100 | 60 | 3219 | 1372 | 436 | 0/36 |

### repeats

| tag | wall s | wall−boot s | module s | verdict | solve calls | …w/ parts | input parts | saturated | derived | Resolution firings (new) | SplitConcrete firings (new) | MINT Res | MINT Split | ids in sat | new ids in sat | dequeues | max solve sat | max solve mints | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gu05 | 19.0 | 7.89 | 7.06 | LOADED | 26 | 5 | 30 | 1392 | 1304 | 1483 | 554 | 367 | 69 | 100 | 60 | 3219 | 1372 | 436 | 0/36 |
| gu05-rep2 | 21.2 | 8.57 | 7.68 | LOADED | 26 | 5 | 30 | 1392 | 1304 | 1483 | 554 | 367 | 69 | 100 | 60 | 3219 | 1372 | 436 | 0/36 |
| ResStar8 | 27.4 | 16.27 | 15.46 | LOADED | 116 | 9 | 16 | 6313 | 6297 | 2424 | 0 | 320 | 0 | 272 | 247 | 7436 | 6305 | 320 | 0/134 |
| ResStar8-rep2 | 31.3 | 18.56 | 17.69 | LOADED | 116 | 9 | 16 | 6313 | 6297 | 2424 | 0 | 320 | 0 | 272 | 247 | 7436 | 6305 | 320 | 0/134 |