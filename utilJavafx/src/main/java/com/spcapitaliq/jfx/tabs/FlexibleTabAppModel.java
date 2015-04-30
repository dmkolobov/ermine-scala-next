package com.spcapitaliq.jfx.tabs;

import java.util.*;

import javafx.event.EventHandler;
import javafx.scene.Scene;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.stage.WindowEvent;
import javafx.util.Pair;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.window.StageModel;

/**
 * Maintains all the state about the {@link FlexibleTabArea}s present for an application. 
 * The StageModel map stores all the dimension, title, and other property information about each
 * Stage that will be established at runtime.
 * 
 * @author mmorton
 *
 */
public final class FlexibleTabAppModel
{
  private static final Logger _log = Logger.getLogger(FlexibleTabAppModel.class);
  
  private static final Long PRIMARY_STAGE_ID = Long.valueOf(0);

  private long _stageIdCounter;
  
  private Map<Long, StageModel> _stages;
  
  private Map<Long, FlexibleSplitAreaModel> _areas;
  
  public FlexibleTabAppModel()
  {
    _stages = new LinkedHashMap<>();
    
    _areas = new LinkedHashMap<>();
    
    /// id 0 is reserved for the primary stage
    _stageIdCounter = 1;
  }

  public boolean hasPrimaryStage()
  {
    return _stages.containsKey(PRIMARY_STAGE_ID);
  }
  
  public void bootstrap(Stage stage, FlexibleSplitAreaModel areaModel)
  {
    if( hasPrimaryStage() )
      throw new UnsupportedOperationException("Bootstrap may only be called if on primary stage already");
    
    StageModel model = new StageModel();
    model.bind(stage);
    
    establishStage(stage, areaModel);
    
    _stages.put(PRIMARY_STAGE_ID, model);
    _areas.put(PRIMARY_STAGE_ID, areaModel);
    
    stage.centerOnScreen();
    
    stage.show();
  }
  
  public Long add(Stage stage, FlexibleSplitAreaModel areaModel)
  {
    JFXUtil.throwIfNotApplicationThread();
    if( !hasPrimaryStage() )
      throw new UnsupportedOperationException("Add may only be called if the primary stage exists");
    
    establishStage(stage, areaModel);
    
    StageModel model = new StageModel();
    model.bind(stage);

    Long id = Long.valueOf(_stageIdCounter++);
    _stages.put(id, model);
    _areas.put(id, areaModel);
    
    return id;
  }
  
  public void restore(final Long stageId, Stage stage)
  {
    StageModel model = _stages.get(stageId);
    if(null == model)
    {
      _log.error("No stage for id: " + stageId);
      return;
    }
    
    FlexibleSplitAreaModel areaModel = _areas.get(stageId);
    establishStage(stage, areaModel);
    
    if(!PRIMARY_STAGE_ID.equals(stageId))
    {
      stage.initStyle(StageStyle.UTILITY);
      stage.initOwner(peekPrimaryStage().peekStage());
      
      class OnCloseHandler implements EventHandler<WindowEvent>
      {
        @Override
        public void handle(WindowEvent we)
        {
          remove(stageId);
        }
      }
      stage.setOnCloseRequest(new OnCloseHandler());
    }
    model.bind(stage);
    stage.show();
  }
  
  private void establishStage(Stage stage, FlexibleSplitAreaModel areaModel)
  {
    stage.setScene(new Scene(areaModel.buildArea()));
  }
  
  public void remove(Long stageId)
  {
    StageModel removed = _stages.remove(stageId);
    if(null == removed)
      _log.error("Stage does not exist to be removed for id: " + stageId );
    
    _areas.remove(stageId);
  }
  
  public StageModel peekPrimaryStage()
  {
    return _stages.get(PRIMARY_STAGE_ID);
  }
  
  public List<Pair<Long, StageModel>> peekStages()
  {
    ArrayList<Pair<Long, StageModel>> stages = new ArrayList<>(_stages.size());
    for(Map.Entry<Long, StageModel> entry : _stages.entrySet())
      stages.add(new Pair<Long, StageModel>(entry.getKey(), entry.getValue()));
    return stages;
  }
  
  public StageModel peekStage(Long id)
  {
    return _stages.get(id);
  }
  
  @Deprecated
  public Map<Long, StageModel> getStages()
  {
    return _stages;
  }

  @Deprecated
  public void setStages(Map<Long, StageModel> stages)
  {
    _stages = stages;
  }
  
  @Deprecated
  public long getStageIdCounter()
  {
    return _stageIdCounter;
  }

  @Deprecated
  public void setStageIdCounter(long stageIdCounter)
  {
    _stageIdCounter = stageIdCounter;
  }
  
  public FlexibleSplitAreaModel peekArea(Long id)
  {
    return _areas.get(id);
  }

  @Deprecated
  public Map<Long, FlexibleSplitAreaModel> getAreas()
  {
    return _areas;
  }
  
  @Deprecated
  public void setAreas(Map<Long, FlexibleSplitAreaModel> areas)
  {
    _areas = areas;
  }
}
