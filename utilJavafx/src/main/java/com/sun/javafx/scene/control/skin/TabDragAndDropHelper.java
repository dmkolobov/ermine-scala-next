package com.sun.javafx.scene.control.skin;

import java.awt.MouseInfo;
import java.awt.Point;
import java.util.IdentityHashMap;

import javafx.event.EventHandler;
import javafx.scene.Scene;
import javafx.scene.SceneBuilder;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.control.TabPaneBuilder;
import javafx.scene.input.*;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.stage.Window;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXUtil;
import com.spcapitaliq.jfx.node.NodeTraverser;
import com.spcapitaliq.jfx.tabs.TabPath;

/**
 * 
 * @author mmorton
 * 
 */
public class TabDragAndDropHelper
{
  private static final Logger _log = Logger.getLogger(TabDragAndDropHelper.class);
  
  private static IdentityHashMap<Tab, Integer> _tabMap = new IdentityHashMap<>();
  
  private static int _tabId = 0;

  public static void registerTab( Tab tab )
  {
    if(_tabMap.containsKey(tab))
      throw new UnsupportedOperationException("This Tab was already registered: " + tab);
    
    Integer id = Integer.valueOf(_tabId++);
    _tabMap.put(tab, id);
  }
  
  private final TabPane _tabs;
  
  private TabDragAndDropHelper(TabPane tabs)
  {
    _tabs = tabs;
  }
  
  private void configure()
  {
    JFXUtil.setOnFirstSized(_tabs, new Runnable()
    {

      @Override
      public void run()
      {
        NodeTraverser.traverse(_tabs, new MakeTabDraggable());
      }
    });
  }
  
  private class MakeTabDraggable extends NodeTraverser.HasInstanceStrategy<TabPaneSkin.TabHeaderSkin>
  {
    MakeTabDraggable()
    {
      super(TabPaneSkin.TabHeaderSkin.class);
    }

    @Override
    protected void applyInstance(final TabPaneSkin.TabHeaderSkin node)
    {
      node.setOnDragDetected(new EventHandler<MouseEvent>()
      {
        @Override
        public void handle(MouseEvent me)
        {
          Dragboard db = node.startDragAndDrop(TransferMode.ANY);

          /* Put the tab's name as string on a dragboard if ctrl is down*/
          ClipboardContent content = new ClipboardContent();
          if(me.isControlDown())
            content.putString(node.getTab().getText());
          content.put(TabPath.DRAGGABLE_TAB_FORMAT, new TabPath(node.getTab()));
          
          /** @todo MJM put in tab's contents as a bitmap */
          
          db.setContent(content);

          me.consume();
        }
      });
      
      node.setOnDragDone(new EventHandler<DragEvent>()
      {
        @Override
        public void handle(DragEvent de)
        {
          Point p = MouseInfo.getPointerInfo().getLocation();
          _log.debug("Drop done on screen at: " + p.x + ", " + p.y);
          
          
          if(true||de.isAccepted())
          {
            _log.debug("abort");
            return;
          }
          
          Tab tab = node.getTab();
          Window ownerWindow = node.getScene().getWindow();
          tab.getTabPane().getTabs().remove(tab);
          
          TabPane newTabs = TabPaneBuilder.create()
            .tabs(tab)
            .build();
          newTabs.setPrefSize(_tabs.getWidth(), _tabs.getHeight());
          
          Scene scene = SceneBuilder.create().root( newTabs ).build();
          Stage stage = new Stage( StageStyle.DECORATED );
//          stage.initModality( Modality.APPLICATION_MODAL );
          stage.setTitle("Child Window");
          stage.setScene(scene);
//          stage.initOwner(ownerWindow);
          stage.sizeToScene();
          stage.setX(p.x);
          stage.setY(p.y);
          
          stage.show();
        }
      });
      
      node.setOnDragDropped(new EventHandler<DragEvent>()
      {
        @Override
        public void handle(DragEvent de)
        {
          _log.debug("drop dropped");
        }
      });
    }
  }
  
  public static void configure(final TabPane tabs)
  {
    TabDragAndDropHelper helper = new TabDragAndDropHelper(tabs);
    helper.configure();
  }
}
