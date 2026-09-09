// This class LOADS.  `getMethod` resolves the signatures of every public
// method while it searches, so looking up the perfectly healthy `ok`
// throws NoClassDefFoundError because `bad` returns the absent class.
package probejar;
public class PresentMember {
  public static String ok(String s) { return s; }
  public static Missing bad() { return null; }
}
