module Scanners where

import DB
import Internal.SMEnv
import Native.Function
import Vector
import Native.Record
import Relation
import Relation.Sort
import Native.Relation
import Native.List

foreign
  data "com.clarifi.reporting.relational.Scanner" Scanner (f: * -> *)
  method "dumpClosed" dumpQuery# : Scanner f -> Relation# -> Sort# -> IO String 

  private
    data "com.clarifi.reporting.backends.Scanners$" ScannersModule
    value "com.clarifi.reporting.backends.Scanners$" "MODULE$" scannersModule : ScannersModule


  method "MySQLInnoDB" mySqlInnoDB# : ScannersModule -> SMEnv f -> Scanner f
  method "MySQL" mySql#: ScannersModule -> SMEnv f -> Scanner f
  method "Postgres" postgres#: ScannersModule -> SMEnv f -> Scanner f
  method "Vertica" vertica#: ScannersModule -> SMEnv f -> Scanner f
  method "SQLite" sqlite#: ScannersModule -> SMEnv f -> Scanner f
  method "MicrosoftSQLServer" sqlServer#: ScannersModule -> SMEnv f -> Scanner f

mySqlInnoDB = mySqlInnoDB# scannersModule
mySql = mySql# scannersModule
postgres = postgres# scannersModule
vertica = vertica# scannersModule
sqlite = sqlite# scannersModule
sqlServer = sqlServer# scannersModule

dumpQueryInOrder : (Relational rel) => Scanner f -> rel r -> Sort r -> IO String
dumpQueryInOrder s r o = dumpQuery# s (relation# r) (toSort# o)

dumpQuery : (Relational rel) => Scanner f -> rel r -> IO String
dumpQuery s r = dumpQuery# s (relation# r) (toList# Nil)
