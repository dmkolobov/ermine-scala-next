package com.spcapitaliq.jfx.table;

import java.lang.reflect.Method;

import java.util.HashMap;
import java.util.Map;

import javafx.scene.control.TableColumn;

import javafx.collections.ListChangeListener;
import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.node.NodePostOp;
import com.spcapitaliq.jfx.node.NodeTraverser;
import com.spcapitaliq.jfx.node.NodeTraverser.HasInstanceStrategy;
import com.spcapitaliq.jfx.value.PropertyDebugger;
import com.sun.javafx.scene.control.behavior.TableCellBehavior;
import javafx.collections.FXCollections;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.*;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.Pane;
import org.apache.log4j.Logger;

/**
 *
 * @author mmorton
 *
 */
public class JFXTableUtil
{
  private static final Logger _log = Logger.getLogger(JFXTableUtil.class);

  private JFXTableUtil() { /** static only */ }

  public static class ColumnStateMigrator<S>
  {
    private final Map<String, TableColumn<S, ?>> _columns;

    public ColumnStateMigrator(TableView<S> table)
    {
      _columns = new HashMap<>();
      for( TableColumn<S, ?> column : table.getColumns() )
      {
        _columns.put(makeKey(column), column);
      }
    }

    private String makeKey(TableColumn<S, ?> column)
    {
      return column.getText();
    }

    public void applyTo(TableView<S> table)
    {
      for( TableColumn<S, ?> column : table.getColumns() )
      {
        TableColumn<S, ?> priorColumn = _columns.get(makeKey(column));
        if(null != priorColumn)
        {
          _log.debug("Column state migrated for: " + column.getText());
          column.setMinWidth(priorColumn.getMinWidth());
          column.setPrefWidth(priorColumn.getPrefWidth());
        }
      }
    }
  }

  public static <S> void monitorColumns(TableView<S> table)
  {
    for( TableColumn<S, ?> column : table.getColumns())
    {
      new PropertyDebugger<>("Column: " + column.getText(), column.prefWidthProperty());
    }
  }

  public static Pane findHeader(TableView<?> table)
  {
    return (Pane) table.lookup("TableHeaderRow");
  }

  public static boolean isColumnHeaderVisible(TableView<?> table)
  {
    return findHeader(table).isVisible();
  }

  /**
   * This method exists to counteract a known memory leak
   * with JavaFX 2.2. This method call should no longer be
   * necessary with JavaFX 8.
   *
   * @param table
   * @param <S>
   *
   */
  @Deprecated
  public static <S> void clearTable(TableView<S> table)
  {
    _log.debug("Clearing table: " + table);

    table.getFocusModel().focus( null );

    try
    {
      Method anchorMethod = TableCellBehavior.class.getDeclaredMethod( "setAnchor", TableView.class, TablePosition.class );
      anchorMethod.setAccessible( true );
      anchorMethod.invoke( null, table, null );
    }
    catch(Exception e)
    {
      _log.error("Failed to invoke setAnchor", e);
    }

    // CFI-22490: The table's skin isn't yet set, but table exists... but it will presumably
    // never get set because we're clearing out the table and removing it from the parent,
    // thus we shouldn't need to call the cleanup method for removing the mouse cursor fix,
    // which gets applied on first size.  If we don't have this guard, it will throw.
    if (null != table.getSkin())
    {
      MouseCursorInTable.removeFixCursorInPanel(table);
    }

    table.setOnMouseClicked(null);
    table.setSelectionModel(null);

    table.setItems(FXCollections.<S>observableArrayList());
  }

  /**
   * Scan through the given parent and all its children
   * to call clearTable on any TableView instances
   * present in teh graph.
   *
   * @param parent
   */
  public static void clearAllTables(final Parent parent)
  {
    JFXUtil.throwIfNotApplicationThread();

    @SuppressWarnings({"unchecked", "rawtypes"})
    class Trav extends HasInstanceStrategy<TableView> implements NodePostOp.Strategy
    {
      private final NodePostOp _postOp;

      Trav()
      {
        super(TableView.class);
        _postOp = new NodePostOp();
      }

      @Override
      protected void applyInstance(final TableView node)
      {
        clearTable(node);
        // to avoid concurrent modification of children,
        // collect things for post op
        _postOp.collect(node, this);
      }

      @Override
      public void applyPostOp(final Node node)
      {
        Parent parent = node.getParent();
        if (parent instanceof BorderPane)
        {
          BorderPane bp = (BorderPane)parent;
          bp.setCenter(null);
          bp.setCenter(null);
          _log.debug("Applied BorderPane post op to table");
        }
        else
          _log.warn("Node: " + node + " parent is not BorderPane");
      }
    }

    Trav trav = new Trav();
    NodeTraverser.traverse(parent, trav);
    trav._postOp.complete();
  }

  public static void addHeaderTooltips(final TableView<?> tableView)
  {
    for (TableColumn<?, ?> tc : tableView.getColumns())
    {
      if (tc.getGraphic() instanceof Control)
      {
        final Control control = (Control) tc.getGraphic();
        control.setTooltip(new Tooltip(tc.getText()));
      }
      else
      {
        final String text = tc.getText();
        final Label label = new Label(text);
        label.setTooltip(new Tooltip(text));
        label.setPrefWidth(Double.MAX_VALUE);
        label.setAlignment(Pos.CENTER);

        tc.setText("");
        tc.setGraphic(label);
      }
    }
  }
}
