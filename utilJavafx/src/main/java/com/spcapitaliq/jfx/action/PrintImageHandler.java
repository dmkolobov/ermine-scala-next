package com.spcapitaliq.jfx.action;

import javafx.event.ActionEvent;
import javafx.scene.Node;

/**
 * Implementer must service a request to print a given Node as an image.
 * @author mmorton
 */
public interface PrintImageHandler
{
  void handlePrint(ActionEvent ae, Node node);
}
