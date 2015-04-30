package com.spcapitaliq.jfx.node;

import javafx.scene.Node;
import javafx.scene.Parent;

import com.spcapitaliq.jfx.JFXUtil;

/**
 * Depth first traversal of a scenegraph that applies
 * a strategy to the appropriate Nodes encountered.
 *
 * @author mmorton
 *
 */
public final class NodeTraverser
{
  public interface Strategy
  {
    boolean isActionable( Node node );

    void apply( Node node );
  }

  public static abstract class AbstractStrategy implements Strategy
  {
    public final void traverse( Node node )
    {
      NodeTraverser.traverse(node, this);
    }
  }

  public static abstract class NaiveStrategy extends AbstractStrategy
  {
    @Override
    public final boolean isActionable(Node node)
    {
      return true;
    }
  }

  public static abstract class HasInstanceStrategy<C extends Node> extends AbstractStrategy
  {
    private final Class<C> _clazz;

    public HasInstanceStrategy( Class<C> clazz )
    {
      _clazz = clazz;
    }

    @Override
    public final boolean isActionable(Node node)
    {
      if( null == node )
        return false;
      return _clazz.isAssignableFrom(node.getClass());
    }

    @Override
    public final void apply( Node node )
    {
      @SuppressWarnings("unchecked")
      C castNode = (C)node;
      applyInstance(castNode);
    }

    protected abstract void applyInstance( C node );
  }

  private NodeTraverser()
  {
    /** static only */
  }

  public static void traverse( Node node, Strategy strategy )
  {
    JFXUtil.throwIfNotApplicationThread();

    if( node instanceof Parent )
    {
      for( Node child : ((Parent)node).getChildrenUnmodifiable())
      {
        traverse( child, strategy );
      }
    }

    if( strategy.isActionable(node) )
    {
      strategy.apply(node);
    }
  }
}
