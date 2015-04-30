package com.spcapitaliq.jfx.action;

import javafx.event.ActionEvent;
import javafx.scene.Node;

import com.spcapitaliq.jfx.JFXClipboard;

/**
 *
 * @author mmorton
 *
 */
public class CopyImageAction extends AbstractJFXAction<Node>
{
  @Override
  protected void handle(ActionEvent ae, Node node)
  {
    JFXClipboard.copyNodeToClipboardAsImage(node);
  }

  @Override
  protected String defineActionText()
  {
    return "Copy as Image";
  }
}
