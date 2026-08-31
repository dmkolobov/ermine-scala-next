package com.clarifi.reporting.ermine.parsing

import com.clarifi.reporting.ermine.{Local, Global}
import com.clarifi.reporting.ermine.syntax._
import com.clarifi.reporting.ermine.syntax.Statement._

import scalaparsers.{++, Located, Pos}
import scalaparsers.Diagnostic.raise
import com.clarifi.reporting.ermine.{ ImplicitBinding, Term }
import scala.collection.immutable.List

case class ModuleHeader(
  loc: Pos,
  name: String,
  explicitLayout: Boolean = false,
  importExports: List[ImportExportStatement] = List()
) extends Located {
  import SI8862._

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

  // the fused name-parser objects retired (D3); the header grammar keeps
  // small local equivalents with the same character classes
  private object HeaderNames extends NameParser {
    def identStart = letter
    override def ident = super.ident | literalIdent
    def opStart = opChar
  }
  private object HeaderCons extends NameParser {
    def identStart = upper
    def opStart = ch(':')
  }

  def moduleName: Parser[String] = for {
    ns <- HeaderCons.ident.sepBy(keyOp(".")) scope "module name"
  } yield ns.mkString(".")


  def explicit: Parser[Explicit[Local]] = for {
    p <- loc
    isTy <- keyword("type").optional map (_.isDefined)
    src <- HeaderNames.name({ case l => List(l) })
    on <- (keyword("as") >> HeaderNames.name({ case l => List(l) })).optional
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
    as <- (keyword("as") >> HeaderNames.ident.map(_.string)).optional
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

  // (moduleBody and the command grammar retired with the fused
  // pipeline, post-G1 D3; the header and import/export statements
  // remain the shared front door)
}

// vim: set ts=4 sw=4 et:
