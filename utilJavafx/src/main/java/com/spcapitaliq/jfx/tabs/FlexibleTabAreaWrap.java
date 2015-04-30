package com.spcapitaliq.jfx.tabs;

import com.spcapitaliq.jfx.node.NodeWrap;

/**
 * 
 * @author mmorton
 *
 */
public class FlexibleTabAreaWrap extends NodeWrap<FlexibleTabArea>
{
  private FlexibleTabAreaModel _model;
  
  public FlexibleTabAreaWrap()
  {
    _model = new FlexibleTabAreaModel();
  }
  
  @Deprecated
  public FlexibleTabAreaModel getModel()
  {
    return _model;
  }

  @Deprecated
  public void setModel(FlexibleTabAreaModel model)
  {
    _model = model;
  }

  @Override
  protected FlexibleTabArea buildNode()
  {
    FlexibleTabArea area = new FlexibleTabArea();
    _model.bind(area);
    return area;
  }
}
