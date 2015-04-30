package com.clarifi.reporting.ermine.editor

import collection.immutable.IndexedSeq

import javafx.application.Platform
import javafx.embed.swing.JFXPanel
import javafx.scene.Node
import javafx.geometry.Bounds
import javafx.scene.Parent
import javafx.scene.control.TextField
import javafx.scene.control.TableView
import javafx.scene.control.TableColumn
import javafx.scene.control.cell.PropertyValueFactory
import javafx.scene.input.MouseEvent
import javafx.scene.input.KeyEvent
import javafx.scene.input.KeyCode
import javafx.stage.Popup
import javafx.beans.property._
import javafx.beans.value.ObservableValue
import javafx.beans.Observable
import javafx.beans.InvalidationListener
import javafx.collections.FXCollections
import javafx.event.EventHandler
import javafx.scene.layout.Pane
import javafx.scene.Group

trait Overlay {
  def updateLocation(anchorBounds: Bounds)
  def close
}

trait OBItem {
  private val displayProp = new ReadOnlyStringPropertyBase() {
      def get = toDisplay
      def getBean = null
      def getName = ""
    }
  def toDisplay: String
  
  //column name -> (property name, pref column width, sort type)
  def columns: Map[String,(String,Int,Option[TableColumn.SortType])] = { Map(("Name", ("display", 300, Some(TableColumn.SortType.ASCENDING)))) }
  
  def filter(s: String): Boolean = toDisplay.toUpperCase().contains(s.toUpperCase())
  
  def displayProperty(): ReadOnlyStringProperty = displayProp
}

trait Omnibox[A <: OBItem] {
  private val filter = new TextField()

  private var explorerOverlay : Option[Overlay] = None

  /////////////////////////////////////////////////////

  def build(tf: TextField, f: Option[A] => Unit)

  def showDataExplorer(anchor: Node) : Overlay

  /////////////////////////////////////////////////////

  def beginSelection(initialSelection: Option[A], showAndFocusFilter: TextField=>Unit, resultHandler: Option[A]=>Unit) = {
    filter.focusedProperty().addListener(new ShowDataExplorerListener(filter, initialSelection, resultHandler))
    filter.boundsInParentProperty().addListener(new FilterLocationListener(filter))

    build(filter, resultHandler)

    showAndFocusFilter(filter)
  }

  def closeOverlay = explorerOverlay.foreach { o =>
    o.close
    explorerOverlay = None
  }
  
  class ShowDataExplorerListener(val tf: TextField, val initialSelection: Option[A], val f: Option[A] => Unit) extends javafx.beans.value.ChangeListener[java.lang.Boolean]
  {
    def changed(o: ObservableValue[_ <: java.lang.Boolean], oldVal: java.lang.Boolean, newVal: java.lang.Boolean) = {
      import java.lang.Boolean
    
      (explorerOverlay,oldVal,newVal) match {
        case (None, Boolean.FALSE, Boolean.TRUE) => {
          tf.setText(initialSelection.map(_.toDisplay).getOrElse(""))
          tf.selectAll()

          explorerOverlay = Some(showDataExplorer(tf))
        }
        case (Some(_), Boolean.TRUE, Boolean.FALSE) => {
          closeOverlay
          f(None)
        }
        case _ => ()
      }
    }
  }

  class FilterLocationListener(val tf: TextField) extends javafx.beans.value.ChangeListener[Bounds]
  {
    def changed(o: ObservableValue[_ <: Bounds], oldVal: Bounds, newVal: Bounds) = {
      explorerOverlay foreach {
        e => e.updateLocation(tf.localToScene(tf.getBoundsInLocal()))
      }
    }
  }
}

case class SimpleOverlay(val p: Popup, val locationOffset: (Int,Int)) extends Overlay
{
  def updateLocation(anchorBounds: Bounds) = {
    p.setX(anchorBounds.getMinX + locationOffset._1)
    p.setY(anchorBounds.getMaxY + locationOffset._2)
  }
  
  def close = p.hide()
}

case class SimpleOmnibox[A <: OBItem](
    val allItems: String=>List[A],
    val locationOffset: (Int,Int))
  extends Omnibox[A]
{
  import javafx.util.Callback
  /** Adapt Scala function to JavaFX "function". */
  implicit def callback[A, B](f: A => B): Callback[A, B] = new Callback[A, B] {
    def call(a: A) = f(a)
  }

  private val table = new TableView[A]
  private val filterProperty = new SimpleStringProperty()
  
  def build(tf: TextField, f: Option[A] => Unit) = {
    import scala.collection.JavaConversions._
    
    val initialItems = allItems("")
    val (tableCols,sortCols) = if (initialItems.isEmpty) {
      val tableCol = new TableColumn[A,A]("Items/Actions")
      tableCol.setCellValueFactory {
        (p: TableColumn.CellDataFeatures[A, A]) => new ReadOnlyObjectWrapper(p.getValue())
      }
      (IndexedSeq(tableCol),IndexedSeq[TableColumn[A,A]]())
    } else {
      val a0 = initialItems(0)
      (a0.columns.toSeq.map{ case (name,(property,width,sort)) => {
        val tableCol = new TableColumn[A,A](name)
        tableCol.setCellValueFactory(new PropertyValueFactory(property))
        tableCol.setPrefWidth(width)
        sort.foreach(tableCol.setSortType(_))
        (tableCol, sort.map(_ => IndexedSeq(tableCol)).getOrElse(IndexedSeq[TableColumn[A,A]]()))
      }}).unzip({ case (a,b) => (a,b) }) match { case (a,b) => (a,b.flatten) }
    }

    table.getColumns().setAll(tableCols :_*)
    table.setItems(FXCollections.observableArrayList(initialItems : java.util.List[A]))
    if (!sortCols.isEmpty) table.getSortOrder().setAll(sortCols :_*)
    table.addEventFilter(KeyEvent.KEY_PRESSED, new TextFieldKeyListener(tf, f))
    table.addEventFilter(MouseEvent.MOUSE_CLICKED, new TableClickListener(tf, f))
    table.getSelectionModel().selectedItemProperty().addListener(new TableSelectionListener(tf))
    table.setColumnResizePolicy(TableView.CONSTRAINED_RESIZE_POLICY)
    
    tf.textProperty().addListener(new TableUpdater(tf))
  }

  def showDataExplorer(anchor: Node) : Overlay = {
    val p = new Popup()
    p.setHideOnEscape(false)

    p.getContent().add(table)
    val b = anchor.localToScene(anchor.getBoundsInLocal())
    p.show(anchor, b.getMinX + locationOffset._1, b.getMaxY + locationOffset._2)
    
    SimpleOverlay(p, locationOffset)
  }
  
  def currentSelection : Option[A] = {
    val sm = table.getSelectionModel()
    if (sm.isEmpty()) None else Some(sm.getSelectedItem())
  }
  
  class TextFieldKeyListener(tf: TextField, f: Option[A] => Unit) extends EventHandler[KeyEvent]
  {
    def handle(ke: KeyEvent) = {
      //TODO JWW: shift key, ctrl key, etc.
      if (!ke.isAltDown() && !ke.isControlDown() && !ke.isShiftDown() && !ke.isShortcutDown()) {
        ke.getCode() match {
          case KeyCode.ESCAPE => { 
            closeOverlay
            f(None)
          }
          case KeyCode.ENTER => currentSelection foreach { a =>
            closeOverlay
            f(Some(a))
          }
          case _ => ()
        }
      }
    }    
  }
  
  class TableClickListener(tf: TextField, f: Option[A] => Unit) extends EventHandler[MouseEvent]
  {
    def handle(me: MouseEvent) =
    {
      if (me.getClickCount == 2)
      {
        currentSelection foreach { a =>
          closeOverlay
          f(Some(a))
        }
        
        me.consume()
      }
    }
  }
  
  class TableSelectionListener(tf: TextField) extends javafx.beans.value.ChangeListener[A]
  {
    def changed(o: ObservableValue[_ <: A], oldVal: A, newVal: A) = {
      newVal match {
        case null => ()
        case v => {
          val s = v.toDisplay
          filterProperty.setValue(s)
          tf.setText(s)
          tf.positionCaret(s.length)
          tf.requestFocus
        }
      }
    }
  }
  
  class TableUpdater(tf: TextField) extends javafx.beans.value.ChangeListener[String]
  {
    def changed(o: ObservableValue[_ <: String], oldVal: String, newVal: String) = {
      val fv = filterProperty.getValue()
      val s = newVal.trim()
      
      if (!s.isEmpty() && (fv == null || !fv.equals(newVal)))
      {
        filterProperty.setValue(newVal)
        
        import scala.collection.JavaConversions._
        
        val newItems = allItems(s).foldRight(List[A]())( (a, res) => if (a.filter(s)) a::res else res )
        
        table.getItems().setAll(newItems : java.util.List[A])
      }
    }
  }
}
