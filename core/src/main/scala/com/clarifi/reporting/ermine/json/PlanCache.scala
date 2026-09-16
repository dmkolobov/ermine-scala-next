package com.clarifi.reporting.ermine.json

import java.time.Instant
import java.security.SecureRandom

/** Where a deferred relation waits for its re-request (design note §3.4a,
  * the v1 token: "a random id keyed to a server-side cache of the plan with a
  * TTL").  `put` mints a token for a relation node and answers it with the
  * instant it stops resolving; `get` answers the entry while `now` is before
  * that instant.  The relation is kept as its PLAN (`Doc.Data`: the `Ext`,
  * its columns, order and path), so a re-request scans it afresh. */
trait PlanCache {
  def put(data: Doc.Data): (String, Instant)
  def get(token: String, now: Long): Option[PlanCache.Entry]
}

object PlanCache {
  final case class Entry(token: String, data: Doc.Data, expires: Instant)

  private val encoder = java.util.Base64.getUrlEncoder.withoutPadding

  /** 128 random bits, base64url without padding: 22 characters. */
  def token(random: SecureRandom): String = {
    val bytes = new Array[Byte](16)
    random.nextBytes(bytes)
    encoder.encodeToString(bytes)
  }
}

/** The in-process `PlanCache`.  Thread-safe (every operation holds the
  * instance's monitor).
  *
  *  - A token expires `ttlMillis` after `clock()` at its `put`; it resolves
  *    while `now < expires` and `get` at or after `expires` answers `None`
  *    and evicts the entry.
  *  - Bounded: past `maxEntries` the OLDEST entries (by `put` order) are
  *    evicted.  `put` also drops the expired entries at the old end first,
  *    so an idle cache does not pin plans past their expiry.
  *  - Tokens are unique among the live entries (a collision of 128 random
  *    bits is re-drawn, not trusted to be impossible). */
final class MemoryPlanCache(ttlMillis: Long, maxEntries: Int, clock: () => Long, random: SecureRandom)
    extends PlanCache {
  require(ttlMillis > 0L, "a time to live is positive")
  require(maxEntries > 0, "a cache holds at least one entry")

  import PlanCache.Entry

  // insertion order: the eldest entry first
  private val entries = new java.util.LinkedHashMap[String, Entry]()

  def put(data: Doc.Data): (String, Instant) = synchronized {
    val now = clock()
    dropExpired(now)
    var t = PlanCache.token(random)
    while (entries.containsKey(t)) t = PlanCache.token(random)
    val e = Entry(t, data, Instant.ofEpochMilli(now + ttlMillis))
    entries.put(t, e)
    while (entries.size > maxEntries) {
      val it = entries.keySet.iterator
      it.next()
      it.remove()
    }
    (t, e.expires)
  }

  def get(token: String, now: Long): Option[Entry] = synchronized {
    val e = entries.get(token)
    if (e == null) None
    else if (now >= e.expires.toEpochMilli) { entries.remove(token); None }
    else Some(e)
  }

  def size: Int = synchronized(entries.size)

  /** The live tokens, eldest first (for tests and diagnostics). */
  def tokens: List[String] = synchronized {
    val b = new scala.collection.mutable.ListBuffer[String]
    val it = entries.keySet.iterator
    while (it.hasNext) b += it.next()
    b.toList
  }

  private def dropExpired(now: Long): Unit = {
    val it = entries.values.iterator
    var going = true
    while (going && it.hasNext) {
      if (now >= it.next().expires.toEpochMilli) it.remove()
      else going = false
    }
  }
}
