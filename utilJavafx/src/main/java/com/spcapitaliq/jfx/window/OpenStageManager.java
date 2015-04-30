package com.spcapitaliq.jfx.window;

import java.awt.DisplayMode;
import java.awt.GraphicsEnvironment;
import java.util.HashMap;
import java.util.Map;

import javafx.application.Platform;
import javafx.event.EventHandler;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.BorderPaneBuilder;
import javafx.stage.Stage;
import javafx.stage.WindowEvent;

import scala.Option;
import scala.Function0;
import scala.Some;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXAppLifecycle;
import com.spcapitaliq.jfx.image.JFXImageUtil;

/**
 * Manages stages by identifier and if a particular identifier is requested it
 * will be brought to front instead of being created anew.
 *
 * @mmorton
 */
public final class OpenStageManager<K>
{
  private static final Logger _log = Logger.getLogger(OpenStageManager.class);

  public interface StageFulfillment
  {
    /**
     * Take the appropriate action to launch the stage. Make sure NOT to block
     * this method. Use another thread instead.
     *
     * @param callback
     */
    void launchStage(FullfillmentCallback callback);
  }

  public interface FullfillmentCallback
  {
    void recognizeLaunch(Stage stage, Option<Runnable> cleanup);
  }

  private class Receiver implements FullfillmentCallback
  {
    private K _key;

    Receiver(K key)
    {
      _key = key;
    }

    @Override
    public void recognizeLaunch(final Stage stage, final Option<Runnable> cleanup)
    {
      synchronized( _openStages )
      {
        _openStages.put(_key, new Some<Stage>(stage));
      }
      stage.setOnHidden(new EventHandler<WindowEvent>()
      {
        @Override
        public void handle(WindowEvent we)
        {
          onStageHidden(cleanup);
        }
      });
    }

    private void onStageHidden(Option<Runnable> cleanup)
    {
      if(null != _openStages.remove(_key))
        _log.debug("Removed " + _key + " from open stages");
      else
        _log.warn("Failed to remove " + _key + " from open stages");

      try
      {
        if(cleanup.isDefined())
          cleanup.get().run();
      }
      catch(Exception e)
      {
        _log.error("Failed to cleanup: " + cleanup, e);
      }
    }
  }

  private final Map<K, Option<Stage>> _openStages;

  public OpenStageManager()
  {
    _openStages = new HashMap<K, Option<Stage>>();
  }

  public void demand(final K key, final StageFulfillment fulfillment)
  {
    synchronized (_openStages)
    {
      final Option<Stage> stage = _openStages.get(key);
      if (null == stage)
      {
        // put a placeholder value until the actual stage is available
        // to prevent multiple requests
        _openStages.put(key, Option.<Stage>apply(null));

        try
        {
          fulfillment.launchStage(new Receiver(key));
        }
        catch (Throwable t)
        {
          _log.error("Failed to fulfill demand", t);
        }
      }
      else if (stage.isDefined())
      {
        _log.debug("Requesting pre-existing stage");
        Platform.runLater(new Runnable()
        {
          @Override
          public void run()
          {
            stage.get().toFront();
          }
        });
      }
      else
      {
        /** noop - wait for the originally established stage */
        _log.debug("Waiting for originally requested stage to be established");
      }
    }
  }
}
