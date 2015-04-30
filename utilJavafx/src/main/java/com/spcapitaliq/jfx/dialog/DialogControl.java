package com.spcapitaliq.jfx.dialog;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.stage.Stage;
import javafx.stage.Window;

import com.sun.javafx.stage.EmbeddedWindow;

import com.spcapitaliq.jfx.JFXUtil;

/**
 *
 * @author mmorton
 *
 */
public class DialogControl
{
  private final Window _owner;
  private Stage _stage;
  private boolean _wait;

  public DialogControl( Window owner )
  {
    _owner = owner;
    _stage = null;
    _wait = true;
  }

  public DialogControl( Node anchor )
  {
    this( resolveOwner(anchor) );
  }

  private static Window resolveOwner(Node anchor)
  {
    Window win = anchor.getScene().getWindow();
    if(win instanceof EmbeddedWindow)
      return null;
    return win;
  }

  public void setWait(boolean wait)
  {
    _wait = wait;
  }

  void show( Stage stage )
  {
    _stage = stage;
    _stage.sizeToScene();
    _stage.initOwner(_owner);

    stage.centerOnScreen();
    if(_wait)
      stage.showAndWait();
    else
      stage.show();
  }

  public void toFront()
  {
    JFXUtil.runSafe(new Runnable() {
      @Override
      public void run()
      {
        _stage.toFront();
      }
    });
  }

  /** doesn't work because bounds is 0,0 until window is shown
  public static void centerOver( Window anchor, Window floater )
  {
      Scene scene = floater.getScene();
      Parent root = scene.getRoot();
      root.layout();
      Bounds bounds = root.layoutBoundsProperty().getValue();

      double width = bounds.getWidth();//scene.getWidth();
      double height = bounds.getHeight();// scene.getHeight();
      floater.setX( anchor.getX() + anchor.getWidth() / 2 - width / 2 );
      floater.setY( anchor.getY() + anchor.getHeight() / 2 - height / 2 );
  }
  */

  public void close()
  {
    JFXUtil.runSafe(new Runnable()
    {
      @Override
      public void run()
      {
        _stage.close();
      }
    });
  }

  public EventHandler<ActionEvent> buildSimpleCloseAction()
  {
    return new CloseDialogAction(this);
  }

  public static class CloseDialogAction implements EventHandler<ActionEvent>
  {
    private final DialogControl _control;

    public CloseDialogAction(DialogControl control)
    {
      _control = control;
    }

    @Override
    public void handle(final ActionEvent ae)
    {
      _control.close();
    }
  }
}
