/*package com.clarifi.reporting
package backends

import org.scalacheck.{Properties, Prop}
import Prop.{AnyOperators, forAll, propBoolean, secure}

import com.clarifi.reporting.{Op, Predicate, Reflexivity,
                              RelationImpl => RI, RTag}
import com.clarifi.reporting.TaggedRelations._
import com.clarifi.reporting.PrimT.IntT
import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.Relation.{Relation, RelationShow}
import com.clarifi.reporting.Relations.{typed, distincted}
import com.clarifi.reporting.RTag.Distinctness

import scalaz.syntax.validation._
import scalaz.{Source => _}
import scalaz.std.AllInstances._
import scalaz.Show._
import scalaz.syntax.show._

import Amalgamation.optimizeRelation

object TestAmalgamation extends Properties("SQL relation optimizer") {
  type RT = RTag.Distinctness[Sourced]

  property("combine followed by project sanity") = secure {
    aabbProjComb[RT] match {
      case Relation(projTag, RI.Project(
        Relation(combTag, RI.Combine(Relation(refTag, RI.Ref(_, myHead, _)),
                                     _, _)), _)) =>
          (projTag.header._2 ?= Map("colAA" -> IntT(),
                                    "colCC" -> IntT()).success) &&
          (projTag.distinct ?= false) &&
          (combTag.header._2 ?= Map("colAA" -> IntT(), "colBB" -> IntT(),
                                    "colCC" -> IntT()).success) &&
          (combTag.distinct ?= true) &&
          (refTag.header._2 ?= Map("colAA" -> IntT(),
                                   "colBB" -> IntT()).success) &&
          (refTag.distinct ?= true)
      case x => false :| ("bad initial relation " + x.shows)
    }
  }

  property("combine followed by project optimized") = secure {
    optimizeRelation(aabbProjComb[RT]) match {
      case Relation(amaTag, RI.Amalgamation(
        List(Relation(refTag, RI.Ref(stbl, myHead, _))),
        prj, ren, cmb, Predicate.Atom(true))) =>
          (stbl ?= RefID("someTbl")) &&
          (amaTag.header._2 ?= Map("colAA" -> IntT(),
                                   "colCC" -> IntT()).success) &&
          (amaTag.distinct ?= false) &&
          (refTag.header._2 ?= Map("colAA" -> IntT(),
                                   "colBB" -> IntT()).success) &&
          (refTag.distinct ?= true) &&
          (prj ?= Set("colAA")) && (ren ?= Map.empty) &&
          (cmb ?= Map(aaPlusBb))
      case x => false :| ("bad initial relation " + x.shows)
    }
  }

  property("combine followed by rename optimized") = secure {
    optimizeRelation(aabbRenComb[RT]) match {
      case Relation(amatag, RI.Amalgamation(
        List(Relation(_, RI.Ref(_, _, _))),
        prj, ren, cmb, Predicate.Atom(true))) =>
          (("project" |: (Set("colAA", "colBB") =? prj))
           && ("rename empty" |: (ren ?= Map.empty))
           && ("rename in combine" |: (cmb.keySet.map(_.name) ?= Set("colDD"))))
    }
  }
}*/
