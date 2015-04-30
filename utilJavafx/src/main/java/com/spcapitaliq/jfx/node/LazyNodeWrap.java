package com.spcapitaliq.jfx.node;

import javafx.scene.Node;
import javafx.scene.control.TabPane;
import javafx.scene.layout.BorderPane;
import javafx.scene.text.Text;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;

/**
 *
 * @author mmorton
 *
 */
public final class LazyNodeWrap extends NodeWrap<BorderPane>
{
  private static final Logger _log = Logger.getLogger(LazyNodeWrap.class);

  public interface Provider
  {
    Node provideNode();
  }

  private final Provider _provider;
  private final BorderPane _area;

  public LazyNodeWrap( Provider provider )
  {
    _provider = provider;
    _area = new LazyBorderPane();
  }

  @Override
  protected BorderPane buildNode()
  {
    return _area;
  }

  private class LazyBorderPane extends BorderPane
  {
    private boolean _reactive = true;

    public void react()
    {
      if( _reactive )
      {
        _log.debug("Reacting: " + this);
        JFXUtil.runSafe(new Runnable() {
          @Override
          public void run()
          {
            Node node;
            try
            {
              node = _provider.provideNode();
              _area.setCenter(node);
            }
            catch( Exception e )
            {
              _log.error("Failed to provideNode", e);
              _area.setCenter( new Text("Error"));
            }
          }
        });
        _reactive = false;
      }
    }
  }

  public static void react( Node parent )
  {
    class Traverser extends NodeTraverser.AbstractStrategy
    {
      @Override
      public boolean isActionable(Node node)
      {
        return node instanceof LazyBorderPane || node instanceof TabPane;
      }

      @Override
      public void apply(Node node)
      {
        if( node instanceof LazyBorderPane )
          ((LazyBorderPane)node).react();
        else if( node instanceof TabPane )
          react( ((TabPane)node).getTabs().get(0).getContent() );
      }
    }
    NodeTraverser.traverse(parent, new Traverser());
  }
}
