package com.clarifi.reporting

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.{ NewPipeline, Renamer }
import com.clarifi.reporting.ermine.surface.{ Anchors, SClassStatement, SDatabaseBlock, SEquation,
  SPat, SPAs, SPParen, SPSig, SPVar, SPrivateBlock, SStatement, Span }
import com.clarifi.reporting.ermine.{ Pretty, SigEntail }
import com.clarifi.reporting.ermine.lsp.{ Diagnostics, Documents, Json, QuickFix, Resident }
import com.clarifi.reporting.ermine.session.{ Printer, Session => S, SessionEnv, TolerantCheck }

import org.scalacheck._
import Prop._
import scalaparsers.{ Death, Supply }

import java.io.File

/** Stage 2 item 5.4: the editor's type checker.
  *
  * Session.loadModule stops at the first Death, which is right for a
  * batch load and useless in an editor.  TolerantCheck reports every
  * independent problem, checks the healthy definitions of a broken
  * file, and refuses to infer anything that depends on something it
  * could not check.
  *
  * The silence-on-good-code half lives in TestTolerantRead's 180-file
  * sweep (the editor checker must find nothing the batch loader
  * accepts); these are the behaviours that need broken input.
  */
object TestTolerantCheck extends Properties("Tolerant check") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)

  /** SIG-3: the same fixture with the signature-entailment check ON, for the two properties
    * that are about it.  A `val`, so the stdlib boots once. */
  private lazy val fxError = ErmineFixture(sigEntail = Some(SigEntail.Error))

  private def header(body: String) =
    "module TC where\nimport Function\nimport List\nimport Primitive\n\n" + body

  private def check(body: String): TolerantCheck.Result =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      // Session.loadModules, not the fixture's: no writeback, so nothing
      // this property loads can reach another property's session.
      S.loadModules(List("Function", "List", "Primitive"))
      val src = header(body)
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      TolerantCheck.check(r.ps, r.module)
    }

  /** As `check`, but asking for what only the editor path asks for
    * (6.2): the local binder types.  `check` itself must never grow
    * them — the batch entry's behaviour is frozen — which is what the
    * "the batch entry collects nothing" property pins. */
  private def checkLocals(body: String, imports: List[String] = Nil,
                          mode: SigEntail.Mode = SigEntail.Off)
      : (TolerantCheck.Result, Renamer.Result) =
    (if (mode == SigEntail.Off) fx else fxError).session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      val mods = List("Function", "List", "Primitive") ++ imports
      S.loadModules(mods)
      val src = "module TC where\nimport Function\nimport List\nimport Primitive\n" +
                imports.map("import " + _ + "\n").mkString + "\n" + body
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      (TolerantCheck.checkWith(r.ps, r.module, Map(), "", TolerantCheck.Cache.empty,
                               wantLocals = true)._1, r.renamed)
    }

  /** A local's type AS HOVER WOULD RENDER IT, by def-site spelling —
    * `scope` and all, so these properties pin the string the editor
    * shows and not a second rendering of my own. */
  private def render(l: TolerantCheck.LocalTy): String = l.scope match {
    case Some(sc) => Pretty.prettyTypeIn(sc, l.ty).toString
    case None     => Pretty.prettyType(l.ty, -1).toString
  }

  private def localsBySpelling(r: TolerantCheck.Result, rn: Renamer.Result): Map[String, String] =
    rn.binders.values.flatMap { b =>
      r.locals.get((b.defSite.startLine, b.defSite.startCol))
        .map(l => b.spelling -> render(l))
    }.toMap

  private def errors(r: TolerantCheck.Result) = r.notes.filter(_.severity == TolerantCheck.Error)
  private def infos(r: TolerantCheck.Result)  = r.notes.filter(_.severity == TolerantCheck.Information)

  property("a module the batch loader accepts draws no notes") = {
    val r = check("v = 1\nw : Int\nw = 2\n")
    (r.notes.isEmpty :| r.notes.map(_.report).toString) &&
      (r.types.contains("v") :| s"types: ${r.types.keySet}") &&
      (r.types.contains("w") :| s"types: ${r.types.keySet}")
  }

  property("two INDEPENDENT type errors are both reported") = {
    // The whole point of the item: loadModule would report only the first.
    val r = check("a : Int\na = \"one\"\n\nb : Int\nb = \"two\"\n")
    ((errors(r).size == 2) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (errors(r).forall(_.report contains "failed to unify") :| errors(r).map(_.report).toString)
  }

  property("an earlier component's failure leaves a later independent one alone") = {
    // With ONE shared SubstEnv the failed component's half-solved metas
    // stay bound on module-wide placeholders, and `good` gets inferred
    // against them.  A fresh SubstEnv per component is what keeps this
    // to exactly one note.
    val r = check("bad = 1 True\ngood = 2\n")
    ((errors(r).size == 1) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (r.types.contains("good") :| s"good lost its type: ${r.types.keySet}")
  }

  property("a dependent component is unchecked, transitively") = {
    val r = check("broken = 1 True\nmid = broken\ntop = mid\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((infos(r).size == 2) :| infos(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (infos(r).forall(_.report contains "unchecked: depends on a broken definition") :|
        infos(r).map(_.report).toString) &&
      // never inferred against unconstrained metas — they would typecheck to lies
      (!r.types.contains("mid") :| "mid was given a type anyway") &&
      (!r.types.contains("top") :| "top was given a type anyway")
  }

  /* ---- SIG-3: the signature-entailment check on the EDITOR's path -------------------- *
   * `TolerantCheck` calls `typeCheckExplicitBinding` itself (:727, inside `guard(Error)`),
   * so the check reaches the editor with no editor-specific code -- and must, or a file the
   * batch loader refuses would look clean in the IDE.  The diagnostic arrives as an ordinary
   * Error note, which is what `tracker/lsp-tests/sigentail.json` then pins over the wire. */

  property("SIG-3: a signed binding whose context is too weak is one Error note, in the editor") = {
    val r = checkLocals("field health : Int\n\n" +
                        "healthOpt : forall r. {..r} -> Int\n" +
                        "healthOpt r = r ! health\n", List("Field"), SigEntail.Error)._1
    val es = errors(r)
    ((es.size == 1) :| es.map(_.report.linesIterator.take(1).mkString).toString) &&
      ((es.head.report contains "the signature does not entail this row constraint") :|
        es.head.report) &&
      ((es.head.report contains "declared at") :| es.head.report) &&
      // the note carries a position in THIS file, not in the stdlib the `!` came from --
      // and the two positions are the BODY's `!` (line 10) and the DECLARED TYPE on the
      // signature line (line 9, column 13), not the equation's head twice (S3 review M1)
      ((es.head.report startsWith "TC:10:17:") :| es.head.report) &&
      ((es.head.report contains "declared at TC:9:13 (sig healthOpt)") :| es.head.report)
  }

  property("SIG-3: the honest twin draws no note on the editor's path") = {
    val r = checkLocals("field health : Int\n\n" +
                        "healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int\n" +
                        "healthWith r = r ! health\n", List("Field"), SigEntail.Error)._1
    (r.notes.isEmpty :| r.notes.map(_.report).toString) &&
      (r.types.contains("healthWith") :| s"types: ${r.types.keySet}")
  }

  property("an undefined term is one note per name, carrying its spelling") = {
    // The spelling is what the editor matches against a broken
    // statement's head word to suppress the cascade (5.4).
    val r = check("v = nosuchthing\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((errors(r).head.spelling == Some("nosuchthing")) :| errors(r).head.spelling.toString) &&
      ((errors(r).head.report contains "undefined term") :| errors(r).head.report)
  }

  property("a definition mentioning an undefined term draws no SECOND note") = {
    // The undefined term IS the explanation; "unchecked" on top of it is
    // noise.  Its dependents still say so.
    val r = check("v = nosuchthing\nw = v\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((infos(r).size == 1) :| infos(r).map(_.report.linesIterator.take(1).mkString).toString)
  }

  // ---- 6.2: types at every binder the collection can reach -----------
  //
  // THE MECHANISM, and its limit (tracker/loopmodel/LSP3-6.2-LOCALS.md).
  // Lower gives every renamer binder ONE `V[Type]` whose type is a fresh
  // meta; a zonk of that meta after inference is the binder's type.
  // Inference constrains that meta for a BINDING HEAD (`let`, `where`,
  // top level) -- `Subst.inferImplicitBindingTypes` subsumes it against
  // the inferred type.  It does NOT for a PATTERN binder: Lower drops
  // the meta when it builds the pattern (`VarP(v.map(_ => annotOf(..)))`)
  // and `Subst.inferPatternType` mints a fresh one per occurrence into a
  // local copy of the body.  So a LAMBDA arg, a `case` binder and a `do`
  // binder are absent by MECHANISM, not by accident.
  //
  // An EQUATION's arguments are recovered anyway, without asking
  // inference again (6.2 option 4, review R-2): `b.arity` patterns, and
  // the head's own type is an arrow chain whose first `arity` domains
  // ARE those arguments.  The properties below pin both sides of the
  // remaining line, and the letters of the two hovers.

  private val kindsBody =
    "argEq a b = a && b\n" +
    "\n" +
    "letLocal x =\n" +
    "  let y = x && True\n" +
    "  in y\n" +
    "\n" +
    "whereLocal x = z\n" +
    "  where z = x || False\n" +
    "\n" +
    "caseLocal p = case p of\n" +
    "  Just q -> q\n" +
    "  Nothing -> True\n" +
    "\n" +
    "lamArg = (w -> w && True)\n" +
    "\n" +
    "signedArg = (v : Bool) -> v\n" +
    "\n" +
    "asLocal l = case l of\n" +
    "  whole@(h :: t) -> h\n" +
    "  _ -> True\n" +
    "\n" +
    "polyWhere x = idy x\n" +
    "  where idy u = u\n" +
    "\n" +
    // 6.2b renamed this binder from `a`: `argEq`'s first argument is also
    // spelled `a`, and `localsBySpelling` is keyed by spelling -- harmless
    // while do binders had no type, a silent clobber once they do.
    "doLocal m ma = (do dbind <- liftDo ma\n" +
    "                   unit (dbind && True)) m\n" +
    "\n" +
    "tupLocal tp = case tp of\n" +
    "  (tl, tr) -> tl && tr\n" +
    "\n" +
    "polyLam x = pl x\n" +
    "  where pl = plz -> plz\n" +
    "\n" +
    "sigWhere x = sw x\n" +
    "  where sw : Bool -> Bool\n" +
    "        sw y = y && True\n" +
    "\n" +
    "sigLet x =\n" +
    "  let sl : Bool -> Bool\n" +
    "      sl sly = sly && True\n" +
    "  in sl x\n"

  private lazy val kinds: (TolerantCheck.Result, Renamer.Result) =
    checkLocals(kindsBody, List("Bool", "Syntax.Do"))

  property("6.2: every LET and WHERE binder gets a type") = {
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    (r.notes.isEmpty :| ("the fixture must be clean: " +
       r.notes.map(_.report.linesIterator.take(1).mkString).mkString(" ;; "))) &&
    ((got.get("y") ?= Some("Bool")) :| s"let binder: $got") &&
    ((got.get("z") ?= Some("Bool")) :| s"where binder: $got") &&
    // 6.2c: a local head hovers the SCHEME the checker published for it, so a
    // polymorphic one shows its quantifier -- the way a top-level head's hover
    // has always shown it (`Heads2.idt : forall a. a -> a` through the real
    // server).  Until 6.2c it showed the pre-generalisation rho, `a -> a`,
    // which is also what a MONOTYPE `a` prints and is the ambiguity E14 is
    // about.  See `TolerantCheck.displayScheme`.
    ((got.get("idy") ?= Some("forall a. a -> a")) :| s"polymorphic where binder: $got") &&
    // A SIGNED `let`/`where` binding is a local ExplicitBinding after the
    // block machinery (`Lower.bindings` -> `Lower.pairSigs`), and shows AS
    // DECLARED (Decision a).  `sl` is the LET twin, and it is a pin with a
    // history: until LET-1 a `let` block built `Let(..., Nil, body)`, so
    // the signature never became an ExplicitBinding, `headType` fell back
    // to the implicit binding's inferred meta, and hover on a signed `let`
    // binder quietly showed the INFERRED type -- Decision (a) violated with
    // no test to notice.  Only `sw` was asserted here.
    ((got.get("sw") ?= Some("Bool -> Bool")) :| s"signed where binder: $got") &&
    ((got.get("sl") ?= Some("Bool -> Bool")) :| s"signed let binder: $got")
  }

  property("6.2b: every remaining pattern-binder kind gets a type") = {
    // FLIPPED BY 6.2b.  Until the hook these were absent: a LAMBDA
    // argument, a `case` binder, a `do` binder and a var nested in a
    // constructor pattern lower to pattern vars whose meta inference
    // never touches, and no equation head's arity reaches them.  The
    // `Subst` hook records the type where the checker mints it, so every
    // one of them now answers -- and answers the type the checker gave
    // it, which is what the corpus-scale agreement check pins.
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    (r.notes.isEmpty :| ("the fixture must be clean: " +
       r.notes.map(_.report.linesIterator.take(1).mkString).mkString(" ;; "))) &&
    ((got.get("w")      ?= Some("Bool")) :| s"lambda argument: $got") &&
    ((got.get("q")      ?= Some("Bool")) :| s"case binder: $got") &&
    ((got.get("dbind")  ?= Some("Bool")) :| s"do binder: $got") &&
    ((got.get("whole")  ?= Some("List Bool")) :| s"as-pattern outer var: $got") &&
    ((got.get("h")      ?= Some("Bool")) :| s"var nested in a ConP: $got") &&
    ((got.get("t")      ?= Some("List Bool")) :| s"the ConP's tail var: $got") &&
    ((got.get("tl")     ?= Some("Bool")) :| s"var nested in a tuple pattern: $got") &&
    ((got.get("tr")     ?= Some("Bool")) :| s"the tuple's second var: $got") &&
    // ... and the renamer DID record them, so this is about the
    // collection and not about an empty binder table (anti-vacuity).
    ((rn.binders.values.count(b => b.kind == Renamer.Arg) >= 6) :|
      s"only ${rn.binders.values.count(b => b.kind == Renamer.Arg)} Arg binders") &&
    ((rn.binders.values.exists(_.kind == Renamer.CaseBound)) :| "no CaseBound binder") &&
    ((rn.binders.values.exists(_.kind == Renamer.DoBound)) :| "no DoBound binder")
  }

  property("6.2: an EQUATION's arguments get their types from the head") = {
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    ((got.get("a") ?= Some("Bool")) :| s"argEq's first argument: $got") &&
    ((got.get("b") ?= Some("Bool")) :| s"argEq's second argument: $got") &&
    // ... at every depth: a `where` equation's own arguments too
    ((got.get("u") ?= Some("a")) :| s"the where-helper's argument: $got")
  }

  property("6.2: one binding's argument letters agree with its own type") = {
    // Review R-4.  `g : forall a b. a -> b -> a` must give `x : a` and
    // `y : b`.  Two independent `prettyType` calls would say `a` and `a`
    // — the same letter for two different variables, which is worse than
    // no answer.  `Pretty.prettyTypeIn` warms the letter state up with
    // the binding's own type first.
    val (r, rn) = checkLocals("g x y = x\n")
    val got = localsBySpelling(r, rn)
    val head = r.types.get("g").map(t => Pretty.prettyType(t, -1).toString)
    ((head ?= Some("forall a b. a -> b -> a")) :| s"g's own type: $head") &&
    ((got.get("x") ?= Some("a")) :| s"g's first argument: $got") &&
    ((got.get("y") ?= Some("b")) :| s"g's second argument: $got")
  }

  property("6.2b: an argument the split cannot see comes from the hook") = {
    // FLIPPED BY 6.2b.  The arity split is still conservative -- a var
    // inside a constructor pattern has a type its arithmetic does not
    // know, and a lambda's argument is not an equation head's argument at
    // all -- but the checker knows both, and the hook reads them from
    // where it mints them.  `w` is the R-4 case: a lambda argument on an
    // UNCONSTRAINED binding, so its type is a variable and it must render
    // with the enclosing binding's own letter.
    val (r, rn) = checkLocals(
      "conP (Just q) = q\n" +
      "lam = (w -> w)\n", List("Bool"))
    val got = localsBySpelling(r, rn)
    val lamTy = r.types.get("lam").map(t => Pretty.prettyType(t, -1).toString)
    val conPTy = r.types.get("conP").map(t => Pretty.prettyType(t, -1).toString)
    ((conPTy ?= Some("forall a. Maybe a -> a")) :| s"conP's own type: $conPTy") &&
    ((got.get("q") ?= Some("a")) :| s"a var inside a ConP: $got") &&
    ((lamTy ?= Some("forall a. a -> a")) :| s"lam's own type: $lamTy") &&
    ((got.get("w") ?= Some("a")) :| s"a lambda argument: $got")
  }

  property("6.2b: a where-bound polymorphic local's LAMBDA argument shares its letters") = {
    // Decision (a) / review R-4 for the hook's own binders: `pl = plz ->
    // plz` under a polymorphic `where` head must print the same letter
    // the head does, not restart the supply on its own.  `LocalTy.scope`
    // carries the TOP-LEVEL binding's type into `Pretty.prettyTypeIn` --
    // the frame the hook's entries live in after `generalize` rewrote
    // them; see LSP-6.2b-HOOK.md Sec. 4 for why not the local head's.
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    // 6.2c: the head's own hover is the published scheme (`forall a. a -> a`);
    // the argument still prints the TOP-LEVEL binding's letter for it.
    ((got.get("pl")  ?= Some("forall a. a -> a")) :| s"the where head: $got") &&
    ((got.get("plz") ?= Some("a")) :| s"its lambda argument: $got")
  }

  property("6.2b: the split and the hook agree wherever both speak") = {
    // Both mechanisms type every EQUATION argument: the split by
    // arithmetic on the head's type, the hook from the checker itself.
    // Where they overlap the split wins (it is the pinned 6.2 answer and
    // it carries the letter agreement), and the two are compared rather
    // than one quietly replacing the other.
    val (r, _) = kinds
    ((r.binderDisagreements ?= Nil) :| s"disagreement(s) at ${r.binderDisagreements}") &&
    ((r.binderAgreed >= 8) :| s"only ${r.binderAgreed} binders compared (vacuous?)")
  }

  // ---- 6.2c: the local HEAD hovers what the checker published --------
  //
  // Ticket E14.  `Subst.inferImplicitBindingTypes` subsumes Lower's meta
  // against `rp`, the PRE-GENERALISATION rho, and the `generalize` two
  // statements later quantifies rp's free metas and moves the deferred
  // constraints into the scheme -- rewriting the SCHEME only.  Nothing
  // binds those metas again, so the meta's zonk is the rho for ever: one
  // frame behind the published type, with the constraints gone.  The
  // scheme is recorded at the generalisation (`SubstEnv.headTypes`,
  // behind `recordBinders`) and is what `headType` reads now.

  private val headsBody =
    "conLocal xs =\n" +
    "  let go2 [] acc2 = acc2\n" +
    "      go2 (h2::t2) acc2 = go2 t2 (h2 * acc2)\n" +
    "  in go2 xs 1\n" +
    "\n" +
    "pairLocal y2 =\n" +
    "  let gl x2 = (x2, y2)\n" +
    "  in (gl 1, y2 + 1)\n" +
    "\n" +
    "laterLocal y3 =\n" +
    "  let zl = y3\n" +
    "  in (zl, y3 && True)\n" +
    "\n" +
    "sigLocal x3 =\n" +
    "  let sg : Int -> Int\n" +
    "      sg n2 = n2 + 1\n" +
    "  in sg x3\n"

  private lazy val heads: (TolerantCheck.Result, Renamer.Result) =
    checkLocals(headsBody, List("Bool"))

  // 6.2c fix round (review R-1/R-5): ONE scheme with BOTH kinds of constraint.
  // `gx`'s published set is `PrimitiveNum a` -- over a variable the scheme
  // quantifies and the body shows -- beside `exists c. c <- (a1, b)`, the row
  // residual `appendR` leaves behind, whose variable occurs nowhere else.  Rule 1
  // must drop the second and KEEP the first; the first version of the rule erased
  // the whole `Exists` and lost both.  Fixture shape from the review's witness.
  private val mixedBody =
    "mixLocal xs rr ss = gx xs 1 rr ss\n" +
    "  where gx []         acc r s = acc\n" +
    "        gx (hx :: tx) acc r s = const (gx tx (hx * acc) r s) (appendR r s)\n"

  private lazy val mixed: (TolerantCheck.Result, Renamer.Result) =
    checkLocals(mixedBody, List("Record"))

  property("6.2c: a CONSTRAINED local head hovers its constraint, not a bare variable") = {
    // THE E14 SHAPE, and the defect it names: `go2`'s `*` is
    // `PrimitiveNum n => n -> n -> n`, so the published scheme carries a
    // constraint -- and until 6.2c the head hovered `List a -> a -> a`,
    // a type with no constraint and a variable nothing in the file
    // quantifies, sitting in the editor beside the hook's `h2 : Int`.
    val (r, rn) = heads
    val got = localsBySpelling(r, rn)
    (r.notes.isEmpty :| ("the fixture must be clean: " +
       r.notes.map(_.report.linesIterator.take(1).mkString).mkString(" ;; "))) &&
    ((got.get("go2") ?= Some("forall a. PrimitiveNum a => List a -> a -> a")) :|
      s"the constrained local head: $got") &&
    // THE SPLIT INHERITS: the argument is peeled from the head's own type
    // and printed in the head's frame, so its letter is the head's.
    ((got.get("acc2") ?= Some("a")) :| s"its argument: $got") &&
    // THE SECOND FRAME, deliberately left standing: the hook records a
    // pattern binder's meta where the checker mints it, and `unbind`
    // carries that record into the FIRST instance the body takes of the
    // scheme (`go2 xs 1`, hence `Int`).  So `h2 : Int` is this let's
    // single use, and `acc2 : a` is the binding's own type.  The two are
    // not in one frame and the 6.2b disagreement set says so at exactly
    // these def-sites; the hook's frame-dragging is written up as a
    // follow-up in LSP-6.2c-HEADS.md, not fixed here.
    ((got.get("h2") ?= Some("Int")) :| s"the hook's answer beside it: $got") &&
    ((got.get("t2") ?= Some("List Int")) :| s"the hook's answer beside it: $got")
  }

  property("6.2c: a head that mentions a variable fixed LATER still shows the settled type") = {
    // THE CONTROL that says this is not the 6.2 review's R-1 mechanism:
    // `gl`'s scheme is `forall a. a -> (a, b)` with `b` the enclosing
    // lambda's meta, and `b` is fixed at `Int` AFTER the let group was
    // generalised.  The record is kept eagerly substituted at
    // `instantiateType` for exactly this reason, so the head still
    // hovers `Int` in the second component -- as it did before 6.2c,
    // which read the rho and got the same `Int` the same way.
    val (r, rn) = heads
    val got = localsBySpelling(r, rn)
    ((got.get("gl") ?= Some("forall a. a -> (a, Int)")) :| s"the later-fixed head: $got") &&
    ((got.get("x2") ?= Some("a")) :| s"its argument: $got") &&
    // and a local whose own type is settled outright is unchanged: no
    // quantifier, no constraint, `Forall.apply` collapses to the body.
    ((got.get("zl") ?= Some("Bool")) :| s"the settled local: $got")
  }

  property("6.2c: a SIGNED local head still shows its declaration") = {
    // Decision (a) is untouched: an explicit local reads its DECLARATION
    // off the tree and never the record -- `headType`'s `ExplicitBinding`
    // case comes first.
    val (r, rn) = heads
    val got = localsBySpelling(r, rn)
    ((got.get("sg") ?= Some("Int -> Int")) :| s"the signed local head: $got") &&
    ((got.get("n2") ?= Some("Int")) :| s"its argument: $got")
  }

  property("6.2c: a row residual is elided and a class constraint is KEPT, in one scheme") = {
    // THE R-1 PIN.  Rule 1 is a FILTER over the published constraint set, one
    // constraint at a time -- not an erase of the set because one member
    // quantifies an existential.  `Subst.generalize` puts the WHOLE set in ONE
    // `Exists`, so the erase lost `Num a` wherever a row residual stood beside it
    // (246 of 930 elision events over the corpus).
    val (r, rn) = mixed
    val got = localsBySpelling(r, rn)
    (r.notes.isEmpty :| ("the fixture must be clean: " +
       r.notes.map(_.report.linesIterator.take(1).mkString).mkString(" ;; "))) &&
    // the rendering is a Document and wraps at the printer's width; the pin is on
    // the type, so whitespace is collapsed before comparing
    ((got.get("gx").map(_.split("\\s+").mkString(" ")) ?= Some(
       "forall a (a1: rho) (b: rho). PrimitiveNum a => List a -> a -> Record a1 -> Record b -> a")) :|
      s"the mixed head: $got") &&
    // the elision DID fire here (or the pin above proves nothing about rule 1)
    ((r.headElided >= 1) :| s"rule 1 never fired: elided ${r.headElided}") &&
    // and it dropped nothing the reader can act on
    ((r.headLost ?= Nil) :| s"a usable constraint was elided at ${r.headLost}")
  }

  property("6.2c: the head record and the meta are compared wherever both speak") = {
    // The heads' cross-check, the equation arguments' one level up.  On
    // this fixture the only head whose hover changes in CONTENT is the
    // constrained one; the others agree, which is what makes the pin
    // above a statement about `go2` and not about the mechanism.
    val (r, rn) = heads
    val defSite = rn.binders.values.find(_.spelling == "go2")
      .map(b => (b.defSite.startLine, b.defSite.startCol))
    ((r.headDisagreements ?= defSite.toList) :|
      s"head disagreements ${r.headDisagreements}, go2 at $defSite") &&
    // `gl` and `zl`; `sg` is an ExplicitBinding and never reads the record.
    ((r.headAgreed >= 2) :| s"only ${r.headAgreed} heads compared (vacuous?)") &&
    ((r.headRequantified >= 2) :| s"only ${r.headRequantified} heads requantified")
  }

  property("6.2: an explicit local signature shows as declared") = {
    // `(v : Bool) -> v`: Lower puts the DECLARED type in the pattern
    // var's annot, so this one needs no inference at all — Decision (a).
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    (got.get("v") ?= Some("Bool")) :| s"signed lambda parameter: $got"
  }

  property("6.2: a component that died contributes no locals") = {
    // 6.2b: `dlam` is a HOOK binder (a lambda argument) inside the dead
    // component.  The hook writes into the component's OWN SubstEnv and
    // the merge only happens when inference returned, so a Death takes
    // the half-solved record with it -- the same rule the 6.2 locals
    // already obeyed, now pinned for the new class too.
    val (r, rn) = checkLocals(
      "broken = (let bad = (dlam -> dlam) 1 True in bad)\n" +
      "healthy = (let good = 2 in good)\n")
    val got = localsBySpelling(r, rn)
    ((errors(r).size == 1) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
    ((!got.contains("bad")) :| s"a dead component's local was published: $got") &&
    ((!got.contains("dlam")) :| s"a dead component's HOOK binder was published: $got") &&
    ((got.get("good") ?= Some("Int")) :| s"the healthy component's local: $got")
  }

  property("6.2: the batch entry collects nothing new") = {
    // BATCH FROZEN: `check` is what everything but the editor calls, and
    // `wantLocals` defaults to false there.
    val r = check("letLocal x =\n  let y = x\n  in y\n")
    (r.locals.isEmpty :| s"check() collected ${r.locals.size} locals")
  }

  // ---- 5.5: per-SCC reuse --------------------------------------------
  // The cache must be invisible: whatever it hands back must equal what
  // a cold check of the same text would have said.

  private def run(body: String, cache: TolerantCheck.Cache)
      : (TolerantCheck.Result, TolerantCheck.Cache) =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      S.loadModules(List("Function", "List", "Primitive"))
      val src = header(body)
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      val (groups, scopeKey) =
        TolerantCheck.keys(src, mh.name, mh.imports.toList.sortBy(_._1).toString, "")
      // 6.2 asks the reuse question of the locals too, so the reuse
      // properties below must run the path that carries them.
      TolerantCheck.checkWith(r.ps, r.module, groups, scopeKey, cache, wantLocals = true)
    }

  private def rendered(r: TolerantCheck.Result): Map[String, String] =
    r.types.map { case (k, t) => k -> Pretty.prettyType(t, -1).toString }

  /** 6.2, Decision (b): a reused entry carries its component's locals,
    * POSITIONS INCLUDED — so warm and cold must agree on the def-site
    * keys, not merely on the types. */
  private def renderedLocals(r: TolerantCheck.Result): Map[(Int, Int), String] =
    r.locals.map { case (k, l) => k -> render(l) }

  /** Check `before`, then check `after` twice — once carrying the cache
    * `before` produced, once cold — and require the two to agree. */
  private def invisible(what: String, before: String, after: String,
                        expectReuse: Boolean = true): Prop = {
    val (_, cache) = run(before, TolerantCheck.Cache.empty)
    val (warm, _)  = run(after, cache)
    val (cold, _)  = run(after, TolerantCheck.Cache.empty)
    ((warm.notes.map(n => (n.severity, n.report)) ?= cold.notes.map(n => (n.severity, n.report)))
       :| s"$what: notes differ") &&
    ((rendered(warm) ?= rendered(cold)) :| s"$what: types differ") &&
    ((renderedLocals(warm) ?= renderedLocals(cold)) :| s"$what: locals differ") &&
    (if (expectReuse) (warm.reused > 0) :| s"$what: nothing was reused (vacuous)"
     else (warm.reused == 0) :| s"$what: reused ${warm.reused}, expected a full drop")
  }

  private val base =
    // `six` carries a LOCAL, so the invisibility set is not vacuous on
    // the 6.2 half: without a let/where binder anywhere in the module
    // "warm locals == cold locals" would compare two empty maps.
    // 6.2b: `seven` and `eight` carry a LAMBDA argument and a `case`
    // binder, the classes only the `Subst` hook can type -- so the cache
    // invariant ("whatever a hit hands back equals what a cold check
    // would have said", Decision (b)) is asserted over the hook's
    // entries too, positions included.
    "one = 1\ntwo = one\nthree : Int\nthree = two\nfour = three\n" +
    "six = (let loc = four in loc)\n" +
    "nine = (lamb -> lamb) four\n" +
    "ten = case four of\n  cb -> cb\n"

  property("reuse is invisible: an edit inside one definition") =
    invisible("body edit", base, base.replace("two = one", "two =  one"))

  property("reuse is invisible: an edit that INTRODUCES an error") =
    invisible("break", base, base.replace("one = 1", "one = 1 True"))

  property("reuse is invisible: an edit that FIXES an error") =
    invisible("fix", base.replace("one = 1", "one = 1 True"), base)

  property("reuse is invisible: a signature edit") =
    // the sig and its equations are ONE invalidation unit
    invisible("sig edit", base, base.replace("three : Int", "three : Integer"))

  property("a new top-level definition drops the whole cache") =
    // the head set is part of the scope key
    invisible("head set", base, base + "five = four\n", expectReuse = false)

  property("a new import drops the whole cache") =
    fx.session { _ =>
      val (_, c1) = run(base, TolerantCheck.Cache.empty)
      val (warm, _) = run(base, c1.copy(scopeKey = c1.scopeKey + "!"))
      (warm.reused == 0) :| s"reused ${warm.reused} across a scope-key change"
    }

  property("a clean module reuses nearly all of its components") = {
    val (_, cache) = run(base, TolerantCheck.Cache.empty)
    val (warm, _)  = run(base, cache)
    ((warm.components >= 3) :| s"only ${warm.components} components") &&
      ((warm.reused == warm.components) :|
        s"reused ${warm.reused} of ${warm.components} on an UNCHANGED module")
  }

  // ---- 7.2: the span arithmetic itself --------------------------------
  //
  // `Anchors` is the ONE place a position is moved between a cached
  // artifact's frame and the buffer's, and 7.1b reuses it for spans, so
  // its three rules are pinned here rather than only where they are
  // consumed.

  private val smallInt: Gen[Int] = Gen.choose(-5000, 5000)

  property("7.2 Anchors: rel and abs are inverses at the same anchor") =
    forAll(smallInt, smallInt) { (line: Int, a: Int) =>
      (Anchors.abs(Anchors.rel(line, a), a) ?= line) &&
      (Anchors.rel(Anchors.abs(line, a), a) ?= line)
    }

  property("7.2 Anchors: a relative line is line - anchor, sign and all") =
    forAll(smallInt, smallInt) { (line: Int, a: Int) =>
      (Anchors.rel(line, a) ?= (line - a)) &&
      (Anchors.tag(line, a) ?= (line - a).toString)
    }

  property("7.2 Anchors: a column is never moved") =
    forAll(smallInt, smallInt, smallInt) { (line: Int, col: Int, a: Int) =>
      (Anchors.relPos((line, col), a)._2 ?= col) &&
      (Anchors.absPos((line, col), a)._2 ?= col) &&
      (Anchors.relSpan(Span(line, col, line + 2, col + 3), a).startCol ?= col) &&
      (Anchors.absSpan(Span(line, col, line + 2, col + 3), a).endCol ?= (col + 3))
    }

  property("7.2 Anchors: a span moves both ends by the same delta") =
    forAll(smallInt, smallInt, smallInt) { (l: Int, n: Int, a: Int) =>
      val sp = Span(l, 1, l + math.abs(n % 40), 7)
      (Anchors.absSpan(Anchors.relSpan(sp, a), a) ?= sp) &&
      ((Anchors.relSpan(sp, a).endLine - Anchors.relSpan(sp, a).startLine) ?=
         (sp.endLine - sp.startLine))
    }

  property("7.2 Anchors: a keyed map round-trips, keys and values") =
    forAll(Gen.listOf(Gen.zip(smallInt, smallInt)), smallInt) {
      (ks: List[(Int, Int)], a: Int) =>
        val m = ks.map(k => k -> k.toString).toMap
        (Anchors.absKeys(Anchors.relKeys(m, a), a) ?= m) &&
        (Anchors.relKeys(m, a).values.toList.sorted ?= m.values.toList.sorted)
    }

  // ---- 7.2: ANCHORED POSITIONS ---------------------------------------
  //
  // The key no longer carries an absolute line, so an edit that only
  // SHIFTS lines must keep every entry AND hand its def-sites back at
  // the lines the buffer now has.  These re-attack the drift invariant
  // in its anchored form: the five attacks of the 6.2 review (R-7) plus
  // the line-shifting ones this item exists for.

  /** `base` plus two definitions whose bodies are BYTE-IDENTICAL apart
    * from the head name -- the case a text-only key is weakest on -- and
    * one whose local sits on the head line. */
  private val anchorBase =
    base + "seven = (let dz = four in dz)\n" + "eight = (let dz = four in dz)\n"

  /** Every def-site of a `let` binder spelled `name`, as (line, column),
    * computed from the TEXT rather than from the check -- so a property
    * that compares them against `locals` is not comparing the
    * implementation with itself. */
  private def letSites(body: String, name: String): Set[(Int, Int)] =
    header(body).split("\n", -1).zipWithIndex.flatMap { case (l, i) =>
      val j = l.indexOf("let " + name + " ")
      if (j < 0) None else Some((i + 1, j + 5))
    }.toSet

  /** The reuse count of a re-run over UNCHANGED text: the number a
    * pure line shift has to match. */
  private lazy val fullReuse: Int = {
    val (_, c) = run(anchorBase, TolerantCheck.Cache.empty)
    run(anchorBase, c)._1.reused
  }

  /** As `invisible`, but also pinning the reuse count and the ACTUAL
    * def-site positions of every `let` binder in the edited text. */
  private def anchored(what: String, before: String, after: String,
                       reuse: Int => Prop): Prop = {
    val (_, cache) = run(before, TolerantCheck.Cache.empty)
    val (warm, _)  = run(after, cache)
    val (cold, _)  = run(after, TolerantCheck.Cache.empty)
    val want = letSites(after, "loc") ++ letSites(after, "dz")
    ((warm.notes.map(n => (n.severity, n.report)) ?= cold.notes.map(n => (n.severity, n.report)))
       :| s"$what: notes differ") &&
    ((rendered(warm) ?= rendered(cold)) :| s"$what: types differ") &&
    ((renderedLocals(warm) ?= renderedLocals(cold)) :| s"$what: locals differ") &&
    ((want.forall(warm.locals.contains)) :|
       s"$what: def-sites ${want.filterNot(warm.locals.contains)} missing from ${warm.locals.keySet}") &&
    reuse(warm.reused)
  }

  private def sameAsUnshifted(what: String)(n: Int): Prop =
    (n ?= fullReuse) :| s"$what: reused $n where an unchanged re-run reuses $fullReuse"

  property("7.2: a line inserted at the TOP keeps every entry, re-anchored") =
    anchored("top insert", anchorBase, "\n" + anchorBase, sameAsUnshifted("top insert"))

  property("7.2: a line DELETED at the top keeps every entry, re-anchored") =
    anchored("top delete", "\n" + anchorBase, anchorBase, sameAsUnshifted("top delete"))

  property("7.2: ten lines inserted at the top keep every entry") =
    anchored("top insert x10", anchorBase, ("\n" * 10) + anchorBase,
             sameAsUnshifted("top insert x10"))

  property("7.2: a line inserted BETWEEN two definitions keeps every entry") =
    anchored("between", anchorBase,
             anchorBase.replace("four = three", "\nfour = three"),
             sameAsUnshifted("between"))

  property("7.2: a comment line inserted between two definitions keeps every entry") =
    // 6.2 review attack C, anchored: it used to keep the groups ABOVE
    // the comment and re-check every group below it.
    anchored("comment between", anchorBase,
             anchorBase.replace("four = three", "-- a comment\nfour = three"),
             sameAsUnshifted("comment between"))

  property("7.2: a group MOVED past another still hits, at its new lines") =
    // The key is text-only, so re-ordering two independent definitions
    // must reuse both -- and each one's local must land where it now is.
    anchored("reorder", anchorBase,
             base + "eight = (let dz = four in dz)\n" + "seven = (let dz = four in dz)\n",
             sameAsUnshifted("reorder"))

  property("7.2: two definitions with IDENTICAL bodies keep their own positions") = {
    // `seven` and `eight` differ only in the head name.  Their keys hold
    // that name, so they cannot collide; if they did, one component's
    // `dz` would come back at the other's line.  Shifted, to make the
    // re-anchoring do work.
    val after = "\n" + anchorBase
    val (_, cache) = run(anchorBase, TolerantCheck.Cache.empty)
    val (warm, _)  = run(after, cache)
    val want = letSites(after, "dz")
    ((want.size ?= 2) :| "the fixture no longer has two identical bodies") &&
    ((want.forall(warm.locals.contains)) :|
       s"identical bodies: want $want, have ${warm.locals.keySet}")
  }

  // ---- 7.2 FIX ROUND: the three properties the review asked for -------
  //
  // R-1.  A top-level bind item whose own SPELLING cannot look its group
  // up reaches NO cache key: `groups` is keyed by the extent scanner's
  // head word and both readers look up by the binding's full spelling.
  // Two halves, one property each.  Before the fix round BOTH FAIL: the
  // dependent hits its cached entry, keeps the old type, and its
  // diagnostic is never found — and 7.2 is what made the edit invisible,
  // because the absolute start line that used to be in every group's text
  // masked it.

  /** Half one: an OPERATOR definition.  `StatementExtents.wordAt` reads
    * letters, digits, `#` and `.`, so `(<+>) x y = ...` scans with an
    * EMPTY head word and is filtered out of `groups` altogether. */
  private val opBase =
    base + "infixl 6 <+>\n(<+>) x y = x\nuseOp = three <+> three\n"

  /** Half two: a head word TRUNCATED by `_`.  `foo_a` scans as `foo`, so
    * `groups` is keyed by `foo` and `groups.get("foo_a")` misses.  `'` is
    * the same case (`Layout/Report.e` has eleven of those and two
    * operators, review R-3). */
  private val hwordBase =
    base + "foo_a = one\nusea = foo_a\n"

  property("7.2 R-1: splitting an OPERATOR's body over two lines is not invisible") =
    // The edit changes the operator's result type AND its line count, so
    // `useOp`'s published type must change.  The fix puts the operator's
    // text in the SCOPE key, so the whole per-uri cache drops -- the same
    // conservative answer 5.5 already gives for a `private` block.
    invisible("operator body split", opBase,
              opBase.replace("(<+>) x y = x\n", "(<+>) x y =\n  True\n"),
              expectReuse = false)

  property("7.2 R-1: splitting a TRUNCATED-HEAD definition's body is not invisible") =
    invisible("truncated head body split", hwordBase,
              hwordBase.replace("foo_a = one\n", "foo_a =\n  True\n"),
              expectReuse = false)

  // R-2.  The component TAGS -- each group's offset from the component's
  // own anchor -- are the only thing that stops a line inserted BETWEEN
  // two mutually recursive groups from being invisible to a key that then
  // re-anchors both of them by ONE number.  The reviewer replaced them
  // with a constant and 44 of 44 properties and 480 of 480 smoke checks
  // stayed green while hover on the second group's local broke.  This is
  // the property that fails instead.

  private val mutrecBase =
    base + "pingx n = (let pa = n in qongx pa)\n" +
           "qongx m = (let qa = m in pingx qa)\n"

  private lazy val fullReuseMutrec: Int = {
    val (_, c) = run(mutrecBase, TolerantCheck.Cache.empty)
    run(mutrecBase, c)._1.reused
  }

  property("7.2 R-2: a line inserted BETWEEN two mutually recursive groups MISSES") = {
    // One component, two groups, a `let` local in each.  The component's
    // anchor is `pingx`'s line; inserting a line above `qongx` moves the
    // second group and not the first, so ONE delta cannot re-anchor both
    // and the entry must not be reused.
    val after = mutrecBase.replace("qongx m =", "\nqongx m =")
    val (_, cache) = run(mutrecBase, TolerantCheck.Cache.empty)
    val (warm, _)  = run(after, cache)
    val (cold, _)  = run(after, TolerantCheck.Cache.empty)
    val want = letSites(after, "pa") ++ letSites(after, "qa")
    ((want.size ?= 2) :| "the fixture no longer has two locals to find") &&
    ((warm.reused < fullReuseMutrec) :|
       s"the mutually recursive component was REUSED across a line inserted between its two groups: reused ${warm.reused} of a possible $fullReuseMutrec") &&
    ((want.forall(warm.locals.contains)) :|
       s"mutrec: def-sites ${want.filterNot(warm.locals.contains)} missing from ${warm.locals.keySet}") &&
    ((warm.notes.map(n => (n.severity, n.report)) ?= cold.notes.map(n => (n.severity, n.report)))
       :| "mutrec: notes differ") &&
    ((rendered(warm) ?= rendered(cold)) :| "mutrec: types differ") &&
    ((renderedLocals(warm) ?= renderedLocals(cold)) :| "mutrec: locals differ")
  }

  property("7.2: a line inserted INSIDE a definition invalidates THAT definition only") =
    anchored("inside", anchorBase,
             anchorBase.replace("six = (let loc = four in loc)",
                                "six = (let loc = four\n          in loc)"),
             n => ((n < fullReuse) :| s"inside: reused $n, expected fewer than $fullReuse") &&
                  ((n > 0) :| "inside: the whole cache went"))

  property("7.2: trailing whitespace after a statement still reuses") =
    // 6.2 review attack A, anchored.
    anchored("trailing space", anchorBase,
             anchorBase.replace("four = three\n", "four = three   \n"),
             n => (n > 0) :| s"trailing space: reused $n")

  property("7.2: a space before a head-line let binder moves the local, warm == cold") =
    // 6.2 review attack E, anchored: the COLUMN moves, the text changes,
    // the entry misses -- which is what keeps the column honest, since
    // nothing here ever shifts a column.
    anchored("space before binder", anchorBase,
             anchorBase.replace("six = (let loc", "six = ( let loc"),
             n => (n >= 0) :| "vacuous")

  property("7.2: a shift AND a new error together stay byte-identical") =
    // The escape route a shifted cache could still take: a FRESH
    // component's diagnostic quoting a REUSED upstream's type.  Notes
    // are compared byte for byte.
    anchored("shift + break", anchorBase,
             ("\n" + anchorBase).replace("two = one", "two = one True"),
             n => (n > 0) :| s"shift + break: reused $n")

  property("a broken statement does not stop the healthy ones being checked") = {
    // The read drops `helper` as unparseable; `lonely` is still checked.
    val r = check("helper = = 3\nlonely : Int\nlonely = \"no\"\n")
    (errors(r).exists(_.report contains "failed to unify") :| errors(r).map(_.report).toString)
  }

  // ---- 6.1: the editor path's POSITIONS ------------------------------
  //
  // These drive `Diagnostics.check` -- the very call `Diagnostics.run`
  // makes -- against a real `Resident`, so what they inspect is what the
  // server publishes, not a re-implementation of it.  They are in this
  // suite because they are editor-check properties; they are JVM-local
  // (no socket, no client) so a failure names the file and the message.

  /** ONE resident session for both sweeps: booting is ~13 s and warming
    * it with the stdlib is more, and `Resident.supply` is a single
    * `Supply` (documented single-threaded), so the properties below hold
    * this lock rather than running concurrently on it -- ScalaCheck runs
    * a Properties object's properties on a pool. */
  private val residentLock = new Object

  private val stdlibRoot = new File("core/src/main/resources/modules")

  private def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  /** The 180-file rule: stdlib AND core/examples, minus the directories
    * whose contents are not good code (TestTolerantRead's `notGoodCode`,
    * same reasons: `shouldfail` must be rejected and `incomplete` does
    * not terminate). */
  private val notGoodCode = Set("shouldfail", "shouldfail-controls", "incomplete")

  private def corpusFiles: List[File] =
    (walk(stdlibRoot) ++ walk(new File("core/examples")))
      .filterNot(f => Option(f.getParentFile).exists(d => notGoodCode(d.getName)))

  /** The LSP fixtures, which are broken ON PURPOSE: the ones that make
    * the 0:0 property non-vacuous. */
  private def fixtureFiles: List[File] = walk(new File("tracker/lsp-tests"))

  private def stdlibModules: List[String] = {
    val root = stdlibRoot.getPath + File.separator
    walk(stdlibRoot).map(_.getPath.stripPrefix(root).stripSuffix(".e")
                          .replace(File.separator, ".")).sorted
  }

  private lazy val resident: Resident = {
    val r = new Resident(_ => ())
    val ready = r.boot()
    // Warm the resident env with the WHOLE stdlib.  Without it every
    // corpus file whose imports are outside the booted Prelude/Layout
    // closure re-loads them into its own throwaway copy, once per file.
    implicit val s: SessionEnv = ready.env
    implicit val su: Supply = r.supply
    implicit val con: Printer = r.printer
    try S.loadModules(stdlibModules)
    catch { case Death(_, _) =>
      stdlibModules.foreach { m => try S.loadModules(List(m)) catch { case Death(_, _) => () } } }
    r
  }

  private def diagnose(f: File, docs: Documents): List[Json] =
    Diagnostics.check(resident, docs, f.toURI.toString, f.toPath, _ => ())

  private def at(d: Json, which: String, field: String): Int =
    (d / "range" flatMap (_ / which) flatMap (_ / field) flatMap (_.int)) getOrElse -1
  private def message(d: Json): String =
    (d / "message" flatMap (_.str)) getOrElse ""
  private def severity(d: Json): Int =
    (d / "severity" flatMap (_.int)) getOrElse -1
  private def at00(d: Json): Boolean =
    at(d, "start", "line") == 0 && at(d, "start", "character") == 0 &&
    at(d, "end", "line") == 0 && at(d, "end", "character") == 0
  private def where(d: Json): String =
    "%d:%d-%d:%d".format(at(d, "start", "line"), at(d, "start", "character"),
                         at(d, "end", "line"), at(d, "end", "character"))

  property("no editor-path diagnostic lands at 0:0") = secure {
    // 6.1(c).  0:0 is line 1, column 1 -- a position the editor CAN
    // show, and therefore a position that hides a real one when it is
    // reached by giving up rather than by pointing.  No corpus file and
    // no fixture is designed to fail there, so the expected count is 0.
    residentLock.synchronized {
      val docs = new Documents
      val files = corpusFiles ++ fixtureFiles
      var seen = 0
      val bad = files.flatMap { f =>
        val ds = diagnose(f, docs)
        seen += ds.size
        ds.filter(at00).map(d =>
          f.getName + " " + where(d) + ": " + message(d).linesIterator.take(1).mkString)
      }
      ((corpusFiles.size >= 180) :| s"only ${corpusFiles.size} corpus files") &&
      ((fixtureFiles.size >= 30) :| s"only ${fixtureFiles.size} fixtures") &&
      // ANTI-VACUITY: the corpus is silent by construction (that is
      // TestTolerantRead's sweep), so all the positions this property can
      // actually inspect come from the fixtures.  If a change made the
      // editor path publish nothing at all, "no diagnostic at 0:0" would
      // pass for the worst possible reason.
      ((seen >= 40) :| s"only $seen diagnostic(s) inspected over ${files.size} files") &&
      ((bad.isEmpty) :| s"${bad.size} diagnostic(s) at 0:0: ${bad.take(6).mkString(" ;; ")}")
    }
  }

  /** The EQUATION-ARGUMENT class the split must cover completely: every
    * argument pattern of a top-level or `where` equation that is a bare
    * variable (parens and a signature do not change that; an `as`
    * pattern's OUTER var is one too).  A `let` inside an expression is
    * not walked here — the statement tree does not reach into terms — so
    * its arguments count as residual rather than as required. */
  private def eqArgSpans(ss: List[SStatement]): List[(String, Span)] = {
    def bare(p: SPat): List[(String, Span)] = p match {
      case SPVar(n)       => List(n.spelling -> n.span)
      case SPAs(_, n, _)  => List(n.spelling -> n.span)
      case SPParen(_, i)  => bare(i)
      case SPSig(_, i, _) => bare(i)
      case _              => Nil
    }
    ss.flatMap {
      case SEquation(_, _, as, _, wh) =>
        as.flatMap(bare) ++ wh.toList.flatMap(w => eqArgSpans(w.statements))
      case SPrivateBlock(_, ss2)     => eqArgSpans(ss2)
      case SDatabaseBlock(_, _, ss2) => eqArgSpans(ss2)
      case x: SClassStatement        => eqArgSpans(x.body)
      case _                         => Nil
    }
  }

  property("6.2b: the 253-file sweep — EVERY value-local binder has a type") = secure {
    // THE SWEEP.  6.2 required two classes to be complete and merely
    // COUNTED the rest; 6.2b requires ALL FIVE renamer value-local kinds
    // — Arg (equation and other), LetBound, WhereBound, DoBound,
    // CaseBound — to be complete over every clean corpus module, because
    // the hook records where the checker mints the type and there is no
    // longer a class it cannot reach.  A residual, if one ever appears,
    // is a named miss in the failure message, not a printed count.
    //
    // It also asserts the two mechanisms AGREE at corpus scale: every
    // equation argument is typed twice over, once by 6.2's arity split
    // and once by the hook, and a single disagreement fails the sweep.
    residentLock.synchronized {
      val docs = new Documents
      val files = corpusFiles
      var checked = 0
      var agreed = 0
      val disagreed = scala.collection.mutable.ListBuffer.empty[String]
      // 6.2b (review R-4): the fourteen def-sites where the split and the
      // hook differ, pinned as a SET.  A count would silently absorb a new
      // disagreement replacing an old one (the review caught exactly that:
      // the report named Interp.e:81:14, the tree produces Column.e:170:15).
      val knownDisagreements = Set(
        "Color.e:72:13", "Unsafe.e:152:19", "Unsafe.e:168:10",
        "Column.e:160:14", "Column.e:170:15", "StyleGrid.e:17:18",
        "Report.e:926:12", "Report.e:1593:23", "Op.e:181:15", "Op.e:181:17",
        "Validation.e:26:14", "ForeignJdk.e:328:17",
        "LetAndPatternMatching.e:8:17", "LetAndPatternMatching.e:9:17")
      // 6.2b: the def-sites the hook dropped as RANK-N.  They are the
      // item's whole residual class, and the sweep requires the misses to
      // be exactly them -- so a binder that goes untyped for any OTHER
      // reason fails, and the residual cannot quietly grow a second cause.
      // 6.2c: the head cross-check's own set -- the local heads whose hover
      // changes in CONTENT because the checker published a constraint the
      // pre-generalisation rho could not show.  Pinned as a SET for the same
      // reason (R-4).  A head that merely gained its `forall` is counted in
      // `headRequantified`, not here; a head whose constraint quantified its
      // own existentials had it ELIDED (`TolerantCheck.displayScheme`) and so
      // agrees.
      //
      // FIX ROUND (review R-6): the comparison is against the PUBLISHED scheme, not
      // the displayed one, so this set is now every local head the checker holds a
      // CONSTRAINT for -- whether or not rule 1 shows it.  It grew 8 -> 65; nothing
      // left it.  The 57 additions are the heads whose whole published set is
      // ambiguous row residual, elided from the hover by rule 1 and counted here
      // because the pre-6.2c rho could not carry it either.  The set the USER sees
      // is `knownHeadShown` below.
      val knownHeadDisagreements = Set(
        "Accumulate.e:34:14", "ClinicalTrial.e:90:9", "Comprehensions.e:206:11",
        "Comprehensions.e:207:17", "ForeignJdk.e:328:9", "Helpers.e:320:9", "Helpers.e:321:9",
        "Helpers.e:322:9", "LetAndPatternMatching.e:8:7", "Op.e:178:9", "Op.e:181:9",
        "Relation.e:222:7", "Relation.e:223:7", "Relation.e:254:7", "Relation.e:39:7",
        "Relation.e:40:20", "Relation.e:41:20", "Relation.e:42:20", "Relation.e:43:20",
        "Relation.e:44:20", "Relation.e:45:20", "Relation.e:47:7", "Report.e:1033:5",
        "Report.e:1034:5", "Report.e:1038:5", "Report.e:1039:5", "Report.e:1111:11",
        "Report.e:1337:7", "Report.e:1339:7", "Report.e:1366:7", "Report.e:1369:7",
        "Report.e:1392:7", "Report.e:1394:7", "Report.e:1604:9", "Report.e:643:9",
        "Report.e:690:7", "Report.e:772:2", "Report.e:774:8", "Report.e:775:8",
        "Report.e:783:2", "Report.e:785:8", "Report.e:786:8", "Report.e:787:8",
        "RunningState.e:240:7", "SalesDashboard.e:364:7", "Scan.e:150:9", "Scan.e:70:9",
        "Signatures.e:260:9", "Signatures.e:261:9", "Signatures.e:262:9",
        "SoftRelation.e:41:7", "SoftRelation.e:42:7", "SoftRelation.e:44:7",
        "TextTables.e:246:28", "Tree.e:83:9", "Tree.e:84:15", "Tree.e:91:9",
        "VarianceStyling.e:322:7", "WildChain.e:144:17", "WildChain.e:145:17",
        "WildChain.e:146:17", "WildChain.e:147:17", "WildChain.e:148:17", "WildChain.e:149:17",
        "WriterOutputs.e:204:7")
      // FIX ROUND: the heads whose hover SHOWS a constraint -- the user-visible
      // claim, and the table in LSP-6.2c-HEADS.md Sec. 5.  Every one read at source
      // and hovered through the real server:
      //   LetAndPatternMatching.e:8:7  go        + Num a                  <- ticket E14
      //   Report.e:643:9               capture   + AsPresentation a
      //   Report.e:1111:11             ope       + Primitive a
      //   Report.e:1604:9              npair     + AsPresentation pr
      //   Layout/Scan.e:70:9           go        + Primitive c
      //   Relation/Scan.e:150:9        extractF  + Relational f
      //   Relation/Op.e:178:9          showE     + PrimitiveString s
      //   Relation/Op.e:181:9          comma     + (AsOp opl1, AsOp opl)   <- R-1 recovered
      //   Accumulate.e:34:14           f         + RelationalComb a        <- R-1 recovered
      //   SoftRelation.e:41:7          pickk     + RelationalComb a        <- R-1 recovered
      //   Comprehensions.e:206:11      step      + a <- (b, (|balanceEur|))  <- R-1 recovered
      //   Layout/Report/Relation.e:39:7 f        + a <- (r2, (|cutoff|))     <- R-1 recovered
      // `Report.e:690:7` (`defaultLg`) LEFT this set in the fix round: its
      // `a1 <- (i, k, v1)` names variables the displayed type shows nowhere, and two
      // checks of that file do not agree about it (7.2's "publish different row
      // constraints on two COLD checks") -- rule 1's visibility predicate drops it.
      val knownHeadShown = Set(
        "LetAndPatternMatching.e:8:7", "Report.e:643:9", "Report.e:1111:11",
        "Report.e:1604:9", "Scan.e:70:9", "Scan.e:150:9", "Op.e:178:9", "Op.e:181:9",
        "Accumulate.e:34:14", "SoftRelation.e:41:7", "Comprehensions.e:206:11",
        "Relation.e:39:7")
      var headAgreed = 0
      var headRequantified = 0
      var headElided = 0
      val headDisagreed = scala.collection.mutable.ListBuffer.empty[String]
      // 6.2c fix round (review R-5): the pin on rule 1 -- a published constraint
      // the reader can act on must survive the elision.  Asserted EMPTY.
      val headLost = scala.collection.mutable.ListBuffer.empty[String]
      val headShown = scala.collection.mutable.ListBuffer.empty[String]
      val rankN = scala.collection.mutable.Set.empty[String]
      val misses = scala.collection.mutable.ListBuffer.empty[String]
      val seen = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
      val hit  = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
      files.foreach { f =>
        val c =
          try Some(resident.checkFile(f.toPath, docs))
          catch { case Death(_, _) => None }
        c foreach { ch =>
          // Only a module the editor path checked CLEANLY can be
          // expected to have typed every binder: a component that failed
          // or went unchecked legitimately contributes none.
          if (!ch.notes.exists(_.severity == TolerantCheck.Error)) {
            checked += 1
            agreed += ch.binderAgreed
            ch.binderDisagreements foreach { k =>
              disagreed += "%s:%d:%d".format(f.getName, k._1, k._2) }
            ch.binderRankN foreach { k =>
              rankN += "%s:%d:%d".format(f.getName, k._1, k._2) }
            headAgreed += ch.headAgreed
            headRequantified += ch.headRequantified
            headElided += ch.headElided
            ch.headDisagreements foreach { k =>
              headDisagreed += "%s:%d:%d".format(f.getName, k._1, k._2) }
            ch.headLost foreach { k =>
              headLost += "%s:%d:%d".format(f.getName, k._1, k._2) }
            ch.headShown foreach { k =>
              headShown += "%s:%d:%d".format(f.getName, k._1, k._2) }
            val required = eqArgSpans(ch.module.statements)
              .map { case (sp, s) => (s.startLine, s.startCol) }.toSet
            ch.renamed.binders.values.foreach { b =>
              val local = b.kind match {
                case Renamer.Arg | Renamer.LetBound | Renamer.WhereBound |
                     Renamer.DoBound | Renamer.CaseBound => true
                case _ => false
              }
              if (local) {
                val at = (b.defSite.startLine, b.defSite.startCol)
                val k  = if (b.kind == Renamer.Arg && required(at)) "Arg(equation)"
                         else if (b.kind == Renamer.Arg) "Arg(other)"
                         else b.kind.toString
                seen(k) = seen(k) + 1
                if (ch.locals.contains(at)) hit(k) = hit(k) + 1
                else
                  // 6.2b: EVERY value-local kind is required now.
                  misses += "%s:%d:%d %s (%s)".format(
                    f.getName, b.defSite.startLine, b.defSite.startCol, b.spelling, k)
              }
            }
          }
        }
      }
      val summary = seen.keys.toList.sorted
        .map(k => "%s %d/%d".format(k, hit(k), seen(k))).mkString(", ")
      println("### 6.2b sweep: " + checked + " clean modules of " + files.size +
              " — " + summary + "; misses " + misses.size +
              "; split-vs-hook agreed " + agreed + " disagreed " + disagreed.size)
      if (misses.nonEmpty) println("### 6.2b misses: " + misses.mkString(" ;; "))
      if (disagreed.nonEmpty) println("### 6.2b disagreements: " + disagreed.mkString(" ;; "))
      println("### 6.2c heads: agreed " + headAgreed + ", disagreed " + headDisagreed.size +
              ", requantified " + headRequantified + ", constraint elided " + headElided +
              ", usable constraint lost " + headLost.size +
              ", hover SHOWS a constraint " + headShown.size)
      if (headDisagreed.nonEmpty)
        println("### 6.2c head disagreements: " + headDisagreed.sorted.mkString(" ;; "))
      if (headShown.nonEmpty)
        println("### 6.2c heads showing a constraint: " + headShown.sorted.mkString(" ;; "))
      val unexplained = misses.filterNot(m => rankN(m.split(" ").head))
      ((files.size >= 180) :| s"only ${files.size} corpus files") &&
      ((checked >= 150) :| s"only $checked modules checked cleanly") &&
      // anti-vacuity: the sweep must actually be looking at binders
      ((seen("LetBound") + seen("WhereBound") >= 200) :|
        s"only ${seen("LetBound") + seen("WhereBound")} binding-head locals seen: $summary") &&
      // and at the equation-argument class too, or an empty `eqArgSpans`
      // would pass at 0 misses covering nothing (6.2 review S-3)
      ((seen("Arg(equation)") >= 2000) :|
        s"only ${seen("Arg(equation)")} equation-argument binders seen: $summary") &&
      // 6.2b anti-vacuity for the classes the hook exists for: they must
      // be SEEN in numbers, or "0 misses" would mean "nothing looked at".
      ((seen("Arg(other)") >= 1500) :|
        s"only ${seen("Arg(other)")} non-equation Arg binders seen: $summary") &&
      ((seen("CaseBound") >= 100) :| s"only ${seen("CaseBound")} case binders seen: $summary") &&
      ((seen("DoBound") >= 25) :| s"only ${seen("DoBound")} do binders seen: $summary") &&
      // 6.2b: the split and the hook are compared everywhere both speak.
      // The residual is a pinned SET, not zero, and the classes behind it are
      // named in LSP-6.2b-HOOK.md: an alias the split leaves unexpanded, a
      // DECLARED type against the skolemised instance inference checked the
      // pattern at, and a published scheme whose domain is more general than
      // the type the checker settled on.  The split still wins (Decision (a)
      // wants the declaration, and it renders better), so this is a drift
      // alarm: if the set moves, look at the new site AND the vanished one.
      ((disagreed.toSet == knownDisagreements) :|
        s"split-vs-hook disagreement set moved: new ${(disagreed.toSet -- knownDisagreements).mkString(" ;; ")}; gone ${(knownDisagreements -- disagreed.toSet).mkString(" ;; ")}") &&
      ((agreed >= 2000) :| s"only $agreed binders compared (vacuous?)") &&
      // 6.2c: the SAME cross-check for binding heads.  The published scheme is
      // what hover shows; the meta is what it showed until 6.2c; a pair differs
      // only where the scheme carries a constraint (or a body) the rho could
      // not show, and those def-sites are pinned as a set.
      ((headDisagreed.toSet == knownHeadDisagreements) :|
        s"head disagreement set moved: new ${(headDisagreed.toSet -- knownHeadDisagreements).mkString(" ;; ")}; gone ${(knownHeadDisagreements -- headDisagreed.toSet).mkString(" ;; ")}") &&
      ((headShown.toSet == knownHeadShown) :|
        s"head SHOWN set moved: new ${(headShown.toSet -- knownHeadShown).mkString(" ;; ")}; gone ${(knownHeadShown -- headShown.toSet).mkString(" ;; ")}") &&
      ((headAgreed >= 150) :| s"only $headAgreed local heads compared (vacuous?)") &&
      // 6.2c fix round (review R-5): rule 1 drops ambiguous row residuals and
      // NOTHING ELSE.  Checked against the PUBLISHED set, not recomputed from the
      // filter, so it can fail -- and before the R-1 fix it did, at 246 events.
      ((headLost.isEmpty) :|
        s"${headLost.size} head(s) lost a usable constraint to rule 1: ${headLost.take(8).mkString(" ;; ")}") &&
      ((headElided >= 20) :| s"rule 1 fired only ${headElided} times (vacuous?)") &&
      // 6.2b: the residual is ONE named class -- a variable bound to a
      // RANK-N constructor field, which Decision (a) does not let a local
      // hover as -- and every miss must be one of them.
      ((rankN.nonEmpty) :| "no RANK-N binder seen (vacuous residual)") &&
      ((unexplained.isEmpty) :|
        "%d value-local binder(s) with no type and no rank-N reason: %s".format(
          unexplained.size, unexplained.take(10).mkString(" ;; ")))
    }
  }

  /** Alpha-equivalence for the sweeps: `AlphaEq.same` (7.2 moved the
    * comparator out of the 6.6 sweep's body into `AlphaEq.scala`, so
    * both sweeps use one). */
  private def sameType(a: com.clarifi.reporting.ermine.Type,
                       b: com.clarifi.reporting.ermine.Type): Boolean = AlphaEq.same(a, b)

  /** 7.2: THE CORPUS-SCALE INVISIBILITY SWEEP.  The unit properties
    * above attack the anchoring on a fixture of six definitions; this
    * runs the same question over the whole 253-file corpus, through
    * `Resident.checkFile` -- the very call the server makes.
    *
    * For each module, FOUR checks:
    *   c0    the file as it is, cold, which fills the per-uri cache;
    *   ctl   the SAME text again, warm -- the CONTROL: whatever reuse
    *         alone changes, with no edit and no shift at all;
    *   warm  ONE BLANK LINE INSERTED AT THE TOP, against ctl's cache;
    *   cold  the same shifted text, cold, in a fresh `Documents`.
    *
    * What must hold, and what the control is for:
    *
    *   (a) NOTES are byte-identical warm vs cold.  This is what would
    *       catch a `Loc` from a reused entry reaching a diagnostic of a
    *       component re-checked around it.
    *   (b) `locals` DEF-SITES are exactly equal warm vs cold, AND
    *       exactly the first check's def-sites moved down one line with
    *       their columns untouched.  That is the re-anchoring itself,
    *       pinned against a number no cache produced.
    *   (c) the shifted check REUSES.  Before 7.2 every one of these
    *       reused nothing whatsoever.
    *   (d) RENDERED TYPES (and the rendered types of locals) may differ
    *       warm vs cold ONLY on a module where the CONTROL already
    *       differs -- i.e. where reuse alone, with no edit, renders a
    *       type differently.  That divergence predates 7.2 and is the
    *       one 6.6's sweep documents: a reused scheme was generalized
    *       with different `V` ids, and the printer's binder/constraint
    *       ORDER follows id-keyed sets (6.6 found 145 of 223 such
    *       "failures", all order).  This item must ADD none, and the
    *       property fails if it does.
    */
  property("7.2: the corpus sweep \u2014 a shifted buffer reuses, invisibly") = secure {
    residentLock.synchronized {
      // ABSOLUTE, or `Documents.byPath` misses and every check silently
      // reads the file from DISK -- no buffer, no cache, no shift.  The
      // `contents` assertion below is the standing guard against that.
      val files = corpusFiles.map(_.getAbsoluteFile)
      var clean = 0
      var withComps = 0
      var reusedFiles = 0
      var reusedComps = 0
      var totalComps = 0
      var ctlDiff = 0
      var coldDiff = 0
      var warmDiff = 0
      var localsColdDiff = 0
      val bad = scala.collection.mutable.ListBuffer.empty[String]

      def one(f: java.io.File, text: String, docs: Documents, v: Long)
          : Option[resident.Checked] = {
        docs.put(f.toURI.toString, text, v)
        try Some(resident.checkFile(f.toPath, docs))
        catch { case Death(_, _) => None }
      }
      def rend(c: resident.Checked): Map[String, String] =
        c.types.map { case (k, t) => k -> Pretty.prettyType(t, -1).toString }
      def locs(c: resident.Checked): Map[(Int, Int), String] =
        c.locals.map { case (k, l) => k -> render(l) }
      // ALPHA-EQUIVALENCE, not the rendered string: two runs never draw
      // the same `V` ids, and the printer's binder and constraint ORDER
      // follows id-keyed sets, so a rendered-string comparison reports
      // an ordering difference as a divergence.  6.6's sweep measured
      // exactly that (145 of 223 "failures", all order) and this
      // comparator -- G1's own, the one the .ei differential runs on --
      // is the answer it settled on.
      // WHAT THE CLIENT SEES first -- hover renders a type, so two runs
      // that PRINT the same thing are indistinguishable to the editor --
      // and alpha-equivalence as the fallback for the id-ordering
      // artifact 6.6 documented (a reused scheme was generalised with
      // different `V` ids, and the printer's binder and constraint order
      // follows id-keyed sets).  Neither alone is the right oracle:
      // rendering is too strict on order, and `aeq` has an id-dependent
      // clause for free variables that makes it vary between runs.
      def typesAgree(a: resident.Checked, c: resident.Checked): Boolean =
        a.types.keySet == c.types.keySet &&
        a.types.forall { case (k, t) =>
          Pretty.prettyType(t, -1).toString == Pretty.prettyType(c.types(k), -1).toString ||
          sameType(t, c.types(k)) }
      // A LOCAL's type is compared AS HOVER RENDERS IT (6.2's own
      // oracle) and not up to alpha: a local's type routinely contains
      // free metas that no generalisation closed, which two runs draw
      // with different ids and which alpha-equivalence therefore refuses
      // to pair -- while both print `a`, which is what the editor shows.
      def localsAgree(a: resident.Checked, c: resident.Checked): Boolean =
        locs(a) == locs(c)

      files.foreach { f =>
        val text = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
        val shifted = "\n" + text
        val hot = new Documents
        for {
          c0 <- one(f, text, hot, 1L)
          if !c0.notes.exists(_.severity == TolerantCheck.Error)
          ctl <- one(f, text, hot, 2L)
          warm <- one(f, shifted, hot, 3L)
          cold <- one(f, shifted, new Documents, 1L)
        } {
          clean += 1
          totalComps += warm.components
          reusedComps += warm.reused
          if (warm.components > 0) withComps += 1
          if (warm.reused > 0) reusedFiles += 1
          // (c) THE CLIFF, per module: a check whose only change is a
          // line shift must reuse EXACTLY what an unedited re-check
          // reuses.  Before 7.2 the left side was always 0.
          if (warm.reused != ctl.reused)
            bad += ("%s: shifted reuse %d, unshifted reuse %d".format(
              f.getName, warm.reused, ctl.reused))
          // Anti-vacuity: the check must have read the EDITED buffer.
          if (warm.contents != shifted) bad += (f.getName + ": the check did not read the buffer")
          // (a) notes
          val nw = warm.notes.map(n => (n.severity, n.report))
          val nc = cold.notes.map(n => (n.severity, n.report))
          if (nw != nc) bad += (f.getName + ": NOTES differ warm vs cold")
          if (ctl.notes.map(n => (n.severity, n.report)) != c0.notes.map(n => (n.severity, n.report)))
            bad += (f.getName + ": NOTES differ on an unshifted reuse")
          // (b) def-site POSITIONS: strict, both ways
          if (locs(warm).keySet != locs(cold).keySet)
            bad += (f.getName + ": local DEF-SITES differ warm vs cold")
          if (locs(warm).keySet != locs(c0).keySet.map { case (l, c) => (l + 1, c) })
            bad += (f.getName + ": local DEF-SITES are not the pre-edit ones + 1 line")
          // (d) TYPES, up to alpha.  The rendered strings are counted
          // beside them, as the measure of how often the pre-7.2 id
          // ordering makes two agreeing runs print differently.
          if (rend(ctl) != rend(c0) || locs(ctl) != locs(c0)) ctlDiff += 1
          // THE CONTROL: what reuse alone does, with no edit and no
          // shift.  A divergence this item may not add is one that shows
          // up SHIFTED where the unshifted reuse agrees.
          // THE SECOND CONTROL, and the one that turned out to matter:
          // two COLD checks of the same module, no cache on either side.
          // They do not always publish the same row constraints -- the
          // simplifier's queue is id-hash ordered and the `Supply` has
          // moved between them (PERF-ROADMAP P10, `Session.scala`'s own
          // note on -Dermine.loadInSeries).  A module where the checker
          // disagrees with ITSELF cannot indict the cache.
          val coldStable = typesAgree(cold, c0)
          if (!coldStable) coldDiff += 1
          // THE LOCALS, between the two WARM checks, with the shift taken
          // out of the KEYS: a third statement of the re-anchoring, and
          // the only one of these comparisons that is fully
          // deterministic -- both sides serve the same cache entries and a
          // rendered local type is id-order-free.
          if (locs(warm) != locs(ctl).map { case ((l, c), t) => (l + 1, c) -> t })
            bad += (f.getName + ": LOCALS differ between a SHIFTED and an UNSHIFTED warm check")
          // THE THIRD CONTROL.  The two WARM checks serve the same cache
          // entries, so if they disagree the disagreement is in a
          // component NEITHER of them cached -- freshly inferred on both
          // sides with the `Supply` in a different place -- or in the
          // comparator, which is not transitive.  Either way it is not
          // the shift.  `Relation.e` is the module this excuses.
          val warmStable = typesAgree(warm, ctl)
          if (!warmStable) warmDiff += 1
          if (!typesAgree(warm, cold) && typesAgree(ctl, c0) && coldStable && warmStable) {
            val ns = (warm.types.keySet ++ cold.types.keySet).toList.sorted.filter { k =>
              !(warm.types.get(k), cold.types.get(k)).match {
                case (Some(x), Some(y)) =>
                  Pretty.prettyType(x, -1).toString == Pretty.prettyType(y, -1).toString ||
                  sameType(x, y)
                case _ => false } }
            bad += (f.getName + ": TYPES (alpha) differ warm vs cold where an UNSHIFTED reuse agrees" +
              ns.take(3).map(k => "\n      " + k +
                "\n        warm " + warm.types.get(k).map(t => Pretty.prettyType(t, -1).toString) +
                "\n        cold " + cold.types.get(k).map(t => Pretty.prettyType(t, -1).toString) +
                "\n        ctl  " + ctl.types.get(k).map(t => Pretty.prettyType(t, -1).toString) +
                "\n        c0   " + c0.types.get(k).map(t => Pretty.prettyType(t, -1).toString)).mkString)
          }
          // The same three controls for the RENDERED LOCAL TYPES: a local's
          // type can carry row constraints too, so it is subject to
          // finding (ii) exactly as a published type is.  `Relation.e`
          // needs this one.
          val localsColdStable =
            locs(cold) == locs(c0).map { case ((l, c), t) => (l + 1, c) -> t }
          if (!localsColdStable) localsColdDiff += 1
          if (!localsAgree(warm, cold) && localsAgree(ctl, c0) && localsColdStable)
            bad += (f.getName + ": LOCAL types differ warm vs cold where every control agrees")
        }
      }
      println("### 7.2 sweep: " + clean + " clean modules of " + files.size +
              " \u2014 " + reusedFiles + " of " + withComps +
              " with components reused after a top-of-file insertion, " +
              reusedComps + " of " + totalComps + " components; " +
              ctlDiff + " render differently on an UNSHIFTED reuse (pre-7.2), " +
              coldDiff + " publish different row constraints on two COLD checks, " +
              warmDiff + " on two WARM checks, " + localsColdDiff +
              " render a LOCAL differently on two COLD checks; mismatches " + bad.size)
      if (bad.nonEmpty) bad.foreach(x => println("###   " + x))
      ((files.size >= 180) :| s"only ${files.size} corpus files") &&
      ((clean >= 100) :| s"only $clean modules checked cleanly on all four passes") &&
      // Anti-vacuity only: the per-module equality above is the real
      // assertion, and it would pass on a corpus that reused nothing.
      ((reusedFiles * 4 >= withComps * 3) :|
        s"only $reusedFiles of $withComps modules with components reused after a line shift") &&
      ((reusedComps * 4 >= totalComps * 3) :|
        s"only $reusedComps of $totalComps components reused after a line shift") &&
      ((bad.isEmpty) :| ("%d module(s) not invisible: %s".format(
        bad.size, bad.take(10).mkString(" ;; "))))
    }
  }

  property("an import that will not load is reported on its own import statement") = secure {
    // 6.1(b).  BadImport.e imports a module that does not exist and a
    // sibling whose body has a syntax error.  Before this item the first
    // failure threw out of checkFile and became ONE diagnostic at 0:0:
    // the second import, and every healthy definition in the file, went
    // unreported.
    residentLock.synchronized {
      val docs = new Documents
      val ds = diagnose(new File("tracker" + File.separator + "lsp-tests" +
                                 File.separator + "BadImport.e"), docs)
      val missing = ds.filter(d => message(d) contains "NoSuchModule")
      val sibling = ds.filter(d => message(d) contains "BadSib")
      // two import failures AND the file's own type error: the roadmap's
      // tick condition is that the other diagnostics still publish, so it
      // is asserted positively, not as an absence (review R4).
      ((ds.size == 3) :| s"got ${ds.size}: ${ds.map(d => where(d) + " " + message(d).take(60))}") &&
      ((ds.count(d => message(d) contains "failed to unify") == 1) :|
        ds.map(message(_).take(60)).toString) &&
      ((missing.size == 1 && sibling.size == 1) :| ds.map(message(_).take(60)).toString) &&
      // the module NAME of `import NoSuchModule`, line 3, columns 8-19
      ((missing.forall(d => severity(d) == 1 && at(d, "start", "line") == 2 &&
                            at(d, "start", "character") == 7 &&
                            at(d, "end", "character") == 19)) :|
        missing.map(where).toString) &&
      // ... and of `import BadSib`, line 4, columns 8-13
      ((sibling.forall(d => severity(d) == 1 && at(d, "start", "line") == 3 &&
                            at(d, "start", "character") == 7 &&
                            at(d, "end", "character") == 13)) :|
        sibling.map(where).toString) &&
      // the loader's own report is kept: it names the sibling's file and
      // the position inside it, which is the only thing that says WHY
      ((sibling.forall(d => message(d) contains "BadSib.e:5:")) :|
        sibling.map(message).toString) &&
      // the rule (6.1(b) step 2): while an import has failed, the names
      // it would have provided are not reported as undefined terms, and
      // nothing is reported "unchecked" on their account
      ((!ds.exists(d => message(d) contains "undefined term")) :| ds.map(message).toString) &&
      ((!ds.exists(d => message(d) contains "unchecked")) :| ds.map(message).toString)
    }
  }

  property("a header that will not parse is still positioned in this file") = secure {
    // 6.1(b) step 3: the one Death that is genuinely about THIS file.
    // `fromReport` recovers its position from the report's first line;
    // the pin is that it does, and that the end is not 0:0 either.
    residentLock.synchronized {
      val docs = new Documents
      val ds = diagnose(new File("tracker" + File.separator + "lsp-tests" +
                                 File.separator + "BadHeader.e"), docs)
      ((ds.size == 1) :| ds.map(d => where(d) + " " + message(d).take(60)).toString) &&
      (ds.forall(d => at(d, "start", "line") == 0 && at(d, "start", "character") == 17 &&
                      at(d, "end", "line") == 0 && at(d, "end", "character") == 17) :|
        ds.map(where).toString) &&
      (ds.forall(d => !at00(d)) :| ds.map(where).toString)
    }
  }

  // ------------------------------------------------------------------ 6.6

  /** THE 6.6 SWEEP (Decision (e): the ONE correctness measurement for the
    * add-signature quick fix, which is offered without any server-side
    * re-checking).
    *
    * For every file of the 180-file corpus: check it, render the
    * add-signature edit for EVERY unsigned top-level group, apply them
    * ALL to a copy of the text in memory, and check the copy.  A file
    * whose copy checks silent AND whose every group's type renders the
    * same as before is N clean insertions; a file that does not is
    * BISECTED, one insertion at a time, so every failure is attributed to
    * the insertion that caused it.
    *
    * The classes: CLEAN, PARSE-FAIL (a new READ diagnostic —
    * `Checked.diags`, the tolerant read's own, so the inserted line did
    * not parse), TYPE-FAIL (a new CHECK note, or a group whose type moved,
    * with the read silent) and SKIPPED (the builder refused, with its
    * reason).  ALPHA-EQUIVALENCE is compared as RENDERED TEXT: both sides
    * go through `QuickFix.render`, i.e. `Pretty.prettyType(t, -1)` with
    * the same fresh-variable supply, so two alpha-equivalent types render
    * to the same string by construction and a difference is a difference.
    *
    * SLOW: two checks of the corpus, plus one per failing insertion.  It
    * runs only under `-Dermine.sweep.quickfix=true`, the way the gate
    * policy quarantines a property that cannot be a per-commit gate; the
    * numbers of record are in `tracker/loopmodel/LSP3-6.6-QUICKFIX.md`.
    */
  private def sweepOn: Boolean = sys.props.get("ermine.sweep.quickfix").contains("true")

  /** Which shape a rendered type is, for the failure table.  Syntactic,
    * on the rendered text, because that is also what a SHIPPING FILTER
    * could be if the bar were missed. */
  private def shape(r: String): String =
    if (r.contains("<-")) "row constraint (<-)"
    else if (r.contains("(|")) "concrete row (|…|)"
    else if (r.contains("=>")) "class constraint (=>)"
    else if (r.contains("exists")) "exists"
    else if (r.contains("forall")) "forall"
    else if (r.contains("->")) "arrow"
    else "ground"

  private def applyInserts(text: String, es: List[QuickFix.TEdit]): String = {
    val eol = QuickFix.eolOf(text)
    val ls = text.split("\n", -1).toBuffer
    // Descending by line, so an earlier insertion cannot move a later one.
    es.sortBy(-_.sl).foreach { e =>
      ls.insert(e.sl, e.newText.stripSuffix(eol) + (if (eol == "\r\n") "\r" else ""))
    }
    ls.mkString("\n")
  }

  property("6.6 sweep: an inserted signature parses and checks (Decision e)") =
    if (!sweepOn) Prop.proved
    else residentLock.synchronized {
    val files = corpusFiles.map(_.getAbsoluteFile)
    var excluded = 0
    var groupsSeen = 0
    var insertions = 0
    var clean = 0
    val parseFail = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
    val typeFail  = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
    val skipped   = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
    val example   = scala.collection.mutable.Map.empty[String, String]
    val scannerBad = scala.collection.mutable.ListBuffer.empty[String]
    val failures   = scala.collection.mutable.ListBuffer.empty[String]
    val oos        = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
    val oosName    = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
    val excludedFiles = scala.collection.mutable.ListBuffer.empty[String]

    def check1(f: java.io.File, text: String, v: Long): Option[resident.Checked] = {
      val docs = new Documents
      docs.put(f.toURI.toString, text, v)
      try Some(resident.checkFile(f.toPath, docs)) catch { case Death(_, _) => None }
    }
    def rendered(c: resident.Checked): Map[String, String] =
      c.types.map { case (k, t) => k -> QuickFix.render(t) }
    def errs(c: resident.Checked) = c.notes.count(_.severity == TolerantCheck.Error)
    // ALPHA-EQUIVALENCE is `tools/G1Compare.alphaEq`, the comparator the
    // G1 gate's .ei differential is built on: a consistent bijection over
    // bound variables, Exists binders paired lazily through constraint
    // matching, and every constraint multiset matched by backtracking
    // permutation.  A rendered-string comparison is NOT good enough and
    // the first run of this sweep proved it: 145 of its 223 "failures"
    // were a `forall {a b c …}` kind-binder group in a different ORDER
    // (`Layout/Column.e`'s `endoColumn`) or a `Part`'s row-constraint
    // arguments in a different order (`Field.e`'s `getF2`) — the same two
    // classes G1's own gate calls logically equal.
    // ... with ONE completeness repair, made HERE and not in G1Compare
    // (that comparator is a gate tool and its verdicts are not this
    // item's to move): `G1Compare.matchMultiset` keeps only the FIRST
    // bijection each constraint admits, so a permuted row-constraint set
    // whose first pairing paints the bijection into a corner is reported
    // unequal even when a consistent pairing exists.  `Relation.e`'s `&`
    // is exactly that (`a <- (e, d), r <- (d, c)` against
    // `a <- (d, e), r <- (c, d)`).  The version below returns EVERY
    // bijection lazily, so the search backtracks properly and stops at
    // the first success; it is strictly more permissive than
    // `G1Compare.alphaEq` and agrees with it everywhere that one succeeds.
    // Both numbers are in the report.
    import com.clarifi.reporting.ermine.{ AppT, Arrow, ConcreteRho, Exists, Forall,
                                          Memory, Part, ProductT, Type, VarT }
    type Bij = com.clarifi.reporting.ermine.tools.G1Compare.Bij
    // `aeq`/`multi` are shared with the 7.2 sweep and live at object
    // scope now (7.2); this block used to define them inline.
    var g1Only = 0
    def sameTy(a: Type, b: Type): Boolean = {
      val strict = AlphaEq.strict(a, b)
      val loose = strict || AlphaEq.loose(a, b)
      if (loose && !strict) g1Only += 1
      loose
    }
    def sameAll(base: Map[String, Type],
                c: resident.Checked, names: List[String]): Boolean =
      names.forall(n => base.get(n).exists(t => c.types.get(n).exists(sameTy(t, _))))

    files.foreach { f =>
      val text = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      check1(f, text, 1L) match {
        case None => excluded += 1; excludedFiles += f.getName
        case Some(c0) if c0.diags.nonEmpty || errs(c0) > 0 =>
          excluded += 1; excludedFiles += f.getName
        case Some(c0) =>
          // The import scanner, differentially against the PARSER's own
          // header on the same text: module names, aliases, the list kind
          // and the spellings the list names.
          val mine = QuickFix.imports(text).map(i =>
            (i.module, i.alias, i.isUsing,
             if (i.isUsing.isEmpty) Nil else i.items.map(x => (x.name, x.isType, x.provides)).sorted))
          // The parser keeps an operator's PARENS in the item's spelling
          // (`(++)`); the scanner strips them, because the spelling an
          // undefined-term note carries is the bare one it has to match.
          // Normalised here rather than in the scanner for that reason.
          def bare(x: String) =
            if (x.startsWith("(") && x.endsWith(")") && x.length > 2) x.substring(1, x.length - 1).trim
            else x
          val theirs = c0.module.header.imports.map(i =>
            (i.module, i.as.map(_.spelling), i.items.map(_._1),
             i.items.toList.flatMap(_._2).map(x =>
               (bare(x.name.spelling), x.isType,
                bare(x.renameTo.map(_.spelling).getOrElse(x.name.spelling)))).sorted))
          if (mine.sortBy(_._1) != theirs.sortBy(_._1))
            scannerBad += f.getName + ": mine=" + mine + " parser=" + theirs

          val gs = QuickFix.groups(c0.module).filterNot(_.hasSig)
          groupsSeen += gs.size
          val built = gs.map { g =>
            val e = c0.types.get(g.spelling) match {
              case None    => Left(QuickFix.NoType: QuickFix.SigSkip)
              // THE CHECK'S OWN env, not the resident one: a module this
              // file's imports dragged in has its origins only there, and
              // `Definitions.index` stores exactly these two maps.
              // 7.5, ticket E10(5): `ownTypes` is the ninth argument, and
              // it is the check's own -- the file's nullary type synonyms
              // resolved to the `Con` each names, which is what lets the
              // scope test see through `type Scan = Scan_S`.
              case Some(t) => QuickFix.sigEdit(text, g, t, c0.scope.canonicalTypes,
                                               c0.scope.canonicalTerms,
                                               c0.env.consOrigins,
                                               c0.env.termNameOrigins, c0.name,
                                               c0.ownTypes)
            }
            (g, e)
          }
          // The names this module DECLARES as types (a `type` synonym or a
          // `data`), for the sub-classification of the out-of-scope
          // refusals below (review R-1).
          val ownTypeNames: Set[String] = {
            def go(ss: List[com.clarifi.reporting.ermine.surface.SStatement]): List[String] = ss flatMap {
              case x: com.clarifi.reporting.ermine.surface.STypeAlias    => List(x.name.spelling)
              case x: com.clarifi.reporting.ermine.surface.SDataStatement => List(x.name.spelling)
              case b: SPrivateBlock  => go(b.statements)
              case b: SDatabaseBlock => go(b.statements)
              case _ => Nil
            }
            go(c0.module.statements).toSet
          }
          val scopeKeys = c0.scope.canonicalTypes.keySet.map(_.string)
          built.foreach {
            case (g, Left(sk)) =>
              val k = sk match {
                case QuickFix.OutOfScope(_) => "out of scope"
                case x                      => x.why
              }
              skipped(k) = skipped(k) + 1
              example.getOrElseUpdate("SKIP " + k,
                f.getName + " " + g.spelling + ": " + sk.why)
              // R-1: WHY is it out of scope?  Three sub-classes, per NAME.
              sk match {
                case QuickFix.OutOfScope(ns) => ns.foreach { n =>
                  val cls =
                    if (ownTypeNames(n)) "own synonym/data (a FALSE NEGATIVE: the file can write it)"
                    else if (scopeKeys.exists(k2 => k2.startsWith(n + "_"))) "imported under an ALIAS"
                    else "not nameable here"
                  oos(cls) = oos(cls) + 1
                  oosName(n + "  [" + cls + "]") = oosName(n + "  [" + cls + "]") + 1
                }
                case _ => ()
              }
            case _ => ()
          }
          val ok = built.collect { case (g, Right((txt, e))) => (g, txt, e) }
          insertions += ok.size
          if (ok.nonEmpty) {
            val base = c0.types
            val names = ok.map(_._1.spelling)
            val all = applyInserts(text, ok.map(_._3))
            val cAll = check1(f, all, 2L)
            val allClean = cAll.exists(c => c.diags.isEmpty && errs(c) == 0 &&
                                            sameAll(base, c, names))
            if (allClean) clean += ok.size
            else ok.foreach { case (g, txt, e) =>
              // BISECT: one insertion at a time, so a failure is attributed
              // to the line that caused it and not to its neighbours.
              val one = applyInserts(text, List(e))
              val c1 = check1(f, one, 3L)
              val sh = shape(txt)
              c1 match {
                case None =>
                  parseFail("Death: " + sh) = parseFail("Death: " + sh) + 1
                  failures += ("PARSE(Death) " + f.getName + ": " + txt)
                case Some(c) if c.diags.nonEmpty =>
                  parseFail(sh) = parseFail(sh) + 1
                  failures += ("PARSE " + f.getName + ": " + txt + "  -->  " +
                               c.diags.head.message.take(100))
                case Some(c) if errs(c) > 0 =>
                  typeFail(sh) = typeFail(sh) + 1
                  failures += ("TYPE " + f.getName + ": " + txt + "  -->  " +
                    c.notes.find(_.severity == TolerantCheck.Error)
                      .map(_.report.linesIterator.take(2).mkString(" ").take(130)).getOrElse(""))
                case Some(c) if !sameAll(base, c, List(g.spelling)) =>
                  typeFail("type moved: " + sh) = typeFail("type moved: " + sh) + 1
                  failures += ("MOVED " + f.getName + " " + g.spelling + ": " +
                    QuickFix.render(base(g.spelling)).take(150) + "  -->  " +
                    c.types.get(g.spelling).map(QuickFix.render).getOrElse("?").take(150))
                case Some(c) if !sameAll(base, c, names) =>
                  typeFail("moved a neighbour: " + sh) = typeFail("moved a neighbour: " + sh) + 1
                  failures += ("NEIGHBOUR " + f.getName + " " + g.spelling + ": " + txt.take(120))
                case _ => clean += 1
              }
            }
          }
      }
    }
    val pct = if (insertions == 0) 0.0 else 100.0 * clean / insertions
    println("### 6.6 sweep: files " + files.size + " (excluded " + excluded +
            "), groups " + groupsSeen + ", insertions " + insertions +
            ", CLEAN " + clean + " (%.2f%%)".format(pct))
    println("###   PARSE-FAIL " + parseFail.toList.sorted.mkString(", "))
    println("###   TYPE-FAIL  " + typeFail.toList.sorted.mkString(", "))
    println("###   SKIPPED    " + skipped.toList.sorted.mkString(", "))
    example.toList.sorted.foreach(e => println("###   eg " + e._1 + " | " + e._2))
    println("###   every failing insertion (" + failures.size + "):")
    failures.toList.sorted.foreach(x => println("###     " + x))
    println("###   OUT-OF-SCOPE by sub-class " + oos.toList.sorted.mkString(", "))
    oosName.toList.sortBy(-_._2).take(14).foreach(x => println("###     oos " + x._2 + " x " + x._1))
    println("###   excluded files: " + excludedFiles.mkString(", "))
    println("###   pairs equal only under the COMPLETE comparator: " + g1Only)
    println("###   import-scanner disagreements " + scannerBad.size)
    scannerBad.take(12).foreach(x => println("###     " + x))
    ((files.size >= 180) :| s"only ${files.size} corpus files") &&
    ((insertions >= 500) :| s"only $insertions insertions") &&
    ((scannerBad.isEmpty) :| s"${scannerBad.size} import-scanner disagreements: ${scannerBad.take(3)}") &&
    ((pct >= 95.0) :| f"only $pct%.2f%% of $insertions insertions clean")
  }
}
