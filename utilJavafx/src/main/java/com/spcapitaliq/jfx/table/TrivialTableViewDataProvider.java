package com.spcapitaliq.jfx.table;

import java.util.Collection;
import java.util.Collections;
import java.util.List;

import javafx.scene.control.TableColumn;

import com.spcapitaliq.jfx.JFXClipboard;

/**
 * Trivial implementation that calls {@link TableColumn#getCellData(int)}.
 * This approach is only applicable for tables that have all their data
 * loaded into memory already (i.e. are not lazy loaded).
 * @author mmorton
 *
 */
public class TrivialTableViewDataProvider<S, ST> implements TableViewDataProvider<S, ST>
{
  @Override
  public ST prepareData(List<TableColumn<S, ?>> sortedColumns, Collection<TableColumn<S, ?>> selectedColumns, Collection<Integer> rows)
  {
    /** noop */
    return null;
  }

  @Override
  public List<String> provideCellData(ST data, TableColumn<S, ?> column, int row)
  {
    return Collections.singletonList(JFXClipboard.cellToPlainText(column.getCellData(row)));
  }

  @Override
  public int countSyntheticColumns(TableColumn<S, ?> column)
  {
    return 1;
  }
}
