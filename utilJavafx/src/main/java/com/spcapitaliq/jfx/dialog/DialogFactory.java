package com.spcapitaliq.jfx.dialog;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.*;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
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
    final HBox inside = new HBox(console);
    inside.setAlignment(Pos.CENTER);
    inside.setSpacing(4);

    final VBox root = new VBox(body, inside);
    root.setPadding(new Insets(4));
    root.setSpacing(4);

    return root;
  }

  public static void showAny( final DialogControl control, final String title, final Node body )
  {
    final Parent root = body instanceof Parent ? (Parent)body : new BorderPane(body);
    JFXUtil.runSafe(new Runnable()
    {
      @Override
      public void run()
      {
        Scene scene = new Scene( root );
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
    Parent body = buildBodyWithConsole(new Label(message), console);
    showAny(control, title, body);
  }

  public static void showMessage( Node anchor, String title, String message )
  {
    final DialogControl control = new DialogControl(anchor);

    Button buttonOK = new Button("OK");
    buttonOK.setOnAction(new EventHandler<ActionEvent>()
      {
        @Override
        public void handle(ActionEvent ae)
        {
          control.close();
        }
      });

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
