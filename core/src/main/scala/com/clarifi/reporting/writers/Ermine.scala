// Ermine integration
package com.clarifi.reporting.writers

import scalaz.syntax.id._
import scalaz.syntax.std.all.ToTuple2Ops

// import com.clarifi.reporting.Provenance.RefUsage._ // for Disjunction monoid
import com.clarifi.reporting.ermine.{Data, Global, Prim, Runtime}
import com.clarifi.reporting.ermine.session.SessionEnv

object Ermine {
  /** Destructure and execute an Ermine report in the context of the
    * given Writer.
    *
    * @param report A report for `Layout.Report.runReport`.
    */
  def runReport[F[_], C](w: Writer[F, C], report: Runtime
                       )(implicit s: SessionEnv): F[C] = {
    assume(s.termNames isDefinedAt Global("Layout.Report", "runReport"))
    assume(s.loadedModules.isDefinedAt("Control.Monad.State"))
    def getv(mod: String, dfn: String) = Global(mod, dfn) |> s.termNames |> s.env
    report.whnfMatch("Writer.runErmineReport"){
      case Data(Global("Layout.Report", "Renderable", _), _) =>
        getv("Layout.Report", "runReport'")
      case Data(Global("Control.Monad.State", "State", _), _) =>
        getv("Layout.Report", "runReport")
    }(Prim(w), report).extract
  }

  // TODO: Port cababilities later
  /** Answer what capabilities are required to run `report`.
    *
    * @param report An unresolved Ermine report. */
  /* def reportCapability(report: Runtime)(implicit s: SessionEnv
                     ): CapabilitySink.capabilityOf.Result =
    ((runReport (new CapabilitySink, report) run)
     fold (_ |+| _)) */
}
