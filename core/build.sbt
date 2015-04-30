scalacOptions ~= (so => (so filterNot Set("-unchecked", "-Xlint"))
                    ++ Seq("-Ywarn-nullary-override", "-Ywarn-inaccessible"))

name := "ermine-scala-core"

//logLevel := Level.Debug

// We're still using scala-iterv; we know, so stop telling us.
logManager in Compile ~= {coreLogMgr =>
  filterLogs(coreLogMgr){coreLog =>
    val suppress = new java.util.concurrent.atomic.AtomicInteger(0)
    def zero(n:Int) = suppress.compareAndSet(n, 0)
    (level, message) => {
      suppress.decrementAndGet() match {
        case n if message endsWith "in package scalaz is deprecated: Scalaz 6 compatibility. Migrate to scalaz.iteratee." =>
          suppress.compareAndSet(n, 2)
        case 1 if level == Level.Warn => ()
        case 0 if level == Level.Warn && (message endsWith "^") => ()
        case n if coreLog atLevel level =>
          zero(n)
          coreLog.log(level, message)
        case n => zero(n)
      }
    }
  }
}
