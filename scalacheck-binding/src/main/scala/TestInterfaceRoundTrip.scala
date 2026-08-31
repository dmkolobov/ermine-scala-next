package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.{ CheckMethod, Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.session.Session.SourceFile

import org.scalacheck._
import Prop._

import java.nio.file.{ Files, Path }

/** Post-G1 debt D0 (Decision g): the interface ROUND-TRIP under the new
  * pipeline, as a repeatable test.  A cold new-pipeline load with
  * useInterface ON writes .ei files into a temp workspace; a FRESH
  * session over the same workspace warm-loads from those interfaces
  * (CheckMethod.Interface — no body inference) and must answer evals
  * identically.  A third session proves the OLD pipeline reads the
  * new-written interfaces too (mixed-version workspaces).
  */
object TestInterfaceRoundTrip extends Properties("Interface round-trip") {

  private val srcA =
    """module RtA where
      |import Primitive as P
      |import Function
      |
      |infixl 6 <+>
      |
      |(<+>) : Int -> Int -> Int
      |(<+>) = (+_P)
      |
      |data Box a = MkBox a
      |unbox (MkBox a) = a
      |
      |grow : Int -> Box Int
      |grow n = MkBox (n <+> 10)
      |""".stripMargin

  private val srcB =
    """module RtB where
      |import RtA
      |import Primitive as P
      |
      |rtUse n = unbox (grow n) <+> 1
      |""".stripMargin

  private def workspace(): Path = {
    val d = Files.createTempDirectory("ermine-rt")
    Files.write(d.resolve("RtA.e"), srcA.getBytes("UTF-8"))
    Files.write(d.resolve("RtB.e"), srcB.getBytes("UTF-8"))
    d
  }

  private def session(dir: Path, pipelineNew: Boolean)(implicit su: scalaparsers.Supply): SessionEnv = {
    implicit val printer: Printer = Printer.ignore
    implicit val e: SessionEnv = new SessionEnv(
      _typeCheck = Some(true), _useInterface = Some(true),
      _pipelineNew = Some(pipelineNew))
    Lib.preamble
    e.loadFile = SourceFile.inOrder(SourceFile.filesystem(dir.toString) _, e.loadFile)
    e
  }

  private def answers(e: SessionEnv)(implicit su: scalaparsers.Supply): (String, Int) = {
    implicit val printer: Printer = Printer.ignore
    implicit val env: SessionEnv = e
    val (ty, r) = Session.eval("rtUse 5", Map("RtB" -> (None, List(), false)))
    (Pretty.prettyType(ty, -1).toString, r.extract[Int])
  }

  property("new-pipeline cold write, fresh warm read, same answers") = secure {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    implicit val printer: Printer = Printer.ignore
    val dir = workspace()

    // the dep cache is process-global; deps cached by OTHER suites carry
    // their sessions' useInterface baked into the read closures (a
    // useInterface=false dep answers readInterface with None forever),
    // which breaks the interface hash chain for our warm load — clear it
    ErmineFixture.literalLock.synchronized {
      Session.depCache.clear()

      val cold = session(dir, pipelineNew = true)
      Session.loadModules(List("RtB"))(cold, su, printer)
      val coldMethod = cold.loadedModules.get("RtB")
      val coldAns = answers(cold)
      val eiA = Files.exists(dir.resolve("RtA.ei"))
      val eiB = Files.exists(dir.resolve("RtB.ei"))

      Session.depCache.clear()
      val warm = session(dir, pipelineNew = true)
      Session.loadModules(List("RtB"))(warm, su, printer)
      val warmMethod = warm.loadedModules.get("RtB")
      val warmAns = answers(warm)

      Session.depCache.clear()
      val old = session(dir, pipelineNew = false)
      Session.loadModules(List("RtB"))(old, su, printer)
      val oldMethod = old.loadedModules.get("RtB")
      val oldAns = answers(old)

      (coldMethod ?= Some(CheckMethod.Full))          :| s"cold method $coldMethod" &&
      (eiA && eiB)                                    :| "interfaces written" &&
      (warmMethod ?= Some(CheckMethod.Interface))     :| s"warm method $warmMethod" &&
      (warmAns ?= coldAns)                            :| s"warm $warmAns vs cold $coldAns" &&
      (oldMethod ?= Some(CheckMethod.Interface))      :| s"old-warm method $oldMethod" &&
      (oldAns ?= coldAns)                             :| s"old-warm $oldAns vs cold $coldAns" &&
      (coldAns._2 ?= 16)                              :| s"value ${coldAns._2}"
    }
  }
}
