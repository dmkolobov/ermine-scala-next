package com.clarifi.reporting

import com.clarifi.reporting.ermine.ConcreteRho
import com.clarifi.reporting.ermine.lsp.QuickFix
import com.clarifi.reporting.ermine.lsp.QuickFix.{ SkipAlias, SkipListed, SkipOpen, SkipOwn, TEdit }
import com.clarifi.reporting.ermine.surface.SurfaceParsers

import org.scalacheck._
import Prop._
import scalaparsers.Loc

/** Stage 3 item 6.6: the two quick-fix EDIT BUILDERS as pure functions.
  *
  * Everything here runs without a session, a check or a server: the
  * import scanner over buffer text, the add-import edit case by case, the
  * top-level group walk over a parsed surface tree, and the signature
  * insertion's placement.  The other half of the item — that an inserted
  * signature parses and re-checks — is measured over the 180-file corpus
  * by the sweep in `TestTolerantCheck` (roadmap Decision (e)), and end to
  * end through the wire by `tracker/tools/lsp-smoke.sh`.
  */
object TestQuickFix extends Properties("Quick fixes 6.6") {

  private def lines(xs: String*): String = xs.mkString("\n") + "\n"
  private def crlf(xs: String*): String = xs.mkString("\r\n") + "\r\n"

  /** A type with no constructors, no fields and no kinds: it renders
    * `(||)` and passes every scope test vacuously, so a property about
    * WHERE a signature goes is not also a property about what is in
    * scope (that half is the corpus sweep's). */
  private val anyTy = ConcreteRho(Loc.builtin)

  private val noScope = Map.empty[com.clarifi.reporting.ermine.Local,
                                  List[com.clarifi.reporting.ermine.Name]]
  private val noOrigins = Map.empty[com.clarifi.reporting.ermine.Global,
                                    List[com.clarifi.reporting.ermine.Global]]

  private def sig(text: String, g: QuickFix.Group) =
    QuickFix.sigEdit(text, g, anyTy, noScope, noScope, noOrigins, noOrigins, "M")

  // ------------------------------------------------------- the import scanner

  property("the scanner reads a module, an alias and a using list") = secure {
    val t = lines("module M where", "",
                  "import Bool", "import Maybe as Mb", "import Ord using {type Ord; fromLess}",
                  "import List hiding cons_Bracket; empty_Bracket", "", "f = 1")
    val is = QuickFix.imports(t)
    ((is.map(_.module) == List("Bool", "Maybe", "Ord", "List")) :| is.map(_.module).toString) &&
    ((is(1).alias == Some("Mb")) :| is(1).alias.toString) &&
    ((is(2).isUsing == Some(true) && is(2).braced) :| is(2).toString) &&
    ((is(2).items.map(x => (x.name, x.isType)) == List(("Ord", true), ("fromLess", false))) :|
       is(2).items.toString) &&
    ((is(3).isUsing == Some(false)) :| is(3).toString) &&
    ((is(3).items.map(_.name) == List("cons_Bracket", "empty_Bracket")) :| is(3).items.toString)
  }

  property("a laid-out list continues onto the following lines") = secure {
    // `core/src/main/resources/modules/Layout/Report/Keyed/OptionTypes.e`
    // writes exactly this shape.
    val t = lines("module M where", "import Layout.Report using",
                  "  type Report; type DisplayScale", "", "f = 1")
    val is = QuickFix.imports(t)
    ((is.size == 1) :| is.toString) &&
    ((is.head.lastLine == 2) :| is.head.lastLine.toString) &&
    ((is.head.items.map(_.name) == List("Report", "DisplayScale")) :| is.head.items.toString) &&
    ((is.head.items.forall(_.isType)) :| is.head.items.toString)
  }

  property("a `{- -}` block hides its imports (Layout/Scan.e:84)") = secure {
    val t = lines("module M where", "import Bool", "{-", "import Maybe as P", "-}", "f = 1")
    val is = QuickFix.imports(t)
    ((is.map(_.module) == List("Bool")) :| is.map(_.module).toString) &&
    // ... and a `--` comment likewise
    ((QuickFix.imports(lines("module M where", "-- import Maybe", "f = 1")).isEmpty) :| "line comment")
  }

  property("an operator item is read WITHOUT its parentheses") = secure {
    // The spelling an undefined-term note carries is the bare one, so the
    // list membership test has to compare against that.
    val is = QuickFix.imports(lines("module M where", "import R using (++) ; type NonEmpty", "f = 1"))
    (is.head.items.map(x => (x.name, x.isType)) == List(("++", false), ("NonEmpty", true))) :|
      is.head.items.toString
  }

  property("`x as y` provides y, not x") = secure {
    val is = QuickFix.imports(lines("module M where", "import List using map_List as map", "f = 1"))
    (is.head.items.map(x => (x.name, x.provides)) == List(("map_List", "map"))) :| is.head.items.toString
  }

  // ---------------------------------------------------------- the ADD IMPORT edit

  property("no imports: the line goes after the module header") = secure {
    val t = lines("module M where", "", "f = not True")
    QuickFix.addImport(t, "M", "Bool", "not", com.clarifi.reporting.ermine.Idfix) match {
      case Right((_, List(e))) =>
        (e == TEdit(1, 0, 1, 0, "import Bool using not\n")) :| e.toString
      case x => false :| x.toString
    }
  }

  property("with imports: the line goes after the LAST one") = secure {
    val t = lines("module M where", "import Maybe", "import Ord using fromLess", "", "f = not True")
    QuickFix.addImport(t, "M", "Bool", "not", com.clarifi.reporting.ermine.Idfix) match {
      case Right((_, List(e))) =>
        (e == TEdit(3, 0, 3, 0, "import Bool using not\n")) :| e.toString
      case x => false :| x.toString
    }
  }

  property("a CRLF buffer gets a CRLF line") = secure {
    val t = crlf("module M where", "import Maybe", "", "f = not True")
    QuickFix.addImport(t, "M", "Bool", "not", com.clarifi.reporting.ermine.Idfix) match {
      case Right((_, List(e))) =>
        ((e.newText == "import Bool using not\r\n") :| e.newText.replace("\r", "\\r")) &&
        ((e.sl == 2) :| e.toString)
      case x => false :| x.toString
    }
  }

  property("an existing `using` list grows by `; name` (the 6.5 gap)") = secure {
    val t = lines("module M where", "import Maybe using isJust", "", "f = isNothing")
    val braced = lines("module M where", "import Maybe using { isJust; maybe }", "", "f = isNothing")
    val laid = lines("module M where", "import Maybe using", "  isJust", "", "f = isNothing")
    def one(s: String) = QuickFix.addImport(s, "M", "Maybe", "isNothing",
                                            com.clarifi.reporting.ermine.Idfix)
    ((one(t) match {
      case Right((_, List(e))) => (e == TEdit(1, 25, 1, 25, "; isNothing")) :| e.toString
      case x => false :| x.toString
    })) &&
    // inside the braces, right after the last item -- `{ isJust; maybe; isNothing }`
    ((one(braced) match {
      case Right((_, List(e))) => (e == TEdit(1, 34, 1, 34, "; isNothing")) :| e.toString
      case x => false :| x.toString
    })) &&
    ((one(laid) match {
      case Right((_, List(e))) => (e == TEdit(2, 8, 2, 8, "; isNothing")) :| e.toString
      case x => false :| x.toString
    }))
  }

  property("`hiding` the name: the fix REMOVES it from the list") = secure {
    val only  = lines("module M where", "import Function hiding id", "", "f = id")
    val first = lines("module M where", "import Function hiding id; flip", "", "f = id")
    val later = lines("module M where", "import Function hiding flip; id", "", "f = id")
    def one(s: String) = QuickFix.addImport(s, "M", "Function", "id",
                                            com.clarifi.reporting.ermine.Idfix)
    // the ONLY hidden name: the whole `hiding` clause goes, leaving `import Function`
    ((one(only) match {
      case Right((_, List(e))) => (e == TEdit(1, 15, 1, 25, "")) :| e.toString
      case x => false :| x.toString
    })) &&
    // the FIRST of several: delete up to the next item's start
    ((one(first) match {
      case Right((_, List(e))) => (e == TEdit(1, 23, 1, 27, "")) :| e.toString
      case x => false :| x.toString
    })) &&
    // a LATER one: delete back to the previous item's end
    ((one(later) match {
      case Right((_, List(e))) => (e == TEdit(1, 27, 1, 31, "")) :| e.toString
      case x => false :| x.toString
    }))
  }

  property("the refusals: own module, open import, alias, already listed") = secure {
    def one(s: String, m: String, n: String) =
      QuickFix.addImport(s, "M", m, n, com.clarifi.reporting.ermine.Idfix)
    val open  = lines("module M where", "import Bool", "", "f = not")
    val alias = lines("module M where", "import Bool as B", "", "f = not")
    val has   = lines("module M where", "import Maybe using isJust", "", "f = isJust")
    val hides = lines("module M where", "import Maybe hiding maybe", "", "f = isJust")
    ((one(open, "M", "x") == Left(SkipOwn("M"))) :| one(open, "M", "x").toString) &&
    ((one(open, "Bool", "not") == Left(SkipOpen("Bool"))) :| one(open, "Bool", "not").toString) &&
    ((one(alias, "Bool", "not") == Left(SkipAlias("Bool", "B"))) :| one(alias, "Bool", "not").toString) &&
    ((one(has, "Maybe", "isJust") == Left(SkipListed("Maybe"))) :| one(has, "Maybe", "isJust").toString) &&
    ((one(hides, "Maybe", "isJust") == Left(SkipListed("Maybe"))) :| one(hides, "Maybe", "isJust").toString)
  }

  // ----------------------------------------------------- the top-level groups

  private def parse(text: String) =
    SurfaceParsers.module("T.e", text, "T").fold(e => sys.error(e.toString), identity)

  property("groups: a sig is found, a private block is top level, a class body is not") = secure {
    val t = lines("module T where",
                  "answer = 42",
                  "signed : Int",
                  "signed = 7",
                  "private",
                  "  hidden = 1",
                  "(<+>) a b = a",
                  "")
    val gs = QuickFix.groups(parse(t))
    val by = gs.map(g => g.spelling -> g).toMap
    ((by.keySet == Set("answer", "signed", "hidden", "<+>")) :| by.keySet.toString) &&
    ((!by("answer").hasSig && by("signed").hasSig) :| gs.toString) &&
    ((by("hidden").eqLine == 6) :| by("hidden").toString) &&
    // the head is written from the FORM the source used, so an operator
    // comes back parenthesised and not as a bare spelling
    ((by("<+>").head == "(<+>)") :| by("<+>").head)
  }

  // ------------------------------------------------------- the SIGNATURE edit

  property("the signature goes above the first equation, at its indentation") = secure {
    val t = lines("module T where", "answer = 42", "private", "  hidden = 1", "")
    val gs = QuickFix.groups(parse(t)).map(g => g.spelling -> g).toMap
    ((sig(t, gs("answer")) match {
      case Right((txt, e)) =>
        ((txt == "answer : (||)") :| txt) && ((e == TEdit(1, 0, 1, 0, "answer : (||)\n")) :| e.toString)
      case x => false :| x.toString
    })) &&
    // inside a `private` block the sig is indented with its equation, so
    // it stays in the block
    ((sig(t, gs("hidden")) match {
      case Right((txt, e)) =>
        ((txt == "  hidden : (||)") :| txt) && ((e.sl == 3 && e.sc == 0) :| e.toString)
      case x => false :| x.toString
    }))
  }

  property("an operator group takes the `(op) : …` form") = secure {
    val t = lines("module T where", "(<+>) a b = a", "")
    val g = QuickFix.groups(parse(t)).head
    sig(t, g) match {
      case Right((txt, _)) => (txt == "(<+>) : (||)") :| txt
      case x => false :| x.toString
    }
  }

  property("a CRLF buffer gets a CRLF signature line") = secure {
    val t = crlf("module T where", "answer = 42", "")
    val g = QuickFix.groups(parse(t)).head
    sig(t, g) match {
      case Right((_, e)) => (e.newText == "answer : (||)\r\n") :| e.newText.replace("\r", "\\r")
      case x => false :| x.toString
    }
  }

  property("a group that already has a signature is refused") = secure {
    val t = lines("module T where", "answer : Int", "answer = 42", "")
    val g = QuickFix.groups(parse(t)).head
    (sig(t, g) == Left(QuickFix.HasSig)) :| sig(t, g).toString
  }

  property("an equation that does not start its line is refused") = secure {
    // `a = 1; b = 2` puts `b`'s equation mid-line, so there is no
    // indentation to copy and no line to insert above.
    val t = lines("module T where", "a = 1; b = 2", "")
    val gs = QuickFix.groups(parse(t)).map(g => g.spelling -> g).toMap
    (gs.get("b").map(g => sig(t, g)) == Some(Left(QuickFix.NotLineStart))) :|
      gs.get("b").map(g => sig(t, g)).toString
  }

  // ------------------------------------------------------------- line endings

  property("eolOf reads the buffer's own terminator") = secure {
    ((QuickFix.eolOf("a\r\nb\r\n") == "\r\n") :| "crlf") &&
    ((QuickFix.eolOf("a\nb\n") == "\n") :| "lf") &&
    ((QuickFix.eolOf("no terminator") == "\n") :| "none")
  }
}
