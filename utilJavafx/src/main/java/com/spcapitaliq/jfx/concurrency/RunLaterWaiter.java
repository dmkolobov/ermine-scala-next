package com.spcapitaliq.jfx.concurrency;

import com.spcapitaliq.jfx.JFXUtil;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.control.Tooltip;
import org.apache.log4j.Logger;

/**
 * Threading logic for a calling thread to wait until a provided
 * {@link Runnable} executes on the JavaFX Thread.
 * 
 * @author mmorton
 */
public final class RunLaterWaiter
{
  private static final Logger Log = Logger.getLogger(RunLaterWaiter.class);
  
  private RunLaterWaiter() {}
  
  public static void runLaterAndWait(Runnable logic)
  {
    if( Platform.isFxApplicationThread() )
      logic.run();
    else
    {
      new RunLaterWaiter().go(logic);
    }
  }
  
  private void go(final Runnable logic)
  {
    class LogicWrapper implements Runnable
    {
      @Override
      public void run()
      {
        try
        {
          logic.run();
        }
        catch(Throwable t)
        {
          Log.error("Failed to run logic: " + logic, t);
        }
        done();
      }
    }
    
    synchronized(this)
    {
      Platform.runLater(new LogicWrapper());
      try
      {
        Log.debug("Waiting...");
        wait();
      }
      catch (InterruptedException ie)
      {
        Log.warn("Interrupted", ie);
      }
    }
    Log.debug("... done.");
  }
  
  private void done()
  {
    synchronized(this)
    {
      notifyAll();
    }
  }

  /**
   * Tooltip assignment requires the JavaFX event thread.
   *
   * @param node
   * @param tooltip
   */
  public static void applyTooltip(final Node node, final String tooltip)
  {
    Runnable logic = new Runnable()
    {
      @Override
      public void run()
      {
        Tooltip.install(node, new Tooltip(tooltip));
      }
    };
    if(null != node.getScene())
      runLaterAndWait(logic);
    else
      JFXUtil.setOnFirstSized(node, logic);
  }
}
