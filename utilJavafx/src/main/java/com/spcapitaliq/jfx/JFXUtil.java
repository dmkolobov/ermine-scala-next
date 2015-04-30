package com.spcapitaliq.jfx;

import java.io.File;
import java.net.MalformedURLException;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import com.spcapitaliq.jfx.node.NodeTraverser;
import com.sun.javafx.css.StyleManager;
import javafx.application.Platform;
import javafx.beans.InvalidationListener;
import javafx.beans.Observable;
import javafx.beans.property.ObjectProperty;
import javafx.beans.value.ChangeListener;
import javafx.beans.value.ObservableValue;
import javafx.collections.ListChangeListener;
import javafx.collections.ObservableList;
import javafx.concurrent.Task;
import javafx.concurrent.WorkerStateEvent;
import javafx.event.EventHandler;
import javafx.geometry.Bounds;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.layout.BorderPaneBuilder;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.stage.Window;
import org.apache.log4j.Logger;
import org.apache.log4j.PropertyConfigurator;

/**
 *
 * @author mmorton
 *
 */
public final class JFXUtil
{
  private static final Logger _log = Logger.getLogger(JFXUtil.class);

  private JFXUtil()
  {
    /** static only */
  }

  public static void throwIfApplicationThread()
  {
    if( Platform.isFxApplicationThread() )
      throw new UnsupportedOperationException( "This operation must NOT be performed on the Platform's event thread" );
  }

  public static void throwIfNotApplicationThread()
  {
    if( !Platform.isFxApplicationThread() )
      throw new UnsupportedOperationException( "This operation must be performed on the Platform's event thread" );
  }

  /**
   * Convenience method to throw NPE if test object is null
   *
   * @param required
   * @param name
   */
  public static void throwIfNull(Object required, String name)
  {
    if(null == required)
      throw new NullPointerException(name + " must not be null");
  }

  /**
   * Guarantee the provided {@link Runnable} is run on the JFX Platform event
   * thread. If the calling thread is already the event thread then logic is run
   * from this thread. Otherwise {@link Platform#runLater(Runnable)} is used.
   *
   * Note: if not called by the Platform thread this method returns immediately.
   * To block until the logic completes, see {@link RunLaterWaiter}.
   *
   * @param logic
   */
  public static void runSafe( Runnable logic )
  {
    if( Platform.isFxApplicationThread() )
      logic.run();
    else
      Platform.runLater( logic );
  }

  private static class RunAndWait implements Runnable
  {
    private final Runnable _logic;

    RunAndWait(Runnable logic)
    {
      _logic = logic;
    }

    void go()
    {
      synchronized(this)
      {
        Platform.runLater(this);
        try
        {
          wait();
        }
        catch (InterruptedException e)
        {
          // TODO Auto-generated catch block
          e.printStackTrace();
        }
      }
    }

    @Override
    public void run()
    {
      try
      {
        _logic.run();
      }
      catch (Throwable t)
      {
        _log.error("_logic unexpectedly fail", t);
      }
      finally
      {
        synchronized (this)
        {
          notify();
        }
      }
    }
  }

  public static void runSafeAndWait( Runnable logic )
  {
    if( Platform.isFxApplicationThread() )
      logic.run();
    else
    {
      new RunAndWait(logic).go();
    }
  }

  private static Map<String, Integer> _classCounters = new HashMap<String, Integer>();

  /**
   * Generates a unique name for the given {@link Class} by maintaining a
   * counter per concrete class name.
   *
   * @param clazz
   * @return
   */
  public static String generateUniqueName( Class<?> clazz )
  {
    synchronized( _classCounters )
    {
      String classname = clazz.getName();
      Integer count = _classCounters.get( classname );
      boolean hasCount = null != count;
      if( hasCount )
      {
        count = Integer.valueOf( count.intValue() + 1 );
      }
      else
      {
        count = Integer.valueOf( 0 );
      }

      _classCounters.put( classname, count );

      StringBuilder name = new StringBuilder( classname );
      if( hasCount )
      {
        name.append( ' ' ).append( count.intValue() );
      }
      return name.toString();
    }
  }

  /**
   * Because sometimes operations happen so fast the User doesn't
   * notice any activity.  This method will sleep at least as long
   * as minimumPause.  If more time has passed since the given
   * referenceTime this method will not sleep at all.
   *
   * @param referenceTime the original time to measure from
   * @param minimumPause the minimum milliseconds to wait
   */
  public static void provideMinimumPause( long referenceTime, long minimumPause )
  {
    throwIfApplicationThread();

    long currentTime = System.currentTimeMillis();
    long elapsedTime = currentTime - referenceTime;
    if( elapsedTime < minimumPause )
    {
      try
      {
        Thread.sleep( minimumPause - elapsedTime );
      }
      catch( InterruptedException ie )
      {
        _log.warn( "generatePause interrupted", ie );
      }
    }
  }

  /**
   * Convenience method that sleeps for the given pause.
   *
   * @param pause the number of milliseconds to wait.
   */
  public static void providePause( long pause )
  {
    provideMinimumPause( System.currentTimeMillis(), pause );
  }

  /**
   * For use when layouts are misbehaving and not recognizing their preferred sizes correctly.
   * If resizing the window or switching tabs gets the layout to be correct, try calling this
   * method. It walks up the through the parents from the given node to the top of the
   * scene. Each parent visited requests a layout. The root then performs the layout.
   *
   * @param node
   */
  public static void forceValidate( Node node )
  {
    Parent parent = node.getParent();
    while(null != parent)
    {
      parent.requestLayout();
      Parent grandParent = parent.getParent();
      if(null == grandParent)
        parent.layout();
      parent = grandParent;
    }
  }

  /**
   * Replace ' ' with '\n' to get the original text to wrap according to the availWidth.
   * The control is passed in for its font.
   *
   * @param original
   * @param control
   * @param availWidth
   * @return
   */
  public static String wrap( String original, Label control, double availWidth )
  {
    if( original.indexOf(' ') == -1 )
      return original;
    StringTokenizer sToke = new StringTokenizer(original, " ");
    List<String> tokens = new ArrayList<String>();
    while( sToke.hasMoreTokens() )
      tokens.add(sToke.nextToken());

    Text l = new Text(" ");
    l.setFont(control.getFont());
    l.snapshot(null, null);
    double spaceW = l.getLayoutBounds().getWidth();

    double w = 0;
    StringBuilder converted = new StringBuilder( original.length() );
    for( Iterator<String> i = tokens.iterator(); i.hasNext(); )
    {
      String token = i.next();
      l.setText(token);
      l.snapshot(null,  null);
      double lW = l.getLayoutBounds().getWidth();
      if( w == 0 ) // beginning of first line
      {
        converted.append(token);
        w += lW;
      }
      else
      {
        if( w + spaceW + lW > availWidth ) // wrap
        {
          converted.append('\n').append(token);
          w = lW + spaceW;
        }
        else
        {
          converted.append(' ').append(token);
          w += spaceW + lW;
        }
      }
    }

    return converted.toString();
  }

  private static abstract class AbstractSlayer<L>
  {
    private L _slain = null;

    @SuppressWarnings("unchecked")
    @Override
    public boolean equals(Object o)
    {
      _slain = (L)o;
      return true;
    }

    L getSlain()
    {
      return _slain;
    }
  }

  private static class ChangeSlayer<T> extends AbstractSlayer<ChangeListener<T>> implements ChangeListener<T>
  {
    @Override
    public void changed(ObservableValue<? extends T> paramObservableValue, T paramT1, T paramT2)
    {
      throw new UnsupportedOperationException();
    }
  }

  public static <T> List<ChangeListener<T>> displace( ObjectProperty<T> prop, ChangeListener<T> listener )
  {
    List<ChangeListener<T>> slain = new LinkedList<ChangeListener<T>>();
    boolean moreToSlay = true;
    while( moreToSlay )
    {
      ChangeSlayer<T> slayer = new ChangeSlayer<T>();
      prop.removeListener(slayer);
      ChangeListener<T> target = slayer.getSlain();
      if( null != target )
      {
        _log.trace("Displaced: " + target + " from: " + prop);
        slain.add( target );
      }
      else
        moreToSlay = false;
    }
    prop.addListener(listener);
    return slain;
  }

  private static class ListChangeSlayer<T> extends AbstractSlayer<ListChangeListener<T>> implements ListChangeListener<T>
  {
    @Override
    public void onChanged(ListChangeListener.Change<? extends T> paramChange)
    {
      throw new UnsupportedOperationException();
    }
  }

  public static <T> List<ListChangeListener<T>> displace( ObservableList<T> list, ListChangeListener<T> listener )
  {
    List<ListChangeListener<T>> slain = new LinkedList<ListChangeListener<T>>();
    boolean moreToSlay = true;
    while( moreToSlay )
    {
      ListChangeSlayer<T> slayer = new ListChangeSlayer<T>();
      list.removeListener(slayer);
      ListChangeListener<T> target = slayer.getSlain();
      if( null != target )
      {
        _log.trace("Displaced: " + target + " from: " + list);
        slain.add( target );
      }
      else
        moreToSlay = false;
    }
    list.addListener(listener);
    return slain;
  }

  private static class InvalidationSlayer extends AbstractSlayer<InvalidationListener> implements InvalidationListener
  {
    @Override
    public void invalidated(Observable paramObservable)
    {
      throw new UnsupportedOperationException();
    }
  }

  public static List<InvalidationListener> displace( ObjectProperty<?> prop, InvalidationListener listener )
  {
    List<InvalidationListener> slain = new LinkedList<InvalidationListener>();
    boolean moreToSlay = true;
    while( moreToSlay )
    {
      InvalidationSlayer slayer = new InvalidationSlayer();
      prop.removeListener(slayer);
      InvalidationListener target = slayer.getSlain();
      if( null != target )
      {
        _log.trace("Displaced: " + target + " from: " + prop);
        slain.add( target );
      }
      else
        moreToSlay = false;
    }
    prop.addListener(listener);
    return slain;
  }

  private static class SetOnFirstSizedAdapter implements ChangeListener<Bounds>
  {
    private final Node _node;
    private final Runnable _response;

    private boolean _fired = false;

    SetOnFirstSizedAdapter(Node node, Runnable response)
    {
      _node = node;
      _response = response;
    }

    @Override
    public void changed( ObservableValue<? extends Bounds> obsVal, Bounds oldVal, Bounds newVal )
    {
      if( _fired )
      {
        _log.warn("Prevented redundant firing");
        return;
      }
      _log.trace(this.toString() + " changed: " + newVal);
      if( newVal.getWidth() != 0 )
      {
        /** remove the listener b/c it's only used once */
        _fired = true;
        _node.boundsInLocalProperty().removeListener( this );
        _log.trace( "Responding to first show for: " + _node );
        try
        {
          _response.run();
        }
        catch( Exception e )
        {
          _log.error( "Failed to run response:" + _response, e );
        }
      }
    }
  }

  private static class SetOnFirstSizedSlayer implements ChangeListener<Bounds>
  {
    @Override
    public void changed(final ObservableValue<? extends Bounds> observableValue, final Bounds bounds, final Bounds bounds2)
    {
      throw new UnsupportedOperationException("Only used to slay");
    }

    public boolean equals(Object o)
    {
      boolean equals = o instanceof SetOnFirstSizedAdapter;
      if(equals)
        _log.debug("SetOnFirstSizedSlayer activated");
      return equals;
    }
  }

  public static void setOnFirstSized( final Node node, final Runnable response )
  {
    node.boundsInLocalProperty().addListener( new SetOnFirstSizedAdapter(node, response) );
  }

  public static void clearAllSetOnFirstSized(Parent root)
  {
    throwIfNotApplicationThread();

    class SlayerTrav extends SetOnFirstSizedSlayer implements NodeTraverser.Strategy
    {
      @Override
      public boolean isActionable(final Node node)
      {
        return true;
      }

      @Override
      public void apply(final Node node)
      {
        node.boundsInLocalProperty().removeListener(this);
      }
    }

    NodeTraverser.traverse(root, new SlayerTrav());
  }

  /**
   * Some operations, like adding a tooltip should only happen on the
   * event thread. If the calling thread is not then the logic will get
   * added to run when the given node is first sized.
   * @param node
   * @param logic
   */
  public static void runIfSafeOrOnFirstSized(final Node node, final Runnable logic)
  {
    if (!Platform.isFxApplicationThread())
    {
      JFXUtil.setOnFirstSized(node, new Runnable()
      {
        @Override
        public void run()
        {
          logic.run();
        }
      });
    }
    else
    {
      try
      {
        logic.run();
      }
      catch(Exception e)
      {
        _log.error("Failed to run logic safely", e);
      }
    }
  }

  /**
   * A utility to handle multiple tasks submitted from UI actions.  When a task
   * is first submitted, it is run immediately.  If another task is submitted,
   * it is deferred until the first completes (or is canceled).  If multiple
   * tasks are submitted while one is running, only the latest one is kept.
   *
   * @author MSP
   */
  public static class TaskBuffer
  {
    private final Object _lock;
    private final ExecutorService _threadPool = Executors.newSingleThreadExecutor();
    private final EventHandler<WorkerStateEvent> _callback;

    private Task<?> _current;
    private Task<?> _deferred;

    /**
     * Creates a new TaskBuffer with a given lock
     * @param lock an Object used as a synchronization lock
     */
    public TaskBuffer(Object lock)
    {
      _lock = lock;

      _callback = new EventHandler<WorkerStateEvent>()
      {
        @Override
        public void handle(WorkerStateEvent wse)
        {
          synchronized(_lock)
          {
            _current = _deferred;
            _deferred = null;
            if (_current != null)
            {
              addCallbacksAndSubmit(_current);
            }
          }
        }
      };
    }

    /**
     * Submits a new task.  If nothing is running, the task is run
     * immediately.  Otherwise it is deferred and run when the task
     * completes.
     * @param task the task to run or defer
     */
    public void submit(Task<?> task)
    {
      synchronized(_lock)
      {
        if (_current == null)
        {
          _current = task;
          addCallbacksAndSubmit(_current);
        }
        else
        {
          _deferred = task;
        }
      }
    }

    /**
     * Cancels the currently running task (if any), and runs the deferred
     * task (if any).
     */
    public void cancelCurrent()
    {
      synchronized(_lock)
      {
        if (_current != null)
        {
          _current.cancel();
          // deferred gets called via the onCancelled callback
        }
      }
    }

    /**
     * Cancels any pending task.  Doesn't touch the currently running task.
     */
    public void cancelPending()
    {
      synchronized(_lock)
      {
        _deferred = null;
      }
    }

    /**
     * Cancels all tasks
     */
    public void cancelAll()
    {
      synchronized(_lock)
      {
        _deferred = null;
        if (_current != null)
          _current.cancel();
      }
    }

    private void addCallbacksAndSubmit(Task<?> task)
    {
      task.onCancelledProperty().setValue(_callback);
      task.onFailedProperty().setValue(_callback);
      task.onSucceededProperty().setValue(_callback);
      _threadPool.submit(task);
    }
  }

  /**
   * Initializes log4j given a path to the property file.
   *
   * @param log4jConfigFilename
   */
  public static void initLogging(String log4jConfigFilename)
  {
    try
    {
      PropertyConfigurator.configure(log4jConfigFilename);
      _log.debug("Logging configured");
    }
    catch (Exception e)
    {
      /**
       * One of the few places to print an exception to STDERR because log4j is
       * not available.
       */
      System.err.println("Failed to configure log4j");
      e.printStackTrace();
    }
  }

  public static void loadCSS( Scene scene, String cssFile )
  {
    if(null == cssFile)
    {
      _log.info("No cssFile was provided.");
      return;
    }
    File file = new File( cssFile );
    if( file.isFile() )
    {
      try
      {
        String cssSource = file.toURI().toURL().toString();
        _log.debug( "Loading CSS from: " + cssSource );
        scene.getStylesheets().add( cssSource );
        StyleManager.getInstance().reloadStylesheets( scene );
      }
      catch( MalformedURLException murle )
      {
        _log.warn( "Failed to add style sheet: " + file.getAbsolutePath(), murle );
      }
    }
    else
    {
      _log.warn( "Style sheet file is missing: " + file.getAbsolutePath() );
    }
  }

  @Deprecated
  public static void configureAndShowStage( Stage stage, Scene scene, String title, String cssFile )
  {
    stage.setTitle( title );

    loadCSS( scene, cssFile );
    stage.setScene( scene );

    Window window = scene.getWindow();
    window.centerOnScreen();

    stage.show();
  }

  @Deprecated
  public static void configureAndShowStage( Stage stage, Node node, String title, String cssFile )
  {
    stage.setTitle( title );

    Parent parent = BorderPaneBuilder.create().center(node).build();

    if( _log.isDebugEnabled() )
    {
      _log.debug("Overlaying debug tools");
      parent = JFXDebug.overlayDebugTools(parent);
    }

    Scene scene = new Scene( parent );
    configureAndShowStage(stage, scene, title, cssFile);
  }
}