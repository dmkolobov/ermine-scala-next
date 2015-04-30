package com.spcapitaliq.jfx.node;

import java.util.*;
import java.util.Map.Entry;

import javafx.scene.Node;

import org.apache.log4j.Logger;

/**
 * Allows collection of nodes for a later operation.
 */
public class NodePostOp
{
  private static final Logger Log = Logger.getLogger(NodePostOp.class);

  public interface Strategy
  {
    void applyPostOp( Node node );
  }

  private final IdentityHashMap<Node, Collection<Strategy>> _strategies;

  public NodePostOp()
  {
    _strategies = new IdentityHashMap<>();
  }

  public void collect(Node node, Strategy strategy)
  {
    Collection<Strategy> strategies = _strategies.get(node);
    if(null == strategies)
    {
      strategies = new LinkedList<>();
      _strategies.put(node, strategies);
    }

    strategies.add(strategy);
  }

  public void complete()
  {
    for(Entry<Node, Collection<Strategy>> strategies : _strategies.entrySet())
    {
      Node node = strategies.getKey();
      for(Strategy strategy : strategies.getValue())
      {
        try
        {
          strategy.applyPostOp(node);
        }
        catch(Exception e)
        {
          Log.error("Failed to apply strategy: " + strategy + " on node: " +  node);
        }
      }
    }
  }
}
