package com.clarifi.reporting

//import scalaz._
//import Scalaz._
//import scalaz.scalacheck.ScalazArbitrary.TreeArbitrary
//
//import org.scalacheck._
//import Prop.{extendedAny => _, _}
//
//import com.clarifi.reporting.Reporting._
//import com.clarifi.reporting.PrimType._
//import com.clarifi.reporting.RTag.RTypeInferencePartial
//import com.clarifi.reporting.RTag.RTypeInferencePartial._
//
//import SqlEmitter._
//import Sql.SqlBackend
//import Enumeration.Equal
//import Flatteners._
//import Lens._
//import Memo._
//import scala.math.{ceil, sqrt, pow}
////import FlattenProfiler.{primF, listF, tupleF, nestedMapMemoF, treeMemoF}
////import DummyPAData.flattenLocalReport
//import Profiler._
//
//import scala.collection.immutable.ListMap

/**
 * @author JAT
 */

//object InsertProfiler {
//
//  def main(argv: Array[String]): Unit = {
//  
//    // Measurement parameters
//    val numTrials = 1
//    val maxRows = 1000
//	println("Max number of rows inserted per table: " + maxRows)
//	
//    // DB to measure
//    val db = DB.mySqlTestDB
//    val backend = SqlBackend(mySqlEmitter)
//    
//    // Flattens define schema into which to insert
//    val flattens: List[Flatten[_, _]] =
//      List(primF, listF, tupleF, nestedMapMemoF, treeMemoF, flattenLocalReport)
//	
//	val flattenNames: List[String] = 
//	  List("primitive", "list", "tuple", "nestedMapMemo", "treeMemo", "dummyPA")
//    
//    // Generate the tuples to insert
//    val dataSets: List[DataSet] = flattens.map(makeData(_, maxRows))
//	flattenNames.zip(dataSets).foreach { case (name, ds) => 
//	  println(ds.toList.length + " unique rows generated to insert in flatten '" + name + "'") }
//	val fds: List[(Flatten[_,_], DataSet)] = flattens.zip(dataSets)
//	
//	type Schema = Map[TableName,(RefID,Header)]
//	
//	// returns (insertion time, index creation time) stats
//    val stats: List[(Stats,Stats)] = fds.map { case(flatten, dataSet) => {
//	  def schema: Schema = createTables[DB](flatten, db, backend)
//	  def setup: (Schema, DataSet) = (schema, dataSet)
//	  def block1(sd: (Schema,DataSet)): Schema = {
//	    val schema: Schema = sd._1
//		val ds: DataSet = sd._2
//	    val action = backend.populateSchema(schema, ds): DB[Unit]
//		db.run(action)
//		schema
//	  }
//	  def block2(sd: (Schema,DataSet)): Unit = {
//	    val schema: Schema = sd._1
//		val ds: DataSet = sd._2
//	    //val action = backend.createIndices(schema, flatten.hints): DB[Unit]
//		//db.run(action)
//	  }
//	  def teardown(s: Schema): Unit = {
//	    s.foreach((t: (TableName,(RefID,Header))) => db.run(backend.destroy(t._2._1)))
//	  }
//	  profile[(Schema,DataSet), Schema](numTrials: Int)(setup)(block1, block2)(teardown): (Stats,Stats)
//	}}
//	
//	
//	println(stats.zip(flattenNames) map { case ((insert,index), name) =>
//      "Flatten:         " + name + "\n"	+
//	  "Insert times:    " + insert + "\n" +
//	  "Indexing times:  " + index } mkString("\n\n"))
//  }
//  
//  
//  def profile[A, B](numTrials: Int)(setup: => A)(block1: A => B, block2: A => Unit)(teardown: B => Any): (Stats,Stats) = {
//    
//    val stats1 = new Stats
//	val stats2 = new Stats
//    var startTime1: Long = 0
//    var startTime2: Long = 0
//    var stopTime1: Long = 0
//    var stopTime2: Long = 0
//    
//    for (i <- 0 until numTrials) {
//      val a = setup
//      startTime1 = System.currentTimeMillis()
//      val b = block1(a)
//      stopTime1 = System.currentTimeMillis()
//	  startTime2 = System.currentTimeMillis()
//      block2(a)
//      stopTime2 = System.currentTimeMillis()
//	  teardown(b)
//	  
//      val duration1: Long = stopTime1 - startTime1
//	  val duration2: Long = stopTime2 - startTime2
//      stats1.addTime(duration1.asInstanceOf[Double])
//	  stats2.addTime(duration2.asInstanceOf[Double])
//    }
//    
//    (stats1, stats2)
//  }
//  
//  
//  def makeData(flatten: Flatten[_, _], size: Int): DataSet = {
//     val l: List[(TableName,Tuple)] = 
//	   // we flatMap over the Iterator[(TableName,Header)] pairs to produce Iterator[(TableName,Tuple)]
//	   // flatMapping over the headers directly results in the Map collapsing all tuples with the same
//	   // table to the last such tuple inserted!!!!
//       flatten.headers.iterator.flatMap((p:(TableName, Header)) =>
//       {
//         val tableName = p._1
//         val header = p._2
//         val tuples = Gen.listOfN[Tuple](size, RelationGens.genRecord(header)).sample.get
//		 val keys = new collection.mutable.HashSet[Any]()
//		 val pkO: Option[Set[ColumnName]] = flatten.hints.tables(tableName).primaryKey
//		 pkO match {
//   		   case None => tuples.iterator.map((tableName, _))
//           // filter out rows with duplicate values for primary key column set
//		   case Some(pkCols) => {
//             val pk: List[ColumnName] = pkCols.toList
//			 tuples.iterator.filter((rec: Tuple) => {
//			   val pkVs: List[PrimExpr] = pk map rec
//			   if (keys(pkVs)) false
//			   else { keys += pkVs; true }
//			 }).map((tableName, _))
//		   }
//		 }
//       }).toList
//	 Enumeration.make(l)
//  }
//
//  /** 
//    * Create tables required by the Flatten in the backend. 
//    * @return Function from TableNames used by the Flatten to RefIDs in the backend.
//    */
//  def createTables[M[_]](flatten: Flatten[_, _], r: Run[M], backend: Backend[M]): Map[TableName,(RefID,Header)] = {
//     val hh = flatten.headers.transform((tn, header) => (header, flatten.hints.tables(tn)))
//     r.run(backend.createSchema(tn => r.run(backend.newRefID), hh))
//  }
// 
//  def createRefID[M[_]](tableName: TableName, backend: Backend[M]): M[RefID] = 
//  {
//    backend.newRefID 
//  } 
//}
