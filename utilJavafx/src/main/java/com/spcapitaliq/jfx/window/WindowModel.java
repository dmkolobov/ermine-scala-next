package com.spcapitaliq.jfx.window;

import java.io.Serializable;

import javafx.stage.Window;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.value.NewValueListener;

/**
 * 
 * @author mmorton
 *
 */
public class WindowModel implements Serializable
{
  private static final Logger _log = Logger.getLogger(WindowModel.class);
  
  private double _x;
  private double _y;
  private double _w;
  private double _h;
  
  public WindowModel()
  {
    _x = 0;
    _y = 0;
    _w = 300;
    _h = 200;
  }

  private static abstract class DoubleMunger extends NewValueListener<Number>
  {
    @Override
    protected void changed(Number newVal)
    {
      apply(newVal.doubleValue());
    }
    
    protected abstract void apply(double val);
  }
  
  public final void bind(Window win)
  {
    // x
    win.setX(_x);
    win.xProperty().addListener(new DoubleMunger()
    {
      @Override
      protected void apply(double val)
      {
        _x = val;
      }
    });

    // y
    win.yProperty().addListener(new DoubleMunger()
    {
      @Override
      protected void apply(double val)
      {
        _y = val;
      }
    });
    win.setY(_y);
    
    // width
    win.widthProperty().addListener(new DoubleMunger()
    {
      @Override
      protected void apply(double val)
      {
        _w = val;
      }
    });
    win.setWidth(_w);
    
    // height
    win.heightProperty().addListener(new DoubleMunger()
    {
      @Override
      protected void apply(double val)
      {
        _h = val;
      }
    });
    win.setHeight(_h);
  }
  
  public final double getX()
  {
    return _x;
  }

  public final void setX(double x)
  {
    _x = x;
  }

  public final double getY()
  {
    return _y;
  }

  public final void setY(double y)
  {
    _y = y;
  }

  public final double getW()
  {
    return _w;
  }

  public final void setW(double w)
  {
    _w = w;
  }

  public final double getH()
  {
    return _h;
  }

  public final void setH(double h)
  {
    _h = h;
  }
}
