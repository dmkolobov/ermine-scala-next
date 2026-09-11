package scalaparsers

import scalaparsers._

//import ParsingUtil._
import scala.collection.immutable.List
import scala.collection.immutable.TreeSet
import scalaz.{ Name => _, _ }
import scalaz.Scalaz._
import scalaz.Lens._

/** Used to track the current indentation level
  *
  * @author EAK
  */

case class ParseState[S](
  loc:            Pos,
  input:          String,
  offset:         Int = 0,
  s:              S,
  layoutStack:    List[LayoutContext[S]] = List(IndentedLayout[S](1,"top level")),
  bol:            Boolean = false,
  /** 7.1a: the furthest input offset this PARSE has examined.  A shared
    * mutable cell, not a value: `copy` carries the same cell, so the mark
    * survives the state a failed `attempt` throws away.  The DEFAULT is
    * `MarkOff`, whose `reach` is empty -- the strict path pays nothing for a
    * number it never reads; the editor's `SurfaceParsers.moduleMarked`
    * installs a live cell.  See `Mark`. */
  mark:           Mark = MarkOff
) extends Located {
  def depth: Int = layoutStack match {
    case IndentedLayout(n,_)   :: _ => n
    case BracedLayout(_,_,_,_) :: _ => 0
    case List()                     => 0
  }
  //import Parsing[S].eofIgnoringLayout
  def layoutEndsWith: Parser[S,Any] = {
    def eof: Parser[S,Unit] = Parser((s, _) => {
      s.mark.reach(s.offset + 1)  // 7.1a: the end-of-input probe examines `offset`
      if (s.offset == s.input.length) Pure(())
      else Fail(None, List(), Set("end of input"))
    })
    layoutStack.collectFirst({ case p : BracedLayout[S] => p.endsWith }).getOrElse(eof scope "end of top level layout")
    }
  def tracing = true // if we ever add an option we can add it to the case class
}

/** LayoutContext are used to track the current indentation level for parsing */
sealed abstract class LayoutContext[S]
case class IndentedLayout[S](depth: Int, desc: String) extends LayoutContext[S] {
  override def toString = "indented " + desc + " (" + depth + ")"
}
case class BracedLayout[S](left: String, endsWith: Parser[S,Any], unmatchedBy: Parser[S,Nothing], right: String) extends LayoutContext[S] {
  override def toString = left + " " + right
}

object ParseState {
  def mk[S](filename: String, content: String, initialState: S) = {
    ParseState(
      loc = Pos.start(filename, content),
      input = content,
      s = initialState
    )
  }

}
