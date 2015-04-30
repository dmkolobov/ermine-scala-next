package com.spcapitaliq.jfx.value;

import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;
import org.apache.log4j.Logger;

/**
 *
 * @author mmorton
 *
 */
public class PropertyDebugger<T> implements ChangeListener<T>
{
  private final String _name;
  private Logger _log;

  public PropertyDebugger(String name, ObservableValue<T> val)
  {
    this(name, val, Logger.getLogger(PropertyDebugger.class));
  }

  public PropertyDebugger(String name, ObservableValue<T> val, Logger log)
  {
    _name = name;
    _log = log;
    val.addListener(this);
  }

  @Override
  public final void changed(ObservableValue<? extends T> val, T oldVal, T newVal)
  {
    recognizeChange(newVal, _name, _log);
  }

  protected void recognizeChange(T newVal, String name, Logger log)
  {
    log.debug(name + " value changed: " + newVal);
  }
}
