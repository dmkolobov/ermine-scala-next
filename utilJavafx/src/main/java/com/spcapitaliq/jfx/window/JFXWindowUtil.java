package com.spcapitaliq.jfx.window;

import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.stage.Stage;
import javafx.stage.Window;
import javafx.stage.WindowEvent;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXSafe;
import com.spcapitaliq.jfx.JFXUtil;

/**
 *
 * @author mmorton
 *
 */
public class JFXWindowUtil
{
  private static final Logger _log = Logger.getLogger(JFXWindowUtil.class);

  private JFXWindowUtil() { /** static only */ }

  public static void centerOver(final Node anchor, final Window window)
  {
    setOnShown(window, new Runnable() {

      @Override
      public void run()
      {
        Window anchorWin = anchor.getScene().getWindow();

        window.setX(anchorWin.getX() + (anchorWin.getWidth() - window.getWidth()) / 2);
        window.setY(anchorWin.getY() + (anchorWin.getHeight() - window.getHeight()) / 2);
      }
    });
  }

  public static void setOnShowing(final Window window, final Runnable logic)
  {
    window.setOnShowing(new EventHandler<WindowEvent>()
    {
      @Override
      public void handle(WindowEvent we)
      {
        try
        {
          logic.run();
        }
        catch(Exception e )
        {
          _log.error("Failed to run setOnShown logic: " + logic, e);
        }

        /** remove the listener b/c it's only used once */
        window.setOnShowing(null);
      }
    });
  }

  public static void setOnShown(final Window window, final Runnable logic)
  {
    window.setOnShown(new EventHandler<WindowEvent>()
    {
      @Override
      public void handle(WindowEvent we)
      {
        try
        {
          logic.run();
        }
        catch(Exception e )
        {
          _log.error("Failed to run setOnShown logic: " + logic, e);
        }

        /** remove the listener b/c it's only used once */
        window.setOnShown(null);
      }
    });
  }

  @JFXSafe
  public static void toFront(final Node node)
  {
    JFXUtil.runSafe(new Runnable()
    {
      @Override
      public void run()
      {
        try
        {
          ((Stage)node.getScene().getWindow()).toFront();
        }
        catch (Exception e)
        {
          _log.error("Failed toFront on node: " + node, e);
        }
      }
    });
  }
}
