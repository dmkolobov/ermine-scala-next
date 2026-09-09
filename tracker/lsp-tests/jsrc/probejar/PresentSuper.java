// Loading this class needs its SUPERCLASS, which is not there:
// Class.forName throws NoClassDefFoundError (an Error, not an Exception).
package probejar;
public class PresentSuper extends Missing {
  public static String shout(String s) { return s.toUpperCase(); }
}
