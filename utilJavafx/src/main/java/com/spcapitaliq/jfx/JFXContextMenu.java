package com.spcapitaliq.jfx;

import java.util.LinkedList;
import java.util.List;

import javafx.collections.ObservableList;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.control.*;
import javafx.scene.input.MouseButton;
import javafx.scene.input.MouseEvent;
import javafx.stage.WindowEvent;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.action.PrintImageAction.DefactoPrintHandler;
import com.spcapitaliq.jfx.action.PrintImageHandler;
import com.spcapitaliq.jfx.table.AbstractTableViewAction;
import com.spcapitaliq.jfx.table.TableViewDataProvider;

/**
 * Convenience class for attaching context menus to Nodes.
 */
public class JFXContextMenu
{
  private static final Logger Log = Logger.getLogger(JFXContextMenu.class);

  private JFXContextMenu() {}

  private interface MenuItemFeeder
  {
    List<MenuItem> feedMe();
  }

  private static void addToNode(final Node node, final MenuItemFeeder feeder)
  {
    class Logic implements Runnable
    {
      @Override
      public void run()
      {
        final ContextMenu menu = new ContextMenu();
        menu.getItems().add(buildPlaceholder());
        addContextMenu(node, menu);

        menu.setOnShowing(new EventHandler<WindowEvent>()
        {
          @Override
          public void handle(WindowEvent we)
          {
            try
            {
              ObservableList<MenuItem> items = menu.getItems();
              items.setAll(feeder.feedMe());
            }
            catch (Exception e )
            {
              Log.error("Failed to feed menu items", e);
            }
          }
        });
      }
    }
    JFXUtil.runIfSafeOrOnFirstSized(node, new Logic());
  }

  @JFXSafe
  public static void addToNode(Node node)
  {
    addToNode(node, new DefactoContextMenuProvider());
  }

  @JFXSafe
  public static void addToNode(final Node node, final JFXContextMenuProvider providerContextMenu)
  {
    JFXUtil.throwIfNull(node, "node");
    JFXUtil.throwIfNull(providerContextMenu, "providerContextMenu");

    class NodeFeeder implements MenuItemFeeder
    {
      @Override
      public List<MenuItem> feedMe()
      {
        return providerContextMenu.provideContextMenuItems(node);
      }
    }

    addToNode(node, new NodeFeeder());
  }

  @JFXSafe
  public static <S, ST> void addToTable(final TableView<S> table,
                                        final JFXContextMenuProvider providerContextMenu,
                                        final TableViewDataProvider<S, ST> providerTableViewData)
  {
    JFXUtil.throwIfNull(table, "table");
    JFXUtil.throwIfNull(providerContextMenu, "providerContextMenu");
    JFXUtil.throwIfNull(providerTableViewData, "providerTableViewData");

    class TableFeeder implements MenuItemFeeder
    {
      @Override
      public List<MenuItem> feedMe()
      {
        return providerContextMenu.provideTableContextMenuItems(table, providerTableViewData);
      }
    }
    addToNode(table, new TableFeeder());
  }

  private static void addContextMenu(final Node node, final ContextMenu menu)
  {
    if (node instanceof Control)
      ((Control) node).setContextMenu(menu);
    else
      node.addEventHandler(MouseEvent.MOUSE_CLICKED,
                           new EventHandler<MouseEvent>()
                           {
                             @Override
                             public void handle(MouseEvent e)
                             {
                               if (e.getButton() == MouseButton.SECONDARY)
                                 menu.show(node, e.getScreenX(), e.getScreenY());
                               else if(menu.isShowing())
                                 menu.hide();
                             }
                           });
  }

  /**
   * This placeholder will be replaced by the actual menu items from the
   * provider when it's shown.
   *
   * @return
   */
  private static MenuItem buildPlaceholder()
  {
    final MenuItem placeholder = new MenuItem("<placeholder>");
    placeholder.setDisable(true);
    return placeholder;
  }

  public static List<MenuItem> safeProvideContextMenuItems(Node node, PrintImageHandler printHandler)
  {
    List<MenuItem> menu = new LinkedList<>();

    try
    {
      menu.addAll(JFXClipboard.provideImageCaptureMenuItems(node, printHandler));
    }
    catch (Exception e)
    {
      Log.error("Failed to add table image capture items", e);
    }

    return menu;
  }

  public static <S,ST> List<MenuItem> safeProvideTableContextMenuItems(TableView<S> table, final TableViewDataProvider<S, ST> provider, PrintImageHandler printHandler)
  {
    List<MenuItem> menu = new LinkedList<>();

    try
    {
      menu.addAll(AbstractTableViewAction.provideCopyToClipboardMenuItems(table, provider));
    }
    catch (Exception e)
    {
      Log.error("Failed to add table clipboard items", e);
    }
    menu.add(new SeparatorMenuItem());
    menu.addAll(safeProvideContextMenuItems(table, printHandler));

    return menu;

  }

  public static class DefactoContextMenuProvider implements JFXContextMenuProvider
  {
    @Override
    public List<MenuItem> provideContextMenuItems(final Node node)
    {
      return safeProvideContextMenuItems(node, providePrintImageHandler());
    }

    @Override
    public <S, ST> List<MenuItem> provideTableContextMenuItems(final TableView<S> table, final TableViewDataProvider<S, ST> provider)
    {
      return safeProvideTableContextMenuItems(table, provider, providePrintImageHandler());
    }

    @Override
    public PrintImageHandler providePrintImageHandler()
    {
      return new DefactoPrintHandler();
    }
  }
}
