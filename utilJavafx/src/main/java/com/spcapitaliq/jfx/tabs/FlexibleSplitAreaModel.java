package com.spcapitaliq.jfx.tabs;

import java.util.*;

import javafx.collections.ListChangeListener;
import javafx.collections.ObservableList;
import javafx.geometry.Orientation;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.Label;
import javafx.scene.control.SplitPane;
import javafx.scene.control.SplitPane.Divider;
import javafx.scene.layout.BorderPane;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.node.NodeWrap;
import com.spcapitaliq.jfx.value.NewValueListener;

/**
 * 
 * @author mmorton
 *
 */
public final class FlexibleSplitAreaModel
{
  private static final Logger _log = Logger.getLogger(FlexibleSplitAreaModel.class);
  
  private Orientation _orientation;

  /**
   * The proportional weight and the wrap to provide a node for each item in the splitter.
   */
  private List<NodeWrap<?>> _contents;
  
  private double[] _dividers;

  private transient SplitPane _splitter;
  
  private transient IdentityHashMap<Divider, DividerHandler> _handlers;
  
  public FlexibleSplitAreaModel()
  {
    _orientation = Orientation.HORIZONTAL;
    _contents = new LinkedList<>();
    _dividers = new double[0];
    _handlers = new IdentityHashMap<>();
  }

  void add(NodeWrap<?> content, int index)
  {
    _contents.add(index, content);
    _splitter.getItems().add(index, content.peekNode());
  }
  
  public Orientation getOrientation()
  {
    return _orientation;
  }

  public void setOrientation(Orientation orientation)
  {
    _orientation = orientation;
  }

  public List<NodeWrap<?>> getContents()
  {
    return _contents;
  }

  @Deprecated
  public void setContents(List<NodeWrap<?>> contents)
  {
    _contents = contents;
  }
  
  public void addContent(NodeWrap<?> content)
  {
    _contents.add(content);
  }
  
  /**
   * Used to mark the parent of a divider's content. A {@link DividerMarker}
   * instance is guaranteed to only be used as an {@link SplitPane}'s item.
   * 
   * Also keeps a reference back to the {@link NodeWrap} for later use.
   *  
   * @author thraxxis
   *
   */
  static final class DividerMarker extends BorderPane
  {
    private final NodeWrap<?> _wrap;

    private DividerMarker(NodeWrap<?> wrap)
    {
      _wrap = wrap;
      setCenter(wrap.peekNode());
    }
  }
  
  public Parent buildArea()
  {
    int numContents = _contents.size();
    if( numContents == 0 )
    {
      return new BorderPane(new Label("??"));
    }
    else
    {
        List<Node> nodes = new ArrayList<>(numContents);
        for( NodeWrap<?> wrap : _contents )
        {
          nodes.add( new DividerMarker(wrap) );
        }
        
        FlexibleSplitArea area = new FlexibleSplitArea(this);
        SplitPane splitter = area.peekSplitter();
        splitter.setOrientation(_orientation);
        splitter.getItems().addAll(nodes);
        return bind(area);
    }
  }  

  @Deprecated
  public double[] getDividers()
  {
    return _dividers;
  }

  @Deprecated
  public void setDividers(double[] dividers)
  {
    _dividers = dividers;
  }
  
  /**
   * 
   * @param splitter
   * @return convenience "fluency" access to splitter
   */
  public FlexibleSplitArea bind(FlexibleSplitArea splitter)
  {
    _splitter = splitter.peekSplitter();
    ObservableList<Divider> dividers = _splitter.getDividers();
    dividers.addListener(new ListChangeListener<Divider>()
    {
      @Override
      public void onChanged(ListChangeListener.Change<? extends Divider> change)
      {
        rebindDividers();
      }
    });
    
    if( _dividers.length == dividers.size() )
      _splitter.setDividerPositions(_dividers);
    rebindDividers();
    
    return splitter;
  }
  
  /**
   * Resets the divider handlers, reusing or introducing as {@link Divider}
   * instances come and go.
   */
  private void rebindDividers()
  {
    _dividers = _splitter.getDividerPositions();
    _log.debug("Rebinding divider positions.");
    
    ObservableList<Divider> dividers = _splitter.getDividers();
    int numDividers = dividers.size();
    
    IdentityHashMap<Divider, DividerHandler> handlers = new IdentityHashMap<>();
    for( int i = 0; i < numDividers; i++ )
    {
      Divider divider = dividers.get(i);
      DividerHandler handler = _handlers.get(i);
      if( null == handler )
      {
        handler = new DividerHandler(i);
        divider.positionProperty().addListener(handler);
      }
      else
        handler._index = i;
      handlers.put(divider, handler);
    }
    
    _handlers = handlers;
  }
  
  private class DividerHandler extends NewValueListener<Number>
  {
    private int _index;
    
    DividerHandler(int index)
    {
      _index = index;
    }

    @Override
    protected void changed(Number newVal)
    {
      _log.trace("Divider " + _index + " changed: " + newVal);
      _dividers[_index] = newVal.doubleValue();
    }
  }
  
}
