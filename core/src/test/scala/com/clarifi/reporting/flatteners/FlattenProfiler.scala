package com.clarifi.reporting

//import scalaz._
//import Scalaz._
//import scalaz.scalacheck.ScalazArbitrary.TreeArbitrary
//
//import org.scalacheck._
//import Prop.{extendedAny => _, _}
//
//import com.clarifi.reporting.Reporting._
//import com.clarifi.reporting.backends._
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
//import DummyPAData._
//
//import scala.collection.immutable.ListMap

/**
 * @author JAT
 */

//object FlattenProfiler {
//
//  // Flatteners to profile
//  val primF = int("Value")
//  val listF = primF.rootList("Index")
//  val tupleF = (primF tuple int("Value2")).iterable("Index")
//  val nestedMapMemoF = {   
//    val intMemoF: RowFlattener[Int ::: Unit, Int] =
//      Memo.simple("ID", "ID", int("Key"))
//    val mapMemoF = intMemoF.orthogonalMap(primF)
//    val remappedMemoF = intMemoF.mapRootTableColNames(_ => "Key2")  
//    intMemoF.map(remappedMemoF.map(primitive[Int ::: Unit, Int]("Table", "Value"))).local
//  }
//  val treeMemoF = {
//    val parent = primitive[Unit, Int]("KeyTable", "ParentID") 
//    val key = primitive[Unit, Int]("KeyTable", "Name")
//    val value = primitive[Unit, Int]("ValueTable","Value")
//    Memo.simple("-", "ID", parent joinR key).orthogonalLabelTree(value).local
//  }
//    
//  //
//  // Main
//  //
//  def main(argv: Array[String]): Unit = {
//
//    // Number of iterations in one measurement and size of data per iteration.
//    val sampleSizes = List((10, 1000),(100, 100),(1000, 10),(10000, 1))
//
//    // Data generators
//    def primGen(size: Int) = 1
//    def listGen(size: Int) = List.range(0, size)
//    def tupleGen(size: Int) = listGen(size).zipWithIndex
//    def nestedMapGen(size: Int): Map[Int, Map[Int, Int]] = {
//      val n:Int = ceil(sqrt(size)).toInt
//      val child = tupleGen(n).toMap
//      listGen(n).map((_, child)).toMap
//    }
//    def treeGen(arity: Int)(size: Int): LabelTree[Int, Int] = {
//      if (size <= 1) 
//        LabelTree(size, Map())
//      else {
//        val keys = List.range(0, arity)
//        val child = treeGen(arity)((size-1) / arity)
//        LabelTree(size, keys.map((_, child)).toMap)
//      }
//    }
//    def dateGen(size: Int) = Gens.choose(2, math.max(2, size/5))
//    def groupGen(size: Int) = Gens.choose(2, math.max(2, size))
//    def paGen(size: Int): Report =
//      genReport(treeShapeGen(dateRangeGen, dateGen(size)), 
//                treeShapeGen(Gens.string, groupGen(size)), 
//                shapeToGroupingMap).sample.getOrElse(paGen(size))
//            
//    // Profile            
//    val stats = List(
//      profileAllSizes("primitive", true, 10, sampleSizes, primGen, (), primF),
//      profileAllSizes("rootList", true, 10, sampleSizes, listGen, (), listF),
//      profileAllSizes("Tuple of lists", true, 10, sampleSizes, tupleGen, (), tupleF),
//      profileAllSizes("Memo map", true, 10, sampleSizes, nestedMapGen, (), nestedMapMemoF),
//      profileAllSizes("Memo tree", true, 10, sampleSizes, treeGen(3), (), treeMemoF),
//      profileAllSizes("Dummy PA", true, 10, List((1, 1)), paGen, (), flattenLocalReport)
//    )
//   println(stats.map(_.mkString("\n")).mkString("\n--\n"))
//  }
//  
//  
//  def profileAllSizes[S, A](
//    name: String,
//    burn: Boolean, 
//    numTrials: Int, 
//    sampleSizes: List[(Int, Int)],
//    gen: Int => A,
//    initialState: S, 
//    flatten: Flatten[S, A]   
//  ): List[FlattenerStats] = {
//    sampleSizes map {
//      case (samples, sizes) => 
//        profileFlatten(name, burn, numTrials, samples, 
//                       gen(sizes), sizes, 
//                       initialState, flatten)
//    }
//  }
//  
//  private def profileFlatten[S, A](
//    name: String,
//    burn: Boolean, 
//    numTrials: Int, 
//    samples: Int,   
//    data: A, 
//    dataLength: Int,
//    initialState: S, 
//    flatten: Flatten[S, A]): FlattenerStats = {
//    val (stats, resultLength) = 
//        profile(burn, numTrials, samples)((flatten(data)!initialState).length)
//
//    FlattenerStats(name, stats, dataLength, resultLength)
//  }
//  
//  private def force(d: DataSet) = {
//    d.foreach(_ => ())
//  }
//  
//  def profile[A](burn: Boolean, numTrials: Int, samples: Int)(block: => A): (Stats, A) = {
//    if (burn)
//      block
//    
//    val stats = new Stats
//    var startTime: Long = 0
//    var stopTime: Long = 0
//    
//    for (i <- 0 until numTrials) {
//      
//      startTime = System.currentTimeMillis()
//      for (j <- 0 until samples) {
//        block
//      }
//      stopTime = System.currentTimeMillis()
//      val duration: Long = stopTime - startTime
//      stats.addTime(duration.asInstanceOf[Double] / samples)
//    }
//    
//    (stats, block)
//  }
//
//   class Stats {
//    var times = List[Double]()
//    def addTime(time: Double): Unit =
//      times = time :: times
//    
//    def min = times.min
//    def max = times.max
//    def mean = times.sum / times.length
//    def median = {
//      val sortedTimes = times.sortWith(_ < _)
//      val len = sortedTimes.length
//      val mid = len / 2
//      if (len % 2 == 0)
//        (sortedTimes(mid) + sortedTimes(mid+1)) / 2.0
//      else
//        sortedTimes(mid)
//    }
//    
//    def n = times.length
//    def stddev = sqrt(variance)
//    def variance = moment(2)
//    def skewness = moment(3) / pow(moment(2), 1.5)
//    def kurtosis = moment(4) / pow(moment(2), 2)
//    
//    private def moment(k: Int) = {
//      if (k == 0) 1.0
//      else if (k == 1) 0.0
//      else {
//        val mu = mean
//        times.map(x => pow(x - mu, k)).sum / times.length
//      }
//    }
//    
//    override def toString = "[min/mean/max/stddev/n] = " +
//        List(min, mean, max, stddev).map(_.truncate(2)).mkString("[", " / ", " / ") + n + "]"
//  }
//  
//  case class Truncatable(d: Double) {
//    def truncate(places: Int): String = {
//      val format = new java.text.DecimalFormat("0." + List.fill(places)("0").mkString)
//      format.format(d)
//    }
//  }
//  implicit def double2Truncatable(d: Double): Truncatable = Truncatable(d)
//  
//  
//    
//  case class FlattenerStats(name: String, stats: Stats, inputSize: Int, resultSize: Int) {
//    override def toString: String = 
//      name + "\n  " + 
//      stats.toString + 
//      "\n  [input cnt/output rows] = [" + inputSize + " / " + resultSize + "]"
//  }
//  
//}
