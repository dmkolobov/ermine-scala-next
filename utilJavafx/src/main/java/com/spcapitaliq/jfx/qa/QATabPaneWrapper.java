package com.spcapitaliq.jfx.qa;

import com.spcapitaliq.jfx.concurrency.RunLaterWaiter;
import javafx.scene.control.TabPane;

/**
 * 
 * @author mmorton
 *
 */
public class QATabPaneWrapper extends TabPane
{
  /**
   * Selects the desired tab in a thread safe manner.
   * @param index
   */
  public void qaSelectTab(final int index)
  {
    RunLaterWaiter.runLaterAndWait(new Runnable()
    {
      @Override
      public void run()
      {
        getSelectionModel().select(index);
      }
    });
  }
}
