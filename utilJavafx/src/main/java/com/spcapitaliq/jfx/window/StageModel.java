package com.spcapitaliq.jfx.window;

import javafx.stage.Stage;

import com.spcapitaliq.jfx.value.NewValueListener;

/**
 * 
 * @author mmorton
 *
 */
public final class StageModel extends WindowModel
{
  private String _title;
  
  private transient Stage _stage;
  
  public StageModel()
  {
    _title = "Untitled";
    _stage = null;
  }
  
  public String getTitle()
  {
    return _title;
  }

  public void setTitle(String name)
  {
    _title = name;
  }
  
  public Stage peekStage()
  {
    if(null == _stage)
      throw new UnsupportedOperationException("Must call bind before peekStage");
    return _stage;
  }
  
  public void bind(Stage stage)
  {
    super.bind(stage);
    _stage = stage;
    
    stage.titleProperty().addListener(new NewValueListener<String>()
    {
      @Override
      protected void changed(String newVal)
      {
        _title = newVal;
      }
    });
    stage.setTitle(_title);
  }
}
