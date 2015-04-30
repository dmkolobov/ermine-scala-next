package com.spcapitaliq.jfx.qa;

import com.spcapitaliq.jfx.JFXClipboard;
import com.spcapitaliq.jfx.table.*;
import com.spcapitaliq.jfx.JFXTraverser;
import javafx.scene.control.TableView;

/**
 * A Node that wraps a {@link TableView} to provide programmatic
 * access to the table's underlying data.
 * @author mmorton
 *
 */
public class QATableViewWrapper<S, ST> extends TableView<S>
{
  private TableViewDataProvider<S, ST> _dataProvider;
  private boolean _includeHeader;

  public QATableViewWrapper(boolean includeHeader)
  {
    this( new TrivialTableViewDataProvider<S, ST>(), includeHeader);
  }
  
  public QATableViewWrapper(TableViewDataProvider<S, ST> dataProvider, boolean includeHeader)
  {
    _dataProvider = dataProvider;
    _includeHeader = includeHeader;
  }
  
  public void setDataProvider(TableViewDataProvider<S, ST> dataProvider)
  {
    _dataProvider = dataProvider;
  }
  
  /**
   * Copies the table to the clipboard in both plain-text and HTML format.
   * 
   * @return a copy of the tab delimted plain text copied to clipboard
   */
  public String qaCopyFullTableToClipboard()
  {
    return JFXClipboard.copyFullTableToClipboard(this, _dataProvider, _includeHeader);
  }
  
  public String qaFindNearbyText()
  {
    return JFXTraverser.findNearbyText(this);
  }
}
