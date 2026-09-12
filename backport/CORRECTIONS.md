# BP-2: the seven library signature corrections and the five pins, on `backport-2.11`

Worktree `ermine-scala-wt-backport`, branch `backport-2.11`, from HEAD `4fefc51`. No commits.
Source of truth: scala3-migration `5162945` and its rationale
`tracker/loopmodel/SIG-3b-CORRECTIONS.md`; the pre-correction text there is `cff6c42`.
No build was run: every claim below is a byte comparison against those two trees plus a
reading of this branch's grammar and `Subst.scala`. BP-1 measures.

**Headline.** All seven corrections applied by patch -- the 2.11 module text at every
correction site was byte-identical to main's pre-correction text, so nothing had to be
ported "by meaning". Four of the five edited files are now **byte-identical to main's
landed blob**; the fifth (`Relation.e`) differs only in prose BP-2 did not touch. All five
pins and the control carry **program text byte-identical to main's**: no syntax adaptation
was required for the Scala-2 grammar.

| file | blob after BP-2 vs `5162945` |
|---|---|
| `Relation/UnifyFields.e` | `7bab327` -- identical |
| `DrilldownList.e` | `38f8e01` -- identical |
| `Layout/Report/Keyed.e` | `dc0e5a2` -- identical |
| `Layout/Report/Relation.e` | `03615e9` -- identical |
| `Relation.e` | `6319415` vs `0df68ca` -- differs, prose only (see §2) |

## 1. The seven corrections, as they now read on this branch

Line numbers are this branch's, after the edit. `(||)` is the empty row.

### c1 -- `core/src/main/resources/modules/Relation/UnifyFields.e:6` `unify1`

before
```
unify1 : forall (r:row) (r2:row) . (r <- (h,f,t), r2 <- (h,f2,t))
      => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
```
after
```
unify1 : forall (r:row) (r2:row) . (r2 <- (f1,f2,p), r <- (f2,p,u))
      => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
```
Discharges `r2\f2 <- (f1, _)`: `f1` occurred in no given, so `rename f1 f2` renamed a
column that need not be there (`Failure(Renaming non-existent attribute)`). This is S3b's
form, **not** the form S3 and the plan recommended (`r <- (h,f2,t)` with
`r2 <- (h,f1,f2,t)`): that one is honest but refuses the real caller
`Algebra/Customer360.e:207` (both operands the same relation, so `r = r2` forces
`f1 = (||)` at a concrete label). That caller is an example-corpus module and does not
exist on this branch, but the weaker form is the one that landed on main and is what a
merge must agree with.

### c2 -- `core/src/main/resources/modules/Relation.e:107` `partialLookup`

before
```
partialLookup : (RelationalComb rel, PrimitiveAtom a, kv <- (key,val), r <- (key,base))
             => Field key a
```
after
```
partialLookup : ( exists r2
                . RelationalComb rel, PrimitiveAtom a
                , kv <- (key,val), r <- (key,base)
                , r2 <- (key,val,base) )
             => Field key a
```
Discharges `r2' <- (base, val, key)`, `partialLookup'`'s own constraint: nothing made
`val` disjoint from `base`, and at `val ⊆ base` the body's row is unsatisfiable. The
existential `r2` is the same spelling `partialLookup'` (:121 here) already uses.

### c3 -- `core/src/main/resources/modules/DrilldownList.e:18` `cons_Bracket`

before
```
cons_Bracket : forall f1 f2 rout r id. (Has rout f1, Has rout f2, Has rout r) =>
```
after
```
cons_Bracket : forall f1 f2 rout r id. (rout <- (f1, f2, r)) =>
```
Discharges `_ <- (r, f1)` and `rout <- (f2, _)`: the three `Has` were an applied type
VARIABLE (`Constraint` is not imported in this module), and `Has` gives membership where
`append` needs disjointness.

### c4 -- `core/src/main/resources/modules/Layout/Report/Keyed.e:52` `softRelation`

before
```
softRelation : (AsPresentation prk, AsPresentation prvd)
            => prk k a -> prvd v b
```
after
```
softRelation : ( exists o
               . o <- (k, v)
               , AsPresentation prk, AsPresentation prvd )
            => prk k a -> prvd v b
```
Discharges `o' <- (k, v)` -- the constraint the wrapped `Layout.Report.softRelation`
declares and the wrapper dropped.

### c5 -- `core/src/main/resources/modules/Layout/Report/Keyed.e:67` `keyValueTabular` (+ the degeneracy comment)

before
```
keyValueTabular : (Relational rel, Relational rel2)
               => (Options (KeyValueTabularOptions u1 i label pid id cid r (rel2 root))
```
after
```
-- DEGENERATE (S3b, 2026-09-11): honest, but the four branches force pid = cid = r = (||),
-- so the two drilldown branches are uncallable; splitting the wrapper is a ticket.
keyValueTabular : ( exists o
                  . r2 <- (k, v, i)
                  , i <- (label, o)
                  , r2 <- (k, v, pid, cid, i)
                  , r2 <- (k, v, r, i)
                  , Relational rel, Relational rel2 )
               => (Options (KeyValueTabularOptions u1 i label pid id cid r (rel2 root))
```
One group per branch of the `case`: `keyValueTabular_R`'s `r <- (k,v,i)`,
`pivotTabular'_R`'s permutation, `drilldownKeyValueTable_R`'s `r <- (k,v,p,c,i)` plus
`i <- (lbl,o)`, and `drilldownKeyValueTable2_R`'s `r2 <- (k,v,r,i)`. Honest but degenerate:
the four together force `pid = cid = r = (||)`, so the two drilldown branches become
uncallable. The two-line comment carries that ticket, verbatim from main.

### c6 -- `core/src/main/resources/modules/Layout/Report/Relation.e:87` `cutoffs`

before
```
     ( exists l e
     . s <- (e, p, v)
     , l <- ((|cutoff|), s)
     , r <- (p, v, (|cutoff|)))
```
after
```
     ( exists l e
     . s <- (e, p, v)
     , l <- ((|cutoff|), s)
     , r <- (p, (|cutoff|)))
```
The body ends `|> except {valueFld}`, so the declared result kept a column the body
removes and the wanted was unsatisfiable for every non-empty `v`. Note from main: this one
is NO VERDICT under the Lean/oracle model (its `ds` half carries the non-empty concrete
left-hand side `(|cutoff|) <- (rs, so)`), in the company of its untouched siblings
`largers` and `small`; it is verified by the load and by hand, not by the oracle.

### c7 -- `core/src/main/resources/modules/Layout/Report/Relation.e:177` `others`

before
```
  others
     : forall v p pt s r d c.
     ( s <- (p, v, d, c)
     , l <- ((|cutoff|), s))
    => ...
    -> Relation s
    -> Relation r
```
after
```
  others
     : forall v p pt s d c.
     ( exists l
     . s <- (p, v, d, c)
     , l <- ((|cutoff,cutoffCount,cutoffChild,cutoffGroup|), s))
    => ...
    -> Relation s
    -> Relation s
```
Three changes in one correction: `r` leaves the `forall`, the dangling `l` is bound by
`exists`, and the declared result row becomes the row the body actually returns (`s`).
Discharges `r' <- ((|cutoffCount|), p)` and its two siblings plus
`r' <- ((|3 cutoffs|), r)`: the result row was in no constraint at all, and nothing said
the three private `cutoff*` columns were outside `p`.

### the forced cascade -- `core/src/main/resources/modules/Layout/Report/Relation.e:55` `cutoffDrilldownRel` (public)

before
```
   ( exists l
   . s <- (d, c, p, v)
   , l <- ((|cutoff|), s))
```
after
```
   ( exists l
   . s <- (d, c, p, v)
   , l <- ((|cutoff,cutoffCount,cutoffChild,cutoffGroup|), s))
```
Not optional: `others` (c7) now asks for the three private `cutoff*` labels to be outside
`s`, and `cutoffDrilldownRel` is its only caller. Without this the module does not load
under the enforced check. It is the one correction that changes a PUBLIC signature's
context.

Nothing else in those five modules was changed. `git diff --numstat` over them:

```
1	1	core/src/main/resources/modules/DrilldownList.e
11	2	core/src/main/resources/modules/Layout/Report/Keyed.e
7	6	core/src/main/resources/modules/Layout/Report/Relation.e
4	1	core/src/main/resources/modules/Relation.e
1	1	core/src/main/resources/modules/Relation/UnifyFields.e
```

The 12 example-corpus corrections (c8a-d melts, c9 `runningTotalFullViaWritten`,
c10-c14 the `Time` helpers, c15/c16 the `yearFrac365*`) and the six other cascaded ones
(`translate`, `yearFrac365`, `yearFrac360`, `yearsOn`, `yearFrac365Deduped`, the
`SoftRelation.e` `(dt, dt)` drilldown level) **do not apply**: `core/examples/Algebra/`,
`Wide/`, `Time/`, `Lang/` and `Present/` do not exist on this branch. `core/examples/SoftRelation.e`
DOES exist here and is byte-identical to main's pre-correction version, so the honest
`cons_Bracket` (c3) may now refuse its `groupingDateDrilldown` -- see §4.

## 2. Where the 2.11 module text differed from main's pre-correction text

Diffed file-by-file against `git -C ../ermine-scala show cff6c42:<path>`:

| file | differs from main's pre-correction text? |
|---|---|
| `Relation/UnifyFields.e` | no -- byte-identical |
| `DrilldownList.e` | no -- byte-identical |
| `Layout/Report/Keyed.e` | no -- byte-identical |
| `Layout/Report/Relation.e` | no -- byte-identical |
| `Relation.e` | YES, in one place, far from the correction |

**The one difference.** `Relation.e` at main `cff6c42` carries two blocks of stage-F3 prose
that this branch does not have -- a `REQUIRES f2 TO ALREADY BE IN THE RELATION (ticket C5,
stage F3)` paragraph on `rename'` and a rewritten `join1` comment (ticket C2). On this
branch `join1` still has the original three-line "requires a witness that the intersection
is nonempty" comment and `rename'` has only its one-line summary. Both sit at lines
~155-170, **fifty lines below** `partialLookup` (:107), and neither is a signature. The
correction region (`partialLookup`'s context, lines 100-120) is byte-identical, so c2 went
in by patch and the residual difference is untouched by BP-2. Confirmed by diffing this
branch's post-edit `Relation.e` against main's landed `5162945:...Relation.e`: the ONLY
hunk is those two prose blocks.

**So: nothing was ported "by meaning".** Every one of the seven corrections plus the
cascade went in as the identical character sequence main landed, and the four files with no
prose divergence hash to main's landed blobs
(`7bab327`, `38f8e01`, `dc0e5a2`, `03615e9`).

## 3. The pins

Created, all LF (main's pins are LF too; no `.gitattributes` in this repo and
`core.autocrlf` is unset):

| file | module | role |
|---|---|---|
| `core/examples/shouldfail/sig01_unconstrained_signature.e` | `ShouldFail.Sig01` | `forall r. {..r} -> Int`, body reads `health` |
| `core/examples/shouldfail/sig02_wrong_label_signature.e` | `ShouldFail.Sig02` | constraint on the WRONG label (`mana`) |
| `core/examples/shouldfail/sig03_let_bound_signature.e` | `ShouldFail.Sig03` | sig01's shape on a LET-bound binding |
| `core/examples/shouldfail/sig04_unconstrained_modify.e` | `ShouldFail.Sig04` | the same hole for a WRITE (`modify`) |
| `core/examples/shouldfail/sig05_annotated_lambda.e` | `ShouldFail.Sig05` | the same hole through an expression ANNOTATION |
| `core/examples/shouldfail-controls/control08_sig_declared.e` | `Shouldfail.Control08` | MUST LOAD: the same bodies, honest signatures |

Module names are main's, unchanged (note main's own casing inconsistency: `ShouldFail.*`
for the pins, `Shouldfail.Control08` for the control -- kept as-is so the two trees agree).

Each header keeps main's mechanism text, with the `Subst.scala` line numbers **re-checked
against this branch's file at HEAD `4fefc51`** rather than copied: `subsumeType` :527-553,
the `ds`/`rs` partition :534, the discarded `for (r <- rs) entails(qs, r)` :535-536, the
`ds`-only return :553, `restrictTypes(tts)` :540, the escape check :543, `entails` :313,
`entail` :394 gated on `isClassConstraint` :398, the `TODO: ADD warnings` :639. Those all
coincide with main's `a15a97e`; two do not, and the headers say so --
`typeCheckExplicitBinding` is **:647** here (main's header says :655), and the `ann` site is
`typeCheck` **:633-640** reached from `case Sig(l, x, ann)` **:893** (main's header says
:638).

Every "measured message" block is replaced by

```
EXPECTED MESSAGE ON THIS BRANCH: TO BE MEASURED on 2.11 by BP-1.
```

followed by main's measured text under an explicit **"For reference only -- ... NOT a claim
about this branch"** label, so BP-1 has the target shape to diff against without the file
asserting an unmeasured position. Main's positions would in any case be wrong here: these
headers are a different length from main's.

### 3.1 Syntax adaptation for the Scala-2 grammar: NONE was needed

The program text of all six files is byte-identical to main's (verified by stripping
comments from both sides and diffing: `CODE IDENTICAL` six times). Checked construct by
construct against this branch's parser, by reading it -- no build:

* **Lambdas.** No `\x ->` form is used anywhere; `TermParsers.lam` (:273-276) is
  `patternL0.some << keyOp("->")`, so `(r -> r ! health)` and `(h -> h + 1)` are what it
  takes. This is the only spelling main's pins use as well.
* **Explicit-forall annotations parse.** `TypeParsers.annot` (:351-355) is an optional
  `some` quantifier followed by `typ`, and `typ` (:298) itself takes an optional `forall`
  via `uQuant` (:294). So `(e : forall r. {..r} -> Int)` (sig05's `crash2`) and
  `(e : forall r t. r <- ((|health|), t) => {..r} -> Int)` (control08's `ok5`) are both
  accepted -- **the 2.11 grammar does not refuse them**, and the stdlib already writes the
  richer `(cont : some a b . forall r . Field r a -> b)` at `Field.e:36`. The bare
  `(e : {..r} -> Int)` (sig05's `crash`) parses too, with `r` resolved by
  `TypeParsers.typeVar` (:54-68).
* **Where the annotation's `r` gets quantified.** Main closes a bare annotation in
  `rename/TyLower.scala` (`TyLower.annot`), which does not exist on this branch. The 2.11
  counterpart is `Annot.close` (`Annot.scala:15`, `body.closeWith(exists).nf`), reached
  through `Term.Sig.close` (`Term.scala:78`) / `ExplicitBinding.close`
  (`Binding.scala:68`) / `ImplicitBinding.close` (:90) from `Session.scala:931-932` at
  module load. So free lowercase type variables in both a signature and an annotation are
  wrapped in a `Forall.mk` here too, and `subsumeType`'s `unbind(Skolem, e1)` skolemises
  them. That is a reading, not a measurement: sig05's header flags it as the one place the
  two pipelines close an annotation in different code and asks BP-1 to record WHICH of
  `crash` / `crash2` the diagnostic names.
* **Laid-out `let` with a signature line parses.** `bindingStatement` is
  `sigStatement | termStatement` (`StatementParsers.scala:332-334`) and `sigs` (:31)
  backtracks up to the `:`, so sig03's and control08's `let f : ... ; f r = ...` bodies
  parse.
* **Row literals, `Has`, `modify`, `cons`, `!`, record literals, `field` declarations,
  `Nullable`.** All present. `Prelude.e` on this branch is **byte-identical** to main's
  (`export Constraint`, `export Field`, `export Nullable as Nullable`), and `Field.e`,
  `Constraint.e`, `Record.e`, `Nullable.e` and `Relation/Row.e` are byte-identical too, so
  every name the pins use resolves the same way. `(|cutoff|)`-style row literals are
  already in this branch's `Layout/Report/Relation.e`.
* **Lexing.** Each pin's block comment is balanced (one `{-`, one `-}`), ASCII-only, no
  tabs, no trailing whitespace, comment at column 1 between `module ... where` and
  `import Prelude` -- the same shape main's use.

### 3.2 The sig03 / LET-1 note, in every header

main's sig03 header is largely about a SECOND bug: the scala3 pipeline's renamer
(`rename/Lower.scala`, SLet case) discarded explicit let bindings, so `local`'s signature
never reached the checker and the module was refused at the CALL by ordinary inference
until LET-1 (`cff6c42`).

**That does not apply on this branch, and each of the six files says so.** `rename/Lower.scala`
does not exist here; the fused Scala-2 grammar builds both halves of `Let` directly --
`TermParsers.let` (:224-243) does `laidout("let binding", bindingStatement)`,
`gatherBindings` (`Statement.scala:284-289`, whose `case (s: SigStatement)` keeps the sig)
then `checkBindings`, which mints `ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, s.ty),
i.alts)` (`Statement.scala:306`). A let-bound signature therefore reaches the same `sig`
site (`typeCheckExplicitBinding`, :647) a top-level or `where` one does. **So sig03 here is
simply sig01 inside a `let`, and must be rejected by the entailment check at the signature,
not at the call** -- the pre-LET-1 `Row partitions are unsatisfiable at field
'ShouldFail.Sig03.health'` message is recorded in sig03's header only as the thing BP-1
should NOT see. control08's `localWith` is the matching honest control and is a real
control on this branch for the same reason.

## 4. For BP-1 and for the merge

1. **Every message and verdict in the six pins is unmeasured.** Fill the
   `EXPECTED MESSAGE ON THIS BRANCH` blocks; the reference blocks below them are main's and
   are labelled as such.
2. **sig05 has two judgements** (`crash`, `crash2`) and dies at the first the check
   refuses. Record which.
3. **`core/examples/SoftRelation.e` is at risk from c3.** It exists on this branch,
   byte-identical to main's pre-correction version, and on main the honest `cons_Bracket`
   refused its `groupingDateDrilldown` -- `[(pid, cid), (dt, dt)]_DDL`, a drilldown level
   whose parent and child are the same column -- with `Fields appear twice in row:
   SoftRelation.dt` at `:97:25`. Main fixed it by keying the date level on
   `(dtGroup, dt)`. BP-2 did **not** apply that fix: it is a behaviour change to an example
   module, it is outside the seven, and the brief scopes BP-2 to the corrections and the
   pins. Expect `SoftRelation.e` to stop loading here, and expect
   `sbt core/testOnly *TestErmine*` to name it first if this branch's suite loads the
   examples. The fix, from main `5162945:core/examples/SoftRelation.e`, is a one-level
   change plus a new `dtGroup` field.
4. **`cutoffDrilldownRel` is a published-interface change** (a public signature's context
   gains three labels). If this branch republishes `.ei` files, that one moves.
5. **c1 is S3b's weaker `unify1`, not S3's recommended form.** A merge must take S3b's.
6. **A stdlib edit needs `sbt core/copyResources`** before `bin/ermine` sees it (the
   modules are read from `core/target/.../classes/modules`).

## 5. Files BP-2 touched

```
core/src/main/resources/modules/Relation.e                       +4  -1   c2
core/src/main/resources/modules/Relation/UnifyFields.e           +1  -1   c1
core/src/main/resources/modules/DrilldownList.e                  +1  -1   c3
core/src/main/resources/modules/Layout/Report/Keyed.e            +11 -2   c4 c5
core/src/main/resources/modules/Layout/Report/Relation.e         +7  -6   c6 c7 + cutoffDrilldownRel
core/examples/shouldfail/sig01_unconstrained_signature.e         NEW
core/examples/shouldfail/sig02_wrong_label_signature.e           NEW
core/examples/shouldfail/sig03_let_bound_signature.e             NEW
core/examples/shouldfail/sig04_unconstrained_modify.e            NEW
core/examples/shouldfail/sig05_annotated_lambda.e                NEW
core/examples/shouldfail-controls/control08_sig_declared.e       NEW
backport/CORRECTIONS.md                                          NEW      this report
```

Nothing else. `Constraints.scala`, `Subst.scala`, `Session.scala`, `SessionState.scala`,
`SigEntail.scala` and `backport/{env-2.11.sh,hg,repositories,sigcheck.py}` in this worktree
are BP-1's.

**Line endings.** Every `.e` edit was made byte-wise in Python (`open(p,'rb')`), replacing
a byte string whose newlines had first been rewritten to the FILE's own ending. The five
modules do not agree on that ending on this branch -- `Relation.e`, `Relation/UnifyFields.e`
and `Layout/Report/Keyed.e` are CRLF; `DrilldownList.e` and `Layout/Report/Relation.e` are
**LF** (main's `SIG-3b-CORRECTIONS.md` lists `DrilldownList.e` among its CRLF files, so
this differs from main and a text-mode edit here would have churned two files in one
direction and three in the other). After the edits: CRLF 267 / 8 / 144 with zero bare LF
and zero lone CR in the three CRLF files; 23 and 199 bare LF and zero CR in the two LF
files. `git diff --numstat` over the five totals 24 insertions and 11 deletions -- a
wholesale conversion would have shown every line of all five files. The six new pins are
LF, as main's are.

`git diff --check` reports "trailing whitespace" on every added line of the three CRLF
modules. That flag is the CR of their own CRLF ending -- every UNCHANGED line of those
files trips it identically -- not whitespace BP-2 introduced. The two LF modules' hunks
carry no CR at all: per-file, 7/7, 11/11 and 25/25 diff-body lines end in CR for
`UnifyFields.e`, `Relation.e` and `Keyed.e`, and 0/8 and 0/37 for `DrilldownList.e` and
`Layout/Report/Relation.e`.

One footnote on main's own bookkeeping: `SIG-3b-CORRECTIONS.md` §6 lists
`Layout/Report/Keyed.e` as `+9 -2`. The correct count is `+11 -2` (c4 replaces one line
with three, c5 one line with eight, two of which are the DEGENERATE comment). This
branch's post-edit blob is byte-identical to main's landed `dc0e5a2`, so the file is right
and that table line was off by two.
