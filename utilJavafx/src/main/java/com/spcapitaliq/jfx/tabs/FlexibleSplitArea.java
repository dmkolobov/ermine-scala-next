package com.spcapitaliq.jfx.tabs;

import java.util.ArrayList;
import java.util.List;

import com.sun.javafx.scene.traversal.Direction;
import javafx.collections.ObservableList;
import javafx.event.EventHandler;
import javafx.geometry.Orientation;
import javafx.scene.Node;
import javafx.scene.control.SplitPane;
import javafx.scene.control.Tab;
import javafx.scene.input.DragEvent;
import javafx.scene.input.TransferMode;
import javafx.scene.layout.Region;
import javafx.scene.layout.StackPane;
import javafx.scene.paint.Color;
import javafx.scene.shape.Polygon;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.node.NodeWrap;
import com.spcapitaliq.jfx.tabs.TabPath.TabPathBrokenException;

/**
 * 
 * @author mmorton
 *
 */
public final class FlexibleSplitArea extends StackPane
{
  /** @todo MJM turn to CSS? */
  private static final Color HIT_COLOR = new Color(0,1,0,.5);
  private static final Color AWARE_COLOR = new Color(0,1,0,.2);

  private static final Logger _log = Logger.getLogger(FlexibleSplitArea.class);
  
  private final SplitPane _splitter;

  private transient Polygon _top;
  private transient Polygon _bottom;
  private transient Polygon _right;
  private transient Polygon _left;

  private final HUD _hud;
  private final FlexibleSplitAreaModel _model;
  
  FlexibleSplitArea(FlexibleSplitAreaModel model)
  {
    _model = model;
    _splitter = new SplitPane();
    
    _hud = new HUD();
    getChildren().addAll(_splitter, _hud);
    
    init();
  }

  // needs to accept a dropped tab or a new tab
  private void expand(Direction dir, NodeWrap<?> content, Runnable cleanup)
  {
    if(_splitter.getOrientation() == Orientation.HORIZONTAL)
    {
      if(dir == Direction.UP)
      {
        SplitPane sourceSplitter = new SplitPane();
        ObservableList<Node> originalItems = _splitter.getItems();
        List<Node> copyOfOriginalItems = new ArrayList<>( originalItems );
        originalItems.clear();
        
        sourceSplitter.getItems().addAll(copyOfOriginalItems);
        
        /** @todo MJM consolidate code to make new splitter */
        SplitPane newSplitter = new SplitPane();
        newSplitter.setOrientation(Orientation.HORIZONTAL);
        newSplitter.getItems().add(content.peekNode());
        
        _splitter.setOrientation(Orientation.VERTICAL);
        originalItems.addAll(newSplitter, sourceSplitter);
      }
      else if(dir == Direction.DOWN)
      {
        /** @todo MJM todo introduce new splitter */
      }
      else if(dir == Direction.LEFT)
      {
        _model.add(content, 0);
      }
      else if(dir == Direction.RIGHT)
      {
        _model.add(content, _splitter.getItems().size());
      }
    }
    else
    {
      
    }
    
    if(null != cleanup)
    try
    {
      cleanup.run();
    }
    catch( Exception e )
    {
      _log.error("Failed to run cleanup: " + cleanup, e);
    }
  }
  
  private Polygon buildPolygon( final Direction direction )
  {
    final Polygon target = new Polygon();

    target.setFill(AWARE_COLOR);
    
    // drag enter
    target.setOnDragEntered(new EventHandler<DragEvent>()
    {
      @Override
      public void handle(DragEvent de)
      {
        if(isDraggableTab(de))
        {
          _hud.setVisible(true);
          target.setFill(HIT_COLOR);
        }
      }
    });
    
    // drag exit
    class TargetDragExit implements EventHandler<DragEvent>
    {
      @Override
      public void handle(DragEvent de)
      {
        _hud.setVisible(false);
        target.setFill(AWARE_COLOR);
      }
    }
    target.setOnDragExited(new TargetDragExit());
    
    // drag over
    class TargetDragOver implements EventHandler<DragEvent>
    {
      @Override
      public void handle(DragEvent de)
      {
        if(de.getDragboard().hasContent(TabPath.DRAGGABLE_TAB_FORMAT))
        {
          de.acceptTransferModes(TransferMode.MOVE);
          
        }
        de.consume();
      }
    }
    target.setOnDragOver(new TargetDragOver());
    
    // drag dropped
    class TargetDragDrop implements EventHandler<DragEvent>
    {
      @Override
      public void handle(DragEvent de)
      {
        if(de.getTransferMode() == TransferMode.MOVE)
        {
          TabPath path = (TabPath) de.getDragboard().getContent(TabPath.DRAGGABLE_TAB_FORMAT);
          
          try
          {
            Tab tab = path.walk(getScene().getRoot());
            tab.getTabPane().getTabs().remove(path.getTabIndex());
            /** @todo MJM update model */
            FlexibleTabAreaWrap wrap = new FlexibleTabAreaWrap();
            wrap.peekNode().peekTabs().getTabs().add(tab);
            expand(direction, wrap, null);
          }
          catch (TabPathBrokenException e)
          {
            _log.warn("Failed to walk path: " + path, e);
          }
        }
        de.consume();
      }
    }
    target.setOnDragDropped(new TargetDragDrop());
    
    return target;
  }
  
  private class HUD extends Region
  {
    private final double gapPixels = 25;
    
    HUD()
    {
      setVisible(false);
      
      _top = buildPolygon(Direction.UP);
      _bottom = buildPolygon(Direction.DOWN);
      _right = buildPolygon(Direction.RIGHT);
      _left = buildPolygon(Direction.LEFT);

      getChildren().addAll(_top, _bottom, _right, _left);
    }
    
    @Override
    protected void layoutChildren()
    {
      /** @todo MJM vary gap based on nesting level */
      double w = getWidth();
      double h = getHeight();
      double x1 = gapPixels;
      double x2 = w - gapPixels;
      double y1 = gapPixels;
      double y2 = h - gapPixels;
      _top.getPoints().setAll(new Double[] {
          0d, 0d,
          w, 0d,
          x2, y1,
          x1, y1
      });
      _bottom.getPoints().setAll(new Double[] {
         0d, h,
         x1, y2, 
         x2, y2, 
         w, h
      });
      _right.getPoints().setAll(new Double[] {
          w, 0d,
          w, h,
          x2, y2,
          x2, y1
      });
      _left.getPoints().setAll(new Double[] {
         0d, 0d,
         x1, y1, 
         x1, y2, 
         0d, h
      });
      
      for(Node child : getChildren())
        child.autosize();
    }  
  }
  
  private static boolean isDraggableTab(DragEvent de)
  {
    return de.getDragboard().hasContent(TabPath.DRAGGABLE_TAB_FORMAT);
  }
  
  private class DragEnter implements EventHandler<DragEvent>
  {
    @Override
    public void handle(DragEvent de)
    {
      if(isDraggableTab(de))
      {
        _hud.setVisible(true);
      }
    }
  }
  
  private class DragExit implements EventHandler<DragEvent>
  {
    @Override
    public void handle(DragEvent de)
    {
      _hud.setVisible(false);
    }
  }
  
  private class DragOver implements EventHandler<DragEvent>
  {
    @Override
    public void handle(DragEvent de)
    {
      double w = getWidth();
      double h = getHeight();
      double x = de.getX();
      double y = de.getY();
//      _log.debug("Drag over: " + x + ", " + y + " " + w + 'x' + h);
      
      boolean isHoriztonal = _splitter.getOrientation().equals(Orientation.HORIZONTAL);
      int i = hitDivider(isHoriztonal ? x / w : y / h);
//      _log.debug("Divider hit: " + i);
      
      de.consume();
    }
    
    private int hitDivider(double proportionalPosition)
    {
      double[] dividerPositions = _splitter.getDividerPositions();
      int i = 0;
      for(; i < dividerPositions.length; i++ )
      {
        if( proportionalPosition <= dividerPositions[i] )
          break;
      }
      return i;
    }
  }
  
  private void init()
  {
    setOnDragOver(new DragOver());
    setOnDragEntered(new DragEnter());
    setOnDragExited(new DragExit());
  }
  
  public SplitPane peekSplitter()
  {
    return _splitter;
  }
}
