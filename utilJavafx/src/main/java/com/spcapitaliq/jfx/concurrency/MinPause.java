package com.spcapitaliq.jfx.concurrency;

import com.spcapitaliq.jfx.JFXUtil;

/**
 *
 * @author mmorton
 *
 */
public class MinPause
{
  private long _referenceTime;
  private final long _minPause;

  public MinPause( long minPause )
  {
    reset();
    _minPause = minPause;
  }

  private void reset()
  {
    _referenceTime = System.currentTimeMillis();
  }

  public void conclude()
  {
    JFXUtil.provideMinimumPause( _referenceTime, _minPause );
    reset();
  }

  public static MinPause quick()
  {
    return new MinPause( 1500 );
  }
}
