package com.spcapitaliq.jfx.node;

import java.util.ArrayList;
import java.util.List;

import javafx.scene.Node;
import javafx.scene.control.Tab;
import javafx.scene.control.TabBuilder;

/**
 * Wraps an actual {@link Node}, building it on demand at runtime.
 *
 * @author mmorton
 *
 */
public abstract class NodeWrap<N extends Node>
{
  private N _node;

  /**
   * @return the wrapped Node, building it if necessary.
   */
  public final synchronized N peekNode()
  {
    if( null == _node )
      _node = buildNode();
    return _node;
  }

  /**
   * Convenience method to build nodes.
   * @param wraps
   * @return
   */
  public static List<Tab> buildTabs( NodeWrap<?>... wraps )
  {
    List<Tab> tabs = new ArrayList<Tab>( wraps.length );
    for( NodeWrap<?> wrap : wraps )
      tabs.add( TabBuilder.create()
        .text(wrap.defineName())
        .content(wrap.peekNode())
        .build() );
    return tabs;
  }

  protected String defineName()
  {
    return getClass().getSimpleName();
  }

  /**
   * Subclass must actually build the {@link Node} to be wrapped.
   * @return
   */
  protected abstract N buildNode();
}
