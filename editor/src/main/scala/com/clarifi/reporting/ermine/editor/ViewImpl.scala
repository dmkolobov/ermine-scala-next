package com.clarifi.reporting.ermine.editor

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.editor.Backend.{MCursor,Loc}
import com.clarifi.reporting.ermine.session.Session
import com.clarifi.reporting.ermine.syntax._
import scalaparsers.Loc._

import javafx.application.Platform
import javafx.embed.swing.JFXPanel
import javafx.event.EventHandler
import javafx.scene.Node
import javafx.scene.Parent
import javafx.scene.control._
import javafx.scene.input.MouseEvent
import javafx.scene.input.MouseButton
import javafx.scene.input.KeyEvent
import javafx.scene.input.KeyCode
import javafx.scene.layout._
import javafx.scene.paint.Color
import javafx.scene.text.Font
import javafx.scene.shape.Rectangle
import javafx.geometry._
import javafx.beans.value.ObservableValue
import javafx.beans.value.ChangeListener
import javafx.beans.property._
import javafx.util.Duration
import java.io.FileInputStream
import java.io.StringWriter

import scala.math
import scala.math.max
import scala.collection.mutable.HashMap
import scala.collection.immutable.{IndexedSeq, TreeSet}
import scalaz.Monad
import scalaz.Functor
import scalaz.Cofree
import scalaparsers.{AssocL, AssocN, AssocR}

trait Nat[F[_],G[_ <: UB],UB] {
  def apply[A <: UB](f: String=>F[A]): G[A]
}

class ViewImpl[F[_],E,S](val B: Backend[F,E,S], val de: Nat[List, Omnibox, OBItem])
  extends View[F,E,S,Loc,Node]
{
  import Renderers._
  import WrapStyle._
  import CellF._
  implicit def toNothingCell(cf: CellF[CellN]): CellN = Cell(cf)
  implicit def toBounds(cr: Rect): Bounds = new BoundingBox(cr.x, cr.y, cr.w, cr.h)
  import CellPathElement._
  import JFXUtil._

  case class CaretLoc(val path: CellPath)
  {
    def update(caret: Node) =
      for {
        cp <- cellPane(path)
        c <- cp.cellRectAt(path)
      } yield {
        val b = caret.localToParent(caret.sceneToLocal(cp.localToScene(c.extract)))
        caret.resizeRelocate(b.getMinX() - 1, b.getMinY(), b.getWidth() + 1, b.getHeight())
      }

    def down(): CaretLoc = getCell(path).flatMap(find(path, _, isLeaf[Unit])).map(_._1).map(CaretLoc(_)).getOrElse(this)

    def up(): CaretLoc = if (path.size == 1) this else CaretLoc(path.dropRight(1))

    def left(): CaretLoc = findPrevious(path, parentCell, isLeaf[Unit]).map(p => CaretLoc(p._1)).getOrElse(this)

    def right(): CaretLoc = findNext(path, parentCell, isLeaf[Unit]).map(p => CaretLoc(p._1)).getOrElse(this)

    def nextHole(): CaretLoc = findNext(path, parentCell, isHole[Unit]).map(p => CaretLoc(p._1)).getOrElse(this)

    def prevHole(): CaretLoc = findPrevious(path, parentCell, isHole[Unit]).map(p => CaretLoc(p._1)).getOrElse(this)
  }

  trait Operation {
    def start: Unit
    def cancel: Unit
  }

  private var rootNode: Option[Node] = None
  private var statusBar: Option[Pane] = None
  private lazy val bindingContainer = buildBindingContainer
  private var bindings: Map[(TermVar,Int),Node] = Map()
  private lazy val caret = createCaret
  private val caretLoc: SimpleObjectProperty[Option[CaretLoc]] = new SimpleObjectProperty(None)
  private var operation: Option[Operation] = None

  //TODO JWW
  def renderers: List[Renderer] = Nil

  def load(S : S) : Unit = {
    rootNode = Some(B.at(Empty())(S).map(m => build(m)).
                   getOrElse(sys.error("no module in S")))
  }

  def changeRenderer(at: Loc, to: Key): Unit = sys.error("TODO JWW")

  def apply(a: B.Action[_,_], at: Loc): Unit = sys.error("TODO JWW")

  //if load has not yet been called, None is returned
  def root: Option[Node] = rootNode

  //////////////////////////////////////////////////////////////////////////////////////////

  def build(m : Module): Node =
  {
    val n = topLevel
    //TODO JWW: handle explicits differently?
    addBindings(m.implicits++m.explicits)
    n
  }

  def addBindings(bs: List[Binding]): Map[(TermVar,Int),Node] = {
    val entries:Map[(TermVar,Int),Node] = bs.map(binding(_)).foldLeft(Map[(TermVar,Int),Node]())( (m,alts) => {
        val c = buildVBox(6)
        c.getStyleClass().add("binding")
        alts.foldLeft(m)( (ma,b) => {
                            val node = declaration(declareCell(b._1, b._2)(b._3)(b._4))
                            compose(c)(node)
                            ma + ( (b._1, b._2) -> node)
                          })
      })

    bindings = bindings ++ entries
    compose(bindingContainer)(entries.keySet.toSeq.sortWith( (a,b) =>
        (for {
          na <- a._1.name
          nb <- b._1.name
        } yield(na.string.toUpperCase < nb.string.toUpperCase)).
        getOrElse(false) ).map(bindings(_)) :_*)
    entries
  }

  def binding(b: Binding): List[(TermVar,Int,Option[CellN],CellN)] =
    b.alts.zipWithIndex.map {
      case (a,i) => (b.v, i, patternCell(b.v, i, a.patterns.map(pattern(_))), bindingTerm(a.body))
    }

  def patternCell(bv: TermVar, ai: Int, ps: List[CellN]): Option[CellN] = if (ps.isEmpty) None else Some(delimited((bv,ai), ()=>lbl(""), lbl(""), lbl(""))(ps))

  //TODO JWW: Is this right? It's not REALLY an App... but just doing this for now to compile
  def prepend(n: Node, e: CellN) = Cell(AppCell(LeafCell(n), IndexedSeq[CellN](e)))

  def pattern(p: Pattern): CellN = p match {
    case ProductP(_,ps)  => prod(Product(builtin,ps.size),ps.map(pattern(_)))
    case LazyP(_,lp)     => prepend(lazyp, pattern(lp))
    case StrictP(_,sp)   => prepend(strictp, pattern(sp))
    case VarP(v)         => LeafCell(namedParam(v))
    case LitIntP(_,v)    => LeafCell(int(v))
    case LitLongP(_,v)   => LeafCell(long(v))
    case LitByteP(_,v)   => LeafCell(byte(v))
    case LitShortP(_,v)  => LeafCell(short(v))
    case LitStringP(_,v) => LeafCell(string(v))
    case LitCharP(_,v)   => LeafCell(char(v))
    case LitFloatP(_,v)  => LeafCell(float(v))
    case LitDoubleP(_,v) => LeafCell(double(v))
    case LitDateP(_,v)   => sys.error("TODO: LitDateP")
    case ConP(_,c,ps)    => ps match {
                              case Nil => LeafCell(conp(c))
                              case _   => prepend(conp(c), prod(Product(builtin,ps.size),ps.map(pattern(_))))
                            }
    case WildcardP(_)    => sys.error("TODO: WildcardP")
    case AsP(_,p1,p2)    => sys.error("TODO: AsP")
  }

  def conp(c: V[Type]) : Node = namedParam(c)

  def namedParam[A](v: V[A]) : Node = v.name match {
    case Some(n) => name(n)
    case _ => lbl(v.id)
  }

  def bindingTerm(t: Term) : CellN = terml(t)

  def terml(t: Term) : CellN = t match {
    case App(_,_)   => aplh(t, List[Term]())
    case Lam(_,n,b) => aplh(t, List[Term]())
    case Let(_,i,e,b) => {
      val binds = (i++e).map(binding(_)).flatMap({ case alts => {
        alts.map({ case x => declareCell(x._1, x._2)(x._3)(x._4) })
      }})

      LetCell(lbl("let","let"), binds.toIndexedSeq, lbl("in","letIn"), bindingTerm(b))
    }
    case tr         => LeafCell(sterm(tr))
  }

  def sterm(t: Term) : Node = t match {
    case Hole(_)            => hole
    case Var(v)             => variable(v)
    case Sig(_,e,t)         => lbl("TODO:SIG")
    case Rigid(e)           => lbl("TODO:RIGID")
    case LitInt(_,i)        => int(i)
    case LitByte(_,f)       => byte(f)
    case LitShort(_,f)      => short(f)
    case LitFloat(_,f)      => float(f)
    case LitLong(_,w)       => long(w)
    case LitString(_,s)     => string(s)
    case LitChar(_,c)       => char(c)
    case LitDouble(_,d)     => double(d)
    case LitDate(_,d)       => lbl("TODO:LIT_DATE")
    case EmptyRecord(_)      => lbl("TODO:EMPTY_TUPLE")
    case Case(_,e,alts)     => lbl("TODO:CASE")
    case Remember(i,e)      => lbl("TODO:REMEMBER")
    case Let(_,i,e,b)       => sys.error("Let should be handled at an outer layer to be a cell")
    case App(e1,e2)         => sys.error("App should be handled at an outer layer because it requires arguments")
    case Lam(_,n,b)         => sys.error("Lam should be handled at an outer layer because it requires arguments")
    case Product(_,n)       => sys.error("Product should be handled at an outer layer because it requires arguments")
  }

  def appCell(fn: CellF[CellN], stack: List[Term]) = appCellN(Cell(fn), stack)

  def appCellN(fn: CellN, stack: List[Term]): CellN = stack match {
    case Nil => fn
    case st => AppCell(fn, st.map(terml(_)).toIndexedSeq)
  }

  def binaryCell(fx: Fixity, op: CellF[CellN], left: CellN, right: CellN): CellN =
    (left,right) match {
      case (lt@Cell(_,OperatorChain(fxL,deL)), _) => appendOp(lt)(fx, op, right)
      case (_, rt@Cell(_,OperatorChain(fxR,deR))) => prependOp(rt)(fx, left, op)
      case _ => Cell(OperatorChain(fx, Delimited(left, op, right)))
    }

  def aplhN(v: Var, stack: List[Term]) : CellN = v match { case Var(vt) =>
    (vt.name.get,stack) match {
      case (Global("List","cons_Bracket",Idfix), s1::s2::st)           => appCellN(list(v, s1 :: extractList(s2, "List", "Relation.Row")), st)
      case (Global("Layout.Legend","cons_Bracket",Idfix), s1::s2::st)  => appCellN(list(v, s1 :: extractList(s2, "Layout.Legend", "Layout.Legend")), st)
      case (Global("Relation.Row","snoc_Brace",Idfix), s1::s2::st)     => appCellN(rowWitness(v, extractRowWitness(s1) :+ s2), st)
      case (Global("Relation.Row","single_Brace",Idfix), s::st)        => appCellN(rowWitness(v, extractRowWitness(s)), st)
      case (Global("Field","cons",Idfix), s1::s2::s3::st)              => appCellN(unorderedList(v, (s1,s2) :: extractUnorderedList(s3)), st)

      case (nm@Local(n, Prefix(p)),  s::st)                            => appCell(UnaryCell(Prefix(p),    LeafCell(name(nm)), terml(s)), st)
      case (nm@Local(n, Postfix(p)), s::st)                            => appCell(UnaryCell(Postfix(p),   LeafCell(name(nm)), terml(s)), st)
      case (nm@Local(n, Infix(p,a)), s::t::st)                         => appCellN(binaryCell(Infix(p, a), LeafCell(name(nm)), terml(s), terml(t)), st)
      case (nm@Global(m, n, Prefix(p)),  s::st)                        => appCell(UnaryCell(Prefix(p),    LeafCell(name(nm)), terml(s)), st)
      case (nm@Global(m, n, Postfix(p)), s::st)                        => appCell(UnaryCell(Postfix(p),   LeafCell(name(nm)), terml(s)), st)
      case (nm@Global(m, n, Infix(p,a)), s::t::st)                     => appCellN(binaryCell(Infix(p, a), LeafCell(name(nm)), terml(s), terml(t)), st)
      case (nm,_)                                                      => appCell(LeafCell(name(nm)), stack)
    }}

  def name[A,B](n: Name): Node = n match {
    case Local(n,_)          => lbl(n)
    case Global(m,n,_)       => lbl(n)   // TODO JWW: ???  + "_" + m
  }

  def aplh(t: Term, stack: List[Term]) : CellN = t match {
    case p@Product(_,n) if stack.length >= n => {
      val (l,r) = stack.splitAt(n)
      appCellN(prod(p, l.map(terml(_))), r)
    }
    case App(e1,e2)                => aplh(e1, e2 :: stack)
    //TODO JWW: cursors for lambdas?
    case Lam(_,n,b)                => appCellN(binaryCell(Infix(0, AssocR), LeafCell(lambda), pattern(n), terml(b)), stack)
    case v@Var(tv) if !tv.name.isEmpty => aplhN(v, stack)
    case _                         => appCellN(terml(t), stack)
  }

  def extractList(t: Term, mc: String, me: String) : List[Term] = t match {
    case Var(v) => v.name match {
      case Some(Global(me,"empty_Bracket",Idfix)) => List[Term]()
      case _ => List(t)
    }
    case App(e1,e2) => e1 match {
      case Var(v) if nameMatches(v, Global(mc,"cons_Bracket",Idfix)) => List(e2)
      case _ => extractList(e1, mc, me) ++ extractList(e2, mc, me)
    }
    case _ => List(t)
  }

  def extractRowWitness(t: Term) : List[Term] = t match {
    case App(e1,e2) => e1 match {
        case Var(v) if nameMatches(v, Global("Relation.Row","snoc_Brace",Idfix)) => extractRowWitness(e2)
        case Var(v) if nameMatches(v, Global("Relation.Row","single_Brace",Idfix)) => List(e2)
        case _ => extractRowWitness(e1) :+ e2
      }
    case _ => List(t)
  }

  def extractUnorderedList(t: Term) : List[(Term,Term)] = t match {
    case EmptyRecord(_) => List[(Term,Term)]()
    case App(App(Var(v),e1),e2) if nameMatches(v, Global("Field","cons",Idfix)) => List((e1,e2))
    case App(e1,e2) => extractUnorderedList(e1) ++ extractUnorderedList(e2)
    case _ => sys.error("Unexpected term in unordered list: " + t)
  }

  def nameMatches(tv: TermVar, n: Name) : Boolean = tv.name match {
    case Some(tn) => tn == n
    case _ => false
  }

  def list(listVar: Var, items: List[Term]): CellN =
  {
    //TODO JWW: grouping terms with parens too
    //TODO JWW: link the open and closet brackets, allow for different renderings, etc.
    commaDelimited(listVar, openBracket, closeBracket)(items.map(terml(_)))
  }

  def rowWitness(rowWitVar: Var, items: List[Term]): CellN = {
    //TODO JWW: grouping terms with parens too
    //TODO JWW: link the open and closet brackets, allow for different renderings, etc.
    commaDelimited(rowWitVar, openBrace, closeBrace)(items.map(terml(_)))
  }

  def unorderedList(listVar: Var, items: List[(Term,Term)]): CellN = {
    //TODO JWW: grouping terms with parens too
    //TODO JWW: link the open and closet brackets, allow for different renderings, etc.
    commaDelimited(listVar, openBrace, closeBrace)(items.map {
      case (a,b) => binaryCell(Infix(-1, AssocN), LeafCell(equals), terml(a), terml(b))
    })
  }

  //calls "d" to generate Nodes to insert between elements in "as" (e.g. comma delimited list)
  //"t" is the type of the delimited... e.g. Product, or a Var with the proper cons, etc.
  def delimited[T](t: T, d: ()=>Node, start: Node, stop: Node)(as: List[CellN]): CellN = {
    val args = as.toIndexedSeq
    val delims = args.tail.map(_ => d())
    Cell(DelimitedCell(t, args, start, stop, delims, d))
  }

  def commaDelimited(t: Term, start: Node, stop: Node) = delimited(t, ()=>comma, start, stop) _

  def prod(p: Product, args: List[CellN]) : CellN = commaDelimited(p, openParen, closeParen)(args)

  def genParens : (Node,Node) = {
    val op = openParen
    val cp = closeParen

    (openParen, closeParen)
  }

  def strictp      = lbl("!", "paren")
  def lazyp        = lbl("~", "paren")
  def openParen    = lbl("(", "paren")
  def closeParen   = lbl(")", "paren")
  def comma        = lbl(",", "comma")
  def openBracket  = lbl("[", "bracket")
  def closeBracket = lbl("]", "bracket")
  def openBrace    = lbl("{", "brace")
  def closeBrace   = lbl("}", "brace")
  def lambda       = lbl("->","lambda")
  def equals       = lbl("=", "equals")

  ///////////////////////////////////////////////////////////////////////////////

  def defaultStyle = "Ermine"

  def fontDef = (".\\res\\conf\\ermine\\font\\Anonymous.ttf", 12)

  val font = fontDef match {
    case (f,s) => Font.loadFont(new FileInputStream(f), s)
  }

  def lbl[V](value: V, styleClass: String = null) : Label =
  {
    val lbl = new Label(value.toString)
    lbl.getStyleClass().addAll(defaultStyle, styleClass)
    lbl.setFont(font)
    lbl
  }

  def compose(parent: Pane)(children: Node*) : Pane = {
    parent.getChildren().addAll(children :_*)
    parent
  }

  def literal[V](v: V, s: String = "") : Node = lbl(v.toString() + s, "literal")

  def buildBindingContainer = {
    val c = buildVBox(18)
    c.getStyleClass().add("bindingContainer")
    c
  }

  ///////////////////////////////////////////////////////////////////////////////

  def hole : Node = lbl("?", "hole")

  def topLevel: Node = {
    val sp = new ScrollPane();
    sp.setFitToWidth(true)
    sp.setContent(bindingContainer)
    sp.setFocusTraversable(true)

    val sb = new HBox()
    sb.getStyleClass().add("statusBar")
    statusBar = Some(sb)

    val bp = new BorderPane();
    bp.setCenter(sp)
    bp.setBottom(sb)
    bp
  }

  def setStatus(s: Option[String]) = statusBar foreach { sb => s match {
    case None => sb.getChildren().clear()
    case Some(st) => sb.getChildren().setAll(lbl(st,"statusText"))
  }}

  def highlightStyleClass = "hoverHighlight"

  def runLater(f: ()=>Any) = Platform.runLater(new java.lang.Runnable() { def run() = f() })

  def replaceInPane(a: Node, b: Node, clos: ()=>Any = ()=>()) = runLater(()=>{
    val p = a.getParent().asInstanceOf[Pane]
    if (p != null) {
      val c = p.getChildren()
      c.set(c.indexOf(a), b)

      clos()
    }
  })

  def declareCell(bindVar: TermVar, altInd: Int)(args: Option[CellN])(body: CellN): CellN = {
    val n = bindVar.name.map(name(_)).getOrElse(lbl(bindVar))
    n.getStyleClass().add("termVar")

    Cell(BindingCell(bindVar, altInd, n, args, equals, body))
  }

  def declaration(cell: CellN): Node =
  {
    val cp = CellPane(cell)
    compose(cp)(cp.getAllNodes :_*)

    compose(new StackPane())(cp)
  }

  def buildVBox(spacing: Int) : VBox = {
    val vb = new VBox(spacing)
    vb.setFillWidth(true)
    vb
  }

  def variable(v: TermVar): Node =
  {
    val text = v.name match {
      case Some(n) => n.string
      case None => v.toString
    }
    lbl(text, "variable")
  }

  def byte(a: Byte): Node = literal(a, "b")
  def short(a: Short): Node = literal(a, "s")
  def int(a: Int): Node = literal(a)
  def long(a: Long): Node = literal(a, "L")
  def float(a: Float): Node = literal(a, "f")
  def double(a: Double): Node = literal(a)
  def date(a: java.util.Date): Node = literal(a)
  def string(a: String): Node = literal("\"" + a + "\"")
  def char(a: Char) : Node = literal("'" + a + "'")

  ///////////////////////////////////////////////////////////////////
  ///////////////////////////////////////////////////////////////////

  //TODO: JavaFX has no ability to get Font metrics (LAME!) -- http://javafx-jira.kenai.com/browse/RT-8060
  //When it does, we can link the horizSpacer to the width of a space in the font used, at the given point size.
  val horizSpacer = 8
  val vertSpacer = 2
  val indentationWidth = 20

  type LayoutF = (Node, Pt) => Rect

  def width(n: Node) = scala.math.ceil(n.prefWidth(-1))
  def height(n: Node) = scala.math.ceil(n.prefHeight(-1))

  sealed trait CellF[+R] {
    def map[S](f: R=>S): CellF[S] = this match {
      case DelimitedCell(t,as,start,stop,d,df) => DelimitedCell(t,as map f, start, stop, d, df)
      case AppCell(h,as) => AppCell(f(h), as map f)
      case OperatorChain(fx,ch) => OperatorChain(fx, Delimited(f(ch.head), ch.tail.map { case (b,a) => (f(b),f(a)) }))
      case UnaryCell(fx,op,e) => UnaryCell(fx, f(op), f(e))
      case BindingCell(v,ai,n,p,e,b) => BindingCell(v, ai, n, p map f, e, f(b))
      case LetCell(let,bs,in,b) => LetCell(let, bs.map(f), in, f(b))
      case LeafCell(n) => LeafCell(n)
      case EmptyCell => EmptyCell
    }
  }

  type Cell[A] = Cofree[CellF,A]

  case class Delimited[+A,+B](head: A, tail: IndexedSeq[(B,A)]) {
    def elements = head +: tail.map(_._2)
    def delimiters = tail.map(_._1)

    def ++[C >: A, D >: B](d: D, t2: Delimited[C,D]): Delimited[C,D] = Delimited(head, tail ++ ((d,t2.head) +: t2.tail))
    def prepend[C >: A, D >: B](h: C, d: D): Delimited[C,D] = Delimited(h, (d,head) +: tail)
    def append[C >: A, D >: B](d: D, e: C): Delimited[C,D] = Delimited(head, tail :+ (d, e))

    def flatMap[C,D](f: A=>Delimited[C,D], g: B=>Delimited[D,C]): Delimited[C,D] = {
      val newTail = tail.map({ case (b,a) => (g(b),f(a)) }).foldLeft( IndexedSeq[(D,C)]() )(
        (s,a) => a match {
          case (left,right) => {
            val x = left.tail.foldLeft( (s, left.head) )( (acc,e) => (acc._1 :+ (acc._2, e._1), e._2) )
            (x._1 :+ (x._2, right.head)) ++ right.tail
          }})

      val newHead = f(head)
      Delimited(newHead.head, newHead.tail ++ newTail)
    }

    def mapElement[C >: A](i: Int, f: A=>C): Delimited[C,B] =
      if (i == 0) Delimited(f(head), tail)
      else Delimited(head, tail.updated(i - 1, tail(i - 1) match { case (b,a) => (b, f(a)) }))

    def mapDelimiter[D >: B](i: Int, f: B=>D): Delimited[A,D] =
      Delimited(head, tail.updated(i, tail(i) match { case (b,a) => (f(b), a) }))
  }

  object Delimited {
    def apply[A,B](left: A, op: B, right: A): Delimited[A,B] = Delimited(left, IndexedSeq((op, right)))
  }

  def prependOp(cell: CellN)(fx: Fixity, exp: CellN, op: CellN): CellN = Cell(cell.out match {
    case c@OperatorChain(f, d) if (f==fx) => OperatorChain(fx, d.prepend(exp, op))
    case c => OperatorChain(fx, Delimited(exp, op, c))
  })

  def appendOp(cell: CellN)(fx: Fixity, op: CellN, exp: CellN): CellN = Cell(cell.out match {
    case c@OperatorChain(f, d) if (f == fx) => OperatorChain(fx, d.append(op, exp))
    case c => OperatorChain(fx, Delimited(c, op, exp))
  })

  object CellF {
    case class DelimitedCell[R,T](t: T, args: IndexedSeq[R], start: Node, stop: Node, delims: IndexedSeq[Node], delimGen: ()=>Node) extends CellF[R]
    case class AppCell[R](head: R, args: IndexedSeq[R]) extends CellF[R]
    case class OperatorChain[+R](fx: Fixity, chain: Delimited[R,R]) extends CellF[R]
    case class UnaryCell[R](fx: Fixity, op: R, exp: R) extends CellF[R]
    case class LeafCell[R](n: Node) extends CellF[R]
    case class BindingCell[+R](bindVar: TermVar, altIndex: Int, nameNode: Node, pattern: Option[R], eq: Node, body: R) extends CellF[R]
    case class LetCell[R](let: Node, bindings: IndexedSeq[R], in: Node, body: R) extends CellF[R]
    case object EmptyCell extends CellF[Nothing]

    private object CellFunctorO extends Functor[CellF] {
      def map[A, B](r: CellF[A])(f: A => B): CellF[B] =
        r map f
    }
    implicit val CellFunctor: Functor[CellF] =
      CellFunctorO
  }

  type CellN = Cell[Unit]

  object Cell {
    def apply(c: CellF[CellN]): CellN = Cofree[CellF,Unit](Unit, c)
    def apply[A](a: A, c: CellF[Cell[A]]): Cell[A] = Cofree[CellF,A](a, c)
    def unapply[A](c: Cell[A]) = Cofree.unapply(c)
  }

  sealed trait CellPathElement
  object CellPathElement {
    case object BindingName extends CellPathElement
    case object BindingPattern extends CellPathElement
    case class BindingAlt(v: TermVar, altInd: Int) extends CellPathElement
    case class LetBind(v: TermVar) extends CellPathElement
    case object LetBod extends CellPathElement
    case object UnaryOp extends CellPathElement
    case object UnaryArg extends CellPathElement
    case class ChainElem(fx: Fixity, elemIndex: Int, numElements: Int) extends CellPathElement // 0 <= elemIndex < numElements
    case class ChainOp(fx: Fixity, opIndex: Int, numElements: Int) extends CellPathElement     // 0 <= opIndex < numElements - 1
    case object ApFn extends CellPathElement
    case class ApArg(index: Int, of: Int) extends CellPathElement
    case class DelimitedArg[T](t: T, index: Int, of: Int) extends CellPathElement
  }

  type CellPath = IndexedSeq[CellPathElement]
  object CellPath {
    def apply() = IndexedSeq[CellPathElement]()
  }


  ///////////////////

  type Up[A,B] = (A, CellF[B]) => B
  type Down[S,-A,+B] = (S,A,CellF[A]) => (B,CellF[S]) // todo: maybe allow early termination via Option or something

  def applyDown[S,A,B](cell: Cell[A], s: S)(f: Down[S,A,B]): Cell[B] = cell match {
    case Cell(a,c) => {
      def downAll(as: IndexedSeq[Cell[A]], asS: IndexedSeq[S]) =
        (as zip asS).map({ case (a,aS) => applyDown(a,aS)(f) })
      val (b,cs) = f(s, a, c.map(_.extract))

      Cell(b, (c,cs) match {
        case (LeafCell(n),LeafCell(nS)) => LeafCell(n)
        case (UnaryCell(fx,op,exp),UnaryCell(_,opS,expS)) =>
          UnaryCell(fx,
            applyDown(op,opS)(f),
            applyDown(exp,expS)(f))
        case (OperatorChain(fx,ch), OperatorChain(_,chS)) =>
          OperatorChain(fx, Delimited(
            applyDown[S,A,B](ch.head, chS.head)(f),
            (ch.tail zip chS.tail).map {
              case ((b,a),(bS,aS)) => (applyDown[S,A,B](b, bS)(f), applyDown[S,A,B](a, aS)(f))
            }))
        case (AppCell(h,as),AppCell(hS,asS)) =>
          AppCell(applyDown(h,hS)(f), downAll(as, asS))
        case (DelimitedCell(t,as,start,stop,d,df),DelimitedCell(_,asS,_,_,_,_)) =>
          DelimitedCell(t, downAll(as, asS), start, stop, d, df)
        case (BindingCell(v,ai,n,p,e,b),BindingCell(_,_,_,pS,_,bS)) =>
          BindingCell(v, ai, n, for { q <- p; s <- pS } yield(applyDown(q,s)(f)), e, applyDown(b,bS)(f))
        case (LetCell(let,bs,in,b),LetCell(_,bsS,_,bS)) =>
          LetCell(let, downAll(bs, bsS), in, applyDown(b,bS)(f))
        case x@_ => sys.error("Unhandled/mismatched case: " + x)
      })
    }
  }

  def applyUp[A,B](cell: Cell[A])(f: Up[A,B]): Cell[B] = cell match {
    case Cell(a,c) => {
      val cB = c.map(applyUp(_)(f))
      Cell(f(a, cB.map(_.extract)), cB)
    }
  }

  type Prec = Int

  def parenthesize: Down[Prec,Any,Parens] =
    (s: Prec, dontcare: Any, cell: CellF[Any]) => {
      def genIf(hp: Boolean) = if (hp) Some(genParens) else None

      cell match {
        case LeafCell(n) => (None,LeafCell(n))
        case u@UnaryCell(fixity,op,arg) =>
          (genIf(fixity.prec < s), u.map(_ => fixity.prec + 1))
        case OperatorChain(Infix(p,assoc), ch) => {
          val chain = assoc match {
            case AssocL => Delimited(p,   ch.tail.map { case (b,a) => (-1,p+1) })
            case AssocR => Delimited(p+1, ch.tail.dropRight(1).map({ case (b,a) => (-1,p+1) }) :+ (-1,p))
            case AssocN => Delimited(p+1, ch.tail.map { case (b,a) => (-1,p+1) })
          }
          (genIf(p < s), OperatorChain(Infix(p,assoc), chain))
        }
        case AppCell(f, args) =>
          (genIf(s > 10), AppCell(10, args.map(_ => 11)))
        case d@DelimitedCell(t, args, start, stop, delims, df) =>
          (None, d.map(_ => -1))
        case BindingCell(v,ai,n,p,e,b) => (None, cell.map(_ => -1))
        case LetCell(let,bs,in,b) => (None, cell.map(_ => -1))
        case x@_ => sys.error("Unhandled case: " + x)
      }
    }

  type Parens = Option[(Node,Node)]

  //Conditionally adds space, based on whether the node itself takes up space (e.g. width).
  //This is basically a hack to allow some flexibility in case portions are
  //hidden, or don't apply.
  def condSpace(w: Double) = if (w > 0.0D) w + horizSpacer else 0.0D
  def condSpaceW(n: Node) = condSpace(width(n))

  //given a tree of parens, produce the unbroken width of the tree
  def unbroken: Up[Parens,Width] =
    (ps: Parens, cell: CellF[Width]) => {
      val w = cell match {
        case LeafCell(n) => width(n)
        case UnaryCell(fx,opW,expW) => opW + expW
        case OperatorChain(fx,chW) => chW.head + chW.tail.foldLeft(0.0D)( (s,x) => x match { case (b,a) => s + b + a + 2*horizSpacer })
        case AppCell(hW,argsW) => hW + argsW.sum + (horizSpacer * argsW.length)
        case DelimitedCell(t,argsW,start,stop,d,df) => condSpaceW(start) + condSpaceW(stop) + d.map(width(_) + horizSpacer).sum + argsW.sum
        case BindingCell(v,ai,n,p,e,bW) => condSpaceW(n) + p.map(_ + horizSpacer).getOrElse(0.0D) + condSpaceW(e) + bW
        case LetCell(let,bsW,in,bW) =>
          maxA(bsW.max + indentationWidth, width(let), width(in), bW + indentationWidth)
        case EmptyCell => 0.0D
      }

      w + ps.map( {case (p1,p2) => width(p1) + width(p2)} ).getOrElse(0.0D)
    }

  sealed trait WrapStyle
  object WrapStyle {
    case object Unbroken extends WrapStyle  //no break--format entirety on the same line
    case object SoftBreak extends WrapStyle //break and start on the current line
    case object HardBreak extends WrapStyle //break and go to the next line
  }

  def fit: Down[Width,(Parens,Width),WrapStyle] =
    (remWidth: Width, parensUnbrWidth: (Parens,Width), cell: CellF[(Parens,Width)]) => {
      val (pStartW,pStopW) = parensUnbrWidth._1.map({case (p1,p2) => (width(p1),width(p2))}).getOrElse((0.0D,0.0D))
      val style = if (parensUnbrWidth._2 >= remWidth) HardBreak else Unbroken

      val outCell =
        if (style == Unbroken) {
          cell.map(_ => remWidth)
        }
        else {
          cell match {
            case LeafCell(n) => LeafCell(n)
            case AppCell(h,as) => AppCell(remWidth - pStartW,
              as.dropRight(1).map(_ => remWidth - indentationWidth) :+ (remWidth - indentationWidth - pStopW))
            case BindingCell(v,ai,n,p,e,b) => BindingCell(v, ai, n, p.map(_ => remWidth - indentationWidth), e, remWidth - indentationWidth)
            case LetCell(let,bs,in,b) => LetCell(let,
              bs.map(_ => remWidth - indentationWidth), in, remWidth - indentationWidth)
            case UnaryCell(fx,op,exp) => fx match {
              //TODO: is this the correct way to layout a unary operator? e.g., if it's "broken", wrapping and indenting will make it worse, so we don't
              case Prefix(_)  => UnaryCell(fx, remWidth - pStartW,         remWidth - op._2 - pStopW)
              case Postfix(_) => UnaryCell(fx, remWidth - exp._2 - pStopW, remWidth - pStartW)
              case _ => sys.error("Unexpected fixity: " + fx)
            }
            case OperatorChain(fx,ch) => {
              val indent = max(pStartW, maxD(ch.delimiters.map(_._2))) + horizSpacer
              OperatorChain(fx, Delimited(remWidth - indent, ch.tail.map { case (b,a) => (indent, remWidth - indent) } ))
            }
            case DelimitedCell(t,as,start,stop,d,df) => {
              val delimWidth = if (d.isEmpty) 0.0D else width(d.head)
              DelimitedCell(t,as.map(_ => remWidth - max(max(width(stop), width(start)), delimWidth) - horizSpacer), start, stop, d, df)
            }
            case EmptyCell => EmptyCell
          }
        }

      (style, outCell)
    }

  //takes parens, the computed size of the cells (given the previously-computed WrapStyle) and that WrapStyle, and then relaxes the
  //wrapping if possible, bringing the AppCell's first line of first child up on the line if possible
  def relaxedFit: Down[Width,(Parens,Sz,WrapStyle),WrapStyle] =
    (remWidth: Width, parensUnbrWidth: (Parens,Sz,WrapStyle), cell: CellF[(Parens,Sz,WrapStyle)]) =>
      (parensUnbrWidth._3,cell) match {
        //Don't allow AppCells to be SoftBreak if their Fn is not Unbroken, or else it looks weird
        case (HardBreak,ac@AppCell(h,as)) if (h._3 == Unbroken) => {
          val (pStartW,pStopW) = parensUnbrWidth._1.map({case (p1,p2) => (width(p1),width(p2))}).getOrElse((0.0D,0.0D))
          val hW = h._2.w
          val asW = (as.size,as.map(_._2.w)) match {
            case (0,_) => 0.0D
            case (1,aws) => aws.head + pStopW
            case (_,aws) => max(aws.dropRight(1).max, aws.last + pStopW)
          }
          val leftW = pStartW + hW + horizSpacer
          if (leftW + asW <= remWidth)
          {
            val remAsW = remWidth - leftW
            (SoftBreak, AppCell(hW, as.dropRight(1).map(_ => remAsW) :+ (remAsW - pStopW)))
          }
          else
          {
            (HardBreak, AppCell(remWidth - pStartW,
              as.dropRight(1).map(_ => remWidth - indentationWidth) :+ (remWidth - indentationWidth - pStopW)))
          }
        }
        case (HardBreak,bc@BindingCell(v,ai,n,p,e,b)) => {
          val lhsW = width(n) + horizSpacer +
            p.map(_._2.w + horizSpacer).getOrElse(0.0D) +
            width(e) + horizSpacer

          if (lhsW + b._2.w <= remWidth) (SoftBreak, BindingCell(v, ai, n, p.map(_._2.w), e, remWidth - lhsW))
          else (HardBreak, BindingCell(v, ai, n, p.map(lhsW - _._2.w - horizSpacer), e, remWidth - indentationWidth))
        }
        //TODO JWW: We probably need to handle all the other types specifically here... but I will
        //wait and come back to this because I want to tackle operators first, and combine this
        //part of "fit" and "relaxedFit" if possible.
        case (ws,x) => (ws, x map {_ => remWidth})
      }

  case class Pt(x: Double, y: Double) {
    def +(other: Sz) = Pt(x + other.w, y + other.h)
  }
  case class Sz(w: Width, h: Height) {
    def +(other: Sz) = Sz(w + other.w, h + other.h)
  }

  def maxD(d: IndexedSeq[Double]) = if (d.isEmpty) 0.0D else d.max
  def maxA(d: Double*) = if (d.isEmpty) 0.0D else d.max

  //takes (optional parens; unbroken width; wrapstyle) and returns the width and height
  def sizeCell: Up[(Parens,Width,WrapStyle),Sz] =
    (p: (Parens,Width,WrapStyle), cell: CellF[Sz]) => {
      def nodeSz(n: Node): Sz = Sz(width(n), height(n))
      def horiz(s: Sz*): Sz = if (s.isEmpty) Sz(0,0) else Sz(s.map(_.w).sum + (horizSpacer * (s.length - 1)), s.map(_.h).max)
      def vert(s: Sz*): Sz = if (s.isEmpty) Sz(0,0) else Sz(s.map(_.w).max, s.map(_.h).sum + (vertSpacer * (s.length - 1)))
      def indent = Sz(indentationWidth, 0)

      val (pStartSz,pStopSz) = p._1.map({case (s1,s2) => (nodeSz(s1),nodeSz(s2))}).getOrElse( (Sz(0,0),Sz(0,0)) )
      p._3 match {
        case Unbroken => {
          val h = cell.map(_.h) match {
            case LeafCell(n) => height(n)
            case UnaryCell(fx,op,arg) => max(op, arg)
            case OperatorChain(fx,ch) => max(ch.head, ch.tail.foldLeft(0.0D)( (s,x) => x match { case (b,a) => maxA(s,b,a) } ))
            case AppCell(h,as) => max(h, maxD(as))
            case BindingCell(v,ai,n,p,e,b) =>
              maxA(height(n), p.getOrElse(0.0D), height(e), b)
            case LetCell(let,bs,in,b) =>
              height(let) + vertSpacer + bs.sum + vertSpacer*bs.size + height(in) + vertSpacer + b
            case DelimitedCell(t,as,start,stop,d,df) => maxA(height(start), height(stop), maxD(as), maxD(d.map(height(_))))
            case EmptyCell => 0
          }
          Sz(p._2, maxA(h, pStartSz.h, pStopSz.h))
        }
        case SoftBreak => cell match {
          case AppCell(h,as) => {
            val phSZ = horiz(pStartSz, h)
            val softIndent = Sz(phSZ.w + horizSpacer, 0)
            as.size match {
              case 0 => horiz(phSZ, pStopSz)
              case 1 => horiz(phSZ, as.head, pStopSz)
              case _ => vert(horiz(phSZ, as.head),
                          softIndent + vert(
                            vert(as.tail.dropRight(1) :_*),
                            if (as.tail.isEmpty) pStopSz else horiz(as.tail.last, pStopSz) ))
            }
          }
          //TODO JWW: If p==None, should we not prevent the horizSpacer from taking effect here??
          case BindingCell(v,ai,n,p,e,b) => horiz(nodeSz(n), p.getOrElse(Sz(0,0)), nodeSz(e), b)
          case _ => sys.error("Unexpected SoftBreak for " + cell)
        }
        case HardBreak => cell match {
          case LeafCell(n) => nodeSz(n)
          case UnaryCell(fx,op,arg) => horiz(pStartSz, op, arg, pStopSz)
          case OperatorChain(fx,ch) => {
            val opIndent = Sz(max(pStartSz.w, maxD(ch.delimiters.map(_.w))) + horizSpacer, 0)
            val items = ch.elements
            vert(horiz(pStartSz, items.head), opIndent + vert(items.tail :_*), pStopSz)
          }
          case AppCell(h,as) =>
            vert(horiz(pStartSz, h),
                 indent + vert(
                   vert(as.dropRight(1) :_*),
                   if (as.isEmpty) pStopSz else horiz(as.last, pStopSz) ))
          case LetCell(let,bs,in,b) =>
            vert(nodeSz(let), indent + vert(bs :_*), nodeSz(in), indent + b)
          case BindingCell(v,ai,n,p,e,b) =>
            vert(horiz(nodeSz(n), p.getOrElse(Sz(0,0)), nodeSz(e)),
                 indent + b)
          case DelimitedCell(t,as,start,stop,d,df) => {
            val delimSize = if (d.isEmpty) Sz(0,0) else nodeSz(d.head)
            val hSpace = Sz(horizSpacer, 0)
            val aligner = Sz(maxA(width(start), width(stop), delimSize.w), 0) + hSpace
            if (as.isEmpty)
              horiz(nodeSz(start), hSpace + nodeSz(stop))
            else
              vert(horiz(nodeSz(start), hSpace + as.head), aligner + vert(as.tail :_*), nodeSz(stop))
          }
          case EmptyCell => Sz(0,0)
        }
      }
    }

  //given the start (x,y) coordinates and cells annotated with (parenthesization,width,broken),
  //determine the bounds for the given cell--but do not apply the bounds to the nodes yet!
  def layoutCell: Down[Pt,(Parens,WrapStyle,Sz),Rect] =
    (loc: Pt, pbs: (Parens,WrapStyle,Sz), cell: CellF[(Parens,WrapStyle,Sz)]) => {
      def acrossAcc(delimWidth: Width)(p: Pt, a: (Parens,WrapStyle,Sz)) = Pt(p.x + a._3.w + delimWidth + horizSpacer, p.y)
      def downAcc(p: Pt, a: (Parens,WrapStyle,Sz)) = Pt(p.x, p.y + a._3.h + vertSpacer)
      def across(startLoc: Pt, delimWidth: Width)(as: IndexedSeq[(Parens,WrapStyle,Sz)]) =
        as.scanLeft(startLoc)(acrossAcc(delimWidth) _).dropRight(1)
      def down(startLoc: Pt)(as: IndexedSeq[(Parens,WrapStyle,Sz)]) =
        as.scanLeft(startLoc)(downAcc _).dropRight(1)

      val pStart = Sz(pbs._1.map({case (s,_) => width(s)}).getOrElse(0.0D), 0)
      val (style,size) = (pbs._2,pbs._3)

      val newCell = cell match {
        case LeafCell(n) => LeafCell(n)
        case UnaryCell(fx,op,arg) => fx match {
            case Prefix(_) => UnaryCell(fx, loc + pStart, Pt(loc.x + op._3.w, loc.y) + pStart)
            case Postfix(_) => UnaryCell(fx, Pt(loc.x + arg._3.w, loc.y) + pStart, loc + pStart)
            case _ => sys.error("Unexpected fixity: " + fx)
          }
        case OperatorChain(fx,ch) => OperatorChain(fx, style match {
          case Unbroken =>
            Delimited(loc + pStart, ch.tail.foldLeft( (ch.head, loc + pStart, IndexedSeq[(Pt,Pt)]()) ) (
              (s,x) => x match { case (b,a) => {
                val bP = acrossAcc(0.0D)(s._2, s._1)
                val aP = acrossAcc(0.0D)(bP, b)
                (a, aP, s._3 :+ (bP, aP))
              }})._3)
          case HardBreak => {
            val opIndent = Sz(max(pStart.w, maxD(ch.delimiters.map(_._3.w))) + horizSpacer, 0)
            Delimited(loc + pStart, ch.tail.foldLeft( (ch.head, loc + pStart, IndexedSeq[(Pt,Pt)]()) ) (
              (s,x) => x match { case (b,a) => {
                val bP = Pt(loc.x, downAcc(s._2, s._1).y)
                val aP = Pt(loc.x + opIndent.w, bP.y)
                (a, aP, s._3 :+ (bP, aP))
              }})._3)
          }
          case SoftBreak =>
            sys error "Impossible, or simply overlooked"
        })
        case AppCell(h,as) => AppCell(loc + pStart,
            style match {
              case Unbroken  => across(Pt(loc.x + h._3.w + horizSpacer, loc.y) + pStart, 0)(as)
              case SoftBreak => down(Pt(loc.x + h._3.w + horizSpacer, loc.y) + pStart)(as)
              case HardBreak => down(Pt(loc.x + indentationWidth, loc.y + h._3.h + vertSpacer))(as)
            })
        case BindingCell(v,ai,n,p,e,b) => {
          val w1 = width(n) + horizSpacer
          val px = p.map(_ => Pt(loc.x + w1, loc.y))
          style match {
            case Unbroken | SoftBreak => {
              val w2 = p.map(_._3.w + horizSpacer).getOrElse(0.0D)
              val w3 = width(e) + horizSpacer
              BindingCell(v, ai, n, px, e, Pt(loc.x + w1+w2+w3, loc.y))
            }
            case HardBreak => {
              val lhsH = max(height(n), max(height(e), p.map(_._3.h).getOrElse(0.0D)))
              BindingCell(v, ai, n, px, e, Pt(loc.x + indentationWidth, loc.y + lhsH + vertSpacer))
            }
          }
        }
        case LetCell(let,bs,in,b) => {
          val bsP = down(Pt(loc.x + indentationWidth, loc.y + height(let) + vertSpacer))(bs)
          LetCell(let, bsP, in, bsP.last + Sz(0, bs.last._3.h + vertSpacer + height(in) + vertSpacer))
        }
        case DelimitedCell(t,as,start,stop,d,df) => {
          val delimWidth = if (d.isEmpty) 0 else width(d.head)
          val asP =
            if (style == Unbroken) {
              across(Pt(loc.x + condSpaceW(start), loc.y), delimWidth)(as)
            } else {
              val aX = loc.x + maxA(condSpaceW(start), condSpaceW(stop), condSpace(delimWidth))
              down(Pt(aX, loc.y))(as)
            }

          DelimitedCell(t, asP, start, stop, d,df)
        }
        case EmptyCell => EmptyCell
      }

      (Rect(loc.x, loc.y, size.w, size.h), newCell)
    }

  //SIDE EFFECT: resizes/relocates Nodes according to their computed bounding rectangles
  def applyLayout(layout: LayoutF): Down[Unit,(Parens,WrapStyle,Rect),Unit] =
    (_, pbr: (Parens,WrapStyle,Rect), cell: CellF[(Parens,WrapStyle,Rect)]) => {
      val parens = pbr._1
      val r = pbr._3

      cell match {
        case LeafCell(n) => layout(n, r.loc)
        case DelimitedCell(t, as, start, stop, delims, df) => {
          layout(start, r.loc)

          //if this cell is broken:
          //  * show the "stop" in the lower left corner, else at the rightmost side
          //  * show the delimiters on the left side of the line, else between elements
          if (pbr._2 != Unbroken) {
            layout(stop, Pt(r.x, r.y + r.h - height(stop)))

            as.tail.zip(delims).foreach { case (a,d) => {
              layout(d, Pt(r.x, a._3.y))
            }}
          }
          else {
            layout(stop, Pt(r.x + r.w - width(stop), r.y))

            as.zip(delims).foreach { case (a,d) => {
              val ar = a._3
              layout(d, Pt(ar.x + ar.w, ar.y + max(0, (ar.h - height(d))/2.0D) ))
            }}
          }
        }
        case LetCell(let,bs,in,_) => {
          layout(let, r.loc)
          layout(in, Pt(r.loc.x, bs.last._3.below.y + vertSpacer))
        }
        case BindingCell(v,ai,n,p,e,_) => {
          val r1 = layout(n, r.loc)
          val r2 = p.map(_._3).getOrElse(r1)
          layout(e, Pt(r2.x + r2.w + horizSpacer, r.y))
        }
        case AppCell(h,as) => parens foreach {
          case (p1,p2) => {
            layout(p1, r.loc)
            val ar = if (as.isEmpty) h._3 else as.last._3
            layout(p2, Pt(ar.x + ar.w, ar.y + max(0, (ar.h - height(p2))/2.0D) ))
          }
        }
        case UnaryCell(fx,op,exp) => parens foreach {
          case (p1,p2) => {
            layout(p1, r.loc)
            val ar = fx match {
              case Prefix(_) => exp._3
              case Postfix(_) => op._3
              case _ => sys.error("Unexpected fixity: " + fx)
            }
            layout(p2, Pt(ar.x + ar.w, ar.y + max(0, (ar.h - height(p2))/2.0D) ))
          }
        }
        case OperatorChain(fx,ch) => parens foreach {
          case (p1,p2) => {
            layout(p1, r.loc)
            if (pbr._2 == Unbroken) layout(p2, Pt(r.x + r.w - width(p2), r.y))
            else  layout(p2, Pt(r.x, r.y + r.h - height(p2)))
          }
        }
        case _ => ()
      }

      (Unit,cell.map(_ => Unit))
    }

  ///////////////////

  case class Rect(val x: Double, val y: Double, val w: Double, val h: Double) {
    def loc: Pt = Pt(x, y)

    def right: Pt = Pt(x + w, y)
    def below: Pt = Pt(x, y + h)
    def belowIndent: Pt = Pt(x + indentationWidth, y + h)
    def contains(p: Pt) = p.x >= x && p.x <= x+w && p.y >= y && p.y <= y+h
  }

  object Rect {
    def apply(pt: Pt, sz: Sz): Rect = Rect(pt.x, pt.y, sz.w, sz.h)
  }

  type Width = Double
  type Height = Double
  type Paren = Option[(Node,Node)]

  def allNodesN(cell: CellN): IndexedSeq[Node] = allNodes(applyDown(cell, -1)(parenthesize))

  def allNodes(cell: Cell[Parens]): IndexedSeq[Node] = cell match {
    case Cell(ps, c) => {
      val cellNodes = c match {
        case DelimitedCell(t,as,start,stop,delims,df) => {
          val middle: IndexedSeq[Node] =
            if (as.isEmpty) IndexedSeq[Node]()
            else as.zip(delims).flatMap({case (a,d) => allNodes(a) :+ d }) ++ allNodes(as.last)
          start +: middle :+ stop
        }
        case AppCell(h,as) => as.foldLeft(allNodes(h))( (b,a) => b ++ allNodes(a) )
        case OperatorChain(_,ch) =>
          ch.tail.foldLeft(allNodes(ch.head))( (s,x) => x match { case (b,a) => s ++ allNodes(b) ++ allNodes(a) } )
        case UnaryCell(fx,o,e) => fx match {
            case Prefix(_) => allNodes(o) ++ allNodes(e)
            case _ => allNodes(e) ++ allNodes(o)
          }
        case BindingCell(v,ai,n,p,e,b) => IndexedSeq(n) ++ p.map(allNodes(_)).getOrElse(IndexedSeq()) ++ IndexedSeq(e) ++ allNodes(b)
        case LetCell(let,bs,in,b) => bs.foldLeft(IndexedSeq(let))( (b,a) => b ++ allNodes(a) ) ++ (in +: allNodes(b))
        case LeafCell(n) => IndexedSeq(n)
        case EmptyCell => IndexedSeq()
      }

      ps match {
        case None => cellNodes
        case Some((p1,p2)) => p1 +: cellNodes :+ p2
      }
    }
  }

  def merge[A,B,C](f: (A,B) => C)(c1: Cell[A], c2: Cell[B]): Cell[C] = {
    def mg(x: (Cell[A],Cell[B])) = merge(f)(x._1, x._2)

    (c1,c2) match {
      case (Cell(a,LeafCell(n)),
            Cell(b,LeafCell(_))) =>
            Cell(f(a,b), LeafCell(n))
      case (Cell(a,UnaryCell(fx,opa,arga)),
            Cell(b,UnaryCell(_,opb,argb))) =>
            Cell(f(a,b), UnaryCell(fx,mg(opa,opb),mg(arga,argb)))
      case (Cell(a,OperatorChain(fx,cha)),
            Cell(b,OperatorChain(_,chb))) =>
            Cell(f(a,b), OperatorChain(fx, Delimited(mg(cha.head, chb.head), cha.tail.zip(chb.tail).map { case ((b1,a1),(b2,a2)) => (mg(b1,b2), mg(a1,a2)) } )))
      case (Cell(a,AppCell(ha,asa)),
            Cell(b,AppCell(hb,asb))) =>
            Cell(f(a,b), AppCell(mg(ha,hb),asa.zip(asb).map(mg _)))
      case (Cell(a,DelimitedCell(t,asa,sta,sto,d,df)),
            Cell(b,DelimitedCell(_,asb,_,_,_,_))) =>
            Cell(f(a,b), DelimitedCell(t,asa.zip(asb).map(mg _),sta,sto,d,df))
      case (Cell(a,BindingCell(v,ai,n,pa,e,ba)),
            Cell(b,BindingCell(_,_,_,pb,_,bb))) =>
            Cell(f(a,b), BindingCell(v,ai,n,for { q <- pa; s <- pb } yield mg(q,s),e,mg(ba,bb)))
      case (Cell(a,LetCell(let,bsa,in,ba)),
            Cell(b,LetCell(_,bsb,_,bb))) =>
            Cell(f(a,b), LetCell(let, bsa.zip(bsb).map(mg _), in, mg(ba,bb)))
      case (Cell(a,EmptyCell),
            Cell(b,EmptyCell)) =>
            Cell(f(a,b),EmptyCell)
      case _ => sys.error("Mismatched cell trees in merge")
    }
  }

  def validate[A](fx: Fixity, ch: Delimited[Cell[A],Cell[A]]): Delimited[Cell[A],Cell[A]] = {
    def check(c: Cell[A]): Delimited[Cell[A],Cell[A]] = c match {
      case Cell(a,OperatorChain(fxThat,chThat)) if (fxThat == fx) => chThat
      case x => Delimited(x, IndexedSeq[(Cell[A],Cell[A])]())
    }

    ch.flatMap(check,check)
  }

  def modify[A](path: CellPath, f: (Cell[A] => Cell[A]))(cell: Cell[A]): Cell[A] = {
    if (path.isEmpty) f(cell)
    else {
      val mod = modify(path.tail, f) _
      def error(cpe: CellPathElement) = sys.error("Unexpected cell path element: " + cpe)

      Cell(cell.extract, (path.head,cell.out) match {
        case (BindingAlt(v1,a1), BindingCell(v2,a2,n,Some(p),e,b)) if (v1==v2 && a1==a2 && path.size >= 2 && path(1) == BindingPattern) =>
              BindingCell(v2,a2,n,Some(modify(path.drop(2), f)(p)),e,b)
        case (BindingAlt(v1,a1), BindingCell(v2,a2,n,p,e,b)) if (v1==v2 && a1==a2) =>
              BindingCell(v2,a2,n,p,e,mod(b))
        case (_, LeafCell(_) | EmptyCell) =>
          sys.error("Unable to perform modification due to early termination at a leaf with remaining path: " + path)
        case (DelimitedArg(_,i,_),
              DelimitedCell(t,as,start,stop,d,df)) =>
              DelimitedCell(t, as updated (i, mod(as(i))), start, stop, d, df)
        case (pe, AppCell(h,as)) => pe match {
          case ApFn => AppCell(mod(h), as)
          case ApArg(i,_) => AppCell(h, as updated (i, mod(as(i))))
          case _ => error(pe)
        }
        case (pe, LetCell(let,bs,in,b)) => pe match {
          case LetBind(v) => sys.error("TODO JWW: find the right binding, and modify it")
          case LetBod => LetCell(let, bs, in, mod(b))
          case _ => error(pe)
        }
        case (pe, UnaryCell(fx,op,exp)) => pe match {
          case UnaryOp => UnaryCell(fx, mod(op), exp)
          case UnaryArg => UnaryCell(fx, op, mod(exp))
          case _ => error(pe)
        }
        case (ChainOp(_,i,n), OperatorChain(fx,ch)) => OperatorChain(fx, validate(fx, ch.mapDelimiter(i, mod)))
        case (ChainElem(_,i,n), OperatorChain(fx,ch)) => OperatorChain(fx, validate(fx, ch.mapElement(i, mod)))
        case (_,x) => sys.error("Unable to modify: [" + x + "] at cell path: " + path)
      })
    }
  }

  //////////////////////////////////////////////////////////////////////////////////

  case class CellPane(var root: CellN) extends Pane
  {
    private var parenthesizedCells: Cell[Parens] = applyDown(root, -1)(parenthesize)
    private var lastLay: Option[Cell[(Parens,WrapStyle,Rect)]] = None

    //update the root and returns the new root, for chaining
    def updateRoot(newRoot: CellN): CellN = {
      val newParens = applyDown(newRoot, -1)(parenthesize)
      val oldNodes = allNodes(parenthesizedCells)
      val newNodes = allNodes(newParens)

      root = newRoot
      parenthesizedCells = newParens
      lastLay = None

      hideCaret

      getChildren().setAll(newNodes :_*)
      newRoot
    }

    def getAllNodes: IndexedSeq[Node] = allNodes(parenthesizedCells)

    def pwidth(n: Node) : Double = n.prefWidth(-1)
    def pheight(n: Node): Double = n.prefHeight(-1)

    def layoutChild(n: Node, pt: Pt) : Rect = {
      layoutInArea(n, pt.x, pt.y, pwidth(n), pheight(n), 0, HPos.LEFT, VPos.TOP)

      val b = n.getLayoutBounds

      Rect(b.getMinX() + n.getLayoutX(), b.getMinY() + n.getLayoutY(), b.getWidth(), b.getHeight())
    }

    def fakeLayout(n: Node, pt: Pt) : Rect = {
      Rect(pt.x, pt.y, snapSize(pwidth(n)), snapSize(pheight(n)))
    }

    def determineLayout(width: Width): Cell[(Parens,WrapStyle,Rect)] = {
      val unbrokenCells = applyUp(parenthesizedCells)(unbroken)

      def selectG[A,B](a: A, b: B): (A,B) = (a, b)
      val parenUnbrokenWidth = merge(selectG[Parens,Width])(parenthesizedCells, unbrokenCells)
      val fitCells = applyDown(parenUnbrokenWidth, width)(fit)

      def selectF[A,B,C](a: (A,B), b: C): (A,B,C) = (a._1, a._2, b)
      val sizeReq = merge(selectF[Parens,Width,WrapStyle])(parenUnbrokenWidth, fitCells)
      val sizedCells = applyUp(sizeReq)(sizeCell)

      def selectH[A,B,C,D](a: (A,B,C), b: D): (A,D,C) = (a._1, b, a._3)
      val relaxReq = merge(selectH[Parens,Width,WrapStyle,Sz])(sizeReq, sizedCells)
      val relaxedCells = applyDown(relaxReq, width)(relaxedFit)

      val relaxedSizeReq = merge(selectF[Parens,Width,WrapStyle])(parenUnbrokenWidth, relaxedCells)
      val relaxedSizedCells = applyUp(relaxedSizeReq)(sizeCell)

      val parensBroken = relaxedSizeReq.map({ case x:(Parens,Width,WrapStyle) => (x._1,x._3)})
      val layReq = merge(selectF[Parens,WrapStyle,Sz])(parensBroken, relaxedSizedCells)
      val layCells = applyDown(layReq, Pt(0,0))(layoutCell)

      merge(selectF[Parens,WrapStyle,Rect])(parensBroken, layCells)
    }

    protected override def layoutChildren() : Unit = {
      lastLay = Some(determineLayout(getWidth()))
      applyDown(lastLay.get, ())(applyLayout(layoutChild _))

      //update the caret location in case any wrap changes caused shifting
      val cl = caretLoc.get
      if (cl.isDefined) caretUpdated(caret)(cl, cl)
    }

    protected override def computePrefHeight(d: Double) : Double = {
      val unbrokenCells = applyUp(parenthesizedCells)(unbroken)
      val cl = determineLayout( if (d == -1) unbrokenCells.extract else d )
      cl.extract._3.h
    }

    protected override def getContentBias() : Orientation = Orientation.HORIZONTAL

    private def traverse[A](path: CellPath)(c: Cell[A]): Option[Cell[A]] ={
      if (path.isEmpty) Some(c) else {
        val tr = traverse[A](path.tail) _
        (path.head,c.out) match {
          case (ApFn,AppCell(h,_)) => tr(h)
          case (ApArg(i,_),AppCell(_,as)) => if (i >= as.size) None else tr(as(i))
          case (UnaryOp,UnaryCell(_,op,_)) => tr(op)
          case (UnaryArg,UnaryCell(_,_,exp)) => tr(exp)
          case (DelimitedArg(_,i,_),DelimitedCell(_,as,_,_,_,_)) => if (i >= as.size) None else tr(as(i))
          case (ChainOp(_,i,_),OperatorChain(_,ch)) => {
            val d = ch.delimiters
            if (i >= d.size) None else tr(d(i))
          }
          case (ChainElem(_,i,_),OperatorChain(_,ch)) => {
            val d = ch.elements
            if (i >= d.size) None else tr(d(i))
          }
          case (LetBod,LetCell(_,_,_,b)) => tr(b)
          case (LetBind(v),LetCell(_,bs,_,_)) => bs.collectFirst({
              case Cell(_,BindingCell(bv,_,_,Some(p),_,_)) if (v==bv && path.tail.head == BindingPattern) => traverse(path.tail.tail)(p)
              case Cell(_,BindingCell(bv,_,_,_,_,b)) if (v==bv) => tr(b)
            }).getOrElse(None)
          case (BindingAlt(v1,ai1),BindingCell(v2,ai2,_,Some(p),_,b)) if (v1==v2 && ai1==ai2 && path.size >= 2 && path(1) == BindingPattern) => traverse(path.drop(2))(p)
          case (BindingAlt(v1,ai1),BindingCell(v2,ai2,_,_,_,b)) if (v1==v2 && ai1==ai2) => tr(b)
          //case (BindingName,bc@BindingCell(_,_,_,_,_,_)) => tr(bc)   //TODO JWW
          case _ => None
        }
      }}

    def cellRectAt(cp: CellPath): Option[Cell[Rect]] = lastLay.flatMap( c => traverse(cp)(c.map(_._3)) )

    def cellAt(cp: CellPath): Option[CellN] = traverse(cp)(root)

    def cellPathAt(p: Pt): Option[(CellPath,Cell[Rect])] = {
      def f(cc: Cell[Rect]): (Boolean,Boolean) = if (cc.extract.contains(p)) (true,true) else (false,false)

      lastLay.flatMap( c =>
        if (c.extract._3.contains(p)) find(IndexedSeq(), c.map(_._3), f) else None )
    }
  }

  def translate(child: Node, pt: Pt) = child.parentToLocal(pt.x, pt.y)
  def hit(n: Node, pt: Pt) = n.contains(translate(n,pt))

  def print(depth: Int, t: Term) {
    t match {
      case App(e1,e2) => {
          println(depth + " APP fn:")
          print(depth+1,e1)
          println(depth + " APP arg:")
          print(depth+1,e2)
        }
      case Var(v) => println(depth + " " + v)
      case _ => println(depth + " " + t)
    }
  }

  def getCell(p: CellPath): Option[CellN] =
    for {
      cp <- cellPane(p)
      c <- cp.cellAt(p)
    } yield (c)

  def parentCell(p: CellPath): Option[(CellPath,CellN)] =
    if (p.size == 0) None
    else if (p.size == 1) {
      cellPane(p).map(cp => (IndexedSeq(),cp.root))
    }
    else {
      val parPat = p.dropRight(1)
      getCell(parPat).map((parPat,_))
    }

  def isLeaf[A](c: Cell[A]) =
    c.out match {
      case LeafCell(n) => (true, false)
      case _ => (false, true)
    }

  def isHole[A](c: Cell[A]) =
    c.out match {
      //TODO JWW: Improve this later
      case LeafCell(n) => (n.getStyleClass().contains("hole"), false)
      case _ => (false, true)
    }

  def findIn[A](as: IndexedSeq[Cell[A]], pf: Int=>CellPath, f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] =
      as.zipWithIndex.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse find(pf(ai._2), ai._1, f)
        )

  //Finds the Cell in the tree for which f returns (true,_).  If f(c)._2 is true,
  //we may find a descendent of c if f(c)._1 is true.
  //f: Cell=>(IsHit,KeepDescending)
  def find[A](path: CellPath, c: Cell[A], f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] = {
    //TODO JWW: add names as cells
    def bindFind(base: CellPath, bc: BindingCell[Cell[A]]) =
      bc.pattern.flatMap(p => find(base :+ BindingPattern, p, f)) orElse find(base, bc.body, f)

    f(c) match {
      case (false,false) => None           //not a hit, do not keep descending
      case (true,false) => Some((path,c))  //hit, but terminate here (do not descend)
      case (isHit,_) => {                  //maybe a hit, but descend (if possible) to keep checking
        (c.out match {
          case LeafCell(_) => Some((path,c))
          case bc@BindingCell(v,ai,_,_,_,_) => {
            val bp = path :+ BindingAlt(v,ai)
            bindFind(bp, bc) orElse Some((bp, c))  // problem: bc comes from c.out, which is covariant
          }
          case LetCell(let,bs,in,b) =>
            bs.foldLeft(None: Option[(CellPath,Cell[A])])(
              (s,a) => s orElse
                (a.out match {
                  case bc@BindingCell(v,_,_,_,_,_) => bindFind(path :+ LetBind(v), bc)
                  case _ => None
                })) orElse find(path :+ LetBod, b, f)
          case DelimitedCell(t,as,_,_,_,_) => findIn(as, i => path :+ DelimitedArg(t,i,as.length), f)
          case AppCell(h,as) => find(path :+ ApFn, h, f) orElse
            findIn(as, i => path :+ ApArg(i, as.length), f)
          case UnaryCell(_,op,e) => find(path :+ UnaryOp, op, f) orElse find(path :+ UnaryArg, e, f)
          case OperatorChain(fx,ch) => {
            val n = ch.elements.size
            find(path :+ ChainElem(fx, 0, n), ch.head, f).orElse(
              ch.tail.foldLeft( (0, None:Option[(CellPath,Cell[A])]) )((s,x) => x match { case (b,a) =>
                (s._1 + 1,
                 s._2.orElse(
                   find(path :+ ChainOp(fx, s._1, n), b, f).orElse(
                   find(path :+ ChainElem(fx, s._1 + 1, n), a, f))))
              })._2)
          }
          case EmptyCell => None
        }) orElse (if (isHit) Some((path,c)) else None)
      }
    }
  }

  def findNext[A](p: CellPath, parent: CellPath=>Option[(CellPath,Cell[A])], f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] = {
    parent(p).flatMap( par => ((p.last,par._2.out) match {
      case (ApFn,AppCell(_,as)) =>
        findIn(as, i => par._1 :+ ApArg(i,as.length), f)
      case (ApArg(i,n),AppCell(_,as)) =>
        findIn(as.drop(i+1), j => par._1 :+ ApArg(i+1+j,n), f)
      case (DelimitedArg(t,i,n),DelimitedCell(_,as,_,_,_,_)) =>
        findIn(as.drop(i+1), j => par._1 :+ DelimitedArg(t,i+1+j,n), f)
      case (ChainOp(fx,i,n),OperatorChain(_,ch)) =>
        find(par._1 :+ ChainElem(fx,i+1,n), ch.tail(i)._2, f) orElse
        ch.tail.drop(i+1).zipWithIndex.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse
                    find(par._1 :+ ChainOp(fx,i+1+ai._2,n), ai._1._1, f) orElse
                    find(par._1 :+ ChainElem(fx,i+1+ai._2+1,n), ai._1._2, f) )
      case (ChainElem(fx,i,n),OperatorChain(_,ch)) =>
        ch.tail.drop(i).zipWithIndex.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse
                    find(par._1 :+ ChainOp(fx,i+ai._2,n), ai._1._1, f) orElse
                    find(par._1 :+ ChainElem(fx,i+ai._2+1,n), ai._1._2, f) )
      case (LetBind(v),LetCell(_,bs,_,b)) =>
         (bs.indexWhere({ case Cell(_,BindingCell(bv,_,_,_,_,_)) => v==bv }) match {
          case i if (i >= 0 && i < bs.size - 1) =>
            bs.drop(i+1).foldLeft(None: Option[(CellPath,Cell[A])])(
              (s,a) => s orElse { a match {
                  case Cell(_,BindingCell(bv,_,_,op,_,b)) =>
                    op.flatMap(p => find(par._1 :+ LetBind(bv) :+ BindingPattern, p, f)) orElse
                    find(par._1 :+ LetBind(bv), b, f)
                  case _ => None
                }
              }
            )
          case _ => None
        }) orElse find(par._1 :+ LetBod, b, f)
      case (UnaryOp,UnaryCell(_,_,exp)) => find(p :+ UnaryArg, exp, f)
      case _ => None
    }).orElse(
      if (p.size == 2) {
        parent(par._1).flatMap(bc => (bc._2.out,p(1)) match {
          case (BindingCell(v,ai,n,Some(p),e,b),BindingPattern) => find(par._1, b, f)  //were looking in the pattern, now move to looking in the body
          case _ => None
        })
      }
      else findNext(par._1, parent, f) //go up one more level and look for the next
    ))
  }

  def findLastIn[A](as: IndexedSeq[Cell[A]], pf: Int=>CellPath, f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] =
      as.zipWithIndex.reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse findLast(pf(ai._2), ai._1, f)
        )

  //Finds the first Cell encountered while traversing in reverse order (or rather from the
  //right-hand side) in the tree for which f returns (true,_).  If f(c)._2 is true,
  //we may find a descendent of c if f(c)._1 is true.
  //f: Cell=>(IsHit,KeepDescending)
  def findLast[A](path: CellPath, c: Cell[A], f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] = {
    //TODO JWW: add names as cells
    def bindFindLast(base: CellPath, bc: BindingCell[Cell[A]]) =
      findLast(base, bc.body, f) orElse bc.pattern.flatMap(p => find(base :+ BindingPattern, p, f))

    f(c) match {
      case (false,false) => None           //not a hit, do not keep descending
      case (true,false) => Some((path,c))  //hit, but terminate here (do not descend)
      case (isHit,_) => {                  //maybe a hit, but descend (if possible) to keep checking
        (c.out match {
          case LeafCell(_) => Some((path,c))
          case bc@BindingCell(v,ai,_,_,_,b) => {
            val bp = path :+ BindingAlt(v,ai)
            bindFindLast(bp, bc) orElse Some((bp, c))
          }
          case LetCell(let,bs,in,b) =>
            findLast(path :+ LetBod, b, f) orElse
              bs.reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
                (s,a) => s orElse
                  (a.out match {
                    case bc@BindingCell(v,_,_,_,_,b) => bindFindLast(path :+ LetBind(v), bc)
                    case _ => None
                  }))
          case DelimitedCell(t,as,_,_,_,_) => findLastIn(as, i => path :+ DelimitedArg(t,i,as.length), f)
          case AppCell(h,as) => findLastIn(as, i => path :+ ApArg(i, as.length), f) orElse
            findLast(path :+ ApFn, h, f)
          case UnaryCell(_,op,e) => findLast(path :+ UnaryArg, e, f) orElse findLast(path :+ UnaryOp, op, f)
          case OperatorChain(fx,ch) => {
            val n = ch.elements.size
            ch.tail.reverse.foldLeft( (0, None:Option[(CellPath,Cell[A])]) )((s,x) => x match { case (b,a) =>
              (s._1 + 1,
               s._2 orElse
               findLast(path :+ ChainElem(fx, s._1 + 1, n), a, f) orElse
               findLast(path :+ ChainOp(fx, s._1, n), b, f))
            })._2 orElse findLast(path :+ ChainElem(fx, 0, n), ch.head, f)
          }
          case EmptyCell => None
        }) orElse (if (isHit) Some((path,c)) else None)
      }
    }
  }

  def findPrevious[A](p: CellPath, parent: CellPath=>Option[(CellPath,Cell[A])], f: Cell[A]=>(Boolean,Boolean)): Option[(CellPath,Cell[A])] = {
    parent(p).flatMap( par => ((p.last,par._2.out) match {
      case (ApArg(i,n),AppCell(h,as)) =>
        findLastIn(as.dropRight(n-i), j => par._1 :+ ApArg(j,n), f) orElse
        findLast(par._1 :+ ApFn, h, f)
      case (DelimitedArg(t,i,n),DelimitedCell(_,as,_,_,_,_)) =>
        findLastIn(as.dropRight(n-i), j => par._1 :+ DelimitedArg(t,j,n), f)
      case (ChainOp(fx,i,n),OperatorChain(_,ch)) =>
        ch.tail.dropRight(n-1-i).zipWithIndex.reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse
                    findLast(par._1 :+ ChainElem(fx,ai._2+1,n), ai._1._2, f) orElse
                    findLast(par._1 :+ ChainOp(fx,ai._2,n), ai._1._1, f)
        ) orElse findLast(par._1 :+ ChainElem(fx,0,n), ch.head, f)
      case (ChainElem(fx,i,n),OperatorChain(_,ch)) if (i > 0) =>
        findLast(par._1 :+ ChainOp(fx,i-1,n), ch.tail(i-1)._1, f) orElse
        ch.tail.dropRight(n-i).zipWithIndex.reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,ai) => s orElse
                    findLast(par._1 :+ ChainElem(fx,ai._2+1,n), ai._1._2, f) orElse
                    findLast(par._1 :+ ChainOp(fx,i+ai._2,n), ai._1._1, f)
        ) orElse findLast(par._1 :+ ChainElem(fx,0,n), ch.head, f)
      case (LetBod,LetCell(_,bs,_,_)) =>
        bs.reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
          (s,a) => s orElse { a match {
              case Cell(_,BindingCell(bv,_,_,op,_,b)) =>
                findLast(par._1 :+ LetBind(bv), b, f) orElse
                op.flatMap(p => findLast(par._1 :+ LetBind(bv) :+ BindingPattern, p, f))
              case _ => None
            }
          }
        )
      case (LetBind(v),LetCell(_,bs,_,_)) =>
        (bs.indexWhere({ case Cell(_,BindingCell(bv,_,_,_,_,_)) => v==bv }) match {
          case i if (i > 0 && i < bs.size) =>
            bs.dropRight(bs.size-i).reverse.foldLeft(None: Option[(CellPath,Cell[A])])(
              (s,a) => s orElse { a match {
                  case Cell(_,BindingCell(bv,_,_,op,_,b)) =>
                    op.flatMap(p => findLast(par._1 :+ LetBind(bv) :+ BindingPattern, p, f)) orElse
                    findLast(par._1 :+ LetBind(bv), b, f)
                  case _ => None
                }
              }
            )
          case _ => None
        })
      case (UnaryArg,UnaryCell(_,op,_)) => findLast(p :+ UnaryOp, op, f)
      case _ => None
    }).orElse(
      if (p.size == 2) {
        parent(par._1).flatMap(bc => (bc._2.out,p(1)) match {
          case (BindingCell(v,ai,n,Some(p),e,b),BindingPattern|BindingName) => None
          case (BindingCell(v,ai,n,Some(p),e,b),_) => findLast(par._1 :+ BindingPattern, p, f)  //were looking in the body, now move to looking in the pattern
          case _ => None
        })
      }
      else findPrevious(par._1, parent, f) //go up one more level and look for the previous
    ))
  }

  def unfoldCursor(n: Int, acc: Cursor[Term,Term] = Empty[Term]())(e: Cursor[Term,Term]): Cursor[Term,Term] = n match {
    case i if (i <= 0) => acc
    case 1 => acc ++ e
    case _ => unfoldCursor(n - 1, acc ++ e)(e)
  }

  def fnPath(n: Int) = unfoldCursor(n)(Cursors.Terms.Fn)
  def argPath(n: Int) = unfoldCursor(n)(Cursors.Terms.Arg)
  def fnArgPath(n: Int) = unfoldCursor(n)(Cursors.Terms.Fn ++ Cursors.Terms.Arg)

  def cursor(cpe: CellPathElement): Cursor[Term,Term] = cpe match {
    case BindingAlt(_,_) => Empty():Cursor[Term,Term] //TODO JWW: fix this so we don't need it to be here...?
    case BindingName => Empty():Cursor[Term,Term]     //TODO JWW: still need to hook up the Name (Cursors.Bindings.Name)
    case BindingPattern => Empty():Cursor[Term,Term]  //TODO JWW: still need to hook up the Params
    case LetBind(_) => Empty():Cursor[Term,Term]      //TODO JWW: still need to hook up the let bindings
    case LetBod => Cursors.Terms.LetBody
    case UnaryOp => Cursors.Terms.Fn
    case UnaryArg => Cursors.Terms.Arg
    case ChainOp(fx,i,n) => (fx match {
        case Infix(_,AssocL) |
             Infix(_,AssocN) => unfoldCursor(n - 2 - i)(Cursors.Terms.Fn ++ Cursors.Terms.Arg)
        case Infix(_,AssocR) => unfoldCursor(i)(Cursors.Terms.Arg)
        case _ => sys.error("Unexpected fixity: " + fx)
      }) ++ Cursors.Terms.Fn ++ Cursors.Terms.Fn
    case ChainElem(fx,i,n) => fx match {
        case Infix(_,AssocL) | Infix(_,AssocN) =>
          unfoldCursor(n - 1 - i)(Cursors.Terms.Fn ++ Cursors.Terms.Arg) ++
            (if (i == 0) Empty() else Cursors.Terms.Arg)
        case Infix(_,AssocR) =>
          unfoldCursor(i)(Cursors.Terms.Arg) ++
            (if (i == n - 1) Empty() else (Cursors.Terms.Fn ++ Cursors.Terms.Arg))
        case _ => sys.error("Unexpected fixity: " + fx)
      }
    case ApFn => Cursors.Terms.Fn
    case ApArg(i,n) => fnPath(n - 1 - i) ++ Cursors.Terms.Arg
    case DelimitedArg(t,i,n) => t match {
      case Product(_,k) => fnPath(n - 1 - i) ++ Cursors.Terms.Arg
      case Var(vt) => vt.name.get match {
        case Global("List","cons_Bracket",_) | Global("Layout.Legend","cons_Bracket",_) =>
          argPath(i) ++ Cursors.Terms.Fn ++ Cursors.Terms.Arg
        case Global("Relation.Row","snoc_Brace",_) | Global("Relation.Row","single_Brace",_) =>
          fnArgPath(n - 1 - i) ++ Cursors.Terms.Arg
        case Global("Field","cons",_) =>
          argPath(i) ++ Cursors.Terms.Fn
        case _ => sys.error("Unexpected TermVar in Cell to Cursor translation: " + vt)
      }
      case (v:TermVar,ai:Int) => Empty():Cursor[Term,Term]   //TODO JWW: Binding args pattern
      case x => sys.error("Bad delimited arg: " + x)
    }
  }

  def pathToCursor(path: CellPath): Option[Cursor[Module,Term]] = if (path.isEmpty) None else
    altCursor(path.head).map(ac => path.tail.foldLeft(ac ++ Cursors.Alts.Body)( (c,cpe) => c ++ cursor(cpe) ))

  def bindingCursor(pe: CellPathElement): Option[Cursor[Module,ImplicitBinding]] = pe match {
    case BindingAlt(v,_) => Some(Cursors.Modules.Binding(v))
    case _ => None
  }

  def altCursor(pe: CellPathElement): Option[Cursor[Module,Alt]] = pe match {
    case BindingAlt(v,ai) => Some(Cursors.Modules.Binding(v) ++ Cursors.Bindings.Alt(ai))
    case _ => None
  }

  def nodeAt(c: Cell[Rect], pt: Pt): Option[Node] = if (!c.extract.contains(pt)) None else
    c.out match {
      case LeafCell(n) => Some(n)
      case DelimitedCell(_,_,start,stop,d,_) => (IndexedSeq(start,stop) ++ d).find(hit(_,pt))
      case BindingCell(_,_,n,_,e,_) => IndexedSeq(n,e).find(hit(_, pt))
      case LetCell(let,_,in,_) => IndexedSeq(let,in).find(hit(_, pt))
      //TODO JWW: should we do a "closest hit" match for things that don't directly have nodes?
      //TODO JWW: parens?
      case _ => None
    }

  def hideCaret = {
    caretLoc.set(None)
    setStatus(None)
  }

  def findAncestor(f: Node => Boolean, cur: Node): Option[Node] = {
    f(cur) match {
      case true => Some(cur)
      case false if cur != null => findAncestor(f, cur.getParent())
      case _ => None
    }
  }

  def findDescendent(f: Node => Boolean, cur: Node): Option[Node] = f(cur) match {
    case true => Some(cur)
    case false if (cur != null && cur.isInstanceOf[Parent]) => {
      import scala.collection.JavaConversions._

      cur.asInstanceOf[Parent].getChildrenUnmodifiable().foldLeft(None:Option[Node])(
        (s,a) => s orElse findDescendent(f, a)
      )
    }
    case _ => None
  }

  def setCaret(path: CellPath) =
    for {
      cp <- cellPane(path)
      c <- cp.cellAt(path)
      s <- findAncestor(_.isInstanceOf[StackPane], cp)
    } yield {
      val target = s.asInstanceOf[StackPane]
      val par = caret.getParent() match {
        case null => compose(new Pane())(caret)
        case p => p
      }

      //check to see if the grandparent is already the stackpane; if so, skip adding
      par.getParent() match {
        case gp if (gp == target) => ()
        case gp:Pane => {
          gp.getChildren().remove(par)
          target.getChildren().add(0, par)

        }
        case null => target.getChildren().add(0, par)
      }

      caretLoc.set(Some(CaretLoc(path)))
    }

  def createCaret = {
    val ct = new Pane()
    ct.setManaged(false)
    ct.getStyleClass().add("caret")
    caretLoc.addListener(caretUpdated(ct) _)
    ct
  }

  def caretUpdated(ct: Node)(oldVal: Option[CaretLoc], newVal: Option[CaretLoc]) = {
    newVal match {
      case None => ct.setVisible(false)
      case Some(cloc) => {
        cloc.update(ct)
        ct.setVisible(true)
        ensureVisible(ct)
      }
    }
  }

  def ensureVisible(n: Node) = findAncestor(_.isInstanceOf[ScrollPane], n) foreach {
    case s => {
      val sp = s.asInstanceOf[ScrollPane]
      val b = sp.sceneToLocal(n.localToScene(n.getBoundsInLocal()))
      val height = sp.getContent().getLayoutBounds().getHeight()
      def vToPixels(v: Double) = (v - sp.getVmin()) / (sp.getVmax() - sp.getVmin()) * height
      def vFromPixels(v: Double) = v / height * (sp.getVmax() - sp.getVmin()) + sp.getVmin()
      val vph = sp.getViewportBounds().getHeight()

      if (b.getMinY() < 0) {
        sp.setVvalue(vFromPixels(vToPixels(sp.getVvalue()) + b.getMinY() - 8))
      }
      else if (b.getMaxY() > vph) {
        sp.setVvalue(vFromPixels(vToPixels(sp.getVvalue()) + b.getMaxY() - vph + 8))
      }
    }
  }

  def cursor(n: Node): Option[MCursor[Any]] = {
    findAncestor(_.isInstanceOf[CellPane], n).flatMap( c => {
      val cp = c.asInstanceOf[CellPane]
      val pt = n.localToParent(0, 0)
      val path = cp.cellPathAt(Pt(pt.getX(), pt.getY()))
      path.flatMap(p => {
        val cur:Option[Cursor[Module,Term]] = pathToCursor(p._1)
        cur.asInstanceOf[Option[MCursor[Any]]]  //ugly explicit cast
      })
    })
  }

  def node(cur: MCursor[Any]): Option[Node] = cur match {
    case Compose(a,b) => a match {
      //case Cursors.Modules.Binding(v) => sys.error("TODO JWW")
      case _ => None
    }
    case _ => rootNode
  }

  def cellPaneDescendent(n: Node): Option[CellPane] = {
    val d:Option[Node] = findDescendent(_.isInstanceOf[CellPane], n)
    d.asInstanceOf[Option[CellPane]]
  }

  def cellPane(path: CellPath): Option[CellPane] = if (path.isEmpty) None else
    path.head match {
      case BindingAlt(v,ai) => bindings.get((v,ai)).flatMap(cellPaneDescendent)
      case _ => None
    }

  def cellAt(path: CellPath): Option[CellN] = cellPane(path).flatMap(_.cellAt(path))

  //TODO JWW: fix this up--break out classes
  def buildInteractivity = ViewInteractivity(this)

  case class ViewInteractivity[F[_],E,S](private val view: ViewImpl[F,E,S]) extends Interactivity[Node] {
    import JFXUtil._

    implicit def extractPoint(me: MouseEvent): Pt = Pt(me.getX(), me.getY())
    implicit def fromJFXpoint(pt: Point2D): Pt = Pt(pt.getX(), pt.getY())

    def enableAt[F[_],E,S](editor: Editor[F,E,S,Node])(node: Node): Unit = {
      node.addEventHandler(MouseEvent.MOUSE_CLICKED, handleClick(editor) _)
      val keyHandler = handleKey(editor) _
      node.addEventHandler(KeyEvent.KEY_PRESSED, keyHandler)
    }

    def enable[F[_],E,S](editor: Editor[F,E,S,Node]): Unit = ()

    def cellPane(pt: Pt): Option[CellPane] = bindings.values.foldLeft(None:Option[CellPane])( (s,a) => s orElse {
      def isHit(n: Node) = view.root match {
        case None => false
        case Some(r) => n.contains(n.sceneToLocal(r.localToScene(pt.x, pt.y)))
      }

      if (!isHit(a)) None
      else cellPaneDescendent(a)
    })

    def replace(root: CellN)(path: CellPath)(replacement: CellN): CellN = modify(path, { _:CellN => replacement })(root)

    def replaceOp(root: CellN)(path: CellPath)(replacementOp: CellN, fxR: Fixity): CellN =
      path.last match {
        case ChainOp(fx,i,n) if (fx != fxR) => {
          //Precedence matters here in order to know how they should be grouped into chains.
          //When we analyze the AST to build chains, precedence doesn't matter because they
          //will be encountered in the proper order.  But when we are building it ourselves,
          //we have to make the cell structure correspond to what we would get from analyzing
          //the AST if it had had this structure.
          def splitMod(inCell: CellN): CellN = Cell(inCell.out match {
            case OperatorChain(fx, ch) => {
              if (fxR.prec > fx.prec) {
                val mch = ch.mapElement(i, a => Cell(OperatorChain(fxR, Delimited(a, replacementOp, ch.tail(i)._2))))
                val (r,s) = mch.tail.splitAt(i)
                OperatorChain(fx, Delimited(mch.head, r ++ s.drop(1)))
              }
              else {
                val (r,s) = ch.tail.splitAt(i)
                val left  = Cell(OperatorChain(fx, Delimited(ch.head, r)))
                val right = Cell(OperatorChain(fx, Delimited(s(0)._2, s.drop(1))))
                OperatorChain(fxR, Delimited(left, replacementOp, right))
              }
            }
            case x => sys.error("Unexpected cell type: " + x)
          })

          modify(path.dropRight(1), splitMod)(root)
        }
        case x => replace(root)(path)(replacementOp)
      }

    sealed trait KeyModifier {
      def value: Int
      override def equals(v: Any) = v match {
        case k:KeyModifier => k.value == value
        case _ => false
      }
    }
    object KeyModifier {
      case object NoModifier extends KeyModifier { def value = 0 }
      case object AltMod extends KeyModifier { def value = 1 }
      case object CtrlMod extends KeyModifier { def value = 2 }
      case object ShiftMod extends KeyModifier { def value = 4 }
      case class Combo (val ms: Set[KeyModifier]) extends KeyModifier {
        def value = ms.map(_.value).sum
      }

      def apply(alt: Boolean, ctrl: Boolean, shift: Boolean): KeyModifier =
        (IndexedSeq(alt,ctrl,shift) zip IndexedSeq(AltMod,CtrlMod,ShiftMod) filter (_._1) map (_._2)) match {
          case IndexedSeq(x) => x
          case xs => Combo(xs.toSet)
        }
    }
    import KeyModifier._
    object Combo {
      def unapplySeq(c: Combo): Option[List[KeyModifier]] =  {
        Some(c.ms.toList.sortWith(_.value < _.value))
      }
    }

    case class KeyBinding(val keyCode: KeyCode, val modifier: KeyModifier = NoModifier)
    object KeyBinding {
      def apply(ke: KeyEvent): KeyBinding = KeyBinding(ke.getCode(), KeyModifier(ke.isAltDown(), ke.isControlDown(), ke.isShiftDown()))
    }

    def newBinding[F[_],E,S](editor: Editor[F,E,S,Node]): Unit = {
      NewBindingOperation(txt => for {
          cur <- editor.declareTopLevel(Some(txt), 0)
          b <- editor.at(cur)
        } yield b).start
    }

    def safeParse[A,B](a: A, f: A=>B): Option[B] =
      try { Some(f(a)) }
      catch { case _ : java.lang.NumberFormatException => None }

    object PShort {
      def unapply(s: String) : Option[Short] = safeParse[String,Short](s, _.toShort)
    }
    object PInt {
      def unapply(s: String) : Option[Int] = safeParse[String,Int](s, _.toInt)
    }
    object PLong {
      def unapply(s: String) : Option[Long] = safeParse[String,Long](s, _.toLong)
    }
    object PFloat {
      def unapply(s: String) : Option[Float] = safeParse[String,Float](s, _.toFloat)
    }
    object PDouble {
      def unapply(s: String) : Option[Double] = safeParse[String,Double](s, _.toDouble)
    }
    object PByte {
      def unapply(s: String) : Option[Byte] = safeParse[String,Byte](s, _.toByte)
    }

    def itemGenerator[F[_],E,S](editor: Editor[F,E,S,Node])(typ: Type)(baseItems: List[(TermVar,Term,Type)]): String=>List[TermItem] = {
      val loc = builtin
      str => {
        def matches(tc: Type) = editor.matches(tc,typ).getOrElse(false)
        val tt = IndexedSeq[(Type,PartialFunction[String,Term])](
          (Type.int,    { case PInt(i)    => LitInt(loc,i) }),
          (Type.short,  { case PShort(sh) => LitShort(loc,sh) }),
          (Type.long,   { case PLong(lg)  => LitLong(loc,lg) }),
          (Type.float,  { case PFloat(f)  => LitFloat(loc,f) }),
          (Type.double, { case PDouble(d) => LitDouble(loc,d) }),
          (Type.byte,   { case PByte(b)   => LitByte(loc,b) }),
          (Type.char,   { case s if (s.length == 1) => LitChar(loc,s(0)) }),
          (Type.string, { case s if (s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) => LitString(loc,s.substring(1,s.length-1)) })
        )
        val tfs = tt.foldLeft( List[LitWrapper]() )( (s,a) =>
          if (matches(a._1)) a._2.andThen(LitWrapper(_,a._1) :: s).
            orElse({case st => s}:PartialFunction[String,List[LitWrapper]])(str)
          else s )
        tfs.reverse ++ baseItems.map(ts => VarWrapper(ts._1, ts._2, ts._3))
      }
    }

    def editAt[F[_],E,S](editor: Editor[F,E,S,Node])(path: CellPath) = {
      for {
        cp <- ViewImpl.this.cellPane(path)
        c <- getCell(path)
      } yield {
        val fullCur = pathToCursor(path)
        fullCur.foreach { cur => {
          val typ = editor.typeOfReplacement(cur)
          println("TYPE_OF: " + typ.map(Pretty.prettyType(_)).getOrElse("(None)"))
          for {
            t <- typ
            items <- editor.indirectMatches(cur, t, None)
          } yield(
            if (!items.isEmpty) {
              def rep(c: CellN): CellN = cp.updateRoot(replace(cp.root)(path)(c))
              def repOp(c: CellN, fx: Fixity) = cp.updateRoot(replaceOp(cp.root)(path)(c, fx))
              val ed = EditOperation[TermItem](de(itemGenerator(editor)(t)(items)), path, c.map(_=>()),
                {
                  case Left(c) => {
                    rep(c)
                    setCaret(path)
                    c
                  }
                  case Right(ti) => {
                    editor.replace(cur, ti.term)
                    val nc = terml(ti.term)

                    path.last match {
                      case ChainOp(_,_,_) => {
                        val fx = ti match {
                          case VarWrapper(V(_,_,Some(nm),_,_),t,ty) => nm.fixity
                          case _ => sys.error("Unable to determine fixity for: " + ti)
                        }
                        repOp(nc,fx)
                      }
                      case _ => rep(nc)
                    }

                    find(path, nc, isHole[Unit]) match {
                      case Some((hp,_)) => setCaret(hp)
                      case None => {
                        setCaret(path)
                        moveCaret(editor)(_.nextHole())
                      }
                    }

                    nc
                  }
                })
              //edit = Some(ed)
              ed.start
            }
          )
        }}
      }
    }

    def addArgument[F[_],E,S](editor: Editor[F,E,S,Node])(path: CellPath) = {
      def appendCell(c: CellN): Unit = updatePattern({
          case None => path.head match {
            case BindingAlt(v,ai) => patternCell(v,ai,List(c))
            case p => sys.error("Malformed path: " + p)
          }
          case Some(Cell(_,DelimitedCell(t,as,start,stop,d,df))) => Some(Cell(DelimitedCell(t,as :+ c,start,stop,d :+ df(),df)))
        })

      def dropRightCell() = updatePattern(_.flatMap {
          case Cell(_,DelimitedCell(t,as,start,stop,d,df)) => if (as.size == 1) None else Some(Cell(DelimitedCell(t,as.dropRight(1),start,stop,d.dropRight(1),df)))
        })

      //Applies a function to update the pattern of the binding
      def updatePattern(f: Option[CellN]=>Option[CellN]): Unit =
        ViewImpl.this.cellPane(path).map(cp =>
          cp.updateRoot(cp.root match {
            case Cell((),BindingCell(v,ai,n,p,e,b)) => Cell(BindingCell(v,ai,n,f(p),e,b))
            case c => sys.error("Illegal state: unexpected non-BindingCell: " + c)
          }))

      AddArgumentOperation(path, appendCell, dropRightCell, {
        nm => for {
          bpe <- if (path.isEmpty) None else Some(path(0))
          bc <- bindingCursor(bpe)
          unt <- editor.addArgument(bc,Some(nm))
          cp <- ViewImpl.this.cellPane(path)
          b <- editor.at(bc)
          pc <- bpe match {
                  case BindingAlt(_,ai) => {
                    val pats = b.alts(ai).patterns
                    Some(pattern(pats(pats.length - 1)))
                  }
                  case _ => None
                }
        } yield (pc)
      }).start
    }

    def clearAt[F[_],E,S](editor: Editor[F,E,S,Node])(path: CellPath) =
      for {
        cp <- ViewImpl.this.cellPane(path)
        cur <- pathToCursor(path)
      } yield {
        val t = Hole(builtin)
        editor.replace(cur, t)
        cp.updateRoot(replace(cp.root)(path)(terml(t)))
        setCaret(path)
      }

    def evalAt[F[_],E,S](editor: Editor[F,E,S,Node])(path: CellPath) =
      for {
        cur <- pathToCursor(path)
        t <- editor.eval(cur)
        cp <- ViewImpl.this.cellPane(path)
      } yield {
        println("EVAL: " + t)
        //TODO JWW: do we need to be concerned about replaceOp?
        cp.updateRoot(replace(cp.root)(path)(terml(t)))
        setCaret(path)
      }

    def introduceCalleeAt[F[_],E,S](editor: Editor[F,E,S,Node])(path: CellPath) =
      for {
        cur <- pathToCursor(path)
        holeCur <- editor.introduceCallee(cur)
        newHole <- editor.at(holeCur)
        cp <- ViewImpl.this.cellPane(path)
        c <- getCell(path)
      } yield {
        c match {
          case Cell(_,fn@LeafCell(n)) => {
            val nc = Cell(AppCell(fn, IndexedSeq(terml(newHole))))
            cp.updateRoot(replace(cp.root)(path)(nc))

            find(path, nc, isHole[Unit]) match {
              case Some((hp,_)) => setCaret(hp)
              case None => {
                setCaret(path)
                moveCaret(editor)(_.nextHole())
              }
            }
          }
          case _ => sys.error("TODO JWW")
        }
      }

    def handleKey[F[_],E,S](editor: Editor[F,E,S,Node])(ke: KeyEvent): Unit =
      KeyBinding(ke) match {
        case KeyBinding(KeyCode.SPACE,NoModifier) |
             KeyBinding(KeyCode.ENTER,NoModifier) => doAtCaret(p => editAt(editor)(p))
        case KeyBinding(KeyCode.N,CtrlMod)        => newBinding(editor)
        case KeyBinding(KeyCode.A,Combo(CtrlMod,ShiftMod)) => doAtCaret(p => addArgument(editor)(p))
        case KeyBinding(KeyCode.DOWN,CtrlMod)     => moveCaret(editor)(_.down())
        case KeyBinding(KeyCode.UP,CtrlMod)       => moveCaret(editor)(_.up())
        case KeyBinding(KeyCode.LEFT,NoModifier)  => moveCaret(editor)(_.left())
        case KeyBinding(KeyCode.RIGHT,NoModifier) => moveCaret(editor)(_.right())
        case KeyBinding(KeyCode.RIGHT,CtrlMod)    => moveCaret(editor)(_.nextHole())
        case KeyBinding(KeyCode.LEFT,CtrlMod)     => moveCaret(editor)(_.prevHole())
        case KeyBinding(KeyCode.E,CtrlMod)        => doAtCaret(p => evalAt(editor)(p))
        case KeyBinding(KeyCode.DELETE,NoModifier) => doAtCaret(p => clearAt(editor)(p))
        case KeyBinding(KeyCode.I,CtrlMod)        => doAtCaret(p => introduceCalleeAt(editor)(p))
        case _ => ()
      }

    def moveCaret[F[_],E,S](editor: Editor[F,E,S,Node])(f: CaretLoc=>CaretLoc): Unit = caretLoc.get().foreach { c => {
      caretLoc.set(Some(f(c)))
      updateStatus(editor)
    }}

    def updateStatus[F[_],E,S](editor: Editor[F,E,S,Node]) =
      if (!caretLoc.get().isDefined) setStatus(None)
      else doAtCaret( p => setStatus( pathToCursor(p).flatMap(editor.typeOf(_)).map(typeToString(_)) ) )

    def doAtCaret(f: CellPath=>Unit): Unit =
      for {
        cl <- caretLoc.get()
        path = cl match { case CaretLoc(p) => p }
      } yield(f(path))

    def handleClick[F[_],E,S](editor: Editor[F,E,S,Node])(me: MouseEvent): Unit = (me.getClickCount(), me.getButton()) match {
      case (1, MouseButton.PRIMARY) => {
        cellPane(me).map(cp => {
          val cpPt = cp.sceneToLocal(me.getSceneX(), me.getSceneY())
          val pathCell = cp.cellPathAt(Pt(cpPt.getX(), cpPt.getY()))
          pathCell.foreach({ case p => {
            println(p._1)
            println("")
            val fullCur = pathToCursor(p._1)
            println("CURSOR: " + fullCur)
            println("")
            println("AT: " + fullCur.flatMap({ cur => editor.at(cur)}))
            println("")
            val node = nodeAt(p._2, Pt(cpPt.getX(), cpPt.getY()))
            println("NODE: " + node.map({
              case n if (n.isInstanceOf[Label]) => n.asInstanceOf[Label].getText()
              case n => n.toString
            }))
            setCaret(p._1)
            updateStatus(editor)
            println("")
          }})
        })
      }
      case (2, MouseButton.PRIMARY) => {
        cellPane(me).map(cp => {
          val cpPt = cp.sceneToLocal(me.getSceneX(), me.getSceneY())
          val pathCell = cp.cellPathAt(Pt(cpPt.getX(), cpPt.getY()))
          pathCell.foreach({ case p => editAt(editor)(p._1) })
        })
      }
      case (1, MouseButton.SECONDARY) => {
        cellPane(me).map(cp => {
          val cpPt = cp.sceneToLocal(me.getSceneX(), me.getSceneY())
          cp.cellPathAt(cpPt).map(hit => {
            caretLoc.get() match {
              case None => setCaret(hit._1)
              case Some(CaretLoc(path)) => if (path != hit._1) setCaret(hit._1) //TODO JWW: cross-reference in some way to see if it's selected
            }

            updateStatus(editor)

            nodeAt(hit._2, cpPt) map { node =>
              val actions = editor.availableActions(node)
              withContextMenu(node,
                contextMenu(actions.map(a => menuItem(a)(_ => editor(node,a))): _*))
            }
          })
        })
      }
      case _ => ()
    }

    trait AddOperation[R] extends Operation {
      val done = new SimpleBooleanProperty(false)
      val textField = new TextField()

      def init = {
        textField.addEventHandler(KeyEvent.KEY_PRESSED, { ke:KeyEvent => {
            KeyBinding(ke) match {
              case KeyBinding(KeyCode.ENTER,NoModifier) => accept
              case KeyBinding(KeyCode.ESCAPE,NoModifier) => cancel
              case _ => ()
            }
            ()
          }})

        def focusListener(oldV: java.lang.Boolean, newV:java.lang.Boolean): Unit =
          if (!oldV.booleanValue() && newV.booleanValue()) {
            runLater(() => {
              hideCaret
              ensureVisible(textField)
            })
          }
          else if (oldV.booleanValue() && !newV.booleanValue()) {
            cancel
          }

        textField.focusedProperty().addListener(focusListener _)
      }

      def accept = if (!done.get.booleanValue) {
        textField.getText().trim() match {
          case "" => ()
          case txt => processName(txt).foreach { r =>
            done.set(java.lang.Boolean.TRUE)
            removeTextField
            complete(r)
          }
        }
      }

      def cancel = if (!done.get.booleanValue) {
        done.set(java.lang.Boolean.TRUE)
        removeTextField
      }

      def processName(name: String): Option[R]
      def complete(r: R): Unit
      def removeTextField: Unit
    }

    case class NewBindingOperation(val declare: String=>Option[Binding]) extends AddOperation[Binding] {
      private lazy val container = new HBox(horizSpacer)

      def start = {
        init
        compose(container)(textField, ViewImpl.this.equals: Node, hole)
        compose(bindingContainer)(container)
        runLater(() => textField.requestFocus)
      }

      def processName(name: String): Option[Binding] = declare(name)
      def complete(b: Binding): Unit = {
        addBindings(List(b))
        setCaret(IndexedSeq(BindingAlt(b.v, 0)))
      }
      def removeTextField: Unit = bindingContainer.getChildren().remove(container)
    }

    case class AddArgumentOperation(val path: CellPath, val appendCell: CellN=>Unit, val dropRightCell: ()=>Unit, val declare: String=>Option[CellN]) extends AddOperation[CellN] {
      def start = {
        init
        appendCell(Cell(LeafCell(textField)))
        runLater(() => textField.requestFocus)
      }

      def processName(name: String): Option[CellN] = declare(name)
      def complete(c: CellN): Unit = {
        appendCell(c)
        //return you to where you started
        setCaret(path)
      }
      def removeTextField: Unit = dropRightCell()
    }

    case class EditOperation[A <: OBItem](val omni: Omnibox[A], val path: CellPath, val origCell: CellN, val replace: Either[CellN,A]=>CellN)
               extends Operation {
      def start = {
        hideCaret
        omni.beginSelection(None, setupTextField, handleResult)
      }

      def cancel: Unit = replace(Left(origCell))

      def setupTextField(tf: TextField): Unit = runLater(() => {
        replace(Left(LeafCell(tf)))
        tf.requestFocus()
      })

      def handleResult(r: Option[A]): Unit = replace(r.map(Right(_)).getOrElse(Left(origCell)))
    }
  }

  def typeToString(typ: Type): String = {
    val w = new StringWriter()
    Pretty.prettyType(typ, -1).format(Integer.MAX_VALUE, w)
    w.toString
  }

  trait TermItem extends OBItem {
    def term: Term
    def typ: Type

    private val typeProp = new SimpleObjectProperty(typeToString(typ))

    def typeProperty: ObjectProperty[String] = typeProp

    //TODO JWW: refactor this into a separate type passed into the omnibox function
    override def columns = super.columns + ("Type" -> ("type", 350, None))
  }

  //Wraps a TermVar to provide an alternate definition of toString.  This should be
  //improved at some point, but since it's unclear as of yet how various fields will
  //be commuted into the omnibox.
  case class VarWrapper(val tv: TermVar, val term: Term, val typ: Type) extends TermItem {
    private val moduleProp = new SimpleObjectProperty(tv.name.map({
        case Global(module,_,_) => module
        case _ => "(local)"
      }).getOrElse(""))

    private def countHoles(s: Term): Int = s match {
      case App(f,Hole(_)) => 1+countHoles(f)
      case _ => 0
    }
    private val numHoles = countHoles(term)

    def toDisplay = tv.name.map(nm => (nm.fixity,numHoles) match {
      case (_,0) => nm.string
      case (Prefix(_),1) => nm.string + " ?"
      case (Postfix(_),1) | (Infix(_,_),1) => "? " + nm.string
      case (Infix(_,_),2) => "? " + nm.string + " ?"
      case _ => nm.string + (" ?" * numHoles)
    }).getOrElse(tv.toString() + (" ?" * numHoles))

    override def filter(s: String): Boolean = tv.name.map(_.toString).getOrElse(tv.toString).toUpperCase().contains(s.toUpperCase())

    def moduleProperty: ObjectProperty[String] = moduleProp

    //TODO JWW: refactor this into a separate type passed into the omnibox function
    override def columns = Map("Module" -> ("module", 100, Some(TableColumn.SortType.ASCENDING))) ++ super.columns
  }

  case class LitWrapper(val term: Term, val typ: Type) extends TermItem {
    def toDisplay = if (typ == Type.string) "\"" + term.toString + "\"" else term.toString

    //TODO JWW: refactor this into a separate type passed into the omnibox function
    private val moduleProp = new SimpleObjectProperty("")
    def moduleProperty: ObjectProperty[String] = moduleProp
    override def columns = Map("Module" -> ("module", 100, Some(TableColumn.SortType.ASCENDING))) ++ super.columns
  }
}

