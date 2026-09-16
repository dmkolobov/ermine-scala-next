package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.PrimT

/** The names the document wire format is spelled with (design note §3.2,
  * §3.4a; tracker/JSON-STAGE3-PLAN.md "Wire contract").  The schema
  * exporter, the document writer, the row encoder, the params decoder and
  * the TypeScript client all read their keys from here or from the plan, so
  * a rename is one edit.
  *
  *   document  {"version": 1, "settings": {..}, "root": <Layout.Doc.Node>}
  *   inline    {"kind": "inline",   "columns": [col..], "rows": [[cell..]..], "rowCount": n}
  *   deferred  {"kind": "deferred", "columns": [col..], "token": "..", "expires": "<ISO instant>"}
  *   col       {"name": "..", "type": <one of columnTypes>, "nullable": bool}
  *
  * Columns are in sorted name order (a `Header` and a record row are both
  * unordered maps; the record encoder sorts too), and each row array follows
  * the column order.  Cells follow the encoder's mapping for the column's
  * type (`Encode`): Long as a decimal string, dates and timestamps as ISO
  * strings, a null as `null`.
  */
object Wire {
  val version = 1

  // the document envelope
  val Version  = "version"
  val Settings = "settings"
  val Root     = "root"

  // a relation object
  val Kind     = "kind"
  val Inline   = "inline"
  val Deferred = "deferred"
  val Columns  = "columns"
  val Rows     = "rows"
  val RowCount = "rowCount"
  val Token    = "token"
  val Expires  = "expires"

  // a column descriptor
  val Name     = "name"
  val Type     = "type"
  val Nullable = "nullable"

  /** The column `type` vocabulary: the Ermine spellings of the ten `PrimT`s,
    * which are the `PrimT` names except `UUID`, whose Ermine type is `GUID`. */
  val columnTypes: List[String] =
    List("Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp")

  /** A header's `PrimT` as a column `type`; nullability is the descriptor's
    * separate `nullable` flag. */
  def columnType(p: PrimT): String = p match {
    case _: PrimT.UuidT => "GUID"
    case other          => other.name
  }
}
