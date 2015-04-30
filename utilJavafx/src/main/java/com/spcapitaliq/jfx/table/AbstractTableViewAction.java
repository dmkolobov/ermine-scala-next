package com.spcapitaliq.jfx.table;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.control.MenuItem;
import javafx.scene.control.MenuItemBuilder;
import javafx.scene.control.TableView;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.action.AbstractJFXAction;

/**
 *
 * @param <S>
 * @param <ST>
 *
 * @author mmorton
 */
public abstract class AbstractTableViewAction<S, ST> extends AbstractJFXAction<TableView<S>>
{
  private static final Logger Log = Logger.getLogger(AbstractTableViewAction.class);

  private TableViewDataProvider<S, ST> _provider;

  public AbstractTableViewAction() {}

  public final void initProvider(TableViewDataProvider<S, ST> provider)
  {
    _provider = provider;
    verifyProvider();
  }

  private void verifyProvider()
  {
    if (null == _provider)
      throw new NullPointerException("provider is null, make sure to call initialize properly");
  }

  protected final void handle(ActionEvent ae, TableView<S> table)
  {
    try
    {
      verifyProvider();
      handle(table, _provider, ae);

    }
    catch (Exception e)
    {
      Log.error("Failed to handle", e);
    }
  }

  protected abstract void handle(TableView<S> table, TableViewDataProvider<S, ST> provider, ActionEvent ae);

  public static <S, ST> List<MenuItem> provideCopyToClipboardMenuItems(TableView<S> table, TableViewDataProvider<S, ST> provider)
  {
    if (null == provider)
      provider = new TrivialTableViewDataProvider<S, ST>();

    List<AbstractTableViewAction<S, ST>> actions = new ArrayList<>(4);
    actions.add(new CopySelectionTableAction<S, ST>());
    actions.add(new SelectAllTableAction<S, ST>());
    actions.add(new CopyFullTableAction<S, ST>(false));
    if (JFXTableUtil.isColumnHeaderVisible(table))
      actions.add(new CopyFullTableAction<S, ST>(true));

    return developMenuItems(table, provider, actions);
  }

  public static <S, ST> MenuItem developMenuItem(TableView<S> table, TableViewDataProvider<S, ST> provider, AbstractTableViewAction<S, ST> action)
  {
    action.initProvider(provider);
    return action.wrapInMenuItem(table);
  }

  public static <S, ST> List<MenuItem> developMenuItems(TableView<S> table, TableViewDataProvider<S, ST> provider, List<AbstractTableViewAction<S, ST>> actions)
  {
    List<MenuItem> items = new LinkedList<MenuItem>();
    for (AbstractTableViewAction<S, ST> action : actions)
    {
      items.add(developMenuItem(table, provider, action));
    }
    return items;
  }
}