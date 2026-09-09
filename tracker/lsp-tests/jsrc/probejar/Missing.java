// LSP-FFI probe (tracker/LSP-FFI-TOLERANCE.md, finding P-1/P-7).
//
// This class is compiled and then DELETED by tracker/tools/build-probejar.sh,
// so the classes below load — or fail to — exactly the way a stale jar of the
// user's Scala 2 fork does: present classes whose supertype or whose member
// signatures name a type this JVM does not have.
package probejar;
public class Missing { public String tag() { return "missing"; } }
