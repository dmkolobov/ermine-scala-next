package com.clarifi.reporting

package relational

abstract class SMEnv[F[+_]] {
  def apply(sm: SM): (OrderedProcedure[F, Record], Header, Reflexivity[ColumnName])
  def augment(h: Header, r: Reflexivity[ColumnName], m: OrderedProcedure[F, Record],
              cur: List[(String, String)], hist: List[(String, String)]):
         (OrderedProcedure[F, Record], Header, Reflexivity[ColumnName])
}

object SMEnv {
  import backends.DB

  val dummySmenv: SMEnv[DB] = new SMEnv[DB] {
    def apply(sm: SM) = sys.error("TODO: Implement a smenv")
    def augment(h: Header, r: Reflexivity[ColumnName], m: OrderedProcedure[DB, Record],
                cur: List[(String, String)], hist: List[(String, String)]) = sys.error("TODO: Implement a smenv")
  }
}
