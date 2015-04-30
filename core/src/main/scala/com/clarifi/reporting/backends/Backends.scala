package com.clarifi.reporting
package backends

import java.sql.Connection

import scalaz.{Source => _, _}
import Scalaz._

import com.clarifi.reporting.Reporting._
import relational._

import com.clarifi.reporting.sql.{ SqlEmitter }
import SqlMetadata.{Schemata, schemata}

object Backends {
  def MySQLInnoDB            = SqlBackend(SqlEmitter.mySqlInnoDBEmitter)
  def MySQL                  = SqlBackend(SqlEmitter.mySqlEmitter)
  def Postgres               = SqlBackend(SqlEmitter.postgreSqlEmitter)
  def Vertica                = SqlBackend(SqlEmitter.verticaSqlEmitter)
  def SQLite                 = SqlBackend(SqlEmitter.sqliteEmitter)
  /** Pre 2008, SQL server did not have a separate date type, only datetime. */
  def MicrosoftSQLServer2005 = SqlBackend(SqlEmitter.msSqlEmitter2005)
  def MicrosoftSQLServer     = SqlBackend(SqlEmitter.msSqlEmitter)
}

object Scanners {
  def MySQLInnoDB(sms: SMEnv[DB])            = new SqlScanner(sms)(SqlEmitter.mySqlInnoDBEmitter)
  def MySQL(sms: SMEnv[DB])                  = new SqlScanner(sms)(SqlEmitter.mySqlEmitter)
  def Postgres(sms: SMEnv[DB])               = new SqlScanner(sms)(SqlEmitter.postgreSqlEmitter)
  def Vertica(sms: SMEnv[DB])                = new SqlScanner(sms)(SqlEmitter.verticaSqlEmitter)
  def SQLite(sms: SMEnv[DB])                 = new SqlScanner(sms)(SqlEmitter.sqliteEmitter)
  /** Pre 2008, SQL server did not have a separate date type, only datetime. */
  def MicrosoftSQLServer2005(sms: SMEnv[DB]) = new SqlScanner(sms)(SqlEmitter.msSqlEmitter2005)
  def MicrosoftSQLServer(sms: SMEnv[DB])     = new SqlScanner(sms)(SqlEmitter.msSqlEmitter)

  def cloudScanner(sms: SMEnv[DB]): Scanner[DB] = MicrosoftSQLServer2005(sms)
}

object Runners {
  def MySQL(url: String): Run[DB]              = DB.Run("org.gjt.mm.mysql.Driver")(url)
  def MicrosoftSQLServer(url: String): Run[DB] = DB.Run("com.microsoft.sqlserver.jdbc.SQLServerDriver")(url)
  def Vertica(url: String): Run[DB]            = DB.Run("com.vertica.Driver")(url)
  def SQLite(url: String): Run[DB]             = DB.Run("org.sqlite.JDBC")(url)
  def Postgres(url: String): Run[DB]           = DB.Run("org.postgresql.Driver")(url)

  def liteDB: Run[DB] = DB.sqliteTestDB

  def cloudDB: Run[DB] = {
    // lets user supply username and password via system properties, otherwise uses windows authentication
    val user     = System.getProperty("db.dev.user")
    val password = System.getProperty("db.dev.password")
    val url      = System.getProperty("db.dev.ds.url")
    val pwConnectString = ";user=%s;password=%s".format(user,password)
    val connectUrl = url + (if (!(user eq null) && !(password eq null)) pwConnectString else "")
    DB.Run("net.sourceforge.jtds.jdbc.Driver")(connectUrl)
  }

  def fromConnection(conn: Connection): Run[DB] = new Run[DB] {
    def run[A](a: DB[A]): A = try a(conn) finally { conn.close }
  }

  def fromPersistentConnection(conn: Connection): Run[DB] = new Run[DB] {
    def run[A](a: DB[A]): A = a(conn)
  }

  /** Database modules the Ermine console knows about. */
  def debugDatabases: PartialFunction[String, (String, DB[Schemata], Run[DB])] = Function unlift (_ => None)
}
