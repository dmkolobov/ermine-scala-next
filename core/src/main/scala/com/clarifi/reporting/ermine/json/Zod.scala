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
  * recursive or mutually recursive type -- is emitted as `z.lazy(() => X)`.
  * `tsc --strict` refuses a `const` whose inferred type would depend on
  * itself (TS7022), so every def of a recursive component is DECLARED as a
  * TypeScript type first (`export interface X {..}` for a record, `export
  * type X = | .. | ..` for a union: exactly what zod infers, see `Types`) and
  * its `const` annotated `z.ZodType<X>` -- zod's own recipe for recursion
  * (WP-32; until then these were `z.ZodTypeAny`, whose `z.infer` is `any`,
  * which is why client/src/props.ts hand-wrote the types).  A non-recursive
  * def stays `export type X = z.infer<typeof X>`.
  *
  * `renderBundle` writes several types into one module (`bin/ermine-schema
  * --zod M:T ...` and `--widgets`): each def once, short names, and the
  * widget registry.
  *
  * Keyword by keyword: integer -> `z.number().int()` (with `.min`/`.max` for
  * `Short`/`Byte`), `Long`'s string+pattern -> `z.string().regex(/^-?[0-9]+$/)`,
  * `format: date` -> `z.string().date()`, `date-time` -> `.datetime()`,
  * `uuid` -> `.uuid()`, an `anyOf` with a null arm -> `.nullable()`, a
  * property absent from `required` -> `.optional()`, `enum` -> `z.enum`, an
  * `oneOf` of objects that all pin `tag` -> `z.discriminatedUnion("tag", ...)`
  * (a relation's delivery arms all pin `kind`: `z.discriminatedUnion("kind",
  * ...)`, J3a), any other `anyOf` -> `z.union`, `minLength` -> `.min`,
  * an object -> `z.object({...}).strict()` -- or `.passthrough()` when the
  * schema says `additionalProperties: true`, which is the exporter's object
  * with a `Spread Json` field (J2b), since zod's default would STRIP the
  * merged keys -- `prefixItems` -> `z.tuple`, the
  * empty schema `{}` (the stdlib `Json` type) -> `z.unknown()`.
  */
object Zod {

  /** One type's zod: every `$defs` entry, then the root as `Schema`.  The
    * shape `bin/ermine-schema --zod -i M T` prints. */
  def render(schema: Json): Either[String, String] = {
    val defs: List[(String, Json)] =
      schema.field("$defs").flatMap(_.obj).map(_.toList).getOrElse(Nil).sortBy(_._1)
    plan(defs).right.flatMap { p =>
      val header = {
        val b = new StringBuilder
        b ++= "// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.\n"
        schema.field("$id").flatMap(_.string) foreach { id => b ++= "// source: " + id + "\n" }
        b ++= "// zod 3\n\nimport { z } from \"zod\";\n\n"
        b.toString
      }
      val rootBody = Json.obj(
        schema.objectFieldsOrEmpty
          .filterNot(f => f == "$schema" || f == "$id" || f == "$defs")
          .map(f => (f, schema.field(f).get)): _*)
      val root = p.ctx.expr(rootBody).left.map(msg => "root: " + msg)
      val all: List[Either[String, String]] = declarations(p, defs.toMap) :+ root.right.map { e =>
        "export const Schema = " + e + ";\nexport type Schema = z.infer<typeof Schema>;\n" }
      collect(all).right.map(xs => header + xs.mkString)
    }
  }

  // ---------------------------------------------------------------------
  // the multi-type bundle (WP-32)

  /** A requested root: its body (normally a `$ref`), the name it is exported
    * under (`None`: the short name of the def it refers to) and a label for
    * messages (`Module:Type`). */
  final case class Root(label: String, alias: Option[String], body: Json)

  /** A registry entry: the widget's name and the root (by label) its props are. */
  final case class Widget(name: String, root: String)

  /** Everything `bin/ermine-schema --zod M:T ...` / `--widgets` writes into one
    * module.
    *
    * {{{
    * <header lines>
    * import { z } from "zod";
    * export const Layout_Widgets_Format_RGB = z.object(..);          // one per $defs entry
    * export type Layout_Widgets_Format_RGB = z.infer<typeof ..>;     //   (non-recursive)
    * export type Layout_Widgets_Format_CellFormat = | {..} | {..};  // recursive: declared,
    * export const Layout_Widgets_Format_CellFormat: z.ZodType<Layout_Widgets_Format_CellFormat> = ..;
    * export type CellFormat = Layout_Widgets_Format_CellFormat;      // short names
    * export const CellFormatSchema = Layout_Widgets_Format_CellFormat;
    * export interface WidgetRegistry { table: TableProps; .. }      // --widgets only
    * export type WidgetName = keyof WidgetRegistry;
    * export const WIDGET_PROP_SCHEMAS: { [K in WidgetName]: z.ZodType<WidgetRegistry[K]> } = {..};
    * export const UNSUPPORTED_WIDGETS: readonly string[] = [..];
    * }}}
    *
    * SHORT NAMES.  A def that instantiates a data type at nothing but type
    * variables (`TableProps r` -> `Layout.Widgets.Table.TableProps__`) is
    * also exported under the type's own name (`TableProps`, `TablePropsSchema`)
    * when that name is unique in the bundle; a root's `=Alias` replaces its
    * def's short name.  A clash drops the short name of every def involved
    * and says so in a header comment, so an import of the lost name fails at
    * `tsc` rather than binding the wrong type. */
  def renderBundle(defs: List[(String, Json)], origins: Map[String, (String, Boolean)],
                   roots: List[Root], widgets: Option[(List[Widget], List[String])],
                   headerLines: List[String]): Either[String, String] =
    plan(defs).right.flatMap { p =>
      val bodies = defs.toMap
      def refOf(j: Json): Option[String] =
        if (j.objectFieldsOrEmpty == List("$ref"))
          j.field("$ref").flatMap(_.string).filter(_.startsWith("#/$defs/")).map(_.substring("#/$defs/".length))
        else None
      val reserved = Set("z", "WidgetRegistry", "WidgetName", "WIDGET_PROP_SCHEMAS", "UNSUPPORTED_WIDGETS", "Schema")
      val badAlias = roots.flatMap(_.alias).find(a => !isIdentifier(a) || reserved(a) || p.ts.values.exists(_ == a))
      val dupAlias = roots.flatMap(_.alias).groupBy(identity).collectFirst { case (a, as) if as.length > 1 => a }
      if (badAlias.isDefined) Left("the alias " + badAlias.get + " is not a free TypeScript identifier")
      else if (dupAlias.isDefined) Left("the alias " + dupAlias.get + " is given twice")
      else {
        // explicit aliases, and the defs they claim
        val aliased: List[(String, String)] =
          roots.flatMap(r => r.alias.flatMap(a => refOf(r.body).map(d => (d, a)))).distinct
        val aliasedDefs = aliased.map(_._1).toSet
        val taken = roots.flatMap(_.alias).toSet
        val candidates: List[(String, String)] = defs.map(_._1).flatMap { d =>
          origins.get(d).collect { case (short, true) if !aliasedDefs(d) => (d, short) } }
        val byShort = candidates.groupBy(_._2)
        val clashes = byShort.toList.filter { case (sh, ds) =>
          ds.length > 1 || taken(sh) || reserved(sh) || p.ts.values.exists(_ == sh) }.sortBy(_._1)
        val defaultShort: Map[String, String] =
          candidates.filterNot(c => clashes.exists(_._1 == c._2)).toMap
        val shorts: List[(String, String)] = defaultShort.toList ++ aliased
        val shortOf: Map[String, String] = defaultShort ++ aliased.reverse
        // a root with no alias and no def of its own cannot be named
        val rootName: List[Either[String, (Root, String)]] = roots.map { r =>
          r.alias.orElse(refOf(r.body).flatMap(shortOf.get)) match {
            case Some(n) => Right((r, n))
            case None    => Left(r.label + " has no short name (" +
              (refOf(r.body) match {
                case Some(d) => "the name of " + d + " clashes"
                case None    => "it is not a data type"
              }) + "); give it one with " + r.label + "=Name")
          }
        }
        collect(rootName).right.flatMap { named =>
          val rootNames = named.map { case (r, n) => (r.label, n) }.toMap
          val shortLines = new StringBuilder
          shorts.sortBy(_._2) foreach { case (d, sh) =>
            shortLines ++= "export type " + sh + " = " + p.ts(d) + ";\nexport const " + sh + "Schema = " + p.ts(d) + ";\n"
          }
          val inlineRoots: List[Either[String, String]] = named.collect {
            case (r, n) if refOf(r.body).isEmpty =>
              p.ctx.expr(r.body).left.map(m => r.label + ": " + m).right.map { e =>
                "export const " + n + "Schema = " + e + ";\nexport type " + n + " = z.infer<typeof " + n + "Schema>;\n" }
          }
          val exported = shorts.map(_._2) ++ named.collect { case (r, n) if refOf(r.body).isEmpty => n }
          val emittedNames = exported.flatMap(n => List(n, n + "Schema")) ++ p.ts.values ++ reserved
          val dupEmitted = emittedNames.groupBy(identity).collectFirst { case (n, ns) if ns.length > 1 => n }
          if (dupEmitted.isDefined) Left("two exports would both be named " + dupEmitted.get)
          else collect(declarations(p, bodies) ++ inlineRoots).right.flatMap { decls =>
            val registry: Either[String, String] = widgets match {
              case None => Right("")
              case Some((ws, unsupported)) =>
                val missing = ws.find(w => !rootNames.contains(w.root))
                if (missing.isDefined) Left("widget " + missing.get.name + ": no root " + missing.get.root)
                else {
                  val b = new StringBuilder
                  b ++= "// -------------------------------------------------------------- widgets\n\n"
                  b ++= "/** Widget registry name -> its props type: every `WidgetName T` term the scan found. */\n"
                  b ++= "export interface WidgetRegistry {\n"
                  ws foreach { w => b ++= "  " + key(w.name) + ": " + rootNames(w.root) + ";\n" }
                  b ++= "}\n\nexport type WidgetName = keyof WidgetRegistry;\n\n"
                  b ++= "/** Widget registry name -> the zod its props are validated with. */\n"
                  b ++= "export const WIDGET_PROP_SCHEMAS: { [K in WidgetName]: z.ZodType<WidgetRegistry[K]> } = {\n"
                  ws foreach { w => b ++= "  " + key(w.name) + ": " + rootNames(w.root) + "Schema,\n" }
                  b ++= "};\n\n"
                  b ++= "/** Names declared `WidgetName T` at an uninhabited `T` (a data type with no\n"
                  b ++= " *  constructors): reserved, with no props and no renderer. */\n"
                  b ++= "export const UNSUPPORTED_WIDGETS: readonly string[] = [" + unsupported.map(quote).mkString(", ") + "];\n"
                  Right(b.toString)
                }
            }
            registry.right.map { reg =>
              val h = new StringBuilder
              h ++= "// Generated from Ermine by bin/ermine-schema (com.clarifi.reporting.ermine.json.Zod) -- do not edit.\n"
              headerLines foreach { l => h ++= (if (l.isEmpty) "//\n" else "// " + l + "\n") }
              if (clashes.nonEmpty) {
                h ++= "//\n// no short name (the name clashes; use the qualified one):\n"
                clashes foreach { case (sh, ds) => h ++= "//   " + sh + " <- " + ds.map(_._1).sorted.mkString(", ") + "\n" }
              }
              h ++= "// zod 3\n\nimport { z } from \"zod\";\n\n"
              h.toString + decls.mkString +
                "// -------------------------------------------------------------- short names\n\n" +
                shortLines.toString + (if (reg.isEmpty) "" else "\n" + reg)
            }
          }
        }
      }
    }

  // ---------------------------------------------------------------------
  // shared: order, recursion, one declaration per def

  private final class Plan(val order: List[String], val recursive: Set[String],
                           val ts: Map[String, String], val ctx: Ctx, val types: Types)

  /** Dependency order over strongly connected components.  A component whose
    * every outside dependency is emitted is ready; all ready components go
    * out together, ordered by their first name, members alphabetically -- on
    * an acyclic graph exactly the old "ready names alphabetically" order.  A
    * def is RECURSIVE when its component has two members or a self-edge; a
    * reference to a def not emitted strictly before the referring one is
    * `z.lazy`, and only a recursive def can be such a target. */
  private def plan(defs: List[(String, Json)]): Either[String, Plan] = {
    val names = defs.map(_._1).sorted
    val ts = names.map(n => (n, identifier(n))).toMap
    val clash = ts.toList.groupBy(_._2).filter(_._2.length > 1)
    if (clash.nonEmpty)
      Left("two $defs names sanitise to the same TypeScript identifier: " +
           clash.toList.sortBy(_._1).map { case (id, ns) =>
             id + " <- " + ns.map(_._1).sorted.mkString(", ") }.mkString("; "))
    else {
      val bodies = defs.toMap
      val deps: Map[String, List[String]] =
        defs.map { case (n, j) => (n, refsIn(j).filter(bodies.contains).sorted) }.toMap

      // Tarjan, visiting names and edges in sorted order (deterministic)
      val index = scala.collection.mutable.HashMap[String, Int]()
      val low   = scala.collection.mutable.HashMap[String, Int]()
      val onStack = scala.collection.mutable.HashSet[String]()
      val stack = new scala.collection.mutable.Stack[String]()
      val comp  = scala.collection.mutable.HashMap[String, Int]()
      var next = 0
      var comps = 0
      def strong(v: String): Unit = {
        index(v) = next; low(v) = next; next += 1
        stack.push(v); onStack += v
        deps(v) foreach { w =>
          if (!index.contains(w)) { strong(w); low(v) = low(v) min low(w) }
          else if (onStack(w)) low(v) = low(v) min index(w)
        }
        if (low(v) == index(v)) {
          var w = ""
          while ({ w = stack.pop(); onStack -= w; comp(w) = comps; w != v }) ()
          comps += 1
        }
      }
      names foreach { n => if (!index.contains(n)) strong(n) }
      val members: Map[Int, List[String]] = names.groupBy(comp).map { case (c, ns) => (c, ns.sorted) }
      val recursive: Set[String] =
        names.filter(n => members(comp(n)).length > 1 || deps(n).contains(n)).toSet

      val order = new ListBuffer[String]
      val done = scala.collection.mutable.HashSet[String]()
      var todo: List[Int] = members.keys.toList.sortBy(c => members(c).head)
      while (todo.nonEmpty) {
        val ready = todo.filter(c => members(c).forall(n => deps(n).forall(d => comp(d) == c || done(d))))
        // a condensation is acyclic, so something is always ready
        val go = if (ready.isEmpty) List(todo.head) else ready
        go foreach { c => order ++= members(c); done ++= members(c) }
        todo = todo.filterNot(go.contains)
      }

      val pos = order.toList.zipWithIndex.toMap
      val lazyTargets: Set[String] =
        defs.flatMap { case (n, j) => refsIn(j).filter(d => bodies.contains(d) && pos(d) >= pos(n)) }.toSet
      Right(new Plan(order.toList, recursive, ts, new Ctx(ts, lazyTargets), new Types(ts, bodies)))
    }
  }

  /** One declaration per def, in plan order.  A non-recursive def is a
    * `const` and `z.infer` of it; a recursive one is DECLARED first -- the
    * TypeScript type of exactly what the zod accepts -- and the `const` is
    * annotated `z.ZodType<X>` (zod's recipe for recursion: `z.infer` of the
    * unannotated `const` would be circular, TS7022, and `z.ZodTypeAny` would
    * make it `any`).  Nothing here transforms, so input and output types are
    * the same and one type parameter is enough. */
  private def declarations(p: Plan, bodies: Map[String, Json]): List[Either[String, String]] =
    p.order.map { n =>
      val id = p.ts(n)
      p.ctx.expr(bodies(n)).right.flatMap { e =>
        if (!p.recursive(n))
          Right("export const " + id + " = " + e + ";\nexport type " + id + " = z.infer<typeof " + id + ">;\n\n")
        else p.types.declaration(id, n, bodies(n)).right.map { d =>
          d + "export const " + id + ": z.ZodType<" + id + "> = " + e + ";\n\n" }
      }.left.map(msg => "$defs." + n + ": " + msg)
    }

  private def collect[A](xs: List[Either[String, A]]): Either[String, List[A]] =
    xs.collectFirst { case Left(e) => e } match {
      case Some(e) => Left(e)
      case None    => Right(xs.map(_.right.get))
    }

  private def isIdentifier(s: String): Boolean =
    s.nonEmpty && (s.head.isLetter || s.head == '_' || s.head == '$') &&
      s.forall(c => c.isLetterOrDigit || c == '_' || c == '$')

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

  /** The TypeScript TYPE of what a schema accepts, written out -- used for a
    * recursive def, where `z.infer` cannot be.  It must be exactly the type
    * zod infers for the same schema, so it follows zod 3's inference, not
    * taste.  The annotation `z.ZodType<X>` only guarantees ONE direction:
    * the schema's output is assignable to X (a NARROWER X fails `tsc`).  A
    * WIDENED X is not caught by `tsc`; the eq-probe (assignability in both
    * directions, `scratch-widget-preview/wp32-s1-review/eq-probe.py`) is the
    * check that catches it, and WP-32 stage 2 registers it in the client
    * gate.  The rules:
    *
    *  - a property absent from `required` is optional (`.optional()`), AND so
    *    is a property whose type admits `undefined` (`z.unknown()`, the
    *    stdlib `Json` type): zod's `addQuestionMarks` makes both `k?:`;
    *  - a `.passthrough()` object is the fields `& { [k: string]: unknown }`;
    *  - `z.enum`/`z.literal` are literal unions, integers are `number`, a
    *    string with a format or a pattern is `string`;
    *  - `prefixItems` is a tuple, `items` an `Array<..>`, `{}` is `unknown`.
    *
    * A record at the top is an `interface`; anything else a `type`, a union
    * one arm per line in the `| {..}` shape client/src/props.ts used. */
  private final class Types(ts: Map[String, String], bodies: Map[String, Json]) {

    def declaration(id: String, defName: String, j: Json): Either[String, String] = {
      val doc = "/** " + defName + " */\n"
      val arms = j.field("oneOf").flatMap(_.array)
        .orElse(j.field("anyOf").flatMap(_.array).filterNot(as => nullableArm(as).isDefined))
      if (isPlainObject(j))
        fields(j).right.map { fs =>
          doc + "export interface " + id + " {\n" + fs.map("  " + _ + ";\n").mkString + "}\n" }
      else if (arms.isDefined && arms.get.length > 1)
        seq(arms.get).right.map { ts => doc + "export type " + id + " =\n" + ts.map("  | " + _).mkString("\n") + ";\n" }
      else apply(j).right.map(t => doc + "export type " + id + " = " + t + ";\n")
    }

    private def isPlainObject(j: Json): Boolean =
      j.field("type").flatMap(_.string).contains("object") &&
        !j.field("additionalProperties").flatMap(_.bool).contains(true)

    private def nullableArm(alts: List[Json]): Option[Json] = {
      val (nulls, rest) = alts.partition(a => a.field("type").flatMap(_.string).contains("null"))
      if (nulls.nonEmpty && rest.length == 1) Some(rest.head) else None
    }

    /** Does zod's output type for `j` include `undefined`? */
    private def admitsUndefined(j: Json, seen: Set[String] = Set()): Boolean = {
      val ref = j.field("$ref").flatMap(_.string).map(_.stripPrefix("#/$defs/"))
      if (ref.isDefined)
        !seen(ref.get) && bodies.get(ref.get).exists(b => admitsUndefined(b, seen + ref.get))
      else {
        val alts = j.field("anyOf").flatMap(_.array).orElse(j.field("oneOf").flatMap(_.array))
        if (alts.isDefined) alts.get.exists(a => admitsUndefined(a, seen))
        else j.objectFieldsOrEmpty.isEmpty
      }
    }

    private def fields(j: Json): Either[String, List[String]] = {
      val props = j.field("properties").flatMap(_.obj).map(_.toList).getOrElse(Nil)
      val required = j.field("required").flatMap(_.array).map(_.flatMap(_.string).toSet).getOrElse(Set[String]())
      collect(props.map { case (k, v) =>
        apply(v).right.map { t =>
          key(k) + (if (required.contains(k) && !admitsUndefined(v)) ": " else "?: ") + t }
      })
    }

    def apply(j: Json): Either[String, String] = {
      val ref    = j.field("$ref").flatMap(_.string)
      val const  = j.field("const")
      val enums  = j.field("enum").flatMap(_.array)
      val anyOf  = j.field("anyOf").flatMap(_.array)
      val oneOf  = j.field("oneOf").flatMap(_.array)
      val tyName = j.field("type").flatMap(_.string)
      if (ref.isDefined) {
        val r = ref.get
        if (!r.startsWith("#/$defs/")) Left("unsupported $ref " + r)
        else ts.get(r.substring("#/$defs/".length)).toRight("dangling $ref " + r)
      }
      else if (const.isDefined) Right(literal(const.get))
      else if (enums.isDefined) Right(enums.get.map(literal).mkString(" | "))
      else if (anyOf.isDefined) nullableArm(anyOf.get) match {
        case Some(inner) => apply(inner).right.map(_ + " | null")
        case None        => seq(anyOf.get).right.map(_.mkString(" | "))
      }
      else if (oneOf.isDefined) seq(oneOf.get).right.map(_.mkString(" | "))
      else tyName match {
        case Some("null")                 => Right("null")
        case Some("boolean")              => Right("boolean")
        case Some("integer") | Some("number") => Right("number")
        case Some("string")               => Right("string")
        case Some("array") =>
          val prefix = j.field("prefixItems").flatMap(_.array)
          val items  = j.field("items")
          if (prefix.isDefined) seq(prefix.get).right.map(ts => "[" + ts.mkString(", ") + "]")
          else if (items.isDefined) apply(items.get).right.map(t => "Array<" + t + ">")
          else if (j.field("maxItems").flatMap(_.number).exists(_.toBigDecimal == BigDecimal(0))) Right("[]")
          else Right("unknown[]")
        case Some("object") =>
          fields(j).right.map { fs =>
            val obj = if (fs.isEmpty) "{}" else "{ " + fs.mkString("; ") + " }"
            if (j.field("additionalProperties").flatMap(_.bool).contains(true))
              "(" + obj + " & { [k: string]: unknown })"
            else obj
          }
        case Some(other) => Left("unsupported type " + quote(other))
        case None =>
          if (j.objectFieldsOrEmpty.isEmpty) Right("unknown")
          else Left("no recognised keyword in " + j.nospaces)
      }
    }

    private def seq(js: List[Json]): Either[String, List[String]] = collect(js.map(apply))
  }

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
        // a data type's constructors pin `tag`; a relation's delivery
        // arms pin `kind` (Wire.Kind)
        val discriminator = List("tag", Wire.Kind).find(d => alts.nonEmpty && alts.forall(a =>
          a.field("properties").flatMap(_.field(d)).flatMap(_.field("const")).flatMap(_.string).isDefined))
        seq(alts).right.map { es =>
          discriminator match {
            case Some(d) => "z.discriminatedUnion(" + quote(d) + ", [" + es.mkString(", ") + "])"
            case None    => "z.union([" + es.mkString(", ") + "])"
          }
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
          val additional = j.field("additionalProperties").flatMap(_.bool)
          val closed = additional.contains(false)
          // `additionalProperties: true` is the exporter's spread object
          // (Stage 2b): zod's default STRIPS unknown keys, which would throw
          // the merged keys away, so such an object is `.passthrough()`
          val open   = additional.contains(true)
          val rendered = props.map { kv =>
            expr(kv._2).right.map { e =>
              key(kv._1) + ": " + e + (if (required.contains(kv._1)) "" else ".optional()")
            }
          }
          rendered.collectFirst { case Left(e) => e } match {
            case Some(e) => Left(e)
            case None    =>
              Right("z.object({ " + rendered.map(_.right.get).mkString(", ") + " })" +
                    (if (closed) ".strict()" else if (open) ".passthrough()" else ""))
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
