package com.spcapitaliq.jfx.window;

import java.awt.event.*;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

import javax.swing.SwingUtilities;

import javafx.application.Platform;
import javafx.embed.swing.JFXPanel;
import javafx.stage.PopupWindow;
import javafx.stage.Window;
import org.apache.log4j.Logger;

/**
 * Hack methods to force JavaFX windows to dispose when necessary. This is
 * needed due to bugs in JFX 2.2 and JFXPanel.
 * 
 * This should be removed when a future version of JFX is used that doesn't have
 * this vulnerability.
 * 
 * @author mmorton
 * 
 */
public class PopupHammer
{
  private static final Logger Log = Logger.getLogger(PopupHammer.class);
  
  private static boolean _initFx;

  private PopupHammer()
  {
    /** static only */
  }

  public static void addPopupHammer(final JFXPanel jfxPanel)
  {
    java.awt.Window win = SwingUtilities.windowForComponent(jfxPanel);
    if (null != win)
    {
      win.addComponentListener(new ComponentAdapter()
      {
        @Override
        public void componentMoved(ComponentEvent e)
        {
          hide();
        }
      });
    }
    else
      Log.warn("No containing window found for: " + jfxPanel);
      

    jfxPanel.addFocusListener(new FocusAdapter()
    {
      @Override
      public void focusLost(FocusEvent e)
      {
        hide();
      }
    });
  }

  private static void hide()
  {
    if (!_initFx)
    {
      // this will initialize JavaFX
      new JFXPanel();
      _initFx = true;
    }

    Platform.runLater(new Runnable()
    {
      @Override
      public void run()
      {
        final Set<Window> toHide = new HashSet<>();
        // Deprecated, but there is no other way to get JavaFX windows
        for (@SuppressWarnings("deprecation")
             Iterator<Window> it = javafx.stage.Window.impl_getWindows();
             it.hasNext();)
        {
          final Window window = it.next();
          if (window instanceof PopupWindow)
          {
            toHide.add(window);
          }
        }

        for (Window window : toHide)
        {
          window.hide();
        }
      }
    });
  }
}
