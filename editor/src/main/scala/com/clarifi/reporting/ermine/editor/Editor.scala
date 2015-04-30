package com.clarifi.reporting.ermine.editor

import Backend.{MCursor,Loc}

import com.clarifi.reporting.ermine._

object Editor {

  def apply[F[_],E,S,Node](S: S, B: Backend[F,E,S], V: View[F,E,S,Loc,Node],
                           I: Interactivity[Node], logError: E => Unit) = {
    new Editor[F,E,S,Node](S, V.root.get, B, V, I, logError)
  }
}

object Renderers {

  sealed trait Key
  case class ValueKey(typ: Type) extends Key
  case class FunctionKey(term: TermVar, arity: Int) extends Key
  case class VariadicKey(term: TermVar) extends Key

  /** To use a renderer, you'll have to */
  sealed trait Renderer {
    def key: Key
  }
  /** `typ` should have some type `t`, and `render`
    * should have the type `t -> Report z a`. */
  case class ValueRenderer(typ: Type, render: Term) extends Renderer {
    val key = ValueKey(typ)
  }
  /** `term` should be of the given arity, and `render`
    * should have the type `forall z . List z -> Report z a`. */
  case class FunctionRenderer(term: TermVar, arity: Int, render: Term) extends Renderer {
    val key = FunctionKey(term, arity)
  }
  /** `term` should have the type `List a -> b` for some types a and b,
    * and `render` should have the type `forall z . List z -> Report z a.` */
  case class VariadicRenderer(term: TermVar, render: Term) extends Renderer {
    val key = VariadicKey(term)
  }
}

trait View[F[_],E,S,Loc,Node] extends PathTranslator[Node] {
  import Renderers._
  val B: Backend[F,E,S]
  def renderers: List[Renderer]

  //def toCursor(l: Loc): Option[MCursor[_]]
  //def fromCursor(l: MCursor[_]): Loc
  //def embed(at: MCursor[Term]): F[Node]
  def changeRenderer(at: Loc, to: Key): Unit
  def apply(a: B.Action[_,_], at: Loc): Unit
  def load(S: S): Unit
  def root: Option[Node]
}

/** Responsible for adding event listeners and callbacks, based
 *  on the set of actions available in the `Editor`.
 */
trait Interactivity[Node] {
  /** Enable any editor-based interactivity for the given `Node`.
    * As an example, this might, on mouseclick of the given `Node`,
    * use the `PathTranslator` in `editor` to determine the set of
    * available actions, and add UI controls based on these actions. */
  def enableAt[F[_],E,S](editor: Editor[F,E,S,Node])(node: Node): Unit

  /** Enable any editor-wide interactivity. */
  def enable[F[_],E,S](editor: Editor[F,E,S,Node]): Unit
}

import javafx.scene.Node
import javafx.scene.control.{ContextMenu,MenuItem}
import javafx.scene.input.MouseEvent
import javafx.scene.input.MouseButton
import javafx.event.EventHandler
import javafx.event.{ActionEvent,Event}
import javafx.geometry.Side
import javafx.beans.value.ObservableValue
import javafx.beans.value.ChangeListener

object JFXUtil {
  implicit def handler[T<:Event](callback: T => Unit): EventHandler[T] =
    new EventHandler[T] { def handle(event: T): Unit = callback(event) }
  implicit def changeListener[E](f: (E,E) => Unit) = new ChangeListener[E] {
    def changed(o: ObservableValue[_ <: E], oldVal: E, newVal: E) = f(oldVal, newVal)
  }

  def menuItem(label: Any)(callback: ActionEvent => Unit): MenuItem = {
    val item = new MenuItem(label.toString)
    item.setOnAction(callback)
    item
  }

  def contextMenu(menuItems: MenuItem*): ContextMenu = {
    val menu = new ContextMenu
    menuItems.foreach(menu.getItems.add)
    menu
  }

  def withContextMenu(n: Node, menu: ContextMenu, side: Side = Side.TOP): Node = {
    menu.show(n, side, 0, 0)
    n
  }

}

object Interactivity {
  import JFXUtil._

  def JFX = new Interactivity[Node] {
    def enable[F[_],E,S](editor: Editor[F,E,S,Node]): Unit = ()

    def enableAt[F[_],E,S](editor: Editor[F,E,S,Node])(node: Node): Unit = {
      // node.onMouseClicked.set(foo) doesn't work??
      node.addEventHandler(MouseEvent.MOUSE_CLICKED, { e: MouseEvent =>
        if (e.getButton() == MouseButton.SECONDARY) {
          val actions = editor.availableActions(node)
          withContextMenu(node,
            contextMenu(actions.map(a => menuItem(a)(_ => editor(node,a))): _*))
        }
        ()
      })
    }
  }

}

class Editor[F[_],E,S,Node] private (
    var S: S, var root: Node,
    val B: Backend[F,E,S],
    val V: View[F,E,S,Loc,Node],
    val I: Interactivity[Node],
    logError: E => Unit) {

  //TODO JWW:
  I.enable(this)
  V.root.foreach(I.enableAt(this))

  def availableActions(node: Node): List[B.Action[_,_]] = {
    V.cursor(node) match {
      case None => List()
      case Some(loc) => {
        val actions = B.run(S, B.availableActions[Any](loc)) match {
          case Left(e) => { logError(e); List() }
          case Right((a,_)) => a // explicitly ignoring new state
        }
        println("Cursor: " + loc + "  Actions: " + actions)
        actions
      }
    }
  }

  def run[A](f: F[A]): Option[A] = B.run(S, f) match {
      case Left(e) => { logError(e); None }
      case Right((a,s)) => { S = s; Some(a) }
    }

  def typeOf(cur: MCursor[Term]): Option[Type] = run(B.typeOf(cur))

  def typeOfReplacement(cur: MCursor[Term]): Option[Type] = run(B.typeOfReplacement(cur)) 

  def environment(cur: MCursor[Term], typ: Type, name: Option[String]): Option[List[TermVar]] =
    run(B.environment(cur, typ, name))

  def indirectMatches(cur: MCursor[Term], typ: Type, name: Option[String]): Option[List[(TermVar,Term,Type)]] =
    run(B.indirectMatches(cur, typ, name))

  def matches(t1: Type, t2: Type): Option[Boolean] = run(B.matches(t1, t2))

  def replace[A](cur: MCursor[A], a: A): Unit = run(B.replace(cur, a))

  def at[A](cur: MCursor[A]): Option[A] = B.at(cur)(S)

  def declareTopLevel(name: Option[String], argCount: Int): Option[MCursor[ImplicitBinding]] = run(B.declareTopLevel(name, argCount))
  
  def addArgument(loc: MCursor[ImplicitBinding], name: Option[String]): Option[Unit] = run(B.addArgument(loc, name))

  def eval(loc: MCursor[Term]): Option[Term] = run(B.eval(loc))

  def introduceCallee(cur: MCursor[Term]): Option[MCursor[Term]] = run(B.introduceCallee(cur))

  /** Applies the given action to the given node, and updates all
    * the internal state used by this `Editor`. */
  def apply(node: Node, action: B.Action[_,_]): Unit = action match {
    case B.IntroduceCaller(f) => B.run(S, f) match {
      case Left(e) => logError(e)
      case Right(((f,arg), s2)) =>
        //TODO JWW:
        //val nodePaths = paths(node)
        //val hole = V.hole
        //val ap = V.ap(hole)(node)
        //V.replaceInParent(node, ap)
        //paths = paths +
        //  (node -> List(Terms.Arg.asInstanceOf[Loc])) +
        //  (hole -> List(Terms.Fn.asInstanceOf[Loc])) +
        //  (ap -> nodePaths)

        S = s2
    }
    case _ => sys.error("todo: " + action)
  }

  def get: Node = root
}
