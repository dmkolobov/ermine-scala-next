// As PresentMember, for `getField`: `OK` is fine, `GONE` is not, and the
// search resolves both.
package probejar;
public class PresentField {
  public static final String OK = "ok";
  public static Missing GONE = null;
}
