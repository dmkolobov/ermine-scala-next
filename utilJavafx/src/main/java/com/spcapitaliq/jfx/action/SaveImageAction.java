package com.spcapitaliq.jfx.action;

import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

import javafx.embed.swing.SwingFXUtils;
import javafx.event.ActionEvent;
import javafx.scene.Node;
import javafx.scene.image.WritableImage;
import javafx.stage.FileChooser;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.concurrency.BlockerModal;
import com.spcapitaliq.jfx.concurrency.BlockerTask;
import com.spcapitaliq.jfx.image.JFXImageUtil;
import com.spcapitaliq.jfx.io.JFXFileUtil;

/**
 *
 * @author mmorton
 *
 */
public class SaveImageAction extends AbstractJFXAction<Node>
{
  private static final Logger _log = Logger.getLogger(SaveImageAction.class);

  @Override
  protected void handle(ActionEvent ae, Node node)
  {
    final WritableImage snapshot = JFXImageUtil.takeSnapshot(node);
    if( null == snapshot )
    {
      _log.error("Failed to take snapshot");
      return;
    }

    FileChooser fileChooser = new FileChooser();
    fileChooser.setTitle("Save Image");
    fileChooser.getExtensionFilters().add(JFXImageUtil.extensionFilterForPng());
    File originalFile = fileChooser.showSaveDialog(node.getScene().getWindow());
    if(null != originalFile)
    {
      final File file = JFXFileUtil.appendExtensionIfMissing(originalFile, JFXImageUtil.Extension.PNG);
      class Logic extends BlockerTask<Object>
      {
        @Override
        protected Object call() throws Exception
        {
          this.updateMessage("Saving image...");

          long referenceTime = System.currentTimeMillis();
          BufferedImage img = SwingFXUtils.fromFXImage(snapshot, null);
          try
          {
            ImageIO.write(img, "png", file);
            JFXUtil.provideMinimumPause(referenceTime, 1500);
          }
          catch (Exception e)
          {
            /** @todo MJM popup dialog */
            _log.error("Failed to write image", e);
          }
          return null;
        }

      }
      new BlockerModal().show(node, new Logic());
    }
  }

  @Override
  protected String defineActionText()
  {
    return "Save as Image...";
  }

}
