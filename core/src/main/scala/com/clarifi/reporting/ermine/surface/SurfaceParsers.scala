package com.clarifi.reporting.ermine.surface

import com.clarifi.reporting.ermine.{ Fixity, Idfix, InfixL, InfixN, InfixR, Postfix, Prefix }
import scalaparsers.{ ++, Err, Pos, Supply }
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

  /** ``literal ident`` — anything between double backticks; spelling
    * kept as written, backticks included (renamer strips). */
  def literalIdentTok: Parser[String] =
    // the SPELLING is the middle with escapes processed (NameParsers
    // yields Local(i.mkString) — no backticks)
    token((for {
      _ <- rawWord("``")
      i <- ((rawSatisfy(c => c != '`' && c != '\\') | (rawCh('\\') >> rawSatisfy(_ => true))).skipMany).slice
      _ <- rawWord("``")
    } yield i.replaceAll("(?s)\\\\(.)", "$1")).attempt("literal identifier"))

  def identTok: Parser[String] =
    token(((setBol(false) >> letter >> identTail).slice).filter(!keywords(_)).attempt("identifier"))

  def moduleNameTok: Parser[String] =
    token((((upper >> identTail).slice).sepBy1(rawCh('.')).map(_.toList.mkString("."))).attempt("module name"))

  /** One operator token, validated by the parity-proven Lexer. */
  def opTok: Parser[String] =
    token(((setBol(false) >>
      satisfy(Lexer.isOpChar) >> rawSatisfy(Lexer.isOpChar).skipMany >>
      (rawCh('_') >> rawSatisfy(Lexer.isTailChar).skipSome).skipOptional).slice)
      .flatMap { s =>
        Lexer.op(s, 0) match {
          // the '|'-before-']' guard needs the REAL next input char — the
          // slice can't see it, so re-check against the stream
          case Some(l) if l.end == s.length =>
            if (s == "|") notFollowedBy(rawSatisfy(_ == ']')) as s else unit(s)
          case _ => fail("operator")
        }
      }.attempt("operator"))

  def keyOp(s: String): Parser[Unit] =
    token(satisfy(Lexer.isOpChar).skipSome.slice.filter(_ == s).skip.attempt("'" + s + "'"))

  def comma: Parser[Char] = token(ch(','))
  def ellipsis: Parser[Unit] =
    token(satisfy(Lexer.isOpChar).skipSome.slice.filter(_ == "..").skip.attempt("'..'"))
  def doubleArrowTok: Parser[Unit] = keyOp("=>")

  def rawKeyword(s: String): Parser[Unit] =
    (stillOnside >> rawLetter >> rawIdentTail).slice.filter(_ == s).skip.attempt("raw " + s)
  def leftLet: Parser[Unit]  = left(keyword("let"), "let", rawKeyword("in"), "in")
  def leftCase: Parser[Unit] = left(keyword("case"), "case", rawKeyword("of"), "of")

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

  // ------------------------------------------------------------ raw types
  // Types arrive at 2.3c; until then annotations capture their exact
  // extent: consume while onside, tracking bracket depth; stop at a
  // top-level ',' or a closing bracket of the ENCLOSING construct.  In
  // pattern-sig mode also stop at top-level '->' (case-alt arrows; arrow
  // types in pattern sigs need parens, as in the fused grammar).

  private def rawTypeText(stopArrow: Boolean): Parser[STy] = for {
    p1 <- loc
    text <- new Parser[String] {
      def apply(s: ParseState, sup: Supply) = {
        val in = s.input; val n = in.length
        var i = s.offset; var depth = 0; var stop = false
        while (!stop && i < n) {
          val c = in.charAt(i)
          if (stopArrow && depth == 0 && c == '-' && i + 1 < n && in.charAt(i + 1) == '>') stop = true
          else if (c == '-' && i + 1 < n && in.charAt(i + 1) == '-') {
            while (i < n && in.charAt(i) != '\n') i += 1  // line comment
          }
          else if (c == '"') {
            i += 1
            while (i < n && in.charAt(i) != '"') { if (in.charAt(i) == '\\') i += 1; i += 1 }
            if (i < n) i += 1  // closing quote
          }
          else if (c == '(' || c == '[' || c == '{') { depth += 1; i += 1 }
          else if (c == ')' || c == ']' || c == '}') { if (depth == 0) stop = true else { depth -= 1; i += 1 } }
          else if (c == ',' && depth == 0) stop = true
          else if (c == '\n') {
            var j = i + 1
            while (j < n && (in.charAt(j) == ' ' || in.charAt(j) == '\t' || in.charAt(j) == '\r')) j += 1
            if (j >= n || in.charAt(j) == '\n') { i = j }
            else {
              val col = j - (in.lastIndexOf('\n', j - 1) + 1) + 1
              if (col <= s.depth) stop = true else i = j
            }
          }
          else i += 1
        }
        val text = in.substring(s.offset, i)
        if (text.trim.isEmpty) scalaz.Trampoline.done(scalaparsers.Fail(None, List(), Set("type text")))
        else {
          val consumed = i - s.offset
          var line = s.loc.line; var lastNl = -1
          var k = 0
          while (k < consumed) { if (text.charAt(k) == '\n') { line += 1; lastNl = k }; k += 1 }
          val col = if (lastNl < 0) s.loc.column + consumed else consumed - lastNl
          scalaz.Trampoline.done(scalaparsers.Commit(s.copy(offset = i, loc = s.loc.copy(line = line, column = col), bol = false), text, Set()))
        }
      }
    }
    p2 <- loc
    _  <- optionalSpace.skipOptional
  } yield STyError(Real(span2(p1, p2)), "unparsed:type:" + text.trim)

  // ---------------------------------------------------------------- names

  private def precTok: Parser[Int] = token(digit.skipSome.slice.map(_.toInt))

  /** A binder-position name: ident, (op), (prefix op), (postfix op), or
    * the (infixl 5 op) declaring form (NameParsers.bindingName). */
  def defName: Parser[SName] =
    (spanned(identTok) | spanned(literalIdentTok)).map(n => SName(n._1, Plain, Idfix, n._2)) |
    token(spanned(paren(
      (keyword("prefix") >> precTok.optional ++ spanned(opTok))
        .map { case n ++ o => SName(o._1, n.map(p => ParenFixityBinder(Prefix(p)): NameForm).getOrElse(ParenPrefixOp), Idfix, o._2) } |
      (keyword("postfix") >> precTok.optional ++ spanned(opTok))
        .map { case n ++ o => SName(o._1, n.map(p => ParenFixityBinder(Postfix(p)): NameForm).getOrElse(ParenPostfixOp), Idfix, o._2) } |
      (keyword("infixl") >> precTok ++ spanned(opTok))
        .map { case n ++ o => SName(o._1, ParenFixityBinder(InfixL(n)), Idfix, o._2) } |
      (keyword("infixr") >> precTok ++ spanned(opTok))
        .map { case n ++ o => SName(o._1, ParenFixityBinder(InfixR(n)), Idfix, o._2) } |
      (keyword("infix") >> precTok ++ spanned(opTok))
        .map { case n ++ o => SName(o._1, ParenFixityBinder(InfixN(n)), Idfix, o._2) } |
      spanned(opTok).map(o => SName(o._1, ParenOp, Idfix, o._2))
      // the fused loc for a (op) form is taken at the OPEN PAREN
    )).map { case (n, sp) => n.copy(span = sp) }.attempt("binder name"))

  def refName: Parser[SName] =
    spanned(identTok).map(n => SName(n._1, Plain, Idfix, n._2)) |
    token(spanned(paren(spanned(opTok))).map { case (o, sp) => SName(o._1, ParenOp, Idfix, sp) }.attempt("(operator)"))

  // ------------------------------------------------------------- patterns

  private def underscoreTok: Parser[Span] =
    spanned(token((rawCh('_') << rawSatisfy(Lexer.isTailChar).not).attempt("wildcard"))).map(_._2)

  private def moduleQualCon: Parser[String] =
    token(((upper >> identTail).slice.sepBy1(rawCh('.')).map(_.toList.mkString("."))).attempt("constructor"))

  private def conOpTok: Parser[String] =
    token(((setBol(false) >> satisfy(c => c == ':') >> rawSatisfy(Lexer.isOpChar).skipMany >>
      (rawCh('_') >> rawSatisfy(Lexer.isTailChar).skipSome).skipOptional).slice)
      .flatMap { s =>
        Lexer.op(s, 0, Lexer.ConOp) match {
          case Some(l) if l.end == s.length => unit(s)
          case _                            => fail("constructor operator")
        }
      }.attempt("constructor operator"))

  private def litPattern: Parser[SPat] = literalTerm map {
    case SLitInt(l, v)    => SPLitInt(l, v)
    case SLitLong(l, v)   => SPLitLong(l, v)
    case SLitByte(l, v)   => SPLitByte(l, v)
    case SLitShort(l, v)  => SPLitShort(l, v)
    case SLitString(l, v) => SPLitString(l, v)
    case SLitChar(l, v)   => SPLitChar(l, v)
    case SLitFloat(l, v)  => SPLitFloat(l, v)
    case SLitDouble(l, v) => SPLitDouble(l, v)
    case SLitDate(l, v)   => SPLitDate(l, v)
    case other            => SPError(other.loc, "non-literal in literal pattern")
  }

  private def asPattern: Parser[SPat] = for {
    v  <- spanned(identTok)
    at <- (keyOp("@") >> patternL0).optional
  } yield at match {
    case None    => SPVar(SName(v._1, Plain, Idfix, v._2))
    case Some(p) => SPAs(Real(v._2 to p.loc.span), SName(v._1, Plain, Idfix, v._2), p)
  }

  private def productPattern: Parser[SPat] = spanned(paren(patternCtx(stopArrow = false) sepBy comma)) map { s =>
    s._1 match {
      case List(one) => SPParen(Real(s._2), one)
      case xs        => SPTuple(Real(s._2), xs)
    }
  }

  private def listPattern: Parser[SPat] =
    spanned(bracket(pattern sepBy comma)).map(s => SPList(Real(s._2), s._1))

  def patternL0: Parser[SPat] = (
    underscoreTok.map(s => SPWildcard(Real(s))) |
    litPattern |
    listPattern |
    spanned(moduleQualCon).map(n => SPApp(SName(n._1, Plain, Idfix, n._2), Nil)) |
    asPattern.attempt |
    productPattern |
    (spanned(keyOp("~")) ++ patternL0).map { case s ++ p => SPLazy(Real(s._2 to p.loc.span), p) } |
    (spanned(keyOp("!")) ++ patternL0).map { case s ++ p => SPStrict(Real(s._2 to p.loc.span), p) }
  ) scope "pattern atom"

  def patternL1: Parser[SPat] = (for {
    con <- spanned(moduleQualCon)
    xs  <- patternL0.some
  } yield SPApp(SName(con._1, Plain, Idfix, con._2), xs.toList)).attempt | patternL0

  /** Flat pattern chain (':'-lexeme constructor operators only).  The
    * arrow-stop only applies OUTSIDE parens: a parenthesized pattern sig
    * takes arrows greedily (its ')' bounds it), while case-alt position
    * must stop at '->'. */
  def pattern: Parser[SPat] = patternCtx(stopArrow = true)

  def patternCtx(stopArrow: Boolean): Parser[SPat] = for {
    p1    <- loc
    first <- patternL1
    rest  <- (spanned(conOpTok) ++ patternL1).many
    sig   <- (keyOp(":") >> annotTy).optional
    p2    <- loc
  } yield {
    val base =
      if (rest.isEmpty) first
      else SPChain(Chain(Real(span2(p1, p2)),
        Left(first) :: rest.toList.flatMap { case o ++ p =>
          List(Right(OpOcc(SName(o._1, Plain, Idfix, o._2), PostOperandPos)), Left(p)) }))
    sig match {
      case None    => base
      case Some(t) => SPSig(Real(span2(p1, p2)), base, t)
    }
  }

  // ---------------------------------------------------------------- terms

  def literalTerm: Parser[STerm] = spanned(
    stringLiteral.map(v => (s: Span) => SLitString(Real(s), v): STerm) |
    token(doubleLiteral_.flatMap(d =>
      satisfy(c => c == 'F' || c == 'f').as((s: Span) => SLitFloat(Real(s), d.toFloat): STerm)
        .orElse((s: Span) => SLitDouble(Real(s), d): STerm))) |
    token(nat_.flatMap(n =>
      satisfy(c => c == 'L' || c == 'l').as((s: Span) => SLitLong(Real(s), n): STerm) |
      satisfy(c => c == 'B' || c == 'b').as((s: Span) => SLitByte(Real(s), n.toByte): STerm) |
      satisfy(c => c == 'S' || c == 's').as((s: Span) => SLitShort(Real(s), n.toShort): STerm)
        .orElse((s: Span) => SLitInt(Real(s), n.toInt): STerm))) |
    charLiteral.map(v => (s: Span) => SLitChar(Real(s), v): STerm) |
    dateLiteral.map(v => (s: Span) => SLitDate(Real(s), v): STerm)
  ).map(x => x._1(x._2)).attempt("literal")

  private def suffixOpt: Parser[Option[String]] = (rawCh('_') >> identTail).slice.optional

  def listLit: Parser[STerm] = for {
    s   <- spanned(bracket(term sepBy comma))
    suf <- suffixOpt
  } yield SListLit(Real(s._2), s._1, suf.map(_.stripPrefix("_")))

  def recOrBrace: Parser[STerm] = (for {
    s <- spanned(brace(((refName << keyOp("=")).attempt ++ term) sepBy1 comma))
  } yield SRecordLit(Real(s._2), s._1.map(f => (SVar(f._1): STerm, f._2)))).attempt |
  (for {
    s   <- spanned(brace(term sepBy comma))
    suf <- suffixOpt
  } yield SBraceLit(Real(s._2), s._1, suf.map(_.stripPrefix("_"))))

  private def relArrowP: Parser[SRelArrow] =
    (for { to <- (refName << keyOp("<-")).attempt; from <- refName }
       yield SRenameArrow(Real(to.span to from.span), to, from): SRelArrow) |
    (for { as <- (refName << keyOp("=")).attempt; e <- term }
       yield SCombineArrow(Real(as.span to e.loc.span), as, e): SRelArrow) |
    term.map(SFilterArrow.apply)

  def relEnvelope: Parser[STerm] = spanned(envelope(relArrowP sepBy1 comma))
    .map(s => SRelEnvelope(Real(s._2), s._1)) scope "relation transformer"

  def holeTerm: Parser[STerm] = underscoreTok.map(s => SHole(Real(s)))

  def rememberTerm: Parser[STerm] = for {
    s <- spanned(word("?") flatMap (_ => bracket(term)))
  } yield SRemember(Real(s._2), s._1)

  def productTerm: Parser[STerm] = spanned(paren(term sepBy comma)) map { s =>
    s._1 match {
      case List(one) => SParen(Real(s._2), one)
      case xs        => STuple(Real(s._2), xs)
    }
  }

  def productSection: Parser[STerm] =
    spanned(paren(comma.many).attempt).map(s => STupleSection(Real(s._2), if (s._1.isEmpty) 0 else s._1.length + 1))

  def varTerm: Parser[STerm] =
    (spanned(identTok) | spanned(literalIdentTok) | spanned(moduleQualCon))
      .map(n => SVar(SName(n._1, Plain, Idfix, n._2)))

  def parenOpRef: Parser[STerm] =
    token(spanned(paren(spanned(opTok))).map { case (o, sp) => SVar(SName(o._1, ParenOp, Idfix, sp)): STerm }.attempt("(operator)"))

  def termL0: Parser[STerm] = (
    holeTerm       |
    rememberTerm   |
    literalTerm    |
    relEnvelope    |
    listLit        |
    productSection |
    varTerm        |
    parenOpRef     |
    productTerm    |
    recOrBrace
  ) scope "term atom"

  def termL0s: Parser[STerm] = termL0.some.map(_.toList.reduceLeft(SApp.apply))

  def caseAltP: Parser[SAlt] = for {
    p1 <- loc
    p  <- pattern << keyOp("->")
    t  <- term
    p2 <- loc
  } yield SAlt(Real(span2(p1, p2)), p, t, None)

  def caseTerm: Parser[STerm] = for {
    p1   <- loc
    _    <- leftCase
    tm   <- term << right
    alts <- laidout("case alternative", caseAltP)
    p2   <- loc
  } yield SCase(Real(span2(p1, p2)), tm, alts)

  def letTerm: Parser[STerm] = for {
    p1   <- loc
    _    <- leftLet
    bs   <- laidout("let binding", bindingStatement)
    _    <- right
    body <- term
    p2   <- loc
  } yield SLet(Real(span2(p1, p2)), bs, body)

  private def doBindingP: Parser[SDoStmt] =
    (for {
      p  <- pattern
      ar <- spanned(keyOp("<-"))
      t  <- term
    } yield SDoBind(Real(p.loc.span to t.loc.span), p, ar._2, t): SDoStmt).attempt |
    term.map(SDoExpr.apply)

  def doTerm: Parser[STerm] = for {
    p1  <- loc
    _   <- keyword("do")
    dbs <- laidout("do binding", doBindingP)
    p2  <- loc
  } yield SDo(Real(span2(p1, p2)), dbs)

  def lamTerm: Parser[STerm] = for {
    p1 <- loc
    ps <- (patternL0.some << keyOp("->")).attempt
    e  <- term
    p2 <- loc
  } yield SLam(Real(span2(p1, p2)), ps.toList, e)

  def termL1: Parser[STerm] = caseTerm | letTerm | doTerm | lamTerm | termL0s

  /** The flat operator chain: operands and op occurrences in source
    * order; position class from adjacency alone. */
  def termChain: Parser[STerm] = {
    def more(prevOperand: Boolean, acc: List[Either[STerm, OpOcc]]): Parser[List[Either[STerm, OpOcc]]] =
      (spanned(opTok).map(o => Right(OpOcc(SName(o._1, Plain, Idfix, o._2),
          if (prevOperand) PostOperandPos else OperandPos)): Either[STerm, OpOcc])
        .flatMap(i => more(prevOperand = false, i :: acc))) |
      (if (prevOperand) unit(acc)
       else termL1.map(t => Left(t): Either[STerm, OpOcc]).flatMap(i => more(prevOperand = true, i :: acc))) |
      unit(acc)
    for {
      p1    <- loc
      first <- termL1
      rest  <- more(prevOperand = true, Nil)
      p2    <- loc
    } yield rest match {
      case Nil   => first
      case items => SChain(Chain(Real(span2(p1, p2)), Left(first) :: items.reverse))
    }
  }

  def termNeg: Parser[STerm] = for {
    p1 <- loc
    m  <- spanned(word("-")).attempt.optional
    t  <- termChain
    p2 <- loc
  } yield m match {
    case Some(s) => SNeg(Real(span2(p1, p2)), s._2, t)
    case None    => t
  }

  def term: Parser[STerm] = for {
    p1 <- loc
    tm <- termNeg
    r  <- (keyOp(":") >> annotTy).optional
    p2 <- loc
  } yield r match {
    case None    => tm
    case Some(t) => SSig(Real(span2(p1, p2)), tm, t)
  }

  // ---------------------------------------------------------------- types
  // The real type grammar (2.3c), replacing the raw-extent scaffold.
  // kindMode adds the kind atoms (*, rho/ρ, phi/φ, constraint/Γ) that the
  // fused pipeline parses with a separate kind grammar; everything else is
  // shared, mirroring TypeParsers typL0/typL1/typL2/typ.

  private def kindKeywordAtom: Parser[STy] =
    (spanned(keyword("rho").as("rho") | keyword("ρ").as("ρ") |
             keyword("phi").as("phi") | keyword("φ").as("φ") |
             keyword("constraint").as("constraint") | keyword("Γ").as("Γ"))
       .map(s => STyName(SName(s._1, Plain, Idfix, s._2)): STy)) |
    spanned(token(rawCh('*'))).map(s => STyName(SName("*", Plain, Idfix, s._2)): STy)

  private def tyName: Parser[SName] =
    (spanned(identTok) | spanned(moduleQualCon) | spanned(qualDottedName))
      .map(n => SName(n._1, Plain, Idfix, n._2))

  /** Module.Sub.name — qualified references to lowercase names too. */
  private def qualDottedName: Parser[String] =
    token((((upper >> identTail).slice << rawCh('.')).some.map(_.toList) ++
           (letter >> identTail).slice)
      .map { case ms ++ n => ms.mkString(".") + "." + n }.attempt("qualified name"))

  private def rowInner(mk: (SLoc, Boolean, List[STy]) => STy, open: Parser[Any]): Parser[STy] = for {
    s <- spanned(for {
      _ <- open
      r <- (ellipsis >> tyName.map(n => (true, List(STyName(n): STy)))) |
           tyName.map(n => STyName(n): STy).sepBy(comma).map(ts => (false, ts.toList))
      _ <- right
    } yield r)
  } yield mk(Real(s._2), s._1._1, s._1._2)

  def tyAtom(kindMode: Boolean): Parser[STy] = (
    rowInner(STyBanana.apply, leftBanana) |
    rowInner(STyRowBrace.apply, leftBrace) |
    rowInner(STyRowBracket.apply, leftBracket) |
    (if (kindMode) kindKeywordAtom else fail("kind atom")) |
    spanned(token(paren(keyOp("->")))).map(s => STyName(SName("->", ParenOp, Idfix, s._2)): STy).attempt |
    spanned(token(paren(comma.some))).map(s => STyTuple(Real(s._2), Nil): STy).attempt |
    tyName.map(n => STyName(n): STy) |
    (for { s <- spanned(paren(typ(kindMode) sepBy comma)) }
       yield (s._1 match {
         case List(one) => STyParen(Real(s._2), one)
         case xs        => STyTuple(Real(s._2), xs)
       }): STy)
  ) scope "type atom"

  def tyApp(kindMode: Boolean): Parser[STy] =
    tyAtom(kindMode).some.map(_.toList.reduceLeft(STyApp.apply))

  private def tyArrowOcc: Parser[OpOcc] =
    (spanned(keyOp("->")).map(s => OpOcc(SName("->", Plain, Idfix, s._2), PostOperandPos)) |
     spanned(doubleArrowTok).map(s => OpOcc(SName("=>", Plain, Idfix, s._2), PostOperandPos)) |
     spanned(keyOp("<-")).map(s => OpOcc(SName("<-", Plain, Idfix, s._2), PostOperandPos)))

  def tyChain(kindMode: Boolean): Parser[STy] = {
    def more(prevOperand: Boolean, acc: List[Either[STy, OpOcc]]): Parser[List[Either[STy, OpOcc]]] =
      ((if (prevOperand) tyArrowOcc | spanned(opTok).map(o => OpOcc(SName(o._1, Plain, Idfix, o._2), PostOperandPos))
        else spanned(opTok).map(o => OpOcc(SName(o._1, Plain, Idfix, o._2), OperandPos)))
         .map(Right(_): Either[STy, OpOcc])
         .flatMap(i => more(prevOperand = false, i :: acc))) |
      (if (prevOperand) unit(acc)
       else tyApp(kindMode).map(t => Left(t): Either[STy, OpOcc]).flatMap(i => more(prevOperand = true, i :: acc))) |
      unit(acc)
    for {
      p1    <- loc
      first <- tyApp(kindMode)
      rest  <- more(prevOperand = true, Nil)
      p2    <- loc
    } yield rest match {
      case Nil   => first
      case items => STyChain(Chain(Real(span2(p1, p2)), Left(first) :: items.reverse))
    }
  }

  /** `a` or `(a : kind)` binder. */
  def tyBinder: Parser[SBinder] =
    spanned(identTok).map(n => SBinder(SName(n._1, Plain, Idfix, n._2), None)) |
    token(paren(for {
      n <- spanned(identTok)
      _ <- keyOp(":")
      k <- tyChain(kindMode = true)
    } yield SBinder(SName(n._1, Plain, Idfix, n._2), Some(k))).attempt("kinded binder"))

  private def kindBraceGroup: Parser[List[SName]] =
    token(brace(spanned(identTok).map(n => SName(n._1, Plain, Idfix, n._2)).many.map(_.toList)))
      .attempt.orElse(Nil)

  def existsTy: Parser[STy] = for {
    p1 <- loc
    _  <- keyword("exists")
    bs <- tyBinder.many
    _  <- keyOp(".")
    cs <- tyChain(kindMode = false).sepBy1(comma)
    p2 <- loc
  } yield STyExists(Real(span2(p1, p2)), bs.toList, cs.toList)

  def typ(kindMode: Boolean): Parser[STy] = (for {
    p1 <- loc
    q  <- (for {
            _   <- keyword("forall")
            ks  <- kindBraceGroup
            bs  <- tyBinder.many
            _   <- keyOp(".")
          } yield (ks, bs.toList)).attempt.optional
    t  <- existsTy | tyChain(kindMode)
    p2 <- loc
  } yield q match {
    case None           => t
    case Some((ks, bs)) => STyForall(Real(span2(p1, p2)), ks, bs, t)
  }) scope "type"

  /** Signature/annotation types: optional `some` quantifier, then typ
    * (TypeParsers.annot). */
  def annotTy: Parser[STy] = for {
    p1 <- loc
    q  <- (for {
            _  <- keyword("some")
            ks <- kindBraceGroup
            bs <- tyBinder.many
            _  <- keyOp(".")
          } yield (ks, bs.toList)).attempt.optional
    t  <- typ(kindMode = false)
    p2 <- loc
  } yield q match {
    case None           => t
    case Some((ks, bs)) => STySome(Real(span2(p1, p2)), ks, bs, t)
  }

  // --------------------------------------------- remaining statement kinds

  private def stringLit: Parser[(String, Span)] = spanned(stringLiteral)

  def fieldStatementP: Parser[SStatement] = for {
    p1 <- loc
    _  <- keyword("field")
    vs <- spanned(identTok).map(n => SName(n._1, Plain, Idfix, n._2)).sepBy1(comma)
    _  <- keyOp(":")
    t  <- typ(kindMode = false)
    p2 <- loc
  } yield SFieldStatement(Real(span2(p1, p2)), vs.toList, t)

  private def dottedDefName: Parser[SName] = for {
    n <- spanned((((letter >> identTail).slice << rawCh('.')).attempt.many.map(_.toList) ++
                  (letter >> identTail).slice)
           .map { case ms ++ n => (ms :+ n).mkString(".") })
  } yield SName(n._1, Plain, Idfix, n._2)

  def tableStatementP(dbName: Option[String]): Parser[SStatement] = (for {
    p1 <- loc
    _  <- keyword("table")
    vs <- token(dottedDefName).sepBy1(comma)
    _  <- keyOp(":")
    t  <- typ(kindMode = false)
    p2 <- loc
  } yield STableStatement(Real(span2(p1, p2)), dbName, vs.toList, t): SStatement).attempt("table statement")

  def typeAliasP: Parser[SStatement] = for {
    p1 <- loc
    _  <- keyword("type")
    v  <- defName
    ks <- kindBraceGroup
    bs <- tyBinder.many
    _  <- keyOp("=")
    t  <- existsTy | typ(kindMode = false)
    p2 <- loc
  } yield STypeAlias(Real(span2(p1, p2)), v, ks, bs.toList, t)

  private def dataConDef: Parser[SConDef] = for {
    p1 <- loc
    ex <- (keyword("forall") >> tyBinder.many << keyOp(".")).attempt.map(_.toList).orElse(Nil)
    n  <- defName
    fs <- tyAtom(kindMode = false).many
    p2 <- loc
  } yield SConDef(Real(span2(p1, p2)), ex, n, fs.toList)

  def dataStatementP: Parser[SStatement] = for {
    p1  <- loc
    _   <- keyword("data")
    v   <- defName
    ks  <- kindBraceGroup
    bs  <- tyBinder.many
    cs  <- (keyOp("=") >> dataConDef.sepBy1(keyOp("|"))).optional
    p2  <- loc
  } yield SDataStatement(Real(span2(p1, p2)), v, ks, bs.toList, cs.map(_.toList).getOrElse(Nil))

  def classStatementP: Parser[SStatement] = for {
    p1  <- loc
    _   <- keyword("class")
    v   <- defName
    ks  <- kindBraceGroup
    bs  <- tyBinder.many
    ctx <- (keyOp("|") >> tyChain(kindMode = false).sepBy1(comma)).map(_.toList).orElse(Nil)
    bod <- (keyword("where") >>
             (classPrivateP | bindingStatement).attempt.sepEndBy(semi)
               .between(virtualLeftBrace("class body"), virtualRightBrace)).map(_.toList).orElse(Nil)
    p2  <- loc
  } yield SClassStatement(Real(span2(p1, p2)), v, ks, bs.toList, ctx, bod)

  private def classPrivateP: Parser[SStatement] = for {
    p1 <- loc
    _  <- keyword("private")
    ss <- laidout("class private statement", bindingStatement)
    p2 <- loc
  } yield SPrivateBlock(Real(span2(p1, p2)), ss)

  private def foreignStatementP: Parser[SForeign] = {
    def sigPart: Parser[(SName, STy)] = for {
      v <- defName
      _ <- keyOp(":")
      t <- typ(kindMode = false)
    } yield (v, t)
    (for {
      p1 <- loc; _ <- keyword("data"); c <- stringLit; v <- defName; bs <- tyBinder.many; p2 <- loc
    } yield SForeignData(Real(span2(p1, p2)), v, bs.toList, c._1, c._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("method"); m <- stringLit; vt <- sigPart; p2 <- loc
    } yield SForeignMethod(Real(span2(p1, p2)), vt._1, vt._2, m._1, m._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("function"); c <- stringLit; m <- stringLit; vt <- sigPart; p2 <- loc
    } yield SForeignFunction(Real(span2(p1, p2)), vt._1, vt._2, c._1, c._2, m._1, m._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("value"); c <- stringLit; m <- stringLit; vt <- sigPart; p2 <- loc
    } yield SForeignValue(Real(span2(p1, p2)), vt._1, vt._2, c._1, c._2, m._1, m._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("constructor"); vt <- sigPart; p2 <- loc
    } yield SForeignConstructor(Real(span2(p1, p2)), vt._1, vt._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("subtype"); vt <- sigPart; p2 <- loc
    } yield SForeignSubtype(Real(span2(p1, p2)), vt._1, vt._2): SForeign) |
    (for {
      p1 <- loc; _ <- keyword("private")
      ss <- laidout("foreign private statement", foreignStatementP)
      p2 <- loc
    } yield SForeignPrivate(Real(span2(p1, p2)), ss): SForeign)
  }

  private def sameLine(p: Pos): Parser[Unit] =
    new Parser[Unit] {
      def apply(s: ParseState, sup: Supply) =
        scalaz.Trampoline.done(
          if (s.loc.line == p.line) scalaparsers.Pure(())
          else scalaparsers.Fail(None, List(), Set()))
    }

  def foreignBlockP: Parser[SStatement] = for {
    p1     <- loc
    _      <- keyword("foreign")
    privat <- (sameLine(p1) >> keyword("private")).as(true).orElse(false)
    ss     <- laidout("foreign statement", foreignStatementP)
    p2     <- loc
  } yield {
    val blk = SForeignBlock(Real(span2(p1, p2)), ss)
    if (privat) SPrivateBlock(Real(span2(p1, p2)), List(blk)) else blk
  }

  def privateBlockP: Parser[SStatement] = for {
    p1      <- loc
    _       <- keyword("private")
    foreign <- (sameLine(p1) >> keyword("foreign")).as(true).orElse(false)
    r <- if (foreign) for {
           ss <- laidout("private foreign statement", foreignStatementP)
           p2 <- loc
         } yield SPrivateBlock(Real(span2(p1, p2)), List(SForeignBlock(Real(span2(p1, p2)), ss)))
         else for {
           ss <- statement.attempt.sepEndBy(semi)
                   .between(virtualLeftBrace("private statement"), virtualRightBrace)
           p2 <- loc
         } yield SPrivateBlock(Real(span2(p1, p2)), ss.toList)
  } yield r

  def databaseBlockP: Parser[SStatement] = for {
    p1 <- loc
    _  <- keyword("database")
    db <- stringLit
    ss <- laidout("database statement", tableStatementP(Some(db._1)))
    p2 <- loc
  } yield SDatabaseBlock(Real(span2(p1, p2)), db._1, ss)

  // ---------------------------------------------------- binding statements

  def sigStatement: Parser[SStatement] = (for {
    p1 <- loc
    vs <- defName.sepBy1(comma)
    _  <- keyOp(":")
    t  <- annotTy
    p2 <- loc
  } yield SSigStatement(Real(span2(p1, p2)), vs.toList, t): SStatement).attempt("signature")

  def equationStatement: Parser[SStatement] = for {
    p1   <- loc
    v    <- defName
    pats <- patternL0.many
    _    <- keyOp("=")
    body <- term
    wh   <- (for {
              w1 <- loc
              _  <- keyword("where")
              ss <- laidout("binding statement", bindingStatement)
              w2 <- loc
            } yield SWhere(Real(span2(w1, w2)), ss)).optional
    p2   <- loc
  } yield SEquation(Real(span2(p1, p2)), v, pats.toList, body, wh)

  def bindingStatement: Parser[SStatement] =
    sigStatement | equationStatement

  /** One raw character of a statement: newlines re-arm the offside check;
    * other characters require being onside.  Nested (deeper-indented)
    * lines stay onside, so this consumes exactly one top-level
    * statement's extent — the skip-to-layout-boundary primitive. */
  private def rawStatementChar: Parser[Any] =
    (rawNewline << setBol(true)) |
    rawSatisfy(c => c == ' ' || c == '\t' || c == '\r') |  // whitespace never decides offside
    (rawCh('-') >> rawCh('-') >> rawSatisfy(_ != '\n').skipMany).attempt |  // line comments are whitespace
    (stillOnside >> rawSatisfy(_ != '\n') << setBol(false))

  private val stmtKinds =
    List("field", "table", "type", "data", "class", "foreign", "private",
         "database", "import", "export")

  /** 2.3b/2.3c placeholder: capture the statement's exact extent and its
    * kind; the message format is load-bearing for TestSurfaceParsers. */
  def rawStatement: Parser[SStatement] = for {
    p1   <- loc
    // the vsemi decision was already made; clear stale begin-of-line state
    // the same way token parsers do before their first character
    text <- (setBol(false) >> rawStatementChar.skipSome).slice
              .filter(t => !t.linesIterator.forall(l => l.trim.isEmpty || (l.trim startsWith "--")))
              .attempt("statement text")  // comment-only extents are whitespace,
                                          // not statements (bare `private` + a
                                          // col-1 comment, Error.e)
    p2   <- loc
    _    <- optionalSpace.skipOptional
  } yield {
    val head = text.trim.takeWhile(c => c.isLetter || c == '#')
    val kind = if (stmtKinds contains head) head else "binding"
    SErrorStatement(Real(span2(p1, p2)), s"unparsed:$kind")
  }

  def statement: Parser[SStatement] =
    optionalSpace.skipOptional >>
    (fixityStatement       |
     fieldStatementP       |
     tableStatementP(None) |
     typeAliasP            |
     dataStatementP        |
     foreignBlockP         |
     privateBlockP         |
     databaseBlockP        |
     classStatementP       |
     bindingStatement.attempt |
     rawStatement)

  def module(fileName: String, contents: String, defaultName: String = "Surface"): Either[Err, SModule] = {
    val p = for {
      h  <- header(defaultName)
      ss <- if (h.explicitLayout)
              // no stdlib witness; real support arrives with 2.3b
              unit(List(SErrorStatement(h.loc, "unparsed:explicit-layout-module")))
            // .attempt: the item's leading whitespace skip may consume a
            // trailing comment and commit before discovering nothing
            // follows — roll back so the closing virtual brace can fire
            else statement.attempt.scope("statement").sepEndBy(semi)
                   .between(virtualLeftBrace("statement"), virtualRightBrace)
      _  <- eof
    } yield SModule(fileName, h, ss)
    val ps = scalaparsers.ParseState.mk(fileName, contents, ())
    p.run(ps, Supply.create.split) match {
      case Left(err)      => Left(err)
      case Right((_, m))  => Right(m)
    }
  }

  /** A REPL expression: the whole input is one term (post-G1 D1 —
    * Session.eval's phrase(term) over the resolution-free grammar). */
  def expression(source: String, contents: String): Either[Err, STerm] = {
    val ps = scalaparsers.ParseState.mk(source, contents, ())
    phrase(term).run(ps, Supply.create.split) match {
      case Left(err)     => Left(err)
      case Right((_, t)) => Right(t)
    }
  }
}
