package com.spcapitaliq.jfx.concurrency;

import java.util.concurrent.ExecutorService;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.window.JFXWindowUtil;
import javafx.beans.value.ChangeListener;
import javafx.concurrent.Worker.State;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.layout.BorderPane;
import javafx.scene.text.Text;
import javafx.stage.Modality;
import javafx.stage.Stage;
import org.apache.log4j.Logger;

/**
 * Modal dialog that shows while a {@link BlockerTask} is running.
 *
 * @author mmorton
 *
 */
public final class BlockerModal extends AbstractBlocker
{
  private static final Logger _log = Logger.getLogger(BlockerModal.class);

  private Stage _stage;

  private Text _text;

  public BlockerModal()
  {
    this(null);
  }

  public BlockerModal( ExecutorService executor )
  {
    super(executor);
  }

  private Stage buildStage( Node anchor )
  {
    _text = new Text("Please wait...");
    BorderPane root = new BorderPane(_text);
    root.setPrefWidth(200);
    root.setPrefHeight(40);

    Stage stage = new Stage();
    stage.setTitle("Please wait...");
    stage.setScene(new Scene(root));

    stage.initModality(Modality.APPLICATION_MODAL);
    stage.initOwner(anchor.getScene().getWindow());
    stage.sizeToScene();

    JFXWindowUtil.centerOver(anchor, stage);

    return stage;
  }

  public void show( Node anchor, BlockerTask<?> worker )
  {
    JFXUtil.throwIfNotApplicationThread();

    if( worker.getState() != State.READY )
      throw new UnsupportedOperationException( "Prevented attempt to bind to Worker not in READY state" );

    _stage = buildStage(anchor);
    _stage.show();

    _text.textProperty().bind(worker.messageProperty());
    submit(worker);
  }

  @Override
  protected ChangeListener<State> buildStateWatcher(BlockerTask<?> worker)
  {
    class StateWatcher extends AbstractBlocker.SimpleStateWatcher
    {
      @Override
      protected void started()
      {
        _log.debug("Started");
      }

      @Override
      protected void stopped(State state)
      {
        _log.debug("Stopped: " + state);
        _stage.hide();
      }
    }
    return new StateWatcher();
  }
}
