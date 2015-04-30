module Scanners where

import DB
import Internal.SMEnv
import Native.Function
import Vector
import Native.Record
import Relation

foreign
  data "com.clarifi.reporting.relational.Scanner" Scanner (f: * -> *)

  private
    data "com.clarifi.reporting.backends.Scanners$" ScannersModule
    value "com.clarifi.reporting.backends.Scanners$" "MODULE$" scannersModule : ScannersModule


  method "MySQLInnoDB" mySqlInnoDB# : ScannersModule -> SMEnv f -> Scanner f
  method "MySQL" mySql#: ScannersModule -> SMEnv f -> Scanner f
  method "Postgres" postgres#: ScannersModule -> SMEnv f -> Scanner f
  method "Vertica" vertica#: ScannersModule -> SMEnv f -> Scanner f
  method "SQLite" sqlite#: ScannersModule -> SMEnv f -> Scanner f
  method "MicrosoftSQLServer" sqlServer#: ScannersModule -> SMEnv f -> Scanner f
  method "MicrosoftSQLServer2005" sqlServer2005#: ScannersModule -> SMEnv f -> Scanner f

mySqlInnoDB = mySqlInnoDB# scannersModule
mySql = mySql# scannersModule
postgres = postgres# scannersModule
vertica = vertica# scannersModule
sqlite = sqlite# scannersModule
sqlServer = sqlServer# scannersModule
sqlServer2005 = sqlServer2005# scannersModule
