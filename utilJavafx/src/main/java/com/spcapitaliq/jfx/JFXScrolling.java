package com.spcapitaliq.jfx;

import com.sun.javafx.scene.control.skin.VirtualFlow;
import javafx.application.Platform;
import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;
import javafx.event.EventHandler;
import javafx.geometry.Orientation;
import javafx.scene.Node;
import javafx.scene.control.ScrollBar;
import javafx.scene.control.TableView;
import javafx.scene.input.ScrollEvent;
import javafx.scene.web.WebView;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;

/**
 * Code to provide improved scrolling behavior where certain components will
 * consume scroll events and prevent a containing scrollpane from operating as
 * desired.
 *
 * @author mmorton
 *
 */
public class JFXScrolling
{
  private static final Logger Log = Logger.getLogger(JFXScrolling.class);

  private JFXScrolling()
  {
    /** static only */
  }

  private static class VerticalScrollbarTraverser extends JFXTraverser.InstanceOfStrategy<ScrollBar>
  {
    VerticalScrollbarTraverser()
    {
      super(ScrollBar.class);
    }

    @Override
    protected boolean isDirectHit(ScrollBar node)
    {
      return node.getOrientation() == Orientation.VERTICAL;
    }
  }

  /**
   * This trick instrument relies on the order of execution by which a scroll
   * event may or may not modify the value of the associated scrollbar. If the
   * scroll event causes the scrollbar to move, the changelistener will act
   * and disarm the event. This prevents the scroll event from being passed
   * to the parent. If the scrollbar does not move, then the event is passed
   * to the parent.
   * <p>
   * This is admittedly a hack, which could break if these assumptions are
   * broken. Still it works nicely now, so ship it!
   *
   * @author mmorton
   *
   */
  private static class Instrument
  {
    private boolean _armed = false;

    Instrument(final Node node, ScrollBar scrollBar)
    {
      scrollBar.valueProperty().addListener(new ChangeListener<Number>()
      {
        @Override
        public void changed(ObservableValue<? extends Number> arg0, Number oldVal, Number newVal)
        {
          Log.trace("Disarming");
          _armed = false;
        }
      });

      final EventHandler<? super ScrollEvent> onScroll = node.getOnScroll();
      node.setOnScroll(new EventHandler<ScrollEvent>()
      {
        @Override
        public void handle(final ScrollEvent se)
        {
          Log.trace("Arming");
          _armed = true;
          if(null != onScroll)
            onScroll.handle(se);
          Platform.runLater(new Runnable()
          {

            @Override
            public void run()
            {
              if (_armed)
              {
                Log.trace("Firing event to parent");
                node.getParent().fireEvent(se);
              }
              _armed = false;
            }
          });
        }
      });
    }
  }

  public static void instrument(final TableView<?> table)
  {
    class Bootstrap implements Runnable
    {
      @Override
      public void run()
      {
        final Node vf = JFXTraverser.breadthFirstSearch(table, new JFXTraverser.InstanceOfStrategy<Node>(
            VirtualFlow.class));
        if (null == vf)
        {
          Log.error("Failed to find VirtualFlow");
          return;
        }

        ScrollBar scrollBar = JFXTraverser.breadthFirstSearch(vf, new VerticalScrollbarTraverser());
        if (null == scrollBar)
        {
          Log.error("Failed to find ScrollBar");
          return;
        }

        new Instrument(vf, scrollBar);
      }
    }

    JFXUtil.setOnFirstSized(table, new Bootstrap());
  }

  public static void instrument(final WebView browser)
  {
    class Bootstrap implements Runnable
    {
      @Override
      public void run()
      {
        ScrollBar scrollBar = JFXTraverser.breadthFirstSearch(browser, new VerticalScrollbarTraverser());
        if (null == scrollBar)
        {
          Log.error("Failed to find ScrollBar");
          return;
        }

        new Instrument(browser, scrollBar);
      }
    }

    JFXUtil.setOnFirstSized(browser, new Bootstrap());
  }
}
