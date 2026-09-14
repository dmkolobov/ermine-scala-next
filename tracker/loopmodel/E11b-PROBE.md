# Item E11b (probe) — does the PROVED non-generative canonicaliser collapse the E11 SET class?

**Measurement only. No source and no other tracker file changed.**  Scripts and logs live in
`<scratch>/e11b/` where `<scratch>` =
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad`.
Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `b3da015e`.
Lean library used as built (`lake env lean --run`; no `lake build`, no file added under
`tracker/lean/Rowpartition/`).

---

## 1. The answer

**None of the genuine SET-class pairs collapse. Zero of six.**

I converted every SET-class pair I could recover from the E11a sweeps into the Lean
`Rowpartition.State` type and ran `canonN` (fuel 2000) on both sides of each pair.

| | bindings | pairs (one per sweep) |
|---|---|---|
| ran | 9 | 31 |
| the two variants normalise to the SAME system (up to renaming existentials) | **3** | 5 |
| the two variants normalise to DIFFERENT systems | **6** | 26 |

and the three that come out SAME **were already the same before `canonN` ran**: their two
renderings differ only in the order of the constraints, the order inside a right-hand side, or
the letters given to existentials — exactly the FORM class that item E11a already fixed.  The
comparison "input vs input" and "normal form vs normal form" gives the identical verdict on all
31 pairs (`<scratch>/e11b/cmp2.log`): **`canonN` changes no verdict at all.**

Stronger, and this is the headline: on the six bindings that genuinely differ, **`canonN` does
not fire a single rule.**  Every one of those twelve systems is *already* a normal form for the
six non-generative rules — `stepFn` returns `none` on the input (`normal=True/True` in
`<scratch>/e11b/cmp.log`, and the constraint counts in and out are equal).  The canonicaliser is
not "almost enough"; on this class it is a no-op.

**What is missing.**  Two things, and neither is a matter of tuning the six rules:

1. **Definitional substitution** — folding or unfolding one partition inside another.  This is
   one of the two rules `Canonical.lean`'s header explicitly lists as NOT implemented
   ("Cancellation and definitional substitution are NOT implemented").  It is what every one of
   `lookbackJoin`, `reportFor`, `joinCumRet`, `joinTotalValue` and `investmentTableData` needs:
   in each of them the leftover difference is one constraint that is the *same* constraint with
   a sub-partition written folded on one side and unfolded on the other.  `absorb` is the
   degenerate case of this rule (it only unfolds a variable whose whole definition is a concrete
   label set); the general case is not there.
2. **Existential projection** — in `reportFor` the extra conjunct on one side mentions an
   existential that occurs nowhere else.  Deleting it is sound only *because the variable is
   existentially quantified*; as a constraint system over all variables the two sides are not
   equivalent, so no model-preserving rule can ever delete it.  The Lean development has no
   notion of which variables are bound by the scheme's `exists`, so this is outside what
   `Canonical.lean` can express today, not merely outside what it implements.
   (`cutoffGroupedFldsPosNegRel'` additionally needs the inverse of a *generative* step — one run
   carries a variable whole where the other carries it split in two — which is a third, harder
   thing again; see §5.4.)

So the answer to the brief's question "if yes for all, E11b is a port of a proved algorithm" is:
**no.**  Porting the six proved rules to Scala would be a correct and cheap piece of hygiene (and
§7 says where it goes and what it would buy), but it would move the SET count by zero.

---

## 2. What I ran on, and one correction to the brief

The brief points at `<scratch>/e11a/set-pairs.txt`.  That file is **truncated**: it is nine
single lines, each holding only the *first* physical line of only the *first* rendering
(`wc -c` = 925 bytes; the `forall` header and nothing else).  It is unusable as an input.

The implementer's raw sweep files are intact, so I took the pairs from them instead.  A record
there is `TAG \t file \t binding \t renderingA \t renderingB \n`, and the renderings do contain
embedded newlines, so my parser splits the file at line-starts matching a known tag
(`<scratch>/e11b/parse.py`).  Five sweeps carry SET records:

| sweep | build | SET records |
|---|---|---|
| `sweep-before.tsv` | pre-E11a | 8 |
| `sweep-after.tsv` | E11a before the review fix round | 7 |
| `sweep-after2.tsv` | E11a, fix round | 6 |
| `sweep-after3.tsv` | E11a, fix round | 5 |
| `sweep-canonall.tsv` | E11a with canonicalisation at every generalisation | 5 |

Nine distinct bindings over the five sweeps, 31 pairs in all — the same nine the truncated
`set-pairs.txt` names.  That covers five of the six members of §4's final target list
(`cutoffGroupedFldsPosNegRel'`, `reportFor`, `investmentTableData`, `joinCumRet`,
`joinTotalValue`) plus `lookbackJoin`, which is in the list on the runs where it appears.

**Three members of the review's union I could NOT get cheaply, and did not run**:
`Layout/Report.e:drilldownKeyValueTable2`, `incomplete/RevenueShare.e:shareOfGroup`,
`incomplete/np01_add_or_recompute.e:inferredRestate`.  Only the sweep TSVs carry renderings, and
none of the five has a SET record for any of the three; the review's own logs
(`<scratch>/review-e11a/rev-ttc1.log`, `rev-ttc2.log`, `core-test-rev.log`) and
`<scratch>/e11a/logs/ttc2.log` print def-site NAMES only, not the two forms.  Getting them means
re-running the property with a patched printer, which is a compiler run and outside this probe's
budget.

---

## 3. How the conversion works, and how I compared

### 3.1 Rendering → Lean `State` (`<scratch>/e11b/conv.py`)

A published scheme prints as `forall <binders>. (exists <binders>. c1, ..., cn) => body`.  I take
the constraint list and:

* **drop class constraints** (anything without `<-`: `RelationalComb rel`, `PrimitiveNum a`,
  `AsOp opl`, ...) — they are not row constraints and are not in the Lean language.  Every
  dropped constraint is listed per case in `<scratch>/e11b/conversions-all.txt` so a reader can
  check nothing row-shaped was thrown away;
* **number the variables.**  Universals are numbered by NAME and shared between the two variants
  (they are the same variables on both sides).  Existentials are numbered per side, so the
  comparison has to find a bijection;
* **labels** become `Nat`s (`Label = Nat` in `Basic.lean`), shared across both sides;
* `a <- (b, c, (|Foo, Bar|))` becomes `⟨a, [b, c], {Foo, Bar}⟩`; several concrete parts in one
  right-hand side are unioned into the single `conc` field; a variable-only right-hand side gets
  `conc = ∅`;
* **a CONCRETE left-hand side** — `(|adjClose, initValue|) <- ((|adjClose|), c, d)`, which really
  does occur — has no home in Lean's `Constraint` (its `lhs` is a `Var`).  I give each distinct
  concrete row a proxy variable `{...}` with the extra constraint `proxy <- ((|...|))`, which
  pins it, and add the same proxies to BOTH sides with the SAME number.  A proxy is treated as a
  universal (a constant cannot be renamed).  This is faithful: the proxy is determined by its
  defining constraint, so the models of the original variables are unchanged.

Both converted systems are printed back for every case in
`<scratch>/e11b/conversions-all.txt`, next to the original renderings in
`<scratch>/e11b/pairs/*.txt`, so the conversion is checkable by eye.

### 3.2 Running the canonicaliser

`<scratch>/e11b/build.py` emits one Lean file, `<scratch>/e11b/run.lean`, with 86 `State`
definitions and a `main` that prints `canonN 2000 s` for each.  Run:

```
export PATH=$HOME/.elan/bin:$PATH
cd tracker/lean && lake env lean --run <scratch>/e11b/run.lean
```

exit 0, empty stderr, output `<scratch>/e11b/run.out` (`run.err` is 0 bytes).  Each block prints
the `solved` list, whether `stepFn` says the result is a normal form, and the constraints.
Sanity check that the harness is wired up correctly: `<scratch>/e11b/t1.lean` reproduces
`Canonical.lean` §13's worked example exactly (`0 <- [1] + [7]`, `2 <- [] + [7]`, solved
`[(5,6)]`).

Fuel was never near binding: the deepest reduction anywhere was **two** steps, and `stepFn`
returned `none` on every one of the 86 results.

### 3.3 Comparing two normal forms

`<scratch>/e11b/cmp.py` searches for a bijection that is the identity on universals and on
concrete proxies and maps A's existentials onto B's, matching constraints as
`(lhs, multiset of right-hand variables, concrete set)` — i.e. up to permutation of the
right-hand side, which is how `dedup` and `common` already read a constraint.  The `solved`
pairs are matched too, as unordered equations.

The matcher backtracks at BOTH levels (which constraint pairs with which, and which right-hand
variable pairs with which).  This matters: my first version committed to the first working
right-hand-side pairing and reported "no bijection" on four of the twelve controls — the exact
defect the E11a review found in `ei-classify.py` and `G1Compare.alphaEq` (review, "The 47",
point (i)).  The numbers below are from the backtracking version.

### 3.4 Control

The brief asks for a pair the FORM sweep now renders identically.  Those bindings are not
recorded in the sweep TSVs at all (only differing ones are), and running the canonicaliser on two
byte-identical inputs proves nothing anyway.  I used a sharper control instead: **twelve
FORM-class pairs** drawn at random from `sweep-before.tsv`'s 129 — pairs whose two renderings
differ but whose constraint SET is known to be the same.  If the tooling is right, all twelve
must come out SAME.

**All twelve are SAME** (`<scratch>/e11b/cmp.log`, the `CTRL` rows), including two
(`melt3Full`, `melt3FullViaDeduped`) where `canonN` deleted three permuted-duplicate constraints
on each side first, and one (`yearFrac365Full`) where it deleted one.  Sizes range from 0 to 22
constraints.

---

## 4. Results, per pair

`<scratch>/e11b/cmp2.log`.  "in" is the converted input size (including the concrete proxies),
"nf" the normal-form size; "INPUT" is the same bijection test applied to the inputs, before
`canonN`.

| case | in A/B | nf A/B | INPUT | NORMAL FORM | canonN changed the verdict? |
|---|---|---|---|---|---|
| before:cutoffGroupedFldsPosNegRel' | 28/28 | 28/28 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| before:level1 | 5/5 | 5/5 | SAME | SAME | no |
| before:lookbackJoin | 8/9 | 8/9 | DIFFERENT (8 vs 9) | DIFFERENT (8 vs 9) | no |
| before:runningTotalFull | 21/21 | 19/19 | SAME | SAME | no |
| before:runningTotalFullViaWritten | 23/23 | 21/21 | SAME | SAME | no |
| before:reportFor | 1/2 | 1/2 | DIFFERENT (1 vs 2) | DIFFERENT (1 vs 2) | no |
| before:investmentTableData | 17/19 | 17/19 | DIFFERENT (17 vs 19) | DIFFERENT (17 vs 19) | no |
| before:joinTotalValue | 7/8 | 7/8 | DIFFERENT (7 vs 8) | DIFFERENT (7 vs 8) | no |
| after:cutoffGroupedFldsPosNegRel' | 28/28 | 28/28 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| after:lookbackJoin | 8/9 | 8/9 | DIFFERENT (8 vs 9) | DIFFERENT (8 vs 9) | no |
| after:runningTotalFull | 21/21 | 19/19 | SAME | SAME | no |
| after:runningTotalFullViaWritten | 23/23 | 21/21 | SAME | SAME | no |
| after:reportFor | 1/2 | 1/2 | DIFFERENT (1 vs 2) | DIFFERENT (1 vs 2) | no |
| after:investmentTableData | 21/19 | 21/19 | DIFFERENT (21 vs 19) | DIFFERENT (21 vs 19) | no |
| after:joinTotalValue | 10/9 | 10/9 | DIFFERENT (10 vs 9) | DIFFERENT (10 vs 9) | no |
| after2:cutoffGroupedFldsPosNegRel' | 28/28 | 28/28 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| after2:lookbackJoin | 9/8 | 9/8 | DIFFERENT (9 vs 8) | DIFFERENT (9 vs 8) | no |
| after2:reportFor | 1/2 | 1/2 | DIFFERENT (1 vs 2) | DIFFERENT (1 vs 2) | no |
| after2:investmentTableData | 19/20 | 19/20 | DIFFERENT (19 vs 20) | DIFFERENT (19 vs 20) | no |
| after2:joinCumRet | 9/10 | 9/10 | DIFFERENT (9 vs 10) | DIFFERENT (9 vs 10) | no |
| after2:joinTotalValue | 10/10 | 10/10 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| after3:cutoffGroupedFldsPosNegRel' | 28/28 | 28/28 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| after3:reportFor | 1/2 | 1/2 | DIFFERENT (1 vs 2) | DIFFERENT (1 vs 2) | no |
| after3:investmentTableData | 18/16 | 18/16 | DIFFERENT (18 vs 16) | DIFFERENT (18 vs 16) | no |
| after3:joinCumRet | 10/8 | 10/8 | DIFFERENT (10 vs 8) | DIFFERENT (10 vs 8) | no |
| after3:joinTotalValue | 8/8 | 8/8 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| canonall:cutoffGroupedFldsPosNegRel' | 28/28 | 28/28 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| canonall:reportFor | 1/2 | 1/2 | DIFFERENT (1 vs 2) | DIFFERENT (1 vs 2) | no |
| canonall:investmentTableData | 19/18 | 19/18 | DIFFERENT (19 vs 18) | DIFFERENT (19 vs 18) | no |
| canonall:joinCumRet | 9/9 | 9/9 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |
| canonall:joinTotalValue | 9/9 | 9/9 | DIFFERENT (no bijection) | DIFFERENT (no bijection) | no |

Per binding: `level1`, `runningTotalFull`, `runningTotalFullViaWritten` SAME (and SAME already on
the input); `cutoffGroupedFldsPosNegRel'`, `lookbackJoin`, `reportFor`, `investmentTableData`,
`joinCumRet`, `joinTotalValue` DIFFERENT on every sweep that records them.

**Where a rule fired at all.**  Only on `runningTotalFull` (21→19), `runningTotalFullViaWritten`
(23→21) and three of the twelve controls.  In every case the rule was `dedup` deleting a
constraint that was a duplicate of another *up to permutation of its right-hand side* — the
second of the two known Scala defects that `Canonical.lean` §12 names.  `occurs`, `selfDedup`,
`absorb`, `unify` and `common` fired **zero times in the whole probe**.  (`absorb` cannot fire on
this data: the only fully-concrete definitions present are the proxies I invented for concrete
left-hand sides, and a proxy never appears on anyone's right-hand side.)

---

## 5. The six that do not collapse — what is left over

For each DIFFERENT pair I searched for the *smallest* number of constraints that have to be set
aside on each side before a bijection exists (`<scratch>/e11b/leftover.py`, log
`<scratch>/e11b/leftover.log`).  The pattern is remarkably uniform.

### 5.1 `Relation.e:lookbackJoin` — one leftover, always

```
after:lookbackJoin   |A|=8 |B|=9   minimal leftover 1:  only in B:  h <- (c, i, r)
after2:lookbackJoin  |A|=9 |B|=8   minimal leftover 1:  only in A:  t <- (c, h, r)
before:lookbackJoin  |A|=8 |B|=9   minimal leftover 1:  only in B:  t <- (c1, g, r)
```

One variant is the other plus one conjunct.  Derivation in §6.

### 5.2 `Present/WriterOutputs.e:reportFor` — one leftover, an unused existential

```
A:  a <- (b) + (|pMinValue, pRegion, pTitle|)
B:  a <- (b) + (|pMinValue, pRegion, pTitle|)
    a <- (c) + (|pMinValue, pRegion|)                 <- only in B
```

`c` occurs in no other constraint.  `B` says: `a` contains `pMinValue` and `pRegion`, and the
rest is `c`.  That follows from `A` — `c` can only be `{pTitle} ⊎ b` — **but only because `c` is
existentially quantified**.  Read as a constraint system over all variables, `A` does not entail
`B`'s second conjunct: an assignment with `a = {pMinValue,pRegion,pTitle}`, `b = ∅`, `c = ∅`
models `A` and refutes it.  `Step.preserves` proves every rule keeps the model set EXACTLY, so
no rule in this system, present or future, may delete that conjunct.  Closing this one needs the
existential quantifier in the object language.

### 5.3 The three `Yahoo.e` bindings — folded vs unfolded concrete groups

Every leftover is a constraint written two ways around a *concrete* label group that the system
itself defines.  `joinCumRet`, sweep `after3` (converted systems in
`<scratch>/e11b/conversions-key.txt`):

```
both sides carry:   (|initValue|) <- (c, d)          -- "initValue is exactly c plus d"

only in A:  t <- (b, rs, so) + (|adjClose, initValue|)
only in B:  t <- (b, c, d, rs, so) + (|adjClose|)          -- the same statement, unfolded

only in A:  r <- (b, rs) + (|adjClose, initValue|)         -- and the same again for r,
            (already present on both sides as r <- (b, c, d, rs) + (|adjClose|))

only in A:  (|adjClose, initValue|) <- (c, d) + (|adjClose|)
            -- "adjClose+initValue is adjClose plus c plus d", which is the both-sides
               constraint with adjClose added to each side
```

`joinTotalValue` and `investmentTableData` are the same phenomenon with
`(|initialInvestment|) <- (c, d)` and `(|initValue|) <- (c, e)` (`leftover.log`,
`<scratch>/e11b/profiles.log`).  In `investmentTableData` the two runs even hand the *same* pair
of variables to *different* concrete groups (A: `{initValue} <- (d,g)`, `{initialInvestment} <-
(c,e)`; B: the other way round) — harmless, a bijection absorbs it — and the real difference is
again folded-vs-unfolded groups inside five other constraints.

The rule needed is: given `(|K|) <- (v1, ..., vn)`, a right-hand side that contains all of
`v1..vn` may have them replaced by the labels `K` (or, oriented the other way, a concrete part
containing `K` may have `K` replaced by `v1..vn`), and then `dedup` finishes the job.  Applied to
a fixpoint in ONE fixed direction this would make the two `joinCumRet` variants identical.  It is
`absorb` generalised from "a variable whose definition is wholly concrete" to "a concrete group
whose definition is wholly variable" — **definitional substitution**, the rule the header says is
not implemented.

### 5.4 `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'` — the hard one

28 constraints each way, no bijection even with 4 set aside.  The structural profile
(`<scratch>/e11b/profiles.log`) says what is going on:

```
A has  d <- (d3, g, h, k)          arity 4
B has  d <- (d1, g, h, k, ro)      arity 5
A has  m <- (d3, g) + (|cutoff|)   two constraints of arity 2 with (|cutoff|)
B has  l <- (d1, g, ro) + (|cutoff|)   two of arity 3 with (|cutoff|)
```

One run carries a row as a single variable `d3`; the other carries the same row split into two,
`d1` and `ro`.  Collapsing the two would mean *merging two variables back into one*, i.e.
undoing a generative split.  That is neither of the two unimplemented non-generative rules; it
needs either a fresh variable (so, a generative rule) or a common-subexpression contraction that
recognises `d1, ro` as always co-occurring.  This is also the one the review flags as changing
between builds and as beyond its matcher's 4M-node budget; my result agrees with it.

---

## 6. `lookbackJoin` worked out by hand

Two cold checks of one build, sweep `after` (`<scratch>/e11b/pairs/after__lookbackJoin.txt`).
Universals `r, r1, a, b` on both sides; everything else existential.

```
check A (8)                        check B (9)
A1  r1 <- (r, c)                   B1  r1 <- (r, c)
A2  r1 <- (c1, d)                  B2  r1 <- (c1, d)
A3  a  <- (r, c2)                  B3  a  <- (r, c2)
A4  a  <- (e, f)                   B4  a  <- (e, f)
A5  b  <- (e, f, g)                B5  b  <- (e, f, g)
A6  r2 <- (c1, h)                  B6  h  <- (r, i, c)
A7  t  <- (c1, d, h)               B7  h  <- (c1, d, i)
A8  o  <- (f, g)                   B8  r2 <- (f, g)
                                   B9  r3 <- (d, i)
```

Rename B's existentials by `i ↦ h`, `h ↦ t`, `r2 ↦ o`, `r3 ↦ r2`, and swap `c1 ↔ d` (allowed:
`r1 <- (c1, d)` is symmetric in them).  Then B2↦A2, B3↦A3, B4↦A4, B5↦A5, B7↦A7, B8↦A8, B9↦A6,
B1↦A1 — and **B6 is left over**, reading `t <- (r, c, h)`.  This is the same shape the review
found between the pre- and post-E11a builds; here it is between two runs of one build.

Why B6 is redundant, in one line of arithmetic — write `⊎` for disjoint union:

* A7 says `t = c1 ⊎ d ⊎ h`;
* A2 says `r1 = c1 ⊎ d`, so `t = r1 ⊎ h`;
* A1 says `r1 = r ⊎ c`, so `t = r ⊎ c ⊎ h` — which is B6.

Only associativity of disjoint union is used, which is exactly what a partition constraint means.
So the two sets are entailment-equivalent, and A is the smaller.

Why `canonN` does not find it: run through the six rules on B.

* `occurs` — needs a constraint whose left-hand variable also appears on its right (`a <- (a, …)`).
  None does.
* `selfDedup` — needs a variable twice on one right-hand side.  None is.
* `absorb` — needs a variable whose whole definition is concrete (`b <- ((|k|))`).  There are no
  concrete rows here at all.
* `dedup` — needs two constraints with the same left-hand variable, the same concrete part and
  right-hand sides that are permutations of each other.  B6 and B7 share `h` but their right-hand
  sides are `(r, i, c)` and `(c1, d, i)`, not permutations.
* `common` — needs two constraints with the *same* right-hand side and different left-hand
  variables.  No two right-hand sides are equal.
* `unify` — needs a singleton right-hand side `a <- (b)`.  None is.

`stepFn` returns `none` immediately; B is its own normal form, confirmed in
`<scratch>/e11b/run.out` (`NORMAL true`).  The step that would be needed is the one in the
arithmetic above: **replace `c1, d` inside B7's right-hand side by `r1`, because B2 defines `r1`
as exactly `c1 ⊎ d`; then replace `r1` by `r, c`, because B1 defines it so; then `dedup` deletes
the resulting duplicate of B6.**  That is definitional substitution, twice.  Note that it also
has to be *oriented* — folding and unfolding are inverse, and a canonicaliser must pick one
direction and run it to a fixpoint, or the two variants will simply swap places.

---

## 7. What a Scala port would consist of

### 7.1 The six rules, and where they go

`Subst.mkSimplified` (`core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala:2086`) is the
one place a binding's constraint list is cleaned before publication.  Inside it, `normalPart`
already converts each `Part` into a `NormalPart(left: TypeVar, concrete: Set[Name], abstrakt:
List[TypeVar])` — which *is* Lean's `Constraint` (`lhs`, `conc`, `vars`), field for field, when
the left-hand side is a variable.  So the six rules would be a function
`List[NormalPart] => (List[(TypeVar,TypeVar)], List[NormalPart])` applied at
`Subst.scala:2132` (`normal.distinct.map(_.left.get.part)`), i.e. **where the tautology deletion
and the `distinct` already are, replacing them**:

* `occurs` — subsumes the existing `a <- (a)` tautology deletion at `Subst.scala:2123`, and
  strengthens it: `a <- (a, b, c)` becomes `b = ∅, c = ∅` rather than being kept;
* `dedup` — subsumes the existing `.distinct`, which after ticket S3 already compares
  `NormalPart`s up to a sorted `abstrakt` (`Subst.scala:1973-1983`), so this is a no-op in the
  port, correctly;
* `selfDedup`, `absorb`, `unify`, `common` — new, and per this probe they would fire on nothing
  in the current corpus.

Order matters: put the rule loop **before** anything that deletes constraints for other reasons,
because `occurs` turns a constraint into equations rather than dropping it, and the equations
have to reach the same `solve` call that the tautology deletion's neighbours reach.

### 7.2 What the Lean proofs buy, and what a port must re-establish

Covered by the Lean, and free:

* **Termination.**  `Step.decreasing` + `lexLt_wf` + `exists_fuel`: the measure is (number of
  distinct variables, total right-hand-side size, number of constraints), lexicographically.  A
  port needs no fuel parameter at all — a `while (step(s)) {}` loop terminates.  If the port
  wants a fuel guard anyway (house style in this codebase), the bound is that measure's ordinal;
  in practice this probe never exceeded **two** steps on any of 86 real systems.
* **Meaning preservation.**  `Step.preserves` and `canonN_preserves`: the model set is preserved
  exactly, not merely up to the eliminated variables, because eliminated variables are kept in a
  `solved` list.  A port must keep that list too (Ermine already has the substitution machinery)
  or it loses the sharp statement.
* **Simplifier soundness and completeness.**  `canonN_entails`: entailment is unchanged.  So the
  port cannot weaken or strengthen a published signature — which is the property the E11a review
  had to argue by hand.
* **The two known defects** are provably fixed: `step_vacuous` (`r <- (r)`) and `step_perm_dup`
  (a duplicate under a permuted right-hand side), `Canonical.lean` §12.

NOT covered, and a port has to establish it itself:

1. **The conversion.**  `Part`/`ConcreteRho`/`VarT` → `Constraint` is only faithful when the
   left-hand side is a variable and every right-hand entry is a variable or a concrete row.
   `normalPart` already recognises exactly that fragment and returns `Right(p)` ("something we
   don't know how to deal with") otherwise — so the port must run the rules on the `Left` half
   only and pass the `Right` half through untouched.  A **concrete left-hand side**
   (`(|adjClose, initValue|) <- (...)`) is in the fragment `normalPart` accepts only in the
   degenerate one-variable case; the Lean type cannot hold it at all, and this probe had to
   introduce proxy variables for it.  Three of the six SET bindings have such constraints, so
   a port that ignores them is ignoring the interesting cases.
2. **Class constraints.**  They are not in the Lean language.  `mkSimplified` already partitions
   them off (`ps.partition(_.isClassConstraint)`), so the port inherits the split for free — but
   it must not let the row rules eliminate a variable that a class constraint mentions without
   substituting into the class constraint as well.  Lean's `common` and `unify` rewrite the whole
   system; the port must rewrite the class constraints too, and no Lean theorem covers that.
3. **Non-row, non-class constraints** (the `Right(p)` bucket) must be treated as opaque
   *occurrences* of variables — again, `common`/`unify` substitutions have to reach them.
4. **Locations.**  `NormalPart` carries a `Loc` that its `equals` deliberately ignores.  Rules
   that merge or delete constraints must choose a `Loc` for the survivor; blame locations are
   load-bearing in this compiler (`ROW-CONSTRAINT-STATE.md`'s blame mechanism), and no Lean
   theorem says anything about them.
5. **Confluence — there is none.**  `Canonical.lean` §11 refutes local confluence
   (`not_locally_confluent`, `not_joinable`) and §11's `Orientation` section shows `common` is not
   even a function (either left-hand variable may be eliminated).  So a port must fix an
   orientation (eliminate the larger id, say) and a rule order, and its output is then a function
   of the *input order*.  That is why this port must sit *after* E11a's canonical form, which
   fixes the input order: the two together are deterministic, `canonN` alone is not.
6. **It is not a decision procedure.**  `CriticalPair.normal_form_can_be_unsat`: a normal form
   can be unsatisfiable.  The port must keep the existing `solve(Exists(l, List(), extinct))`
   call — the rules are hygiene, not a solver.

### 7.3 Is it worth doing?

On the evidence here: as a *fix for E11b*, no — it moves the SET count by zero.  As hygiene, it
is cheap and provably safe, and it makes the strengthened `occurs` and the `absorb`/`unify`/
`common` behaviour available for the day the generative side changes.  The actual E11b fix has to
be one of:

* **definitional substitution, oriented and run to a fixpoint** — closes `lookbackJoin` and the
  three `Yahoo` bindings (four of six), and is a rule that would have to be added to
  `Canonical.lean` first, with a new termination argument (it does not obviously decrease the
  existing measure: folding shrinks a right-hand side, unfolding grows it, so the measure has to
  be chosen with the orientation);
* **existential projection** — closes `reportFor`, and needs the quantifier in the Lean model
  before anything can be proved about it;
* **un-splitting** — `cutoffGroupedFldsPosNegRel'`, the hardest, and generative.

---

## 8. Threats to validity

* **Names, not identities.**  The renderings print name *hints*, so my converter identifies
  variables by printed name.  For a post-E11a published scheme that is safe (the canonical form
  gives distinct existentials distinct positional letters).  It is NOT safe for the two
  `Algebra/Signatures.e` bindings, whose renderings have **no `exists` binder at all** — their
  constraint variables are unbound in the printed scheme, so two different solver variables can
  print as the same letter.  That is why my converter sees permuted duplicates there that the
  compiler's own `NormalPart.distinct` did not remove, and it means the SAME verdict on
  `runningTotalFull` / `runningTotalFullViaWritten` should be read as "same as printed", not
  "same as inferred".  Neither binding is in the final target list (§4), and neither affects the
  headline, which is about the six that DIFFER.
* **Dropped class constraints.**  Verdicts are about the row part only.  Every case's dropped
  constraints are listed in `<scratch>/e11b/conversions-all.txt`; the two variants of a pair drop the
  same list in every case but one -- `before:cutoffGroupedFldsPosNegRel'`, where both sides drop
  13 class constraints but the class-variable letters differ.
* **Proxy variables** for concrete left-hand sides add one constraint per distinct concrete row
  to BOTH sides, so they cannot create or hide a difference; they can only make a system slightly
  larger than the rendering suggests.
* **Bijection search** is exact for the pairs where a verdict of SAME or a minimal leftover is
  reported (it backtracks at both levels and none of those searches hit the 2M/4M-node budget).
  The two "no bijection" verdicts on 28-constraint systems
  (`cutoffGroupedFldsPosNegRel'`) completed inside budget as well; the *leftover* search for it
  is the one that gave up (no partial match with 4 set aside).

---

## 9. Every claim's log

All under `<scratch>/e11b/` =
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11b/`.

| file | what it is |
|---|---|
| `parse.py` | record-level parser for the sweep TSVs (embedded newlines) |
| `conv.py` | rendering → `Rowpartition.State` converter |
| `build.py` | writes `cases.json` and `run.lean` (43 cases, 86 systems) |
| `run.lean`, `run.out`, `run.err` | the Lean run; `run.err` is empty, exit 0 |
| `t1.lean` | harness sanity check: reproduces `Canonical.lean` §13 |
| `cmp.py`, `cmp.log` | normal-form comparison, all 43 cases incl. the 12 controls |
| `cmp2.py`, `cmp2.log` | the same comparison run on inputs AND normal forms — the "canonN changed no verdict" table |
| `leftover.py`, `leftover.log` | minimal leftover constraints per DIFFERENT pair |
| `profile.py`, `profiles.log` | arity/concrete profiles for the two large cases |
| `dump.py`, `conversions-all.txt`, `conversions-key.txt` | converted systems and normal forms printed back, for checking against the renderings |
| `pairs/*.txt` | the 31 raw rendering pairs, extracted from the sweeps |

Inputs read, unchanged: `<scratch>/e11a/logs/sweep-{before,after,after2,after3,canonall}.tsv`,
`<scratch>/e11a/set-pairs.txt` (found truncated, see §2), `tracker/lean/Rowpartition/*.lean`,
`tracker/loopmodel/E11a-CANON.md`, `tracker/loopmodel/E11a-REVIEW.md`.
