package com.clarifi.reporting

import java.io.File

import com.clarifi.reporting.ermine.{ Global, Idfix, InfixR, Local }
import com.clarifi.reporting.ermine.lsp.{ Completion, Definitions, Symbols }
import com.clarifi.reporting.ermine.rename.{ ModuleScope, Renamer }
import com.clarifi.reporting.ermine.rename.Renamer._
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._

/** Renamer semantics against the pinned spec (roadmap 3.2a): resolution
  * through frames + canonical scope, id-unification, whole-block
  * scoping, do sequencing, the two owed refusals, and the LSP outputs.
  * Uses a synthetic import scope — no session boot. */
object TestRenamer extends Properties("Renamer 3.2a") {

  private val funcId    = Global("Function", "id")
  private val funcConst = Global("Function", "const")
  private val boolAnd   = Global("Bool", "&&")

  private val scope = ModuleScope.Scope(
    canonicalTerms = Map(
      Local("id", Idfix)      -> List(funcId),
      Local("id_F", Idfix)    -> List(funcId),
      Local("const", Idfix)   -> List(funcConst),
      Local("&&", InfixR(3))  -> List(boolAnd)),
    canonicalTypes = Map(),
    termNames = Map(),
    termOrigins = Map(funcId -> List(funcId), funcConst -> List(funcConst)),
    typeOrigins = Map())

  private def renamed(body: String): Renamer.Result = {
    SurfaceParsers.module("t", "module T where\n" + body, "T") match {
      case Right(m)  => Renamer.rename(m, scope)
      case Left(err) => sys.error("parse failed: " + err)
    }
  }

  private def resOf(r: Renamer.Result, spelling: String): List[Resolution] =
    r.occurrences.filter(_.spelling == spelling).map(_.resolution)

  property("sig and equations share one binder; def-site is the last equation") = secure {
    val r = renamed("f : a\nf 0 = 1\nf q = q")
    val ids = r.occurrences.filter(_.spelling == "f").collect { case Occurrence(_, _, ToBinder(i), _) => i }.distinct
    val info = r.binders(ids.head)
    val qKinds = resOf(r, "q").collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((ids.size ?= 1) :| "one binder id") &&
    ((info.defSite.startLine ?= 4) :| s"def-site last equation, got ${info.defSite}") &&
    ((qKinds ?= List(Renamer.Arg: BinderKind)) :| s"body q binds the argument, got $qKinds")
  }

  property("references: own binder beats import; import resolves with origin; unknown tolerated") = secure {
    val r = renamed("mine = 1\nuse = mine\nborrow = const\nmystery = frob")
    (resOf(r, "mine").forall(_.isInstanceOf[ToBinder]) :| "own binder") &&
    ((resOf(r, "const").head ?= ToGlobal(funcConst, funcConst, funcConst)) :| "imported") &&
    ((resOf(r, "frob").head ?= Unresolved("frob")) :| "placeholder tolerance")
  }

  property("let and where scope over every rhs and the body (heads first)") = secure {
    val r = renamed("v = let a = w\n        w = 5\n    in a\nu = q where q = w2\n            w2 = 6")
    val letW = resOf(r, "w")
    val whW2 = resOf(r, "w2")
    (letW.forall(_.isInstanceOf[ToBinder]) :| s"early sibling w binds block: $letW") &&
    (whW2.forall(_.isInstanceOf[ToBinder]) :| s"where sibling w2 binds block: $whW2")
  }

  property("a where binding shadows the equation argument for the body") = secure {
    val r = renamed("f w = w + 1 where w = 5")
    val wOccs = r.occurrences.filter(o => o.spelling == "w" && o.span.startLine == 2)
    val bodyRef = wOccs.find(o => o.span.startCol > 6 && o.span.startCol < 12).get
    val whereBinder = r.binders(bodyRef.resolution.asInstanceOf[ToBinder].id)
    (whereBinder.kind ?= WhereBound) :| s"body w resolves to the where binder, got $whereBinder"
  }

  property("do binders: rhs sees outer, later statements see the binder") = secure {
    val r = renamed("g w = do w <- liftDo (w + 1)\n         unit w")
    val occs = r.occurrences.filter(_.spelling == "w").sortBy(o => (o.span.startLine, o.span.startCol))
    // order: arg binder is not an occurrence; rhs w (line 2), final w (line 3)
    val rhsW  = occs.find(o => o.span.startLine == 2 && o.span.startCol > 20).get
    val lastW = occs.find(_.span.startLine == 3).get
    val rhsKind  = r.binders(rhsW.resolution.asInstanceOf[ToBinder].id).kind
    val lastKind = r.binders(lastW.resolution.asInstanceOf[ToBinder].id).kind
    ((rhsKind ?= (Renamer.Arg: BinderKind)) :| s"rhs sees the outer argument, got $rhsKind") &&
    ((lastKind ?= DoBound) :| s"after the bind, the do binder, got $lastKind")
  }

  property("shadowing the plain name leaves the alias resolving to the global") = secure {
    val r = renamed("f id = id_F id")
    ((resOf(r, "id_F").head ?= ToGlobal(funcId, funcId, funcId)) :| "alias untouched") &&
    (resOf(r, "id").forall(_.isInstanceOf[ToBinder]) :| "plain name captured by the binder")
  }

  property("owed refusal: a top-level binder shadowing an import is diagnosed") = secure {
    val r = renamed("id = 1")
    r.diagnostics.exists(_.message contains "would shadow global definition") :| r.diagnostics.toString
  }

  property("owed refusal: a ':'-operator binder naming a constructor is diagnosed") = secure {
    val consScope = scope.copy(canonicalTerms =
      scope.canonicalTerms + (Local("::", InfixR(5)) -> List(Global("Builtin", "::"))))
    val m = SurfaceParsers.module("t", "module T where\nv = let (::) a b = 7 in 1", "T")
      .getOrElse(sys.error("parse"))
    val r = Renamer.rename(m, consScope)
    r.diagnostics.exists(_.message contains "would shadow a data constructor") :| r.diagnostics.toString
  }

  property("operator occurrences resolve through the fixity bucket") = secure {
    val r = renamed("v = a && b\na = 1\nb = 2")
    (resOf(r, "&&").head ?= ToGlobal(boolAnd, boolAnd, boolAnd)) :| resOf(r, "&&").toString
  }

  property("scope-at-position sees block binders only inside the block") = secure {
    val r = renamed("v = let deep = 1 in deep\nafter = 2")
    val inside  = r.scopeAt(2, 22)
    val outside = r.scopeAt(3, 3)
    ((inside contains "deep") :| s"inside: $inside") &&
    ((!(outside contains "deep")) :| s"outside: $outside") &&
    ((outside contains "after") :| "top-level visible")
  }

  // ------------------------------------------------------------- 3.2b

  property("Death rendering carries file:line:col plus the caret line") = secure {
    val source = "module T where\nok = 1\nid = 2\n"
    val m = SurfaceParsers.module("t", source, "T").getOrElse(sys.error("parse"))
    try { Renamer.renameOrDie(m, scope, source); falsified :| "expected Death" }
    catch {
      case d: scalaparsers.Death =>
        val msg = d.getMessage
        ((msg.linesIterator.next() startsWith "t:3:1: error: term definition would shadow") :| msg.take(90)) &&
        ((msg.linesIterator.toList.lift(1) ?= Some("id = 2")) :| "source line for the caret") &&
        ((msg.linesIterator.toList.lift(2).exists(_.trim == "^")) :| "caret")
    }
  }

  property("class members bind like top-levels and refuse import shadowing") = secure {
    val ok = renamed("class Frob a where\n  frob q = frub q\n  frub q = q")
    val frubRes = resOf(ok, "frub").collect { case ToBinder(i) => ok.binders(i).kind }
    val shadow = renamed("class Frob a where\n  id q = q")
    ((frubRes.distinct ?= List(Renamer.TopLevel: BinderKind)) :| s"member cross-ref: $frubRes") &&
    (shadow.diagnostics.exists(_.message contains "would shadow global definition") :| shadow.diagnostics.toString)
  }

  property("foreign class names resolve at rename; failures are diagnosed") = secure {
    val good = renamed("foreign\n  data \"java.lang.String\" JStr")
    val bad  = renamed("foreign\n  data \"com.nope.Missing\" Gone")
    ((good.diagnostics ?= Nil) :| good.diagnostics.toString) &&
    (bad.diagnostics.exists(_.message contains "error loading 'com.nope.Missing'") :| bad.diagnostics.toString)
  }

  // ------------------------------------------------------------- 3.2c

  private def tyOccs(r: Renamer.Result, spelling: String) =
    r.occurrences.filter(_.spelling == spelling)

  property("sig type variables quantify per annotation, independently") = secure {
    val r = renamed("f : a -> a\ng : a -> b")
    val aIds = tyOccs(r, "a").map(_.resolution).collect { case ToBinder(i) => i }.distinct
    val kinds = aIds.map(r.binders(_).kind).distinct
    ((aIds.size ?= 2) :| s"two independent implicit binders for a, got $aIds") &&
    ((kinds ?= List(Renamer.TyImplicit: BinderKind)) :| kinds.toString) &&
    ((tyOccs(r, "a").size ?= 3) :| "three occurrences of a (2 in f, 1 in g)")
  }

  property("forall binders capture; kind braces bind kind vars") = secure {
    val r = renamed("h : forall {k} (a: k) b. a -> b")
    val aRes = tyOccs(r, "a").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    val kRes = tyOccs(r, "k").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((aRes ?= List(Renamer.TyParam: BinderKind)) :| s"a: $aRes") &&
    ((kRes ?= List(Renamer.KindParam: BinderKind)) :| s"k: $kRes")
  }

  property("data declaration args scope over constructor fields") = secure {
    val r = renamed("data D {k} (a: k) b = MkD a b")
    val fieldRefs = tyOccs(r, "a").map(_.resolution) ++ tyOccs(r, "b").map(_.resolution)
    fieldRefs.forall {
      case ToBinder(i) => r.binders(i).kind == Renamer.TyParam
      case _ => false
    } :| fieldRefs.toString
  }

  property("kind atoms and arrows are builtin; unknown constructors tolerated") = secure {
    val r = renamed("w : forall (m: rho -> *). Wibble m")
    val star = tyOccs(r, "*").map(_.resolution)
    val wib  = tyOccs(r, "Wibble").map(_.resolution)
    (star.forall { case ToGlobal(g, _, _) => g.module == "Builtin"; case _ => false } :| star.toString) &&
    ((wib ?= List(Unresolved("Wibble"))) :| wib.toString)
  }

  property("partition constraints share the annotation's implicit vars") = secure {
    val r = renamed("q : exists c. r <- (h, c)")
    // r and h are annotation-implicit; c is the exists binder
    val cKind = tyOccs(r, "c").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    val rKind = tyOccs(r, "r").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((cKind ?= List(Renamer.TyParam: BinderKind)) :| s"c: $cKind") &&
    ((rKind ?= List(Renamer.TyImplicit: BinderKind)) :| s"r: $rKind")
  }

  // ----------------------------------------------------------------------
  // 6.3 TABLE INTEGRITY over the whole corpus (stdlib + core/examples, the
  // standing 180-file rule).
  //
  // These are what `textDocument/references`, `documentHighlight` and
  // `rename` STAND ON: the LSP joins an occurrence to a binder by id, a
  // binder to a position by its def-site, and a spelling to a top level by
  // `moduleTerms` -- and then EDITS the file at the spans it read off.  If
  // an id had no binder, a def-site pointed outside the file, two binders
  // claimed one position, or two occurrences claimed overlapping text, a
  // rename would write nonsense.  No session is needed: an empty import
  // scope leaves more names `Unresolved` but changes no binder, no
  // def-site and no span, which is all these properties look at.

  private val stdlibRoot = new File("core/src/main/resources/modules")

  private def walk(f: File): List[File] =
    if (f.isDirectory) Option(f.listFiles).toList.flatMap(_.toList.sortBy(_.getName)).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  /** The same exclusions TestTolerantRead's sweep makes: `shouldfail/` is
    * meant to be rejected and `incomplete/` does not always terminate. */
  private val notGoodCode = Set("shouldfail", "shouldfail-controls", "incomplete")

  private def corpusFiles: List[File] =
    (walk(stdlibRoot) ++ walk(new File("core/examples")))
      .filterNot(f => Option(f.getParentFile).exists(d => notGoodCode(d.getName)))

  /** The corpus files the surface parser REFUSES outright; named, so the
    * sweep's denominator is never quietly smaller than the corpus. */
  private lazy val unparsed: List[String] =
    corpusFiles.filter { f =>
      val src = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      SurfaceParsers.module(f.toString, src, f.getName.stripSuffix(".e")).isLeft
    }.map(_.getName)

  /** file -> (contents, surface tree), for every file that parses.  Parsed
    * ONCE: the renamer tables and the 6.4 symbol trees both come off it. */
  private lazy val corpusTrees: List[(File, String, SModule)] =
    corpusFiles.flatMap { f =>
      val src = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      SurfaceParsers.module(f.toString, src, f.getName.stripSuffix(".e")) match {
        case Right(m) => List((f, src, m))
        case Left(_)  => Nil
      }
    }

  /** file -> (contents, renamer tables), for every file that parses. */
  private lazy val corpusTables: List[(File, String, Renamer.Result)] =
    corpusTrees.map { case (f, src, m) =>
      (f, src, Renamer.rename(m, ModuleScope.Scope.empty)) }

  property("6.3 corpus: the tables are there at all") = secure {
    val n = corpusTables.size
    val occs = corpusTables.map(_._3.occurrences.size).sum
    val toB  = corpusTables.map(_._3.occurrences.count(_.resolution.isInstanceOf[ToBinder])).sum
    val bs   = corpusTables.map(_._3.binders.size).sum
    val mt   = corpusTables.map(_._3.moduleTerms.size).sum
    // `collect` prints on a PASS too (sbt's scalacheck runner shows the
    // collected data), so the counts these properties cover are reported
    // rather than only asserted.
    Prop.collect(s"files ${corpusFiles.size} renamed $n | occurrences $occs " +
                 s"(ToBinder $toB) | binders $bs | moduleTerms $mt" +
                 (if (unparsed.isEmpty) "" else " | unparsed " + unparsed.mkString(","))) {
      ((n >= 150) :| s"corpus files renamed: $n (files found: ${corpusFiles.size})") &&
      ((occs > 10000) :| s"occurrences: $occs") &&
      ((bs > 3000) :| s"binders: $bs")
    }
  }

  property("6.3 corpus: every ToBinder occurrence has a binder, in this file") = secure {
    val bad = corpusTables.flatMap { case (f, src, r) =>
      val lines = src.linesIterator.size
      r.occurrences.collect { case Occurrence(sp, n, ToBinder(id), _) =>
        r.binders.get(id) match {
          case None => Some(s"${f.getName}:${sp.startLine}: $n -> binder $id absent")
          case Some(b) if b.defSite.startLine < 1 || b.defSite.startLine > lines =>
            Some(s"${f.getName}: binder ${b.spelling} def-site ${b.defSite} outside 1..$lines")
          case Some(b) if b.defSite.startCol < 1 =>
            Some(s"${f.getName}: binder ${b.spelling} def-site column ${b.defSite.startCol}")
          case _ => None
        }
      }.flatten
    }
    val n = corpusTables.map(_._3.occurrences.count(_.resolution.isInstanceOf[ToBinder])).sum
    (bad.isEmpty :| s"${bad.size} bad of $n ToBinder occurrences: ${bad.take(5)}") &&
    ((n > 5000) :| s"anti-vacuity: only $n ToBinder occurrences")
  }

  property("6.3 corpus: no two occurrences overlap") = secure {
    // Half-open, and by the NAME's own extent rather than the token span:
    // `SurfaceParsers.spanned` brackets a `token`, which eats the
    // whitespace after the lexeme, so raw spans run to the next token and
    // a name at the end of a line spans onto the next one.  The LSP edits
    // the NAME, so the edited extents are what must not collide -- and
    // this calls `Definitions.nameExtent`, THE VERY FUNCTION the index
    // uses, rather than re-stating its rule (review R2: the first version
    // re-implemented it inline and was therefore blind to exactly the
    // class of mis-measurement the reviewer found).
    val bad = corpusTables.flatMap { case (f, src, r) =>
      val ls = new Definitions.Lines(src)
      val ext = r.occurrences.map { o =>
        val (len, _) = Definitions.nameExtent(ls, o.span, o.spelling)
        (o.span.startLine, o.span.startCol, o.span.startCol + len, o.spelling)
      }.sortBy(x => (x._1, x._2))
      ext.sliding(2).collect {
        case List(a, b) if a._1 == b._1 && b._2 < a._3 =>
          s"${f.getName}:${a._1}: '${a._4}' [${a._2},${a._3}) overlaps '${b._4}' at ${b._2}"
      }.toList
    }
    bad.isEmpty :| s"${bad.size} overlapping pairs: ${bad.take(5)}"
  }

  property("6.3 corpus: a name's measured extent is the source's own") = secure {
    // The companion to the overlap property, and the one that would have
    // caught R2: for every occurrence, either the source at that position
    // spells the name exactly (`exact`), or it does NOT and rename
    // refuses it.  Report the non-exact ones as a CLASS with counts --
    // they are real (``literal`` names, parenthesised operators) and the
    // point is that they are recognised, not that they are absent.
    val forms = corpusTables.flatMap { case (f, src, r) =>
      val ls = new Definitions.Lines(src)
      r.occurrences.map { o =>
        val (len, exact) = Definitions.nameExtent(ls, o.span, o.spelling)
        val off = ls.offset(o.span.startLine, o.span.startCol)
        val text = if (off < 0) "" else src.substring(off, math.min(off + len, src.length))
        (exact, text, o.spelling, f.getName)
      }
    }
    val inexact = forms.filterNot(_._1)
    val ticked  = inexact.count(_._2.startsWith("``"))
    val parens  = inexact.count(_._2.startsWith("("))
    // behind a TAB the parser's column is not a character index, so the
    // extent is measured but the name is not treated as exact
    val tabbed  = inexact.count(x => x._2 == x._3)
    val other   = inexact.filterNot(x =>
      x._2.startsWith("``") || x._2.startsWith("(") || x._2 == x._3)
    Prop.collect(s"occurrences ${forms.size} | exact ${forms.count(_._1)} | " +
                 s"backticked $ticked | parenthesised $parens | behind a tab $tabbed | " +
                 s"other ${other.size}") {
      ((forms.count(_._1) > 50000) :| s"anti-vacuity: ${forms.count(_._1)} exact") &&
      // every non-exact one is a form we can NAME -- if a new one appears,
      // this is where it shows up rather than in a corrupted rename
      ((other.size == 0) :|
        s"${other.size} occurrences in no form this measurement knows: " +
        s"${other.take(5).map(x => x._4 + " '" + x._3 + "' vs '" + x._2 + "'")}")
    }
  }

  property("6.3 corpus: one binder per def-site position") = secure {
    // The index keys a binder's def-site Occ by (line, column) and keeps
    // ONE entry per position (`Definitions.dedup`), so two binders sharing
    // a def-site would silently lose one -- and a rename would then miss
    // every use of it.
    val bad = corpusTables.flatMap { case (f, _, r) =>
      r.binders.values.groupBy(b => (b.defSite.startLine, b.defSite.startCol))
        .filter(_._2.size > 1)
        .map { case (pos, bs) =>
          s"${f.getName}:$pos shared by ${bs.map(b => b.spelling + "/" + b.kind).mkString(",")}" }
    }
    val n = corpusTables.map(_._3.binders.size).sum
    (bad.isEmpty :| s"${bad.size} shared def-sites of $n binders: ${bad.take(5)}") &&
    ((n > 3000) :| s"anti-vacuity: only $n binders")
  }

  property("6.3 corpus: every moduleTerms id is a TopLevel binder") = secure {
    val bad = corpusTables.flatMap { case (f, _, r) =>
      r.moduleTerms.toList.flatMap { case (spelling, id) =>
        r.binders.get(id) match {
          case None => Some(s"${f.getName}: moduleTerms('$spelling') -> $id absent")
          case Some(b) if b.kind != Renamer.TopLevel =>
            Some(s"${f.getName}: moduleTerms('$spelling') is ${b.kind}")
          case Some(b) if b.spelling != spelling =>
            Some(s"${f.getName}: moduleTerms('$spelling') spells '${b.spelling}'")
          case _ => None
        }
      }
    }
    val n = corpusTables.map(_._3.moduleTerms.size).sum
    (bad.isEmpty :| s"${bad.size} bad of $n moduleTerms entries: ${bad.take(5)}") &&
    ((n > 1000) :| s"anti-vacuity: only $n moduleTerms entries")
  }

  // ----------------------------------------------------------------------
  // 6.4 DOCUMENT SYMBOLS over the same corpus.  `textDocument/documentSymbol`
  // hands the editor a TREE of ranges and the LSP spec requires two things
  // of it -- a symbol's `range` contains its `selectionRange`, and a child
  // sits inside its parent -- which an editor will happily believe and then
  // scroll to nonsense.  `Symbols.build` makes both true by construction;
  // these properties are what says so over 253 real files, and they call
  // `Symbols.containsRng`, the builder's OWN rule, rather than restating it.
  //
  // No session and no types: `build` takes "the type of this spelling" as a
  // function, and `_ => None` is a legitimate check (the editor path passes
  // the check's own types).  Nothing here looks at a detail string.

  private def symKindName(k: Int): String = k match {
    case Symbols.KModule      => "Module"
    case Symbols.KNamespace   => "Namespace"
    case Symbols.KClass       => "Class"
    case Symbols.KMethod      => "Method"
    case Symbols.KProperty    => "Property"
    case Symbols.KField       => "Field"
    case Symbols.KConstructor => "Constructor"
    case Symbols.KEnum        => "Enum"
    case Symbols.KInterface   => "Interface"
    case Symbols.KFunction    => "Function"
    case Symbols.KVariable    => "Variable"
    case Symbols.KObject      => "Object"
    case Symbols.KStruct      => "Struct"
    case other                => "kind" + other
  }

  private lazy val corpusSymbols: List[(File, List[Symbols.Sym])] =
    corpusTrees.map { case (f, src, m) =>
      (f, Symbols.build(m, new Definitions.Lines(src), _ => None)) }

  property("6.4 corpus: a symbol tree for every file, every range well formed") = secure {
    val bad = corpusSymbols.flatMap { case (f, syms) =>
      def go(parent: Option[Symbols.Sym])(s: Symbols.Sym): List[String] = {
        val here =
          (if (s.name.trim.isEmpty) List(s"${f.getName}: an unnamed ${symKindName(s.kind)}") else Nil) :::
          (if (Symbols.containsRng(s.range, s.selection.asRange)) Nil
           else List(s"${f.getName}: '${s.name}' range ${s.range} excludes its selection ${s.selection}")) :::
          (parent.filterNot(p => Symbols.containsRng(p.range, s.range))
             .map(p => s"${f.getName}: '${s.name}' ${s.range} escapes parent '${p.name}' ${p.range}").toList)
        here ::: s.children.flatMap(go(Some(s)))
      }
      syms.flatMap(go(None))
    }
    val all   = corpusSymbols.flatMap(x => Symbols.flatten(x._2))
    val kinds = all.groupBy(_.kind).toList.map { case (k, xs) => symKindName(k) + " " + xs.size }
                   .sorted.mkString(", ")
    Prop.collect(s"files ${corpusSymbols.size} | symbols ${all.size} | $kinds") {
      (bad.isEmpty :| s"${bad.size} malformed symbols: ${bad.take(5)}") &&
      ((corpusSymbols.size >= 150) :| s"only ${corpusSymbols.size} files") &&
      ((all.size > 3000) :| s"anti-vacuity: only ${all.size} symbols")
    }
  }

  property("6.4 corpus: siblings are sorted, and no two of them straddle") = secure {
    // The two properties the review (F1/F3) asked for, and the ones the
    // FIRST version of 6.4 got wrong.  An LSP client that maps a CURSOR to
    // a symbol -- breadcrumbs, sticky scroll, outline follow-cursor --
    // walks a level in order and takes the first range that contains the
    // position, so it needs the level SORTED and it needs no two siblings
    // to partially cover each other.
    //
    // IDENTICAL ranges are a separate, legitimate class and are counted
    // rather than failed: one statement can declare several names
    // (`field fa, fb : Int`, `symBoth, symAlsoBoth : Int`), and each gets
    // its own symbol over the same statement, distinguished by its
    // selectionRange.  A cursor there is genuinely inside both.
    // STRADDLING -- overlapping but not identical -- is the defect, and it
    // must be zero.
    var levels = 0
    var identical = 0
    val bad = corpusSymbols.flatMap { case (f, syms) =>
      def level(where: String, ss: List[Symbols.Sym]): List[String] = {
        levels += 1
        val unsorted = ss.sliding(2).collect {
          case List(a, b) if !Symbols.beforeSym(a, b) =>
            s"${f.getName}: $where '${a.name}' ${a.range} precedes '${b.name}' ${b.range}"
        }.toList
        val straddling = ss.combinations(2).collect {
          case List(a, b) if Symbols.overlaps(a.range, b.range) =>
            if (a.range == b.range) { identical += 1; None }
            else Some(s"${f.getName}: $where '${a.name}' ${a.range} straddles " +
                      s"'${b.name}' ${b.range}")
        }.flatten.toList
        unsorted ::: straddling ::: ss.flatMap(s => level(where + "/" + s.name, s.children))
      }
      level("", syms)
    }
    Prop.collect(s"files ${corpusSymbols.size} | sibling levels $levels | " +
                 s"identical-range pairs $identical | straddling pairs ${bad.size}") {
      (bad.isEmpty :| s"${bad.size} unsorted-or-straddling: ${bad.take(5)}") &&
      ((levels > 200) :| s"anti-vacuity: only $levels levels")
    }
  }

  property("6.4 corpus: term groups are exactly the renamer's moduleTerms") = secure {
    // THE CROSS-CHECK that groups merge correctly: one symbol per top-level
    // term GROUP, and `Renamer.Result.moduleTerms` is one entry per top-level
    // term group.  They must agree file by file -- a sig that failed to merge
    // with its equations, or two equations of one name that split, shows up
    // here as a count that is one too many.  `Symbols.termGroups` is the
    // builder's own answer to "which symbols are groups" -- a `foreign`
    // declaration is a Function to an editor but the renamer never binds
    // it, and a `class` body is its own binding scope -- so this compares
    // two counts rather than restating a rule.
    val pairs = corpusSymbols.zip(corpusTables).map {
      case ((f, syms), (_, _, r)) =>
        (f, Symbols.termGroups(syms).size, r.moduleTerms.size)
    }
    val bad = pairs.filter { case (_, g, mt) => g != mt }
      .map { case (f, g, mt) => s"${f.getName}: $g Function/Variable symbols, $mt moduleTerms" }
    val groups = pairs.map(_._2).sum
    val mts    = pairs.map(_._3).sum
    Prop.collect(s"files ${pairs.size} | term groups $groups | moduleTerms $mts") {
      (bad.isEmpty :| s"${bad.size} files disagree: ${bad.take(5)}") &&
      ((groups > 1000) :| s"anti-vacuity: only $groups groups")
    }
  }

  property("6.4: every statement kind maps to a SymbolKind") = secure {
    // The kinds the FIXTURES cannot reach: `class`, `table` and `database`
    // are essentially unused in the corpus (Eq.e's class is commented out;
    // Syntax/Procedure.e's database lives in a doc comment), so the mapping
    // for them is pinned here, on the parser alone.
    val src =
      "module Pins where\n" +
      "\n" +
      "class SymEq a where\n" +
      "  symEq : a -> a -> Int\n" +
      "  symNe a b = symEq a b\n" +
      "\n" +
      "field pkA, pkB : Int\n" +
      "\n" +
      "database \"somedb\"\n" +
      "  table thing : Int\n"
    SurfaceParsers.module("Pins.e", src, "Pins") match {
      case Left(err) => falsified :| ("the pin source does not parse: " + err)
      case Right(m)  =>
        val syms = Symbols.build(m, new Definitions.Lines(src), _ => None)
        val flat = Symbols.flatten(syms).map(s => (s.name, s.kind))
        val want = List(
          ("SymEq", Symbols.KInterface), ("symEq", Symbols.KMethod),
          ("symNe", Symbols.KMethod),
          ("pkA", Symbols.KField), ("pkB", Symbols.KField),
          ("somedb", Symbols.KNamespace), ("thing", Symbols.KObject))
        val malformed = Symbols.flatten(syms)
          .filterNot(s => Symbols.containsRng(s.range, s.selection.asRange))
        // A class body is its own binding scope, so its members are NOT
        // moduleTerms; `thing` inside the database block IS one.
        val mt = Renamer.rename(m, ModuleScope.Scope.empty).moduleTerms.keySet
        ((flat == want) :| s"symbols were $flat") &&
        (malformed.isEmpty :| s"malformed: ${malformed.map(_.name)}") &&
        ((!mt.contains("symEq") && !mt.contains("symNe")) :|
          s"class members leaked into moduleTerms: $mt")
    }
  }

  // ----------------------------------------------------------------------
  // 6.5 SCOPE AT A POSITION, over the same corpus.  `Renamer.Result.scopeAt`
  // was built at 4.2 and DEFERRED ("to where a consumer exists"); completion
  // is that consumer, and the 4.2 note said the layer was subsumed by the
  // G1Resolution differential.  Subsumed is not the same as pinned: the
  // differential says every REFERENCE resolves the way the fused pipeline
  // resolved it, and says nothing at all about the frame stack `scopeAt`
  // folds.  So this pins it directly, and in the only terms that matter to
  // a completion: AT EVERY REAL OCCURRENCE of a local binder, the name the
  // renamer resolved must be the name `scopeAt` says is visible there --
  // same spelling, same binder id.  A wrong id here is a completion that
  // offers the shadowed binding's type.

  /** A VALUE-level local binder: an argument, a `let`/`where` head, a
    * `do` or `case` binder.  The renamer pushes a FRAME for each of their
    * scopes, which is what `scopeAt` folds.
    *
    * TYPE-level binders (`TyParam`, `TyImplicit`, `KindParam`) are NOT in
    * any frame -- measured, not assumed: 12339 of the corpus's 18982
    * local occurrences are type-level and `scopeAt` sees none of them.
    * So the scope-at-position layer is a VALUE-scope layer, and 6.5's
    * completion offers no type variables at all (the report says so). */
  private def localKind(k: Renamer.BinderKind): Boolean =
    k != Renamer.TopLevel && k != Renamer.TyDef &&
    k != Renamer.TyParam && k != Renamer.TyImplicit && k != Renamer.KindParam

  private def typeLevelKind(k: Renamer.BinderKind): Boolean =
    k == Renamer.TyParam || k == Renamer.TyImplicit || k == Renamer.KindParam

  property("6.5 corpus: scopeAt agrees with resolution at every local occurrence") = secure {
    var checked = 0
    var typeLevel = 0
    corpusTables foreach { case (_, _, r) =>
      r.occurrences foreach {
        case Occurrence(_, _, ToBinder(id), _) =>
          if (r.binders.get(id).exists(b => typeLevelKind(b.kind))) typeLevel += 1
        case _ => ()
      }
    }
    val bad = corpusTables.flatMap { case (f, _, r) =>
      r.occurrences.flatMap {
        case Occurrence(sp, n, ToBinder(id), _) =>
          r.binders.get(id).filter(b => localKind(b.kind)).flatMap { b =>
            checked += 1
            r.scopeAt(sp.startLine, sp.startCol).get(n) match {
              case Some(got) if got == id => None
              case Some(got) =>
                Some(s"${f.getName}:${sp.startLine}:${sp.startCol} $n -> $id " +
                     s"(${b.kind}) but scopeAt says $got " +
                     r.binders.get(got).map(x => "(" + x.kind + " at " + x.defSite.startLine + ")").getOrElse(""))
              case None =>
                Some(s"${f.getName}:${sp.startLine}:${sp.startCol} $n -> $id " +
                     s"(${b.kind}) not visible at all")
            }
          }
        case _ => None
      }
    }
    Prop.collect(s"files ${corpusTables.size} | value-local occurrences $checked " +
                 s"| scopeAt disagreements ${bad.size} " +
                 s"| type-level occurrences $typeLevel (no frames: not offered)") {
      (bad.isEmpty :| s"${bad.size} of $checked disagree: ${bad.take(8)}") &&
      ((checked > 5000) :| s"anti-vacuity: only $checked local occurrences")
    }
  }

  property("6.5 corpus: scopeAt claims no local where the renamer used none") = secure {
    // THE REVERSE DIRECTION (review F-3).  The property above looks only
    // at occurrences that RESOLVED to a value-local binder, so it cannot
    // see a frame that reaches one statement too far -- an over-wide
    // frame shows up as `scopeAt` claiming a local at a position where
    // the renamer used a TOP LEVEL, an import, or nothing at all.  That
    // is exactly the failure mode the do-binder frame fix could have
    // introduced, so it is pinned here rather than left to a reviewer's
    // scratch directory.
    //
    // Type-level occurrences are excluded for the reason the forward
    // property states: `scopeAt` is a value-scope layer and reports none
    // of them, so every one of them would be a trivial pass.
    var checked = 0
    val bad = corpusTables.flatMap { case (f, _, r) =>
      r.occurrences.flatMap { o =>
        val local = o.resolution match {
          case ToBinder(id) => r.binders.get(id).exists(b => localKind(b.kind))
          case _            => false
        }
        val typeLevel = o.resolution match {
          case ToBinder(id) => r.binders.get(id).exists(b => typeLevelKind(b.kind))
          case _            => o.typeLevel
        }
        if (local || typeLevel) None
        else {
          checked += 1
          r.scopeAt(o.span.startLine, o.span.startCol).get(o.spelling).flatMap { id =>
            r.binders.get(id).filter(b => localKind(b.kind)).map { b =>
              s"${f.getName}:${o.span.startLine}:${o.span.startCol} ${o.spelling} " +
              s"resolved to ${o.resolution} but scopeAt offers the ${b.kind} " +
              s"bound at ${b.defSite.startLine}"
            }
          }
        }
      }
    }
    Prop.collect(s"top-level/free value occurrences $checked | false-local ${bad.size}") {
      (bad.isEmpty :| s"${bad.size} of $checked are false locals: ${bad.take(8)}") &&
      ((checked > 20000) :| s"anti-vacuity: only $checked such occurrences")
    }
  }

  property("6.5 corpus: an inner binding wins over an outer one of the same name") = secure {
    // The anti-vacuity clause for the property above: without a SHADOWED
    // name in the corpus, agreement is a statement about a map with no
    // collisions in it.  Count the occurrences whose spelling is bound by
    // more than one frame containing that position -- those are the ones
    // where "innermost wins" is the only thing that can make the two
    // agree.
    var shadowed = 0
    corpusTables foreach { case (_, _, r) =>
      r.occurrences foreach {
        case Occurrence(sp, n, ToBinder(id), _) if r.binders.get(id).exists(b => localKind(b.kind)) =>
          val frames = r.frames.filter(fr => fr.span.contains(sp.startLine, sp.startCol))
          if (frames.count(_.bindings.contains(n)) > 1) shadowed += 1
        case _ => ()
      }
    }
    Prop.collect(s"shadowed value-local occurrences $shadowed") {
      (shadowed >= 20) :| s"anti-vacuity: only $shadowed shadowed occurrences"
    }
  }

  // ----------------------------------------------------------------------
  // 6.5 THE CONTEXT RULES.  Completion reads the CURRENT BUFFER TEXT for
  // the word prefix and for the `import` / qualified / comment / string
  // context, and nothing else; `Completion.contextAt` is that whole rule and
  // these call it rather than restate it.

  property("6.5: the context rules over one line of text") = secure {
    def at(line: String, col: Int) = Completion.contextAt(line, col)
    val cases: List[(String, Int, Completion.Ctx)] = List(
      ("topFn arg = arg && True", 14, Completion.Names("ar")),
      ("topFn arg = arg && True", 11, Completion.Names("")),
      ("import Layout.Scan", 9, Completion.Modules("La")),
      ("import Layout.Scan", 14, Completion.Modules("Layout.")),
      ("export Bool", 9, Completion.Modules("Bo")),
      ("  import Bool", 11, Completion.Modules("Bo")),
      ("import Bool using not", 20, Completion.Names("no")),
      ("x = Bool.no", 11, Completion.Qualified("Bool", "no", 4)),
      ("x = Layout.Report.so", 20, Completion.Qualified("Layout.Report", "so", 4)),
      ("x = Bool.", 9, Completion.Qualified("Bool", "", 4)),
      ("x = rec.fie", 11, Completion.Names("fie")),
      ("x = 1  -- not a name", 18, Completion.Dead),
      ("x = \"not a name\"", 10, Completion.Dead),
      ("x = \"s\" ++ no", 13, Completion.Names("no")),
      ("{- x = no -}", 8, Completion.Dead),
      ("x = 1 <+", 8, Completion.Names("")))
    val bad = cases.filterNot { case (l, c, want) => at(l, c) == want }
    bad.isEmpty :| bad.map { case (l, c, want) =>
      s"[$l] at $c: want $want, got ${at(l, c)}" }.mkString("; ")
  }
}


