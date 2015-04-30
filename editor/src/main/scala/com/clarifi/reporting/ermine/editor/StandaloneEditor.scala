package com.clarifi.reporting
package ermine.editor

import java.io.File

import javafx.application.Platform
import javafx.scene.Node
import javafx.scene.layout.BorderPane
import javafx.scene.layout.HBox
import javafx.scene.control.TextField
import javafx.scene.control.Button
import javafx.scene.control.Label
import javafx.event.EventHandler
import javafx.event.ActionEvent
import javafx.scene.input.KeyEvent
import javafx.scene.input.KeyCode
import javafx.stage.FileChooser
import javafx.geometry.Pos
import javafx.geometry.Insets
import scalaparsers.{Document, Supply}

import com.clarifi.reporting.ermine.session._
import com.clarifi.reporting.ermine.syntax.Module
import com.spcapitaliq.jfx.JFXAppHarness
import com.clarifi.reporting.writers.jfx.Process.Promise

class StandaloneEditor

object StandaloneEditor {
  private val _log = org.apache.log4j.Logger.getLogger(classOf[StandaloneEditor])

  private var root : Option[Node] = None

  def ermineCSSFile = "res/conf/ermine/ermineEditor.css"

  def runnable(f: => Unit) = new Runnable{ def run = f }

  def runLater(f: => Unit): Unit = Platform.runLater(runnable(f))

  def docLogger(od: Option[Document]) = od.foreach { d => println(d) }

  def offsetProvider = {
    val r = root.get
    val s = r.getScene()
    val w = s.getWindow()
    (w.getX.toInt, (w.getY + w.getHeight - s.getRoot().getBoundsInLocal().getHeight).toInt)
  }

  def filter[A <: OBItem](fs: String, s: A) = s.toDisplay.toUpperCase().contains(fs.toUpperCase())

  def fileChooser(f: String => Unit, initialFile: Option[String]) : Node = {
    val file = new TextField()
    val browse = new Button("Browse")
    val load = new Button("Load")

    load.addEventHandler(ActionEvent.ACTION, new EventHandler[ActionEvent] {
      def handle(e: ActionEvent) {
        file.getText() match {
          case "" => ()
          case filename => f(filename)
        }
      }
    })

    browse.addEventHandler(ActionEvent.ACTION, new EventHandler[ActionEvent] {
      def handle(e: ActionEvent) {
        val chooser = new FileChooser()
        chooser.setInitialDirectory(new File(file.getText()).getParentFile() match {
            case p if p != null && p.exists() => p
            case _ => new File(System.getProperty("user.dir"))
          })
        val selectedFile = chooser.showOpenDialog(file.getScene().getWindow())

        selectedFile match {
          case null => ()
          case _ => {
            val path = selectedFile.getAbsolutePath().toString()
            file.setText(path)
            load.fire()
          }
        }
      }
    })

    file.addEventHandler(KeyEvent.KEY_PRESSED, new EventHandler[KeyEvent] {
      def handle(e: KeyEvent) {
        e.getCode() match {
          case KeyCode.ENTER => load.fire()
          case _ => ()
        }
      }
    })

    val buttons = new HBox(6)
    buttons.getChildren().addAll(browse, load)

    val label = new Label("Filename:")

    val bp = new BorderPane()
    bp.setLeft(label)
    bp.setCenter(file)
    bp.setRight(buttons)
    BorderPane.setMargin(buttons, new Insets(3, 3, 3, 3))
    BorderPane.setAlignment(label, Pos.CENTER)

    initialFile foreach { fn =>
      file.setText(fn)
      load.fire()
    }

    bp
  }

  //TODO JWW: Update to use type args if we get BackendImpl.loadState working properly
  //def rock[F[_],E,S](backend: Backend[F,E,S], logger: E => Unit, initialFile: Option[String])(implicit s: SessionEnv, su: Supply, con: Printer) =
  def rock(backend: BackendImpl, logger: Option[Document] => Unit, initialFile: Option[String])(implicit s: SessionEnv, su: Supply, con: Printer) =
  {
    val parent = new BorderPane();

    def loader(filename: String) = Promise.pure {
      //TODO JWW: Update to use type args if we get BackendImpl.loadState working properly
      //val state = backend.loadState(Session.readModule(filename))
      val state = (Session.readModule(filename), s, su)

      runLater {
        val view = new ViewImpl[EditorSession, Option[Document], (Module,SessionEnv,Supply)](backend,
          new Nat[List,Omnibox,OBItem]{
            def apply[A <: OBItem](i: String=>List[A]) = new SimpleOmnibox[A](i, offsetProvider)
          })
        view.load(state)

        root = view.root
        val rootNode : Node = root.get

        val editor = Editor(state, backend, view, view.buildInteractivity, logger)

        parent.setCenter(rootNode)
      }
    }

    val fileArea = fileChooser(loader, initialFile)

    parent.setTop(fileArea)
    parent.setPrefSize(600, 400)
    BorderPane.setMargin(fileArea, new Insets(4, 4, 4, 4))

    parent
  }

  def main(args: Array[String]) {
    com.clarifi.reporting.util.Logging.initializeLogging
    try {
      val backend = new BackendImpl()
      val istate = backend.initialState

      implicit val sessionEnv = istate._2
      implicit val supply = istate._3
      implicit val printer = Printer.simple

      Lib.preamble
      Session.loadModules(List("Prelude", "Layout"))

      val initialFile = if (args.length > 0) Some(args(0)) else None

      JFXAppHarness.launch(rock(backend, docLogger, initialFile), "Ermine Editor", ermineCSSFile)

    } catch {
      case e : Throwable =>
        _log.fatal("Failed to launch", e);
    }
  }
}
