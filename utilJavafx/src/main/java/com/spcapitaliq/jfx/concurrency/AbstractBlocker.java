package com.spcapitaliq.jfx.concurrency;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;
import javafx.concurrent.Worker;
import javafx.concurrent.Worker.State;

/**
 *
 * @author mmorton
 *
 */
public abstract class AbstractBlocker
{
  public static abstract class SimpleStateWatcher implements ChangeListener<Worker.State>
  {
    @Override
    public void changed( ObservableValue<? extends State> observable, State oldValue, State newValue )
    {
      switch( newValue )
      {
      case READY:
      case RUNNING: break;
      case SCHEDULED: started(); break;
      case SUCCEEDED:
      case FAILED:
      case CANCELLED: stopped( newValue ); break;
      }
    }

    protected abstract void started();

    protected abstract void stopped(State state);
  }

  private final ExecutorService _executor;

  public AbstractBlocker()
  {
    this(null);
  }

  public AbstractBlocker(ExecutorService executor)
  {
    _executor = null != executor ? executor : Executors.newSingleThreadExecutor();
  }

  protected abstract ChangeListener<Worker.State> buildStateWatcher(BlockerTask<?> worker);

  protected final void submit(BlockerTask<?> worker)
  {
    worker.stateProperty().addListener(buildStateWatcher(worker));
    _executor.submit(worker);
  }
}
