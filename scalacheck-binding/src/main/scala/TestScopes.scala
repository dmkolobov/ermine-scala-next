package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.syntax.Explicit

import org.scalacheck._
import Prop.{ Result => _, _ }

/** Properties for lexical scoping: a binder (pattern variable, lambda, case
  * alternative, `let` or `where` binding) may share a name with — and shadow —
  * an import or an enclosing binder, and the outer meaning comes back when the
  * binder's scope ends.  Each property round-trips Ermine source through the
  * full pipeline: parse, type check, evaluate.
  *
  * These cover the bug filed upstream as core/examples/bugs/variableShadow.e
  * (a pattern variable could not shadow a global) and the related loss of a
  * shadowed outer binding after a `let`.
  */
object TestScopes extends Properties("Ermine scoping") {
  private lazy val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture._

  /** Function and List are imported so their exports are the globals we
    * try to shadow. */
  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Function" -> all, "List" -> all)

  /** Names exported by the imports above; using one as a binder used to be
    * "error: pattern variable shadows global binding ..." or
    * "error: term definition would shadow global definition ...". */
  val imported: Gen[String] = Gen.oneOf("id", "const", "flip", "curry", "head", "tail")
  val small: Gen[Int] = Gen.choose(0, 1000)

  def evalInt(stmts: String, e: String): Int = defAndEval(stmts, e, imps).extract[Int]

  // -- every binder form may shadow an import ---------------------------------

  property("a pattern variable may shadow an import") =
    forAll(imported, small) { (n, x) =>
      evalInt(s"f $n = $n", s"f $x") ?= x }

  property("an infix constructor pattern's variables may shadow imports") =
    forAll(small, small) { (x, y) =>
      evalInt("f (head :: tail) = head", s"f [$x, $y]") ?= x }

  property("a lambda binder may shadow an import") =
    forAll(imported, small) { (n, x) =>
      evalInt(s"f q = ($n -> $n) q", s"f $x") ?= x }

  property("a case binder may shadow an import") =
    forAll(imported, small) { (n, x) =>
      evalInt(s"f q = case q of\n  $n -> $n", s"f $x") ?= x }

  property("a let binding may shadow an import") =
    forAll(imported, small) { (n, x) =>
      evalInt(s"v = let $n = $x in $n", "v") ?= x }

  property("a where binding may shadow an import") =
    forAll(imported, small) { (n, x) =>
      evalInt(s"v = $n where $n = $x", "v") ?= x }

  // -- ...and the shadowed meaning comes back afterwards ----------------------

  property("an import shadowed in a pattern means itself again outside") =
    forAll(small, small) { (x, y) =>
      evalInt("f id = id", s"(f $x) + id $y") ?= x + y }

  property("an import shadowed in a let means itself again outside") =
    forAll(small, small) { (x, y) =>
      evalInt(s"v = (let id = $x in id) + id $y", "v") ?= x + y }

  property("an import shadowed in a where means itself again in later statements") =
    forAll(small, small) { (x, y) =>
      evalInt(s"v = id where id = $x\nw = id $y", "v + w") ?= x + y }

  property("an outer binder shadowed by a let survives the let") =
    forAll(small, small) { (x, y) =>
      // before the fix the outer `w` was deleted, not restored: undefined term
      evalInt(s"f w = (let w = $x in w) + w", s"f $y") ?= x + y }

  // -- a block's bindings scope over each other, letrec-style -----------------

  property("let bindings see later siblings") =
    forAll(small) { x =>
      evalInt(s"v = let fwd q = aux q\n        aux q = q\n    in fwd $x", "v") ?= x }

  property("a let binding shadowing an import binds earlier sibling references") =
    forAll(small) { x =>
      // fwd's rhs mentions `id` before the block rebinds it; letrec scoping
      // says fwd calls the block's id, not Function.id
      evalInt(s"v = let fwd q = id q\n        id q = q\n    in fwd $x", "v") ?= x }

  property("a where binding shadowing an import is what the body sees") =
    forAll(small) { x =>
      evalInt(s"v = id $x where id q = q", "v") ?= x }

  property("multiple equations still make one let binding") =
    forAll(small, small) { (x, y) =>
      evalInt(s"v = let me 0 = $x\n        me n = $y\n    in me 0 + me 1", "v") ?= x + y }

  // Kept, and it means more than it did: until LET-1 the `let` lowering
  // DROPPED the signature, so this pinned only that a signed `let` still
  // parses and evaluates -- `f` was inferred and the declaration happened
  // to agree.  The signature is now checked against the body
  // (`TestLetSignatures` pins the checking itself), so this exercises the
  // checker's explicit-binding path on top of the pairing.
  property("a signed let binding still pairs signature with definition") =
    forAll(small) { x =>
      evalInt(s"v = let f : Int -> Int\n        f q = q\n    in f $x", "v") ?= x }

  // -- shadowing binders are fresh variables, not the outer ones --------------

  property("a let binder's type is independent of what it shadows") =
    // with a shared variable this inferred f : String -> String
    typeChecks("f w = let w = \"s\" in w", "(f 42, f True)", imps)

  // -- what still must not parse ----------------------------------------------

  property("a top-level definition still may not shadow an import") =
    forAll(imported) { n =>
      no(sessionProof(implicit s => loadStatements(s"$n = 1", imps))) }

  property("let bindings do not leak into the enclosing scope") =
    no(typeChecks("v = let q = 1 in q", "q", imps))

  property("where bindings do not leak into the enclosing scope") =
    no(typeChecks("v = q where q = 1", "q", imps))

  // -- an import in scope under two names (here: id and id_F) ----------------

  val aliasImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Prelude" -> all, "Function" -> ((Some("F"), List[Explicit[Global]](), false)))

  // Post-G1 semantics (4.4/D3): plain Haskell scoping — a local binder
  // shadows only its own spelling, so a reference through the
  // module-affixed alias still reaches the import.  (The fused
  // pipeline's capture refusals retired with it.)
  // No Primitive import here: with Prelude too it would make `+`
  // ambiguous (the operator-imported-twice pin).
  val flipImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all,
        "Prelude" -> all, "Function" -> ((Some("F"), List[Explicit[Global]](), false)))

  locally {
    property("an alias-affixed reference survives a plain-name shadow (where)") =
      forAll(small) { x =>
        defAndEval(s"v = id_F $x where id q = 99", "v", flipImps).extract[Int] ?= x }

    property("an alias-affixed reference survives a plain-name shadow (let)") =
      forAll(small) { x =>
        defAndEval(s"v = let a = id_F $x\n        id q = 99\n    in a", "v", flipImps).extract[Int] ?= x }

    property("combined capture: id_F untouched AND plain id captured, one program") =
      forAll(small, small) { (x, y) =>
        defAndEval(s"v = id_F $x + id $y where id q = q + 90", "v", flipImps).extract[Int] ?= x + y + 90 }

    property("letrec: an early plain-name reference binds the block's shadowing binding") =
      forAll(small) { x =>
        defAndEval(s"v = let a = id $x\n        id q = q + 7\n    in a", "v", flipImps).extract[Int] ?= x + 7 }
  }

  property("shadowing an aliased import is fine when no reference is captured") =
    forAll(small) { x =>
      defAndEval(s"v = let id = $x in id", "v", aliasImps).extract[Int] ?= x }

  // -- references under ?[...] rebind like plain references ------------------

  property("a ?[...] reference is rebound by a shadowing let sibling") =
    forAll(small) { x =>
      defAndEval(s"f w = let a = ?[w] + 0\n          w = $x\n      in a", "f 0", imps).extract[Int] ?= x }

  property("a ?[...] reference is rebound by a shadowing where binding") =
    forAll(small) { x =>
      defAndEval(s"g w = ?[w] + 0 where w = $x", "g 0", imps).extract[Int] ?= x }

  // -- data constructors stay unshadowable; ordinary operators do not --------

  property("a data constructor operator may not be shadowed") =
    no(typeChecks("v = let (::) a b = 7 in 1", "v", aliasImps))

  property("an operator with its own fixity declaration can still be let-bound") =
    forAll(small, small) { (x, y) =>
      defAndEval(s"infixl 5 :+:\nv = let (:+:) a b = a + b in $x :+: $y", "v", imps).extract[Int] ?= x + y }

  // -- nested blocks ----------------------------------------------------------

  property("nested lets shadowing the same name restore outward layer by layer") =
    forAll(small, small, small) { (x, y, z) =>
      defAndEval(s"f w = (let w = (let w = $x in w) + $y in w) + w", s"f $z", imps).extract[Int] ?= x + y + z }

  property("a let inside a where clause shadows and restores independently") =
    forAll(small, small) { (x, y) =>
      defAndEval(s"f w = q + w where q = let w = $x in w", s"f $y", imps).extract[Int] ?= x + y }
}

