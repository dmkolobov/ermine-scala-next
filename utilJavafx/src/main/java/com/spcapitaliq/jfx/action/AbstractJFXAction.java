package com.spcapitaliq.jfx.action;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.control.MenuItem;

/**
 *
 * @author mmorton
 *
 */
public abstract class AbstractJFXAction<N extends Node> implements EventHandler<ActionEvent>
{
  private volatile N _node;

  private void verifyNode()
  {
    if (null == _node)
      throw new NullPointerException("Associated Node is null, make sure to call initialize properly");
  }

  @Override
  public final void handle(ActionEvent ae)
  {
    verifyNode();
    // else
    handle(ae, _node);
  }

  protected abstract void handle(ActionEvent ae, N node);

  protected abstract String defineActionText();

  public final MenuItem wrapInMenuItem(N node)
  {
    _node = node;
    MenuItem item = new MenuItem(defineActionText());
    item.setOnAction(this);
    wrapInMenuItemInit(item);
    return item;
  }

  /**
   * Optional additional init to perform on the menu item.
   *
   * @param item
   */
  protected void wrapInMenuItemInit(MenuItem item)
  {
    /** noop */
  }
}
