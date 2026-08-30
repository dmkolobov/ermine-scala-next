package com.clarifi.reporting

import scalaz.{Source => _, _}
import Scalaz._
import scalaz.scalacheck.ScalaCheckBinding._

import math.random

import org.scalacheck._
import org.scalacheck.Arbitrary.arbitrary
import org.scalacheck.Gen

import java.util.UUID

import com.clarifi.reporting.Gens._
import com.clarifi.reporting.PredicateGens._
import com.clarifi.reporting.AggFuncGens._
import com.clarifi.reporting.OpGens._

import relational._

import com.clarifi.reporting.PrimT._

/**
 * Contains generators used to create relations, as well as other
 * related items.
 */
object RelationGens {

  private val MinHeaderSize: Int = 1
  private val MaxHeaderSize: Int = 10

  /**
   * The maximum number of permitted nested relations.
   */
  val NoRelationLevel = -1

  /**
   * The maximum levels of nested relations permitted. This was originally
   * set to 5, but one of the properties in TestRawDataAPI tripped with
   * an error: 'SQLException: Too high level of nesting for select'.
   */
  private val MaxRelationLevel = 3

  /**
   * The maximum number of tuples generated when creating a relation
   * from a stream of tuples.
   */
  private val MinRecordSize = 1
  private val MaxRecordSize = 10

  /** A generator for StringExpr with Strings of non-zero length */
  def genStringExpr(len: Int = Gens.DefaultMaxStringSize): Gen[StringExpr] = Gens.string(len).map(StringExpr(false, _))

  private def gen1PrimExpr[T, TE](mk: (Boolean, T) => TE
                                )(implicit src: Arbitrary[T]): Gen[TE] =
    src.arbitrary map (mk(false, _))

  /**
   * A generator for IntExpr.
   */
  private def genIntExpr: Gen[IntExpr] = gen1PrimExpr(IntExpr)

  /** A generator for DoubleExpr */
  private def genDoubleExpr: Gen[DoubleExpr] = gen1PrimExpr(DoubleExpr.apply)

  /**
   * A generator for DateExpr for dates between 1/1/1902 and 2/5/2038. These
   * dates were selected because they are the min and max dates downstream.
   */
  def genDateExpr: Gen[DateExpr] = Gens.date.map(DateExpr(false, _))

  private def genUuidExpr: Gen[UuidExpr] = arbitrary[UUID].map(UuidExpr(false, _))

  /* A generator for BooleanExpr */
  private def genBooleanExpr: Gen[BooleanExpr] = gen1PrimExpr(BooleanExpr)

  private def genNullExpr: Gen[NullExpr] = simplePrimT map (_.withNull |> (NullExpr(_)))

  val genNumExpr: Gen[PrimExpr] =
    Gen.oneOf(gen1PrimExpr(ByteExpr), gen1PrimExpr(ShortExpr),
              genIntExpr, gen1PrimExpr(LongExpr), genDoubleExpr)

  private def genStringLen(len: Int = Gens.DefaultMaxStringSize): Gen[Int] = Gen.choose(1,len)

  /**
   * Generate a primitive expression by selecting equally among all
   * primitve expressions
   */
  def genPrimExpr: Gen[PrimExpr] = Gen.oneOf(
    genStringExpr(),
    gen1PrimExpr(ByteExpr),
    gen1PrimExpr(ShortExpr),
    genIntExpr,
    gen1PrimExpr(LongExpr),
    genDoubleExpr,
    genDateExpr,
    genBooleanExpr,
    genUuidExpr,
    genNullExpr
  )

  /**
   * Generates a Type to be used in a Header. The boolean primitive is not
   * included since this generator is used for the combine relation,
   * which is not defined for booleans.
   */
  def genPrimTypeForCombine: Gen[PrimT] = for {
    pe <- Gen.oneOf(genStringExpr(), genIntExpr, genDoubleExpr)
    // TODO: Nullable Combines
  } yield pe.typ

  /**
   * Generates a Type to be used in a Header, specifically for the Aggregate
   * relation since the aggregate functions only apply to certain column
   * types.
   */
  private def genPrimTypeForAggFunc: Gen[PrimT] = for {
    pe <- Gen.oneOf(genIntExpr, genDoubleExpr)
  } yield pe.typ

  /**
   * Generates a Type to be used in a Header, specifically for the Filter
   * relation since the predicates only apply to certain column
   * types.
   */
  private def genPrimTypeForPredicate: Gen[PrimT] = for {
    pe <- Gen.oneOf(genStringExpr(), genIntExpr, genDoubleExpr, genDateExpr)
  } yield pe.typ


  def simplePrimT: Gen[PrimT] = {
    import Gen.const
    Gen.oneOf(
      genStringLen().map(StringT(_,false)), const(ByteT()),
      const(ShortT()), const(IntT()), const(LongT()), const(DoubleT()),
      const(DateT()), const(BooleanT()), const(UuidT())
    )
  }

  def primT: Gen[PrimT] = Gen.oneOf(
    simplePrimT,
    simplePrimT.map(_.withNull)
  )

  def simplePrimExpr(t: PrimT): Gen[PrimExpr] = t match {
    case StringT(l,n) => if (l == 0) genStringExpr() else genStringExpr(l)
    case ByteT(_) => gen1PrimExpr(ByteExpr)
    case ShortT(_) => gen1PrimExpr(ShortExpr)
    case IntT(_) => genIntExpr
    case LongT(_) => gen1PrimExpr(LongExpr)
    case DoubleT(_) => genDoubleExpr
    case DateT(_) => genDateExpr
    case BooleanT(_) => genBooleanExpr
    case UuidT(_) => genUuidExpr
  }

  /**
   * Generator for PrimExpr that is based off a given Type.
   */
  private def primExpr(t: PrimT): Gen[PrimExpr] = {
    val simple = simplePrimExpr(t)
    if (t.nullable) Gen.oneOf(simple, Gen.const(NullExpr(t)))
    else simple
  }

  private def genOptionExpr(t: PrimT): Gen[PrimExpr] = Gen.oneOf(
    Gen.const(NullExpr(t)),
    simplePrimExpr(t)
  )

  /**
   * Generates a Header, which is a Map[String, Type],
   * where Type is a Type.Variable.
   *
   * The number and type of columns in the header is arbitrary,
   * but is at least between MinHeaderSize and MaxHeaderSize.
   *
   * The resultant header map is of the form Column# -> Type where # is
   * the original index in the generated list of PrimExpr.
   */
  def genVariableHeader: Gen[Header] =
    _genVariableHeader(columnNamer(0))

  /**
   * Returns strings of the form Column# where the # starts
   * at the given starting value and is incremented each
   * time a name is generated.
   */
  def columnNamer(start: Int)(cur: Int): String = "Column" + (start + cur)

  /**
   * Generates a header with some given minimum number of columns; the column
   * names are given by a function.
   *
   * @param namer given the number of the column, create a name for it; 0-based
   * @param min the minimum number of columns to generate
   */
  private def _genVariableHeader(namer: Int => String, min: Int = MinHeaderSize, max: Int = MaxHeaderSize): Gen[Header] = {
    if (min <= 0) sys.error("Cannot have a min <= 0: " + min)
    else {
      for {
        n <- Gen.choose(min, max)
        xs <- Gen.listOfN(n, genPrimExpr)
      } yield xs.zipWithIndex.foldLeft(Map[String, Type]())((m: Map[String, Type], t: (PrimExpr, Int)) => m + ((namer(t._2), t._1.typ)))
    }
  }

  //
  // Below are the generators for the different types of relations.
  //

  /**
   * Generates a literal tuple from a pre-existing header by creating a
   * PrimExpr using the type information and name from the header.
   */
  def genLiteral(h: Header): Gen[Relation[Nothing, Nothing]] = h.toList.foldLeftM(Map[ColumnName, PrimExpr]())((a, attr) => for {
      expr <- primExpr(attr._2)
      r <- Gen.const(a ++ Map(attr._1 -> expr))
    } yield r).map(x => SmallLit(NonEmptyList(x)))

  def genLiteral: Gen[Relation[Nothing, Nothing]] = for {
    expr <- genPrimExpr
    r <- genLiteral(expr)
  } yield r

  def genLiteral(expr: PrimExpr): Gen[Relation[Nothing, Nothing]] =
    Gen.listOfN(10, Gen.alphaLowerChar).map(k => SmallLit(NonEmptyList(Map(k.mkString("") -> expr))))
  def genZero: Gen[Relation[Nothing, Nothing]] = Gen.const(RelEmpty(Map()))
  def genOne: Gen[Relation[Nothing, Nothing]] = Gen.const(SmallLit(NonEmptyList(Map())))
  def genEmpty: Gen[Relation[Nothing, Nothing]] = for {
    h <- genVariableHeader
    r <- genEmpty(h)
  } yield r
  def genEmpty(h: Header): Gen[Relation[Nothing, Nothing]] = Gen.const(RelEmpty(h))

  /**
   * Generates a join relation that, depending on the given boolean, will
   * either have at least one common header (if true), or have distinct
   * headers (if false).
   *
   * @param commonHeaders true to have at least one common header; otherwise
   * false to have zero common headers (to create a cartesian product)
   */
  def genJoin(commonHeaders: Boolean,
                    minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                   : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Option[Header])] = for {
    h <- genVariableHeader
    t <- _genJoinWithHeader(commonHeaders, h, NoRelationLevel, minRecords, maxRecords)
  } yield t

  /** Generates a JoinOn relation */
  def genJoinOn[M[+_]:Monad](minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize):
    Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Set[(String, String)])] = for {
      h1 <- genVariableHeader
      h2 <- genVariableHeader.map((x: Header) => x.toList.zipWithIndex.map {
        // Ensure disjoint names
        case ((k, v), i) => (columnNamer(h1.size)(i), v)
      }.toMap)
      r1 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
      r2 <- _genRelationAnyNestedWithHeader(h2, NoRelationLevel, minRecords, maxRecords)
      // (\ d i -> fmap (\ f -> f >>= \ e -> e) (Data.Traversable.traverse d i))
      // was Gen.sequence, whose Buildable scalacheck 1.15 will not infer here
      ch <- ((h1.toStream |@| h2.toStream)((_, _)) map {
              case ((k1, v1), (k2, v2)) => Gen.oneOf(true, false) map (b =>
                if (b && (v1 == v2)) Stream((k1, k2)) else Stream())
            }).foldRight(Gen.const(List.empty[Stream[(String, String)]])) {
              (g, acc) => for { x <- g ; xs <- acc } yield x :: xs
            }
    } yield (r1, r2, ch.flatten.toMap.map(_.swap).map(_.swap).toSet)

  /**
   * Similar to the above genJoin(), except that the header is given
   * instead of being generated on each call.
   *
   * @param commonHeaders true to have at least one common header; otherwise
   * false to have zero common headers (to create a cartesian product)
   * @param h the header to use / start with when creating the two relations
   * that make up the join relation
   */
  private def _genJoinWithHeader(commonHeaders: Boolean, h: Header,
                    level: Int = MaxRelationLevel, minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                   : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Option[Header])] = {
    if (commonHeaders)
      _genJoinCommon(h, level, minRecords, maxRecords)
    else
      _genJoinCartesianProduct(h, level, minRecords, maxRecords)
  }

  /**
   * Similar to the above genJoin(), except that the join relation is
   * created and the decision to create a natural join or cartesian product
   * is randomized.
   *
   * @param h the header to use / start with when creating the two relations
   * that make up the join relation
   */
  private def _genJoinNested(h: Header,
                    level: Int = MaxRelationLevel, minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                   : Gen[Relation[Nothing, Nothing]] = {
    for {
      (r1, r2, _) <- _genJoinWithHeader(scala.math.random > .5d, h, level, minRecords, maxRecords)
    } yield Join(r1, r2)
  }

  /**
   * Generates a join relation that has at least one common column.
   *
   * This is done by taking a header with N number of columns, then
   * splitting that header into two headers that will be used for a
   * projection (and additions of more tuples to guarantee some
   * non-unique rows).
   */
  private def _genJoinCommon(h: Header,
                                  level: Int, minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                                 : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Option[Header])] = {
    for {
      // create 'master' relation that will be split via two projections
      //
      r1 <- _genRelationAnyNestedWithHeader(h, level, minRecords, maxRecords)

      // once the master relation is created, split up its header
      // (which may differ from the given header, depending on how
      // the relation was created)
      //
      h2 = Typer.relTyper(r1).toOption.get
      n <- Gen.choose(1, h2.size - 1)
      (common, other) = h2.splitAt(n)
      (other1, other2) = if (other.size == 1) (other, other) else other.splitAt(other.size / 2)
      (ph1, ph2) = (other1 ++ common, other2 ++ common)

      // create another relation to union with the projected one to introduce
      // non-unique tuples
      //
      u1 <- genRelationWithHeader(ph1, minRecords, maxRecords)
      u2 <- genRelationWithHeader(ph2, minRecords, maxRecords)
      // create the projected relations, then yield the union of
      // the projected relations with the other relation
      //
      (p1, p2) = (Project(r1, Header.proj(ph1)),
                  Project(r1, Header.proj(ph2)))
    } yield (Union(p1, u1), Union(p2, u2), Some(common))
  }

  /**
   * Generates join relation that will be cartesian products such that
   * no column names will be identical.
   */
  private def _genJoinCartesianProduct(h1: Header,
                                            level: Int, minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                                           : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Option[Header])] = for {
    h2 <- _genVariableHeader(columnNamer(h1.size))
    r1 <- _genRelationAnyNestedWithHeader(h1, level, minRecords, maxRecords)
    r2 <- _genRelationAnyNestedWithHeader(h2, level, minRecords, maxRecords)
  } yield (r1, r2, None)

  /**
   * Generates a relation with an arbitrary header whereby the relation
   * is backed by a RefID.
   */
  def genRelation(minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                       : Gen[Relation[Nothing, Nothing]] = for {
    h <- genVariableHeader
    r <- genRelationWithHeader(h, minRecords, maxRecords)
  } yield r

  /**
   * Generates a union relation based on the given header and arbitrary
   * types of nested relations (i.e. union of two joins).
   */
  private def _genUnionNested(h: Header, level: Int = MaxRelationLevel,
                                minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                                : Gen[Relation[Nothing, Nothing]] =
    _genSameHeaderNested(h, Union(_, _), level, minRecords, maxRecords)

  /**
   * Generates a minus relation based on the given header and arbitrary
   * types of nested relations (i.e. union of two joins).
   */
  private def _genMinusNested(h: Header, level: Int = MaxRelationLevel,
                                minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                                : Gen[Relation[Nothing, Nothing]] =
    _genSameHeaderNested(h, Minus(_, _), level, minRecords, maxRecords)

  /**
   * Generates a relation based on two other relations (i.e. union or minus).
   */
  private def _genSameHeaderNested(h: Header,
                                f: (Relation[Nothing, Nothing], Relation[Nothing, Nothing]) => Relation[Nothing, Nothing],
                                level: Int = MaxRelationLevel,
                                minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                                : Gen[Relation[Nothing, Nothing]] = for {
    // it is possible that these nested relations are joins, which changes
    // the headers; that can't be helped, so instead of preventing it,
    // take it into account and simply project the original header columns
    // to omit any additional ones
    //
    r1 <- _genRelationAnyNestedWithHeader(h, level, minRecords, maxRecords)
    r2 <- _genRelationAnyNestedWithHeader(h, level, minRecords, maxRecords)
  } yield f(Project(r1, Header.proj(h)),
            Project(r2, Header.proj(h)))

  /**
   * Generates two arbitrary relations with the same header.
   */
  def genRelationSameHeader2(minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                    : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing])] = for {
    h1 <- genVariableHeader
    r1 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
    r2 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
  } yield (r1, r2)

  /**
   * Generates three arbitrary relations with the same header.
   */
  def genRelationSameHeader3(minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize)
                    : Gen[(Relation[Nothing, Nothing], Relation[Nothing, Nothing], Relation[Nothing, Nothing])] = for {
    h1 <- genVariableHeader
    r1 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
    r2 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
    r3 <- _genRelationAnyNestedWithHeader(h1, NoRelationLevel, minRecords, maxRecords)
  } yield (r1, r2, r3)

  /**
   * Generator for any type of relation; if new relation generators are added,
   * this function should be updated to include selecting from them. More
   * specific generators are below.
   */
  def genRelationAny(level: Int = MaxRelationLevel)
                          : Gen[Relation[Nothing, Nothing]] = for {
    r <- Gen.oneOf(genLiteral, genZero, genOne, genEmpty, _genRelationAnyNested(level))
  } yield r

  /**
   * Generator for an n-level nested relation. The maximum depth is capped, but
   * the relation could be nested less depending on the type of relations that
   * are used in the nesting (i.e. a join of two empties)
   */
  private def _genRelationAnyNested(level: Int)
                                    : Gen[Relation[Nothing, Nothing]] = for {
    h <- genVariableHeader
    t <- _genRelationAnyNestedWithHeader(h, level)
  } yield t


  private def _genRelationAnyNestedWithHeader(h: Header,
                                                    level: Int = MaxRelationLevel,
                                                    minRecords: Int = MinRecordSize,
                                                    maxRecords: Int = MaxRecordSize)
                                                    : Gen[Relation[Nothing, Nothing]] = {
    def nest(level: Int = MaxRelationLevel, h: Header): Gen[Relation[Nothing, Nothing]] = level match {
      case NoRelationLevel =>
        // special case where a relation is generated and materialized
        // on the backend without any nesting
        //
        genRelationWithHeader(h, minRecords, maxRecords)
      case 1 => for {
        r <-  if (1 == h.size)
                Gen.oneOf(genLiteral(h), genEmpty(h), genRelationWithHeader(h, minRecords, maxRecords))
              else
                Gen.oneOf(genEmpty(h), genRelationWithHeader(h, minRecords, maxRecords))
      } yield r
      case _ => {
        // not at the last level, so combine relations into various operations,
        // like a join of two unions, for example
        //
        for {
          r <-  if (1 == h.size)
                  Gen.oneOf(genLiteral(h),
                            genEmpty(h),
                            genRelationWithHeader(h, minRecords, maxRecords)
                  )
                else
                  Gen.oneOf(genEmpty(h),
                            genRelationWithHeader(h, minRecords, maxRecords),
                            _genJoinNested(h, level - 1, minRecords, maxRecords),
                            _genUnionNested(h, level - 1, minRecords, maxRecords),
                            _genMinusNested(h, level - 1, minRecords, maxRecords)
                  )
        } yield r
      }
    }

    nest(level, h)
  }

  //
  // Additional generators are below which restrict or add to the generated
  // relations
  //

  /**
   * Generates either a One or a Zero.
   */
  def genZeroOrOne: Gen[Relation[Nothing, Nothing]] = Gen.oneOf(genZero, genOne)

  /**
   * Generator for a (Relation[Nothing, Nothing], List[String]) pair, where the relation
   * is generated from the given generator and the list of headers is randomly
   * selected from the relation header.
   */
  def genRelationHeaderTuple(g: Gen[Relation[Nothing, Nothing]]): Gen[(Relation[Nothing, Nothing], Set[String])] = {
    for {
      r <- g
      h = Typer.relTyper(r).toOption.get.filter(t => random > 0.5)
    } yield (r, h.keys.toSet)
  }

  /**
   * Generator for the rename relation to provide the relation itself plus
   * the column to rename and what to rename it to.
   */
  def genRelationRename(g: Gen[Relation[Nothing, Nothing]]): Gen[(Relation[Nothing, Nothing], String, String)] = for {
    r <- g
    h = Typer.relTyper(r).toOption.get.keySet.toList
    i <- Gen.choose(0, h.size - 1)
  } yield (r, h(i), h(i) + "_Renamed")

  /**
   * Generator for a (Relation[Nothing, Nothing], Predicate) pair, where the relation
   * is generated from the given generator and the predicate is generated
   * from the relation (some predicates need column names from the header).
   */
  def genRelationPredicateTuple(useSimpleRelation: => Boolean = {scala.math.random > .5},
                                level: Int = MaxRelationLevel,
                                minRecords: Int = MinRecordSize,
                                maxRecords: Int = MaxRecordSize)
                              : Gen[(Relation[Nothing, Nothing], Predicate)] = {
    // randomly select if the generated relation will be 'simple'
    // (empty, one, zero etc) or more complex
    //
    if (useSimpleRelation) {
      for {
        r <- Gen.oneOf(genLiteral, genZero, genOne, genEmpty)
        p <- genPredicateAtom
      } yield (r, p)
    }
    else {
      for {
        h <- genVariableHeader
        t <- genPrimTypeForPredicate
        r <- _genRelationAnyNestedWithHeader((h + ("CommonColumn1" -> t)) + ("CommonColumn2" -> t),
                                             level,
                                             minRecords,
                                             maxRecords)
        p <- genPredicateAny(("CommonColumn1", "CommonColumn2"))
      } yield (r, p)
    }
  }

  /**
   * Generator for a (Relation[Nothing, Nothing], Op, Type) tuple, where the
   * Op uses columns from the relation.
   */
  def genCombineRecord : Gen[(Relation[Nothing, Nothing], Op, Type)] = for {
    h <- genVariableHeader
    t <- genPrimTypeForCombine
    r <- genRelationWithHeader((h + ("CommonColumn1" -> t)) + ("CommonColumn2" -> t))
    op <- genOpAny(t, "CommonColumn1", "CommonColumn2")
  } yield (r, op, t)

  /**
   * Generator for a (Relation[Nothing, Nothing], AggFunc, Type) tuple, where the
   * AggFunc uses a column from the relation.
   */
  def genAggregateTuple : Gen[(Relation[Nothing, Nothing], AggFunc, Type)] = for {
    h <- genVariableHeader
    t <- genPrimTypeForAggFunc
    r <- genRelationWithHeader((h + ("AggColumn" -> t)))
    f <- genAggFuncAny(t, "AggColumn")
  } yield (r, f, t)

  /**
   * Generator that selects some desired numer of columns from a relation
   * produced by the given generator. The desired number of columns is
   * always produced unless the original generated relation does not
   * have that many columns, in which case the List will be empty.
   *
   * The types of the columns are not guaranteed to be the same.
   */
  def genRelationColumnsTuple(g: Gen[Relation[Nothing, Nothing]], n: Int): Gen[(Relation[Nothing, Nothing], Option[List[String]])] = {
    for {
      r <- g
      h = Typer.relTyper(r).toOption.get
      t = h.size match {
            case i if (i >= 0 && i < n) => None
            case j => {
              // randomly select from the headers the desired number of
              // columns; if the number of columns remaining equals the
              // number of desired columns, then just add them directly
              // and avoid the possibility of them not being randomly
              // selected
              //
              // this is done by zipping the columns with a Range that counts
              // down from size, s,  to 1, resulting in the following series:
              //  ((s, h_s), (s-1, h_s-1), ..., (1, h_1))
              // so for exaxmple:
              //  ((3, header_one), (2, header_two), (1, header_three))
              //
              Some(Range.inclusive(1, h.size).reverse.zip(h.keys).foldLeft(List[String]())((l: List[String], t: (Int, String)) => {
                if ((n != l.size) && ((n - l.size) == t._1 || random > .5))
                  // have not yet collected the desired number of columns,
                  // so add this to the List (either because it randomly
                  // worked out that way, or because the number of columns
                  // is running out and it has to be added)
                  //
                  t._2 :: l
                else
                  // either the desired number of columns was already
                  // selected, or the random selection was false for
                  // this column; in either case, just return the List
                  //
                  l
              }))
            }
          }
    } yield (r, t)
  }

  /**
   * Generates Tuples based on a header to match up the types.
   */
  def genRecord(h: Header): Gen[Record] = {
    h.mapValues((v: Type) => primExpr(v)).foldLeft(Gen.const(Map[String, PrimExpr]()))(
      (z: Gen[Map[String, PrimExpr]], kv: (String, Gen[PrimExpr])) => {
        for {
          m <- z
          v <- kv._2
        } yield m + ((kv._1, v))
      }
    )
  }

  /**
   * Generates a relation with a specific header. The relation will be created
   * via Scanner.load of randomly generated tuples.
   */
  def genRelationWithHeader(h: Header, minRecords: Int = MinRecordSize, maxRecords: Int = MaxRecordSize): Gen[Relation[Nothing, Nothing]] = {
    val genrecord = genRecord(h)
    for {
      n <- Gen.choose(minRecords, maxRecords)
      l <- Gen.listOfN(n, genrecord)
    } yield LetR(ExtMem(Literal(l.toNel.get)), List(), VarR(RTop))
  }
}
