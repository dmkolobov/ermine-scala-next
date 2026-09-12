package com.clarifi.reporting
package writers

/*
import scalaz.NonEmptyList

import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import Arbitrary.arbitrary
import Prop.{AnyOperators, forAll, propBoolean, secure}

import com.clarifi.{reporting => ccr}
import ccr.PrimExpr

object TestWriters extends Properties("writer API") {
  implicit val primexpr = Arbitrary(ccr.RelationGens.genPrimExpr)

  property("toPrimExprNel encodes all PrimExprs") = forAll {(pe: PrimExpr) =>
    (Writer toPrimExprNel pe.value map (_.value)) ?= NonEmptyList(pe.value)
  }

  property("toPrimExprNel survives Ermine foreign calls") = secure {
    val ermineF = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
    import ermineF._
    Prop.all(eval("foreignTrials", Map("Layout.Report.ChoiceTest" -> all))
             .extract[List[_]] map {
      case (pes: NonEmptyList[PrimExpr], shown: String) =>
        ((pes map (_ extractNullableString "null!!!") list)
         mkString ("++")) ?= shown
      case nonsense => false :| ("nonsensical " + nonsense.toString)
    }:_*)
  }
}*/
