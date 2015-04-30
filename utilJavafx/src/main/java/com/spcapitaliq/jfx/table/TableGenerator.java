package com.spcapitaliq.jfx.table;

import java.util.ArrayList;
import java.util.List;

import com.spcapitaliq.jfx.value.PropertyDebugger;
import javafx.beans.property.ReadOnlyStringWrapper;
import javafx.beans.value.ObservableValue;
import javafx.scene.control.TableColumn;
import javafx.scene.control.TableColumn.CellDataFeatures;
import javafx.scene.control.TableView;
import javafx.util.Callback;
import org.apache.log4j.Logger;

/**
 * Generates banal tables, typically used for testing.
 *
 * @author mmorton
 *
 */
public class TableGenerator
{
  private static final Logger _log = Logger.getLogger(TableGenerator.class);

  private TableGenerator() { /** static only */ }

  public static <S, T> List<TableColumn<S, T>> buildNumberedColumns(int num)
  {
    ArrayList<TableColumn<S, T>> columns = new ArrayList<>(num);
    for(int i=0; i < num; i++)
      columns.add(new TableColumn<S, T>(Integer.toString(i)));
    return columns;
  }

  public interface ItemBuilder<S>
  {
    S buildItem(int index);
  }

  public static class TestTableRow
  {
    /**
     * Returns a {@link String} that encodes the column index and the row index as "c,r".
     *
     * @author mmorton
     *
     */
    static class CellValueFactory implements Callback<TableColumn.CellDataFeatures<TestTableRow,String>,ObservableValue<String>>
    {
      private static final StringBuilder val = new StringBuilder();

      @Override
      public ObservableValue<String> call(CellDataFeatures<TestTableRow, String> p)
      {
        int colix = Integer.parseInt(p.getTableColumn().getText());
        int rowix = p.getValue()._index;
        val.setLength(0);
        val.append(colix).append(',').append(rowix);
        return new ReadOnlyStringWrapper(val.toString());
      }

    }

    private final int _index;

    private TestTableRow(int index)
    {
      _index = index;

    }
  }



  public static class ColumnWatcher
  {
    private static class NumberWatcher extends PropertyDebugger<Number>
    {
      NumberWatcher(String name, ObservableValue<Number> val)
      {
        super(name, val, _log);
      }
    }

    public ColumnWatcher(final TableColumn<?, ?> column)
    {
      new NumberWatcher("Column: " + column.getText() + " width", column.widthProperty());
      new NumberWatcher("Column: " + column.getText() + " minWidth", column.minWidthProperty());
      new NumberWatcher("Column: " + column.getText() + " prefWidth", column.prefWidthProperty());
    }
  }

  public static TableView<TestTableRow> buildTestTable(int numCols, int numRows)
  {
    List<TableColumn<TestTableRow, String>> columns = buildNumberedColumns(numCols);

    TestTableRow.CellValueFactory cvf = new TestTableRow.CellValueFactory();
    for( TableColumn<TestTableRow, String> column : columns )
    {
      column.setMinWidth(100);
      column.setCellValueFactory(cvf);
      new ColumnWatcher(column);
    }

    TableView<TestTableRow> table = new TableView<TestTableRow>();
    table.getColumns().addAll(columns);

    addItems(table, numRows, new ItemBuilder<TestTableRow>()
    {
      @Override
      public TestTableRow buildItem(int index)
      {
        return new TestTableRow(index);
      }
    });

    return table;
  }

  public static <S> void addItems(TableView<S> table, int num, ItemBuilder<S> s)
  {
    for(int i = 0; i < num; i++ )
      table.getItems().add(s.buildItem(i));
  }
}
