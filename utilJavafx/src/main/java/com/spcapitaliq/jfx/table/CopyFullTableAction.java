package com.spcapitaliq.jfx.table;

import javafx.event.ActionEvent;
import javafx.scene.control.TableView;
import javafx.scene.input.ClipboardContent;

import com.spcapitaliq.jfx.JFXClipboard;
import com.spcapitaliq.jfx.concurrency.BlockerModal;

/**
 * Action to copy the full table.
 *
 * @author mmorton
 */
public class CopyFullTableAction<S, ST> extends AbstractTableViewAction<S, ST>
{
  private final boolean _includeHeader;

  public CopyFullTableAction(boolean includeHeader)
  {
    _includeHeader = includeHeader;
  }

  @Override
  protected void handle(final TableView<S> table, final TableViewDataProvider<S, ST> provider, final ActionEvent ae)
  {
    class CopyFullTableLogic extends JFXClipboard.ToClipboardLogic
    {
      @Override
      protected void populateContent(ClipboardContent content)
      {
        JFXClipboard.copyFullTableToClipboard(table, provider, _includeHeader, content);
      }
    }
    new BlockerModal().show(table, new CopyFullTableLogic());
  }

  @Override
  protected String defineActionText()
  {
    return _includeHeader ? "Copy Table with Headers" : "Copy Table";
  }
}
