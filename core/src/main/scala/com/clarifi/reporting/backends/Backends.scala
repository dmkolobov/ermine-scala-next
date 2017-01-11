package com.clarifi.reporting
package backends

import java.sql.Connection

import relational._

import com.clarifi.reporting.sql.{ SqlEmitter }
import SqlMetadata.Schemata

object Backends {
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
