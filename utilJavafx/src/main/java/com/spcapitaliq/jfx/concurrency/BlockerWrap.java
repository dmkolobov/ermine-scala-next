package com.spcapitaliq.jfx.concurrency;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.node.NodeWrap;
import javafx.concurrent.Worker.State;
import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.geometry.Pos;
import javafx.scene.Cursor;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBuilder;
import javafx.scene.control.ProgressBar;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBoxBuilder;
import javafx.scene.text.Text;
import org.apache.log4j.Logger;

/**
 * Provides an overlay that blocks all keyboard and mouse input
 * to the content beneath.
 *
 * @author mmorton
 *
 */
public final class BlockerWrap extends NodeWrap<StackPane>
{
  private static final Logger _log = Logger.getLogger(BlockerWrap.class);

  private final BorderPane _content;

  private final Overlay _overlay;

  private Node _childWithFocus = null;

  private int _blockCount;
  private final Object _blockLock;

  private BlockerTask<?> _worker;
  private final Object _workerLock;

  private final ExecutorService _executor;

  public BlockerWrap()
  {
    this( null, null );
  }

  public BlockerWrap( ExecutorService executor )
  {
    this( null, executor );
  }

  public BlockerWrap( Node content )
  {
    this( content, null );
  }

  public BlockerWrap( Node content, ExecutorService executor )
  {
    _content = new BorderPane();
    _overlay = new Overlay();
    _blockCount = 0;
    _blockLock = new Object();
    _worker = null;
    _workerLock = new Object();

    _executor = null != executor ? executor : Executors.newSingleThreadExecutor();

    _content.setCenter( content );
  }

  @Override
  protected StackPane buildNode()
  {
    _overlay.setVisible( false );
    _overlay.setFocusTraversable( true );

    class BlockerStackPane extends StackPane
    {
      BlockerStackPane()
      {
        getChildren().addAll(_content, _overlay);
      }
    }
    return new BlockerStackPane();
  }

  private class Overlay extends BorderPane
  {
    private final ProgressBar _progress;
    private final Text _text;
    private final Button _cancel;

    private Overlay()
    {
      setCenter( VBoxBuilder.create()
          .alignment(Pos.CENTER)
          .spacing(4)
          .children(
              _cancel = ButtonBuilder.create()
                .text("Cancel")
                .onAction(new EventHandler<ActionEvent>()
                {
                  @Override
                  public void handle(ActionEvent ae)
                  {
                    _worker.cancel(_worker.doesCancelInterrupt);
                  }
                })
                .build(),
              _progress = new ProgressBar(),
              _text = new Text())
          .build() );
      setCursor(Cursor.WAIT);
      reset();
    }

    private void reset()
    {
      _cancel.setVisible(false);
    }
  }

  public void pokeContent( final Node content )
  {
    class Logic implements Runnable
    {
      @Override
      public void run()
      {
        _content.setCenter( content );
      }
    }
    JFXUtil.runSafe( new Logic() );
  }

  public void pokeMessage( final String message )
  {
    _overlay._text.setText(message);
  }

  private boolean doesContentChildHaveFocus()
  {
    Scene scene = _content.getScene();
    if( null == scene )
      return false;
    Node node = scene.getFocusOwner();
    if( null != node && node.isFocused() )
    {
      while( null != node )
      {
        if( node == _content )
          return true;
        node = node.getParent();
      }
    }

    return false;
  }

  public void addBlocking()
  {
    synchronized( _blockLock )
    {
      if( ++_blockCount > 1 )
        return;
    }

    class Logic implements Runnable
    {
      @Override
      public void run()
      {
        _content.setDisable( true );
        _overlay.setVisible( true );
        if( doesContentChildHaveFocus() )
        {
          _childWithFocus = _content.getScene().getFocusOwner();
          _overlay.requestFocus();
        }
        else
          _childWithFocus = null;
      }
    }
    JFXUtil.runSafe( new Logic() );
  }

  public void removeBlocking()
  {
    synchronized( _blockLock )
    {
      if( --_blockCount > 0 )
        return;
      if( _blockCount < 0 )
      {
        _blockCount = 0;
        throw new UnsupportedOperationException( "Prevented attempt to stop blocking when not already blocking" );
      }
    }

    class Logic implements Runnable
    {
      @Override
      public void run()
      {
        _overlay.setVisible( false );
        _content.setDisable( false );

        if(null != _childWithFocus)
        {
          if(null != _childWithFocus.getScene())
            _childWithFocus.requestFocus();
        }
      }
    }
    JFXUtil.runSafe( new Logic() );
  }

  public boolean isBound()
  {
    synchronized( _workerLock )
    {
      return null != _worker;
    }
  }

  private void unbind()
  {
    synchronized( _workerLock )
    {
      _overlay._progress.progressProperty().unbind();
      _overlay._text.textProperty().unbind();
      _overlay.reset();
      _worker = null;
    }
  }

  private void bind()
  {
    _overlay._progress.progressProperty().bind(_worker.progressProperty());
    _overlay._text.textProperty().bind(_worker.messageProperty());

    if(_worker.allowCancel)
      _overlay._cancel.setVisible(true);
  }

  public void bindTo( BlockerTask<?> worker )
  {
    if( worker.getState() != State.READY )
      throw new UnsupportedOperationException( "Prevented attempt to bind to Worker not in READY state" );

    synchronized( _workerLock )
    {
      if( null != _worker )
        throw new UnsupportedOperationException( "Prevented attempt to bind when already bound" );
      _worker = worker;
    }

    _log.debug("Bound to: " + worker);

    class StateWatcher extends AbstractBlocker.SimpleStateWatcher
    {
      @Override
      protected void started()
      {
        addBlocking();
        bind();
      }

      @Override
      protected void stopped(State state)
      {
        unbind();
        removeBlocking();
      }
    }
    worker.stateProperty().addListener( new StateWatcher() );
    _executor.submit( worker );
  }
}