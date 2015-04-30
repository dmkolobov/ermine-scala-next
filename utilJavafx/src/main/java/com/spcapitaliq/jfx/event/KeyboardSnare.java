package com.spcapitaliq.jfx.event;

import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.input.KeyEvent;
import javafx.scene.input.MouseEvent;
import org.apache.log4j.Logger;

/**
 * Use as the parent of a Node to capture keyboard
 * focus when clicked.
 *
 * @author Mat
 *
 */
public class KeyboardSnare extends Button
{
  private static final Logger Log = Logger.getLogger(KeyboardSnare.class);

  public KeyboardSnare(Node content)
  {
    super(null, content);

    setStyle("-fx-padding: 0 0 0 0; -fx-background-color: transparent");

//    EventHandler<MouseEvent> clicker = new EventHandler<MouseEvent>()
//    {
//
//      @Override
//      public void handle(MouseEvent arg0)
//      {
//        Log.info("click");
////        Log.info("\nFocus owner: " + chart.getScene().getFocusOwner());
////        stack.requestFocus();
////        Log.info("Focus owner: " + chart.getScene().getFocusOwner());
////        button.requestFocus();
////        Log.info("Focus owner: " + chart.getScene().getFocusOwner());
//        requestFocus();
//
//      }
//    };
//    setOnMousePressed(clicker);
//
//    EventHandler<KeyEvent> typer = new EventHandler<KeyEvent>()
//    {
//      @Override
//      public void handle(KeyEvent ke)
//      {
//        Log.info("snare: " + ke);
//      }
//    };
//    setOnKeyPressed(typer);
  }
}