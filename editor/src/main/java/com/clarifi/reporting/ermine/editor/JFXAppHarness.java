package com.spcapitaliq.jfx;

import java.io.File;
import java.net.MalformedURLException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.spcapitaliq.jfx.JFXUtil;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.image.Image;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import org.apache.log4j.Logger;

/**
* Collection of methods relating to bridging in to the JavaFX environment from
* an external module, such as REPL.
*
* @author mmorton
*
*/
public class JFXAppHarness
{
  private static final Logger Log = Logger.getLogger( JFXAppHarness.class );

  static final String CONF_FILENAME_ROOT = "res/conf/ermine/";

  public static final String CSS_CONF_FILENAME = CONF_FILENAME_ROOT + "REPL.css";

  private static final String DEFAULT_TITLE = "Proto FX Report";

  private JFXAppHarness()
  {
    /** static only */
  }

  public static class App extends Application
  {
    public static enum Args
    {
      TITLE_PARAM,
      CSS_FILE,
    }

    private static Node _node;

    /**
     * @todo Replace JFXUtil.configureAndShowStage, most of rest with
     *       JFXAppLifecycle, remove deprecation warning suppression
     */
    @SuppressWarnings("deprecation")
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
        title = DEFAULT_TITLE;
      }

      String cssFile = namedParams.get(Args.CSS_FILE.toString());
      if (cssFile == null || cssFile.trim().isEmpty())
      {
        cssFile = CSS_CONF_FILENAME;
      }

      JFXUtil.configureAndShowStage( stage, _node, title, cssFile );
    }
  }

  public static void loadCSS( Scene scene )
  {
    JFXUtil.loadCSS( scene, CSS_CONF_FILENAME );
  }


  /**
   * @todo Replace JFXUtil.configureAndShowStage, most of rest with
   *       JFXAppLifecycle, remove deprecation warning suppression
   */
  @SuppressWarnings("deprecation")
  public static void configureAndShowStage( Stage stage, Scene scene, String title )
  {
    JFXUtil.configureAndShowStage(stage, scene, title, CSS_CONF_FILENAME);
  }

  private static boolean _launched = false;

  /**
   * Launches the given Node in the center of a new Stage, with default title and CSS
   */
  public static void launch( final Node node )
  {
    launch( node, DEFAULT_TITLE, CSS_CONF_FILENAME );
  }

  /**
   * Launches the given Node in the center of a new Stage.
   *
   * @todo Replace JFXUtil.configureAndShowStage, most of rest with
   *       JFXAppLifecycle, remove deprecation warning suppression
   */
  @SuppressWarnings("deprecation")
  public static void launch( final Node node, final String title, final String cssFile )
  {
    com.clarifi.reporting.Profiling p = com.clarifi.reporting.Profile.instance();
    Log.debug( p.summary() );
    Log.trace( p.fullTrace() );

    /** NOTE: this isn't 100% bulletproof threading wise
     as multiple calls in rapid succession could blow it up
     but for the purpose of testing in REPL it should work fine */
    if( !_launched )
    {
      Platform.setImplicitExit(false);
      Log.debug( "Launching..." );
      _launched = true;
      App._node = node;
      Thread thread = new Thread( "Launcher" )
      {
        @Override
        public void run()
        {
          try
          {
            Application.launch( App.class, new String[]{
              App.Args.TITLE_PARAM + "=" + title,
              App.Args.CSS_FILE + "=" + cssFile,
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
            JFXUtil.configureAndShowStage(stage, node, title, cssFile);
          }
          catch (Exception e)
          {
            Log.error("Failed in subsequent launch", e);
          }
        }
      } );
    }
  }

  public static Image gif( String name )
  {
    return image( name, "gif" );
  }

  public static Image png( String name )
  {
    return image( name, "png" );
  }

  private static Image image( String name, String extension )
  {
    File file = new File( CONF_FILENAME_ROOT + "images/" + name + '.' + extension );
    String url;
    if( file.isFile() )
    {
      try
      {
        url = file.toURI().toURL().toString();
      }
      catch( MalformedURLException murle )
      {
        Log.warn( "Failed to get valid URL from: " + file.getAbsolutePath(), murle );
        url = "b0mb";
      }
    }
    else
    {
      Log.warn( "Missing image file: " + file.getAbsolutePath() );
      url = "m1ss1ng";
    }
    return new Image( url );
  }
}
