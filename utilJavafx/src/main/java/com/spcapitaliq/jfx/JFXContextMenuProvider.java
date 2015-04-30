package com.spcapitaliq.jfx;

import java.util.List;

import javafx.scene.Node;
import javafx.scene.control.MenuItem;
import javafx.scene.control.TableView;

import com.spcapitaliq.jfx.action.PrintImageHandler;
import com.spcapitaliq.jfx.table.TableViewDataProvider;

/**
 * Allows specification of the context menu items.
 */
public interface JFXContextMenuProvider
{
  /**
   * @param node the node to provide context menu items for
   *
   * @return the items to include in the context menu
   */
  List<MenuItem> provideContextMenuItems(Node node);

  /**
   * @param table the table to provide context menu items for
   * @param provider the table data provider
   * @return the items to include in the context menu
   */
  <S, ST> List<MenuItem> provideTableContextMenuItems(TableView<S> table, TableViewDataProvider<S, ST> provider);

  PrintImageHandler providePrintImageHandler();
}
