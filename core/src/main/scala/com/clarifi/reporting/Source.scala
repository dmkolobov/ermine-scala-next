package com.clarifi.reporting

import scalaz._
import Show._
import Equal._
import Scalaz._

case class Source(source: String = "", namespace: List[String] = List())

object Source {
  implicit def sourceEq: Equal[Source] = equalBy(x => (x.namespace, x.source))

  implicit def sourceShow: Show[Source] = showFromToString
}


