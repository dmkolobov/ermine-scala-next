# D1 Part A — REVIEW

Target: stage `D1` **Part A** of `tracker/LOOP-MODEL-PLAN.md`; brief `tracker/loopmodel/briefs/brief-D1.md`;
report `tracker/loopmodel/D1-DESIGN.md`; new modules `tracker/lean/Rowpartition/Loop/Budget.lean` (221 lines)
and `Loop/Policy.lean` (442 lines); instrument `Loop/Main.lean` (+65).  Repo `scala3-migration`, HEAD `3991a58`,
D1's files uncommitted.  Reviewer's scratch `/home/dmitry/.claude/jobs/880c725d/tmp/review-D1/`; every command
below was re-run there.  **Nothing in the tree was edited by this review except this file.**

## VERDICT: **ADVANCE** (with the fixes of T-1…T-3 folded into Part B, and T-4…T-7 corrected in the prose)

Every load-bearing number in `D1-DESIGN.md` reproduced, most of them to the digit, on my own runs.  The two
theorems are real, the axiom audit is clean, the winner is the winner on my recount, and the one claim I
expected to break — "no policy changes a verdict" — survives for the five policies whose census finished.  The
findings are (a) three defects in the **Part B specification** (§6), which is the part of the report that has
not been tested by running anything, and (b) four prose/number slips in a report that is otherwise unusually
careful about disclosing its own gaps (§7 pre-empts most of what a reviewer would look for).

---

## 1. Rebuild and re-audit (§ method 1)

```
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition      -> Build completed successfully (863 jobs)
lake env lean Audit.lean     -> Rowpartition theorems audited: 3936; declarations using a non-standard axiom: 0
lake build looptrace         -> Build completed successfully (1668 jobs)
```

* **863 / 1668 confirmed.**  **3936 theorems, not 3935** — `D1-DESIGN.md` §5f says "3,935"; the plan's D1 row
  says 3936, which is what I measure.  0 non-standard axioms confirmed.
* `grep` over both new modules for `sorry`, `Classical`, `partial`, `axiom`, `unsafe`, `native_decide`,
  `opaque`, `implemented_by`, `admit`, `#exit`: **no hits**.  (`decide` appears three times, at
  `Policy.lean:181,185,189`, only as the `Decidable → Bool` coercion inside `natListLt`/`canonLt`/`scLt`.)
* `#print axioms` over **my own** list of every declaration in the two files — 45 of them, extracted by grep,
  matching the implementer's claimed 45 — gives 45 lines, every one either "does not depend on any axioms" or
  the three standard ones.  `diff` against the implementer's `tmp/D1/print-axioms-D1.out` (sorted): **empty**.
* `git diff --stat`: only `Rowpartition.lean` (import list + doc), `Loop/Main.lean` (the instrument),
  `LOOP-MODEL-PLAN.md`, `LOOP-MODEL-HANDOFF.md`, `briefs/brief-D1.md`.  **No pre-existing theorem module was
  touched.**  `Rowpartition/CutSearch.lean` is still out of the root import list.
* Every Lean statement paraphrased in the report matches the source — but see **T-6**: the report says they are
  quoted verbatim, and no Lean is quoted at all.
* **Every line reference in the report is exact.**  I checked all eight Lean references of §5f's table
  (`Wf.lean:331`, `RefineLearn.lean:1331`, `Dequeue.lean:79/118/50/140`, `NoConc.lean:1381`,
  `RefineConcrete.lean:637`) and all four Scala references of §6 (`Constraints.scala:543` `Q.pop`, `:583` the
  `pop` call inside `PQueue.dequeue`, `:1441` `splitConcrete`'s `fresh`, `:1887` `resolution`'s `fresh`).  Each
  points at exactly what the report says it does.

## 2. The theorems (§ method 2)

`TerminatesB d0 b s := ∃ n, Finished (runBud d0 b s n)` (`Budget.lean:69`) — the same existential
`Order.Terminates` is, as the report says.

`budget_terminates` (`Budget.lean:193`) concludes `TerminatesB s.su.drawn b s` **under exactly the ten
hypotheses of `VocFix.terminates_of_drawsAtMost`** (`VocFix.lean:1926`): the three shipped flag settings, `Wf`,
`EnvNodup`, `SupOk`, `SupFresh`, `QueueHygiene` and both `KDist`s.  So it is *not* "at any state"; it is at any
state satisfying the invariants, and `budget_terminates_of_buildQueue` (`Budget.lean:209`) discharges five of
them at a solve's own initial state, leaving `Wf`, `SupOk`, `SupFresh` and the flags — which is the right
corollary and is the one a compiler cares about.  The report states this correctly.

**Is "no a-priori fuel" honest, and does it matter?**  Yes and yes-but-bounded.  The proof's positive case *is*
`terminates_of_drawsAtMost`, whose own proof is a `by_contra` over `drawn_unbounded_of_not_terminates` — it
produces no dequeue bound, so `TerminatesB` is a bare existential.  The practical question the brief asks —
*can a budgeted solve still run forever without drawing?* — is answered **no at a solve's initial state** (the
corollary), and **not answered in general**: the budget's check fires only on `s.su.drawn`, so a hypothetical
state that dequeues forever without drawing would never trip it, and the only thing that rules that out is
`terminates_of_drawsAtMost`'s invariant machinery.  For Part B this means the budget is a *diagnostic for
divergence-by-minting*, which is the divergence the eight L5 rounds actually found; it is not a wall-clock
watchdog and does not claim to be.  That distinction is in the report (§7) but is worth one line in the user
documentation.

`budget_never_accepts` (`Budget.lean:118`): `runBud d0 b s n = .solved s' → run s n = .solved s'`, same fuel,
same final state.  Direction is right — the budget can only turn an acceptance into a rejection.  Contrapositive
gives "a shipped death survives" in the only sense that matters (it cannot become an acceptance).  `.outOfFuel`
is handled by the `n = 0` base case and by `runBud_mono`; `.died` by `stepBud_died_sys` (`Budget.lean:100`),
which splits on the budget branch (`rfl`) and defers to `Refine.step_died_sys` otherwise.
`budget_exhausted_rejects` (`Budget.lean:108`) is the explicit "exhaustion is `.rejected` with the diagnostic at
the unchanged state".

`stepBud` (`Budget.lean:55`) is `if d0 + b < s.su.drawn then .died … else step s` — one check, before the
dequeue, and nowhere else.  So the model is one dequeue coarser than the compiler's spec, exactly as §1 says;
`Draws.learnPartitions_drawn`'s `su'.drawn ≤ su.drawn + 1 + proc.elems.length` is the overshoot bound and the
report quotes it correctly.  `budgetMsg` (`Budget.lean:48`) matches the string quoted in §1 character for
character.

`runBud_eq_run` (`Budget.lean:82`) needs `∀ t, Reaches s t → t.su.drawn ≤ d0 + b`, which is the right
hypothesis.  **The flag-off claim checked by running it**: `looptrace --replay` at the defaults against
`tracker/tools/looptrace-diff.py --segments`, three groups (the brief asked for two):

| group | segments | AGREE | SKIP | hashdiff | eqdiff |
|---|---|---|---|---|---|
| `boot` | 54,199 | 54,199 | 0 | 0 | 0 |
| `top` | 92,673 | 92,673 | 0 | 0 | 0 |
| `inc/gu05_star_join_4dim_concrete_signature` | 54,235 | 54,235 | 0 | 0 | 0 |

## 3. The policy census, re-derived (§ method 3)

`gzip -t` over all 41 trace files of `tmp/L5r8/{traces,inc}/`: clean.

**(a) My own census.**  `looptrace --replay <g> --policy=<p> --fuel=3000` over **36 of the 41 groups** — `boot`,
`top` and all 34 of `inc/` (the brief asked for three including `incomplete/`) — **1,998,003 segments**, at
`shipped` and at `smallcanon`.  Compared row for row against `tmp/D1/pol-shipped.tsv.gz` and
`pol-smallcanon.tsv.gz`: **0 differing rows in either**, verdict, dequeues, `drawn` and `drawn0` alike.  On that
population shipped spends 52,942 dequeues / 1,007 loop draws and `smallcanon` 52,713 / 1,265, with **0 verdict
differences**, 417 segments differing in dequeues and 46 in draws.

**(b) An independent cross-check the implementer only ran on `boot`.**  `--policy=shipped` against the
`--depth` instrument (a different code path) over all **1,998,003** of my segments: **0 differing**
(verdict, steps, drawn, drawn0).  That is the runtime witness for `stepP_shipped` at 37x the implementer's
scale.

**(c) The whole-corpus table, recomputed from the implementer's census files with my own script**
(`tmp/review-D1/rev_analyse.py`).  Every figure of §5a reproduced:

| policy | rows | dict | dequeues | loop draws | max draw | max deq | REJ | verdict diffs |
|---|---|---|---|---|---|---|---|---|
| `shipped` | 2,301,195 | 2,301,195 | 69,207 | 1,845 | 149 | 281 | 33 | — |
| `concfirst` | 1,460,527 | 1,460,524 | 44,699 | 2,864 | 264 | 500 | 32 | **1** |
| `smallrhs` | 2,301,195 | 2,301,195 | 69,650 | 3,872 | 1,612 | 1,108 | 33 | 0 |
| `fifo` | 2,301,189 | 2,301,188 | 73,896 | 4,934 | 316 | 294 | 33 | 0 |
| `canon` | 2,301,189 | 2,301,188 | 69,953 | 1,628 | 93 | 211 | 33 | 0 |
| `smallcanon` | 2,301,195 | 2,301,195 | **68,940** | 2,485 | 328 | 381 | 33 | 0 |

and the shipped corpus census of §1 recomputed straight from `depth-shipped.tsv.gz`: **2,301,195 segments,
1,845 total loop draws, 69,207 total dequeues, 343 solves that draw at all, maximum 149** at
`gu05_star_join_4dim_concrete_signature#54234` = `core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)`.
Exact.

**(d) `analyse.py`'s aggregation.**  "Worse by > 2x" is `v > 2*b && v > b + 2` — a **+2 absolute noise floor**
that the table does not mention.  It matters for nobody here: recomputed without the floor, `smallcanon` is
still **0** solves worse by > 2x in dequeues (and `smallrhs` still 1).  TIMEOUT rows never reach the files
(`polsweep.sh`'s `awk` keeps only `pol` lines), so a truncated group is a *missing* row, not a bad one; rows
with an unparsable verdict are dropped, which is how 2,301,189 rows become a 2,301,188-key dict (one line of
`canon`'s and one of `fifo`'s was cut mid-write when `timeout` killed the process).  The one-segment-short
policies **are** compared on the full shipped total in the table, which is **T-4**.

**(e) Where `smallcanon`'s +35 % draws lands, and does "0 verdict diffs" survive on the segments that move.**
Only **134** of 2,301,195 segments draw a different number of ids, and **0 of those 134 change verdict** —
the claim holds exactly where it is hardest.  The cost is concentrated: gross increase 798 draws against 158
saved, and the **top five solves account for 306 of the 798**:

| segment | shipped deq/draws | smallcanon deq/draws |
|---|---|---|
| `gu05_star_join_4dim_concrete_signature#54234` | 281 / 149 | **381 / 328** |
| `np01_add_or_recompute#55006` | 84 / 27 | 121 / 85 |
| `Ai#72386` | 84 / 20 | 106 / 47 |
| `Ai#81482` | 105 / 24 | 98 / 47 |
| `np02_which_table_supplies_the_measure#54850` | 42 / 13 | 59 / 32 |

Against which it saves 85 dequeues on `np01_add_or_recompute#54838` (137→52), 58 on
`np05_label_column_no_escape#54711` and 58 on `gu08_label_inline#54751`.  So: yes, the +35 % is visible, and it
is visible in one place — **the corpus's hardest solve costs 1.36x the dequeues and 2.2x the draws under the
winner**.  That is the honest price of the base-invariance, and it halves the budget's headroom on the corpus
(134x → 61x).  The same solve costs `smallrhs` 1,108 dequeues / 1,612 draws and `concfirst` more than the
500-dequeue fuel; `canon` and `fifo` do not finish it in 1,800 s (see (g)).

**(f) `GU05`/`GU05MIN` at 10 of the 25 bases, re-run.**  Fixed 200-dequeue probe, my runs:

| seed | policy | draws min..max over bases 0–9 | ratio |
|---|---|---|---|
| `GU05` | `shipped` | 22 .. 245 | **11.14** |
| `GU05` | `smallrhs` | 73 .. 135 | 1.85 |
| `GU05` | `canon` | **65 .. 65** | **1.00** |
| `GU05` | `smallcanon` | **107 .. 107** | **1.00** |
| `GU05MIN` | `shipped` | 23 .. 39 | 1.70 |
| `GU05MIN` | `smallrhs` | 79 .. 114 | 1.44 |
| `GU05MIN` | `canon` | **20 .. 20** | **1.00** |
| `GU05MIN` | `smallcanon` | **78 .. 78** | **1.00** |

Identical, base for base, to `tmp/D1/seed-gu05f200*.tsv` and `seed-gu05minf200*.tsv`; the 25-base ranges the
report quotes (22…245 / 65…172 / 65…65 / 107…107, and 23…46 / 71…115 / 20…20 / 78…78) are consistent with my
10-base subsets and the extremes for `shipped`, `canon` and `smallcanon` all appear inside them.
`smallcanon` running `GU05` to completion at 10 bases: see §6 below.

Two caveats on that table which the report does not flag: `smallrhs` **SOLVES** `GU05` at bases 0, 8 and 9
within the 200 dequeues (162/173/182 steps), so its "draws@200" mixes draws-to-solution with draws-so-far; and
the tracked-seed table's "ratio" is `max/max(min,1)`, so a seed that draws 0 at some base reports 0.0 rather
than a ratio.  Neither affects the headline, because `shipped` and `smallcanon` are FUEL at all 25 bases.

**(g) The two long runs.**  `tmp/D1/logs/hard1-{canon,fifo}.log` finished while this review was running:
`HARD1 canon rc=124` and `HARD1 fifo rc=124` at 08:20, i.e. **both hit the 1,800 s cap with no output**.  §7's
claim is therefore CONFIRMED rather than provisional.

**(h) The 19 tracked seeds at 10 bases** (`tracked-analyse.py`, re-run): totals
`{shipped 2008, concfirst 4584, smallrhs 1929, fifo 3095, canon 2130, smallcanon 1860}` dequeues and
`{293, 1436, 421, 958, 300, 410}` draws, **0 verdict mismatches** — §5b to the digit — and every one of the 19
`smallcanon` rows has `min == max` in *both* draws and dequeues, so "the DEQUEUE counts are identical too" is
true as stated.

## 4. Order-independence (§ method 4)

**The greps, re-done.**  `dequeue_prio_min` occurs 4 times in the tree: its doc line
(`Dequeue.lean:19`), its statement (`:50`), **one use** (`:143`, inside `dequeue_not_of_lt`'s proof) and one
mention in `Policy.lean`'s prose.  `dequeue_not_of_lt` occurs 3 times: doc, statement, prose — **zero uses**.
`PQueue.dequeue` is unfolded outside `Loop/Dequeue.lean` in exactly three places (`Wf.lean:333`,
`NoConc.lean:1383`, `RefineLearn.lean:1333`) plus `Policy.lean:377`.  **CONFIRMED.**  `prio` does not occur at
all in `Depth.lean`, `VocFix.lean`, `NoConc.lean` or `Fragment.lean`, so the termination fragments really are
order-blind.  `solve_sound` (`Solve.lean:88`) has hypotheses `buildQueue`, three flags, `Wf`, `SupOk`,
`SupFresh` — **none mentions the order**.  CONFIRMED.

**Is `DequeueShape` enough?**  For the success path, yes: `shape_mem`, `shape_mem_or` and `shape_length_lt`
give `dequeue_mem`, `dequeue_mem_or`, `dequeue_sub` and `dequeue_length_lt` uniformly, the graph is carried
verbatim (`rest = ⟨q.elems.eraseIdx i, q.graph⟩`) so `Graph.prio` and `KDist`'s key function are untouched, and
`findRHS` reads `s.proc` and never the graph.  For the rest, see **T-3**: the `none` case is not covered, and
`kdist_dequeue` / `dequeue_unique` are not re-derived.  A Part B mirror needs those three lemmas and nothing
else — no hypothesis has to move.

**Does the shipped order have a semantic role the report missed?**  I read `Q.pop` (`Constraints.scala:543`),
`Q.insert`/`sandwich` (`:509`), the measure `PSQK`/`pr` (`:468`/`:471`), `TypeVarGraph` (`:429`),
`PQueue.findRHS` (`:614`), `PQueue.contains` (`:634`), `incorporateAll` (`:1213`), `unify`/`instantiate`
(`:1624`/`:1636`), `makeConcrete`/`destructiveSub` (`:1714`/`:1740`) and `ensureSuperset` (`:325`).

* **No rule reads the dequeue order.**  `ensureSuperset` is applied to *every* definition of `v` present in
  `incm ∪ proc` at the moment `makeConcrete` fires (`:1719-1732`), not to the first one dequeued; `unify`'s
  direction is fixed by the partition's shape (`common` → `unify(v,u)`, singleton-rhs → `unify(u,v)`), not by
  which came out first; the `common` redirect is `proc findRHS(rhs)`, a lookup, not a position.  So the
  report's reading is right: what the order changes is **which** partitions exist when, and the empirical
  answer (0 verdict differences over 2.3 M solves + 950 seed runs, including the whole `unsound0*`,
  `witness0*`, `shouldfail` and `np*` families) is the only answer available, since refutation *completeness*
  was never a theorem (S1/S2).
* **But the finger tree's ORDER is load-bearing elsewhere**, and that is the part §6b misses — see **T-2**.
  `findRHS` and `contains` are `q.split` range queries on `rhs.hashCode`/`lhs.hashCode`; they are correct only
  because `insert`'s `sandwich` keeps the tree sorted by that key.  A policy may choose a different *element*
  but must leave the remaining tree in that order.
* **A positive finding the report does not name** — see **T-11**: `smallcanon` wins partly *because* arity is
  primary.  `Dequeue.lean`'s own R5.3 result is that the `Q.++!` redirect turns a partition into a LINK
  `u <- (p.lhs)` and adds the edge `u → p.lhs`, so under the reverse-topological priority "the repair is
  scheduled last, exactly when it is needed first".  A link has arity 1, so an arity-primary order dequeues
  the repair *first*.

## 5. Design and the Part B specification (§ method 5)

**The two mint sites.**  Under the shipped flags (`genRules=cut` ⇒ `cseMints=false`; `disjunction` off), the
live `fresh` calls in the loop are exactly `Constraints.scala:1441` (`splitConcrete`, in the mint branch,
after the `splitKey`/`splitRow`/`emptyRow` guards) and `:1887` (`resolution`, **before** its guards, so a
reuse costs an id — as §1 says).  The other three are `:1974` (`commonSubexpression`, dead behind
`if (!GenRules.cseMints) Set()` at `:1972`) and `:2003`/`:2012` (`disjunction`, whose two call sites are
`if(!GenRules.disjRule) Nil`).  `PQueue.build`'s mint at `:684` is outside the loop and is correctly excluded.
**CONFIRMED, and the count `1 + proc.size` per dequeue matches `Draws.learnPartitions_drawn`.**
Stronger: the *type* rules the rest out.  `unify` (`:1624`), `makeEmpty` (`:1665`), `makeConcrete` (`:1714`)
and `destructiveSub` (`:1745`) do not take an `implicit su: Supply` at all, so they cannot mint; only
`learnPartitions` (`:1459`) does, and `instantiateType` (`Subst.scala:182`) — the one thing `unify` calls
outside `Constraints.scala` — only writes the environment.  So the budget's two wrapped sites are the complete
inventory of loop draws, not merely the complete inventory under today's flags.

**The value 20,000.**  Defensible on the model: 134x the corpus maximum (149) and 61x the winner's worst
measured solve (328 corpus / 306 `GU05` at every base).  Three things Part B must measure or say, none of
which Part A could:

1. the compiler's own worst under the SHIPPED order on the corpus is the same 149 (the corpus trace *is* the
   compiler's), but under `smallcanon` the compiler has never been run — §7 says so.  Part B's gate 8 must
   report the compiler's draw count per base for `GU05`, and Part B should additionally assert, per solve,
   that the compiler's counted draws equal the model's `drawn - drawn0` (the budget is defined in draws, and
   nothing currently gates that equality — the L2 differential gates the row *trace*, not the draw count).
2. **20,000 draws is ~110 s of wall clock at `GU05`'s 5.6 ms/draw**, PER SOLVE.  §1 says "of the order of a
   minute"; it should say *per solve*, because a module with several pathological signatures multiplies it.
3. **The budget without the policy is a footgun** and the two flags are independent.  §1's last bullet says
   this in prose ("the budget is useless without §5"); the *code* does not.  Part B should either warn when
   `solveBudget > 0 && dequeuePolicy == "shipped"`, or document that the pair is adopted together.

**The flags and the gate list.**  The two properties and the four flags-OFF gates are right, and gates 5–9 are
the right ON gates.  Missing, in descending value:

* **the `.ei` gate with the policy ON.**  §6d item 4 checks the published interfaces only with the flags OFF.
  §7 admits that *substitution identity across policies was never compared* — only verdicts.  A different order
  legitimately derives a different saturated set, and `.ei` is exactly where a different-but-equivalent
  substitution becomes user-visible (and where a *wrong* one would).  This is the highest-value gate Part B is
  missing.
* the S2 environment-fact gate (`tracker/repro/satterm/run.sh env`, the nine-case table) that S2's review made
  a tracked gate;
* `repl-smoke` / `lsp-smoke`;
* a gate that the budget's `Death` renders as a diagnostic and not as an internal error — it does
  (`Locations.scala:126` `throw Death(loc.report(...))`, caught at `session/Console.scala:220` and
  `session/TolerantCheck.scala:137`), but it renders **as a located type error**, which is worth a deliberate
  decision (**T-9**).

**The model mirror (§6c).**  Sound in outline.  Note the model already takes its flags from the CLI
(`--flags`), not from the trace, so the policy could ride the same route; putting it on the `sin` record
(`RowTrace.scala:316`) is the more robust choice, and I checked that it works: `Loop/Replay.lean:214-225`
parses `sin` as `site :: loc :: lo :: hi :: n :: blk :: bsz :: nr :: _`, so **extra trailing columns are
ignored** and old traces keep parsing.  Note `RowTrace.log` already appends a thread-id column to every record
(`RowTrace.scala:180`, stage L4), so the new fields go before it.  One thing §6c should say:
`replayPolicyOne` (`Loop/Main.lean:161`) deliberately does **not** apply the early label check, so the "0
verdict differences" of §5a are about the LOOP, not about the whole `Subst.solve`.  That is the right choice
for comparing orders and the docstring says so, but §5a does not.

## 6. Prose, acceptance, and my own long run

**`smallcanon` run to completion on `GU05`, my re-run**, `--fuel=100000`, 300 s cap, bases 0–9:
**SOLVED at every base, 414 dequeues and 306 loop draws at every base, 16–17 s each.**  Exactly the report's
"306 at every one of 25 bases"; the dequeue count (414) is a figure the report does not give and that Part B
will want, since the compiler's cost is dequeues.

**`stepP` really is `step`.**  Diffing `Policy.lean:259-304` against `Step.lean`'s `step`: the bodies are
identical character for character except the first line (`dequeuePol pol a s.incm` for `s.incm.dequeue`), and
`stepP_shipped` (`Policy.lean:306`) is `rfl`, which the build checks.  `stepPB_default` is `rfl` too.

**A1 PASS.**  Budget specified in draws, checked at the right places, `budget_terminates` /
`budget_never_accepts` / `stepBud_died_sys` / `budget_exhausted_rejects` / `runBud_eq_run` all real, audit clean,
L2 differential at the default re-verified on three groups.
**A2 PASS.**  Six policies, whole-corpus census, seeds, 25 bases; the winner meets the brief's bar
(`GU05` spread 1.00x ≤ 10x; corpus dequeues −0.39 %, not "a few percent" worse).
**A3 PASS.**  The grep is right, the shape theorem is the right abstraction, and the claim is correctly
labelled as *not yet a transport* (§7).  Docked only by T-3.
**A4 PASS with corrections.**  The design note is complete and unusually candid (§7 pre-empts most of what a
reviewer would raise); §6 is the weak part, and T-1/T-2 are real specification defects.

---

## 7. Findings, ranked

### T-1 (MEDIUM, CONFIRMED) — the Part B budget's reset hook is trace-gated, so with tracing off the counter is never reset

`D1-DESIGN.md` §6a: *"The counter is reset where `RowTrace.site` is (`Subst.solve`)"*.
`RowTrace.withSite` (`core/src/main/scala/com/clarifi/reporting/ermine/RowTrace.scala:172-178`) is
`if (!enabled) body else { save; set; try body finally restore }` — **a no-op unless `-Dermine.rowTrace` is
set**, and its only three callers are `Subst.scala:805`, `:1383`, `:1669`.  A budget counter reset there
would never be reset in a normal compile: it would accumulate across every solve in a module, and
`-Dermine.solveBudget=20000` would fire on whichever solve happened to push the module's *cumulative* draw
count past 20,000 — an arbitrary, module-size-dependent rejection of a well-typed program.  Concrete input:
`core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e` compiled with `-Dermine.solveBudget=400`
and no `-Dermine.rowTrace` — 343 corpus solves draw at all, so the counter never resets and the budget fires
at whichever solve crosses 400 cumulative, not at the one that drew 149.
**Fix.** Reset the counter at the loop's own entry (`PQueue.expand` / `Constraints.incorporateAll`'s top-level
call), unconditionally, with save/restore — `withSite` proves solves NEST — and make it a `ThreadLocal`, which
is exactly why `site0` (`RowTrace.scala:165`) is one: stage L4's parallel loader runs solves on several
threads and the trace carries a thread-id column for that reason.

### T-2 (MEDIUM, CONFIRMED) — §6b understates the Scala change: `Q.pop` is not "the whole of it" for `smallcanon`

`D1-DESIGN.md` §6b: *"`Q.pop` (`Constraints.scala:543`) is the whole of the change … A policy takes the same
`(q, graph)` and returns the same `Option[(Partition, PSQI)]`; … nothing else in `Constraints.scala` moves."*
The finger tree's measure is `PSQK = (Option[(Int, (Int, Int))], Int)` (`Constraints.scala:468`) built by
`pr` (`:471`) as `((graph.sort(lhs), (rhs.hashCode, lhs.hashCode)), 1)`, and its monoid (`:472-484`) minimises
only the FIRST component.  `pop` reads `q.measure._1.map(_._1)` — that minimum — and splits on it.
Consequences the spec does not state:

* `smallcanon`'s **primary key is the partition's ARITY**, which the measure does not carry.  Part B must
  either extend `PSQK`/`pr` with a min-arity component (which is "something else in `Constraints.scala`
  moving"), or scan the queue linearly per dequeue.  The model chose the linear scan and its own comment
  (`Policy.lean:207-210`) says why the alternative — indexing per candidate — is "the difference between
  seconds and an hour"; a linear scan still makes the loop **O(n²) in the queue**, and `GU05`'s queue reaches
  hundreds of partitions.  §6b should say which, and gate 7 (`perf-bench.sh`) should be run **with the policy
  ON**, which the gate list does not currently ask for.
* the canonical key must **not** replace `rhs.hashCode` in the tree's sort order.  `PQueue.findRHS`
  (`:614-630`) and `PQueue.contains` (`:634-637`) and `Q.insert`/`sandwich` (`:509-541`) are finger-tree RANGE
  SPLITS on `(rhs.hashCode, lhs.hashCode)`; they return wrong answers, silently, if the tree stops being
  sorted by that key.  A policy that only chooses a different element and re-joins `lhs <++> rest` is safe;
  one that re-measures the tree under a new key is not.

### T-3 (MEDIUM, CONFIRMED) — `DequeueShape` is silent on the `none` case, and `none` is exactly the acceptance branch

`Policy.lean:371` defines `DequeueShape q r rest` only for a *successful* dequeue, and `Policy.lean:345-367` /
`D1-DESIGN.md` §5f claim it is "the only thing the development's proofs ever use of `pop`" / "everything the
development's proofs use".  It is not: `stepP`'s `.done` — the model's ACCEPTANCE (`Policy.lean:259`) — is the
branch `dequeuePol pol a s.incm = none`, and nothing proves
`dequeuePol pol a q = none → q.elems = []`.  `dequeueAlt` does satisfy it (for a non-empty `es`, `withIndex es`
is non-empty, the `canon`/`smallCanon` folds return `some` after their first element, and in the `_` branch the
element achieving each minimum is in the list being filtered/`find?`ed, so `pick` is always `some i` with
`i < es.length`), so this is a MISSING LEMMA, not a bug — but it is the one the Scala mirror must not get
wrong, because a `pop` that returns `None` on a non-empty queue makes `incorporateAll` return `proc` and the
solve **accept without saturating**.  `kdist_dequeue` and `dequeue_unique` are likewise listed in the
`Policy.lean` §5 inventory but not re-derived from the shape (both are routine).
**Fix.** Add `dequeuePol_none` (three lines) plus the two derivations, and narrow §5f's claim to the success
path until they exist.

### T-4 (LOW-MEDIUM, CONFIRMED) — `canon`'s and `fifo`'s corpus rows are compared against a population they do not cover, and the shortfall is SEVEN segments, not two

`D1-DESIGN.md` §5a table and §7 bullet ("two segments short").  `pol-canon.tsv.gz` and `pol-fifo.tsv.gz` are
each 2,301,189 rows against `shipped`'s 2,301,195, and one of those rows is truncated mid-write (the
`timeout` kill), so each covers 2,301,188 segments.  The missing keys are
`gu05_star_join_4dim_concrete_signature` segments **54228 … 54234** — seven, six of them trivial and one of
them the corpus's hardest solve (`shipped`: 281 dequeues, 149 loop draws).  On the COMMON population `shipped`
spends **68,926** dequeues and **1,696** loop draws, so the like-for-like figures are

| policy | dequeues vs shipped (report) | vs shipped (common population) | draws vs shipped (report) | (common population) |
|---|---|---|---|---|
| `canon` | +1.1 % | **+1.49 %** | **−12 %** | **−4.0 %** |
| `fifo` | +6.8 % | **+7.21 %** | +167 % | **+191 %** |

§7 does say the totals are lower bounds and that `canon`'s figure "EXCLUDES the one solve that matters most",
so the fact is disclosed; the table prints the numbers unmarked and §5e's runner-up discussion leans on the
−12 %.  `smallcanon`'s and `smallrhs`'s percentages cover the full 2,301,195 and are sound as printed.

### T-5 (LOW, CONFIRMED) — "No policy changes a single verdict" is false as written: `concfirst` changes one

`D1-DESIGN.md` §5a, the bolded sentence after the table.  My recount over the 1,460,524 segments `concfirst`
covered: **1 verdict difference** — `gu05_star_join_4dim_concrete_signature#54234`, SOLVED under `shipped`,
FUEL under `concfirst`.  §5d's footnote does mention "one solve hitting the 500-dequeue fuel", so the fact is
in the report; the bolded claim is not.  §5a should also say that `concfirst`'s census ran at **`--fuel=500`**
while the other five ran at `--fuel=3000` (its `max deq` column is exactly 500), so its FUEL count is not
comparable with theirs.  Restrict the sentence to the five policies whose census finished.

### T-6 (LOW, CONFIRMED) — the report says the theorems are quoted verbatim; no Lean is quoted at all

`D1-DESIGN.md` §2: *"The two theorems the brief asks for, verbatim, are quoted in the report"*.  The only
fenced blocks in the file are the diagnostic string (§1) and the Scala flag snippet (§6).  Both theorem
statements are paraphrased — accurately, I checked each against the source — but the brief asked for verbatim
statements and the report claims to have given them.

### T-7 (LOW, CONFIRMED) — numeric and bookkeeping slips

* §5f: "`Audit.lean` **3,935** theorems".  My run of the same audit on the same tree: **3936**.  (The plan's
  D1 row already says 3936, so §5f is the outlier.)
* The plan's D1 row: "`Loop/Policy.lean`, **423** lines".  `wc -l` says **442**.
* `Rowpartition.lean`'s new doc block (line 190) lists "`concFirst`, `smallRhs`, `fifo` and `canon`" and omits
  **`smallCanon`** — the winner.
* The lemma-use table in §5f and the same table in `Policy.lean:350-356` disagree with each other, and **§5f
  is the right one**.  My raw greps over the tree excluding `Policy.lean` are 37 / 10 / 4 / 3 / 3 / 14 / 3 / 2
  for `dequeue_mem` / `dequeue_mem_or` / `dequeue_length_lt` / `dequeue_sub` / `kdist_dequeue` /
  `dequeue_unique` / `dequeue_prio_min` / `dequeue_not_of_lt`; net of each lemma's own statement and doc line
  that is **36 / 9 / 3 / 2 / 2 / 13 / 1 / 0**, i.e. §5f's table exactly.  `Policy.lean:351-354`'s
  "40 uses / 10 / 4 / 3" is the one to correct.
* `Policy.lean:366-367` says `DequeueShape` "is proved for `PQueue.dequeue` itself and for all **four**
  alternatives" — there are **five** (`concFirst`, `smallRhs`, `fifo`, `canon`, `smallCanon`), and
  `dequeuePol_shape` does cover all five.  Same late-addition slip as the `Rowpartition.lean` doc block above;
  `Policy.lean:347` likewise says "exactly **five** facts" over a list of **six** bullets.
* §5e's "**266x** reduction in the maximum" divides a COMPILER figure (81,481 draws, `L5-TERMINATION.md`
  §R8.0a) by a MODEL figure (306).  §5c labels the instruments and §7 flags that the compiler was never run
  under a policy, so the licence is stated — but the bullet should carry the same label.

### T-8 (LOW, CONFIRMED, no action) — the census sweep's `rc` column, and three groups that silently produced nothing

`polsweep.sh` uses `set -uo pipefail`, so its `rc=$?` after `timeout … | awk …` *is* the pipeline's failure and
the log's codes are genuine.  `logs/polsweep-ff.log` shows `rc=127` for `Signatures`, `RecalibratedColumns` and
`TargetList` — the `looptrace` binary was momentarily absent during a concurrent rebuild — and `rc=143` for the
`gu05` group.  The implementer noticed and re-ran the three with `patchgroups.sh`; I diffed the per-group row
counts of `pol-fifo.tsv.gz` against `pol-shipped.tsv.gz` for all 41 groups and **only `gu05` differs**, so the
merge is complete.  Recorded so the next reader does not re-open it.

### T-9 (LOW) — the diagnostic's shape

`budgetMsg` (`Budget.lean:48`) names the site, the loop's draw count, the budget and the property to turn.
`tml.die` (`parsers/src/main/scala/scalaparsers/Locations.scala:126`) wraps it in `loc.report`, and `Death` is caught by
`session/Console.scala:220` and `session/TolerantCheck.scala:137`, so it surfaces **as a located type error at
the signature**.  Two improvements for Part B: (a) say what to do — *"raise the budget with
`-Dermine.solveBudget=<n>`, or simplify the row constraints at this signature"*; (b) consider a distinct
prefix or severity, because §0's whole point is that budget exhaustion is a resource limit and NOT a verdict
about the program, and today's rendering says the opposite.

### T-10 (LOW, CONFIRMED) — "the `Supply`'s `drawn`" does not exist

`D1-DESIGN.md` §6a: *"its baseline is the `Supply`'s `drawn` at the loop's first dequeue"*.
`parsers/src/main/scala/scalaparsers/Supply.scala` has no `drawn`: it has private `lo`/`hi` that
`RowTrace.supplyBounds` (`RowTrace.scala:242`) reads by reflection, and `lo` is not a draw count across block
boundaries (`fresh` jumps to `getBlock` when a block runs out).  The mechanism the same paragraph gives first
— a counter incremented at the two wrapped **call sites** — is the one that works, and it excludes
`PQueue.build`'s mint (`Constraints.scala:684`) automatically, because that is a third call site and is not
wrapped.  Delete the baseline sentence.

### T-11 (INFO / POSITIVE) — the mechanism behind `smallcanon`'s win, which the report does not name

`Loop/Dequeue.lean`'s own R5.3 result (`Dequeue.lean:9-17`): `Q.++!` refuses to insert `p` when some
`u ∈ p.rhs` is already queued and inserts the LINK `u <- (p.lhs)` instead, and `PQueue.+` adds the edge
`u → p.lhs`, which makes `p.lhs` a CHILD of `u`; under the reverse-topological priority *"every partition of
the swallowed variable `p.lhs` is dequeued BEFORE the link that would repair it — the repair is scheduled last,
exactly when it is needed first."*  A link has **arity 1**.  An arity-primary order therefore dequeues every
repair link before the arity-≥2 partitions it repairs.  That is a structural reason to prefer arity-primary
over the graph priority, it explains why `smallrhs` and `smallcanon` both collapse `GU05`'s cost while `canon`
alone does not, and it predicts the corpus result (`smallcanon` is the only policy that *reduces* corpus
dequeues).  Worth a paragraph in §5e: it turns "the measurement said so" into a reason.

### T-12 (INFO) — what a Part B mirror needs beyond `DequeueShape`

Besides T-3's three lemmas: `QueueHygiene`, both `KDist`s, `SupOk` and `SupFresh` are all stated over
`s.incm.elems` / `s.proc.elems` / `s.su` and transport through `shape_mem` / `shape_mem_or`; the graph is
carried verbatim by every policy (`rest = ⟨q.elems.eraseIdx i, q.graph⟩`), so `Graph.prio` and `KDist`'s key
function are untouched; `findRHS` reads `s.proc` and never the graph; and `prio` occurs **zero** times in
`Depth.lean`, `VocFix.lean`, `NoConc.lean` and `Fragment.lean`, so `terminates_of_chainRun`,
`noConc_terminates` and `vocFixed_terminates` are order-blind as claimed.  One thing I checked that the report
does not mention and that turns out fine: `Aux.next`'s cache for `canon`/`smallCanon` invalidates on a graph
FINGERPRINT (node count, total edge-set size), which is sound only because `Graph.add` (`Queue.lean:94`) is
monotone in both — and `TypeVarGraph.rename` (`Constraints.scala:455`), the one operation that could keep the
fingerprint while changing the graph, has **no callers** in `Constraints.scala` and no counterpart in the
model.

### T-13 (LOW) — the budget value: what is defensible now, and what Part B must measure

20,000 is 134x the corpus maximum (149) and 61x the winner's worst measured solve (328 corpus / 306 `GU05` at
every base) — defensible **on the model**.  Three things to add:

* at `GU05`'s 5.6 ms/draw, 20,000 draws is ≈ 110 s **per solve**; §1's "of the order of a minute" should say
  *per solve*, because a module with several pathological signatures multiplies it;
* the compiler has never been run under `smallcanon`, so the compiler's own worst draw count under the winner
  is unknown.  Part B's gate 8 must report it per base for `GU05`, and Part B should additionally assert
  **per solve that the compiler's counted draws equal the model's `drawn − drawn0`** — the budget is defined
  in draws and nothing currently gates that equality (the L2 differential gates the row *trace*);
* the two flags are independent, and `-Dermine.solveBudget=20000` **alone** is a footgun: §1's own last bullet
  says GU05 would then be accepted at the fast bases and rejected at the slow ones.  Part B should warn when
  `solveBudget > 0 && dequeuePolicy == "shipped"`, or the pair should be documented as adopt-together.

### T-14 (LOW) — gates missing from §6d

In descending value:

1. **the `.ei` gate with the policy ON.**  §6d item 4 checks the published interfaces only with the flags OFF,
   and §7 admits that substitution identity across policies was never compared — only verdicts.  A different
   order legitimately derives a different saturated set, and `.ei` is exactly where a different substitution
   becomes user-visible.  This is the highest-value gate Part B is missing.
2. the S2 environment-fact gate (`tracker/repro/satterm/run.sh env`, the nine-case table), which S2's review
   made a tracked gate.
3. `repl-smoke` / `lsp-smoke`.
4. `perf-bench.sh batch` with the policy **ON** as well as off (gate 7 as written is before/after the change
   at the default), because of T-2's O(n) dequeue.
5. one line saying that `replayPolicyOne` (`Loop/Main.lean:161`) deliberately skips the early label check, so
   §5a's "0 verdict differences" is about the LOOP and not about the whole `Subst.solve`.

---

## 7b. Every number of mine that differs from the implementer's

Everything not listed here reproduced **exactly** — including all six policy rows of §5a
(dequeues / draws / max draw / max deq), the shipped corpus census of §1 (2,301,195 / 1,845 / 69,207 / 343 /
149 at `gu05…#54234`), the tracked-seed totals of §5b, the `GU05`/`GU05MIN` fixed-fuel probes of §5c(i) on the
10 bases I ran, and `smallcanon`'s 306 draws at every base.

| quantity | implementer | mine |
|---|---|---|
| `Audit.lean` theorems (§5f) | 3,935 | **3,936** |
| `Loop/Policy.lean` lines (plan row) | 423 | **442** |
| segments `canon`/`fifo` are short (§5a, §7) | "two" | **seven** (`gu05…` 54228–54234; 6 rows missing + 1 truncated) |
| `canon` corpus dequeues vs shipped | +1.1 % (vs the full 69,207) | **+1.49 %** (vs 68,926 on the population it covers) |
| `canon` corpus draws vs shipped | **−12 %** (vs the full 1,845) | **−4.0 %** (1,628 vs 1,696 on the common population) |
| `fifo` corpus dequeues / draws vs shipped | +6.8 % / +167 % | **+7.21 % / +191 %** (common population) |
| verdict differences, any policy (§5a bold) | 0 | **1** — `concfirst`, `gu05…#54234`, SOLVED → FUEL |
| lemma-use counts, `Policy.lean:351-354` | 40 / 10 / 4 / 3 | **36 / 9 / 3 / 2** — which is what §5f's own table says, so only the inline copy in `Policy.lean` is wrong |

Numbers I measured that the report does not give:

* `smallcanon` on `GU05` costs **414 dequeues** at every base (the report gives only the 306 draws), 16–17 s
  per base in the model;
* only **134** of 2,301,195 segments change their draw count under `smallcanon`, **0** of them change verdict,
  and the top five account for **306 of the 798** gross extra draws;
* shipped on the population `canon`/`fifo` cover: **68,926** dequeues, **1,696** loop draws;
* `--policy=shipped` reproduces `--depth` over **1,998,003** segments (the implementer checked 54,199);
* the L2 differential at the default also passes on `inc/gu05_star_join_4dim_concrete_signature`
  (54,235 AGREE), a third group;
* the two 1,800 s runs the report left open finished during this review: `HARD1 canon rc=124`,
  `HARD1 fifo rc=124`, no output — §7's claim is now confirmed, not provisional;
* `smallrhs` re-run on the `gu05` and `np01_add_or_recompute` groups (the brief asked for one):
  **109,250 segments, 0 differing rows** against `pol-smallrhs.tsv.gz`; the hard solve
  `gu05…#54234` is SOLVED at **1,108 dequeues / 1,612 loop draws**, 3.9x the shipped dequeues and 10.8x the
  shipped draws — which is why `smallrhs` is the runner-up and not the winner even before the base-invariance
  argument.

---

## 8. Part B recommendation

**Implement `smallcanon` and the draw budget as specified, together, both default OFF — with T-1, T-2 and T-3
folded in before any Scala is written.**  The data does not argue for a different policy, a different unit, or
a Part B without the policy.

*Why the winner is the winner, on my numbers and not only the implementer's.*  `smallcanon` is the only policy
that is simultaneously (a) base-invariant — `GU05` **306 draws / 414 dequeues at every one of the 10 bases I
ran to completion**, 16–17 s each, and 107 draws at every one of 10 bases at a fixed 200-dequeue fuel, against
the shipped order's 22…245 over the same 10 — (b) **cheaper on the corpus** (68,940 dequeues against 69,207,
the only policy that reduces them) and (c) verdict-neutral (0 differences in 2,301,195 corpus solves, 0 among
the 134 segments whose draw counts actually move, 0 in 950 seed runs).  It also has a *mechanism*, not just a
measurement (T-11): the redirect's repair link has arity 1, so an arity-primary order dequeues it first, which
is precisely the pathology `Loop/Dequeue.lean` §R5.3 documents for the shipped order.

*Why not one of the others.*  `canon` is the only rival for base-invariance and it **does not converge**: it
times out at every `GU05` base and, as this review confirmed when the two 1,800 s runs finished (`rc=124`,
both, no output), on the corpus's own instance of that system too.  Its headline −12 % corpus draws is an
artefact of that failure — on the population it actually covers it is −4.0 % (T-4).  `smallrhs` gets the cost
down but keeps a 1.85x spread over 10 bases (2.65x over 25) and is not order-canonical, so a budget set for it
is still a budget that can be hit by id base — the exact outcome §0 calls worse than slow.  `fifo` is +7.2 %
dequeues and +191 % draws on the common population; `concfirst` is intractable and is the only policy that
moved a verdict.

*Why the unit stays DRAWS.*  Dequeues have no theorem behind them — `VocFix.terminates_of_drawsAtMost` is
about `Sup.drawn`, and the missing dequeues-per-draw bound is `L5-TERMINATION.md` §R8.6b's open problem — and a
wall-clock unit would be non-deterministic and would break the L2 differential's reproducibility.  Draws is
right.  What should change is the *framing*: the budget detects **divergence by minting**, which is the
divergence eight L5 rounds actually found; it is not a watchdog, and a solve that dequeues without drawing is
outside its reach except through `budget_terminates`'s invariants.  Say that in the message (T-9) and in §2.

*The value.*  Keep 20,000 as the proposal but treat it as provisional until Part B measures the compiler.  The
winner's worst measured solve is 328 draws (corpus) and 306 (`GU05` at every base), so **any budget from 5,000
up already has ≥ 15x headroom** while cutting the worst-case wall clock proportionally — 5,000 draws is ≈ 28 s
at `GU05`'s 5.6 ms/draw against 20,000's ≈ 110 s, per solve.  The report's own criterion ("long enough that no
healthy compile is near it, short enough that the failure is a message and not a hang") argues for the smaller
end.  Have Part B report the compiler's per-base draw counts for `GU05` under the policy and then choose.

*Sequencing.*  Before the Scala: ~20 lines of Lean for T-3's `dequeuePol_none`, `kdist` and `unique`
derivations — the cheapest insurance there is, and exactly the facts the Scala mirror has to get right.  Then
the Scala, with T-1's reset moved off `RowTrace.withSite` and T-2's measure-or-scan decision made and measured.
Then the gate list of §6d plus T-14's five additions, of which the two that matter are **`.ei` with the policy
ON** (the only place a different-but-equivalent substitution becomes visible; §7 admits substitution identity
was never compared) and a **per-solve equality of the compiler's counted draws with the model's
`drawn − drawn0`** (the budget's unit is currently gated by nothing).
