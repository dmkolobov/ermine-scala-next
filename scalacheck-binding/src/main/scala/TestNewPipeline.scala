package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }
import com.clarifi.reporting.ermine.session.Session.{ Literal, SourceFile }
import com.clarifi.reporting.ermine.tools.G1Compare

import org.scalacheck._
import Prop._
import scalaparsers.Supply

/** 4.1c: a whole module through the NEW pipeline into the REAL
  * typechecker, compared against the old load name-by-name. */
object TestNewPipeline extends Properties("NewPipeline 4.1c") {
  private val fx = ErmineFixture()
  import fx._
  private val fxChain = ErmineFixture()

  private val src =
    """module NPT where
      |import Function
      |import List
      |import Primitive
      |
      |double : Int -> Int
      |double q = q + q
      |applied = double 3
      |
      |data Box a = MkBox a
      |unbox (MkBox q) = q
      |boxed = unbox (MkBox 7)
      |
      |swap (a, b) = (b, a)
      |""".stripMargin.replace("\n", "\r\n")  // stdlib-style CRLF for realism

  private def moduleTypes(load: SessionEnv => Unit): Map[String, Type] =
    session { implicit s =>
      loadModules(List("Function", "List", "Primitive"))
      load(s)
      s.termNames.collect { case (g, v) if g.module == "NPT" => g.string -> v.extract }
    }

  property("a whole module loads and typechecks through the new pipeline") = secure {
    val oldTypes = moduleTypes { implicit s =>
      S.load(Literal(src, "NPT"))
      ()
    }
    val newTypes = moduleTypes { implicit s =>
      implicit val su: Supply = supply
      val (ps0, mh) = S.parse(ModuleParsers.moduleHeader("NPT"),
        ErParseState.mk("NPT", src, "NPT"))
      val (ps, m) = NewPipeline.readModule("NPT", src, mh)
      S.loadModule(ps, m, (_: Map[Global, Type.Con]) => None)
      ()
    }
    val sameKeys = (oldTypes.keySet ?= newTypes.keySet) :| "exported name sets"
    val sameTypes = oldTypes.keys.toList.map { k =>
      (newTypes.contains(k) &&
        G1Compare.alphaEq(oldTypes(k), newTypes(k), G1Compare.Bij.empty).isDefined) :|
        s"$k: OLD ${oldTypes(k).toString.take(120)} NEW ${newTypes.get(k).map(_.toString.take(120))}"
    }.foldLeft(proved: Prop)(_ && _)
    sameKeys && sameTypes
  }

  property("chained modules load through the live switch") = secure {
    val srcA = "module NPA where\nimport Primitive\n\nvalA : Int\nvalA = 1\n\ndata Wrap q = MkWrap q\nunwrap (MkWrap q) = q\n"
    val srcB = "module NPB where\nimport NPA\nimport Primitive\n\nvalB = valA + unwrap (MkWrap 2)\n"
    val r = fxChain.session { implicit s0 =>
      fxChain.loadModules(List("Primitive"))(s0)
      implicit val s: SessionEnv = s0.withPipelineNew(true)
      S.load(Literal(srcA, "NPA"))
      S.load(Literal(srcB, "NPB"))
      s.termNames.keys.filter(g => g.module == "NPA" || g.module == "NPB").map(_.string).toSet
    }
    (r ?= Set("valA", "unwrap", "MkWrap", "valB")) :| r.toString
  }
}

