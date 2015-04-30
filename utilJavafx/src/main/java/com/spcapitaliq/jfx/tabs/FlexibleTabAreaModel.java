package com.spcapitaliq.jfx.tabs;

import java.util.LinkedList;
import java.util.List;

import com.sun.javafx.scene.control.skin.TabDragAndDropHelper;
import javafx.collections.ObservableList;
import javafx.scene.control.Tab;
import javafx.scene.control.TabBuilder;
import javafx.scene.control.TabPane;

import com.spcapitaliq.jfx.node.NodeWrap;

/**
 * Bean that stores all persistent state for a {@link FlexibleTabArea}
 * 
 * @author mmorton
 *
 */
public final class FlexibleTabAreaModel
{
  private List<String> _tabNames;
  private List<NodeWrap<?>> _nodes;

  public FlexibleTabAreaModel()
  {
    _tabNames = new LinkedList<>();
    _nodes = new LinkedList<>();
  }

  public void addTab(String name, NodeWrap<?> content)
  {
    _tabNames.add(name);
    _nodes.add(content);
  }
 
  @Deprecated
  public List<NodeWrap<?>> getNodes()
  {
    return _nodes;
  }

  @Deprecated
  public void setNodes(List<NodeWrap<?>> nodes)
  {
    _nodes = nodes;
  }
  
  @Deprecated
  public List<String> getTabNames()
  {
    return _tabNames;
  }

  @Deprecated
  public void setTabNames(List<String> tabNames)
  {
    _tabNames = tabNames;
  }

  void bind(FlexibleTabArea area)
  {
    TabPane tabPane = area.peekTabs();
    ObservableList<Tab> tabs = tabPane.getTabs();
    int numTabs = _tabNames.size();
    for(int i = 0; i < numTabs; i++)
    {
      Tab tab = TabBuilder.create()
          .text(_tabNames.get(i))
          .content(_nodes.get(i).peekNode())
          .build();
      
      tabs.add(tab);
    }
    TabDragAndDropHelper.configure(tabPane);
  }
}
