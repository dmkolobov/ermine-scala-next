package com.clarifi.reporting.ermine.surface

import com.clarifi.reporting.ermine.{ Fixity, Idfix, InfixL, InfixN, InfixR, Postfix, Prefix }
import scalaparsers.{ Err, Pos, Supply }
import scalaparsers.Diagnostic.fail

/** The resolution-free parser, slice one (tracker/LSP-ROADMAP.md 2.3a):
  * module header, fixity statements, and lexically-split statement
  * structure onto the surface AST.  Instantiates the SAME generic
  * scalaparsers layout machinery as the fused pipeline — over Unit
  * state, so there is nowhere for name maps to hide.
  *
  * Terms/patterns arrive at 2.3b, types and the remaining statement
  * grammars at 2.3c; until then non-fixity statements are captured as
  * SErrorStatement placeholders with their KIND and exact extent — the
  * splitter (rawStatement) is the per-character offside rule, and is
  * also Stage 2's skip-to-layout-boundary recovery primitive.
  *
  * Span ends currently point at the position after the token's trailing
  * whitespace (the generic token() consumes it before we can look);
  * tightening span ends is 2.3b polish.
  */
object SurfaceParsers extends scalaparsers.Parsing[Unit] {

  // ---------------------------------------------------------------- tokens
  // State-free copies of parsing/package.scala's token layer.

  val keywords: Set[String] =
    Set("subtype") ++
    Set("exists", "constructor", "do", "forall", "phi", "φ", "prj#", "rho", "ρ",
        "constraint", "Γ", "table", "where", "infixr", "infixl", "infix",
        "postfix", "prefix", "case", "let", "in", "of", "esac", "hole", "Eval") ++
    Set("private", "abstract", "field", "data", "foreign", "type", "import",
        "export", "database", "class", "instance")

  def keyword(s: String): Parser[Unit] =
    token((letter >> identTail).slice.filter(_ == s).skip.attempt(s))

  def identTok: Parser[String] =
    token(((setBol(false) >> letter >> identTail).slice).filter(!keywords(_)).attempt("identifier"))

  def moduleNameTok: Parser[String] =
    token((((upper >> identTail).slice).sepBy1(rawCh('.')).map(_.toList.mkString("."))).attempt("module name"))

  /** One operator token, validated by the parity-proven Lexer. */
  def opTok: Parser[String] =
    token(((setBol(false) >>
      satisfy(Lexer.isOpChar) >>
      rawSatisfy(c => Lexer.isOpChar(c) || c == '_' || Lexer.isTailChar(c)).skipMany).slice)
      .flatMap { s =>
        Lexer.op(s, 0) match {
          case Some(l) if l.end == s.length => unit(s)
          case _                            => fail("operator")
        }
      }.attempt("operator"))

  def spanned[A](p: Parser[A]): Parser[(A, Span)] = for {
    p1 <- loc
    a  <- p
    p2 <- loc
  } yield (a, Span(p1.line, p1.column, p2.line, p2.column))

  private def span2(p1: Pos, p2: Pos) = Span(p1.line, p1.column, p2.line, p2.column)

  // ---------------------------------------------------------------- header

  def importItem: Parser[SImportItem] = for {
    isTy <- keyword("type").optional map (_.isDefined)
    n    <- spanned(identTok | paren(opTok).map("(" + _ + ")"))
    ren  <- (keyword("as") >> spanned(identTok | paren(opTok).map("(" + _ + ")"))).optional
  } yield SImportItem(
    SName(n._1, Plain, Idfix, n._2), isTy,
    ren map (r => SName(r._1, Plain, Idfix, r._2)))

  def importStatement: Parser[SImport] = for {
    p1     <- loc
    isExp  <- keyword("import").as(false) | keyword("export").as(true)
    mod    <- spanned(moduleNameTok)
    as     <- (keyword("as") >> spanned(identTok)).optional
    items  <- (for {
                 isUsing <- keyword("using").as(true) | keyword("hiding").as(false)
                 xs <- laidout("explicit imports", importItem)
               } yield (isUsing, xs)).optional
    p2     <- loc
  } yield SImport(Real(span2(p1, p2)), isExp, mod._1, mod._2,
                  as map (a => SName(a._1, Plain, Idfix, a._2)), items)

  def header(defaultName: String): Parser[SHeader] = for {
    _    <- whiteSpace(false, false)
    p1   <- loc
    nm   <- (keyword("module") >> spanned(moduleNameTok) << keyword("where")).map(x => (x._1, Some(x._2)))
              .scope("module header") orElse ((defaultName, None))
    expl <- leftBrace.as(true) | (semi | eof).as(false)
    imps <- importStatement.sepEndBy(if (expl) token(';') else semi) scope "import statements"
    p2   <- loc
  } yield SHeader(Real(span2(p1, p2)), nm._1, nm._2, expl, imps)

  // ------------------------------------------------------------ statements

  def fixityStatement: Parser[SStatement] = (for {
    p1  <- loc
    mk  <- (keyword("infixl") as ((n: Int) => InfixL(n))) |
           (keyword("infixr") as ((n: Int) => InfixR(n))) |
           (keyword("infix")  as ((n: Int) => InfixN(n))) |
           (keyword("prefix") as ((n: Int) => Prefix(n))) |
           (keyword("postfix") as ((n: Int) => Postfix(n)))
    tyLv <- keyword("type").optional map (_.isDefined)
    n    <- token(digit.skipSome.slice.map(_.toInt).filter(_ <= 10).attempt("precedence"))
    ops  <- spanned(opTok).some
    p2   <- loc
  } yield SFixity(Real(span2(p1, p2)), mk(n), tyLv,
                  ops.toList.map(o => SName(o._1, Plain, mk(n), o._2)))).attempt("fixity statement")

  /** One raw character of a statement: newlines re-arm the offside check;
    * other characters require being onside.  Nested (deeper-indented)
    * lines stay onside, so this consumes exactly one top-level
    * statement's extent — the skip-to-layout-boundary primitive. */
  private def rawStatementChar: Parser[Any] =
    (rawNewline << setBol(true)) |
    rawSatisfy(c => c == ' ' || c == '\t' || c == '\r') |  // whitespace never decides offside
    (stillOnside >> rawSatisfy(_ != '\n') << setBol(false))

  private val stmtKinds =
    List("field", "table", "type", "data", "class", "foreign", "private",
         "database", "import", "export")

  /** 2.3b/2.3c placeholder: capture the statement's exact extent and its
    * kind; the message format is load-bearing for TestSurfaceParsers. */
  def rawStatement: Parser[SStatement] = for {
    p1   <- loc
    text <- rawStatementChar.skipSome.slice
    p2   <- loc
    _    <- optionalSpace.skipOptional
  } yield {
    val head = text.trim.takeWhile(c => c.isLetter || c == '#')
    val kind = if (stmtKinds contains head) head else "binding"
    SErrorStatement(Real(span2(p1, p2)), s"unparsed:$kind")
  }

  def statement: Parser[SStatement] = fixityStatement | rawStatement

  def module(fileName: String, contents: String, defaultName: String = "Surface"): Either[Err, SModule] = {
    val p = for {
      h  <- header(defaultName)
      ss <- if (h.explicitLayout)
              // no stdlib witness; real support arrives with 2.3b
              unit(List(SErrorStatement(h.loc, "unparsed:explicit-layout-module")))
            else laidout("statement", statement)
      _  <- eof
    } yield SModule(fileName, h, ss)
    val ps = scalaparsers.ParseState.mk(fileName, contents, ())
    p.run(ps, Supply.create.split) match {
      case Left(err)      => Left(err)
      case Right((_, m))  => Right(m)
    }
  }
}
