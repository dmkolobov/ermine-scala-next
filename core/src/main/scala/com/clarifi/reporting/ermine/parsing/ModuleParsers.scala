package com.clarifi.reporting.ermine.parsing

import com.clarifi.reporting.ermine.{Local, Global}
import com.clarifi.reporting.ermine.syntax._
import com.clarifi.reporting.ermine.syntax.Statement._

import scalaparsers.{++, Located, Pos}
import scalaparsers.Diagnostic.raise
import com.clarifi.reporting.ermine.{ ImplicitBinding, Term }
import scala.collection.immutable.List
import StatementParsers._

case class ModuleHeader(
  loc: Pos,
  name: String,
  explicitLayout: Boolean = false,
  importExports: List[ImportExportStatement] = List()
) extends Located {
  import SI8862._

  def topLayout: Parser[List[Statement]] =
    if (explicitLayout)
      for {
        ss <- statement.sepBy(token(";"))
        _ <- (right >> eof) attempt "end of explicit layout"
      } yield ss
    else statements
  def imports: Map[String, (Option[String], List[Explicit[Global]], Boolean)] = {
    val counts = importExports.foldLeft(Map[String,Int]()) {
      case (m, i) => m.get(i.module) match {
        case Some(n) => m + (i.module -> (n+1))
        case None => m + (i.module -> 1)
      }
    } filter { case (_, i) => i > 1 }

    if (counts.size > 0)
      die("Duplicate module imports not correctly handled: " +
          "\n\tModule: " + name +
          "\n\tImports: " + counts.keySet.mkString(", "))

    val all : (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)
    Map("Builtin" -> all, name -> all) ++ importExports.map {
      i => i.module -> (i.as, i.explicits, i.using)
    }
  }
}

object ModuleParsers {
  import SI8862._

  def moduleName: Parser[String] = for {
    ns <- DataConParsers.ident.sepBy(keyOp(".")) scope "module name"
  } yield ns.mkString(".")

  def bindingSpan(xs: List[Statement], acc: List[BindingStatement] = List()): (List[BindingStatement], List[Statement]) = xs match {
    case (b: BindingStatement) :: ys => bindingSpan(ys, b :: acc)
    case _ => (acc.reverse, xs)
  }

  def explicit: Parser[Explicit[Local]] = for {
    p <- loc
    isTy <- keyword("type").optional map (_.isDefined)
    src <- TermNameParsers.name({ case l => List(l) })
    on <- (keyword("as") >> TermNameParsers.name({ case l => List(l) })).optional
    _ <- on match {
      case Some(rename) if src.fixity.con != rename.fixity.con =>
        raise(p, "error: Renaming to different operator type is not supported.")
      case _ => unit(())
    }
  } yield on match {
      case Some(rename) => Renaming(src, rename, isTy)
      case None         => Single(src, isTy)
    }

  val importExportStatement: Parser[ImportExportStatement] = (for {
    p <- loc
    isExport <- keyword("import").as(false) | keyword("export").as(true)
    src <- moduleName // stringLiteral
    as <- (keyword("as") >> TermNameParsers.ident.map(_.string)).optional
    opt <- (for {
      isUsing <- keyword("using").as(true) | keyword("hiding").as(false)
      exps <- laidout("explicit imports", explicit.map(_.map(_.global(src))))
    } yield (isUsing, exps)).optional
  } yield opt match {
    case Some((isUsing, exps)) => ImportExportStatement(p, isExport, src, as, exps, isUsing)
    case None                  => ImportExportStatement(p, isExport, src, as)
  }) scope "import/export statement"

  // parse leading import statements, leaving the remainder of the input untouched
  def moduleHeader(defaultName: String): Parser[ModuleHeader] = (
    for {
      p <- whiteSpace(false, false) >> loc
      name <- (keyword("module") >> moduleName << keyword("where")) scope "module header" orElse defaultName
      _ <- modify(ErParseState.Lenses.moduleName.set(_, name))
      explicit <- leftBrace.as(true) | (semi | eof).as(false)
      importExports <- importExportStatement.sepEndBy(if (explicit) token(";") else semi) scope "import statements"
    } yield ModuleHeader(p, name, explicit, importExports)
  ) scope "module definition"

  // resume parsing after we've loaded the definitions required by the module header
  def moduleBody(header: ModuleHeader): Parser[Module] = {
    def go(ss: List[Statement], sigs: List[SigStatement], m: Module): (List[SigStatement], Module) = ss match {
      case List() => (sigs, m)
      case s :: ss => s match {
        case t : ForeignTermDef       => go(ss, sigs, m.copy(foreigns = t :: m.foreigns))
        case t : FieldStatement       => go(ss, sigs, m.copy(fields = t :: m.fields))
        case t : TableStatement       => go(ss, sigs, m.copy(tables = t :: m.tables))
        case t : ForeignDataStatement => go(ss, sigs, m.copy(foreignData = t :: m.foreignData))
        case _ : FixityStatement      => go(ss, sigs, m)
        case t : TypeDef              => go(ss, sigs, m.copy(types = t :: m.types, privateTerms = t.privateTerms ++ m.privateTerms))
        case t : BindingStatement     =>
          val (bs, xs) = bindingSpan(ss)
          val (is, signatures) = gatherBindings(t :: bs)
          go(xs, signatures ++ sigs, m.copy(implicits = is ++ m.implicits))
        case t : PrivateBlock => {
          val (ns, nm) = go(t.statements,
                            sigs,
                            m.copy(privateTerms = t.definedTerms ++ m.privateTerms,
                                   privateTypes = t.definedTypes ++ m.privateTypes)
                           )
          go(ss, ns, nm)
        }
        case t : DatabaseBlock => {
          val (ns, nm) = go(t.statements, sigs, m)
          go(ss, ns, nm)
        }
        case t : ForeignBlock => {
          val (ns, nm) = go(t.statements, sigs, m)
          go(ss, ns, nm)
        }
      }
    }
    for {
      pos <- loc
      stmts <- header.topLayout scope "statements"
      (sigs, mod) = go(stmts, List(), Module(header.loc, header.name, header.importExports))
      p <- checkBindings(pos, mod.implicits, sigs)
      _ <- p.distinct(pos)
    } yield mod.copy( // reversing just so we get errors roughly in order
      foreigns = mod.foreigns.reverse,
      fields = mod.fields.reverse,
      tables = mod.tables.reverse,
      foreignData = mod.foreignData.reverse,
      implicits = p.extract._1,
      explicits = p.extract._2
    )
  }

  def command(mh: ModuleHeader) : Parser[Command] = simpleSpace.skipMany >> (
    (importExportStatement << eof).map(ImportExportCommand(_)) |
    eof.as(EmptyCommand) |
    ModuleParsers.moduleBody(mh).map(ModuleCommand(_))
  ).race(
    nakedTerm.map(ExpressionCommand(_))
  )
}

// vim: set ts=4 sw=4 et:
