module Environment.Sqlite where

import Bool
import Eq
import Function
import Layout using { harness; harness' }
import Layout.Report using type Report
import Layout.Writer using type Writer
import Runners using type Runner
import Scanners using { type Scanner; sqlite }
import String as S
import DB

private foreign
  function "com.clarifi.reporting.backends.Runners" "SQLite"
      sqliteRun : String -> Runner DB
  value "java.io.File" "separator" fileSeparator : String
  data "java.io.File" File
  data "java.net.URI" URI
  constructor file# : String -> File
  method "toURI" uriFromFile : File -> URI
  method "getPath" uriPath : URI -> String

type SqliteHarness o = (Scanner DB -> Runner DB -> Writer DB z) -> (Report DB z) -> IO o

memory : SqliteHarness ()
memory = harness sqlite (sqliteRun "jdbc:sqlite::memory:")

localFile : String -> SqliteHarness ()
localFile f = harness sqlite (sqliteRun $ "jdbc:sqlite::" ++_S sqliteFilePath f)

private
  sqliteFilePath : String -> String
  sqliteFilePath f = let uf = uriPath . uriFromFile . file# $ f
    in if (fileSeparator == "/" || (not ("/" == take_S 1 uf)))
          uf
          (drop_S 1 uf)
