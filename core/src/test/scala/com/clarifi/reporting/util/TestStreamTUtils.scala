package com.clarifi.reporting
package util

import scalaz.{State, StreamT}
import State.{modify, state}
import scalaz.syntax.functor._
import org.scalacheck.{Prop, Properties}
import Prop.{?=, forAll, propBoolean}

object TestStreamTUtils extends Properties("StreamT utilities") {
  property("toStreamT/toIterable round-trip") = forAll {
    (xs: List[Int]) =>
      ?=(StreamTUtils toIterable (StreamTUtils toStreamT xs) toList,
         xs)
  }

  property("runStreamTOut trampolines long streams") = forAll{n: Short =>
    val len = (n:Int) - java.lang.Short.MIN_VALUE
    // XXX remove + in "+α" in scalaz 7.1
    val sstream = StreamT.unfoldM[({type λ[+α] = State[Int, α]})#λ, Unit, Int](len){n =>
      if (n <= 0) state(None)
      else modify((_:Int) + 2) as Some(((), n - 1))
    }
    val (p, sti) = StreamTUtils.runStreamTOut(sstream, -5)
    val before = p.fulfilled
    val slen = (StreamTUtils toIterable sti).size // run it once
    val after = p.fulfilled
    ((?=(before, len == 0) :| "unfulfilled before iff not empty")
       && (?=(slen, len) :| "length matches")
       && (after :| "fulfilled after")
       && (?=(p.get, len * 2 - 5) :| "output is final state"))
  }
}
