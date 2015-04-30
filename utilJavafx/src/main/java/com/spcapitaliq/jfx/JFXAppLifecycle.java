package com.spcapitaliq.jfx;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.layout.BorderPaneBuilder;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import org.apache.log4j.Logger;

/**
 *
 * @author mmorton
 *
 */
public class JFXAppLifecycle
{
  private static final Logger Log = Logger.getLogger( JFXAppLifecycle.class );

  private JFXAppLifecycle()
  {
    /** static only */
  }


  private static boolean _launched = false;

  public interface Launchable
  {
    Node provideNode();

    Scene provideScene();

    String provideTitle();

    String provideCSSFile();

    void decorateStage(Stage stage);
  }

  public static class VanillaLaunchable implements Launchable
  {
    private Node _node;
    private final String _title;
    private final String _cssFile;

    public VanillaLaunchable(Node node, String title, String cssFile)
    {
      _node = node;
      _title = title;
      _cssFile = cssFile;
    }

    @Override
    public Node provideNode()
    {
      return _node;
    }

    @Override
    public String provideTitle()
    {
      return _title;
    }

    @Override
    public String provideCSSFile()
    {
      return _cssFile;
    }

    @Override
    public void decorateStage(Stage stage)
    {
      stage.centerOnScreen();
    }

    @Override
    public Scene provideScene()
    {
      return buildVanillaScene(provideNode());
    }

    public static Scene buildVanillaScene(Node node)
    {
      return new Scene(BorderPaneBuilder.create().center(node).build());
    }

    public void cleanup()
    {
      //wipe out the reference so that the App's launchable is not
      //holding it in memory
      _node = null;
    }
  }

  private static void configureAndShowStage(Stage stage, Launchable launchable)
  {
    stage.setTitle( launchable.provideTitle() );

    Scene scene = launchable.provideScene();
    JFXUtil.loadCSS( scene, launchable.provideCSSFile() );
    stage.setScene( scene );

    launchable.decorateStage(stage);
//    Window window = scene.getWindow();
//    window.centerOnScreen();

    stage.show();
  }

  /**
   * Launches the given Node in the center of a new Stage.
   */
  public static void launch( final Launchable launchable )
  {
    /** NOTE: this isn't 100% bulletproof threading wise
        as multiple calls in rapid succession could blow it up
        but for the purpose of testing in REPL it should work fine */
    if( !_launched )
    {
      Platform.setImplicitExit(false);
      Log.debug( "Launching..." );
      _launched = true;
      App._launchable = launchable;

      Thread thread = new Thread( "Launcher" )
      {
        @Override
        public void run()
        {
          try
          {
            Application.launch( App.class, new String[]{
               App.Args.TITLE_PARAM + "=" + launchable.provideTitle(),
               App.Args.CSS_FILE + "=" + launchable.provideCSSFile()
            } );
          }
          catch( Exception e )
          {
            Log.error( "Failed to launch", e );
          }
        }
      };
      thread.setDaemon(true);
      thread.start();
      Log.debug( "Initial launch." );
    }
    else
    {
      Log.debug( "Subsequent launch." );
      Platform.runLater( new Runnable()
      {
        @Override
        public void run()
        {
          Stage stage = new Stage( StageStyle.DECORATED );
          try
          {
            configureAndShowStage(stage, launchable);
          }
          catch (Exception e)
          {
            Log.error("Failed in subsequent launch", e);
          }
        }
      } );
    }
  }

  public static class App extends Application
  {
    public static enum Args
    {
      TITLE_PARAM,
      CSS_FILE,
    }

    private static Launchable _launchable;

    /**
     * Do not call this constructor directly.
     * It's only to be used by {@link JFXAppLifecycle}
     */
    @Deprecated
    public App()
    {

    }

    @Override
    public void start( Stage stage ) throws Exception
    {
      //JWW: I couldn't figure out how Application.Parameters is supposed to work,
      //(and judging by some posts online, it doesn't currently work), so I am
      //allowing the title to be passed through as a raw arg in the form "TITLE=blah",
      //and manually splitting the name-value pairs, etc.  Maybe in a future version
      //of JFX this will be improved and the getParameters().getNamed() will actually
      //be populated.
      final List<String> args = getParameters().getRaw();
      final Map<String,String> namedParams = new HashMap<String,String>();
      for (String arg : args)
      {
        final String[] kv = arg.split("=", 2);
        if (kv.length == 2)
        {
          namedParams.put(kv[0], kv[1]);
        }
      }

      String title = namedParams.get(Args.TITLE_PARAM.toString());
      if (title == null || title.trim().isEmpty())
      {
        title = _launchable.provideTitle();
      }

      String cssFile = namedParams.get(Args.CSS_FILE.toString());
      if (cssFile == null || cssFile.trim().isEmpty())
      {
        cssFile = _launchable.provideCSSFile();
      }

      configureAndShowStage(stage, _launchable);
    }
  }
}