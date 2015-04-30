package com.spcapitaliq.jfx.table;

import java.util.ArrayList;
import java.util.List;

import com.spcapitaliq.jfx.JFXUtil;
import com.sun.javafx.scene.control.skin.NestedTableColumnHeader;
import com.sun.javafx.scene.control.skin.TableHeaderRow;
import com.sun.javafx.scene.control.skin.TableViewSkin;
import javafx.collections.ListChangeListener;
import javafx.collections.ObservableList;
import javafx.event.EventHandler;
import javafx.scene.Cursor;
import javafx.scene.Node;
import javafx.scene.control.TableView;
import javafx.scene.input.MouseEvent;
import javafx.scene.shape.Rectangle;
import org.apache.log4j.Logger;

/**
 * Hack for introducing the resize cursor in between table columns. This is necessary in the current iteration of
 * JavaFX when a JFXPanel is used. It should be benign to use in a full JavaFX application (such as what gets
 * launched from REPL).
 *
 * @author mmorton
 *
 */
public class MouseCursorInTable
{
  private static final Logger _log = Logger.getLogger(MouseCursorInTable.class);

  private static void changeHandler(final TableView<?> tableView, final List<Node> children)
  {
    for (Node node : children)
    {
      if (!(node instanceof Rectangle))
      {
        continue;
      }

      _log.trace("Adding handlers for: " + node);

      final Rectangle rect = (Rectangle) node;
      rect.setOnMouseEntered(new EventHandler<MouseEvent>()
      {
        @Override
        public void handle(MouseEvent mouseEvent)
        {
          tableView.setCursor(Cursor.W_RESIZE);
        }
      });

      rect.setOnMouseExited(new EventHandler<MouseEvent>()
      {
        @Override
        public void handle(MouseEvent mouseEvent)
        {
          tableView.setCursor(Cursor.DEFAULT);
        }
      });
    }
  }

  private static void removeHandler(List<Node> children)
  {
    for (Node node : children)
    {
      if (node instanceof Rectangle)
      {
        Rectangle rect = ( Rectangle ) node;

        rect.setOnMouseEntered( null );
        rect.setOnMouseExited( null );
      }
    }
  }

  public static void removeFixCursorInPanel(final TableView<?> tableView )
  {
    JFXUtil.throwIfNotApplicationThread();

    TableViewSkin<?> skin = (TableViewSkin<?>) tableView.getSkin();

    if(null == skin)
      throw new NullPointerException("Skin not present yet, try calling again with delay set to true");

    for (Node skinNode : skin.getChildren())
    {
      if (skinNode instanceof TableHeaderRow)
      {
        final TableHeaderRow headerRow = (TableHeaderRow) skinNode;
        for (Node headerNode : headerRow.getChildrenUnmodifiable())
        {
          _log.debug("Removing fix for headerNode: " + headerNode);

          if (headerNode instanceof NestedTableColumnHeader)
          {
            final NestedTableColumnHeader nestedHeader = (NestedTableColumnHeader) headerNode;

            ObservableList<Node> headerChildren = nestedHeader.getChildren();
            removeHandler(headerChildren);
          }
        }
      }
    }
  }

  public static void fixCursorInPanel(final TableView<?> tableView, boolean delay )
  {
    if( delay )
    {
      JFXUtil.setOnFirstSized(tableView, new Runnable() {

        @Override
        public void run()
        {
          fixCursorInPanel(tableView, false);
        }
      });
      return;
    }

    _log.trace("Fixing table resize cursors");

    TableViewSkin<?> skin = (TableViewSkin<?>) tableView.getSkin();

    if(null == skin)
      throw new NullPointerException("Skin not present yet, try calling again with delay set to true");

    for (Node skinNode : skin.getChildren())
    {
      if (skinNode instanceof TableHeaderRow)
      {
        final TableHeaderRow headerRow = (TableHeaderRow) skinNode;
        for (Node headerNode : headerRow.getChildrenUnmodifiable())
        {
          _log.debug("Fixing headerNode: " + headerNode);

          if (headerNode instanceof NestedTableColumnHeader)
          {
            final NestedTableColumnHeader nestedHeader = (NestedTableColumnHeader) headerNode;

            ObservableList<Node> headerChildren = nestedHeader.getChildren();
            changeHandler(tableView, headerChildren);
            headerChildren.addListener(new ListChangeListener<Node>()
            {
              @Override
              public void onChanged(Change<? extends Node> change)
              {
                _log.trace("Header nodes changed.");

              while (change.next())
              {
                if (change.wasAdded())
                {
                  changeHandler(tableView, new ArrayList<>(change.getList()));
                }
              }
              }
            });
          }
        }
      }
    }
  }
}
