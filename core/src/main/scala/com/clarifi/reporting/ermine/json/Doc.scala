package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.{ Header, PrimT, SortOrder }
import com.clarifi.reporting.ermine.{ Runtime, Rel, EmptyRel, Bottom, Global, Type, AppT, ConcreteRho, Local, Memory, FieldConDecl }
import com.clarifi.reporting.ermine.session.SessionEnv
import com.clarifi.reporting.relational.{ Ext, ExtMem, Typer }
import scala.util.control.NonFatal

/** The document tree the writer consumes (tracker/JSON-API-DESIGN.md §3.4a,
  * tracker/JSON-STAGE3-PLAN.md "Wire contract"): plain JSON nodes plus one
  * node per relation, whose rows are resolved later by `Write.doc` inside the
  * scanner's effect.
  *
  * A `Doc` is built from an evaluated Ermine value by `Doc.fromRuntime`,
  * which runs the generic walker (`Encode.encode`) with `DocJson` as the
  * builder, so everything that is not a relation is exactly what `:json`
  * would print, and a relation becomes a `Data` whose columns are already
  * known: the column descriptors of a relation object are written before
  * its scan starts.
  *
  * Numbers keep the walker's distinction: `DLong` is an integral JSON number
  * (Int/Short/Byte, and a hand-built `JInt`), `DNum` a finite double.  An
  * object keeps its keys in walker order (a `data` value's `"tag"` first,
  * then declaration order; a record's keys sorted); a repeated key keeps the
  * LAST value at the FIRST key's position, which is what argonaut does.
  */
sealed abstract class Doc

object Doc {
  case object DNull extends Doc
  final case class DBool(value: Boolean) extends Doc
  final case class DLong(value: Long) extends Doc
  /** Always finite: the walker refuses NaN and the infinities. */
  final case class DNum(value: Double) extends Doc
  final case class DStr(value: String) extends Doc
  final case class DArr(items: List[Doc]) extends Doc
  final case class DObj(fields: List[(String, Doc)]) extends Doc
  /** A JSON value written verbatim (the runner's `settings`). */
  final case class DRaw(json: argonaut.Json) extends Doc

  /** One column descriptor: `{"name":..,"type":..,"nullable":..}`. */
  final case class Column(name: String, prim: PrimT) {
    def nullable: Boolean = prim.nullable
    def typeName: String = Wire.columnType(prim)
  }

  /** A relation in the document.  `columns` are the plan header's, sorted by
    * name (the row arrays follow this order); `order` is the scan order
    * (`Nil`: whatever the scanner yields -- nothing in Ermine gives one
    * today); `delivery` is what the VALUE asked for (`ByRequest` for a bare
    * relation); `path` is the walker path of the node (`$.props.rows`), used
    * in every error and log line about it. */
  final case class Data(ext: Ext[Nothing, Nothing],
                        columns: List[Column],
                        order: List[(String, SortOrder)],
                        delivery: Delivery,
                        path: String) extends Doc

  /** A header per walker path, for relations that do not carry one. */
  type Hints = String => Option[Header]
  val noHints: Hints = _ => None

  /** The columns of a header, in wire order (sorted by name, the order the
    * record encoder uses too). */
  def columnsOf(h: Header): List[Column] =
    h.toList.sortBy(_._1).map { case (n, p) => Column(n, p) }

  /** Run the generic walker over an evaluated value.  A header-less empty
    * relation (the runtime's `EmptyRel`, what `mkRelation# []` evaluates to)
    * is an error at its path unless `hints` supplies a header for that path;
    * see `headerOfType` for turning a static relation type into one. */
  def fromRuntime(node: Runtime, hints: Hints = noHints): Either[Encode.Error, Doc] =
    Encode.encode(node, new DocJson(hints))

  /** `{"version":1,"settings":settings,"root":root}`. */
  def document(root: Doc, settings: Doc): Doc =
    DObj(List(Wire.Version -> DLong(Wire.version), Wire.Settings -> settings, Wire.Root -> root))

  def document(root: Doc, settings: argonaut.Json): Doc = document(root, DRaw(settings))

  def document(root: Doc): Doc = document(root, DObj(Nil))

  /** Every relation node, in document order. */
  def relations(d: Doc): List[Data] = {
    val acc = new scala.collection.mutable.ListBuffer[Data]
    var stack: List[Doc] = List(d)
    while (stack.nonEmpty) {
      val top = stack.head
      stack = stack.tail
      top match {
        case x: Data   => acc += x
        case DArr(xs)  => stack = xs ++ stack
        case DObj(fs)  => stack = fs.map(_._2) ++ stack
        case _         => ()
      }
    }
    acc.toList
  }

  // ---------------------------------------------------------------------
  // a header from a static type

  /** The header of a relation TYPE `[f1, f2, ..]` (a `Relation` of a closed
    * row), read from the field witnesses in `s.cons`: the one kind of static
    * hint the writer supports for a header-less empty relation.  `module` is
    * the module a `Local` field name resolves in.  `Nullable t` is the
    * nullable `PrimT` of `t`; a field of a type that is not one of the ten
    * column types is refused. */
  def headerOfType(t: Type, module: String)(implicit s: SessionEnv): Either[String, Header] = {
    def unfurl(t: Type, args: List[Type]): (Type, List[Type]) = t match {
      case AppT(f, a)   => unfurl(f, a :: args)
      case Memory(_, u) => unfurl(u, args)
      case other        => (other, args)
    }
    def prim(ft: Type): Either[String, PrimT] = unfurl(ft, Nil) match {
      case (Type.Con(_, Global("Builtin", "Nullable", _), _, _), List(a)) =>
        prim(a).right.map(_.withNull)
      case (Type.Con(_, Global("Builtin", n, _), _, _), Nil) => n match {
        case "Int"       => Right(PrimT.IntT(false))
        case "Byte"      => Right(PrimT.ByteT(false))
        case "Short"     => Right(PrimT.ShortT(false))
        case "Long"      => Right(PrimT.LongT(false))
        case "Double"    => Right(PrimT.DoubleT(false))
        case "String"    => Right(PrimT.StringT(0, false))
        case "Bool"      => Right(PrimT.BooleanT(false))
        case "Date"      => Right(PrimT.DateT(false))
        case "Timestamp" => Right(PrimT.TimestampT(false))
        case "GUID"      => Right(PrimT.UuidT(false))
        case other       => Left("the type " + other + " is not a column type")
      }
      case other => Left("the type " + other._1 + " is not a column type")
    }
    unfurl(t, Nil) match {
      case (Type.Con(_, Global("Builtin", "Relation", _), _, _), List(row)) => row match {
        case ConcreteRho(_, names) =>
          names.toList.foldLeft(Right(Map.empty): Either[String, Header]) { (acc, n) =>
            acc.right.flatMap { h =>
              val g = n match {
                case l: Local  => l.global(module)
                case g: Global => g
              }
              s.cons.get(g) match {
                case Some(Type.Con(_, fg, FieldConDecl(ft), _)) =>
                  prim(ft).right.map(p => h + (fg.string -> p)).left.map("field " + fg.string + ": " + _)
                case _ => Left("no field witness for " + g)
              }
            }
          }
        case other => Left("not a closed row: " + other)
      }
      case _ => Left("not a relation type: " + t)
    }
  }

  // ---------------------------------------------------------------------
  // text

  /** The JSON text of a document with no relation in it (a `Data` node is
    * refused: its rows need the scanner). */
  def pureText(d: Doc): String = {
    val sb = new java.lang.StringBuilder
    Write.segments(d).foreach {
      case Write.Text(t) => sb.append(t)
      case Write.Relation(x) => throw new IllegalArgumentException("a relation at " + x.path + " has no pure text")
    }
    sb.toString
  }
}

/** The third `JsonBuilder` (beside `ArgonautJson` and `ErmineJson`): the
  * document writer's tree.  `rel` forces the relation and reads its header
  * from the plan (`Typer.extTyper`, the same header `relation#` and the
  * writers use), so a malformed plan is an encode error at its path, before
  * any scan runs. */
final class DocJson(hints: Doc.Hints) extends JsonBuilder[Doc] {
  import Doc._
  def nul                = DNull
  def bool(b: Boolean)   = DBool(b)
  def int(i: Int)        = DLong(i.toLong)
  def long(l: Long)      = DLong(l)
  def num(d: Double)     = DNum(d)
  def str(s: String)     = DStr(s)
  def arr(xs: List[Doc]) = DArr(xs)
  def obj(fields: List[(String, Doc)]) = {
    // argonaut's JsonObject: a repeated key keeps its first position and its last value
    val seen = new java.util.HashMap[String, Doc]
    fields.foreach { case (k, v) => seen.put(k, v) }
    if (seen.size == fields.length) DObj(fields)
    else {
      val done = new java.util.HashSet[String]
      DObj(fields.flatMap { case (k, _) => if (done.add(k)) List((k, seen.get(k))) else Nil })
    }
  }

  def rel(path: String, r: Runtime, delivery: Delivery): Either[Encode.Error, Doc] = {
    val v = try Runtime.swhnf(r) catch { case NonFatal(e) => Bottom(throw e) }
    v match {
      case Rel(ext) =>
        val typed = try Typer.extTyper(ext).toEither.left.map(_.list.toList.mkString("; "))
                    catch { case NonFatal(e) => Left(Option(e.getMessage).getOrElse(e.toString)) }
        typed match {
          case Right(h) => Right(Data(ext, columnsOf(h), Nil, delivery, path))
          case Left(m)  => Left(Encode.Error(path, "the relation's plan has no header: " + m))
        }
      case EmptyRel => hints(path) match {
        case Some(h) =>
          Right(Data(ExtMem(com.clarifi.reporting.relational.EmptyRel(h)), columnsOf(h), Nil, delivery, path))
        case None =>
          Left(Encode.Error(path, "an empty relation built from no rows carries no columns; " +
                                  "give it a header (mkRelationWithHeader#) or a static hint"))
      }
      case b: Bottom =>
        val t = b.thrown
        Left(Encode.Error(path, "the relation is an error: " + Option(t.getMessage).getOrElse(t.toString)))
      case other =>
        Left(Encode.Error(path, "expected a relation, found " + other.getClass.getSimpleName))
    }
  }
}
