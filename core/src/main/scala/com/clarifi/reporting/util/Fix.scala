package com.clarifi.reporting.util

private[reporting] object Fix {
  /** Least fixpoint of `f`. */
  @inline def fix[A](f: (=> A) => A): A = {
    lazy val a: A = f(a)
    a
  }
}
