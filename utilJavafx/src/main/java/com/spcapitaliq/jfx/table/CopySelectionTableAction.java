package com.spcapitaliq.jfx.table;

import javafx.event.ActionEvent;
import javafx.scene.control.TableView;

import com.spcapitaliq.jfx.JFXClipboard;

/**
 * Action to copy selection from the table.
 *
 * @author mmorton
 */
public class CopySelectionTableAction<S, ST> extends AbstractTableViewAction<S, ST>
{
  @Override
  protected void handle(final TableView<S> table, final TableViewDataProvider<S, ST> provider, final ActionEvent ae)
  {
    JFXClipboard.copyTableSelection(table, provider);
  }

  @Override
  protected String defineActionText()
  {
    return "Copy Selection";
  }
}
