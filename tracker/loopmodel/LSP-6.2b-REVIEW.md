# Review: LSP interstage item 6.2b — the pattern-binder hover hook

Reviewer's report.  Brief `tracker/loopmodel/briefs/brief-LSP-6.2b-review.md`; implementer's report
`tracker/loopmodel/LSP-6.2b-HOOK.md` (outcome PARTIAL); item of record `tracker/LSP-ROADMAP.md`
§ "Interstage item 6.2b".  Branch `scala3-migration`, HEAD `2f88b862` plus the uncommitted
deliverables.  Before build: the prepared worktree `../ermine-scala-wt-62b` (verified pre-change —
`SubstEnv.class` there carries no `binderTypes` symbol; its `tracker/repl-classpath.txt` points at
its own 5 project class directories, so the A/B measured two different builds).  No commits, no
stash; every scratch edit restored by copy and checked by md5.  Logs under
`<scratch>/review-6.2b/`.  Wall clock 13:43–15:15.

---

## VERDICT: ACCEPT WITH FIXES (R-1 … R-10 below; none blocks the merge)

The mechanism is the right one and the item proves it rather than asserting it.  Every Tier-1
identity gate re-ran EXACT on my own run.  The coverage sweep reproduces to the digit, twice.  The
refutation reproduces.

**The one number that made the item PARTIAL does not reproduce.**  On four interleaved rounds, run
alone at load 0.99–1.26, the editor round trip moved **+34.5 ms (+3.93 %)** against a budget of
**43.9 ms (5 % of my before median)** — INSIDE.  The typecheck segment moved **+30.0 ms**.  The
`read` segment moved **0.0 ms** (0.050 s on all eight runs), which is where 7.5 ms of the
implementer's +58 ms came from.  So the brief's trigger — "over budget → the hook stays OFF in
Resident and the item is PARKED" — **is not met on the reviewer's measurement**, and the hook ships
ON as the tree has it.  §5 gives both data sets side by side so the user can decide on the spread
rather than on one of them.

The fixes are corrections to the REPORT and one test-strength item.  Three of the report's numbers
are wrong (a line count, a segment total, and the list of the 14 disagreement sites), one claimed
gate result is not reproducible as stated (corpus byte-identity), one stated justification is wrong
and the exposure it dismisses is measurable (93 of 5054 local types), and one perf claim (`read`
+7.5 ms) is noise.  None of them changes what ships.

---

## 1. What I refuted, with the command and the output

### 1.1 "read +7.5 ms" (report §9b) — NOISE, refuted

`perf-bench.sh editor -k 15`, four interleaved rounds, each side from its own tree:

```
editor before r1..r4  editor_read_s = 0.050 0.050 0.050 0.050
editor after  r1..r4  editor_read_s = 0.050 0.050 0.050 0.050
```

Eight runs, one value.  `NewPipeline.readModuleTolerant` runs before the flag is armed; the
implementer said so and then carried the 7.5 ms into the +58 ms anyway.  Logs
`<scratch>/review-6.2b/perf-editor-{before,after}-{1..4}.log`.

### 1.2 "0 of 168 outputs differ" (report §8, Tier-0 table) — NOT REPRODUCIBLE AS STATED

`corpus-run.sh --batch` both sides, then normalising (a) the checkout path, (b) the progress frames
and (c) the `(N.NN seconds)` wall-clock lines — the report names only (a) and (b), and (c) is needed
too:

```
files compared: 168; differing: 21
diff cb-norm/shouldfail_der01_rename_onto_existing_column.e.out ca-norm/...
< ... Row partitions are unsatisfiable at field 'Shouldfail.Der01.b': the whole contains it but no part does
> ... Row partitions are unsatisfiable at field 'Shouldfail.Der01.b': two parts of one partition both contain it
```

THEN THE CONTROL, which is what settles it: a second run of the AFTER build against the first,
same normalisation —

```
after-vs-after: 22 differing files;  before-vs-after: 21
in A/B but not in the control: (empty)
```

Every file that differs across the A/B also differs between two runs of one build, and the control's
set is a superset.  This is the batch loader's documented run-to-run nondeterminism (a DIFFERENT
CLAUSE of the same refutation at the same field and position — `corpus-run.sh`'s own header, and the
reason `-Dermine.loadInSeries` exists), not the hook.  **Verdicts are identical: 89 LOADED / 79
REJECTED / 0 UNKNOWN of 168 on the before build, the after build and the control.**  The Tier-1
differential (below) is the gate that actually proves identity here, and it is exact.

### 1.3 The 14 disagreement sites (report §5) — the LIST is wrong

Two independent runs of the shipped tree print the same fourteen, and `Interp.e:81:14` is not among
them:

```
### 6.2b disagreements: Color.e:72:13 ;; Unsafe.e:152:19 ;; Unsafe.e:168:10 ;; Column.e:160:14 ;;
    Column.e:170:15 ;; StyleGrid.e:17:18 ;; Report.e:926:12 ;; Report.e:1593:23 ;; Op.e:181:15 ;;
    Op.e:181:17 ;; Validation.e:26:14 ;; ForeignJdk.e:328:17 ;;
    LetAndPatternMatching.e:8:17 ;; LetAndPatternMatching.e:9:17
```

`Column.e:170:15` is `fcjas x = [x]_L` in `joinAllStrict`'s `where`, the twin of `Column.e:160:14`
(`fcja x = [x]_L`) — class 2, not class 1.  So the classes are **1 / 11 / 2**, not 2 / 10 / 2, and
the alias example the report gives for `Interp.e` is not produced by this tree (`Interp.e` is one of
the three corpus modules that fail to parse, §6).  The set is STABLE across runs, which is what
makes R-4 worth doing.

### 1.4 "3 159 981 segments" (report §8a) — arithmetic

The eighteen per-group counts in the report's own table are all correct and all reproduce; they sum
to **3 210 881**, not 3 159 981.  (The brief inherited the wrong total.)

### 1.5 "+33 lines, 0 removed" in `Subst.scala` (report §7, §10) — **+41 / −0**

`git diff --numstat` says `41 0 core/.../Subst.scala`.  25 of the 41 are the doc comment the
implementer added after the Tier-1 build; the executable change is 16 lines.

### 1.6 "four properties are new" (report §6) — two are

`property(` count 49 → 51.  Three titles were rewritten in place (the two 6.2 null pins and the
sweep) and **two** are genuinely new (`a where-bound polymorphic local's LAMBDA argument shares its
letters`, `the split and the hook agree wherever both speak`).  The dead-component pin and the
cache-invisibility set were strengthened, not added.

### 1.7 The `restrictKinds` justification (report §2a) — WRONG, and the exposure is observable

The report says the asymmetry "does not reach hover, because `TolerantCheck` reads every entry
through `Subst.substType`, which applies `hm.kinds` … as they stand at that moment".  That is not a
defence: `substType` (`Subst.scala:167`) is called from `collectLocals`, i.e. AFTER the component's
inference and therefore after every `restrictKinds` (`:1017`, `:1111`, …).  The reader zonks LAST,
not first.  Probe D, over the 253 clean corpus modules:

```
== PART D: 253 clean files, 5054 local types, 93 carry an unresolved kind meta
   kind meta in Reader.e : !r -> m !a  metas=List(698751)
   kind meta in Column.e : Column !t2 !k2 v'  metas=List(776781, 776861)
```

So it is not "never yet observed" — it is observed 93 times.  It does not reach the user, because
hover renders a TYPE and the rendered strings above carry no kind; and it is inherited from
`remembered`, not introduced here.  The report should say that instead.

---

## 2. The mechanism (brief §1)

**(a) The flag.**  Every write is accounted for.  `grep -rn recordBinders --include=*.scala` gives
exactly two writes, `TolerantCheck.scala:813` and `:857`, both `if (wantLocals) hm.recordBinders =
true`, both inside a `Session.subst` block that RUNS inference.  `Session.subst`
(`Session.scala:59-60`) is `m(new SubstEnv(...))` — a fresh env per block, default `false`, so the
flag cannot leak between components or out of `checkWith`.  The third `Session.subst` in `checkWith`
(the `unbindAnnot` block) is unarmed.  `Resident` asks for `wantLocals` at exactly one place
(`Resident.scala:426`) and fast mode returns `Result(Nil, Map())` at `:418` without calling
`checkWith` at all.  `TolerantCheck.check`, `Session.loadModule`, `readModule`, the REPL, `bin/ermine`
and the loader all take the default.  CONFIRMED.

**(b) The five per-id writes.**  CONFIRMED, and the report's reason is the right one.  `unifyType`'s
two `Memory` cases store the RESULT of a recursive `unifyType`; any meta bound on the way is bound by
`instantiateType`, which IS mirrored.  `funType`'s `Memory` case reaches `instantiateType(v, Arrow(...))`
for the same reason.  `:837` and `:1019` are INSERTS keyed by a `Remember` id.  A pattern binder has
no `Memory` node and no id, so no per-id write can name an entry `binderTypes` also holds.  Note that
`instantiateType`'s only live branch is `case None` (the `Some` branch dies), so the single mirror
line covers the whole function.

**(c) The kind asymmetry.**  Refuted as argued, harmless as measured — §1.7.

**(d) The refutation, reproduced.**  One probe, two shapes (a `naive` switch that disables the three
maintenance sites — the runtime equivalent of the brief's `false &&`, chosen so one compile serves
both), `<scratch>/review-6.2b/probe-ab.log`:

```
### BUILD N: the three eager-maintenance sites DISABLED (the refuted shape)
   binder at (7,7)   recorded = a  zonked = a  [recorded type is the bare meta 46026; hm.types holds it: false]
   binder at (8,10)  recorded = a  zonked = a  [recorded type is the bare meta 46028; hm.types holds it: false]
   y at (12,10) -> a     r -> a   q -> a   c -> a   p -> a   pp2 -> a   u -> a   d -> a
   agreement: agreed=2 disagreed=List((13,8), (11,7), (18,7))

### BUILD W: the four-site shape as it ships
   binder at (7,7)   recorded = Bool  zonked = Bool  [recorded type is not a bare meta]
   y at (12,10) -> Bool  r -> Bool  q -> Bool  c -> Bool  p -> Bool  pp2 -> Bool  u -> Bool  d -> Bool
   agreement: agreed=5 disagreed=List()
```

`hm.types holds it: false` is the deciding fact, exactly as the 6.2 review's R-1 said, and the naive
shape would have shipped `y : a` for a lambda argument AND disagreed with the arity split at three
def-sites.  The founding claim is sound.

---

## 3. The merge and the agreement check (brief §2)

**(a) A false agreement EXISTS and is constructible.**  `sameUpToVarNaming` seeds `open1`/`open2`
with every free type variable of both sides, and `G1Compare.alphaEq`'s `VarT/VarT` case then binds
any two variables pairwise.  It cannot see `VarType`.  Probe E:

```
== PART E: the comparator ==
   Bound var vs SKOLEM var -> true   rendered: a vs !a
   Bound var vs FREE meta  -> true   rendered: a vs a
   f a vs !g !b            -> true
```

`a` and `!a` render differently and compare equal.  That is precisely disagreement class 2's shape
(a DECLARED type against the skolemised instance) reduced to a bare variable, so the drift alarm
UNDER-counts there.  It does not affect what the editor shows — the split wins at every compared
site — so this is R-8 (optional), not a defect in the shipped answer.

**(b) The 14 disagreements.**  List corrected in §1.3; classes 1 / 11 / 2.  I read the def-sites:
`Column.e:160:14` and `:170:15` are `fcja x` / `fcjas x` whose declared domain is
`Column (JoinReady a p d) k v` against the hook's skolemised instance — class 2, the split is right
by Decision (a).  The two `LetAndPatternMatching.e` sites deserve their own paragraph.

**THE `LetAndPatternMatching.e` PAIR IS A CORRECTNESS HOLE — in 6.2, not in 6.2b — and 6.2b makes it
VISIBLE.**  Hovering the real server over `core/examples/guide/LetAndPatternMatching.e` (my client,
`<scratch>/review-6.2b/hover.log`) now shows, in three consecutive lines of one `let`:

```
go  : List a -> a -> a      <- the local head's own type (6.2)
acc : a                     <- the arity split (6.2); the hook said Int and lost
h   : Int                   <- the hook (6.2b)
t   : List Int              <- the hook (6.2b)
```

`go (h::t) acc = go t (h * acc)` over `go xs 1`: the checker settled `acc : Int`, which is why the
hook says `Int` and why `h : Int`.  The split's `a` is not a weaker rendering of the same type, it is
a type the binder does not have, and it now sits next to two hook answers that contradict it in the
same editor view.  This was already the shipped 6.2 answer and 6.2b did not cause it, so it does not
block this item — but the implementer's follow-up 1 is REAL and should be a ticket, and the report's
framing ("a published scheme more general than the type the checker settled on … the split is right")
understates it.  A rule of the shape "prefer the hook when the split's domain is a bare type variable
and the hook's type is ground", pinned at those two def-sites, would fix it without touching classes
1 and 2.

**(c) The ceiling is not a real test.**  `TestTolerantCheck.scala`, sweep property:
`((disagreed.size <= 14) :| ...)`.  Fourteen NEW disagreements replacing fourteen old ones pass
silently — and §1.3 is a live demonstration that the SET moves while the count does not.  The set is
stable across runs (I ran the sweep twice; identical), so a set pin is feasible: see R-4.

**(d) The rank-N residual.**  The sweep asserts `misses.filterNot(m => rankN(m.split(" ").head))` is
empty, and `rankN` is fed only from `hook`'s `else` branch — i.e. `!t.mono`.  `Type.mono` is false
only for `Forall`, `Exists` and a `Memory` wrapping one (`Type.scala:265, 335, 446`), so `binderRankN`
cannot be padded by anything but a genuinely polymorphic hook type.  It IS slightly broader than the
report's "a variable bound to a rank-N constructor field" — that narrower claim is not asserted
anywhere.  I read five of the 29 at source and all five are exactly that:
`Alt.e:11 empty (Alt z p t)`, `Monad.e:10 unit (Monad u b)`, `Church.e:21 runF (F m)`,
`TypesAndRows.e:471 applyNat (Applier k)`, `Helpers.e:466 case n of Nat k ->` (the one `CaseBound`).
ADEQUATE.

**(e) The dead component.**  CONFIRMED structurally: the merge sits in the `Some` branch of
`guard(Error) { Session.subst { … } }`, the hook writes into that component's own `SubstEnv`, and a
`Death` discards both.  A neighbour that succeeds is a different `Session.subst` block with its own
map.  Pinned by `6.2: a component that died contributes no locals` (`dlam` absent), which passes.

**(f) 7.2 anchored positions on a WARM check — REPRODUCED through the real server.**  My client opens
a fixture with five lambda arguments, three `case` binders, two `do` binders, a `ConP`-nested var and
its tail, then sends a `didChange` inserting one line ABOVE everything and hovers every position again
at +1 line:

```
shifted: 0 mismatches over 33 hover positions
```

All 33 hover strings identical at the shifted positions on the warm check.

**(g) The letters (`topTwo`/`locTwo`, report §4).**  Reproduced, shipped row only:

```
topTwo p1 p2 = (tv -> p1) p2      tv : b   <- lambda arg under a TOP-LEVEL head
locTwo q1 q2 = hh q2              lv : b   <- lambda arg under a `where` head
  where hh = lv -> q1             hh : a -> b   q1 : a
```

Both `b` ✓.  The documented residual is live and visible in the same three lines: `hh : a -> b`
beside `lv : b`, where `hh`'s `a` is a third name for `q1`'s variable.  `docs/lsp.md` says so.

**(h) `do` binders.**  `d1`/`d2` answer `Bool` at def-site and at a use in my fixture; `LocalsDo.e`
is clean and its two lsp-smoke checks pass.

**(i) Fast mode → null.**  Confirmed at source (`Resident.scala:418` short-circuits before
`checkWith`) and through the two lsp-smoke checks, which pass inside the 565.

---

## 4. Coverage (brief §3) — reproduces exactly, twice

`sbt 'core/testOnly *TestTolerantCheck'`, run twice, byte-identical summary lines:

```
### 6.2b sweep: 253 clean modules of 257 — Arg(equation) 2874/2874, Arg(other) 1776/1804,
    CaseBound 116/117, DoBound 31/31, LetBound 165/165, WhereBound 92/92; misses 29;
    split-vs-hook agreed 2869 disagreed 14
[info] Passed: Total 51, Failed 0, Errors 0, Passed 51
```

5054 / 5083 (99.4 %) against 3079 / 5083 before.  Every figure in the report's coverage table
matches.

**Ten binders the hook now types, hovered through `bin/ermine-lsp` at def-site AND at a use**
(`<scratch>/review-6.2b/hover.log`; five lambda arguments, three `case` binders, two `do` binders):

```
la  9:8 -> la : Bool  | 9:14 -> la : Bool          lb 10:8 -> lb : a | 10:14 -> lb : a
ld 12:16 -> ld : Bool | 12:22 -> ld : Bool         le 13:8 -> le : Bool | 13:21 -> le : Bool
lf 13:15 -> lf : Bool | 13:27 -> lf : Bool
c1 16:9 -> c1 : Bool  | 16:15 -> c1 : Bool         c2 17:9 -> c2 : Bool | 17:15 -> c2 : Bool
c3 21:7 -> c3 : Bool  | 21:13 -> c3 : Bool
d1 28:2 -> d1 : Bool  | 29:8 -> d1 : Bool          d2 32:2 -> d2 : Bool | 33:8 -> d2 : Bool
(also h : Bool / t : List Bool for a ConP var and its tail)
```

Every rendered string is sane, and `lb : a` under `lam2 = (lb -> lb) : forall a. a -> a` shows the
letter agreement the item claims.

---

## 5. THE A/Bs — the disputed number, re-measured

Both A/Bs ran ALONE, nothing else of mine in flight, each round waiting for a one-minute load below
1.3.  BEFORE = the worktree build; AFTER = the main tree; each side invoked through its own tree's
`perf-bench.sh` so it reads its own `tracker/repl-classpath.txt`.

### (a) EDITOR — four interleaved rounds, `perf-bench.sh editor -k 15`, debounce pinned 300

| round | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| before round trip | 0.868 | 0.889 | 0.893 | 0.864 |
| after round trip | 0.917 | 0.910 | 0.905 | 0.916 |
| before typecheck | 0.495 | 0.510 | 0.505 | 0.490 |
| after typecheck | 0.540 | 0.530 | 0.530 | 0.530 |
| before / after read | 0.050 / 0.050 | 0.050 / 0.050 | 0.050 / 0.050 | 0.050 / 0.050 |

| measure | REVIEWER (4 rounds) | IMPLEMENTER (8 rounds) |
|---|---|---|
| round trip, median of medians | 0.8785 → 0.9130 = **+34.5 ms (+3.93 %)** — **INSIDE** (budget 43.9 ms) | 0.9065 → 0.9645 = +58.0 ms (+6.40 %) — OVER (budget 45.3 ms) |
| round trip, median pairwise Δ | **+35.0 ms (+3.99 %)** — **INSIDE** | +48.5 ms (+5.35 %) — OVER |
| typecheck segment | 0.500 → 0.530 = **+30.0 ms** (+6.0 % of the segment, **+3.42 % of the round trip**) | 0.5375 → 0.5725 = +35.0 ms (+3.86 % of the round trip) |
| read segment | **0.050 → 0.050 = 0.0 ms** | 0.050 → 0.0575 = +7.5 ms |
| residual | 0.028 → 0.027 | — |
| reuse | 97/154 → 97/154 | 97/154 → 97/154 |

**My round trip lands INSIDE the 45 ms / 5 % budget on both readings.**  The two data sets agree on
the number that is attributable — the typecheck segment, +30 ms against +35 ms — and disagree only on
the part that is not: the implementer's before side was 28 ms slower and their after side 52 ms
slower than mine, and 7.5 ms of their round-trip Δ sat in `read`, a phase the flag is armed after
(§1.1).  Taking both runs together, the honest statement is **the hook costs ~30–35 ms of typecheck
on the editor path, and the round-trip figure straddles the 5 % line depending on how quiet the
machine is.**

### (b) ATTRIBUTION — where the 30 ms is, and whether follow-up 2 would recover it

Scratch instrumented build (copy-edit-restore; `git stash` not used; both files restored and md5-
verified against the pre-edit copies).  ONE editor-path check of `Layout/Report.e` with the flag on,
154 components, 966 locals:

```
   instantiateType  calls=5017  meanMapSize=6  maxMapSize=17  total=8.3 ms
   unbind(Forall)   calls=5622  meanMapSize=5  maxMapSize=17  total=7.5 ms
   generalize       calls=7266  meanMapSize=5  maxMapSize=17  total=10.5 ms
   TOTAL in the three whole-map rewrites: 26.4 ms
   merge-side zonk (hooked):   calls=935  total=0.7 ms
   agreement check (alphaEq):  calls=656  total=2.4 ms
```

(Upper bounds: two `System.nanoTime` calls per site are included in the totals.)

**The map is TINY — mean 6 entries, never more than 17 — and the cost is the CALL COUNT: 17 905
guarded whole-map rewrites for 966 recorded binders.**  That is the number the user's decision turns
on:

* **Follow-up 2 (a reverse index `TypeVar -> keys`) addresses at most 8.3 of the 26.4 ms.**  It
  applies to `instantiateType`, where a single variable is bound and most of the 6-entry map does not
  mention it.  It does NOT apply to `unbind` and `generalize` (18.0 ms, two thirds of the cost),
  which substitute a whole `km`/`tm` pair into every entry by construction.  The report calls it "the
  only untried route to the +35 ms"; on these numbers it is a third of a route.
* The agreement check — `G1Compare.alphaEq` on the editor's hot path, whose only consumer is the
  corpus sweep — costs **2.4 ms**.  Real, but not the lever; see R-8.
* A cheaper mechanism would have to reduce the 17 905 rewrites, not the map.

### (c) BATCH — two interleaved rounds, `perf-bench.sh batch -n 3`, 6 reps a side

| | before | after | Δ |
|---|---|---|---|
| pooled median, wall (6 reps each) | 12.2850 s | 12.2600 s | **−0.20 %** |
| median of medians, wall | 12.2850 s | 12.2350 s | **−0.41 %** |
| pooled median, in-process | 11.4450 s | 11.3950 s | −0.44 % |

Inside the ~1 % floor and on the free side of zero, confirming the implementer (−0.12 % pooled /
−0.36 % median-of-medians).  The flag-off path is one boolean read at four sites and the batch target
cannot see it.

---

## 6. The baseline discrepancy (brief §6) — answered, and the brief's hypothesis is wrong

The corpus `corpus-run.sh --batch` covers is `core/examples/{*,Ai,Wide,Wide/shouldfail,Algebra,
Algebra/shouldfail,Time,Time/shouldfail,Present,Present/shouldfail,Lang,Lang/shouldfail,shouldfail}`
— it does NOT cover `shouldfail-controls`, `bugs`, `guide` or `incomplete`.  Counting that set at
each commit:

```
775a20f8 154      ba293897 158      fbe3d3b0 168      51629452 168      2f88b862 168
```

So `158` is the corpus at **`ba293897`** (sig-entail S0), which is exactly where
`SIG-ENTAIL-PLAN.md:185` records `88/70/0 of 158` — and that line reads **"Tier 0 off: corpus
88/70/0 of 158"**, i.e. it was measured with the entailment check OFF.  The ten files added since:

```
shouldfail/let01..let05, shouldfail/sig05_annotated_lambda   (6, REJECTED)
Lang/Corrected.e, Lang/LetSignatures.e, Time/Corrected.e, Wide/Corrected.e   (4, LOADED)
```

**The brief's guess ("the +9 REJECTED are `let01..05, sig01..05`") is wrong**: `sig01..04` were
already inside the 158 — they are what made it 158.

Today's 79 REJECTED decompose exactly: **76 = every `shouldfail` file in the covered directories,
plus 3 long-broken examples** — `Interp.e` (`error: unknown operator ==` at 24:29), `Sample.e`
(`panic: trailing virtual semicolon`) and `Yahoo.e`.  Those three have been rejecting since the
154-file era: GATE-POLICY's `85/69/0 over 154` is 66 shouldfail + those 3.  And `88/70` at 158 is
what the same corpus gives with the check OFF (three of the four `sig` pins load, `sig02` still
rejects).  Nothing is unexplained and nothing regressed.

**THE BASELINE THE ROADMAP SHOULD CARRY: `corpus-run.sh --batch` = 89 LOADED / 79 REJECTED /
0 UNKNOWN of 168, with the shipped `sigEntail=error` default.**  `tracker/LSP-ROADMAP.md:14` and
`tracker/SIG-ENTAIL-PLAN.md:185` should be annotated: the 88/70/0-of-158 figure is a check-OFF
measurement of a smaller corpus and is not comparable.  (Implementer's follow-up 4, CONFIRMED, with
the reason.)

---

## 7. Gates I re-ran, with the figure and the log

### Tier 1 — all of it, in parallel per GATE-POLICY

| gate | result | log |
|---|---|---|
| `LOOPTRACE_PAR=3 looptrace-corpus.sh`, BOTH sides | 18/18 groups, every one `rc=0 timeouts=0 dropped=0`, model `agree` = `segments`, `skip=0`; `incomplete` 1 905 718 segments both sides | `<scratch>/review-6.2b/lt-{before,after}.log` |
| `trace-ab.py`, ALL record kinds, per group | **18 of 18 IDENTICAL, `sinmoved 0`, concrete identities 0**, over **3 210 881** segments | `trace-ab-*.log` |
| path normalisation, audited | per group, `lines containing ermine-scala-wt-62b` == `lines changed by the rewrite` (boot 147 089 = 147 089; incomplete 5 150 087 = 5 150 087; …) and the AFTER side contains the substring **0** times.  A field scan over every matching boot line shows the substring occurs **only in column 3**, the `loc` field, and in no other column of any record kind | `trace-ab-2.log`, inline |
| `ei-diff.sh --snapshot --batch` `-Dermine.loadInSeries=true`, BOTH sides | **274 interfaces captured on BOTH** (no lost chunks), `0 of 274 interfaces differ`, `bindings by verdict: {'identical': 3523}` | `ei-{before,after}.log`, `ei-classify.log` |
| `g1-validate.sh` | **9/9 PASS**, `129 files, 1447 signatures, EQUIVALENT`, `no drift from tracker/g1-baseline`, rc 0 | `g1.log` |

Not one `Supply` draw moved and not one record of any kind differs over 3.2 million solves.  The
flag is off in batch and batch observes nothing.

### Tier 0

| gate | expected | measured |
|---|---|---|
| `core/compile core/copyResources` | clean | clean |
| `TestLoopTrace` | 720/720 | **720 solves, 720 segments, 720 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0` |
| targeted suites (8 patterns) | green | **157 properties, 0 failed, 0 errors** |
| `TestTolerantCheck` alone | 51 | **51/51**, twice |
| `corpus-run.sh --batch` both sides | verdicts + byte-identity | **89/79/0 of 168 on BOTH**; byte-identity NOT reproducible as stated — §1.2 |
| `repl-smoke.sh` | 8 groups, goldens clean | **8/8 PASS**, `git status` shows no golden touched |
| `lsp-smoke.sh` | 551 + 14 | **PASS lsp (565 checks)**, the two flipped 6.2 pins answering `r : Bool` |
| boot | 129 modules | **`Ermine session ready: 129 modules in 11.8s`** |
| `.ei` by `find` | 0 | **0** outside `tracker/g1-*` |
| `git diff --stat --histogram` vs `-w` | equal | **451/92 both** |
| line endings | preserved | all ten touched/added files LF now and LF at HEAD (`grep -cU $'\r'` = 0 on both sides) |

### Tier 2

`sbt -batch -J-Xmx3g core/test`, ALONE, started at load 0.48:

```
[info] Passed: Total 1063, Failed 0, Errors 0, Passed 1063     wall 1363 s (22m43s)
```

1063 is 1061 + the two new `TestTolerantCheck` properties, exactly as predicted.  Neither documented
intermittent (E12 `TestInterfaceRoundTrip`, E13 `TestLegend`) fired; no re-run was needed.

---

## 8. R-items

| # | severity | file:line | the one-line change |
|---|---|---|---|
| **R-1** | report | `LSP-6.2b-HOOK.md` §7 table, §10 first bullet | `+33 lines, 0 removed` → **`+41 / −0`** (16 executable, 25 comment). |
| **R-2** | report | `LSP-6.2b-HOOK.md` §8a table, last row | `3 159 981` → **`3 210 881`** (the per-group numbers are right and reproduce). |
| **R-3** | report | `LSP-6.2b-HOOK.md` §5, classes 1 and 2 | Replace `Interp.e:81:14` with **`Column.e:170:15`** and move it to class 2; the classes are **1 / 11 / 2**.  The shipped tree does not produce `Interp.e:81:14` (that module fails to parse). |
| **R-4** | test | `scalacheck-binding/.../TestTolerantCheck.scala`, sweep property, `((disagreed.size <= 14) :| …)` | Pin the SET, not the count: keep `val knownDisagreements = Set("Color.e:72:13", …14 strings…)` and assert `disagreed.toSet == knownDisagreements`, the way `misses` is already checked against `rankN`.  The set is stable across runs (verified twice); the count is not a test — §1.3 is a live case of the set moving while the count held. |
| **R-5** | report | `LSP-6.2b-HOOK.md` §2a, last paragraph | The reason given is wrong (the reader zonks AFTER `restrictKinds`, not before) and the exposure is measurable: **93 of 5054** local types carry an unresolved kind meta.  Say that, and that it is invisible because hover renders no kinds. |
| **R-6** | report | `LSP-6.2b-HOOK.md` §9b, the `read` row and the "+23 ms sits in read and residual" sentence | Drop it: `read` was 0.050 s on all eight of my runs, both sides. |
| **R-7** | report | `LSP-6.2b-HOOK.md` §8 Tier-0 table and bookkeeping note 2 | `0 of 168 outputs differ` → **verdicts identical (89/79/0), .out text carries the documented batch-loader nondeterminism**: 21 of 168 differ after three normalisations, and a same-build control differs on 22 (a superset).  A third normalisation, the `(N.NN seconds)` lines, is also required and unmentioned. |
| **R-8** | optional | `TolerantCheck.scala`, `sameUpToVarNaming` | The comparator cannot distinguish a `Bound` var from a `Skolem` (`a` vs `!a`), so class-2 disagreements whose whole type is a bare variable are counted as agreements.  If the alarm is meant to be tight, compare `v.ty` in the `VarT/VarT` case before binding. |
| **R-9** | optional | `Subst.scala:1136-1138` / `TolerantCheck.scala` `keyOf` | `binderTypes` is keyed by `(line, column)` with no file name: the WRITER accepts any `Pos`, the READER filters on `p.fileName == file`.  Unreachable today (one module per `SubstEnv`), silent if it ever becomes reachable.  Either key on the file too, or say in the field comment that the single-module invariant is what makes the key safe. |
| **R-10** | report | `LSP-6.2b-HOOK.md` §6, "four properties are new" | **Two** are new (49 → 51); three titles were rewritten in place. |

None of these is a stop.  R-4 is the only code/test change I would ask for before the item is closed;
R-1..R-3, R-5..R-7 and R-10 are report corrections; R-8 and R-9 are notes for whoever touches this
next.

## 9. The implementer's follow-ups

1. **CONFIRMED, and stronger than stated.**  The two `LetAndPatternMatching.e` sites are not "the
   split is right and the hook is more informative" — the split's `a` is not a type `acc` has, and
   6.2b has now put two contradicting hook answers (`h : Int`, `t : List Int`) in the same three
   lines of the editor.  Worth its own ticket against 6.2's arity split.
2. **PARTLY REFUTED.**  A reverse index addresses 8.3 of the 26.4 ms (§5b); `unbind` and `generalize`
   carry the other 18.0 ms and a reverse index does not apply to them.  It is not "the only untried
   route" to the cost, and it is not the largest part of it.
3. **CONFIRMED and now OBSERVED** — 93 of 5054 (§1.7).  Still not user-visible.
4. **CONFIRMED**, with the reason and the corrected arithmetic (§6).

## 10. The cost of parking, checked against the tree

Should the user park it anyway: `checkWith` gains a second parameter (or a `-Dermine.lsp.binderHook`
default-off probe) that `Resident` leaves unset and `TestTolerantCheck` sets — the map, the four
sites, the merge, the agreement check and the sweep all stay, and the flag-off path is what Tier 1
already proves byte-identical.  Of the 16 lsp-smoke checks this item added, **13 would have to go
back to asserting null** (11 new hover checks plus the two flipped 6.2 pins); the `LocalsDo.e clean`
check and the two fast-mode null checks survive unchanged.  `docs/lsp.md`'s coverage paragraph
reverts, and the editor answers null on **1975** of the corpus's 5083 local binders again.  On my
numbers that buys back ~30 ms of a ~0.88 s round trip.

## 11. NOT CHECKED

* §9c's cheaper placement (the substitution at `restrictTypes`) and its `14 → 251` measurement — not
  rebuilt, not reproduced.  I did confirm by reading that `generalize` rewrites entries to the
  scheme's Bound variables, which makes the argument plausible.
* §4's first two table rows (no `generalize` maintenance; scope = the enclosing binding).  Only the
  SHIPPED row was reproduced.
* The `binderRankN` class was argued from `Type.mono` and spot-checked at 5 of 29 def-sites; the
  other 24 are taken from the sweep's own assertion.
* The lsp-smoke fast-mode null pins and the two flipped `case`-binder pins were verified only as part
  of the 565-check run, not individually re-executed.
* The interface sweep beyond `274 captured` and `0 of 274 differ` — I did not audit per-chunk
  timeouts.
* `repl-smoke`'s 66 individual checks (the 8 group PASSes were read, not the check bodies).
* Anything about the 2.11 back-port, the REPL, or `bin/ermine` timing.
* Whether the 93 unresolved kind metas can reach ANY rendering path — I checked the hover strings the
  sweep and my client produce, not every printer.
* The implementer's own gate logs were read for context (`<scratch>/6.2b/`) but every figure in §7
  above is from my own run.

## 12. Housekeeping

No JVM of mine is running (the only `java` process on the box is the user's two-day-old bloop
daemon).  No `.ei` outside `tracker/g1-*`.  The scratch probe source is deleted; `Subst.scala` and
`TolerantCheck.scala` are restored by copy and md5-identical to their pre-instrumentation state; the
tree was recompiled afterwards.  `tracker/tools/__pycache__/` (created by my client importing
`lsp-client.py`) is removed.  `../ermine-scala-wt-62b` shows only its deliberate
`tracker/repl-classpath.txt`, and it is LEFT IN PLACE — remove it with `git worktree remove --force`
when the item is closed.  `git status --short` in the main tree shows exactly the implementer's seven
modified files, `LSP-6.2b-HOOK.md`, `LocalsDo.e`, the brief, and this report.
