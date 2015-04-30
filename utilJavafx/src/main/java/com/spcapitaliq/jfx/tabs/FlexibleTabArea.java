package com.spcapitaliq.jfx.tabs;

import javafx.scene.control.TabPane;
import javafx.scene.layout.StackPane;

/**
 * 
 * @author mmorton
 *
 */
public final class FlexibleTabArea extends StackPane
{
  private final TabPane _tabs;

  public FlexibleTabArea()
  {
    _tabs = new TabPane();
    
    getChildren().add(_tabs);
  }
  
  public TabPane peekTabs()
  {
    return _tabs;
  }
}
