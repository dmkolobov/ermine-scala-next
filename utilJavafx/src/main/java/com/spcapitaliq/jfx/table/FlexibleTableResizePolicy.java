package com.spcapitaliq.jfx.table;

import java.util.List;

import javafx.scene.control.TableColumn;
import javafx.scene.control.TableView;
import javafx.scene.control.TableView.ResizeFeatures;
import javafx.util.Callback;

/**
 * A resize policy for TableViews that switches behavior depending on whether there is
 * currently a scrollbar.
 *
 * Note that we do not claim this as a perfect solution, but it is better than using either
 * the "constrained" or "unconstrained" resize policies alone.  By making a hybrid/switching
 * resize policy, we resize the columns up if there's enough space, or if not, and a scrollbar
 * is induced, the user can still increase the widths of the columns--they don't get *stuck*
 * like they would if we used the "constrained" resize policy.
 *
 * Better still, in the future, it'd be nice to distribute the resize deltas as evenly as
 * possible over the columns so that it isn't just the rightmost resizable column that
 * gets adjusted.
 *
 * @author JWW
 */
public class FlexibleTableResizePolicy implements Callback<ResizeFeatures<?>, Boolean>
{
  private boolean _wasLastUnconstrained = false;

  @Override
  public String toString()
  {
    return "flexible-resize";
  }

  @Override
  public Boolean call(final ResizeFeatures<?> prop)
  {
    final TableView<?> table = prop.getTable();
    final double tableWidth = table.getWidth();
    final double delta = prop.getDelta();

    if (tableWidth == 0)
    {
      return Boolean.FALSE;
    }

    final TableColumn<?,?> resizeCol = prop.getColumn();

    double colWidth = 0;
    for (TableColumn<?,?> col : table.getVisibleLeafColumns()) {
      colWidth += col.getWidth();
    }

    if ((colWidth > tableWidth && (resizeCol != null || _wasLastUnconstrained)) ||
        (resizeCol != null && delta > 0 && allColumnsAtMin(table, resizeCol)))
    {
      _wasLastUnconstrained = true;
      return TableView.UNCONSTRAINED_RESIZE_POLICY.call(prop);
    }
    _wasLastUnconstrained = false;
    return TableView.CONSTRAINED_RESIZE_POLICY.call(prop);
  }

  /**
   * Returns whether or not all the columns to the right of the resize column are at their minimum size already
   *
   * @param table
   * @param resizeCol
   * @return
   */
  private boolean allColumnsAtMin(TableView<?> table, TableColumn<?,?> resizeCol)
  {
    final List<? extends TableColumn<?,?>> visibleCols = table.getVisibleLeafColumns();

    // need to find the last leaf column of the given column - it is this
    // column that we actually resize from. If this column is a leaf, then we
    // use it.
    TableColumn<?,?> leafColumn = resizeCol;
    while (leafColumn.getColumns().size() > 0)
    {
      leafColumn = leafColumn.getColumns().get(leafColumn.getColumns().size() - 1);
    }

    int colPos = visibleCols.indexOf(leafColumn);
    for (TableColumn<?,?> col : visibleCols.subList(colPos + 1, visibleCols.size()))
    {
      if (col.isResizable() && col.getWidth() > col.getMinWidth())
      {
        return false;
      }
    }

    return true;
  }
}
