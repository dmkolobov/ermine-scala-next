package com.spcapitaliq.jfx.concurrency;

import java.util.concurrent.ExecutorService;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.window.JFXWindowUtil;
import javafx.beans.value.ChangeListener;
import javafx.concurrent.Worker.State;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.SceneBuilder;
import javafx.scene.layout.BorderPaneBuilder;
import javafx.scene.text.Text;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.StageBuilder;
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
    Parent root = BorderPaneBuilder.create()
        .center(_text)
        .prefWidth(200)
        .prefHeight(40)
        .build();

    Stage stage = StageBuilder.create()
      .title("Please wait...")
      .scene(SceneBuilder.create()
        .root(root)
        .build())
      .build();

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
