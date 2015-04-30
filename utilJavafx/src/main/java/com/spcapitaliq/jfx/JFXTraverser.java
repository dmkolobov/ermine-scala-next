package com.spcapitaliq.jfx;

import java.util.LinkedList;

import javafx.collections.ObservableList;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.ButtonBase;
import javafx.scene.control.TableView;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.layout.BorderPane;
import javafx.scene.text.Text;
import org.apache.log4j.Logger;

import scala.Option;
import static scalaz.std.option.some;
import static scalaz.std.option.none;

/**
 * Provides code for recursively applying a strategy for
 * to a Parent's descendents.
 *
 * Also has code for applying a strategy up the parent chain.
 *
 * @author mmorton
 *
 */
public final class JFXTraverser
{
  private static final Logger Log = Logger.getLogger(JFXTraverser.Strategy.class);

  public interface Strategy<A>
  {
    Option<A> apply(Node node);
  }

  public static class InstanceOfStrategy<C extends Node> implements Strategy<C>
  {
    private final Class<C> _clazz;

    public InstanceOfStrategy(Class<C> clazz)
    {
      _clazz = clazz;
    }

    protected boolean isDirectHit(C node)
    {
      return true;
    }

    @SuppressWarnings("unchecked")
    public Option<C> apply(Node node)
    {
      if (_clazz.isAssignableFrom(node.getClass()) && isDirectHit((C) node))
      {
        return some((C) node);
      }
      else
      {
        return none();
      }
    }
  }

  public static <N extends Node> N findFirst(Node node, Class<N> clazz)
  {
    return breadthFirstSearch(node, new InstanceOfStrategy<>(clazz));
  }

  public static <N> N breadthFirstSearch(final Node node, final Strategy<N> strategy)
  {
    LinkedList<Node> queue = new LinkedList<Node>();
    queue.add(node);

    while(!queue.isEmpty())
    {
      Node trav = queue.pollFirst();
      Log.trace("Traversing: " + trav.getClass().getSimpleName());
      Option<N> hit = strategy.apply(trav);
      if( hit.isDefined() )
        return hit.get();
      if( trav instanceof Parent )
      {
        queue.addAll(((Parent)trav).getChildrenUnmodifiable());
      }
    }

    return null;
  }

  public static <N> N ancestorSearch(final Node node, final Strategy<N> strategy)
  {
    if(null == node)
      return null;

    Option<N> hit = strategy.apply(node);
    if( hit.isDefined() )
      return hit.get();

    return ancestorSearch(node.getParent(), strategy);
  }

  /**
   * Scans the scene graph to look for the nearest text.
   *
   * @param reference
   * @return nearby text or <tt>null</tt> if none found.
   */
  public static String findNearbyText(Node reference)
  {
    Parent parent = reference.getParent();
    if(null == parent)
      return null;

    if(parent instanceof BorderPane)
    {
      BorderPane bp = (BorderPane)parent;
      Node left = bp.getLeft();
      if(left != null && left != reference)
      {
        String result = diveForText(left);
        if(null != result)
        {
          return captureToClipboard(result);
        }
      }
      Node top = bp.getTop();
      if(top != null && top != reference )
      {
        String result = diveForText(top);
        if(null != result)
        {
          return captureToClipboard(result);
        }
      }
    }
    else
    {

      ObservableList<Node> chitlins = parent.getChildrenUnmodifiable();
      int index = chitlins.indexOf(reference);
      for(int i = 0; i < index; i++ )
      {
        Node child = chitlins.get(i);
        String result = diveForText(child);
        if(null != result)
        {
          return captureToClipboard(result);
        }
      }
    }

    return findNearbyText(parent);
  }

  private static String captureToClipboard(String result)
  {
    ClipboardContent content = new ClipboardContent();
    content.putString(result);
    Clipboard.getSystemClipboard().setContent(content);
    return result;
  }

  private static final Class<?>[] EXCLUDE = { TableView.class, ButtonBase.class };


  /**
   * Depth first search for a text node.
   *
   * @param reference
   * @return the text of the node or <tt>null</tt> if none found
   */
  public static String diveForText(Node reference)
  {
    if(!reference.isVisible())
      return null;

    Class<?> refClazz = reference.getClass();
    for(Class<?> clazz : EXCLUDE)
      if(clazz.isAssignableFrom(refClazz))
        return null;

    if( reference instanceof Text)
    {
      String text = ((Text)reference).getText();
      Log.info("Found text '" + text + "' in: " + JFXDebug.formatPath(reference));
      return text;
    }

    if(reference instanceof Parent)
    {
      for(Node child : ((Parent)reference).getChildrenUnmodifiable())
      {
        String result = diveForText(child);
        if(null != result)
          return result;
      }
    }

    return null;
  }

  public static <N extends Node> N findFirstAncestor(Node node, Class<N> clazz)
  {
    return ancestorSearch(node, new InstanceOfStrategy<>(clazz));
  }

  public static class StyleStrategy implements Strategy<Node>
  {
    private final String _style;

    public StyleStrategy(String style)
    {
      JFXUtil.throwIfNull(style, "style");
      _style = style;
    }

    @Override
    public Option<Node> apply(Node node)
    {
      if(_style.equals(node.getStyleClass().toString()) )
        return some(node);
      return none();
    }
  }

  public static Node findFirstWithStyle(Node node, String style)
  {
    return breadthFirstSearch(node, new StyleStrategy(style));
  }
}