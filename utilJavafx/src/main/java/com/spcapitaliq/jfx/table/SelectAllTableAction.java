package com.spcapitaliq.jfx.table;

import javafx.event.ActionEvent;
import javafx.scene.control.TableView;

/**
 * Action to select all in the table.
 *
 * @author mmorton
 */
public class SelectAllTableAction<S, ST> extends AbstractTableViewAction<S, ST>
{
  @Override
  protected void handle(final TableView<S> table, final TableViewDataProvider<S, ST> provider, final ActionEvent ae)
  {
    table.getSelectionModel().selectAll();
  }

  @Override
  protected String defineActionText()
  {
    return "Select All";
  }
}
