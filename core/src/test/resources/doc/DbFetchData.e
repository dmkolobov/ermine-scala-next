module DbFetchData where

-- The DB-backed twin of FetchData (DB-PLAN D7/D8, tracker/db/REPORTS.md):
-- the same two exported relations, `sales` and `targets`, with the same
-- field names and types, but as `table` statements, so a report that
-- imports this module scans the database the runner is CONNECTED to
-- instead of a `VALUES` literal.  The data comes from the views of the
-- same names in ErmineSales (tracker/db/SCHEMA-SALES.md §2, loaded by
-- `scripts/db.sh load sales --tier T`) or from the SQLite twin the loader
-- writes (D13).  At tier xs both hold exactly FetchData's literal rows:
-- north 4350.75, south 2605.75, east 4175.5, west 1550.0, all 12682.0.
--
-- Bare names, no `database "..."` block: the connection decides the
-- database, MSSQL resolves `sales` through the login's default schema dbo,
-- and SQLite would read `dbo.sales` as an attached database
-- (SCHEMA-SALES.md §7).  The field types are the contract's `ermine`
-- values exactly (data/schema/sales.contract.json); a mismatch fails at
-- scan time, not at compile time.

import Date
import Relation

field region : String
field day    : Date
field amount : Double
field units  : Int
field target : Double

table sales   : [region, day, amount, units]
table targets : [region, target]
