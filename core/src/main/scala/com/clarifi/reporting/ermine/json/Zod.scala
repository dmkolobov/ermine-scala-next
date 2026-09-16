package com.clarifi.reporting.ermine.json

import scala.collection.immutable.List
import scala.collection.mutable.ListBuffer
import argonaut.Json

/** `JSON Schema => TypeScript`, zod 3: the generated half of the browser
  * contract (tracker/JSON-API-DESIGN.md §3.5).
  *
  * The input is a document `Schema.export` produced, not JSON Schema at
  * large -- the same subset `Validate` checks -- so this is a translator,
  * not a compiler, and an unrecognised node is a `Left`, never a silent
  * `z.any()`: a mapping this file has not learned about must break the build
  * rather than reach the client as "anything goes".
  *
  * Shape of the output, one file:
  *
  * {{{
  * import { z } from "zod";
  *
  * export const Test_Colour = z.enum(["Red", "Green", "Blue"]);
  * export type Test_Colour = z.infer<typeof Test_Colour>;
  *
  * export const Schema = Test_Colour;
  * export type Schema = z.infer<typeof Schema>;
  * }}}
  *
  * One `const` per `$defs` entry, in dependency order, so a reference is
  * normally a plain identifier.  A reference that cannot be ordered -- a
  * recursive or mutually recursive type -- is emitted as `z.lazy(() => X)`,
  * and every def reached that way is annotated `: z.ZodTypeAny`, because
  * `tsc --strict` refuses a `const` whose inferred type would depend on
  * itself (TS7022).  `z.infer` of such a def is `any`: the runtime check is
  * exact, the static type of a recursive schema is not, which is the price
  * zod 3 charges for recursion without a hand-written interface.
  *
  * Keyword by keyword: integer -> `z.number().int()` (with `.min`/`.max` for
  * `Short`/`Byte`), `Long`'s string+pattern -> `z.string().regex(/^-?[0-9]+$/)`,
  * `format: date` -> `z.string().date()`, `date-time` -> `.datetime()`,
  * `uuid` -> `.uuid()`, an `anyOf` with a null arm -> `.nullable()`, a
  * property absent from `required` -> `.optional()`, `enum` -> `z.enum`, an
  * `oneOf` of objects that all pin `tag` -> `z.discriminatedUnion("tag", ...)`,
  * an object -> `z.object({...}).strict()`, `prefixItems` -> `z.tuple`, the
  * empty schema `{}` (the stdlib `Json` type) -> `z.unknown()`.
  */
object Zod {

  def render(schema: Json): Either[String, String] = {
    val defs: List[(String, Json)] =
      schema.field("$defs").flatMap(_.obj).map(_.toList).getOrElse(Nil).sortBy(_._1)
    val names = defs.map(_._1)
    val ts = names.map(n => (n, identifier(n))).toMap
    val clash = ts.toList.groupBy(_._2).filter(_._2.length > 1)
    if (clash.nonEmpty)
      Left("two $defs names sanitise to the same TypeScript identifier: " +
           clash.toList.sortBy(_._1).map { case (id, ns) =>
             id + " <- " + ns.map(_._1).sorted.mkString(", ") }.mkString("; "))
    else {
      val bodies = defs.toMap
      val deps = defs.map { case (n, j) => (n, refsIn(j).filter(bodies.contains)) }.toMap

      // dependency order.  A self-edge does not block (it only forces
      // z.lazy below); a genuine cycle is broken by taking the
      // alphabetically first remaining name, so the order is deterministic.
      val order = new ListBuffer[String]
      var todo = names
      while (todo.nonEmpty) {
        val ready = todo.filter(n => deps(n).forall(d => d == n || order.contains(d)))
        if (ready.isEmpty) { order += todo.head; todo = todo.tail }
        else { order ++= ready; todo = todo.filterNot(ready.contains) }
      }

      // A reference is lazy when its target is not emitted strictly before
      // the referring def -- a self-reference included.
      val pos = order.toList.zipWithIndex.toMap
      val lazyTargets: Set[String] =
        defs.flatMap { case (n, j) => refsIn(j).filter(d => bodies.contains(d) && pos(d) >= pos(n)) }.toSet

      val header = {
        val b = new StringBuilder
        b ++= "// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.\n"
        schema.field("$id").flatMap(_.string) foreach { id => b ++= "// source: " + id + "\n" }
        b ++= "// zod 3\n\nimport { z } from \"zod\";\n\n"
        b.toString
      }

      val ctx = new Ctx(ts, lazyTargets)
      val decls = order.toList.map { n =>
        ctx.expr(bodies(n)).right.map { e =>
          val id = ts(n)
          val ann = if (lazyTargets.contains(n)) ": z.ZodTypeAny" else ""
          "export const " + id + ann + " = " + e + ";\nexport type " + id + " = z.infer<typeof " + id + ">;\n\n"
        }.left.map(msg => "$defs." + n + ": " + msg)
      }
      val rootBody = Json.obj(
        schema.objectFieldsOrEmpty
          .filterNot(f => f == "$schema" || f == "$id" || f == "$defs")
          .map(f => (f, schema.field(f).get)): _*)
      val root = ctx.expr(rootBody).left.map(msg => "root: " + msg)
      val all: List[Either[String, String]] = decls :+ root.right.map { e =>
        "export const Schema = " + e + ";\nexport type Schema = z.infer<typeof Schema>;\n" }
      all.collectFirst { case Left(e) => e } match {
        case Some(e) => Left(e)
        case None    => Right(header + all.map(_.right.get).mkString)
      }
    }
  }

  /** A TypeScript identifier for a `$defs` key: `Test.Tree_Int` becomes
    * `Test_Tree_Int`.  A leading digit gets a `_`. */
  def identifier(name: String): String = {
    val s = name.map(c => if (c.isLetterOrDigit || c == '_') c else '_')
    if (s.isEmpty) "_" else if (s.head.isDigit) "_" + s else s
  }

  private def refsIn(j: Json): List[String] = {
    val buf = new ListBuffer[String]
    def walk(x: Json): Unit = {
      x.field("$ref").flatMap(_.string) foreach { r =>
        if (r.startsWith("#/$defs/")) buf += r.substring("#/$defs/".length)
      }
      x.obj foreach { o => o.toList foreach { kv => walk(kv._2) } }
      x.array foreach { xs => xs foreach walk }
    }
    walk(j)
    buf.toList.distinct
  }

  // ---------------------------------------------------------------------

  private final class Ctx(ts: Map[String, String], lazyTargets: Set[String]) {

    def expr(j: Json): Either[String, String] = {
      def num(f: String): Option[BigDecimal] = j.field(f).flatMap(_.number).map(_.toBigDecimal)
      def str(f: String): Option[String] = j.field(f).flatMap(_.string)

      val ref     = j.field("$ref").flatMap(_.string)
      val const   = j.field("const")
      val enums   = j.field("enum").flatMap(_.array)
      val anyOf   = j.field("anyOf").flatMap(_.array)
      val oneOf   = j.field("oneOf").flatMap(_.array)
      val tyName  = j.field("type").flatMap(_.string)

      if (ref.isDefined) {
        val r = ref.get
        if (!r.startsWith("#/$defs/")) Left("unsupported $ref " + r)
        else {
          val target = r.substring("#/$defs/".length)
          ts.get(target) match {
            case None     => Left("dangling $ref " + r)
            case Some(id) => Right(if (lazyTargets.contains(target)) "z.lazy(() => " + id + ")" else id)
          }
        }
      }
      else if (const.isDefined) Right("z.literal(" + literal(const.get) + ")")
      else if (enums.isDefined) {
        val vs = enums.get
        if (vs.nonEmpty && vs.forall(_.string.isDefined))
          Right("z.enum([" + vs.flatMap(_.string).map(quote).mkString(", ") + "])")
        else
          Right("z.union([" + vs.map(v => "z.literal(" + literal(v) + ")").mkString(", ") + "])")
      }
      else if (anyOf.isDefined) {
        val alts = anyOf.get
        val (nulls, rest) = alts.partition(a => a.field("type").flatMap(_.string).contains("null"))
        if (nulls.nonEmpty && rest.length == 1) expr(rest.head).right.map(_ + ".nullable()")
        else seq(alts).right.map(es => "z.union([" + es.mkString(", ") + "])")
      }
      else if (oneOf.isDefined) {
        val alts = oneOf.get
        val tagged = alts.nonEmpty && alts.forall(a =>
          a.field("properties").flatMap(_.field("tag")).flatMap(_.field("const")).flatMap(_.string).isDefined)
        seq(alts).right.map { es =>
          if (tagged) "z.discriminatedUnion(\"tag\", [" + es.mkString(", ") + "])"
          else "z.union([" + es.mkString(", ") + "])"
        }
      }
      else tyName match {
        case Some("null")    => Right("z.null()")
        case Some("boolean") => Right("z.boolean()")
        case Some("integer") =>
          val b = new StringBuilder("z.number().int()")
          num("minimum") foreach { m => b ++= ".min(" + m.toLong + ")" }
          num("maximum") foreach { m => b ++= ".max(" + m.toLong + ")" }
          Right(b.toString)
        case Some("number")  => Right("z.number()")
        case Some("string")  =>
          val b = new StringBuilder("z.string()")
          str("format") foreach {
            case "date"      => b ++= ".date()"
            case "date-time" => b ++= ".datetime()"
            case "uuid"      => b ++= ".uuid()"
            case _           => ()
          }
          str("pattern") foreach { p => b ++= ".regex(/" + p.replace("/", "\\/") + "/)" }
          num("minLength") foreach { m => b ++= ".min(" + m.toInt + ")" }
          num("maxLength") foreach { m => b ++= ".max(" + m.toInt + ")" }
          Right(b.toString)
        case Some("array") =>
          val prefix = j.field("prefixItems").flatMap(_.array)
          val items  = j.field("items")
          if (prefix.isDefined) seq(prefix.get).right.map(es => "z.tuple([" + es.mkString(", ") + "])")
          else if (items.isDefined) expr(items.get).right.map(e => "z.array(" + e + ")")
          else if (num("maxItems").exists(_ == BigDecimal(0))) Right("z.tuple([])")
          else Right("z.array(z.unknown())")
        case Some("object") =>
          val props = j.field("properties").flatMap(_.obj).map(_.toList).getOrElse(Nil)
          val required = j.field("required").flatMap(_.array).map(_.flatMap(_.string).toSet).getOrElse(Set[String]())
          val closed = j.field("additionalProperties").flatMap(_.bool).contains(false)
          val rendered = props.map { kv =>
            expr(kv._2).right.map { e =>
              key(kv._1) + ": " + e + (if (required.contains(kv._1)) "" else ".optional()")
            }
          }
          rendered.collectFirst { case Left(e) => e } match {
            case Some(e) => Left(e)
            case None    =>
              Right("z.object({ " + rendered.map(_.right.get).mkString(", ") + " })" +
                    (if (closed) ".strict()" else ""))
          }
        case Some(other) => Left("unsupported type " + quote(other))
        case None        =>
          // the empty schema: any JSON (the stdlib `Json` type)
          if (j.objectFieldsOrEmpty.isEmpty) Right("z.unknown()")
          else Left("no recognised keyword in " + j.nospaces)
      }
    }

    private def seq(js: List[Json]): Either[String, List[String]] = {
      val rs = js.map(expr)
      rs.collectFirst { case Left(e) => e } match {
        case Some(e) => Left(e)
        case None    => Right(rs.map(_.right.get))
      }
    }
  }

  private def literal(j: Json): String =
    j.string.map(quote).orElse(j.number.map(n => n.toBigDecimal.toString))
      .orElse(j.bool.map(_.toString)).getOrElse(if (j.isNull) "null" else j.nospaces)

  /** A property name that is a plain identifier stays bare; anything else is
    * quoted, so a field named `data-source` still compiles. */
  private def key(k: String): String =
    if (k.nonEmpty && !k.head.isDigit && k.forall(c => c.isLetterOrDigit || c == '_' || c == '$')) k
    else quote(k)

  private def quote(s: String): String =
    "\"" + s.flatMap {
      case '"'  => "\\\""
      case '\\' => "\\\\"
      case '\n' => "\\n"
      case c    => c.toString
    } + "\""
}
