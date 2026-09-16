package com.clarifi.reporting.ermine.json

import scala.collection.immutable.List
import scala.collection.mutable.ListBuffer
import argonaut.Json

/** A JSON Schema validator for EXACTLY the subset `json/Schema.scala` emits.
  *
  * It exists so the encode/schema consistency property of §5's Stage 1 gate
  * can be asserted in this repository with no new dependency: for every
  * generated (type, value), `Encode.toArgonaut` of the value must validate
  * against `Schema.export` of the type with zero errors.  It is deliberately
  * NOT a general implementation -- no `$dynamicRef`, no `if`/`then`, no
  * `patternProperties`, no remote `$ref` -- and an unknown keyword is
  * ignored rather than refused, so a schema this file has not learned about
  * yet fails loudly in the exporter's own tests rather than silently here.
  *
  * Supported: `$ref` (into the root document's `$defs` only), `type`, `enum`,
  * `const`, `properties`, `required`, `additionalProperties: false`, `items`,
  * `prefixItems`, `minItems`, `maxItems`, `minimum`, `maximum`, `pattern`,
  * `minLength` (J3a: a deferred relation's `token`), `maxLength`, `anyOf`,
  * `oneOf`.  `format` is NOT a validation keyword in JSON Schema and is not
  * treated as one here either, with one exception the tests need: `date`,
  * `date-time` and `uuid` strings are parsed with `java.time` /
  * `java.util.UUID`, because those three formats are the whole reason the
  * encoder writes a string where a client expects a moment.  Exactly:
  * `date` is `DateTimeFormatter.ISO_LOCAL_DATE` (`yyyy-MM-dd`, a real
  * calendar day); `date-time` is `ISO_OFFSET_DATE_TIME` -- a date, `T`, a
  * time with optional seconds and fraction (0-9 digits), and a REQUIRED
  * offset (`Z` or `+hh:mm`): RFC 3339's profile, loosened only in making
  * seconds optional.  A relation's `expires` in the wire's Timestamp format
  * `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` passes; zod's `.datetime()` is stricter
  * (a `Z` offset only).  `uuid` is the canonical 8-4-4-4-12 form: a regex and
  * then `UUID.fromString`, because `UUID.fromString` ALONE also takes
  * "1-1-1-1-1", which zod's `.uuid()` and the params decoder both refuse
  * (J2a).
  *
  * Every message carries the JSON path of the instance node it is about
  * (`$.rows[0].name`), the same spelling `Encode.Error` uses.
  */
object Validate {

  /** The empty list means the document satisfies the schema. */
  def check(schema: Json, doc: Json): List[String] = {
    val defs = schema.field("$defs").flatMap(_.obj).map(_.toMap).getOrElse(Map[String, Json]())
    val out = new ListBuffer[String]
    go(schema, doc, "$", defs, out)
    out.toList
  }

  private val dateFmt     = java.time.format.DateTimeFormatter.ISO_LOCAL_DATE
  private val dateTimeFmt = java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME
  private val uuidPattern =
    java.util.regex.Pattern.compile("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

  private def go(schema: Json, doc: Json, path: String,
                 defs: Map[String, Json], out: ListBuffer[String]): Unit = {
    def bad(msg: String): Unit = out += (path + ": " + msg)

    schema.field("$ref") match {
      case Some(r) =>
        r.string match {
          case Some(s) if s.startsWith("#/$defs/") =>
            val name = s.substring("#/$defs/".length)
            defs.get(name) match {
              case Some(target) => go(target, doc, path, defs, out)
              case None         => bad("dangling $ref " + s)
            }
          case other => bad("unsupported $ref " + other.getOrElse(r.nospaces))
        }
        return
      case None => ()
    }

    // `type`
    schema.field("type").flatMap(_.string) foreach { t =>
      val ok = t match {
        case "null"    => doc.isNull
        case "boolean" => doc.bool.isDefined
        case "string"  => doc.string.isDefined
        case "number"  => doc.number.isDefined
        case "integer" => doc.number.exists(n => n.toBigDecimal.isWhole)
        case "array"   => doc.array.isDefined
        case "object"  => doc.obj.isDefined
        case other     => true // a type this validator does not know: not its business
      }
      if (!ok) bad("expected " + t + ", found " + describe(doc))
    }

    // `const` and `enum`
    schema.field("const") foreach { c => if (c != doc) bad("expected the constant " + c.nospaces + ", found " + doc.nospaces) }
    schema.field("enum").flatMap(_.array) foreach { vs =>
      if (!vs.contains(doc)) bad("expected one of " + vs.map(_.nospaces).mkString(", ") + ", found " + doc.nospaces)
    }

    // numbers
    doc.number foreach { n =>
      val d = n.toBigDecimal
      schema.field("minimum").flatMap(_.number) foreach { m =>
        if (d < m.toBigDecimal) bad(d.toString + " is below the minimum " + m.toBigDecimal.toString) }
      schema.field("maximum").flatMap(_.number) foreach { m =>
        if (d > m.toBigDecimal) bad(d.toString + " is above the maximum " + m.toBigDecimal.toString) }
    }

    // strings
    doc.string foreach { s =>
      schema.field("minLength").flatMap(_.number) foreach { m =>
        val n = m.truncateToInt
        if (s.length < n) bad("the string is " + s.length + " characters, shorter than minLength " + n)
      }
      schema.field("maxLength").flatMap(_.number) foreach { m =>
        val n = m.truncateToInt
        if (s.length > n) bad("the string is " + s.length + " characters, longer than maxLength " + n)
      }
      schema.field("pattern").flatMap(_.string) foreach { p =>
        if (!java.util.regex.Pattern.compile(p).matcher(s).find()) bad("the string " + quote(s) + " does not match /" + p + "/")
      }
      schema.field("format").flatMap(_.string) foreach {
        case "date" =>
          try dateFmt.parse(s) catch { case _: Throwable => bad("the string " + quote(s) + " is not a date") }
        case "date-time" =>
          // the encoder writes `...Z`, which ISO_OFFSET_DATE_TIME accepts
          try dateTimeFmt.parse(s) catch { case _: Throwable => bad("the string " + quote(s) + " is not a date-time") }
        case "uuid" =>
          // the canonical 8-4-4-4-12 form only, as zod's .uuid() and the
          // decoder insist: UUID.fromString alone also takes "1-1-1-1-1"
          if (!uuidPattern.matcher(s).matches) bad("the string " + quote(s) + " is not a uuid")
          else try { java.util.UUID.fromString(s); () } catch { case _: Throwable => bad("the string " + quote(s) + " is not a uuid") }
        case _ => () // every other format is an annotation, not an assertion
      }
    }

    // arrays
    doc.array foreach { xs =>
      schema.field("minItems").flatMap(_.number) foreach { m =>
        val n = m.truncateToInt
        if (xs.length < n) bad("the array has " + xs.length + " items, fewer than minItems " + n)
      }
      schema.field("maxItems").flatMap(_.number) foreach { m =>
        val n = m.truncateToInt
        if (xs.length > n) bad("the array has " + xs.length + " items, more than maxItems " + n)
      }
      val prefix = schema.field("prefixItems").flatMap(_.array).getOrElse(Nil)
      xs.zipWithIndex foreach { case (x, i) =>
        val at = path + "[" + i + "]"
        if (i < prefix.length) go(prefix(i), x, at, defs, out)
        else schema.field("items") foreach { it => go(it, x, at, defs, out) }
      }
    }

    // objects
    doc.obj foreach { o =>
      val fields = o.toMap
      val props = schema.field("properties").flatMap(_.obj).map(_.toMap).getOrElse(Map[String, Json]())
      schema.field("required").flatMap(_.array) foreach { rs =>
        rs.flatMap(_.string) foreach { k => if (!fields.contains(k)) bad("the required key " + quote(k) + " is missing") }
      }
      val closed = schema.field("additionalProperties").flatMap(_.bool).contains(false)
      o.toList foreach { case (k, v) =>
        props.get(k) match {
          case Some(ps) => go(ps, v, path + "." + k, defs, out)
          case None     => if (closed) out += (path + "." + k + ": the key " + quote(k) + " is not allowed here")
        }
      }
    }

    // combinators
    schema.field("anyOf").flatMap(_.array) foreach { alts =>
      if (!alts.exists(a => branch(a, doc, path, defs).isEmpty))
        bad("no anyOf branch matches " + doc.nospaces)
    }
    schema.field("oneOf").flatMap(_.array) foreach { alts =>
      val hits = alts.count(a => branch(a, doc, path, defs).isEmpty)
      if (hits == 0) {
        // report the closest branch's complaint too: for a tagged union
        // that is the arm whose tag matched, which is the useful message
        val nearest = alts.map(a => branch(a, doc, path, defs)).sortBy(_.length).headOption.getOrElse(Nil)
        bad("no oneOf branch matches " + doc.nospaces + (if (nearest.isEmpty) "" else "; closest: " + nearest.head))
      } else if (hits > 1) bad(hits + " oneOf branches match " + doc.nospaces + "; exactly one must")
    }
  }

  private def branch(schema: Json, doc: Json, path: String, defs: Map[String, Json]): List[String] = {
    val out = new ListBuffer[String]
    go(schema, doc, path, defs, out)
    out.toList
  }

  private def quote(s: String) = "\"" + s + "\""

  private def describe(j: Json): String =
    if (j.isNull) "null"
    else j.bool.map(_ => "a boolean")
      .orElse(j.number.map(_ => "a number"))
      .orElse(j.string.map(s => "the string " + quote(s)))
      .orElse(j.array.map(_ => "an array"))
      .orElse(j.obj.map(_ => "an object"))
      .getOrElse(j.nospaces)
}
