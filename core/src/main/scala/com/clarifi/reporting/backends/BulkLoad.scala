package com.clarifi.reporting.backends

import f0._
import f0.Writers._
import f0.Readers._
import f0.Sinks
import com.clarifi.reporting._
import com.clarifi.reporting.flatteners.TableFlattener
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.Reporting.{SimpleDataSet}
import scalaz.StreamT
import java.util.{UUID, Date}
import org.apache.log4j.Logger
import util.{IOUtils, StreamTUtils}
import java.io.{FileInputStream, File, InputStream, OutputStream}
import com.clarifi.reporting.util.PimpedLogger._
import Reporting._
import scalaz.Scalaz._

object BulkLoad {

  val Log = Logger.getLogger(this.getClass)

  def main(args: Array[String]) {
    import java.io.PrintWriter
    if(args.length < 1)
      println("Need a file name to deserialize.")
    else {
      val src = Sources.fromFile(args(0))
      val ((meta,schema),rows) = schemaRowsR(src)
      val out = if(args.length < 2) new PrintWriter(System.out)
                else {
                  new PrintWriter(args(1))
                }
      val rows2 = if(args.length < 3) rows
                  else rows.filter { case (tbl, row) => tbl == args(2) }
      def endl = out.println("")
      out.println("Metadata\n--------\n")
      out.println(meta) ; endl
      out.println("Schema\n------\n")
      out.println(schema) ; endl
      out.println("Rows\n----\n")
      val nonkey = Range(3,args.length).toList.map(args(_))
      var seen = Map[Record, Record]()
      for ((tab,row) <- rows2) {
        if(seen.contains(row -- nonkey)) {
          println("Duplicate rows")
          println(row)
          println(seen(row -- nonkey))
          sys.error("bomb")
        } else {
          seen = seen + ((row -- nonkey) -> row)
        }
        out.println(tab + ": " + row)
      }
      out.flush
      out.close
    }
  }

  val dateW = longW.cmap((d: Date) => 621355968000000000L+d.getTime*10000L)
  val dateR = longR map (l => new Date((l - 621355968000000000L)/10000L))
  val uuidW = stringW.cmap((uid: UUID) => uid.toString)
  val uuidR = stringR map (UUID.fromString(_))

  def primExprW = s10W(
    optionW(booleanW),
    optionW(byteW),
    optionW(shortW),
    optionW(intW),
    optionW(longW),
    optionW(doubleW),
    optionW(stringW),
    optionW(dateW),
    optionW(uuidW),
    optionW(unitW))((a,b,c,d,e,f,g,h,i,j) => (p:PrimExpr) => p match {
    case BooleanExpr(n, x) => a(Some(x))
    case ByteExpr(n, x)    => b(Some(x))
    case ShortExpr(n, x)   => c(Some(x))
    case IntExpr(n, x)     => d(Some(x))
    case LongExpr(n, x)    => e(Some(x))
    case DoubleExpr(n, x)  => f(Some(x))
    case StringExpr(n, x)  => g(Some(x))
    case DateExpr(n, x)    => h(Some(x))
    case UuidExpr(n, x)    => i(Some(x))
    case NullExpr(x)       => j(None)
  })

  def liftExprCon[A](t: PrimT, con: (Boolean, A) => PrimExpr)(oa: Option[A]) = oa match {
    case None    => NullExpr(t)
    case Some(x) => con(false, x)
  }

  def primExprR =
    union10R( optionR(booleanR) map (liftExprCon(BooleanT(), BooleanExpr))
            , optionR(byteR) map (liftExprCon(ByteT(), ByteExpr))
            , optionR(shortR) map (liftExprCon(ShortT(), ShortExpr))
            , optionR(intR) map (liftExprCon(IntT(), IntExpr))
            , optionR(longR) map (liftExprCon(LongT(), LongExpr))
            , optionR(doubleR) map (liftExprCon(DoubleT(), DoubleExpr))
            , optionR(stringR) map (liftExprCon(StringT(0), StringExpr))
            , optionR(dateR) map (liftExprCon(DateT(), DateExpr))
            , optionR(uuidR) map (liftExprCon(UuidT(), UuidExpr))
            , optionR(unitR) map (_ => NullExpr(IntT(true))) // no way to recover the type information
            )

  def rowW(colOrder: List[String]) = // Writer[Record, _]
    repeatW(primExprW).cmap((tup: Map[String,PrimExpr]) => colOrder.map(tup(_)))

  def rowR(colOrder: List[String]) =
    listR(primExprR) map (l => colOrder zip l toMap)

  def rowInTableW(orders: Map[String,List[String]]) = //: Writer[(String, Record), _]
    stringW withLast (s => rowW(orders(s)))

  def rowInTableR(orders: Map[String, List[String]]) =
    stringR flatMap { s =>
      rowR(orders(s)) map ((s, _))
    }

  def flattenerStreamW(orders: Map[String,List[(String,PrimT)]]) = // Writer[DataSet, _]
    unfoldW(rowInTableW(orders.toMap.mapValues(_.toList.map(_._1))))((d: SimpleDataSet) => StreamTUtils.unconsId(d))

  def flattenerStreamR(orders: Map[String, List[(String, PrimT)]]) =
    streamR(rowInTableR(orders.mapValues(_.map(_._1))))

  def schemaW = repeatW(tuple2W(stringW, repeatW(tuple2W(stringW,stringW)))).cmap(
    (schema: Map[String,Header]) => schema.mapValues(_.mapValues(_.toString).toList).toList)

  def preschemaR = listR(tuple2R(stringR, listR(tuple2R(stringR, stringR)))) map {
    l => l map { case (k, h) => k -> (h map { case (col, pt) => col -> PrimT.read(pt) })} toMap
  }
  def toSchema(m: Map[String, List[(String, PrimT)]]): Map[String, Header] = m.mapValues(_ toMap)

  def metadataW = p5W(stringW, optionW(stringW), optionW(stringW), optionW(stringW), optionW(stringW))(f => (md:Metadata) =>
    f(md.databaseName, md.before, md.onSuccess, md.onError, md.after))

  def metadataR = p5R(stringR, optionR(stringR), optionR(stringR), optionR(stringR), optionR(stringR))(Metadata(_,_,_,_,_))

  // Writer[(connectionURL, (Map[String,List[(ColumnName,ColumnTypeString)]], DataSet)), _]
  def schemaRows =
    tuple2W(
      metadataW,
      schemaW) withLast { case (_,s) => flattenerStreamW(s.mapValues(_.toList)) }

  def schemaRowsR =
    tuple2R(metadataR, preschemaR) flatMap {
      case (md, pre) =>
        flattenerStreamR(pre) map { ((md, toSchema(pre)), _) }
    }

  type Results = (Int, Option[(Int,String,List[String])])
  val resultReader = tuple2R(intR, optionR(tuple3R(intR, stringR, listR(stringR))))

  def writeData(out:OutputStream, dbName: Metadata,
                schema: Map[String,(RefID,Header)], tuples: SimpleDataSet): Unit = {
    Sinks.using(Sinks.toOutputStream(out)){ s =>
      val data = ((dbName, schema.values.map { case (tn, h) => tn.toString -> h } toMap), tuples)
      schemaRows.bind(s)(data)
    }
  }
  def readResult(in:InputStream) = resultReader.bind(f0.Sources.fromInputStream(in)).get

  def run(out:OutputStream,
          dbName: Metadata,
          schema: Map[String,(RefID,Header)],
          records: SimpleDataSet,
          in: => InputStream): Results = {
    writeData(out, dbName, schema, records)
    Log.info("done writing rows; reading result...")
    readResult(in)
  }

  def bulkLoadToWebHandler(input: File, webHandlerURL: String): Either[Exception, Results] = {
    // send the data to the web handler and read the result when it's finished
    Log.timed("streaming data from: " + input + " to: " + webHandlerURL) {
      try Right(StreamingWebRequest.streamWith(webHandlerURL){ (out, in) =>
      // write all the data from the input stream to the web stream
        IOUtils.copy(new FileInputStream(input), out)
        // read the result
        BulkLoad.readResult(in)
      })
      catch { case e => Left(new Exception("Error processing bulk loading response", e)) }
    }
  }

  /** `before` is run before doing the inserts; `after` is always run in case of success or in case of failure. */
  case class Metadata(
    databaseName: String,
    before: Option[String] = None,
    onSuccess: Option[String] = None,
    onError: Option[String] = None,
    after: Option[String] = None)

  import com.clarifi.reporting.util.StreamTUtils

  def flattenTo[A](f: TableFlattener[Unit,A])(a: A, out: OutputStream, md: Metadata): Unit =
    Sinks.using(Sinks.toOutputStream(out)) { sink =>
      schemaRows.bind(sink)(((md, f.schema.map {
        case (k,v) => (k.name, v)
      }), StreamTUtils.runStreamT(f(a).map { case (x, y) => (x.name, y) })))
    }
}

object StreamingWebRequest {
  import java.net.{HttpURLConnection, URL}
  import java.io.{OutputStream, InputStream}
  def streamWith[T](url:String)(f: (OutputStream, => InputStream) => T) = {
    val conn = new URL(url).openConnection().asInstanceOf[HttpURLConnection]
    // enables chunked transfer with default chunk size
    conn.setChunkedStreamingMode(0)
    // this enables you to write to the output stream.
    conn.setDoOutput(true)
    conn.setRequestMethod("PUT")
    conn.setReadTimeout(1000 * 60 * 10) // 10 minutes)
    conn.connect()
    try f(conn.getOutputStream, conn.getInputStream)
    finally conn.getInputStream.close()
  }
}

object BulkLoadTester {
  import com.clarifi.reporting.{ Run, Reporting }
  import Reporting.RefID

  def main(args: Array[String]): Unit = {
    val backend = Backends.MySQLInnoDB

    import java.io.PrintWriter
    if(args.length < 2)
      println("Need a file name to deserialize.")
    else {
      val src = Sources.fromFile(args(0))
      val connectionString = args(1)
      val runner = Runners.MySQL(connectionString)
      val ((meta,schema),rows) = BulkLoad.schemaRowsR(src)
      val rows2 = if(args.length < 3) rows
                  else rows.filter { case (tbl, row) => tbl == args(2) }

      val newschema = schema.map {
        case (k, h) => (TableName(k), (RefID(k), h))
      }
      runner.run(backend.populateSchema(newschema, StreamT.fromIterable(rows2.map { case (t, r) => TableName(t) -> r }))(Source()))
    }
  }
}
