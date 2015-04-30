package com.clarifi.reporting.flatteners

import java.util.Date
import java.util.UUID

import scalaz._
import Scalaz._

import org.scalacheck._
import Prop._

import com.clarifi.reporting.Gens._
import com.clarifi.reporting.PrimType._
import com.clarifi.reporting.backends.Backends

import com.clarifi.reporting._
import flatteners.Flatteners._
import Flatteners.Implicits._
import Lens._

//import Memo._

/**
 * @author JAT, EAK
 */

object TestFlatteners extends Properties("Flatteners") {
  implicit def testStringLen: Int = 40
  implicit def primString: PrimType[String] = PrimType.primString(2000)
  implicit def arbString: Arbitrary[String] = Arbitrary[String](Gens.string(testStringLen-1))

  type DS = Stream[(TableName,Record)]

  class CheckHeader(
    tuple: Record,
    header: Header,
    name: String = "header"
  ) extends Properties(name) {
    property("everything-present") = tuple.keySet ?= header.keySet
    // property("types-match") = tuple.mapValues(_.typ) ?= header
    property("complies-with-header") = tuple.forall(ab => ab._2.typ.isa(header(ab._1)))
  }

  def checkHeader(record: Record, header: Header): Prop = new CheckHeader(record, header)

  /** Answer duplicates in `xs` according to some `key`. */
  def duplicates[A, B](xs: Traversable[A])(key: A => B = identity _): Iterable[A] =
    xs.groupBy(key).values.flatMap(_.tail)

  /** Update the value at a particular key. */
  def updateIn1[K, V, V1 >: V](m: Map[K, V], k: K)(default: => V)(f: V => V1) =
    m.updated(k, f(m.get(k).getOrElse(default)))

  def sanityCheck[T[_,-_], S, A](f: Flattener[T, S, A], output: DS, name: String = "sanity-check") =
    new Properties(name) {
      property("is-sane") = Prop.all(output.map({ case (tn, tup) => f.schema.get(tn) match {
        case Some(header) => checkHeader(tup, header)
        case None    => "missing header" |: false
      }}):_*)

      // check that we don't emit multiple records in a given table
      // with the same primary key
      private def pk(t: TableName) =
        f.hints.tables.get(t).flatMap(_.primaryKey)
      property("primary keys are unique") =
        (duplicates(output) {case (tableName, record) =>
           (tableName,
            (for (pkey <- pk(tableName); if !pkey.isEmpty)
             yield record.filterKeys(pkey)).getOrElse(record))
        }) ?= List.empty

      // check that any foreign keys described by the hints in the
      // flattener link fields of the same type
      private def fks(t: TableName) =
        f.hints.tables.get(t).map(_.foreignKeys)
      // Each table's column groups that are known to be
      // referenceable.
      private val foreignReferencees =
        (f.hints.tables.values
         .map(_.foreignKeys.mapValues(_.map(_.toList.map(_._2))))
         .foldLeft(Map.empty[TableName, Set[List[ColumnName]]]) {
            (m, m2) => std.map.unionWith(m, m2)(_ ++ _)
         })

      property("foreign key references are resolvable") =
        (((foreignReferencees.mapValues
           (_.toIterable.map(fk => (fk, Set.empty[List[PrimExpr]])).toMap),
           (true: Prop)))
         /: output) {
          (state, row) =>
            val ((pastReferencees, errors), (tableName, record)) = (state, row)
            // Save bits from previous rows known to be referenceable
            // as foreign keys.  Presumably, a row can refer to itself.
            val availReferencees =
              updateIn1(pastReferencees, tableName)(Map.empty) (
                _.map {case (fk, refs) => (fk, refs + fk.toList.map(record apply _))})
          (availReferencees,
           Prop.all(errors +: (for {
             fkPerTable <- fks(tableName).getOrElse(Map.empty)
             (ftabName, fks) = fkPerTable
             availfrs = availReferencees.get(ftabName).getOrElse(Map.empty)
             oneFkSet <- fks
             oneFk = oneFkSet.toList
           } yield (availfrs(oneFk.map(_._2))
                    contains oneFk.map(record apply _._1)) :|
                          "Foreign reference %s required by %s".format(oneFk, record))
                    .toSeq:_*))
       }._2
    }

  abstract class FlattenerProperties[T[_,-_],S,A](
    f: T[S,A],
    initialState: S,
    checkFinalState: (S => Prop) = (s: S) => true,
    name: String = "flattener"
  )(implicit witness: T[S,A] <:< Flattener[T,S,A], A: Arbitrary[A]) extends Properties(name) {

    case class Ctx(value: A, finalState: S, testEnum: DS)

    def all(test: Ctx => Prop) = forAll (Arbitrary.arbitrary[A].map(a => {
      val (finalState, testEnum) = dataset(f, a, initialState)
      Ctx(a, finalState, testEnum)
    }))(test)

    def dataset(flattener: T[S,A], a: A, s: S): (S, DS)

    property("sane")           = all (s => sanityCheck[T,S,A](f, s.testEnum.toStream))
    property("final-state-ok") = all (s => checkFinalState(s.finalState))
  }

  class TableFlattenerProperties[S, A: Arbitrary](
    f: TableFlattener[S, A],
    initialState: S,
    checkOutput: (A,DS) => Prop = (a:A,s:DS) => true,
    checkFinalState: (S => Prop) = (s: S) => true,
    name: String = "flattener"
  ) extends FlattenerProperties[TableFlattener, S, A](f, initialState, checkFinalState, name) {
    def dataset(f: TableFlattener[S,A], a: A, s: S) = f(a).toStream.apply(s)
    property("tuples-ok")      = all (s => checkOutput(s.value, s.testEnum))
  }

  class RowFlattenerProperties[S, A: Arbitrary](
    f: RowFlattener[S, A],
    initialState: S,
    checkOutput: (A,Record,DS) => Prop = (a:A,t:Record,s:DS) => true,
    checkFinalState: (S => Prop) = (s: S) => true,
    name: String = "flattener"
  ) extends FlattenerProperties[RowFlattener, S, A](f, initialState, checkFinalState, name) {
    def dataset(f: RowFlattener[S,A], a: A, s0: S) = {
      val (s1, (_, ds1)) = f(a)(s0)
      ds1.toStream.apply(s1)
    }

    def allRow(test: (Ctx, Record) => Prop) = forAll (Arbitrary.arbitrary[A].map(a => {
      val (s1, (t, ds1)) = f(a).apply(initialState)
      val (finalState, ds2) = ds1.toStream.apply(s1)
      (Ctx(a, finalState, ds2), t)
    }))(test.tupled)

    property("row-header-ok") = allRow((s, t) => checkHeader(t, f.header))
    property("tuples-ok") = allRow((s, t) => checkOutput(s.value, t, s.testEnum))
  }

  val primField = "Field1"
  val primField2 = "Field2"
  val primField3 = "Field3"
  val primField4 = "Field4"
  val rootTable  = "Root"
  val indexField = "Index"

  class StateProperties[S](name: String = "state") extends Properties(name) {
    def prim[T: PrimType] = primitive[T](primField)
    def prim2[T: PrimType] = primitive[T](primField2)
    def prim3[T: PrimType] = primitive[T](primField3)
    def prim4[T: PrimType] = primitive[T](primField4)
  }

  class MonoidProperties[S: Monoid](name: String = "zero") extends StateProperties[S](name) {
    def checkTableFlattener[A: Arbitrary](
      name: String,
      f: TableFlattener[S, A],
      checkOutput: (A, DS) => Prop = (a:A,s:DS) => true:Prop,
      checkFinalState: S => Prop = s => s == mzero[S]
    ) = include(new TableFlattenerProperties[S, A](f, mzero[S], checkOutput, checkFinalState, name))

    def checkRowFlattener[A: Arbitrary](
      name: String,
      f: RowFlattener[S, A],
      checkOutput: (A, Record, DS) => Prop,
      checkFinalState: S => Prop = s => s == mzero[S]
    ) = include(new RowFlattenerProperties[S, A](f, mzero[S], checkOutput, checkFinalState, name))
  }

  trait Check {
    def check[T:PrimType:Arbitrary](name: String)
    check[Boolean]("Boolean")
    check[Date]("Date")
    check[Double]("Double")
    check[Long]("Long")
    check[String]("String")
    check[UUID]("UUID")
  }

  trait Check2 extends Check { outer =>
    def check[S:PrimType:Arbitrary](s: String) {
      new Check {
        def check[T: PrimType:Arbitrary](t: String) = {
          outer.check2[S,T](s,t)
        }
      }
    }
    def check2[S:PrimType:Arbitrary, T:PrimType:Arbitrary](s: String, t: String)
  }

  include(new StateObliviousProperties[Int])

  class StateObliviousProperties[S: Monoid](name: String = "state-oblivious") extends MonoidProperties[S](name) {
    include(new MonoidProperties[S]("prim") with Check {
      def check[A:PrimType:Arbitrary](name: String) = checkRowFlattener[A](
        name,
        prim[A],
        (a:A,t:Record,s:DS) => (t ?= Map(primField -> toPrim(a))) && s.isEmpty
      )
    })

    include(new MonoidProperties[S]("contramap") {
      def checkPrimContramap[A:Arbitrary,B:PrimType](name: String, f: A => B) = checkRowFlattener[A](
        name,
        prim[B] contramap f,
        (a,t,s) => (t ?= Map(primField -> toPrim(f(a)))) && s.isEmpty
      )

      checkPrimContramap[Long, Boolean]("positive", (l: Long) => l > 0)
      checkPrimContramap[Int, Double]("halve", (i: Int) => i / 2.0)
      checkPrimContramap[String, Int]("length", _.length)
      checkPrimContramap[Date, String]("dateFormat", "" + _)
    })

    include(new MonoidProperties[S]("joins") with Check2 {
      def check2[A: PrimType:Arbitrary,B: PrimType:Arbitrary](A: String, B: String) = {
        include(new MonoidProperties[S]("[" + A + "," + B + "]") {
          val (a, b) = (prim[A], prim2[B])
          def expectedJoin(ab: (A,B)) =
            Map(primField -> toPrim(ab._1), primField2 -> toPrim(ab._2))
          def checkPair(
            name: String,
            fab: RowFlattener[S, (A,B)],
            expected: ((A,B)) => Record
          ) = include(new MonoidProperties[S](name) {
            checkRowFlattener[(A,B)]("flatten", fab, (ab,t,s) => (t ?= expected(ab)) && s.isEmpty)
          })
          checkPair("join", a join b, expectedJoin)
          checkPair("orthogonalJoin", a.orthogonalJoin(b).local.lens(trivialLens[S]), expectedJoin)
        })
      }
    })


    include(new MonoidProperties[S]("examples") with Check {
      def check[A:PrimType:Arbitrary](A: String) = include(new MonoidProperties[S](A) {
        val t = TableName("Table1")
        val i = prim[A]
        checkTableFlattener[A]("table", i table t, (a, s) => s ?= Stream((t,(i(a) eval mzero[S])._1)))
        checkTableFlattener[A]("table.mapRootColumnNames", i table t mapRootColumnNames (x => primField2), (a, s) => s ?= Stream ((t,Map(primField2 -> (i(a) eval mzero[S])._1(primField)))))
        checkTableFlattener[Set[A]](
          "table.set",
          i table t unfold { (s:Set[A]) => if (s.isEmpty) none else some((s.head, s.tail)) },
          (a, s) => s.size ?= a.size
        )
      })
    })

    include(new MonoidProperties[S]("examples") with Check2 {
      def check2[A:PrimType:Arbitrary,B:PrimType:Arbitrary](A: String, B:String) = include(new MonoidProperties[S]("[" + A + "," + B + "]") {
        val i = prim[A]
        val j = prim2[B]
        val t1 = TableName("Table1")
        val t2 = TableName("Table2")
        val tt = (i table t1) tuple (j table t2)
        checkTableFlattener[(A, B)]("tuple", tt, (a, s) => "size" |: (s.size ?= 2))
        property("tuple.roots.match") = tt.roots == tt.schema.keySet.toSet
      })
    })

    //include
  }

  include(new MonoidProperties[Unit]("unit") {
    include(new MonoidProperties[Unit]("examples") {
      val t = TableName("Table1")
      val i = prim[Int]
      checkTableFlattener[Int]("table.localState", i table t localState 1000, (a, s) => s ?= Stream((t,(i(a) eval (()))._1)))
    })
  })
}


/*


    include(new MonoidProperties[S]("nest") {
      def guid = "AGUID"
      def checkNest[A:Arbitrary](name: String, p: Flatten[S, A]) = include(new Properties(name) {
        val np = p.nest(rootTable, guid)
        case class Ctx(a: A) {
          val nestedEnum = p.zero(a)
          val testEnum = np.zero(a)
          val (rootTuples, nestedTuples) = testEnum.partition(t => t._1 == rootTable)
          val rootTuple = rootTuples.head._2
          val expectedEnum: DataSet =
            nestedTuples.map(t => (t._1, t._2.filter(p => p._1 != guid)))
        }
        def all(pred: Ctx => Prop) = forAll(Arbitrary.arbitrary[A].map(Ctx))(pred)
        property("non-empty")    = all (c => !c.rootTuples.isEmpty)
        property("has-guid")     = all (c => c.rootTuple.contains(guid))
        property("tuples-equal") = all (c => c.nestedEnum.toSet == c.expectedEnum.toSet)
        property("sanity")       = all (c => sanityCheck(np, c.testEnum.toList))
      })
      checkNest("Date",prim[Date].set)
      checkNest("Int", prim[Int].set)
      checkNest("(Long,Boolean)", prim[Long] tuple prim2[Boolean])
    })

  // tests for flatteners that only work with Unit state
  include(new MonoidProperties[Unit]("Unit") {
    include(new MonoidProperties[Unit]("list") {
      def checkPrimList[A:PrimType:Arbitrary](name: String) = checkFlatten[List[A]](
        name,
        prim[A].list(indexField),
        l => l.zipWithIndex.foldLeft[DataSet](Enumeration())((acc,next) =>
           acc ++ Enumeration(
             (primTable, Map(primField -> toPrim(next._1), indexField -> toPrim(next._2))))))
      checkPrimList[Double]("Double")
      checkPrimList[Boolean]("Boolean")
    })

    include(new MonoidProperties[Unit]("indexedMap") {
        def checkIndexedMap[A:PrimType:Arbitrary, B:PrimType:Arbitrary](name: String) =
          checkFlatten[Map[A,B]](
            name,
            prim[A].indexedMap(indexField, prim2[B]),
            m => m.zipWithIndex
              .map(rec => ((rec._1._1, rec._2), (rec._1._2, rec._2)))
              .foldLeft[DataSet](Enumeration())(
                (acc, next) => acc ++ Enumeration(
                  (primTable, Map(
                    primField -> toPrim(next._1._1),
                    indexField -> toPrim(next._1._2))),
                  (primTable2, Map(
                    primField2 -> toPrim(next._2._1),
                    indexField -> toPrim(next._2._2))))))
        checkIndexedMap[Long,Date]("[Long,Date]")
        checkIndexedMap[Int,Boolean]("[Int,Boolean]")
    })

    def listTuples[K: PrimType:Arbitrary,V: PrimType:Arbitrary](l: List[(K, V)],
                        rootTable: TableName,
                        keyTable: TableName, keyCol: ColumnName,
                        valueTable: TableName, valueCol: ColumnName): DataSet =
      l.zipWithIndex.foldLeft(Enumeration(): DataSet)((acc:  DataSet, next: ((K, V), Int)) => {
        val idx = (indexField -> toPrim(next._2))
        acc ++ Enumeration((keyTable, Map(keyCol -> toPrim(next._1._1), idx)),
                           (valueTable, Map(valueCol -> toPrim(next._1._2), idx)),
                           (rootTable, Map(idx)))})

    include(new MonoidProperties[Unit]("indexWithRoot") {
      def checkIndexWithRoot[A:PrimType:Arbitrary,B:PrimType:Arbitrary](name: String) =
        checkFlatten[Enumeration[(A,B)]](
          name,
          (prim[A] tuple prim2[B]).indexWithRoot(rootTable,indexField),
          l => listTuples(l.toList, rootTable, primTable, primField, primTable2, primField2))
      checkIndexWithRoot[Double,Date]("[Double,Date]")
      checkIndexWithRoot[Int,Long]("[Int,Long]")
    })

    include(new MonoidProperties[Unit]("keyedMap") {
      def checkKeyedMap[A:PrimType:Arbitrary,B:PrimType:Arbitrary,C:PrimType:Arbitrary](name: String) =
        checkFlatten[Map[C, Enumeration[(A,B)]]](
          name,
          prim3[C].keyedMap(prim[A].tuple(prim2[B]).indexWithRoot(rootTable,indexField)),
          m => m.foldLeft[DataSet](Enumeration())((acc, next) => {
            val lt = listTuples(next._2.toList, rootTable, primTable, primField, primTable2, primField2)
            val key = Map(primField3 -> toPrim(next._1))
            acc ++ lt.map((t: (TableName, Tuple)) => (t._1, key ++ t._2))}))
      checkKeyedMap[Double,Date,Int]("Map[Int,Enumeration[(Double,Date)]]")
    })
  })


  class MemoProperties(name: String) extends Properties(name) {
    def checkMemoFlattenWithState[S, A:Arbitrary](
      s: String,
      f: Flatten[S, A],
      initialState: S
    ) = include(new Properties(s) {
      case class Ctx(a: A) {
        val (fs0, test0Enum) = f(a)(initialState)
        val (fs1, test1Enum) = f(a)(initialState)
        val (fs2, test2Enum) = f(a)(fs0)
        val (fs3, test3Enum) = f(a)(fs2)
        val got = test1Enum.toList
      }
      def all(pred: Ctx => Prop) = forAll(Arbitrary.arbitrary[A].map(Ctx))(pred)
      property("sane")             = all (c => sanityCheck[S,A](f, c.got))
      property("fresh-run-stable") = all (c => c.test0Enum.toSet == c.test1Enum.toSet)
      property("memo-run-stable")  = all (c => c.test2Enum.toSet == c.test3Enum.toSet)
      property("steady-state")     = all (c => c.fs0 == c.fs2)
      property("non-increasing-tuple-count") = all(c => c.test2Enum.length <= c.test0Enum.length)
    })

    def checkMemoFlatten[S:Monoid, A:Arbitrary](s: String, f: Flatten[S, A]) =
      checkMemoFlattenWithState[S, A](s, f, mzero[S])
  }

  include(new MemoProperties("Memo") {
    def booleanMemoFlatten: Flatten[Boolean ::: Unit, Boolean] =
      Memo.simple("ID", "ID", primitive[Unit, Boolean]("KeyTable", "Key"))
     checkMemoFlatten("boolean", booleanMemoFlatten)

    def booleanDoubleMemoFlatten =
      booleanMemoFlatten.joinR(
          Flatten.primitive[Boolean ::: Unit, Double]("ValueTable", "Value"))
     checkMemoFlatten("booleanDouble", booleanDoubleMemoFlatten)

    // Map of maps with distinct memoizers
    def booleanMemoFlatten2: Flatten[Boolean ::: Unit, Boolean] =
      Memo.simple("ID2", "ID2", primitive[Unit, Boolean]("Key2Table", "Key2"))
    def mapBooleanMapBooleanDoubleSeparateMemoFlatten =
      booleanMemoFlatten2.orthogonalMap(
        booleanDoubleMemoFlatten.enumeration.contramap((m: Map[Boolean, Double]) => Enumeration.make(m)))
     checkMemoFlatten("mapBooleanMapBooleanDoubleSeparate",
                      mapBooleanMapBooleanDoubleSeparateMemoFlatten)

    // Map of maps with shared memoizers
    def remappedBooleanMemoFlatten = booleanMemoFlatten.mapRootTableColNames(_ => "ID3")
    def mapBooleanMapBooleanDoubleSharedMemoFlatten =
      booleanMemoFlatten.map(
        remappedBooleanMemoFlatten.map(
          primitive[Boolean ::: Unit, Double]("ValueTable", "Value")))
    checkMemoFlatten("mapBooleanMapBooleanDoubleShared",
                      mapBooleanMapBooleanDoubleSharedMemoFlatten)

    // Compare shared to separate memoizers
    val xor = Map(true  -> Map(true -> 0d, false -> 1d),
                  false -> Map(true -> 1d, false -> 0d))
    val (separateFacts, separateKeys) =
      mapBooleanMapBooleanDoubleSeparateMemoFlatten.zero(xor).partition(
        _._1 == "ValueTable")
    val (sharedFacts, sharedKeys) =
      mapBooleanMapBooleanDoubleSharedMemoFlatten.zero(xor).partition(
        _._1 == "ValueTable")
    property("xorSharedKeySize")    = 2 == sharedKeys.length
    property("xorSeparateKeySize")  = 4 == separateKeys.length
    property("xorSharedFactSize")   = 4 == sharedFacts.length
    property("xorSeparateFactSize") = 4 == separateFacts.length

    // OrthogonalLabelTree
    def orthogonalLabelTreeStringDoubleMemoFlatten = {
      val parent = primitive[Unit, Int]("KeyTable", "ParentID")
      val key = primitive[Unit, String]("KeyTable", "Name")
      val value = primitive[Unit, Double]("ValueTable","Value")
      Memo.simple("-", "ID", parent joinR key) orthogonalLabelTree value
    }

    checkMemoFlatten("orthogonalLabelTreeStringDouble",
                     orthogonalLabelTreeStringDoubleMemoFlatten)

    // LabelTree
    def labelTreeStringDoubleMemoFlatten = {
      val parent = primitive[Unit, Int]("KeyTable", "ParentID")
      val key = primitive[Unit, String]("KeyTable", "Name")
      val value = primitive[(Int, String) ::: Unit, Double]("ValueTable","Value")
      Memo.simple("-", "ID", parent joinR key) labelTree value
    }
    checkMemoFlatten("labelTreeStringDouble",
                     labelTreeStringDoubleMemoFlatten)

    // Nested, shared label tree
    def labelTreeBooleanLabelTreeBooleanDoubleSharedMemoFlatten = {
      val parent = primitive[Unit, Int]("KeyTable", "ParentID")
      val key = primitive[Unit, Boolean]("KeyTable", "Key")
      val memo = Memo.simple("-", "ID", parent joinR key)
      val memo2 = memo.mapRootTableColNames(_ => "ID2")
      val value = primitive[(Int, Boolean) ::: Unit, Double]("ValueTable","Value")
      memo.labelTree(memo2.labelTree(value))
    }
     checkMemoFlatten("labelTreeBooleanLabelTreeBooleanDoubleShared",
                     labelTreeBooleanLabelTreeBooleanDoubleSharedMemoFlatten)

    // Named label tree
    def namedLabelTreeStringDoubleMemoFlatten = {
      val parent = primitive[Unit, Int]("KeyTable", "ParentID")
      val key = primitive[Unit, String]("KeyTable", "Name")
      val value = primitive[(Int, String) ::: Unit, Double]("ValueTable","Value")
      Memo.simple("-", "ID", parent joinR key) namedLabelTree value
    }
    checkMemoFlatten("namedLabelTreeStringDouble",
                     namedLabelTreeStringDoubleMemoFlatten)
  })
}
*/
