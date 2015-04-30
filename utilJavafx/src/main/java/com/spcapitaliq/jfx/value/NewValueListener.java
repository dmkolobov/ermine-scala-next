package com.spcapitaliq.jfx.value;

import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;

/**
 * Convenience class that only deals with the new value argument of {@link ChangeListener}.
 * @author mmorton
 *
 */
public abstract class NewValueListener<T> implements ChangeListener<T>
{

  @Override
  public final void changed(ObservableValue<? extends T> value, T oldVal, T newVal)
  {
    changed(newVal);
  }

  protected abstract void changed(T newVal);
}
