package com.spcapitaliq.jfx.table;

import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.TableCell;
import javafx.scene.control.TableColumn;
import javafx.scene.control.Tooltip;
import javafx.scene.text.Text;
import javafx.util.Callback;

/**
 * Creatures {@link TableCell}s with a tooltip set to the text.
 *
 * @author mmorton
 *
 */
public class CellWithTooltipFactory<S, T> implements Callback<TableColumn<S, T>, TableCell<S, T>>
{
  @Override
  public TableCell<S, T> call(TableColumn<S, T> paramP)
  {
    return new TableCell<S, T>()
    {
      @Override
      protected void updateItem(T paramObject, boolean paramBoolean)
      {
        if (paramObject == getItem())
          return;

        super.updateItem(paramObject, paramBoolean);

        Tooltip ttip = null;

        if (paramObject == null)
        {
          setText(null);
          setGraphic(null);
        }
        else if (paramObject instanceof Node)
        {
          setText(null);
          setGraphic((Node) paramObject);
        }
        else
        {
          String text = paramObject.toString();
          setText(text);
          ttip = new Tooltip(text);
          setGraphic(null);
        }
        setTooltip(ttip);
      }
    };
  }

  public static void extractText(Node node, StringBuilder txt)
  {
    if( node instanceof Text )
    {
      txt.append(((Text)node).getText());
    }
    if( node instanceof Parent)
    {
      for(Node child : ((Parent)node).getChildrenUnmodifiable() )
      {
        extractText(child, txt);
      }
    }
  }
}
