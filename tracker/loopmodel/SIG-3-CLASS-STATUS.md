# SIG-3c: what happens to CLASS constraints at a declared signature

**VERDICT: LEAVE IT AS IS in this programme -- but PIN it, do not call it sound.** The class path at a declared
signature has the SAME hole as the row path, it is reachable, and it crashes (P2/P8 below). It is still the wrong
thing for S3 to fix: ~2/3 of the class obligations a naive check would reject are rejected by an unrelated RENAMER bug
-- an out-of-scope class name in a written context silently becomes an implicitly quantified type variable (P10) -- so
the check would blame the signature for a name-resolution defect. Order: (1) the row check, as decided; (2) pin the
class hole as a `shouldfail` module + a ticket; (3) fix unresolved constraint heads in the renamer; (4) then the class
check, which the `Site` plumbing carries for free. Separately `split` :386, `ambiguities` :374, `defaultSubst` :377
are dead THIH leftovers, removable in a cleanup commit that is not S3's.

Lines are `core/src/main/scala/.../Subst.scala` at `sig-fixes` HEAD 9a0fd02 (the brief's :527-560/:638/:655/:1030 are
a15a97e's). Probes, outputs and `classify.py` are in this session's scratch `.../S3c/`, run with
`-Dermine.useInterface=false` on a snapshot of this worktree's classes taken before S3b began editing the stdlib.

## 1. What happens today

`subsumeType` (:534) splits the body's residual `ps` at :541 into `ds` (skolem-free) and `rs` (mentions a signature
skolem -- the obligations). `rs` is used twice and kept nowhere: the S1 probe at :547, then `for (r <- rs)
entails(qs,r)` at :548-549 whose Boolean is discarded. Only `ds` is returned, through `mkSimplified` (:566). `entails`
(:313) IS class-aware (`bySuper` :297 / `byInst` :305), so for a class obligation that loop computes exactly the
verdict a check needs and throws it away. `entail` (:394, gated on `isClassConstraint`) is a different function, live
only from `unifyType`'s Forall/Forall case (:262); it never sees a signature. So a class-constrained signature whose
body needs a class it does not provide is **accepted silently and fails at run time**:

    P2.e  plusA : forall a. a -> a -> a          -- body needs `Num a`, signature gives nothing
          plusA x y = x + y
    loads clean; warn record `sig:plusA other nolit (Num a^S)` with NO givens.
    R9.out:  :type plusA  ==>  forall a. a -> a -> a
             crashA       ==>  res0 : String = <error: (foo,bar) (of class scala.Tuple2)>

    P8.e  toOp2 : forall o r a. AsPresentation o => o r a -> Op r a   -- body needs `AsOp o`
          toOp2 x = asOp x
    loads clean; warn record `sig:toOp2 nolit (AsOp o^S)` given `(AsPresentation o^S)`.
    R8.out:  boom  ==>  res0 : Op (|foo|) Int =
             <error: Panic: unexpected runtime value in Relation.Op.asOp - Presentation(...)>

Both are class twins of `sig01`'s `<error: key not found: health>`. Inference alone is right -- the unsigned sibling
`plusB` gets `:type plusB == forall a. Num a => a -> a -> a` -- so the hole opens only through the signature.

Nothing fails earlier for want of a dictionary: class constraints carry NO evidence here. Every builtin instance's
`build` returns `Prim(())` ("no dictionary to build", `Lib.scala:1083`, `:1122`), and user class BODIES are refused
outright -- P7.e (`class MyC a where myc : a -> Int`) dies `error: class bodies are not supported (members die:
undefined type)` (`rename/NewPipeline.scala:504`). A class constraint is a pure presence check; what crashes is the
primitive underneath it. `byInst`'s `c.die("Unknown class")` (:307) is unreachable: both paths that mint a class `Con`
(`Lib.addClass`, `Session.scala:899`) register it.

## 2. Why the non-row control IS rejected

    P1.e  bad : forall a. a -> Int ; bad x = x + 1
    ==>   P1.e:5:1: error: failed to unify type !a with type Int

`unifyType` refusing to instantiate a skolem: the body's RESULT TYPE against the declared one, no constraint
consulted. `(+)` is `Num n => n -> n -> n` (`modules/Num.e:10`), so with `x : !a` the body is `!a -> !a` while the
signature demands `!a -> Int` -- the control dies on the arrow. The row case has no such handle: `healthOpt`'s body
and signature agree on `{..r} -> Int` and the whole disagreement lives in the discarded constraint. Remove the type
mismatch and the class control behaves like the row one -- that is P2, accepted. A declared class context is
load-bearing at the CALL site and only there: P11.e (`plusN : Num a => a -> a -> a`, `use = plusN "a" "b"`) is refused
`No instance for (Num String)`, while P2's identical call through the unconstrained signature is accepted and crashes.

## 3. Where class constraints do flow

* **Generalisation.** `inferAltTypesPrime` (:1009) ends in `generalize` (:1625) -> `mkSimplified` (:1936), where
  `reduce(classes)` (:1983) runs `toPNF` (:345) and dies `No instance for (...)` on a skolem-free wanted (P6.e `"a"
  + "b"`; P11.e's call site). The one live class rejection channel, and it fires only when the head's arguments are
  concrete enough for `isPNF` (:337) to say no.
* **Ambiguity / publication.** `ambiguitiesIn` (:1984) runs on the class half of the published residual; a SIGNED
  binding publishes its DECLARED type, an unsigned one the inferred context.
* **Never compared.** Nowhere is a declared class context checked against the inferred one. Correction for
  SIG-2-DESIGN item 6, which cites `:389` as "where they ARE checked": `:389` sits inside `split` (:386), which has
  **no caller anywhere in the tree**, nor do `ambiguities` (:374), `defaultSubst` (:377), `Ambiguity.default`
  (:361), `hm.defaults` (:94). The live site is `:1983` and it belongs to generalisation, not to the signature.

## 4. What a class check would cost, measured

One warn-mode boot (129 stdlib modules, no example files): 245 distinct signatures fire the probe, 560 unique records.
Judging each wanted's head against the givens' superclass closure (`classify.py`; hierarchy from `Lib.scala:1196-1308`
-- `Num -> PrimitiveNum -> {Primitive, Scaled}`, `RelationalComb -> Relational`, rest none), which is what `entails`
computes since no instance can fire on a bare skolem:

    strict (given's head must be the class Con)   277 class wanteds, 74 NOT entailed, 48 signatures
    heads matched by NAME instead                 326 class wanteds, 35 NOT entailed, 29 signatures
      in 10 modules: Layout.{Format,Legend,Presentation,Report}, Relation{,.Aggregate,.Predicate,.Scan},
      Report.SoftRelation, Syntax.Relation

The gap between the rows IS the renamer bug: an out-of-scope constraint head becomes an implicitly quantified variable
and the context is vacuous. P10.e (`f : Foo a => a -> a`) loads clean and `:type f` prints `forall a. Foo a => a -> a`
-- the junk is invisible. The stdlib is full of it: `Layout/Report.e` imports `asPresentation` but not
`AsPresentation`, so its written `AsPresentation pr` givens print as `AsPresentation^537025B` (Bound); `Relation.e:78`
spells `RelationalComp` (no such class) and `Syntax/Relation.e` spells `relalComb`. In my probes, which
`import Relation.Op`, the same `AsOp op` context DOES resolve to the real Con -- per-module scope, not syntax.

The 35 residual holes are real, in three families. (a) **Wrong direction**, 14 signatures: wanted `RelationalComb rel`
from a given `Relational rel` (`Relation.join1`, `joinBy`, `joinBy'`, `copyColumn`, `unsafeRightJoin`,
`Layout.Report.{keyValueTabular,pivotTabular,drilldownKeyValue*}`, `Relation.Aggregate.aggregateBy`,
`Relation.Predicate.select{,Not}Nulls`, `Report.SoftRelation.dynamicSchema`, `Syntax.Relation.**'`).
(b) **`Primitive` from `Unscaled`/`Scaled`/nothing**: `Layout.Format.truncate`, `Layout.Presentation.markdown` and
`truncate`, `Layout.Report.{defaultUnscaled,scaled,barChart,timeSeriesChart,drilldownBarChart*}`,
`Layout.Legend.fromRowWithFormat`. (c) **Missing outright**: `Layout/Report.e:1423` `pieChart` declares only
`r <- (labels, value, o), Relational rel` yet its body calls `asPresentation labelPres`/`valuePres`, so a caller
passing a value that is not a `Presentation`/`Op`/`Field` gets P8's Panic out of a shipped API -- likewise
`treemapChart`, `orderedScanner` (`Relational rel`, no givens) and `Relation.Scan.pickByK` (`Eq k2` given `Eq k`).

## 5. The three options

**Leave as is (recommended).** Zero code. The cost is that the hole stays, so it must be NAMED: a pinned `shouldfail`
module, a ticket, a line in RESULTS.md -- else the next reader takes the row fix to cover classes.

**Add the analogous check.** Cheap in code, expensive in corpus. The `Site` parameter on `subsumeType` (:534) carries
it for free -- same two sites (`:651` `ann`, `:669` `sig`), same `rs` -- and the decision procedure is already CALLED
at :549: `if (!entails(qs,r)) die(...)` is the whole check, with `entail`'s message (:399) as the wording. Switched on
today it refuses 74 obligations in 48 stdlib signatures (35 in 29 after name normalisation), of which the first ~39 are
the renamer bug; it also needs the editor path (`TolerantCheck.scala:669`) and a policy for `byInst` on partially
concrete heads (`Primitive (Nullable a)`). Worth doing AFTER the renamer fix, when the residue is the ~35 honest ones.

**Remove the dead machinery.** Small and safe, but THIH leftovers only: `split` :386, `ambiguities` :374,
`defaultSubst` :377, `Ambiguity.default` :361, `hm.defaults` :94 (all callerless) and the stale comment at :677. NOT
`entails` at :548-549 -- SIG-2-DESIGN keeps those two lines (an `.ei` diff cannot observe a lost `die`) and they are
option 2's hook. Own commit, no verdict change, Tier 0.
