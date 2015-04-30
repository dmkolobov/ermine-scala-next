package com.spcapitaliq.jfx.qa;

import com.spcapitaliq.jfx.JFXTraverser;
import javafx.scene.control.ComboBox;

/**
 * 
 * @author mmorton
 *
 * @param <T>
 */
public class QAComboBoxWrapper<T> extends ComboBox<T>
{
  public String qaFindNearbyText()
  {
    return JFXTraverser.findNearbyText(this);
  }
}
