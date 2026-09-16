package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.json.{ Decode, Encode, Schema, Validate }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.session.{ Session, SessionEnv }

import org.scalacheck._
import Prop.{ Result => _, _ }
import argonaut.Json

/** The PARAMS DECODER (core/json/Decode.scala, tracker/JSON-API-DESIGN.md
  * §3.3, Stage 2a): type-directed `JSON => Runtime`, the inverse of `Encode`
  * and the executable reading of the schema `Schema` exports.
  *
  * The cases are TestSchema's: `TestSchema.shape` generates a random Ermine
  * type (with the declarations it needs) and random values of it, loaded as
  * `module Test`.  Stage 2a added the scalar rows the vocabulary lacked
  * (Short, Byte, Float, Char, Date, Timestamp, GUID), Nullable, the native
  * collections, Vector and the stdlib `Json` type there, so TestSchema's own
  * encode/schema property covers them too.
  *
  *  (a)  round trip: `decode(ty, encode v)` is `v`, compared by a stack-safe
  *       walk that also compares the JVM classes of primitives (`==` alone
  *       says `Prim(3: Int) == Prim(3: Short)`);
  *  (b)  agreement: over the valid document and random single mutations of
  *       it, `Validate` accepts iff `decode` succeeds, less the three schema
  *       gaps pinned below;
  *  (c)  error paths: a mutation at p is reported at p or its parent,
  *       distribution printed;
  *  (d)  entry: poisoned types are refused at the poison's path, closed ones
  *       accepted;
  *  (s)  Stage 2b: a constructor with a `Spread Json` field is OPEN -- the
  *       keys it does not declare are gathered into the spread in document
  *       order, which is the inverse of the encoder's merge;
  *  (e)  scale: 100,000 records, and documents far deeper than argonaut's
  *       own parser can read.
  */
object TestDecode extends Properties("Ermine JSON Decode") {
  private lazy val ermineFixture = ErmineFixture()
  import ermineFixture._
  import TestSchema.{ Shape, samples }

  val imps: Map[String, ImportSpec] = TestSchema.imps

  // ---------------------------------------------------------------------
  // one generated case

  def source(sh: Shape, v: String): String =
    (sh.decls.distinct ++ List("gv : " + sh.ty, "gv = " + v)).mkString("\n")

  /** Load `gv : ty; gv = v` into `s`; the published type and the value. */
  def load(sh: Shape, v: String)(implicit s: SessionEnv): (Type, Runtime) = {
    loadStatements(source(sh, v), imps)
    Session.eval("gv", imps)
  }

  def parse(text: String): Json = argonaut.Parse.parse(text).fold(e => sys.error("argonaut: " + e), identity)

  // ---------------------------------------------------------------------
  // a stack-safe, class-strict comparison of two runtime values

  private final case class Raw(v: Any)

  /** `None` when `a` and `b` are the same value: the same constructors, the
    * same record keys, and primitives of the same JVM class that are
    * `equals`.  Thunks are forced; the walk keeps its own stack, so a
    * 100,000-element list or a 100,000-deep value compares. */
  def same(a: Runtime, b: Runtime): Option[String] = {
    /** Which null-carrying WRAPPER a value is, when its payload is one the
      * encoder collapses into the same `null`: `Just JNull` and `Nothing`
      * (and `Just# JNull` and `Nothing#`) go out identically, since a `Json`
      * value can be a null of its own, and the decoder can only choose one
      * preimage -- it chooses the empty one.  The round trip is up to THAT
      * ambiguity and no more: the wrapper itself is still compared, so a
      * decoder that answered a `Maybe`'s `Nothing` where a native `Maybe#`'s
      * belongs is still caught (and `(map)` pins both with `==`).  Nested
      * `Maybe (Maybe a)` is refused outright for the same reason; `Maybe
      * Json` is not, because a raw-JSON parameter is worth having.
      *
      * A native container stores its elements unwrapped (`Some(x)` rather
      * than `Prim(Some(x))`), so both spellings count. */
    def nullKind(x0: Any): Option[String] = {
      val x = x0 match { case r: Runtime => Runtime.swhnf(r); case o => o }
      x match {
        case Data(Global("Builtin", "Nothing", _), _)     => Some("Maybe")
        case Data(Global("Builtin", "Just", _), Array(v)) => if (collapsed(v)) Some("Maybe") else None
        case Prim(None)                                   => Some("Maybe#")
        case Prim(Some(v))                                => if (collapsed(v)) Some("Maybe#") else None
        case None                                         => Some("Maybe#")
        case Some(v)                                      => if (collapsed(v)) Some("Maybe#") else None
        case _                                            => None
      }
    }
    /** A payload the encoder writes as a bare `null`. */
    def collapsed(x0: Any): Boolean = {
      val x = x0 match { case r: Runtime => Runtime.swhnf(r); case o => o }
      x match {
        case Data(Global("Json", "JNull", _), _) => true
        case other                               => nullKind(other).isDefined
      }
    }
    var stack: List[(String, Any, Any)] = List(("$", a, b))
    var bad: Option[String] = None
    def cls(x: Any) = if (x == null) "null" else x.getClass.getName
    while (stack.nonEmpty && bad.isEmpty) {
      val (p, x0, y0) = stack.head
      stack = stack.tail
      def fail(why: String): Unit = bad = Some(p + ": " + why)
      def push(kids: List[(String, Any, Any)]): Unit = stack = kids ++ stack
      val x = x0 match { case r: Runtime => Runtime.swhnf(r); case o => o }
      val y = y0 match { case r: Runtime => Runtime.swhnf(r); case o => o }
      (x, y) match {
        case (u, w) if nullKind(u).isDefined && nullKind(u) == nullKind(w) => ()
        case (Data(g, as), Data(h, bs)) =>
          if (g != h) fail("constructor " + g + " against " + h)
          else if (as.length != bs.length) fail(g.toString + " with " + as.length + " against " + bs.length + " arguments")
          else push(as.indices.toList.map(i => (p + "." + g.string + "[" + i + "]", as(i), bs(i))))
        case (Arr(as), Arr(bs)) =>
          if (as.length != bs.length) fail("tuples of " + as.length + " and " + bs.length)
          else push(as.indices.toList.map(i => (p + "[" + i + "]", as(i), bs(i))))
        case (r: Rec, q: Rec) =>
          if (r.t.keySet != q.t.keySet) fail("record keys " + r.t.keySet + " against " + q.t.keySet)
          else push(r.t.keys.toList.sorted.map(k => (p + "." + k, r.t(k), q.t(k))))
        case (Prim(u), Prim(w)) => push(List((p, Raw(u), Raw(w))))
        case (Box(u), Box(w))   => push(List((p, Raw(u), Raw(w))))
        case (Raw(u), Raw(w)) => (u, w) match {
          case (null, null) => ()
          case (e, f) if nullKind(e).isDefined && nullKind(e) == nullKind(f) => ()
          case (ru: Runtime, rw: Runtime) => push(List((p, ru, rw)))
          case (lu: List[_], lw: List[_]) =>
            if (lu.length != lw.length) fail("native lists of " + lu.length + " and " + lw.length)
            else push(lu.zip(lw).zipWithIndex.map { case ((e, f), i) => (p + "[" + i + "]", Raw(e), Raw(f)) })
          case (vu: Vector[_], vw: Vector[_]) =>
            if (vu.length != vw.length) fail("vectors of " + vu.length + " and " + vw.length)
            else push(vu.toList.zip(vw.toList).zipWithIndex.map { case ((e, f), i) => (p + "[" + i + "]", Raw(e), Raw(f)) })
          case (Some(e), Some(f)) => push(List((p + "?", Raw(e), Raw(f))))
          case (None, None) => ()
          case ((e1, f1), (e2, f2)) => push(List((p + "[0]", Raw(e1), Raw(e2)), (p + "[1]", Raw(f1), Raw(f2))))
          case _ =>
            if (u == null || w == null || u.getClass != w.getClass || !u.equals(w))
              fail("primitive " + u + " (" + cls(u) + ") against " + w + " (" + cls(w) + ")")
        }
        case (bx: Bottom, _) => fail("the first value is an error: " + bx.exn)
        case (_, by: Bottom) => fail("the second value is an error: " + by.exn)
        case _ => fail("a " + cls(x) + " against a " + cls(y))
      }
    }
    bad
  }

  // ---------------------------------------------------------------------
  // (a) round trip

  /** The complaint, or None: decode(ty, encode v) is v, both from the
    * in-memory document and from its text (what the runner receives). */
  def roundTrip(sh: Shape, v: String): Option[String] =
    try session { implicit s =>
      val (ty, rt) = load(sh, v)
      Encode.toArgonaut(rt) match {
        case Left(e) => Some("encode refused " + sh.ty + ": " + e.report + "\n" + source(sh, v))
        case Right(doc) =>
          val text = Schema.compact(doc)
          List(("in memory", doc), ("through text", parse(text))).flatMap { case (how, d) =>
            Decode.decode(ty, d) match {
              case Left(e)     => List(how + ": " + e.report)
              case Right(back) => same(back, rt).toList.map(how + ": " + _)
            }
          }.headOption.map(_ + "\n  type " + sh.ty + "\n  doc " + text + "\n" + source(sh, v))
      }
    } catch { case e: Throwable => Some("threw " + e + "\n" + source(sh, v)) }

  /** The Stage 2a vocabulary, each of which must turn up in (a)'s cases. */
  private val vocabulary: List[(String, String => Boolean)] = List(
    ("Short", _.contains("Short")), ("Byte", _.contains("Byte")), ("Float", _.contains("Float")),
    ("Char", _.contains("Char")), ("Date", _.contains("Date")), ("Timestamp", _.contains("Timestamp")),
    ("GUID", _.contains("GUID")), ("Nullable", _.contains("Nullable")), ("Vector", _.contains("Vector_V")),
    ("List#", _.contains("List#")), ("Maybe#", _.contains("Maybe#")), ("Pair#", _.contains("Pair#")),
    ("Json", _.contains("Json")), ("record", _.contains("{sf")), ("record-style data", _.contains("c1 { ")),
    ("Maybe", _.contains("Maybe ")),
    // Stage 2b: a merged `Spread Json` field must reach the round trip too
    ("Spread", _.contains("Spread Json")))

  property("(a) decode(ty, encode v) is v (200 cases)") = {
    val cases = samples(TestSchema.typeAndValue, 200, seed0 = 20260916L)
    // J3a put relations in the vocabulary behind `shape`'s `rels` flag, which
    // `typeAndValue` leaves false: a relation is not encodable by
    // `Encode.toArgonaut` and not decodable at all, and `(d3)` below is where
    // that pair of refusals is checked.
    val withRels = cases.count(_._1.rels > 0)
    val bad = cases.flatMap { case (sh, v) => roundTrip(sh, v) }
    val seen = vocabulary.map { case (name, hit) => (name, cases.count { case (sh, v) => hit(source(sh, v)) }) }
    println("  decode round trip: " + cases.length + " cases; vocabulary " +
            seen.map { case (n, k) => n + " " + k }.mkString(", "))
    val missing = seen.filter(_._2 == 0).map(_._1)
    (bad.isEmpty :| (bad.length + " failed\n" + bad.take(3).mkString("\n---\n"))) &&
      ((cases.length == 200) :| ("generated " + cases.length + " of 200 cases")) &&
      ((withRels == 0) :| (withRels + " cases carry a relation: typeAndValue is meant to be relation-free")) &&
      (missing.isEmpty :| ("never generated: " + missing.mkString(", ")))
  }

  property("(a2) the same, with ScalaCheck's own generator") =
    forAllNoShrink(TestSchema.typeAndValue) { (tv: (Shape, String)) =>
      roundTrip(tv._1, tv._2) match {
        case None    => proved
        case Some(m) => falsified :| m
      }
    }

  property("(a3) negative numbers, extremes, and the corners the generator leaves out") = sessionProof { implicit s =>
    def rt(decls: String, ty: String, v: String): Unit = {
      val sh = Shape(ty, decls.split("\n").filter(_.nonEmpty).toList, Gen.const(v))
      roundTrip(sh, v).foreach(m => sys.error(m))
    }
    rt("", "Int", "(0 - 2147483647 - 1)")
    rt("", "Int", "2147483647")
    rt("", "Long", "(0L - 9223372036854775807L - 1L)")
    rt("", "Long", "9223372036854775807L")
    rt("", "Short", "(0s - 32767s - 1s)")
    rt("", "Byte", "(0b - 127b - 1b)")
    rt("", "Double", "(0.0 - 123456789.125)")
    rt("", "Double", "0.000001")
    rt("", "Float", "0.1f")
    rt("", "Date", "@1970/1/1")
    rt("", "Date", "@9999/12/31")
    rt("", "Timestamp", "(timestampFromLong (0L - 1L))")
    rt("", "Timestamp", "(timestampFromLong 253402300799999L)")
    rt("", "String", "\"\\\"\\\\\\n\"")
    rt("", "Char", "' '")
    rt("", "(Maybe Int)", "Nothing")
    rt("", "(List (Maybe String))", "[Just \"a\", Nothing]")
    rt("", "()", "()")
    rt("", "(List ())", "[(), ()]")
    // a record-style Maybe (Maybe a) field: absent is Nothing, null is Just Nothing
    rt("data Mm = Mm { mmA : Maybe (Maybe Int), mmB : Int }", "(List Mm)", "[Mm Nothing 1, Mm (Just Nothing) 2, Mm (Just (Just 3)) 3]")
    // a PHANTOM parameter at a concrete type, and a type alias
    rt("data Ph a = Ph Int", "(Ph String)", "(Ph 3)")
    rt("type Ints = List Int", "Ints", "[1, 2]")
    // a Nullable carries the nullable witness `Null Int` carries
    rt("", "(List (Nullable String))", "[Null String, Some \"x\"]")
  }

  // ---------------------------------------------------------------------
  // (b) + (c): agreement with the validator, and where errors are reported

  sealed abstract class Seg
  final case class K(k: String) extends Seg
  final case class I(i: Int) extends Seg
  def render(p: List[Seg]): String = "$" + p.map { case K(k) => "." + k; case I(i) => "[" + i + "]" }.mkString

  /** Every node with its path, pre-order (generated documents are small). */
  def nodes(j: Json, p: List[Seg] = Nil): List[(List[Seg], Json)] =
    (p, j) :: (j.array match {
      case Some(xs) => xs.zipWithIndex.flatMap { case (x, i) => nodes(x, p :+ I(i)) }
      case None => j.obj.map(_.toList.flatMap { case (k, v) => nodes(v, p :+ K(k)) }).getOrElse(Nil)
    })

  /** `j` with the node at `p` replaced by `f` of it. */
  def update(j: Json, p: List[Seg], f: Json => Json): Json = p match {
    case Nil => f(j)
    case K(k) :: rest => Json.obj(j.obj.get.toList.map { case (k2, v) => (k2, if (k2 == k) update(v, rest, f) else v) }: _*)
    case I(i) :: rest => Json.array(j.array.get.zipWithIndex.map { case (v, i2) => if (i2 == i) update(v, rest, f) else v }: _*)
  }

  /** One single mutation: its kind, the document, and the path it is at. */
  final case class Mutation(kind: String, doc: Json, at: List[Seg])

  private val replacements: List[Json] = List(
    Json.jNull, Json.jBool(true), Json.jNumber(0), Json.jNumber(-1), Json.jNumber(1.5).get, Json.jNumber(300),
    Json.jNumber(40000), Json.jNumber(2147483648L), Json.jNumber(BigDecimal("1e400")),
    Json.jString(""), Json.jString("x"), Json.jString("xy"), Json.jString("12"), Json.jString("-7"),
    Json.jString("99999999999999999999"), Json.jString("2026-02-30"), Json.jString("2026-09-16"),
    Json.jString("2026-09-16T12:00:00.000Z"), Json.jString("2026-09-16T12:00:00+02:00"),
    Json.jString("3f2504e0-4f89-11d3-9a0c-0305e82c3301"), Json.jString("1-1-1-1-1"),
    Json.jEmptyArray, Json.jEmptyObject)

  def mutation(doc: Json): Gen[Mutation] = {
    val all = nodes(doc)
    val objects = all.filter(_._2.obj.isDefined)
    val arrays  = all.filter(_._2.array.isDefined)
    val strings = all.flatMap(_._2.string).distinct
    val tags    = all.filter { case (p, j) => p.lastOption == Some(K("tag")) }
    def pick[A](xs: List[A]): Gen[A] = Gen.oneOf(xs)
    val kinds: List[Gen[Mutation]] = List(
      for { (p, _) <- pick(all); r <- pick(replacements) } yield Mutation("replace", update(doc, p, _ => r), p),
      for { (p, j) <- pick(all) } yield {
        val r = j.number.map(n => Json.jNumber(n.toBigDecimal + BigDecimal("0.5")))
          .orElse(j.string.map(s => Json.jString(s + "x")))
          .orElse(j.bool.map(b => Json.jBool(!b)))
          .getOrElse(Json.jNull)
        Mutation("tweak", update(doc, p, _ => r), p)
      }) ++
      (if (objects.exists(_._2.obj.get.fields.nonEmpty)) List(
        for { (p, o) <- pick(objects.filter(_._2.obj.get.fields.nonEmpty)); k <- pick(o.obj.get.fields) }
        yield Mutation("drop key", update(doc, p, j => Json.obj(j.obj.get.toList.filter(_._1 != k): _*)), p :+ K(k)))
       else Nil) ++
      (if (objects.nonEmpty) List(
        for { (p, _) <- pick(objects) }
        yield Mutation("add key", update(doc, p, j => Json.obj((j.obj.get.toList :+ ("zz" -> Json.jNull)): _*)), p :+ K("zz")))
       else Nil) ++
      (if (arrays.exists(_._2.array.get.nonEmpty)) List(
        for { (p, a) <- pick(arrays.filter(_._2.array.get.nonEmpty)); i <- Gen.choose(0, a.array.get.length - 1) }
        yield Mutation("drop element", update(doc, p, j => Json.array(j.array.get.zipWithIndex.filter(_._2 != i).map(_._1): _*)), p :+ I(i)))
       else Nil) ++
      (if (arrays.nonEmpty) List(
        for { (p, a) <- pick(arrays); extra <- Gen.oneOf(Json.jNull, a.array.get.lastOption.getOrElse(Json.jNull)) }
        yield Mutation("append element", update(doc, p, j => Json.array((j.array.get :+ extra): _*)), p :+ I(a.array.get.length)))
       else Nil) ++
      (if (tags.nonEmpty && strings.length > 1) List(
        for { (p, t) <- pick(tags); s <- pick(strings.filter(x => Some(x) != t.string)) }
        yield Mutation("retag", update(doc, p, _ => Json.jString(s)), p))
       else Nil)
    Gen.oneOf(kinds).flatMap(identity)
  }

  /** How a decoder error path relates to the mutation's path. */
  def relation(err: String, at: List[Seg]): String = {
    val p = render(at)
    val parent = if (at.isEmpty) None else Some(render(at.init))
    if (err == p) "same"
    else if (parent.contains(err)) "parent"
    else if (err.startsWith(p)) "deeper"
    else if (at.nonEmpty && err.startsWith(render(at.init))) "sibling"
    else "elsewhere"
  }

  /** The schema cannot say these, so the validator accepts what the decoder
    * refuses: Int has no bounds (`{"type":"integer"}`), Long only a digit
    * pattern, Double/Float no finite range.  Pinned below. */
  def knownGap(e: Decode.Error): Boolean =
    List("Int", "Long", "Double", "Float").exists(t => e.message.contains("is out of the range of " + t))

  final case class Tally(valid: Int, invalid: Int, gaps: Int, disagreements: List[String],
                         paths: Map[(String, String), Int])

  def agreement(sh: Shape, v: String, seed: Long): Tally =
    try session { implicit s =>
      val (ty, rt) = load(sh, v)
      val schema = Schema.exportType(ty, "Test").fold(e => sys.error("export refused: " + e.report), identity)
      val doc = Encode.toArgonaut(rt).fold(e => sys.error("encode refused: " + e.report), identity)
      val p = Gen.Parameters.default.withSize(12)
      val muts = (0 until 12).toList.flatMap(i => mutation(doc).apply(p, rng.Seed(seed * 31 + i)))
      var valid, invalid, gaps = 0
      val dis = List.newBuilder[String]
      val paths = scala.collection.mutable.Map[(String, String), Int]()
      (Mutation("none", doc, Nil) :: muts).foreach { m =>
        val errs = Validate.check(schema, m.doc)
        val dec = Decode.decode(ty, m.doc)
        (errs.isEmpty, dec.right.flatMap(r => same(r, r).map(b => Decode.Error("$", b)).toLeft(r))) match {
          case (true, Right(_)) => valid += 1
          case (false, Left(e)) =>
            invalid += 1
            val key = (m.kind, relation(e.path, m.at))
            paths(key) = paths.getOrElse(key, 0) + 1
          case (true, Left(e)) if knownGap(e) => gaps += 1
          case (true, Left(e)) =>
            dis += ("validator accepts, decoder refuses (" + m.kind + " at " + render(m.at) + "): " + e.report +
                    "\n  doc " + Schema.compact(m.doc) + "\n  type " + sh.ty + "\n" + source(sh, v))
          case (false, Right(_)) =>
            dis += ("validator refuses, decoder accepts (" + m.kind + " at " + render(m.at) + "): " + errs.mkString("; ") +
                    "\n  doc " + Schema.compact(m.doc) + "\n  type " + sh.ty + "\n" + source(sh, v))
        }
      }
      Tally(valid, invalid, gaps, dis.result(), paths.toMap)
    } catch { case e: Throwable => Tally(0, 0, 0, List("threw " + e + "\n" + source(sh, v)), Map()) }

  property("(b)+(c) Validate accepts iff decode succeeds; errors at the mutation or its parent (150 cases x 13 documents)") = {
    val cases = samples(TestSchema.typeAndValue, 150, seed0 = 20260917L)
    val withRels = cases.count(_._1.rels > 0) // relation-free by construction; see (a) and (d3)
    val tallies = cases.zipWithIndex.map { case ((sh, v), i) => agreement(sh, v, 7000L + i) }
    val valid = tallies.map(_.valid).sum
    val invalid = tallies.map(_.invalid).sum
    val gaps = tallies.map(_.gaps).sum
    val dis = tallies.flatMap(_.disagreements)
    val paths = tallies.flatMap(_.paths.toList).groupBy(_._1).map { case (k, vs) => (k, vs.map(_._2).sum) }
    println("  decode agreement: " + cases.length + " cases, " + (valid + invalid + gaps + dis.length) +
            " documents: " + valid + " valid, " + invalid + " invalid, " + gaps + " pinned schema gaps, " +
            dis.length + " disagreements")
    println("  decode error paths (mutation kind / where the decoder reported it):")
    paths.toList.sortBy(_._1).foreach { case ((kind, rel), n) => println("    " + kind + " / " + rel + ": " + n) }
    // every mutation kind but retag is reported at the mutation or its parent
    val strays = paths.toList.filter { case ((kind, rel), _) => kind != "retag" && rel != "same" && rel != "parent" }
    (dis.isEmpty :| (dis.length + " disagreements\n" + dis.take(3).mkString("\n---\n"))) &&
      (strays.isEmpty :| ("errors reported away from the mutation: " + strays.mkString(", "))) &&
      // not vacuous: both verdicts occur, in quantity
      ((valid > 150 && invalid > 300) :| ("valid " + valid + ", invalid " + invalid)) &&
      ((withRels == 0) :| (withRels + " cases carry a relation: the agreement property is meant to be relation-free"))
  }

  property("(b2) the validator gaps the agreement property skips, pinned") = sessionProof { implicit s =>
    loadStatements("field sfInt : Int", imps)
    def both(ty: String, j: Json): (List[String], Either[Decode.Error, Runtime]) = {
      val t = Session.eval("[] : List (" + ty + ")", imps)._1 match {
        case AppT(_, elem) => elem
        case other => sys.error("unexpected " + other)
      }
      val schema = Schema.exportType(t, "Test").fold(e => sys.error(e.report), identity)
      (Validate.check(schema, j), Decode.decode(t, j))
    }
    def gap(ty: String, j: Json, why: String): Unit = both(ty, j) match {
      case (Nil, Left(e)) => assert(knownGap(e) || e.message.contains(why), ty + " " + j.nospaces + ": " + e.report)
      case other => sys.error(ty + " " + j.nospaces + ": expected the validator to accept and the decoder to refuse, got " + other)
    }
    def agree(ty: String, j: Json, ok: Boolean): Unit = both(ty, j) match {
      case (Nil, Right(_)) if ok => ()
      case (_ :: _, Left(_)) if !ok => ()
      case other => sys.error(ty + " " + j.nospaces + ": expected both to " + (if (ok) "accept" else "refuse") + ", got " + other)
    }
    // (1) Int has no bounds in the schema
    gap("Int", Json.jNumber(2147483648L), "range")
    // (2) Long is only a digit pattern
    gap("Long", Json.jString("99999999999999999999"), "range")
    // (3) Double and Float have no finite range
    gap("Double", Json.jNumber(BigDecimal("1e400")), "range")
    gap("Float", Json.jNumber(1e39).get, "range")
    // (4) Java's `$` also matches before a final newline; zod's (ECMAScript) does not
    gap("Long", Json.jString("12\n"), "decimal")
    // (5) an instant java.sql.Timestamp / java.util.Date cannot hold
    gap("Timestamp", Json.jString("+999999999-12-31T23:59:59Z"), "date-time")
    gap("Date", Json.jString("+999999999-12-31"), "date")
    // closed by Stage 2a (schema/validator/zod fixed): these used to be gaps
    agree("Char", Json.jString(""), ok = false)
    agree("GUID", Json.jString("1-1-1-1-1"), ok = false)
    agree("GUID", Json.jString("3F2504E0-4F89-11D3-9A0C-0305E82C3301"), ok = true)
  }

  // ---------------------------------------------------------------------
  // the mapping decisions, one pin each

  property("(map) mapping decisions") = sessionProof { implicit s =>
    loadStatements("field sfInt : Int\ndata Shq = Circq { radius : Double } | Dotq\ndata Opt = Opt { oa : Maybe Int, ob : Int }\n" +
                   "data Tgf = Tgfa { tag : Int } | Tgfb { tgfx : Int }\n" +
                   "type Rep = {sfInt} -> List Int\npolyRep : a -> a\npolyRep x = x", imps)
    def ty(t: String): Type = Session.eval("[] : List (" + t + ")", imps)._1 match {
      case AppT(_, elem) => elem
      case other => sys.error("unexpected " + other)
    }
    def ok(t: String, text: String): Runtime =
      Decode.decode(ty(t), parse(text)).fold(e => sys.error(t + " " + text + ": " + e.report), identity)
    def no(t: String, text: String): Decode.Error =
      Decode.decode(ty(t), parse(text)) match {
        case Left(e)  => e
        case Right(r) => sys.error(t + " " + text + ": decoded, expected a refusal")
      }
    // an integer may be written with a zero fraction or an exponent (JSON Schema's integer)
    assert(ok("Int", "1.0") == Prim(1) && ok("Int", "1e2") == Prim(100))
    assert(no("Int", "1.5").message.contains("fraction"))
    // Long is a string; a JSON number is refused
    assert(no("Long", "7").message.contains("decimal string"))
    // a Timestamp with any offset is that instant; a Date is UTC midnight
    assert(same(ok("Timestamp", "\"2026-09-16T14:00:00.000+02:00\""),
                Prim(java.sql.Timestamp.from(java.time.Instant.parse("2026-09-16T12:00:00Z")))).isEmpty)
    assert(same(ok("Timestamp", "\"2026-09-16T12:00:00.123456789Z\""),
                Prim(java.sql.Timestamp.from(java.time.Instant.parse("2026-09-16T12:00:00.123456789Z")))).isEmpty)
    assert(same(ok("Date", "\"2026-09-16\""), Session.eval("@2026/9/16", imps)._2).isEmpty)
    assert(no("Date", "\"2026-9-16\"").path == "$")
    // the Null of a Nullable is the one `Null Int` evaluates to
    assert(same(ok("Nullable Int", "null"), Session.eval("(Null Int : Nullable Int)", imps)._2).isEmpty)
    // a Maybe field is an optional key; null is not its Nothing
    assert(same(ok("Opt", "{\"ob\": 1}"), Session.eval("Opt Nothing 1", imps)._2).isEmpty)
    assert(no("Opt", "{\"oa\": null, \"ob\": 1}").path == "$.oa")
    // unknown keys at the key, missing ones at the object, a bad tag at the tag
    assert(no("{sfInt}", "{\"sfInt\": 1, \"zz\": 2}").path == "$.zz")
    assert(no("{sfInt}", "{}").path == "$")
    assert(no("Shq", "{\"tag\": \"Square\"}").path == "$.tag")
    assert(no("Shq", "{\"tag\": \"Dotq\", \"args\": [1]}").path == "$.args")
    assert(no("List Shq", "[{\"tag\": \"Dotq\", \"args\": []}, {\"tag\": \"Circq\", \"radius\": \"x\"}]").path == "$[1].radius")
    // `same` holds every null wrapper equivalent (the Maybe Json
    // non-injectivity), so the wrappers themselves are pinned with `==`, which
    // does discriminate (review, optional 1)
    assert(ok("Maybe# Int", "null") == Prim(None))
    assert(ok("Maybe Int", "null") == Session.eval("Nothing : Maybe Int", imps)._2)
    assert(!(ok("Maybe Int", "null") == Prim(None)), "a Maybe's Nothing is not a native Maybe#'s")
    assert(ok("Nullable Int", "null") != Prim(None))
    // a field named `tag` in a type with SEVERAL constructors would overwrite
    // the discriminator: the decoder, the exporter and the encoder all refuse
    // it, at the field, and all three say the same thing (review finding 2)
    val tagf = ty("Tgf")
    val decEr = Decode.entry(tagf).left.getOrElse(sys.error("entry accepted Tgf"))
    val schEr = Schema.exportType(tagf, "Test").left.getOrElse(sys.error("the exporter accepted Tgf"))
    val encEr = Encode.toArgonaut(Session.eval("Tgfa 7", imps)._2).left.getOrElse(sys.error("the encoder accepted Tgfa 7"))
    assert(decEr.path == "Tgf.Tgfa[0]" && schEr.path == "Tgf.Tgfa[0]", decEr.toString + " / " + schEr.toString)
    assert(List(decEr.message, schEr.message, encEr.message).forall(_.contains("collides with the discriminator")),
           decEr.message + " / " + schEr.message + " / " + encEr.message)
    assert(encEr.path == "$.tag", encEr.toString)
    // ONE constructor has no discriminator, so `tag` is an ordinary field
    // there.  In its own module load: Stage 1a refuses two data types of one
    // module declaring a selector of the same name.
    session { implicit s2 =>
      loadStatements("data Tg1 = Tg1 { tag : Int }", imps)
      val t1 = Session.eval("[] : List Tg1", imps)._1 match { case AppT(_, e) => e; case o => sys.error("" + o) }
      val got = Decode.decode(t1, parse("{\"tag\": 7}")).fold(e => sys.error(e.report), identity)
      assert(same(got, Session.eval("Tg1 7", imps)._2).isEmpty)
      assert(Schema.exportType(t1, "Test").isRight)
      assert(Encode.toArgonaut(Session.eval("Tg1 7", imps)._2).right.map(_.nospaces) == Right("{\"tag\":7}"))
    }
    // the Json type takes anything, as `parse` would
    val anyDoc = "{\"a\": [1, 2.5, \"s\", true, null, {}]}"
    assert(same(ok("Json", anyDoc), Session.eval("maybe jnull id (parse \"" + anyDoc.replace("\"", "\\\"") + "\")", imps)._2).isEmpty)
    // reportSignature splits P -> R and refuses the rest
    assert(Decode.reportSignature(ty("Int -> String")).isRight)
    assert(Decode.reportSignature(ty("Int")).isLeft)
    val (p, r) = Decode.reportSignature(Session.eval("[] : List Rep", imps)._1 match { case AppT(_, e) => e; case o => o })
      .fold(e => sys.error(e.report), identity)
    assert(Schema.renderType(p) == "{..(|sfInt|)}" && Schema.renderType(r) == "List Int", p.toString + " / " + r)
    assert(Decode.reportSignature(Session.eval("polyRep", imps)._1).isLeft)
  }

  // ---------------------------------------------------------------------
  // (d) entry

  /** A poison type, the declarations it needs, the refusal's message
    * fragment, whether the SCHEMA exporter refuses it too, and -- for a poison
    * that is a DECLARATION rather than a type -- the fixed path the refusal
    * names whatever context it sits in. */
  private val poisons: List[(String, String, String, Boolean, Option[String])] = List(
    ("a",                    "", "polymorphic", true, None),
    ("(Int -> Int)",         "", "function", true, None),
    ("{..r}",                "", "open row", true, None),
    ("(IO Int)",             "", "IO", true, None),
    ("(FFI Int)",            "", "FFI", true, None),
    ("(Prim Int)",           "", "PrimT", true, None),
    ("(Maybe (Maybe Int))",  "", "nested Maybe", true, None),
    ("[sfPoison]",           "field sfPoison : Int", "relation", false, None),
    ("(Inline (|sfPoison|))",   "field sfPoison : Int", "relation", false, None),
    ("(Deferred (|sfPoison|))", "field sfPoison : Int", "relation", false, None),
    ("(Nullable Char)",      "", "PrimT witness", false, None),
    // Stage 2b: a Spread is a constructor FIELD, one per constructor, named,
    // of `Spread Json`; the decoder, the exporter and `Encode.rejections`
    // refuse the other spellings at the field that carries them
    ("(Spread Json)", "", "nothing to gather into", true, None),
    ("Sy1", "data Sy1 = Sy1 { sy1a : Spread Json, sy1b : Spread Json }",
     "at most one Spread field", true, Some("Sy1.Sy1[1]")),
    ("Sy2", "data Sy2 = Sy2 Int (Spread Json)", "nothing to gather into", true, Some("Sy2.Sy2[1]")),
    ("Sy3", "data Sy3 = Sy3 { sy3a : Spread Int }", "only Spread Json", true, Some("Sy3.Sy3[0]")),
    // a field named `tag` in a type with several constructors: refused by the
    // decoder, the exporter and the encoder alike, at the field it names
    ("Tg", "data Tg = Tga { tag : Int } | Tgb { tgx : Int }",
     "collides with the discriminator", true, Some("Tg.Tga[0]")))

  /** A context the poison sits in, and the path the refusal must name. */
  private def contexts(n: Int): List[(String => String, String, String)] = List(
    ((x: String) => x, "", "$"),
    ((x: String) => "(List " + x + ")", "", "$[]"),
    ((x: String) => "(Vector_V " + x + ")", "", "$[]"),
    ((x: String) => "(Int, " + x + ")", "", "$[1]"),
    ((x: String) => "(Pz" + n + " " + x + ")", "data Pz" + n + " a = Pz" + n + " Int a", "Pz" + n + ".Pz" + n + "[1]"),
    ((x: String) => "(Qz" + n + " " + x + ")", "data Qz" + n + " a = Qz" + n + "a | Qz" + n + "b { qz" + n + "f : a }",
     "Qz" + n + ".Qz" + n + "b[0]"))

  private val poisoned: Gen[(String, String, String, String, Boolean)] =
    for {
      n <- Gen.choose(0, 1000000)
      (t, d, why, schemaRefuses, fixed) <- Gen.oneOf(poisons)
      (ctx, cd, at) <- Gen.oneOf(contexts(n).filter { case (_, _, p) =>
        // a named `Maybe` field whose payload is a Maybe IS invertible
        // (absent -> Nothing, null -> Just Nothing, value -> Just (Just v)),
        // so the nested-Maybe poison is not poison in that one context
        !(t == "(Maybe (Maybe Int))" && p.contains("Qz")) })
      // a nested Maybe directly under Maybe-like contexts is refused one level up; keep them apart
      sibling <- TestSchema.shape(2)
    } yield (ctx(t), (List(d, cd) ++ sibling.decls).filter(_.nonEmpty).distinct.mkString("\n"),
             why, fixed.getOrElse(at), schemaRefuses)

  property("(d) entry refuses a poisoned type at the poison, and so does the exporter") =
    forAllNoShrink(poisoned) { (c: (String, String, String, String, Boolean)) =>
      val (tyExpr, decls, why, at, schemaRefuses) = c
      try session { implicit s =>
        loadStatements(decls, imps)
        val ty = NewPipeline.replType("<poison>", tyExpr, imps)
        (Decode.entry(ty), Schema.exportType(ty, "Test")) match {
          case (Right(_), _) => falsified :| ("entry accepted " + tyExpr)
          case (Left(e), sch) =>
            ((e.path == at) :| ("refused at " + e.path + ", expected " + at + ": " + e.report)) &&
            (e.message.contains(why) :| ("message " + e.message + " lacks " + why)) &&
            ((sch.isLeft == schemaRefuses) :| ("the exporter " + (if (sch.isLeft) "refused" else "accepted") + " " + tyExpr))
        }
      } catch { case ex: Throwable => falsified :| ("threw " + ex + " for " + tyExpr + "\n" + decls) }
    }

  property("(d2) entry accepts every closed generated type, as the exporter does") =
    forAllNoShrink(TestSchema.shape(3)) { (sh: Shape) =>
      try session { implicit s =>
        loadStatements(sh.decls.distinct.mkString("\n"), imps)
        val ty = NewPipeline.replType("<closed>", sh.ty, imps)
        (Decode.entry(ty), Schema.exportType(ty, "Test")) match {
          case (Right(_), Right(_)) => proved
          case (l, r) => falsified :| ("entry " + l + ", export " + r.left.map(_.report) + " for " + sh.ty)
        }
      } catch { case ex: Throwable => falsified :| ("threw " + ex + " for " + sh.ty) }
    }

  /** J3a gave a relation a schema (the delivery union, or one arm for a
    * `Json.Inline` / `Json.Deferred` wrapper); a relation's rows never come
    * from the request, so the decoder refuses every one of them.  This is the
    * one deliberate disagreement between the exporter and `entry` that is
    * generated rather than pinned: `shape(2, rels = true)` puts relations,
    * bare and wrapped, anywhere in the tree. */
  /** The verdicts of one relation-bearing case: the complaint, or None. */
  def relationCase(sh: Shape): Option[String] =
    try session { implicit s =>
      loadStatements(sh.decls.distinct.mkString("\n"), imps)
      val ty = NewPipeline.replType("<rels>", sh.ty, imps)
      (Decode.entry(ty), Schema.exportType(ty, "Test")) match {
        case (Left(e), Right(_)) if sh.rels > 0 =>
          if (e.message.contains("relation")) None
          else Some("entry refused " + sh.ty + " for the wrong reason: " + e.report)
        case (Right(_), Right(_)) if sh.rels == 0 => None
        case (Left(e), Left(x)) if sh.rels > 0 =>
          Some("the exporter refused a relation type " + sh.ty + ": " + x.report + " (entry: " + e.report + ")")
        case (Right(_), _) if sh.rels > 0 => Some("entry ACCEPTED the relation type " + sh.ty)
        case (l, r) => Some("entry " + l + ", export " + r.left.map(_.report) + " for " + sh.ty)
      }
    } catch { case ex: Throwable => Some("threw " + ex + " for " + sh.ty) }

  property("(d3) a relation-bearing type is exported by the schema and refused by entry (120 cases)") = {
    val cases = samples(TestSchema.shape(2, rels = true), 120, seed0 = 20260918L)
    val bad = cases.flatMap(relationCase)
    val bearing = cases.count(_.rels > 0)
    println("  decode vs J3a's relation export: " + cases.length + " shapes, " + bearing + " carry a relation")
    (bad.isEmpty :| (bad.length + " wrong verdicts\n" + bad.take(3).mkString("\n---\n"))) &&
      // not vacuous, and a floor rather than a pin: a relation is one leaf
      // among many, so the fixed seeds give 15 of 120 today
      ((bearing >= 10) :| ("only " + bearing + " of " + cases.length + " shapes carry a relation"))
  }

  // ---------------------------------------------------------------------
  // (s) Stage 2b: what the encoder merged, the decoder gathers back

  /** The complaint about one spread case, or None.  Three things: the round
    * trip through the merged document; that a constructor with a spread
    * field no longer REFUSES a key it does not declare (the validator agrees,
    * since the exporter opened the object); and that such a key comes back
    * in the spread, in document order, which re-encoding shows. */
  def spreadGathers(c: TestSchema.SpreadCase): Option[String] = {
    val decls = (c.decls.distinct ++ List("gv : " + c.ty, "gv = " + c.value)).mkString("\n")
    try session { implicit s =>
      loadStatements(decls, imps)
      val (ty, rt) = Session.eval("gv", imps)
      val schema = Schema.exportType(ty, "Test").fold(e => sys.error("export refused: " + e.report), identity)
      val doc    = Encode.toArgonaut(rt).fold(e => sys.error("encode refused: " + e.report), identity)
      val r1 = Decode.decode(ty, doc).fold(e => Some("decode refused " + Schema.compact(doc) + ": " + e.report),
                                           r => same(r, rt))
      // a key before every declared one and a key after every merged one
      val open = Json.obj(((("zzA" -> Json.jNumber(1)) :: doc.obj.get.toList) :+ ("zzB" -> Json.jString("b"))): _*)
      val r2 = Validate.check(schema, open) match {
        case Nil => None
        case es  => Some("the validator refused a key of an OPEN object: " + es.mkString("; "))
      }
      val want = c.fields ++ ("zzA" :: c.keys) ++ List("zzB")
      val r3 = Decode.decode(ty, open).fold(
        e => Some("decode refused the key it should gather: " + e.report),
        back => Encode.toArgonaut(back).fold(e => Some("re-encode refused: " + e.report), j =>
          if (j.objectFieldsOrEmpty == want) None
          else Some("gathered " + j.objectFieldsOrEmpty.mkString(", ") + ", expected " + want.mkString(", "))))
      List(r1, r2, r3).flatten.headOption.map(_ + "\n" + decls)
    } catch { case e: Throwable => Some("threw " + e + "\n" + decls) }
  }

  property("(s) a spread constructor gathers the keys it does not declare, in document order (60 cases)") = {
    val cases = samples(TestSchema.spreadProbe, 60, seed0 = 20260919L).filter(_.clash.isEmpty)
    val bad = cases.flatMap(spreadGathers)
    val merged = cases.count(c => c.fields.nonEmpty && c.keys.nonEmpty)
    println("  spread gather: " + cases.length + " collision-free cases, " + merged +
            " with both declared and merged keys")
    (bad.isEmpty :| (bad.length + " failed\n" + bad.take(3).mkString("\n---\n"))) &&
      ((cases.length >= 30) :| ("only " + cases.length + " collision-free cases")) &&
      ((merged >= 15) :| ("only " + merged + " cases mix declared and merged keys"))
  }

  property("(s-pins) a closed constructor still refuses the key an open one gathers") = sessionProof { implicit s =>
    loadStatements(List("data Sz1 = Sz1 { sz1a : Int }",
                        "data Sz2 = Sz2 { sz2a : Int, sz2s : Spread Json }",
                        "data Sz3 a = Sz3 { sz3a : Spread a }").mkString("\n"), imps)
    def ty(n: String): Type = NewPipeline.replType("<spread>", n, imps)
    def schema(n: String): Json = Schema.exportType(ty(n), "Test").fold(e => sys.error(e.report), identity)
    val closed = Json.obj("sz1a" -> Json.jNumber(1), "zz" -> Json.jNull)
    val open   = Json.obj("sz2a" -> Json.jNumber(1), "zz" -> Json.jNull)
    // the closed type: both refuse the extra key, at the key
    assert(Validate.check(schema("Sz1"), closed).exists(_.startsWith("$.zz")), Validate.check(schema("Sz1"), closed).mkString)
    assert(Decode.decode(ty("Sz1"), closed).fold(e => e.path, _ => "accepted") == "$.zz")
    // the open one: both take it, and it is the spread's
    assert(Validate.check(schema("Sz2"), open).isEmpty, Validate.check(schema("Sz2"), open).mkString)
    val back = Decode.decode(ty("Sz2"), open).fold(e => sys.error(e.report), identity)
    assert(Encode.toArgonaut(back).fold(e => sys.error(e.report), _.nospacesWithOrder) ==
           "{\"sz2a\":1,\"zz\":null}")
    // the spread field of the decoded value is `Spread (JObj [("zz", JNull)])`
    back match {
      case Data(g, args) if g.string == "Sz2" && args.length == 2 =>
        Runtime.swhnf(args(1)) match {
          case Data(sg, sa) if sg == Global("Json", "Spread") && sa.length == 1 =>
            assert(Encode.render(sa(0)).fold(e => sys.error(e.report), identity) == "{\"zz\":null}",
                   Encode.render(sa(0)).toString)
          case other => sys.error("the spread field decoded to " + other)
        }
      case other => sys.error("decoded to " + other)
    }
    // an empty spread is still a Spread of an empty object
    val empty = Decode.decode(ty("Sz2"), Json.obj("sz2a" -> Json.jNumber(1))).fold(e => sys.error(e.report), identity)
    assert(Encode.toArgonaut(empty).fold(e => sys.error(e.report), _.nospacesWithOrder) == "{\"sz2a\":1}")
    // The SPREAD field's own name is a spare key like any other: the
    // validator takes it, the decoder gathers it and the encoder writes it
    // back unchanged, so all three agree about a document that names it
    // (J2b review finding 1; TestSchema's (s-pins) pins the encode direction).
    val own = Json.obj("sz2a" -> Json.jNumber(1), "sz2s" -> Json.jString("x"))
    assert(Validate.check(schema("Sz2"), own).isEmpty, Validate.check(schema("Sz2"), own).mkString)
    val ownBack = Decode.decode(ty("Sz2"), own).fold(e => sys.error(e.report), identity)
    assert(Encode.toArgonaut(ownBack).fold(e => sys.error(e.report), _.nospacesWithOrder) ==
           "{\"sz2a\":1,\"sz2s\":\"x\"}")
    // a `Spread a` field is decided at the INSTANTIATION, as the exporter
    // decides it: `Spread Json` plans, `Spread Int` is refused at the field
    assert(Decode.entry(ty("(Sz3 Json)")).isRight)
    assert(Decode.entry(ty("(Sz3 Int)")).fold(e => e.path + " " + e.message, _ => "accepted")
             .startsWith("Sz3.Sz3[0] only Spread Json gathers"))
    true
  }

  // ---------------------------------------------------------------------
  // (e) scale

  property("(e) a 100,000-element list of records decodes") = sessionProof { implicit s =>
    loadStatements("field sfInt : Int\nfield sfString : String", imps)
    val (ty, rt) = Session.eval("replicate {sfInt = 7, sfString = \"a\"} 100000 : List {sfInt, sfString}", imps)
    val text = Schema.compact(Encode.toArgonaut(rt).fold(e => sys.error(e.report), identity))
    val t0 = System.nanoTime
    val back = Decode.decode(ty, parse(text)).fold(e => sys.error(e.report), identity)
    val ms = (System.nanoTime - t0) / 1000000
    same(back, rt).foreach(d => sys.error(d))
    println("  decode scale: 100,000 records (" + text.length + " bytes) in " + ms + " ms")
  }

  /** The deepest `[[..]]` argonaut's recursive parser reads on this thread. */
  private def parserDepth: Int = {
    def parses(n: Int): Boolean =
      try { argonaut.Parse.parse("[" * n + "]" * n).isRight } catch { case _: StackOverflowError => false }
    var lo = 1; var hi = 1 << 18
    while (lo < hi) { val mid = (lo + hi + 1) / 2; if (parses(mid)) lo = mid else hi = mid - 1 }
    lo
  }

  property("(e2) nesting to the parser's depth and far beyond decodes without growing the stack") = sessionProof { implicit s =>
    loadStatements("data Nest = Nest { kids : List Nest }", imps)
    val nestTy = Session.eval("[] : List Nest", imps)._1 match { case AppT(_, e) => e; case o => sys.error("" + o) }
    val jsonTy = Session.eval("[] : List Json", imps)._1 match { case AppT(_, e) => e; case o => sys.error("" + o) }
    // A MARGIN, never the boundary.  `parserDepth` measures where argonaut's
    // recursive parser overflows ON THIS THREAD AT THIS INSTANT, and that moves
    // with the JIT state of a JVM that is running four suites (3,864 to 21,259
    // measured across the review's runs and mine), so re-parsing AT the
    // measurement is a coin flip, and it overflowed one gate run in fifteen
    // (J2a review finding 1).
    val probe = parserDepth
    val limit = math.max(1, probe * 3 / 4)
    // what the parser can read decodes as Json
    val parsed =
      try parse("[" * limit + "]" * limit)
      catch { case _: StackOverflowError => sys.error("the parser probe over-measured: " + probe) }
    def arrDepth(r: Runtime): Int = {
      var d = 0; var cur = Runtime.swhnf(r)
      var go = true
      while (go) cur match {
        case Data(Global("Json", "JArr", _), Array(xs)) => Runtime.swhnf(xs) match {
          case Data(Global("Builtin", "::", _), Array(h, _)) => d += 1; cur = Runtime.swhnf(h)
          case _ => d += 1; go = false
        }
        case _ => go = false
      }
      d
    }
    val j1 = Decode.decode(jsonTy, parsed).fold(e => sys.error(e.report), identity)
    assert(arrDepth(j1) == limit, arrDepth(j1) + " vs " + limit)
    // Far deeper, built in memory: Json, a recursive record-style type, and a
    // failure at the bottom.  A FIXED depth, not a multiple of the probe: this
    // half is about the DECODER being iterative, which has nothing to do with
    // what the parser can read.
    val deep = 100000
    var arr: Json = Json.jEmptyArray
    var nest: Json = Json.obj("kids" -> Json.jEmptyArray)
    var badNest: Json = Json.obj("kids" -> Json.jNumber(1))
    var i = 0
    while (i < deep) {
      arr = Json.array(arr)
      nest = Json.obj("kids" -> Json.array(nest))
      badNest = Json.obj("kids" -> Json.array(badNest))
      i += 1
    }
    val j2 = Decode.decode(jsonTy, arr).fold(e => sys.error(e.report), identity)
    assert(arrDepth(j2) == deep + 1, arrDepth(j2) + " vs " + (deep + 1))
    assert(Decode.decode(nestTy, nest).isRight)
    Decode.decode(nestTy, badNest) match {
      case Left(e) => assert(e.path.length == 1 + deep * ".kids[0]".length + ".kids".length, e.path.take(40))
      case Right(_) => sys.error("decoded a bad deep document")
    }
    println("  decode depth: argonaut parses " + probe + " levels here (" + limit + " read back with a margin); " +
            deep + " levels decode in memory")
  }
}
