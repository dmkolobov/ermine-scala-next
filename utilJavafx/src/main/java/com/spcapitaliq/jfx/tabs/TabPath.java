package com.spcapitaliq.jfx.tabs;

import java.util.LinkedList;
import java.util.List;

import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.SplitPane;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.input.DataFormat;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXTraverser;
import com.spcapitaliq.jfx.tabs.FlexibleSplitAreaModel.DividerMarker;

/**
 * Describes a path from the root to a Tab. There will be 1+ path indexes to point to the location with
 * a {@link SplitPane}. There is also a dedicated tabIndex.
 * 
 * @author mmorton
 *
 */
public final class TabPath implements java.io.Serializable
{
  private static final Logger _log = Logger.getLogger(TabPath.class);
  
  public static final class TabPathBrokenException extends Exception
  {
    private TabPathBrokenException(TabPath path, String explanation)
    {
      super( "Broken path: " + path + " - " + explanation );
    }
  }
  
  public static final DataFormat DRAGGABLE_TAB_FORMAT = new DataFormat(TabPath.class.getName());
  
  private final int _tabIndex;
  private final List<Integer> _path;

  public TabPath(Tab tab)
  {
    TabPane tabs = tab.getTabPane();
    _tabIndex = tabs.getTabs().indexOf(tab);
    
    _path = new LinkedList<>();
    
    Parent trav = tabs.getParent();
    DividerMarker marker = null;
    while(trav != null)
    {
      if( trav instanceof DividerMarker )
      {
        marker = (DividerMarker)trav;
      }
      else if( trav instanceof FlexibleSplitArea )
      {
        if(marker == null)
          throw new UnsupportedOperationException("Missing a DividerMarker");
        FlexibleSplitArea area = (FlexibleSplitArea)trav;
        int index = area.peekSplitter().getItems().indexOf(marker);
        _path.add(0, Integer.valueOf(index) );
        
        marker = null;
      }
      trav = trav.getParent();
    }
    
    _log.trace("Constructed " + toString());
  }
  
  public int getTabIndex()
  {
    return _tabIndex;
  }
  
  /**
   * 
   * @param root
   * @return
   */
  public Tab walk(Node root) throws TabPathBrokenException
  {
    int i = 0;
    for(Integer splitterIndex : _path)
    {
      FlexibleSplitArea splitter = JFXTraverser.findFirst(root, FlexibleSplitArea.class);
      if(null == splitter)
      {
        throw new UnsupportedOperationException("splitter " + i + " is missing");
      }
      
      int si = splitterIndex.intValue();
      try
      {
        root = splitter.peekSplitter().getItems().get(si);
      }
      catch( IndexOutOfBoundsException ioobe )
      {
        throw new TabPathBrokenException(this, "splitter item " + si + " + is missing at splitter " + i);
      }
      
      ++i;
    }

    FlexibleTabArea tabs = JFXTraverser.findFirst(root, FlexibleTabArea.class);
    if(null == tabs)
    {
      throw new UnsupportedOperationException("tabs are missing");
    }
    
    try
    {
      return tabs.peekTabs().getTabs().get(_tabIndex);
    }
    catch( IndexOutOfBoundsException ioobe )
    {
      throw new TabPathBrokenException(this, "tab " + _tabIndex + " is missing");
    }
  }
  
  @Override
  public String toString()
  {
    StringBuilder out = new StringBuilder();
    for(Integer splitIndex : _path)
    {
      if(out.length() > 0)
        out.append('|');
      out.append(splitIndex);
    }
    out.append('[').append(_tabIndex).append(']');
    return out.toString();
  }
}
