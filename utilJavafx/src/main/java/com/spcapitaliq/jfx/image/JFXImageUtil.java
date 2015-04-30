package com.spcapitaliq.jfx.image;

import java.awt.*;
import java.awt.image.BufferedImage;
import java.awt.image.ImageObserver;
import java.awt.print.PageFormat;
import java.awt.print.Printable;
import java.awt.print.PrinterException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import javax.swing.SwingUtilities;

import javafx.embed.swing.SwingFXUtils;
import javafx.scene.Node;
import javafx.scene.SnapshotParameters;
import javafx.scene.image.Image;
import javafx.scene.image.WritableImage;
import javafx.stage.FileChooser;

import com.spcapitaliq.jfx.concurrency.RunLaterWaiter;

/**
 * Static goodies for dealing with images in JavaFX.
 *
 * @author mmorton
 */
public class JFXImageUtil
{
  public static final class Extension
  {
    private Extension() {}

    public static final String PNG = ".png";
  }

  private JFXImageUtil() { /** static only */ }

  /**
   * Creates a {@link WritableImage} for the current state of the given {@link Node}.
   * This is only supported for Nodes current part of the scene. Whatever dimensions
   * it currently has will be used to generate the snapshot.
   *
   * @param node
   * @return
   */
  public static WritableImage takeSnapshot(final Node node)
  {
    final WritableImage[] holder = new WritableImage[1];
    RunLaterWaiter.runLaterAndWait(new Runnable() {
      @Override
      public void run()
      {
        holder[0] = node.snapshot(new SnapshotParameters(), null);
      }
    });
    return holder[0];
  }

  public static FileChooser.ExtensionFilter extensionFilterForPng()
  {
    return new FileChooser.ExtensionFilter("Portable Network Graphics", Collections.singletonList("*" + Extension.PNG));
  }

  /**
   *
   * @param swingComponent
   * @return the images or an empty list if none exists.
   */
  public static List<Image> extractSwingWindowIcons(java.awt.Component swingComponent)
  {
    Window window = swingComponent instanceof Window ? (Window)swingComponent
        : SwingUtilities.getWindowAncestor(swingComponent);

    List<java.awt.Image> swingIcons = window.getIconImages();

    int numIcons = swingIcons.size();
    List<Image> images = new ArrayList<>(numIcons);
    for(int i = 0; i < numIcons; i++)
      images.add(convertSwingImage(swingIcons.get(i), swingComponent));

    return images;
  }

  public static Image convertSwingImage(java.awt.Image img, ImageObserver obs)
  {
    BufferedImage bImg = new BufferedImage(img.getWidth(obs), img.getHeight(obs), BufferedImage.TYPE_INT_ARGB);
    bImg.getGraphics().drawImage(img, 0, 0, obs);
    return SwingFXUtils.toFXImage(bImg, null);
  }

  /**
   * Way to paint any Node as an image. This may be made obsolete by JFX8.
   *
   * @param node
   * @param pageFormat
   * @param pageIndex
   *
   * @return PAGE_EXISTS if the page is rendered successfully or NO_SUCH_PAGE
   * if pageIndex specifies a non-existent page.
   *
   * @throws PrinterException if the print failed
   */
  public static int printNode(Graphics2D g2, Node node, PageFormat pageFormat, int pageIndex)
  {
    if (pageIndex != 0) {
      return Printable.NO_SUCH_PAGE;
    }

    Dimension sizeAvail = new Dimension((int)pageFormat.getImageableWidth(), (int)pageFormat.getImageableHeight());

    double xImageable = pageFormat.getImageableX();
    double yImageable = pageFormat.getImageableY();

    g2.translate(xImageable, yImageable);

    WritableImage img = takeSnapshot(node);

    int imageW = (int)img.getWidth(), imageH = (int)img.getHeight();
    Dimension desiredSize = new Dimension(imageW, imageH);
    float zoom = determineZoomFactor(sizeAvail, desiredSize);
    g2.scale(zoom, zoom);

    java.awt.image.BufferedImage bImg = SwingFXUtils.fromFXImage(img, null);
    g2.drawImage(bImg, 0, 0, imageW, imageH, null);
    return Printable.PAGE_EXISTS;
  }

  public static class PrintableNode implements Printable
  {
    private final Node _node;

    public PrintableNode(Node node)
    {
      _node = node;
    }

    @Override
    public int print(final Graphics graphics, final PageFormat pageFormat, final int pageIndex) throws PrinterException
    {
      return printNode((Graphics2D)graphics, _node, pageFormat, pageIndex);
    }
  }

  /**
   * Determines the zoom factor based on the space available and the desired
   * size.
   *
   * @param availableSize Dimension the size available for the page
   * @param desiredSize Dimension the desired size of the component
   *
   * @return float the scale factor required to fit the desired size'd
   * component all on one page
   */
  public static float determineZoomFactor(Dimension availableSize, Dimension desiredSize)
  {
    float zoomFactor = 1;
    if( desiredSize.width > availableSize.width || desiredSize.height > availableSize.height )
    {
      // compare the decimal values since the incorrect zooming factor could
      // be used if both the width and height are off by the same whole number
      // For example, if the width is off by 1.9 but the height is off by 1.01
      // then the decimal is very important.  If not used, then it will compare
      // 1>1, which is false and the height will be incorrectly used for the
      // scaling.
      //
      if( desiredSize.width / (float)availableSize.width > desiredSize.height / (float)availableSize.height )
      {
        // adjust the width since it is further off
        //
        zoomFactor = availableSize.width / (float)desiredSize.width;
      }
      else
      {
        // adjust the height since it is further off
        //
        zoomFactor = availableSize.height / (float)desiredSize.height;
      }
    }
    return zoomFactor;
  }
}