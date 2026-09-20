package com.clarifi.reporting
package backends

import java.sql.Connection

import relational._

import com.clarifi.reporting.sql.{ SqlEmitter }
import SqlMetadata.Schemata

object Backends {
  /** The `Scanner[DB]` a preview PROFILE names, and nothing else: the
    * dialect picks the EMITTER, the variant picks between the two scanners
    * one dialect has (JSON-WIDGET-PLAYGROUND §7.1).  Unlike
    * `RunnerConfig.backend` this opens nothing and loads no driver class --
    * a scanner is a pure emitter wrapper -- so the preview can build one
    * before it has a connection, and swap the connection underneath it
    * afterwards (`lsp/DelegatingRun.scala`).
    *
    * | dialect                 | variant          | scanner                                |
    * |-------------------------|------------------|----------------------------------------|
    * | sqlite                  | default          | `Scanners.SQLite`                      |
    * | mssql, sqlserver        | default          | `Scanners.MicrosoftSQLServer`          |
    * | mssql, sqlserver        | noTransactions   | `MicrosoftSQLServerNoTransactions`     |
    * | mysql                   | default          | `Scanners.MySQL`                       |
    * | postgres, postgresql    | default          | `Scanners.Postgres`                    |
    * | vertica                 | default          | `Scanners.Vertica`                     |
    *
    * The dialect names are `RunnerConfig.dialects`, spelled as
    * `RunnerConfig.backend` spells them, and the comparison is
    * case-insensitive for the dialect -- under `Locale.ROOT`, so a Turkish
    * locale does not fold `I` to a dotless one and lose `sqlite` -- and
    * EXACT for the variant (a settings key, not prose).  `noTransactions` exists for SQL Server alone --
    * `SqlEmitter` has one non-transactional emitter -- so it is REFUSED for
    * the others rather than silently read as `default`: a profile that asks
    * for it and does not get it would run transactions the operator
    * believed were off.  A `Left` is the message a profile refusal shows. */
  def scannerFor(dialect: String, variant: String,
                 sms: SMEnv[DB] = SMEnv.dummySmenv): Either[String, Scanner[DB]] =
    (dialect.toLowerCase(java.util.Locale.ROOT), variant) match {
      case ("sqlite", "default")                        => Right(Scanners.SQLite(sms))
      case ("mssql" | "sqlserver", "default")            => Right(Scanners.MicrosoftSQLServer(sms))
      case ("mssql" | "sqlserver", "noTransactions")     => Right(Scanners.MicrosoftSQLServerNoTransactions(sms))
      case ("mysql", "default")                          => Right(Scanners.MySQL(sms))
      case ("postgres" | "postgresql", "default")        => Right(Scanners.Postgres(sms))
      case ("vertica", "default")                        => Right(Scanners.Vertica(sms))
      case (d, v) =>
        if (!scannerDialects(d))
          Left("unknown dialect " + dialect + "; one of " + scannerDialects.toList.sorted.mkString(", "))
        else if (v == "noTransactions")
          Left("the " + dialect + " scanner has no noTransactions variant; " +
               "it is SQL Server's alone")
        else
          Left("unknown scanner variant " + variant + "; one of default, noTransactions")
    }

  /** The dialect names `scannerFor` knows, every spelling of each. */
  private val scannerDialects: Set[String] =
    Set("sqlite", "mssql", "sqlserver", "mysql", "postgres", "postgresql", "vertica")

  def MySQLInnoDB            = SqlBackend(SqlEmitter.mySqlInnoDBEmitter)
  def MySQL                  = SqlBackend(SqlEmitter.mySqlEmitter)
  def Postgres               = SqlBackend(SqlEmitter.postgreSqlEmitter)
  def Vertica                = SqlBackend(SqlEmitter.verticaSqlEmitter)
  def SQLite                 = SqlBackend(SqlEmitter.sqliteEmitter)
  def MicrosoftSQLServer     = SqlBackend(SqlEmitter.msSqlEmitter)
}

object Scanners {
  def MySQLInnoDB(sms: SMEnv[DB])            = new SqlScanner(sms)(SqlEmitter.mySqlInnoDBEmitter)
  def MySQL(sms: SMEnv[DB])                  = new SqlScanner(sms)(SqlEmitter.mySqlEmitter)
  def Postgres(sms: SMEnv[DB])               = new SqlScanner(sms)(SqlEmitter.postgreSqlEmitter)
  def Vertica(sms: SMEnv[DB])                = new SqlScanner(sms)(SqlEmitter.verticaSqlEmitter)
  def SQLite(sms: SMEnv[DB])                 = new SqlScanner(sms)(SqlEmitter.sqliteEmitter)
  def MicrosoftSQLServer(sms: SMEnv[DB])     = new SqlScanner(sms)(SqlEmitter.msSqlEmitter)
  def MicrosoftSQLServerNoTransactions(sms: SMEnv[DB])     = new SqlScanner(sms)(SqlEmitter.msSqlNonTransactionalEmitter)

  def cloudScanner(sms: SMEnv[DB]): Scanner[DB] = MicrosoftSQLServer(sms)
}

object Runners {
  def MySQL(url: String): Run[DB]              = DB.Run("org.gjt.mm.mysql.Driver")(url)
  def MicrosoftSQLServer(url: String): Run[DB] = DB.Run("com.microsoft.sqlserver.jdbc.SQLServerDriver")(url)
  def Vertica(url: String): Run[DB]            = DB.Run("com.vertica.Driver")(url)
  def SQLite(url: String): Run[DB]             = DB.Run("org.sqlite.JDBC")(url)
  def Postgres(url: String): Run[DB]           = DB.Run("org.postgresql.Driver")(url)

  def liteDB: Run[DB] = DB.sqliteTestDB

  def cloudDB: Run[DB] =
    // assumes TDS (ms sql) specified by system property
    DB.Run("net.sourceforge.jtds.jdbc.Driver")(System.getProperty("db.dev.ds.url"))

  def fromConnection(conn: Connection): Run[DB] = new RunDB {
    def run[A](a: DB[A]): A = try a(conn) finally { conn.close }
  }

  def fromPersistentConnection(conn: Connection): Run[DB] = new RunDB {
    def run[A](a: DB[A]): A = a(conn)
  }

  /** Database modules the Ermine console knows about. */
  def debugDatabases: PartialFunction[String, (String, DB[Schemata], Run[DB])] = Function unlift (_ => None)
}
