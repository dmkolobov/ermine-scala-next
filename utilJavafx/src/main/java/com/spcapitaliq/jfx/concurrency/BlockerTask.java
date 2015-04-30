package com.spcapitaliq.jfx.concurrency;

import javafx.concurrent.Task;

/**
 *
 * @author mmorton
 *
 */
public abstract class BlockerTask<V> extends Task<V>
{
  final boolean allowCancel;
  final boolean doesCancelInterrupt;

  public BlockerTask()
  {
    this( false );
  }

  public BlockerTask( boolean allowCancel )
  {
    this( allowCancel, false );
  }

  public BlockerTask( boolean allowCancel, boolean doesCancelInterrupt )
  {
    this.allowCancel = allowCancel;
    this.doesCancelInterrupt = doesCancelInterrupt;
    updateMessage("Please wait...");
  }
}
