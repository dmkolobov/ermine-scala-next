package com.clarifi.reporting.ermine

import scalaparsers.Loc
import java.util.concurrent.ConcurrentHashMap
import scala.collection.immutable.List

/** The declaration a `data` type's `Con` carries: its constructors in
  * source order, each with its existential binders and field types.
  *
  * Before this the checker attached an anonymous `ConDecl { def desc =
  * "data" }` and the ordered constructor list was lost after load; the
  * JSON encoder (`json/Encode.scala`) needs to know whether a type is
  * all-nullary (encoded as a string enum) and the schema exporter needs the
  * field types.  tracker/JSON-API-DESIGN.md §2.3, §3.1 item 1.
  *
  * `constructors` is by-name: `Session.processTypeDefComponent` builds the
  * `Con` before the component's type map is complete, and the field types
  * are substituted through that map on first use.
  *
  * `Con` equality is by name only (Type.scala), so carrying this decl does
  * not disturb `.ei` interfaces or the G1 oracle.
  */
final class DataConDecl(
  val typeName: Global,
  val loc: Loc,
  val kindArgs: List[KindVar],
  val typeArgs: List[TypeVar],
  cs: => List[DataConDecl.Constructor]
) extends ConDecl {
  def desc = "data"
  lazy val constructors: List[DataConDecl.Constructor] = cs
  /** Every constructor nullary: the wire form is the constructor name. */
  def isEnum: Boolean = constructors.nonEmpty && constructors.forall(_.fields.isEmpty)
  def constructor(g: Global): Option[DataConDecl.Constructor] = constructors.find(_.name == g)
  override def toString = "DataConDecl(" + typeName + ")"
}

object DataConDecl {
  /** Field names are `None` until named constructor fields land (design
    * note §3.1 item 2, Stage 1); the runtime stays positional either way. */
  final case class Constructor(name: Global, existentials: List[TypeVar], fields: List[(Option[String], Type)])

  /** Constructor name -> the declaration it belongs to.
    *
    * A runtime `Data` node carries only its constructor's `Global`, and the
    * FFI primitive `toJson#` runs without a `SessionEnv` in reach, so the
    * lookup is process-wide.  Entries are facts about a declaration
    * (module + name -> shape); reloading a module re-registers and
    * overwrites, and the `SessionEnv.cons` map (which carries the same decl
    * on the type's `Con`) remains the per-session source of truth for
    * callers that have an env.  Two sessions in one JVM defining the same
    * module.name with different shapes (only the test fixture does this)
    * see the last writer.
    */
  private val byConstructor = new ConcurrentHashMap[Global, DataConDecl]
  private val byType        = new ConcurrentHashMap[Global, DataConDecl]

  def register(decl: DataConDecl, constructorNames: List[Global]): DataConDecl = {
    constructorNames.foreach(byConstructor.put(_, decl))
    byType.put(decl.typeName, decl)
    decl
  }

  def forConstructor(g: Global): Option[DataConDecl] = Option(byConstructor.get(g))
  def forType(g: Global): Option[DataConDecl]        = Option(byType.get(g))

  /** Every registered declaration, one entry per type, in no particular order. */
  def all: List[DataConDecl] = {
    // a manual loop: JavaConverters is deprecated on Scala 3 and
    // CollectionConverters does not exist on 2.11 (this file is built on both)
    val buf = scala.collection.mutable.ListBuffer[DataConDecl]()
    val it = byType.values.iterator // byType, so a zero-constructor type (Void) is listed too
    while (it.hasNext) buf += it.next
    buf.toList.distinct
  }
}
