package com.spcapitaliq.jfx

/** Annotate a type with a
  * [com.spcapitaliq.jfx.JFXClipboard#cellToPlainText] result, which
  * overrides any other choice.
  */
trait WithPlainText {
  def plainText: String
}

/** Scala rewrite of part of JFXClipboard. */
object JFXClipboardS {
  import scala.collection.JavaConverters._
  import javafx.scene.{Node, Parent}
  import javafx.scene.text.Text
  import javafx.scene.control.{Labeled, TextInputControl}

  def cellToPlainText(cell: Any): String = cell match {
    case null => ""
    case wpt: WithPlainText => wpt.plainText
    case cell: Parent =>
      val txt = new StringBuilder()
      plainTextFromParent(cell, txt)
      txt.toString()
    case cell: Node => plainTextFromNode(cell)
    case _ => cell.toString()
  }

  private[this]
  def plainTextFromNode(cell: Node): String = cell match {
    case cell: Text => cell.getText()
    case cell: Labeled => cell.getText()
    case cell: TextInputControl => cell.getText()
    case _ => ""
  }

  private[this]
  def plainTextFromParent(node: Parent, txt: StringBuilder): Unit =
    for (child <- node.getChildrenUnmodifiable().asScala) {
      child match {
        case child: Parent => plainTextFromParent(child, txt)
        case _ => txt.append(cellToPlainText(child))
      }
    }
}
