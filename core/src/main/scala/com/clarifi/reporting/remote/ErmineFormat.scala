package com.clarifi.reporting
package remote

import f0.{Source => _, _}
import f0.Formats._
import f0.Writers._
import f0.Readers._

import ermine._
import remote.{Format => RF}

import scalaparsers.{Assoc, AssocL, AssocN, AssocR}

object ErmineFormat {
  type ErminePrimF = S10[StringF, IntF, LongF, BooleanF, DoubleF
                       , ByteF, ShortF, LongF, StringF, RF.PrimTF
                        ]

  /** A sampling of data that could reasonably expected to be in Prim or
    * Box for known (i.e. selector) use cases, and is actually
    * reasonably serializable.
    */
  lazy val erminePrimW: Writer[Any, ErminePrimF] =
    s10W(stringW, intW, longW, booleanW, doubleW,
         byteW, shortW, longW, stringW, RF.primTW
    ){(str, int, date, boolpr, double,
       byte, short, long, uuid, primt) => _ match {
        case s: String => str(s)
        case i: Int => int(i)
        case d: java.util.Date => date(d.getTime)
        case b: Boolean => boolpr(b)
        case d: Double => double(d)
        case b: Byte => byte(b)
        case s: Short => short(s)
        case l: Long => long(l)
        case u: java.util.UUID => uuid(u.toString)
        case t: PrimT => primt(t)
        // Hi!  If you got here, you should add a case for your data
        // to erminePrimW, erminePrimR, and ErminePrimF, or use
        // Ermine data instead of Scala data.
        case o => sys error ("Missing ErmineFormat.erminePrim* for %s (class %s)"
                              format (o, o.getClass))
      }}

  /** Complement to erminePrimW. */
  lazy val erminePrimR: Reader[Any, ErminePrimF] = union10R(
    stringR,
    intR,
    longR map (new java.util.Date(_)),
    booleanR,
    doubleR,
    byteR,
    shortR,
    longR,
    stringR map java.util.UUID.fromString,
    RF.primTR
  )

  type GlobalF = (StringF :: StringF ::
                    S4[UnitF, IntF, IntF :: S3[UnitF, UnitF, UnitF], IntF])

  lazy val globalW: Writer[Global, GlobalF] = {
    val assocW = s3W(unitW, unitW, unitW){
      (l, r, n) => (_:Assoc) match {
        case AssocL => l(())
        case AssocR => r(())
        case AssocN => n(())
      }}
    val fixityW = s4W(unitW, intW, tuple2W(intW, assocW), intW){
      (id, pref, in, post) => (_:Fixity) match {
        case Idfix => id(())
        case Prefix(p) => pref(p)
        case Infix(p, a) => in((p, a))
        case Postfix(p) => post(p)
      }}
    tuple3W(stringW, stringW, fixityW) cmap {
      case Global(m, s, f) => (m, s, f)
    }
  }

  lazy val globalR: Reader[Global, GlobalF] = {
    val assocR = union3R(unitR map (_ => AssocL),
                         unitR map (_ => AssocR),
                         unitR map (_ => AssocN))
    val fixityR = union4R(
      unitR map (_ => Idfix),
      intR map Prefix,
      p2R(intR, assocR)(Infix),
      intR map Postfix)
    p3R(stringR, stringR, fixityR)(Global)
  }

  type RuntimeF[A] = S7[ErminePrimF, ErminePrimF
                      , DynamicF
                      , UnitF, RepeatF[A]
                      , GlobalF :: RepeatF[A], RepeatF[StringF :: A]]

  def runtimeW = fixFW[Runtime, RuntimeF]{self =>
    s7W(erminePrimW, erminePrimW,
        RF.extW[Nothing, Nothing](nothingW.erase, nothingW.erase),
        unitW, repeatW(self),
        tuple2W(globalW, repeatW(self)), RF.mapW(stringW, self)
    ){(prim, box,
       rel,
       erel, arr,
       data, rec) => (_: Runtime).whnf match {
        case Prim(p) => prim(p)
        case Box(p) => box(p)
        case Rel(r) => rel(r)
        case EmptyRel => erel(())
        case Arr(a) => arr(a)
        case Data(n, a) => data((n, a))
        case Rec(t) => rec(t)
        case Fun(_) => sys error "Ermine functions cannot be serialized"
        case Bottom(_) => sys error "Ermine errors cannot be serialized"
        case e => sys error ("Unrecognized Ermine data %s" format e)
      }}}

  def runtimeR = fixFR[Runtime, RuntimeF]{self =>
    val arrself = listR(self) map (_.toArray)
    union7R(erminePrimR map (Prim(_)),
            erminePrimR map (Box(_)),
            RF.extR[Nothing, Nothing](nothingR.erase, nothingR.erase) map (Rel(_)),
            unitR map (_ => EmptyRel),
            arrself map Arr,
            p2R(globalR, arrself)(Data),
            RF.mapR(stringR, self) map (Rec(_)))
  }
}
