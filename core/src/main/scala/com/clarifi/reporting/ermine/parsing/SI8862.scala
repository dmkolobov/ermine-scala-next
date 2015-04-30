package com.clarifi.reporting.ermine
package parsing

import scalaz.Monad
import scalaparsers.Diagnostic

/** These definitions work around
  * https://issues.scala-lang.org/browse/SI-8862 .
  *
  * To test whether they're still necessary, remove the below
  * definitions within the object and see if everything still
  * compiles.
  *
  * To remove this hack, delete this object and all imports that refer
  * to it.
  *
  * @todo Remove in Scala 2.12.0 (maybe 2.11.3?)
  */
object SI8862 {
  @deprecated("Suppressors for definitions in package object", since="use-scala-parsers")
  def parserDiagnostic: Diagnostic[Parser] = parsing.parserDiagnostic

  @deprecated("Suppressors for definitions in package object", since="use-scala-parsers")
  def parserMonad: Monad[Parser] = parsing.parserMonad

  @deprecated("Suppressors for definitions in package object", since="use-scala-parsers")
  def word(s: String): Parser[String] = parsing.word(s)

  implicit def `SI-8862 parser Diagnostic`: Diagnostic[Parser] =
    parsing.parserDiagnostic

  implicit def `SI-8862 parser Monad`: Monad[Parser] = parsing.parserMonad

  implicit def `SI-8862 word`(s: String): Parser[String] = parsing.word(s)
}
