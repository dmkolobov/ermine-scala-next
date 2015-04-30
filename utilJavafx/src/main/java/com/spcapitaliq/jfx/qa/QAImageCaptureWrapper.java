package com.spcapitaliq.jfx.qa;

import com.spcapitaliq.jfx.JFXClipboard;
import com.spcapitaliq.jfx.JFXTraverser;
import javafx.scene.Node;
import javafx.scene.layout.BorderPane;

/**
 * Used to wrap an arbitrary node and give it nearest text
 * and image to clipboard capture facilities. 
 * 
 * @author mmorton
 *
 */
public class QAImageCaptureWrapper extends BorderPane
{
  public QAImageCaptureWrapper(Node node)
  {
    setCenter(node);
  }
  
  public void qaCopyAsImageToClipboard()
  {
    JFXClipboard.copyNodeToClipboardAsImage(this);
  }
  
  public String qaFindNearbyText()
  {
    return JFXTraverser.findNearbyText(this);
  }
}
