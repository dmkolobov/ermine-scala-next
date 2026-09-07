module Present.Signatures where

{- THE SIGNATURES IN `Helpers.e`, AND MACHINE-CHECKED PROOF THAT THEY SAY WHAT
   THE COMPILER INFERS -- or, where they do not, exactly how much smaller they
   are and why the difference is legitimate.

   For each helper treated here this file holds

     xFull       -- the body, carrying VERBATIM the constraint set the compiler
                    infers for it when the signature is REMOVED;
     xDeduped    -- the same set with the redundant members deleted, DEFINED AS
                    `= xFull`; and, where the two are equivalent,
     xAsWritten   -- the signature `Helpers.e` actually carries, defined in BOTH
                    directions so the two are proved equivalent rather than
                    merely comparable;
     xSimple      -- where the written signature is a SPECIALISATION rather than
                    an equivalent, the body written out at that signature, so
                    that checking it proves the body really has that type.

   A definition `p = q` is the proof: checking it means ASSUMING p's constraints
   and DISCHARGING q's, so if this module compiles then p entails q.

   The inferred sets were read out of a signature-free scratch module compiled
   with `-Dermine.useInterface=true`, whose `.ei` is the compiler's own
   rendering of what it inferred, on 2026-09-07 at the adopted row-solver
   defaults. Reproduce with the recipe in `tracker/loopmodel/E4-EXAMPLES.md` §G4.

   ---------------------------------------------------------------------------
   A FINDING THAT SHAPES THIS FILE, and that a reader should know about

   THREE of the helpers cannot have their inferred signature written down at
   all: `styledBy`, `hiddenBy` and `outOfRange`. Each infers a constraint set
   containing an EXISTENTIALLY QUANTIFIED CLASS, printed as

       (exists (AsOp: b). AsOp op, Relation.Op.AsOp op)

   -- a variable named after the class, of an unnamed kind, applied as if it
   were the class, ALONGSIDE the real class constraint. There is no source
   syntax for that, so `xFull` for those three is impossible to write and the
   file gives `xSimple` (or the largest writable generalisation) instead.

   It is NOT a property of every `AsOp`-polymorphic body: `scaledBy` and
   `unreconciled` are equally `AsOp`-polymorphic and infer only the real class.
   Measured with each body alone in a module, which is the precaution this
   file's own header demands. Whether the existential class is a printer
   artefact or a real unresolved class variable in the residual is an open
   question, recorded in `tracker/loopmodel/E4-EXAMPLES.md` section 4.

   ---------------------------------------------------------------------------
   STAGE S3 HAS LANDED IN THE WORKING TREE (committed as a2789a8), AND IT CHANGES THESE

   Every inferred set quoted below was read out BEFORE stage S3's uncommitted
   change to `Subst.scala`, which (i) deletes the `a <- (a)` TAUTOLOGY from
   published residuals and (ii) gives `NormalPart` a `hashCode` consistent with
   its `equals` so permuted duplicate partitions stop being published. That
   change is in the working tree and was compiled in at 03:56 on 2026-09-07;
   re-measured against it, the same bodies now infer:

       scaledBy   : (Relation.Op.AsOp b, PrimitiveNum a) => a -> b c a -> Op c a
                    -- `c <- (c)` GONE
       outOfRange : (exists (AsOp: d) (AsOp1: d) (e: rho). RelationalComb b,
                     Primitive a, AsOp1 opl, c1 <- (c, e), AsOp1 Op, AsOp Op,
                     AsOp opl) => …
                    -- `c <- (c)` GONE; the existential class REMAINS
       unreconciled : 11 existentials, 13 constraints, 8 of them partitions
                    -- one fewer than the 14 quoted below

   NOTHING HERE STOPS CHECKING. A signature that carries a true-but-redundant
   constraint is still a legal signature, so `taut`, `scaledByFull` and
   `unreconciledFull` all still compile and all their entailment proofs still
   hold; what has changed is that the sets they quote are now the compiler's
   OLD answers. Read them as "the residual before S3" and the file as a record
   of what S3 removed -- which is, incidentally, exactly what `taut` /
   `tautIsFree` proved was safe to remove.

   The permutation facts (`permA` / `permB` / `permBackA`) survive S3: the
   `hashCode` fix stops the same constraint being PUBLISHED twice in two
   rotations, and does not stop two GENUINELY different partitions over the same
   row appearing together -- `Present/ProjectionCost.ei`'s `proj5` publishes four
   at once, distinguished by their existential remainders.

   KEEP THIS FILE SEPARATE from `Helpers.e`: an annotated copy of a body in the
   same module as the unannotated one perturbs what the unannotated one infers.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.SortStrategy as SS
import Layout.Color
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Syntax.List

-- ============================================== two facts used throughout

-- `r <- (r)` is a TAUTOLOGY: a row is the disjoint union of itself and nothing.
-- It is discharged at a call site with no constraint in scope at all, so every
-- occurrence of it in a residual is pure noise. It shows up in `scaledBy` and
-- `outOfRange` below because `prim` contributes an empty row that the solver
-- records as a partition rather than dropping.
taut : r <- (r) => Legend_Lg r -> Legend_Lg r
taut x = x

tautIsFree : Legend_Lg r -> Legend_Lg r
tautIsFree x = taut x

-- The right-hand side of a partition is a SET: the rotations entail one
-- another, so of any group of permuted copies all but one are noise. Every
-- `.ei` below prints the partition in a different rotation from the source, and
-- this is why that is not a difference.
permA : t <- (a, b) => Legend_Lg t -> Legend_Lg t
permA x = x
permB : t <- (b, a) => Legend_Lg t -> Legend_Lg t
permB x = permA x
permBackA : t <- (a, b) => Legend_Lg t -> Legend_Lg t
permBackA x = permB x

-- ==================================================================== withFormats
--
-- INFERRED (verbatim, only the variable names spelled in source syntax):
--
--     forall {a} (r: rho) (a1: a) (r1: rho) (t: rho).
--       t <- (r1, r) => Legend r -> Format a1 -> Row r1 -> Legend t
--
-- The written signature is the SAME constraint with the partition rotated and
-- the variables renamed to say what they mean. Both directions are proved, so
-- the two are equivalent and the rotation really is free.

withFormatsFull : t <- (r1, r) => Legend_Lg r -> Format_Fmt a -> Row r1 -> Legend_Lg t
withFormatsFull klg fmt mrow = klg ++_Lg fromRowWithFormat_Lg fmt mrow

withFormatsAsWritten : r <- (k, m) => Legend_Lg k -> Format_Fmt a -> Row m -> Legend_Lg r
withFormatsAsWritten = withFormatsFull

withFormatsBack : t <- (r1, r) => Legend_Lg r -> Format_Fmt a -> Row r1 -> Legend_Lg t
withFormatsBack = withFormatsAsWritten

-- ======================================================================= labelled
--
-- INFERRED:
--
--     forall {a} (pr: rho -> * -> *) (r: rho) (a1: a) (s: rho) (t: rho).
--       (t <- (s, r), AsPresentation pr)
--       => pr r a1 -> String -> Legend s -> Legend t
--
-- Again a rotation, and again equivalent. Note that the class constraint here
-- is `AsPresentation`, which the compiler DOES resolve to the real class --
-- unlike `AsOp`, below.

labelledFull : (t <- (s, r), AsPresentation pr)
            => pr r a -> String -> Legend_Lg s -> Legend_Lg t
labelledFull pr lbl rest = legend_Lg pr lbl ++_Lg rest

labelledAsWritten : (t <- (r, s), AsPresentation pr)
                 => pr r a -> String -> Legend_Lg s -> Legend_Lg t
labelledAsWritten = labelledFull

labelledBack : (t <- (s, r), AsPresentation pr)
            => pr r a -> String -> Legend_Lg s -> Legend_Lg t
labelledBack = labelledAsWritten

-- ======================================================================= sortedBy
--
-- INFERRED:
--
--     forall {a b} (pr: rho -> * -> *) (r: rho) (a1: a)
--            (pr1: rho -> * -> *) (r1: rho) (a2: b) (t: rho).
--       (t <- (r1, r), AsPresentation pr1, AsPresentation pr)
--       => SortDirection -> pr r a1 -> SortDirection -> pr1 r1 a2
--       -> SortStrategy t
--
-- The rotation again, and the same equivalence. This is the whole content of
-- `Layout.SortStrategy.(++)`: two strategies compose iff their column sets are
-- disjoint, and the ORDER of the two halves in the partition is irrelevant even
-- though the order of the two strategies is not.

sortedByFull : (t <- (r1, r), AsPresentation pr, AsPresentation pr1)
            => SortDirection_SS -> pr r a -> SortDirection_SS -> pr1 r1 b
            -> SortStrategy_SS t
sortedByFull d1 x d2 y = sortBy_SS d1 x ++_SS sortBy_SS d2 y

sortedByAsWritten : (t <- (r, s), AsPresentation p1, AsPresentation p2)
                 => SortDirection_SS -> p1 r a -> SortDirection_SS -> p2 s b
                 -> SortStrategy_SS t
sortedByAsWritten = sortedByFull

sortedByBack : (t <- (r1, r), AsPresentation pr, AsPresentation pr1)
            => SortDirection_SS -> pr r a -> SortDirection_SS -> pr1 r1 b
            -> SortStrategy_SS t
sortedByBack = sortedByAsWritten

-- ======================================================================= scaledBy
--
-- INFERRED, verbatim and writable:
--
--     forall a (b: rho -> * -> *) (c: rho).
--       (c <- (c), Relation.Op.AsOp b, PrimitiveNum a) => a -> b c a -> Op c a
--
-- Note what is NOT here: `scaledBy` is `AsOp`-polymorphic and infers the REAL
-- class, not the existential class variable that `styledBy`, `hiddenBy` and
-- `outOfRange` produce. So that defect is not a property of `AsOp` as such.
--
-- The interesting member is `c <- (c)`, the tautology -- `prim` contributes an
-- empty row that the solver records as a partition rather than dropping.
-- `scaledByDeduped` discharges it from nothing, which proves it carries no
-- information. (Stage S3 removes it from the residual; see the header.)

scaledByFull : (c <- (c), AsOp b, PrimitiveNum a) => a -> b c a -> Op_Op c a
scaledByFull k o = asOp_Op o /_Op prim_Op k

scaledByDeduped : (AsOp b, PrimitiveNum a) => a -> b c a -> Op_Op c a
scaledByDeduped = scaledByFull

scaledByBack : (c <- (c), AsOp b, PrimitiveNum a) => a -> b c a -> Op_Op c a
scaledByBack = scaledByDeduped

-- ===================================================================== outOfRange
--
-- INFERRED -- and this one is NOT writable, for the reason in the header:
--
--     forall (opl: rho -> * -> *) (c: rho) a (b: rho -> *) (c1: rho).
--       (exists (d: rho) (AsOp: e) (AsOp1: e).
--          AsOp opl, RelationalComb b, AsOp1 Op, AsOp Op, AsOp1 opl,
--          c <- (c), c1 <- (c, d), Primitive a)
--       => opl c a -> a -> a -> b c1 -> b c1
--
-- EIGHT constraints, of which four are the two class variables applied twice
-- each, one is the tautology `c <- (c)`, and exactly ONE carries information:
-- `c1 <- (c, d)`, the partition that says the range column is in the relation.
--
-- `Helpers.e` writes that one, specialises `opl` to `Field` and `b` to
-- `Relation`, and strengthens `Primitive` to `PrimitiveNum`. Checking the body
-- at that signature proves the specialisation sound.

outOfRangeSimple : (r <- (v, o), PrimitiveNum n)
                => Field v n -> n -> n -> Relation r -> Relation r
outOfRangeSimple f lo hi =
  filter_Pred (f <_Pred prim_Op lo ||_Pred f >_Pred prim_Op hi)

-- The generalisation that IS writable: keep `AsOp` and `RelationalComb`, drop
-- the tautology and the duplicated class variables. This is the largest
-- honest statement of `outOfRange`'s type.
outOfRangeGeneral : (r <- (v, o), AsOp op, RelationalComb rel, PrimitiveNum n)
                 => op v n -> n -> n -> rel r -> rel r
outOfRangeGeneral f lo hi =
  filter_Pred (asOp_Op f <_Pred prim_Op lo ||_Pred asOp_Op f >_Pred prim_Op hi)

-- =================================================================== unreconciled
--
-- The extreme case -- and, unlike `styledBy`/`hiddenBy`/`outOfRange`, one whose
-- inferred set IS writable: every class in it is a real class. It is written
-- out below as `unreconciledFull`, and `unreconciledSimple = unreconciledFull`
-- is the proof that the one-partition signature `Helpers.e` carries is a sound
-- specialisation of it.
--
-- INFERRED, verbatim (only the variable names spelled in source syntax):
--
--     forall (a: rho -> * -> *) (b: rho) c (d: rho -> * -> *) (e: rho)
--            (f: rho -> * -> *) (g: rho) (h: rho -> *) (i: rho).
--       (exists b1 d1 e1 f1 c1 d2 j e2 f2 c2 c3.
--          i <- (j, e, d2, d1, c1),  g <- (e1, d1),  c3 <- (f2, e2, d2),
--          AsOp a,                   e <- (f2, e2),  AsOp d,
--          RelationalComb h,         PrimitiveNum c, b <- (e2, d2),
--          b1 <- (e, d2, d1, c1),    c2 <- (f1, e1, d1),
--          b1 <- (c1, f1, e1, d1),   AsOp f,         c3 <- (f1, e1))
--       => a b c -> d e c -> f g c -> c -> h i -> h i
--
-- ELEVEN existentials and FOURTEEN constraints, for a helper whose meaning is
-- "these three columns are in the relation". The written signature is ONE
-- partition. The gap is not the solver being wrong -- the inferred set is what
-- `abs (total - (p1 + p2))` really needs, one partition per intermediate `Op`
-- -- it is the difference between the type of a body and the type of an idea,
-- and it is the entire argument for `Helpers.e` writing its signatures by hand:
-- a caller who had to discharge fourteen constraints per call site would not
-- use the helper twice.

unreconciledFull
  : forall opA rB n opD rE opF rG rel rI.
    ( exists b1 d1 e1 f1 c1 d2 j e2 f2 c2 c3.
      rI <- (j, rE, d2, d1, c1)
    , rG <- (e1, d1)
    , c3 <- (f2, e2, d2)
    , AsOp opA
    , rE <- (f2, e2)
    , AsOp opD
    , RelationalComb rel
    , PrimitiveNum n
    , rB <- (e2, d2)
    , b1 <- (rE, d2, d1, c1)
    , c2 <- (f1, e1, d1)
    , b1 <- (c1, f1, e1, d1)
    , AsOp opF
    , c3 <- (f1, e1) )
 => opA rB n -> opD rE n -> opF rG n -> n -> rel rI -> rel rI
unreconciledFull p1 p2 total tol =
  filter_Pred (abs_Op (asOp_Op total -_Op (asOp_Op p1 +_Op asOp_Op p2))
                 >_Pred prim_Op tol)

-- The proof. Assuming ONE partition and discharging fourteen constraints and
-- eleven existentials: if this module compiles, the written signature entails
-- the inferred one, which is what "specialisation" has to mean.
unreconciledSimple : (r <- (a, b, c, o), PrimitiveNum n)
                  => Field a n -> Field b n -> Field c n -> n
                  -> Relation r -> Relation r
unreconciledSimple = unreconciledFull

-- ======================================================================== chartOf
--
-- The opposite lesson. INFERRED:
--
--     forall {a b} (xa: a) (ya: b) c d e f (f1: * -> *) z.
--       (Primitive xa, Primitive ya)
--       => String -> Axis xa -> Axis ya
--       -> (c -> d -> e -> f -> ChartSeries xa ya) -> c -> d -> e -> f
--       -> Report f1 z
--
-- The compiler infers NOTHING about the rows: the series mode is an opaque
-- function and its four arguments are four unrelated type variables. The
-- inferred type is perfectly sound and completely useless -- it would let a
-- caller pass a series selector for one relation and a value selector for
-- another.
--
-- The written signature adds the row structure the mode is going to need
-- anyway, `r <- (sr, xr, yr, o)`, so the mistake is caught at the CALL SITE
-- rather than inside the chart. This is a case where the hand-written signature
-- is strictly more informative than the inferred one, and checking the body at
-- it is the proof that the extra information is true.

chartOfSimple : forall s x y r sr xr yr sa xa ya rel f z.
                (exists o. AsPresentation s, AsOp x, AsOp y,
                           r <- (sr, xr, yr, o), Relational rel,
                           Primitive xa, Primitive ya)
             => String -> Axis xa -> Axis ya
             -> (s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> ChartSeries xa ya)
             -> s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> Report f z
chartOfSimple title xax yax mode s x y rel =
  chart_K ([chartTitle_O := title]_Opt) xax yax [mode s x y rel]
