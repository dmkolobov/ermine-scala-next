# SIG-1: the warn-mode survey -- what the signature-entailment hole actually covers

Stage S1 of `tracker/SIG-ENTAIL-PLAN.md`, worktree `ermine-scala-wt-sig`, branch `sig-entail`
(from `ba29389`). THIS STAGE MEASURES: it adds no entailment logic and changes no verdict.
Under the default (`-Dermine.sigEntail=off`) shipped behaviour is byte-identical -- see §7.

REVISED after the review (`tracker/loopmodel/SIG-1-REVIEW.md`, verdict FIX-THEN-ADVANCE).
The review's corrections are folded in and attributed where they change a claim: the `ann`
site is LIVE and unsound (§4, §8 item 8), the split table's arithmetic (§5), the false
"no stdlib obligation mentions a concrete label" clause (§8 item 1), the second `let`-drop
site and the regression history (§6), the repl-smoke classpath trap and the no-op compile
(§7), the class constraints mixed into two shape rows (§4), and the taxonomy that says how
much of the corpus the refutation trick actually reaches (**§8, first block -- the single
most important input to S2**). Its runtime witnesses for eight of the twelve (c) items are
in §5.

## 1. The probe

New file `core/src/main/scala/com/clarifi/reporting/ermine/SigEntail.scala`; three lines of
wiring in `Subst.scala`. The flag is

    -Dermine.sigEntail=off    DEFAULT -- shipped behaviour, nothing is read, nothing allocated
    -Dermine.sigEntail=warn   print one line per skolem-mentioning wanted at a user signature

read ONCE at class-init (`SigEntail.mode`, SigEntail.scala:29) exactly the way
`Constraints.GenRules` reads `ermine.genRules` (Constraints.scala:928), so a run is a
constant and the fixture rule at the top of `scalacheck-binding/src/main/scala/TestErmine.scala`
("never `System.setProperty` a flag that Session reads PER CALL") is satisfied by
construction.

**It is deliberately NOT a field of `Constraints.GenRules`.** `GenRules.toString` is the
second half of `Session.interfaceKey` (Session.scala:167) and is the first line of every
published `.ei`; a flag added there invalidates every cached interface (the comment at
Constraints.scala:1569 says so). `ermine.sigEntail` cannot change what the compiler
publishes at S1, so it must not be in that string. S3 must make the same call for `error`,
where the answer is the opposite: `error` CAN change what is published (by refusing), and
belongs in the key.

### The record

    sigEntail \t <module> \t <kind>:<binding> \t <file:line:col> \t <shape> \t lit|nolit
              \t <wanted> \t <givens> \t <thread>

`<kind>` is `sig` (a declared binding signature, `typeCheckExplicitBinding`) or `ann` (a term
annotation `e : T`, `typeCheck`). `<module>` is `<dir>.<file>` without the `.e`
(`Layout.Report`, `Lang.Helpers`) -- the parent directory is kept because the corpus has five
different `Helpers.e`. `<file:line:col>` is the `Located` of the WANTED, i.e. the occurrence
that incurred it, not the signature; a location the checker inferred from a source position
is marked `~`, a builtin prints `-`.

`<wanted>`/`<givens>` are a compact rendering (`SigEntail.render`) rather than
`Pretty.prettyType`: the pretty printer starts a fresh letter supply per call, so the two
columns would name two different variables `a` and hide exactly the distinction the survey is
about. The compact form carries the variable's id and its flavour -- `S` skolem (rigid,
the signature's own universal), `A` ambiguous-existential (the solver's minted remainder,
free), `B` bound, bare free.

The line goes through `RowTrace.log` when `-Dermine.rowTrace` is set (so a traced run keeps
one file and one order) and to stdout otherwise, which is where `tracker/tools/corpus-run.sh`
captures it into the per-file `.out`. Both spellings end with `RowTrace`'s thread-id column.

### SHAPE, tested in this order (SigEntail.shapeOf)

| tag | meaning |
|---|---|
| `multi-skolem` | more than one DISTINCT skolem anywhere in the wanted |
| `concrete-ext` | lhs is that one skolem; every part is a concrete label set or a flexible variable, with EXACTLY ONE of the latter -- what every `!`, `cons`, `\` and `modify` generates, and the shape the plan's refutation trick decides |
| `skolem-in-parts` | the one skolem occurs among the parts instead |
| `other` | anything else, INCLUDING a class constraint over a skolem |

`other` is split by `tracker/tools/sigentail-agg.py` into `other-row` and `other-class` on
whether the wanted contains the partition arrow, because a class constraint is not a row
obligation and S1's subject is the row hole.

### LITERAL

`lit` iff the wanted is alpha-equivalent to some given UP TO THE FRESH REMAINDER:
skolems match on the nose, flexible variables under a bijection, a `Part`'s parts up to
PERMUTATION. Conservative: anything the matcher cannot take apart it compares with `==`, so
`nolit` means "not obviously literal", never "provably not entailed". One normalisation is
applied: a class HEAD may be a `Con` in the body's wanted and still the `Bound` type variable
the renamer left in the signature's constraint (`AsPresentation^537025B` in `Report.e`'s
givens against `AsPresentation` in its wanteds); those are matched by name.

## 2. The caller table: which `subsumeType` calls check a user signature

Every call site of `Subst.subsumeType` in the tree, at the line numbers of THIS commit
(`subsumeType` itself is Subst.scala:534). "User signature" means `e1` is a type the user
WROTE and the compiler is checking a body against; those are the only two the probe fires at.

| # | call site | `e1` (the subsumed type) | user signature? | probed |
|---|---|---|---|---|
| 1 | `Subst.typeCheck` :651 | the annotation of `e : T` (`inferType`'s `Sig` case, :908-910) | **YES** | `ann` |
| 2 | `Subst.typeCheckExplicitBinding` :669 | the binding's DECLARED signature | **YES** | `sig` |
| 3 | `Subst.inferImplicitBindingTypes` :815 | `substType(b.v.extract)` -- the binding group's own fresh meta for an UNSIGNED binding | no | -- |
| 4 | `Subst.inferType`, `App` case :936 | the function's domain `i`, from `matchFunType` | no | -- |
| 5 | `Subst.typeCheckPattern` :992 | an expected pattern type | no -- and the method is DEAD: no caller anywhere in the tree, confirmed tree-wide by the review (only the definition and its own `subsumeType` call) | -- |
| 6 | `editor/.../BackendImpl.scala:447` (`matches`) | an editor query "does t2 subsume t1" | no | -- |

Two callers reach #2 rather than `subsumeType` directly and therefore inherit the probe:
`Subst.inferBindingGroupTypes` :780 (every top-level and every `let`/`where` explicit
binding) and `session/TolerantCheck.scala:669` (the editor's own check -- which is why S4's
parity work starts from a probe that already fires there).

How the two are told apart is an explicit optional parameter
`sig: Option[SigEntail.Site] = None` on `subsumeType`, not a thread-local. That is
deliberate and is S2's answer to plan item (iii): the distinction is a property of the CALL,
not of the dynamic extent. `typeCheckExplicitBinding` runs `inferAltTypes` (which contains
arbitrarily many `App` subsumptions) BEFORE its own `subsumeType`, so an ambient flag would
happen to work today -- but the `App` case at :936 is reached from inside signature checking
on other paths, and a flag that is right by accident is the kind of thing S3 must not ship.
Default `None` means no existing call site changed.

### Limitations of the probe, stated so the counts are read correctly

* `lit` matches `Bound` variables under the same bijection as free ones. `Bound` is
  effectively rigid (see §8 item 5), so wanted-fresh against given-`Bound` is the right
  reading ("the wanted asks for SOME remainder, the given supplies `t`"), but the reverse
  direction is also accepted and is not. Rare; it can only make `lit` too generous, never
  too strict.
* The `shape` and `lit` columns are per WANTED. Entailment is a property of the SET of
  wanteds of one signature (§8 item 2); §4's classification is done at the set level, the
  columns are not.
* The probe fires only when `rs` is non-empty, and only at the two signature callers of
  §2. A signature whose obligations were already discharged inside `inferAltTypes` never
  appears.

## 3. The sweep -- exact commands

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt -batch -J-Xmx3g core/compile core/copyResources

# the survey: ONE JVM PER FILE (corpus-run.sh's default), 154 corpus files, the 161-module
# stdlib booted inside every one of them
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh <OUT>/corpus-warn

# the confirming count: ONE JVM for the whole corpus
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh --batch <OUT>/corpus-warn-batch

# the totals, the shape table and the module table
tracker/tools/sigentail-agg.py <OUT>/corpus-warn

# the lists
tracker/tools/sigentail-agg.py --list nolit-row <OUT>/corpus-warn
tracker/tools/sigentail-agg.py --list concrete-ext <OUT>/corpus-warn
tracker/tools/sigentail-agg.py --tsv <OUT>/corpus-warn        # the whole deduped table
```

`tracker/tools/sigentail-agg.py` is new and commit-worthy. It reads every `.out` (or
`batch.log`) under a directory, keeps the `sigEntail` records, and DEDUPLICATES on
everything but the variable ids and the thread column -- because the stdlib boot happens
inside each of the 154 per-file invocations, so one stdlib obligation is written 154 times
and two JVMs number their variables from their own `Supply`. "Unique hit" below always
means that identity.

## 4. The counts

158 corpus files, one JVM each, the 161-module standard library booted inside every one:

```
records read           97325       (the stdlib boot repeats inside all 158 invocations)
unique hits             1502
  row obligations        914   (of which nolit 449)
  class constraints      588   (of which nolit  81)

shape               hits     lit   nolit
concrete-ext          20       0      20
multi-skolem         372     254     118
other-class          574     502      72
other-row            411     166     245
skolem-in-parts      125      50      75
```

The five shape rows sum to 1502, not to the 914/588 row/class split: `shapeOf` tests the
skolem COUNT before it looks for a `Part`, and `sigentail-agg.py` re-splits only the `other`
tag, so **14 class constraints are mixed into `multi-skolem` and `skolem-in-parts`**
(20+372+411+125 = 928, of which 914 are row obligations). The "20 of 914" headline below is
unaffected; a reader counting rows should subtract those 14.

Every one of the 1502 is a `sig` hit -- a DECLARED BINDING SIGNATURE. **Not one `ann` hit
anywhere in the corpus or the stdlib.** That is a fact about the CORPUS, not about the
site: the `ann` site (`Subst.typeCheck` :651, from `inferType`'s `Sig` case) carries the
identical soundness hole, and the reviewer produced the witness -- see §8 item 8. The
probe fires in 44 stdlib modules and 17 example modules; the ten heaviest:

```
module                         hits  nolit
Layout.Report                   150     36
Wide.Helpers                    149     55
Time.Helpers                    127     76
Time.Signatures                 118     55
Wide.Signatures                 114     22
Relation                        112     81
Algebra.Helpers                 111     14
Relation.Op                      75      1
Algebra.Signatures               61     17
Present.Signatures               55     16
```

The full table is `tracker/tools/sigentail-agg.py <OUT>/corpus-warn`.

**`concrete-ext` -- the shape the plan's refutation trick decides -- is 20 of the 914 row
obligations, and NONE of them is in the standard library.** Seventeen are in two example
modules that were written to exercise exactly this shape (`Present/WildChain.e`'s
`wildCells`, six; `Present/ProjectionCost.e`'s `proj5Pinned` and `proj6Pinned`, eleven) and
three are the pins `shouldfail/sig01`, `sig02`, `sig04`. `shouldfail/sig03` produces NO hit
at all -- §6 explains why -- and `shouldfail-controls/control08` is not in `corpus-run.sh`'s
globs; run separately it gives four hits, all `lit`:

```
sig:healthWith  concrete-ext  lit  r <- ((|health|), _)   given  r <- ((|health|), t)
sig:healthHas   concrete-ext  lit  r <- ((|health|), _)   given  r <- ((|health|), c)
sig:bumpWith    concrete-ext  lit  r <- ((|health|), t)   given  r <- ((|health|), t)
sig:tagged      multi-skolem  lit  t <- ((|health|), r)   given  t <- ((|health|), r)
```

and its fifth spelling, the LET-BOUND `localWith`, gives none -- again §6.

## 5. Classification of every non-literal hit

The classification is done PER SIGNATURE, not per line: a fresh existential is shared
between two wanteds of the same binding in a large fraction of them, so a witness must be
chosen once for the whole set. The mechanical part is
`tracker/tools/sigentail-entail.py` -- a TRIAGE AID, not a gate and not the check S2
designs: it
decomposes each given partition into ATOMS, records which atoms are KNOWN-DISJOINT
(they sit in different parts of one given partition), forces every free part that is the
only free part of its wanted, iterates, and then judges each wanted. Its two known
limitations, both of which only move a hit into the hand-checked bucket, are that it reads
only the FIRST given partition of a repeated left-hand side (`Time.Signatures.
nearestByDeduped` and `Algebra.Signatures.runningTotalFullViaWritten` have several), and
that it never derives disjointness by a chain. Everything it could not decide was read by
hand against the source; that is the list in (c).

### The split

```
row obligations                                   914
  (a) LITERAL: alpha-equivalent to a given        465
  (b) not literal, entailed                       414
  (c) NOT entailed -- a real hole                  32   in 12 signatures
  the three pins (sig01, sig02, sig04)              3
                                                 ----
                                                  914
```

The triage's own summary is `{'a': 465, 'b': 396, 'UNSURE': 53}`, and the 53 decompose as
32 (the twelve (c) signatures) + 3 (the pins) + 18 entailed by hand. So the (b) figure is
**396 settled mechanically plus 18 settled by hand** out of the 53 the
triage left open (`Present/WildChain.e`'s `wildCells`, `Present/ProjectionCost.e`'s
`proj5Pinned` and `proj6Pinned` -- 17 single labels each drawn from a concrete part the
signature already names -- and `Time/Signatures.e`'s `nearestByDeduped`, whose one
surviving wanted `h <- (fd, g)` follows from the given `out <- (sd, fd, k, g)`; that
module's header claims seven constraints were deleted as redundant and this survey
CONFIRMS the claim for the one that reached the checker).

Entailment is a property of the SET: a fresh existential is shared between two wanteds of
the same signature in 139 of the 308 signatures that have a row obligation at all.

### (b) Not literal, but entailed -- a sample of 20, one line of argument each

Read `x <- (p1, ..., pn)` as "x is the DISJOINT union of the parts". Every argument below
exhibits a choice for the wanted's fresh existentials (`A`) that satisfies it in every model
of the givens; where a binding has several wanteds the choice is made ONCE for the whole set,
because entailment is a property of the set, not of a line (see §5).

| # | module . binding | wanted | why it holds |
|---|---|---|---|
| 1 | `Relation.filterEq` (Relation.e:46) | `r <- (_1,_2)` and `r <- (_1,_2,_3)` | given `r <- (c0, c)`: take `_1=c`, `_2=c0`, `_3=(||)`; the two wanteds then force `_3` empty, which is the choice made |
| 2 | `Relation.filterEq` | `_4 <- (c)` | `_4` is fresh and occurs nowhere else: take `_4 = c` |
| 3 | `Relation.firstBy` (Relation.e:52) | `h <- (c, h)` | a row is itself plus the empty row: take `c = (||)` |
| 4 | `Relation.firstBy` | `h <- (_2,_3)` with `r <- (_1,_2)` and `r <- (_1,_2,_3)` | the pair of `r` wanteds forces `_3=(||)`, so `_2=h`; given `r <- (c0,h)` gives `_1=c0` |
| 5 | `Relation.join1` (Relation.e:179) | `r <- (_1,_2,_3)`, `ra <- (_1,_2)`, `rb <- (_2,_3)` | givens `r <- (k,r1,r2)`, `ra <- (k,r1)`, `rb <- (k,r2)`: take `_1=r1`, `_2=k`, `_3=r2` |
| 6 | `Relation.joinWithDefault` (Relation.e:94) | `_1 <- (extra)`, `r2 <- (_1,s')`, `r3 <- (_1,s',r')` | `_1=extra`; given `r2 <- (extra,c0)` forces `s'=c0`; given `r1 <- (s0,c0)` with the literal `r1 <- (s',r')` forces `r'=s0`; then `r3 = extra+c0+s0` is the given `r3` |
| 7 | `Relation.copyColumn` (Relation.e:267) | `ro <- (rs,so,ro')`, `r2 <- (rs,so)`, `ri <- (rs,ro')` | take `rs=(||)`, `so=r2`, `ro'=ri`; the givens `ro <- (r1,r2,t)` and `ri <- (r1,t)` give `ro = r2 + ri` |
| 8 | `Relation.leafRows` (Relation.e:74) | `r <- (child, c)` | given `r <- (parent, child, t)`: take `c = parent+t` |
| 9 | `Relation.leafRows` | `parent <- (parent, _)` and `_694 <- (child, _)` | the same `_` in both: take it empty, then `_694 = child` |
| 10 | `Relation.leftJoinOr` (Relation.e:85) | `r3 <- (_, t)` | given `r3 <- (r,s,t)`: take `_ = r+s` |
| 11 | `Relation.nearestDate` (Relation.e:232) | `r <- (_409, rfine)`, `_409 <- (_410, rsparse)`, `_400 <- (_409, rfine)` | given `r <- (rfine, rsparse)` forces `_409=rsparse`; then `_410=(||)` and `_400=r` |
| 12 | `Relation.partialLookup` (Relation.e:114) | `r' <- (base', val, key)` | `r'`, `base'` both fresh; given `kv <- (key,val)` makes `key`,`val` disjoint: take `base'=(||)`, `r'=key+val` |
| 13 | `Relation.Row.except` (Row.e:53) | `r <- (r2, _)` | given `r <- (r1,r2)`: take `_ = r1` |
| 14 | `Relation.Row.spanT` (Row.e:62) | `r <- (t', h)` | given `r <- (h,t)`: take `t' = t` |
| 15 | `Relation.Scan.groupBy'` (Scan.e:98) | `r <- (_1,_2,_3)`, `r <- (_2,_3)`, `h <- (_1,_2)` | the two `r` wanteds force `_1=(||)`, so `h=_2`; given `r <- (h,t)` gives `_3=t` |
| 16 | `Relation.Sort.reorderSome` (Sort.e:68) | `r <- (rs,ro)` and `s <- (rs,c)` with NO row givens | `rs` is shared, so choose it once: `rs=(||)`, `ro=r`, `c=s` |
| 17 | `Syntax.Relation.&'` (Syntax/Relation.e:58) | `a <- (_5,_3,_4)`, `r <- (_5,_3)`, `a <- (_3,_4)` | the two `a` wanteds force `_5=(||)`; then `_3=r` and, by the given `a <- (r,o)`, `_4=o` |
| 18 | `Layout.Report.pivotTabular` (Report.e:770) | `t' <- (v,i)`, `r <- (k,c')`, `r <- (c'',i)`, `r <- (k,v,i')` | given `r <- (k,v,i)` makes `k,v,i` pairwise disjoint: `t'=v+i`, `c'=v+i`, `c''=k+v`, `i'=i` |
| 19 | `Tree.fromRel` (Tree.e:82) | `r' <- (cid,pid)` and `t <- (t'', pid)` | given `t <- (pid,cid,h)` makes `pid,cid,h` pairwise disjoint: `r'=cid+pid`, `t''=cid+h` |
| 20 | `Report.SoftRelation.joinKey` (SoftRelation.e:31) | `t' <- (v,i)` and `r <- (k,t')` | one choice for the shared `t'`: `t'=v+i`; given `r <- (i,k,v)` then gives `r = k + t'` |

Two whole classes account for most of the rest and need no per-item argument:

* **the whole is its own part** -- `h <- (h, _)`, `r <- (_, r)`, `s <- (s, c)`
  (`Relation.Scan.sumBy`/`sumBy'`/`groupBy1`/`groupBy1'`/`avgBy'`, `Relation.Sort.only`,
  `Relation.Sort.recordOrd`): take the fresh part empty. 11 hits.
* **the whole is fresh** -- `_ <- (k)`, `_ <- (v,i)` where the parts are already known
  disjoint (`Relation.Pivot.defaultFulcrum`, `defaultFulcrumWithDefault`,
  `Report.SoftRelation.dynamicSchema`): take the whole to be their union. 6 hits.

### (c) NOT entailed -- real holes in shipped code

Every item below is a signature that ships (or ships in the example corpus) whose body
incurs a row obligation its declared constraints do not imply. Each is stated with the
model that breaks it. "Reachable" answers the brief's question: can a call in the corpus,
or a call a user could write against the published signature, reach the failure.

#### c1. `Relation.UnifyFields.unify1` -- `f1` is in no constraint
`core/src/main/resources/modules/Relation/UnifyFields.e:6-8`

    unify1 : forall (r:row) (r2:row) . (r <- (h,f,t), r2 <- (h,f2,t))
          => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
    unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r

Obligation (UnifyFields.e:8:27): `r2' <- (f1, _)` where `r2'` is `r2 \ f2 = h + t`
(the sibling wanted `r2 <- (f2, r2')` at 8:41 against the given `r2 <- (h, f2, t)` forces
it). So the body needs `f1` INSIDE
`h + t`. `f1` occurs in none of the two givens, so the model `h=(|a|)`, `t=(||)`,
`f=(|b|)`, `f2=(|c|)`, `f1=(|d|)` satisfies `Q` and falsifies `W`.
**Reachable:** yes. `core/examples/Algebra/shouldfail/alg03_unify_cross_schema.e` is the
corpus's negative control for the OTHER weakness of this signature (the shared `h` and
`t`); a call that satisfies those and still breaks `f1` is one line -- see §6.

#### c2. `Relation.partialLookup` -- `val` may sit inside `base`
`core/src/main/resources/modules/Relation.e:107-116`

    partialLookup : (RelationalComb rel, PrimitiveAtom a, kv <- (key,val), r <- (key,base))
                 => Field key a -> Field val a -> rel kv -> rel r -> rel r
    partialLookup bf ef mout min = partialLookup' bf ef mout min |> except {bf} |> rename ef bf

Obligation (Relation.e:114:3): `r2' <- (base', val, key)` -- `partialLookup'`'s
`r2 <- (key,val,base)` instantiated, with `base'` forced to `base` by the literal
`r <- (base', key)`. The three parts must be PAIRWISE DISJOINT. `key`/`base` are disjoint
(parts of `r`), `key`/`val` are disjoint (parts of `kv`) -- nothing makes `val` and `base`
disjoint. The model `key=(|k|)`, `val=(|v|)`, `base=(|v|)`, `r=kv=(|k,v|)` satisfies `Q`
and makes `W` UNSATISFIABLE (`v` in two parts of one partition), so the body cannot run at
all for that instantiation.
Two wanteds are counted against this signature; the argument above is for the first. The
second, `_606 <- (val, _607)` (Relation.e:116:6), is entailed RELATIVE TO THE SET -- taken
with `r <- (key, _607)` it forces `_607 = base` and then asks for `val + base`, which is
the same disjointness. It is in (c) only because the set as a whole has no model at the
instantiation above, not because it is independently unentailed.
**Reachable:** yes, from a one-line call; see §6.

#### c3. `DrilldownList.cons_Bracket` -- the givens are an applied type VARIABLE
`core/src/main/resources/modules/DrilldownList.e:18-20`

    cons_Bracket : forall f1 f2 rout r id. (Has rout f1, Has rout f2, Has rout r) =>
                   (Field f1 id, Field f2 id) -> DrilldownList r -> DrilldownList rout

`DrilldownList.e` imports `List`, `Native.List`, `Prim`, `Field`, `Function`,
`Relation.Row` and `Control.Functor` -- and NOT `Constraint`, where
`type Has a b = exists c. a <- (b, c)` lives (`Constraint.e:5`). `Relation.Row` imports
`Constraint` but does not export it. So `Has` is closed over as an ordinary implicitly
quantified type variable and the three constraints assert nothing; the probe prints them
as `((Has^435209B rout^435579S) r^435578S)`. The body needs `rout <- (f2, f1, r)` (as two
wanteds, DrilldownList.e:20:98 and 20:119). Any model works as a counterexample -- e.g.
`rout=(|p|)`, `f1=(|q|)`, `f2=(|s|)`, `r=(||)`.
Note that ADDING `import Constraint` would not fix it: `Has` gives that each part is
inside `rout`, not that `f1`, `f2` and `r` are pairwise DISJOINT, which is what
`append (single f2) . append (single f1)` needs. The honest signature is
`rout <- (f1, f2, r)`.
**Reachable:** yes; `core/examples/Present/DrilldownExplorer.e:29` documents these three
constraints as "how it accumulates one row out of the pairs", which is what they do not do.

#### c4. `Layout.Report.Keyed.softRelation` -- the options wrapper dropped `o <- (k, v)`
`core/src/main/resources/modules/Layout/Report/Keyed.e:52-56`

    softRelation : (AsPresentation prk, AsPresentation prvd)
                => prk k a -> prvd v b -> (Options ...) -> SoftRelation a b k v

The function it wraps, `Layout.Report.softRelation` (Report.e:635-642), declares
`exists o . o <- (k, v)` -- exactly the disjointness of the key columns from the value
columns. The `Keyed` wrapper declares only the two class constraints, and the probe shows
the obligation surviving at Keyed.e:59:6 as `o' <- (k, v)`. With `k` and `v` independent
universals a model can give both the same label.
**Reachable:** no corpus call -- every corpus use of `softRelation` resolves to
`Layout.Report`'s (the `Keyed` module is imported qualified, `as K`, and no module in
`core/examples` names `softRelation_K`). It is exported and callable.

#### c5. `Layout.Report.Keyed.keyValueTabular` -- same wrapper, seven obligations
`core/src/main/resources/modules/Layout/Report/Keyed.e:63-75`

Declared: `(Relational rel, Relational rel2)` and nothing else. The body reaches
`keyValueTabular_R` / `drilldownKeyValueTable_R`, whose `Layout.Report` originals declare
`r <- (k, v, i)` (Report.e:683-687). Seven wanteds survive, all over the signature's own
universals and none of them implied:

    r2 <- (i, v, k)                          Keyed.e:70:21
    r2 <- (k, v, i)                          Keyed.e:72:24
    i  <- (o', label)                        Keyed.e:73:42
    r2 <- (i, cid, pid, v, k)                Keyed.e:73:42
    r2 <- (r, i, k, v)                       Keyed.e:74:48
    i' <- (i, r)                             Keyed.e:74:48
    s' <- (i, k, v)                          Keyed.e:74:48

**Reachable:** no corpus call (as c4). Exported and callable.

#### c6. `Layout.Report.Relation.cutoffs` -- the declared result row contradicts the body
`core/src/main/resources/modules/Layout/Report/Relation.e:87-102` (`private`)

Declared `r <- (p, v, (|cutoff|))`, i.e. the result KEEPS the value column `v`. The body
ends `|> except {valueFld}`, which REMOVES it. The surviving obligation at
Relation.e:101:10 is `r'' <- (r, v)` -- and `v` is already a part of `r` by the signature's
own given, so this wanted is unsatisfiable for every non-empty `v`. The signature should
read `r <- (p, (|cutoff|))`.
**Reachable:** `cutoffs` is `private`; its caller `largers` (Relation.e:71-85) and the
public `cutoffDrilldownRel` (Relation.e:57-69) inherit it. The consequence here is a WRONG
PUBLISHED TYPE rather than a crash: at run time `cutoffs` returns `p + cutoff`, and
`largers`' natural join `rel ** cutoffs ...` joins on `p` alone and does the right thing.
Under an enforced check this signature has to be corrected before the module loads.

#### c7. `Layout.Report.Relation.others` -- the result row `r` is in no constraint
`core/src/main/resources/modules/Layout/Report/Relation.e:177-199` (`private`)

    others : forall v p pt s r d c. (s <- (p, v, d, c), l <- ((|cutoff|), s))
          => ... -> Relation s -> Relation r

`r` -- the RESULT row -- appears in no constraint at all, and `l` is a dangling variable
(it is quantified by nothing; see §8 item 5). Four obligations survive, each asking that a
literal cutoff column be disjoint from `p`:

    r' <- ((|cutoffCount|), p)                                   Relation.e:190:12
    r' <- ((|cutoffChild|), p)                                   Relation.e:191:12
    r' <- ((|cutoffGroup|), p)                                   Relation.e:192:12
    r' <- ((|cutoffChild,cutoffCount,cutoffGroup|), r)           Relation.e:197:13

Nothing says `p` lacks those three names.
**Reachable:** as c6, through `cutoffDrilldownRel`.

#### c8. `Wide.Helpers.melt2` / `melt3` / `melt4`, `Wide.Signatures.melt3Simple`
`core/examples/Wide/Helpers.e:318-325` (and :328, :339), `core/examples/Wide/Signatures.e:245`

    melt2 : (r <- (i, fa, fb), out <- (i, key, val), RelationalComb rel)
         => Field key String -> Field val t -> Field fa t -> Field fb t -> rel r -> rel out
    melt2 kf vf fa fb r =
      union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb} r)))
            (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa} r)))

Obligation (Helpers.e:324:10 and 325:10): `t <- (fa, _)` with `_` forced to `out \ val`
= `i + key`. So `key` must be disjoint from `fa` (and from `fb`). The givens make `key`
disjoint from `i` and `val`, and `fa`,`fb` disjoint from `i` -- never `key` from `fa`.
`melt2 fa vf fa fb r` type-checks and adds a column the row already has.
**Reachable:** yes, from a one-line call; see §6. (`melt3` has three such obligations,
`melt4` four, `melt3Simple` three.)

#### c9. `Algebra.Signatures.runningTotalFullViaWritten` -- the module's claim is false
`core/examples/Algebra/Signatures.e:255-277`

The module states "the twenty-one assumed, the two discharged": it declares the
twenty-one constraints the compiler wrote for `runningTotalFull` and defines the binding
as `runningTotalAsWritten`, whose two constraints are `r <- (ord, amt, rest)` and
`out <- (r, tot)`. The probe shows both surviving as wanteds:

    r <- (rest, b, a)     Algebra/Signatures.e:278:30
    d <- (c, r)           Algebra/Signatures.e:278:30

`a` and `b` (the `Field a a1`, `Field b a2` arguments, i.e. `ord` and `amt`) occur in NONE
of the twenty-one constraints, so the first is plainly not implied; the second needs
`c = m`, which nothing forces (the givens have `d <- (p,n,m)`, `r <- (p,n)` and
`l <- (c,e1,f1)`). The module loads today only because the obligations are dropped, so
its documented claim -- that the written-out constraint set implies the hand-written one
-- is NOT established by the compiler accepting it.
**Reachable:** the binding is an alias, so any call at a row where `a` or `b` is outside
`r` reaches the failure.


### The (c) list in one table -- and the plan's stop point

| # | signature | file:line | wanteds | tree |
|---|---|---|---|---|
| c1 | `Relation.UnifyFields.unify1` | `Relation/UnifyFields.e:6` | 1 | **stdlib** |
| c2 | `Relation.partialLookup` | `Relation.e:107` | 2 | **stdlib** |
| c3 | `DrilldownList.cons_Bracket` | `DrilldownList.e:18` | 2 | **stdlib** |
| c4 | `Layout.Report.Keyed.softRelation` | `Layout/Report/Keyed.e:52` | 1 | **stdlib** |
| c5 | `Layout.Report.Keyed.keyValueTabular` | `Layout/Report/Keyed.e:63` | 7 | **stdlib** |
| c6 | `Layout.Report.Relation.cutoffs` | `Layout/Report/Relation.e:87` | 1 | **stdlib** |
| c7 | `Layout.Report.Relation.others` | `Layout/Report/Relation.e:177` | 4 | **stdlib** |
| c8a | `Wide.Helpers.melt2` | `core/examples/Wide/Helpers.e:318` | 2 | examples |
| c8b | `Wide.Helpers.melt3` | `core/examples/Wide/Helpers.e:328` | 3 | examples |
| c8c | `Wide.Helpers.melt4` | `core/examples/Wide/Helpers.e:339` | 4 | examples |
| c8d | `Wide.Signatures.melt3Simple` | `core/examples/Wide/Signatures.e:245` | 3 | examples |
| c9 | `Algebra.Signatures.runningTotalFullViaWritten` | `core/examples/Algebra/Signatures.e:255` | 2 | examples |

Seven of the twelve are in the SHIPPED standard library (18 of the 32 wanteds), so the
plan's stop point -- "if (c) is non-empty in stdlib" -- **fires**. Stdlib source paths are
under `core/src/main/resources/modules/`.

The review re-derived every one of the twelve independently and could not refute any, and
it pushed EIGHT of them to a runtime witness this survey did not have (a crash, or a value
outside its printed type -- `LOADS` alone does not count). Its table, reproduced from
`tracker/loopmodel/SIG-1-REVIEW.md` §"(c) The table":

| # | item | really not entailed? | runtime witness? | severity |
|---|---|---|---|---|
| c1 | `Relation.UnifyFields.unify1` | yes -- `r2 <- (f2, r2')` against `r2 <- (h,f2,t)` forces `r2' = h+t`, and `f1` is in neither given | **YES** -- `unify1_UF d c rr rr2 : Relation (\|a,b\|)` = `<relation with Failure(NonEmpty[Renaming non-existent attribute])>` | **HIGH** -- shipped stdlib, unsound, one-line call |
| c2 | `Relation.partialLookup` | yes -- nothing gives `val # base` | **YES** -- `partialLookup k v kv rr : Relation (\|k,v\|)` = `Success(Map(k -> IntT(false)))`: a relation whose runtime header lacks `v`, i.e. outside its printed type | **HIGH** |
| c3 | `DrilldownList.cons_Bracket` | yes -- the three givens are an applied `Bound` variable; even in scope `Has` gives containment, not disjointness | **YES, twice** -- `projectT (toRow_DD bad2) {p=1,q=2,s=3} : Record (\|p\|)` prints `{s = 3, q = 2}`, and `... ! p` gives `<error: key not found: p>` | **HIGH** |
| c4 | `Layout.Report.Keyed.softRelation` | yes -- `o' <- (k, v)` with two class givens; `k=v=(\|a\|)` | no -- presentation-valued, no corpus call; exported and callable | MEDIUM |
| c5 | `Layout.Report.Keyed.keyValueTabular` | yes -- 7 wanteds over unconstrained universals; `r2=(\|a\|), i=v=k=(\|\|)` falsifies `r2 <- (i,v,k)` | no (as c4) | MEDIUM |
| c6 | `Layout.Report.Relation.cutoffs` | yes, and worse: `r'' <- (r, v)` with `r <- ((\|cutoff\|), v, p)` is UNSATISFIABLE for non-empty `v` | no -- the public `cutoffDrilldownRel` evaluates to `Success` with exactly the declared header | MEDIUM -- wrong published type; blocks the module under an enforced check |
| c7 | `Layout.Report.Relation.others` | yes -- and its own siblings `smallcount`/`smallid`/`smallgroup` DO declare `r <- (p, (\|cutoffCount\|))` etc. | no (same measurement as c6) | MEDIUM |
| c8a | `Wide.Helpers.melt2` | yes -- `t' <- (fa, out\val)` needs `key # fa` | **YES** -- `melt2 pp vcol pp qq src : Relation (\|vcol,pp,x\|)` = `Failure(Cannot union columns: expected Map(x, vcol), found Map(x, pp, vcol))` | MEDIUM -- examples |
| c8b | `Wide.Helpers.melt3` | yes (3, same shape) | **YES** (same Failure) | MEDIUM |
| c8c | `Wide.Helpers.melt4` | yes (4, same shape) | not run separately -- identical body shape | MEDIUM |
| c8d | `Wide.Signatures.melt3Simple` | yes (3) | **YES** (same Failure) | MEDIUM |
| c9 | `Algebra.Signatures.runningTotalFullViaWritten` | yes, both -- `a`,`b` occur in none of the 21 givens; `d <- (c, r)` refuted on an explicit model | **YES** -- `runningTotalFullViaWritten ordc amtc totc src : Mem (\|totc,other\|)` = `Failure(Operation refers to nonexistent column (ordc) ...(amtc)...)` | MEDIUM -- examples |

The review also found no false positive and no false negative in the (b) classification:
it re-derived samples #3, #4, #7, #8, #9, #16 and #18 by hand and hand-checked the fifteen
riskiest of the 396 mechanically-settled verdicts.

### The REPL evidence for the reachable ones

Each of these modules LOADS today with `-Dermine.useInterface=false`. The source is under
the scratch `probes/` directory; the point of each is that the call type-checks although
the callee's body cannot run at that instantiation.

```
-- c1: `f1` (here the field `d`) is in neither relation and in no constraint
import Relation.UnifyFields as UF ; import Syntax.Relation
field a, b, c, d : Int
rr  : [a, b] ; rr  = relation [{a = 1, b = 2}]
rr2 : [a, c] ; rr2 = relation [{a = 1, c = 3}]
bad = unify1_UF d c rr rr2                        -- LOADS  (S1.C1)

-- c2: `val` = `v` sits inside `base` = `r \ key`
field k, v : Int
kv : [k, v] ; kv = relation [{k = 1, v = 9}]
rr : [k, v] ; rr = relation [{k = 1, v = 0}]
bad3 = partialLookup k v kv rr                    -- LOADS  (S1.C3)

-- c3: `rout` is declared `(|p|)` while the body puts `q` and `s` in it
import DrilldownList as DD
field p, q, s : Int
bad2 : DrilldownList_DD (|p|)
bad2 = cons_Bracket_DD (q, s) empty_Bracket_DD    -- LOADS  (S1.C2)

-- c8: the key column and one melted column are the same field
import Wide.Helpers
field x : Int ; field p, q, vcol : String
src : [x, p, q] ; src = relation [{x = 1, p = "a", q = "b"}]
bad4 = melt2 p vcol p q src                       -- LOADS  (Wide.S1C4)
```

c4 and c5 have no corpus call: every corpus use of `softRelation` / `keyValueTabular`
resolves to the `Layout.Report` originals, which declare the constraints; the `Keyed`
module is always imported qualified (`as K`) and no module in `core/examples` names
`softRelation_K` or `keyValueTabular_K`. They are exported and callable.
c6 and c7 are `private` to `Layout.Report.Relation` and are reached through the public
`cutoffDrilldownRel`.
c9 is an alias whose body is `runningTotalAsWritten`, so any call at a row where `ord` or
`amt` is outside `r` reaches it.

## 6. REQUIRED: why `shouldfail/sig03` is refused at the call while `sig01` is accepted

**Because a `let`-bound type signature is thrown away by the renamer, and never reaches
the type checker at all.** `Lower.scala:185-187`:

```scala
case SLet(l, ss, b)     =>
  val (implicits, _) = bindings(ss, c)
  Let(c.pos(l.span), implicits, Nil, term(b, c))
```

`bindings(ss, c)` returns `(implicits, sigs)` and the `Let` is built with `Nil` EXPLICIT
bindings, and the second component of `bindings(ss, c)` is EMPTY BY CONSTRUCTION rather
than discarded: `Lower.bindings` (Lower.scala:287) is typed
`(List[ImplicitBinding], List[Nothing])` and its signature case is

```scala
case _: SSigStatement => ()  // 4.1
```

-- it never constructs an explicit binding at all, so there is nothing for the `SLet` case
to pass on. There is a SECOND drop site with the same cause: `Lower.scala:298-299`, where a
`where` attached to an equation **inside a `let` block** also builds `Let(..., Nil, ...)`,
because that `where` goes through `Lower.bindings` and not through
`NewPipeline.lowerLet`. So in sig03 `local` is an `ImplicitBinding`,
`Subst.inferBindingGroupTypes` (:752, the call at :780) gets an empty `es`, `typeCheckExplicitBinding` (:661)
is never called, `subsumeType` never skolemises anything, and there is no residual to
drop. `local`'s type is INFERRED -- `forall r t. r <- ((|health|), t) => {..r} -> Int`,
which is what `:type (r -> r ! health)` prints -- so the body of the `let` instantiates
that HONEST constraint at `{position = 2.0}` and the solver refutes
`(|position|) <- ((|health|), t)`. The refusal is ordinary inference doing its job at
`sig03_let_bound_signature.e:32:12` (the pin header and RESULTS.md say `20:12`; measured
today it is **32:12** -- the column is right, the line is stale, and the pins should be
corrected), with

    Row partitions are unsatisfiable at field 'ShouldFail.Sig03.health':
    the whole contains it but no part does

sig01 has the same body at the TOP LEVEL, where `NewPipeline.pairSigs` (NewPipeline.scala:367-376) does pair the signature into an `ExplicitBinding`. So `typeCheckExplicitBinding`
runs, `subsumeType` skolemises `r`, the wanted `r^S <- ((|health|), _)` lands in `rs`, is
dropped (:541-542, :553), and the published type is the DECLARED one, which carries no
constraint for the call to contradict.

Five measurements settle it (each a module under the scratch `probes/`, loaded with
`-Dermine.sigEntail=warn`; "probe" means whether a `sigEntail` line was printed for the
module's own binding):

| probe | program | verdict | probe line |
|---|---|---|---|
| P5 | sig01's signature, TOP LEVEL, never called | LOADS | **yes**, `concrete-ext nolit` |
| P1 | sig03's `let`, never called | LOADS | **none** |
| P2 | sig03's `let`, called at `{position, health}` | LOADS | none |
| P4 | sig03's `let`, called at TWO different rows that both have `health` | LOADS | none |
| P3 | control08's HONEST `let` signature, called at TWO different rows | LOADS | none |

P4 and P3 are the "honest programs" test the brief asks for: a let-bound binding used at
two different rows still generalises, because the binding is implicit and is generalised
the ordinary way -- the sig03 mechanism does not monomorphise anything and does not refuse
honest programs. It also does not help: it simply declines to read the signature.

Two further probes show that this is a SEPARATE BUG and that `where` is not affected
(`NewPipeline.lowerLet`, NewPipeline.scala:504-507, pairs `where` signatures):

| probe | program | verdict |
|---|---|---|
| P6 | sig01's signature on a **`where`**-bound binding, called at `{position}` | **LOADS** -- and the probe fires, `concrete-ext nolit`: the hole applies to `where` exactly as to the top level |
| P7 | `let g : Int -> Int; g x = x in g "hello"` | **LOADS** -- the let signature is ignored outright |
| P8 | the same, `where`-bound | **REJECTED**: `error: failed to unify type Int with type String` |
| -- | a `where` inside a `let` block (the second drop site, Lower.scala:298-299) | **LOADS** |
| -- | a `let` inside a `where` body | **LOADS** |

P7 is the clean statement of the defect: a `let`-bound signature can neither restrict nor
widen, and the compiler does not say so. The reviewer took P7 one step further and
evaluated it: `r1 : String = "hello"`, so the signature is not merely unenforced, it is
never consulted.

### The `let` drop is a REGRESSION of the new pipeline

The FUSED pipeline handled let signatures. Its `let` production
(`parsing/TermParsers.scala:224-243` at `d8a98a6^`) ran `gatherBindings(bs)` then
`checkBindings` and yielded
`Let(letLoc, rewriteShadowed(sh, p.extract._1), rewriteShadowed(sh, p.extract._2), body)`
-- **both** halves into `Let(pos, implicits, explicits, body)`; that is who filled
`explicits`. The replacement was written EMPTY: the `Lower.bindings` stub above was
introduced in **284afe1** ("Stage 3.4a: surface-to-core lowering with the tnodes
differential", 2026-08-30), whose promised item 4.1 never came; it became reachable behind
`-Dermine.pipeline=new` in **b8f06ae** (Stage 4.1c); and it became the ONLY module path
when **faa5769** ("Post-G1 D3 part 2: fused module path retired", 2026-08-31) deleted the
fused branch from `Session.dep`. The fused term grammar itself was deleted in **d8a98a6**.
A `where` on a TOP-LEVEL equation is unaffected because it goes
`NewPipeline.collectBlock` -> `lowerLet` -> `pairSigs` (NewPipeline.scala:346, 504-507,
367-376), which pairs by shared `V` -- but `lowerLet` has that one call site, which is why
a `where` nested inside a `let` falls back to `Lower.bindings` and is dropped too.

**Nothing pins it, and one comment asserts the opposite.**
`session/TolerantCheck.scala:326-328` states "A local explicit binding is what `assemble`'s
`lowerLet` makes of a SIGNED `let`/`where` binding" -- true for `where`, FALSE for `let`.
`TestTolerantCheck`'s "6.2: every LET and WHERE binder gets a type" repeats the claim in a
comment but asserts only `sw` from a `sigWhere` fixture, and `tracker/lsp-tests/Locals.e`
has `sigLocal`/`strict` (a `where`) and no signed `let`. So no LSP test pins
let-signature behaviour, and hover on a signed `let` binding silently shows the INFERRED
type instead of the declaration (`collectLocals`' `headType` returns `i.v.extract` for an
`ImplicitBinding`), quietly violating LSP Decision (a). This belongs to the LSP loop as
much as to this one.

**Is the mechanism the seed of the fix?** No -- it is a coincidence, and a second defect.
It refuses sig03 for the right reason (inference is complete here) but only because the
signature was dropped; the moment the `SLet` lowering is fixed, sig03 will behave exactly
like sig01 and be ACCEPTED again, unless S3's check is in place. That ordering matters:
**fixing `Lower.scala:185` / `:298` before S3 lands would silently turn sig03 from a
rejection into an acceptance.** Both should land together, and `TestSigEntail`'s "let-bound unconstrained
signature is refused today (at the call site)" property is pinning the wrong thing -- it
will go green for the wrong reason on the day the lowering is fixed.


## 7. Tier 0, with the flag OFF

Run in this worktree with nothing else on the machine (`pgrep -af sbt-launch` empty, no
file under `../ermine-scala/tracker/loopmodel/` touched in the preceding ten minutes),
one JVM at a time. Script: the scratch `tier0.sh`; the commands are

```
sbt -batch -J-Xmx3g core/compile core/copyResources
sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'
sbt -batch -J-Xmx3g 'core/testOnly *TestSigEntail *TestStage1Pins *TestReplDifferential'
tracker/tools/corpus-run.sh --batch <OUT>/batch-off
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh --batch <OUT>/batch-warn
tracker/tools/corpus-verdicts.py <OUT>/batch-off <OUT>/batch-warn
tracker/tools/repl-smoke.sh
```

| gate | result |
|---|---|
| `core/compile core/copyResources` | success. My own run was a NO-OP (1 s, nothing recompiled), so "no new warning" was not evidence; the reviewer's CLEAN build (`core/clean core/compile core/copyResources`, 104 s) emits **478 warning sites: 14 in `Subst.scala`** (lines 100, 101, 153, 158, 274, 478, 1460, 1464, 1604, 1605, 1978 -- all pre-existing, none within 30 lines of an edit) and **0 in `SigEntail.scala`** |
| `*TestLoopTrace` | **3/3 passed, no skips**, 64 s -- run with `-Dermine.looptrace` pointed at the main checkout's prebuilt binary (`diff -rq` shows `tracker/lean` is byte-identical between the two trees, so the binary is valid here and no `lake build` was needed). My own run reported 3/3 in 2 s with two properties SKIPPED because the binary is not built in this worktree; that spelling of the gate said nothing, and the real model differential does run. |
| `*TestSigEntail *TestStage1Pins *TestReplDifferential` | **41/41 passed, 0 failed, 0 errors** (215 s here, 285 s on the review's re-run under load) |
| corpus batch, flag OFF | **88 LOADED, 70 REJECTED, 0 UNKNOWN, 158 total** |
| corpus batch, flag WARN | **88 / 70 / 0 over 158** |
| `corpus-verdicts.py off warn` | **0 of 158 files differ** -- neither a verdict nor a message. The review strengthened this: all 158 `.out` files are BYTE-IDENTICAL once the `sigEntail` lines, the progress-bar lines and the embedded timings are removed. |
| `repl-smoke.sh` | **8/8 PASS**, 66 checks (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5), goldens byte-identical -- **but see the classpath note below**: my run measured the wrong tree, and the figure quoted here is the reviewer's re-run with the worktree classpath. |
| `.ei` under `off` vs the committed `tracker/g1-baseline` | (review) `G1 COMPARE: EQUIVALENT`; all 129 `.ei` byte-identical once the S5.2 `-- ermine-interface` key line, absent from the baseline, is ignored -- and that key line does not mention `sigEntail` |
| `.ei` under `off` vs `warn` | (review) **129/129 byte-identical** |

**The repl-smoke classpath trap.** `tracker/repl-classpath.txt` is a CHECKED-IN file of
ABSOLUTE paths into `/home/dmitry/research/ermine/ermine-scala` -- the MAIN checkout --
and `repl-smoke.sh:15` reads it verbatim. Run from this worktree it therefore tested the
main checkout's build, not the sig-entail build, so my "8/8 PASS, goldens byte-identical"
was vacuous as evidence about this change. Re-run with a classpath exported from THIS
worktree it is still **8/8 PASS, 66 checks**, so the conclusion survives. The review found
the same defect in `g1-validate.sh:12`, `lsp-smoke.sh:12`, `g1-diff.sh:17` and
`perf-bench.sh:94`: from any worktree those five gates silently measure another tree, which
is worse than a missing gate, and it belongs in `tracker/GATE-POLICY.md`.

`tracker/GATE-POLICY.md` records the corpus batch baseline as "85 / 69 / 0 over 154 as of
F3". The corpus has since grown by four files (158 now), and the three extra LOADED plus
one extra REJECTED account for exactly that; the policy's figure should be refreshed.

### Why `off` is byte-identical, beyond the gates

* `SigEntail.mode` is a read-once `val`; `SigEntail.warn` is `false` under the default and
  is the first test at every one of the three new sites.
* The two call sites pass `if (SigEntail.warn) Some(...) else None`, so under `off` no
  `Site` is allocated and no name is rendered.
* `subsumeType` gained a DEFAULT parameter, so no existing call site changed; the probe
  runs after the `ds`/`rs` partition and before the `entails` loop, reads `qs` and `rs`,
  and returns `Unit`. It touches no `Supply`, mints no variable, and writes nothing to
  `hm`.
* `Session.interfaceKey` (Session.scala:167) is unchanged, because the flag is NOT in
  `Constraints.GenRules.toString` -- so no `.ei` is invalidated and none needs rebuilding.
## 8. What S2 must decide

### READ THIS FIRST: the refutation trick reaches 4.7% of the corpus

The reviewer re-tagged all 914 row obligations structurally, independently of `shapeOf`,
and the buckets reproduce this report's counts on the nose (`SIG-1-REVIEW.md`
§"Taxonomy"):

| structural bucket | count | this report's tag |
|---|---|---|
| A `sk <- (concrete..., exactly 1 flex)` | **20** | `concrete-ext` (20) |
| B `sk <- (concrete..., rigid..., flex...)` | 3 | inside `multi-skolem`; all `lit` |
| C `sk <- (flexible parts only)` | **411** (2 parts 314, 3 parts 85, 4 parts 5, 7 parts 7) | `other-row` (411) |
| D `sk <- (vars, >=1 rigid)` | 310 | `multi-skolem` / `skolem-in-parts` |
| E `flex <- (concrete..., rigid...)` | 20 | `skolem-in-parts` / `multi-skolem` |
| G `flex <- (vars, >=1 rigid)` | 150 | `skolem-in-parts` |

* **Coverage as the plan literally states the trick: 20/914 = 2.2%** (bucket A, decided
  per label: `Q |= l in sk` iff `Q + {sk' <- (sk, {l})}` unsat).
* **Coverage after the generalisation that matters: 43/914 = 4.7%** -- add the **DUAL**
  for bucket E. `X <- (L, sk)` with `X` FRESH is entailed iff `Q |= l not-in sk` for every
  `l` in `L`, i.e. iff `Q + {sk <- ({l}, s')}` is unsatisfiable: the same single-label
  refutation the solver already performs, pointed the other way. **This bucket is where
  four of the eighteen stdlib (c) wanteds live** (c7's `r' <- ((|cutoffCount|), p)` and its
  two siblings, plus `r' <- ((|cutoffChild,cutoffCount,cutoffGroup|), r)`), and the dual
  correctly ACCEPTS the analogous obligations of `small` and `largers`. Bucket B's concrete
  half is decidable the same way; its skolem part is not, and all three are `lit` anyway.
* **C + D + G = 871/914 = 95.3% is out of reach of a refutation-shaped procedure in any
  form.** `Q + {sk' <- (sk, X)}` unsatisfiable decides "X MEETS sk in every model", which
  for a variable `X` is not "X is INSIDE sk" and admits no label-wise decomposition. These
  are pure variable-partition problems: containment and pairwise disjointness among
  skolems, `Bound`s and fresh remainders. **S2's decision procedure has to be a set-level
  solver over those**, with the literal-match-plus-warning fallback carrying ~95% of the
  standard library.
* One suspicion is REFUTED on the way: `other-row` (411) is exactly bucket C and contains
  no concrete label at all -- not one record in the sweep has the form
  `sk <- (concrete + TWO flexibles)` -- so relaxing "exactly one flexible" buys nothing and
  `other-row` is not `concrete-ext` in disguise.

Each item below is a shape or a mechanism the survey saw that the plan's refutation trick
(`Q` entails `L subset-of sk` iff `Q + {sk' <- (sk, L)}` is unsatisfiable) does not cover,
with an example from the sweep.

1. **`concrete-ext` is RARE, and it never occurs in the standard library.** The refutation
   trick is stated for "a concrete-label extension of one skolem, i.e. every wanted `!`,
   `cons`, `\` and `modify` generates". In the whole sweep `concrete-ext` accounts for
   20 of 914 row obligations: 17 in three EXAMPLE modules
   (`Present/WildChain.e`'s `wildCells`, `Present/ProjectionCost.e`'s `proj5Pinned` and
   `proj6Pinned` -- all entailed, each a single label drawn from a concrete part the
   signature already names), plus the four `shouldfail/sig0*` pins and
   `shouldfail-controls/control08`. **ZERO in the 161-module standard library.**
   What is NOT true -- an earlier draft of this report said it, and the review refuted it
   -- is that the stdlib's non-literal row obligations never mention a concrete label set.
   **43 of the 914 row obligations mention one; 26 of those are stdlib, all in
   `Layout/Report/Relation.e`, and 6 are `nolit`**: `others` 4 (which ARE the c7 holes),
   `small` 1, `largers` 1. Those six are exactly the shape the dual of the trick decides
   (see the taxonomy above), which is why the correction matters for S2's scope. What holds
   is the weaker statement: no stdlib obligation is `concrete-ext`, and the overwhelming
   majority of them are partitions of SKOLEMS and fresh remainders. A procedure that decides only
   `concrete-ext` would be right on the bug reports and silent on the library; the fallback
   ("must appear literally among the givens, with a warning") is what would actually run
   there, and §4 shows how much of the stdlib it would fire on.
   Example: `Relation.join1` (Relation.e:179) wants `r <- (_1,_2,_3)`, `ra <- (_1,_2)`,
   `rb <- (_2,_3)` -- no concrete label anywhere.

2. **Entailment is a property of the SET of wanteds, not of one wanted.** A fresh
   existential is shared between two wanteds of the same signature in 37 of the 95 stdlib
   bindings that have a row obligation at all. Choosing a witness per line is unsound in
   one direction (two lines may demand different values of the same variable) and
   incomplete in the other (`Relation.Scan.groupBy'`: `r <- (_1,_2,_3)` together with
   `r <- (_2,_3)` FORCES `_1` empty, and only then does `h <- (_1,_2)` follow from
   `r <- (h,t)`). The judgement in the plan is already set-shaped
   ("there is rho' agreeing with rho off F such that rho' models W"); the DECISION
   PROCEDURE must be too.

3. **The givens can hold an UNEXPANDED alias.** `qs` is `unbindExists(Free, substType(qz))`
   (Subst.scala:540-541) -- no `nf`, no `expandAlias`. `DrilldownList.cons_Bracket`'s givens
   arrive as `((Has^435209B rout) r)`, an application whose head is a type VARIABLE.
   Any check must normalise the givens first, or it compares against a constraint whose row
   content is invisible.

4. **An alias that is not in scope becomes a vacuous constraint, silently.** In
   `DrilldownList.e` (no `import Constraint`) `Has` is closed over as an ordinary
   implicitly-quantified type variable of kind `row -> row -> constraint`, so
   `(Has rout f1, Has rout f2, Has rout r)` constrains nothing at all. S2 should decide
   whether that is the entailment check's business or a separate diagnostic; note that
   ADDING the import does not fix the signature (`Has` gives each part is inside `rout`,
   not that the three are DISJOINT, which is what the body needs).

5. **A third variable flavour: `Bound`.** The plan's Lean statement adds
   `flavour : Var -> Rigid|Flex`. There is a third state in the compiler.
   `Forall.mk` (Type.scala:373) keeps only quantified variables that occur in the BODY:
   `nts = ats.filter(tm(_))` with `ats = typeVars(b)`. A variable that occurs ONLY in the
   constraint -- `h` and `t` of `Has r h` after `Annot.close`'s `.nf` -- is dropped from
   the binder list and survives as a dangling `Bound` variable inside the given
   (`Relation.Scan.avgBy'`: `r^497579S <- (h^486812B, t^486814B)`). `Type.fskvs` does not
   see it, so `subsumeType`'s `ds`/`rs` split treats a wanted mentioning only such a
   variable as skolem-FREE and RETURNS it. S2 must say what a `Bound` variable means in
   the judgement (it behaves as rigid, but nothing enforces that).

5b. **A given's existential and a wanted's existential are rendered and treated
   IDENTICALLY, and they are opposites.** `subsumeType` mints both as `Free`:
   `unbindExists(Free, q)` for the givens at :540 and `unbindExists(Free, substType(pz))`
   for the wanteds at :541, and the probe prints both with the same `A` tag. Semantically
   a GIVEN's existential is one the check must ACCEPT -- "some `c` exists", so it behaves
   as rigid, chosen by the caller -- while a WANTED's is one the check may CHOOSE. Both
   `SigEntail.literal` and `tracker/tools/sigentail-entail.py` conflate them, which can
   only make `lit` and "entailed" too GENEROUS, never too strict. A live example is
   `Relation.firstBy`, whose given is `r <- (c^471996A, h)`. S2's judgement must name the
   distinction (it is the same omission as item 5's `Bound`: the plan's
   `flavour : Var -> Rigid|Flex` has two states and the compiler has at least four --
   `Skolem`, `Bound`, given-existential and wanted-existential).

6. **Class constraints are in `rs` too, and their answer is discarded the same way.**
   `for (r <- rs) entails(qs,r)` (Subst.scala:541-542) runs the class-only `entails` and
   drops the Boolean, so a skolem-mentioning CLASS constraint is also unchecked here.
   S2 must say whether S3's check covers them -- they are checked elsewhere, at
   generalisation (`Subst.split`/`reduce` :383-391), which is why no corpus module is
   visibly broken by it -- or leaves them to that path.

7. **Blame.** A large share of the wanteds carry a location that is NOT in the module being
   checked: a builtin (`-`) or another file (`Layout/Format.e:21:14` while checking
   `Layout.Report.drilldownBarChart`). The message needs the "declared at" secondary
   location the plan already asks for, and S2 should decide which of the two is PRIMARY --
   an error whose only position is in the standard library is the failure mode
   `labelCheckEarly` was declined for on 2026-09-01 and then fixed.

8. **The `ann` site has the SAME DEFECT, and here is the witness -- this is not a "decide
   whether" item.** `typeCheck` (:651) checks a TERM ANNOTATION `e : T` and discards the
   skolem-mentioning wanteds exactly as `typeCheckExplicitBinding` does. The corpus never
   writes such an annotation (§4: zero `ann` hits), so the survey alone could not tell
   an unexercised site from a sound one. The reviewer settled it:

       a1 = ((r -> r ! health) : {..r} -> Int) { position = 2.0 }

   fires `ann:<annot> ... concrete-ext nolit  r^586561S <- ((|A1.health|), _^586563A)` with
   EMPTY givens, the module **LOADS**, and `a1` evaluates to
   `<error: key not found: health>`. The explicit-`forall` spelling
   `((r -> r ! health) : forall r. {..r} -> Int)` behaves identically
   (`res1 : Int = <error: key not found: health>`). The mechanism is the same as at a
   binding signature: `TyLower.annot` closes an annotation with `c.nf(...)`
   (TyLower.scala:250-257), so a `Forall` reaches `subsumeType` and skolems are minted.

   Consequences for S2/S3: the check MUST cover the `ann` site, and the acceptance
   criteria must say so. The plan's S3 lines name only sig01/sig02/sig04; a fifth pin
   (`shouldfail/sig05_annotated_lambda.e`) carrying the program above is the cheapest way
   to keep it covered. The residual design question is only the MESSAGE and the blame for
   an ascription, not whether to check it.

9. **Unsatisfiable givens.** The plan defers the policy to S2 and notes the precondition
   on `entails_iff_forall_label`. The sweep found no signature with unsatisfiable givens
   (every module that loads has a satisfiable one by construction), so the policy is a free
   choice; the cheapest is "if `Q` is unsatisfiable, the signature is vacuous and every
   wanted is entailed", which costs one extra solve per signature.

10. **`let`-bound signatures never reach the checker at all** (§6; two drop sites,
    `Lower.scala:185-187` and `:298-299`, both because `Lower.bindings` at `:287` is typed
    `(List[ImplicitBinding], List[Nothing])` and never builds one).
    Three consequences for this programme, all of which S2 must decide before S3 writes
    code: (i) an enforced check will be silent on every `let` signature, so the
    "let-bound signature" spelling of the plan's controls (`control08`'s `localWith`) tests
    nothing; (ii) fixing the lowering turns `shouldfail/sig03` from a rejection into an
    ACCEPTANCE unless the check lands in the same commit; (iii) `TestSigEntail`'s
    "let-bound unconstrained signature is refused today (at the call site)" property is
    pinning ordinary inference, not the hole, and should say so. `where` is unaffected --
    `NewPipeline.lowerLet` pairs its signatures, and probe P6 shows the hole applies there
    exactly as at the top level.

11. **The pins' recorded position is stale.** `shouldfail/sig03_let_bound_signature.e`'s
    header and `RESULTS.md:223` say the refusal is at `20:12`; measured today it is at
    **32:12** (`in local { position = 2.0 }` is line 32), which the review re-measured
    independently. Handed to the orchestrator with the rest of the out-of-report
    corrections (§9), not made here.


## 9. Files changed

| file | what |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/SigEntail.scala` | NEW. The flag, the record, `shapeOf`, `render`, the alpha matcher, `probe`. 221 lines, all of it inert under `off`. |
| `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala` | three edits: the `sig: Option[SigEntail.Site] = None` parameter on `subsumeType` (:534) with its comment, the probe call (:540), and the two call sites that pass a `Site` (:651 `typeCheck`, :669 `typeCheckExplicitBinding`). 18 lines added, 3 changed. |
| `tracker/tools/sigentail-agg.py` | NEW. Aggregates a sweep: totals, the shape table, the module table, `--list`, `--tsv`. Deduplicates across the 158 repeated stdlib boots by canonicalising variable ids and sorting both the parts of a partition and the given list. |
| `tracker/tools/sigentail-entail.py` | NEW. The triage aid of §5. Not a gate. |
| `tracker/loopmodel/SIG-1-SURVEY.md` | this report |

No `.e`, no test, no `tracker/lean/` file, and no pin was changed: S1 changes no verdict,
so `TestSigEntail`'s KNOWN HOLE properties and the four `shouldfail/sig0*` headers still
say what they said. The corrections that fall OUTSIDE this report -- sig03's recorded
position (`32:12`, not `20:12`) in its own header and in
`core/examples/shouldfail/RESULTS.md:223`, the note that `TestSigEntail`'s "let-bound
unconstrained signature is refused today" property pins ordinary inference rather than the
hole, the fifth `ann` pin and the S3 scope lines in `SIG-ENTAIL-PLAN.md`, and the
`GATE-POLICY.md` entries for the stale 85/69/0 baseline and the five worktree-blind gate
scripts -- are the orchestrator's, and are not made here.

Every `.ei` written by the sweeps and the probes was deleted (`find core/examples -name
'*.ei' -delete`); the checked-in ones under `tracker/g1-*` were not touched.

## Appendix: the probe modules of §6

They are five lines each; nothing in them is subtle, and they are reproduced here because
the scratch directory they were run from is not durable. Load each with
`ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" bin/ermine <file>`.

```
-- P5  top level, never called            LOADS, probe fires
healthOpt : forall r. {..r} -> Int
healthOpt r = r ! health

-- P1  let, never called                  LOADS, no probe
p1 = let local : forall r. {..r} -> Int
         local r = r ! health
     in 0

-- P2  let, called where `health` is present            LOADS, no probe
p2 = let local : forall r. {..r} -> Int
         local r = r ! health
     in local { position = 2.0, health = 1 }

-- P3  honest let signature at TWO different rows       LOADS, no probe
p3 = let f : forall r t. r <- ((|health|), t) => {..r} -> Int
         f r = r ! health
     in f { position = 1.0, health = 10 } + f { health = 3, mana = Null Int }

-- P4  sig03's let at TWO different rows                LOADS, no probe
p4 = let local : forall r. {..r} -> Int
         local r = r ! health
     in local { position = 1.0, health = 10 } + local { health = 3, mana = Null Int }

-- P6  sig01's signature, WHERE-bound                   LOADS, probe fires
p6 = f { position = 2.0 }
  where f : forall r. {..r} -> Int
        f r = r ! health

-- P7  a let signature that RESTRICTS                   LOADS  <-- the signature is IGNORED
p7 = let g : Int -> Int
         g x = x
     in g "hello"

-- P8  the same, WHERE-bound                            REJECTED: failed to unify Int with String
p8 = g "hello"
  where g : Int -> Int
        g x = x
```

Each module declares `field position : Double`, `field health : Int` and (P3, P4)
`field mana : Nullable Int`, and imports `Prelude`.
