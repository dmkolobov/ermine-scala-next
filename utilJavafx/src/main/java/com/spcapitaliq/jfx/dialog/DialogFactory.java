package com.spcapitaliq.jfx.dialog;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.*;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBuilder;
import javafx.scene.control.LabelBuilder;
import javafx.scene.layout.BorderPaneBuilder;
import javafx.scene.layout.HBoxBuilder;
import javafx.scene.layout.VBoxBuilder;
import javafx.stage.*;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;

/**
 *
 * @author mmorton
 *
 */
public class DialogFactory
{
  private static final Logger Log = Logger.getLogger(DialogFactory.class);

  private DialogFactory()
  {
    /** static only */
  }

  public static Parent buildBodyWithConsole(Node body, Node... console)
  {
    final Parent root = VBoxBuilder.create()
      .padding(new Insets(4))
      .spacing(4)
      .children(
        body,
        HBoxBuilder.create()
          .alignment(Pos.CENTER)
          .spacing(4)
          .children(console)
          .build()
      )
      .build();
    return root;
  }

  public static void showAny( final DialogControl control, final String title, final Node body )
  {
    final Parent root = body instanceof Parent ? (Parent)body : BorderPaneBuilder.create().center(body).build();
    JFXUtil.runSafe(new Runnable()
    {
      @Override
      public void run()
      {
        Scene scene = SceneBuilder.create().root( root ).build();
        final Stage stage = new Stage( StageStyle.UTILITY );
        stage.initModality( Modality.APPLICATION_MODAL );
        stage.setResizable(false);
        stage.setTitle(title);
        stage.setScene(scene);

        stage.setOnHidden(new EventHandler<WindowEvent>()
        {
          @Override
          public void handle(final WindowEvent we)
          {
            Log.debug("Hidden");
            control.close();
          }
        });

        control.show( stage );
      }
    });
  }

  public static void showAny( final DialogControl control, final String title, String message, Node... console )
  {
    Parent body = buildBodyWithConsole(
      LabelBuilder.create().text(message).build(), console);
    showAny(control, title, body);
  }

  public static void showMessage( Node anchor, String title, String message )
  {
    final DialogControl control = new DialogControl(anchor);

    Button buttonOK = ButtonBuilder.create().text("OK")
      .onAction(new EventHandler<ActionEvent>()
      {
        @Override
        public void handle(ActionEvent ae)
        {
          control.close();
        }
      }).build();

    showAny( control, title, message, buttonOK );
  }

  public static void showInfo( Node anchor, String message )
  {
    showMessage(anchor, "Information", message);
  }

  public static void showError( Node anchor, String message )
  {
    showMessage(anchor, "Error", message);
  }
}
