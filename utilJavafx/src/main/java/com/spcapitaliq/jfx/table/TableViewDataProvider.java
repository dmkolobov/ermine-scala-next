package com.spcapitaliq.jfx.table;

import java.util.Collection;
import java.util.List;

import javafx.scene.control.TableColumn;

public interface TableViewDataProvider<S, ST>
{
  /**
   * Will be called ahead of provideCellData(TableColumn, int) to do any
   * preparation of the data.
   *
   * @param sortedColumns all the columns of the table, useful for determining sort order
   * @param selectedColumns the columns to load
   * @param rows the rows to load or null for all rows
   */
  ST prepareData(List<TableColumn<S, ?>> sortedColumns, Collection<TableColumn<S, ?>> selectedColumns, Collection<Integer> rows);

  List<String> provideCellData(ST data, TableColumn<S, ?> column, int row );

  int countSyntheticColumns(TableColumn<S, ?> column);
}
