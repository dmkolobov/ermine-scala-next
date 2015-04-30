package com.spcapitaliq.jfx;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;
import javafx.collections.ObservableMap;
import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.geometry.Bounds;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.scene.text.Text;
import org.apache.log4j.Logger;

/**
 * Static methods and classes used to debug JavaFX.
 *
 * @author mmorton
 *
 */
public class JFXDebug
{
  private static final Logger Log = Logger.getLogger(JFXDebug.class);

  private static final int TAB = 2;

  private JFXDebug() { /** static only */ }

  /**
   * Convenience method that calls {{@link #formatStructure(StringBuilder, Input, int)}
   * with its own self-contained {@link StringBuilder}.
   *
   * @param input
   * @return
   */
  public static String formatStructure( Node input )
  {
    StringBuilder msg = new StringBuilder("Debugging: " + input + '\n' );
    formatStructure( msg, input, 0);
    return msg.toString();
  }

  /**
   * Displays the simple name of the class of the given {@link Input} along with its
   * memory address/pointer (via {@link System#identityHashCode(Object)}). If the
   * {@link Input} is a transform (implements {@link HasInputs} this method will be
   * recursively called on those children.
   *
   * @param msg where to output the info
   * @param input what to format
   * @param level used to indent children
   */
  public static void formatStructure( StringBuilder msg, Node input, int level )
  {
    formatStructure(msg, null, input, level);
  }

  public static void formatStructure( StringBuilder msg, String prefix, Node input, int level )
  {
    boolean traceEnabled = Log.isTraceEnabled();
    if( !traceEnabled && input instanceof Skin<?> )
      return;
    if( !traceEnabled && !input.isVisible() )
      return;

    if( null != input )
    {
      insetForLevel(msg, level);
      if( null != prefix)
        msg.append(prefix);
      Class<? extends Node> clazz = input.getClass();
      msg.append( traceEnabled ? clazz.getName() : clazz.getSimpleName() );
      if( input instanceof Button )
        msg.append(": " + ((Button)input).getText());
      else if( input instanceof TextInputControl )
        msg.append(": " + ((TextInputControl)input).getText());
      else if( input instanceof Labeled )
        msg.append(": " + ((Labeled)input).getText());
      else if( input instanceof Text )
        msg.append(": " + ((Text)input).getText());
      else if( input instanceof TabPane)
        msg.append(": " + ((TabPane)input).getSelectionModel().getSelectedItem().getText());
      Bounds layoutBounds = input.getLayoutBounds();
      msg.append(" (").append((int)layoutBounds.getWidth()).append('x').append((int)layoutBounds.getHeight()).append(')');
      msg.append(" prefH: " ).append((int)input.prefHeight(-1));
      formatNodeProperties(msg, input);

      if( traceEnabled )
      {
        msg.append('@').append(System.identityHashCode(input));
        msg.append(" Style: ").append(input.getStyleClass());
      }
    }
    else
      msg.append("null");
    msg.append('\n');

    @SuppressWarnings("unchecked")
    NodeFormatStrategy<Node> strategy =
      (NodeFormatStrategy<Node>) _formatStrategies.get(input.getClass());
    if( null != strategy )
    {
      strategy.format(msg, input, level);
    }
    else if( input instanceof Parent )
    {
      DefaultParentNodeFormat.format(msg, (Parent)input, level);
    }
  }

  private static void formatNodeProperties( StringBuilder msg, Node input )
  {
    ObservableMap<Object, Object> properties = input.getProperties();
    formatNodeProperty(msg, properties, "vbox-vgrow");
    formatNodeProperty(msg, properties, "hbox-hgrow");
  }

  private static void formatNodeProperty( StringBuilder msg, ObservableMap<Object, Object> properties, String name )
  {
    Priority val = (Priority) properties.get(name);
    if( null != val )
      msg.append( ' ' ).append(name).append(": ").append(val);
  }

  private static void insetForLevel( StringBuilder msg, int level )
  {
    for( int i = level * TAB; i-->0; )
      msg.append(' ');
    if( level < 10 )
      msg.append(' ');
    msg.append(level).append(") ");
  }

  protected static final void formatChildren( StringBuilder msg, List<Node> children, int level )
  {
    level++;
    for( Node child : children )
    {
      formatStructure(msg, child,level);
    }
  }

  private static interface NodeFormatStrategy<N extends Node>
  {
    void format(StringBuilder msg, N node, int level);
  }

  private static NodeFormatStrategy<Parent> DefaultParentNodeFormat = new NodeFormatStrategy<Parent>()
  {
    @Override
    public void format(StringBuilder msg, Parent node, int level)
    {
      formatChildren(msg, node.getChildrenUnmodifiable(), level);
    }
  };

  private static NodeFormatStrategy<Node> NoopNodeFormat = new NodeFormatStrategy<Node>()
  {
    @Override
    public void format(StringBuilder msg, Node node, int level)
    {
      /** noop */
    }
  };

  private static Map<Class<? extends Node>, NodeFormatStrategy<?>> _formatStrategies = new HashMap<Class<? extends Node>, NodeFormatStrategy<?>>();

  static {
    _formatStrategies.put(TableView.class, NoopNodeFormat);
    _formatStrategies.put(TabPane.class, new NodeFormatStrategy<TabPane>()
    {
      @Override
      public void format(StringBuilder msg, TabPane node, int level)
      {
        Tab tab = node.getSelectionModel().getSelectedItem();
        level++;
        formatStructure(msg, tab.getContent(), level);
      }
    });
    _formatStrategies.put(BorderPane.class, new NodeFormatStrategy<BorderPane>()
    {
      private void format(StringBuilder msg, String prefix, Node child, int level)
      {
        if( null != child )
          formatStructure(msg, prefix + ": ", child, level);
      }

      @Override
      public void format(StringBuilder msg, BorderPane node, int level)
      {
        level++;

        format(msg, "top", node.getTop(), level);
        format(msg, "right", node.getRight(), level);
        format(msg, "bottom", node.getBottom(), level);
        format(msg, "left", node.getLeft(), level);
        format(msg, "center", node.getCenter(), level);
      }
    });
  }

  public static Parent overlayDebugTools( final Node content )
  {
    Button button = ButtonBuilder.create()
        .text("?")
        .tooltip(new Tooltip("debug node structure"))
        .opacity(.5)
        .onAction(new EventHandler<ActionEvent>()
        {
          @Override
          public void handle(ActionEvent ae)
          {
            Log.info("Node Structure:\n" + formatStructure(content));
          }
        })
        .build();
    StackPane.setAlignment(button, Pos.BOTTOM_LEFT);

    return StackPaneBuilder.create()
        .children(content, button)
        .build();
  }

  /**
   * Returns a string that represents the path to the node in the scene by
   * traversing up the parent chain.
   *
   * @param node
   * @return
   */
  public static String formatPath(Node node)
  {
    StringBuilder path = new StringBuilder("Node path: ");
    formatPathHelper(node, path);
    return path.toString();
  }

  private static void formatPathHelper(Node node, StringBuilder path)
  {
    Parent parent = node.getParent();
    if(null != parent)
    {
      formatPathHelper(parent, path);
    }
    path.append("->").append(node.getClass().getSimpleName());
  }

  public static Node inspect(Node node)
  {
    Log.debug("Inspecting node: " + node);
    return node;
  }

  public static Node watch(final Node node)
  {
    if(node instanceof Region)
    {
      Region parent = (Region)node;
      parent.needsLayoutProperty().addListener(new ChangeListener<Boolean>()
      {
        @Override
        public void changed(final ObservableValue<? extends Boolean> observableValue, final Boolean pre, final Boolean post)
        {
          Log.debug("Node: " + node + " needsLayout: " + post + "\n" +formatStructure(node));
        }
      });

      parent.prefWidthProperty().addListener(new ChangeListener<Number>()
      {
        @Override
        public void changed(final ObservableValue<? extends Number> observableValue, final Number pre, final Number post)
        {
          Log.debug("Node: " + node + " prefWidth: " + post);
        }
      });
    }

    return node;
  }
}
