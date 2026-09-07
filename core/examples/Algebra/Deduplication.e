module Algebra.Deduplication where

{- LATEST RECORD WINS: deduplicating a change feed, and proving that nothing
   was lost while doing it.

   A change-data-capture feed carries every version of every customer record.
   Reporting wants one row per customer -- the newest -- and wants to be able
   to say exactly which rows it threw away and why.

   The interesting constraint is where the ranking column has to live.
   `groupBy` hands its group function only the NON-KEY part of the row, so a
   helper that ranks within a group needs `v <- (ord, o)`: the ordering column
   must be OUTSIDE the grouping key. Grouping by `(customerId, eventVersion)`
   and then ranking by `eventVersion` is not a runtime surprise, it is a type
   error -- see `shouldfail/alg04_dedupe_key_contains_order.e`.

   Table: custEvents (15 columns)
            eventId, customerId, eventVersion, eventTimestamp, sourceSystem,
            operation, emailAddress, phoneNumber, addressLine, postalCode,
            countryCode, loyaltyScore, tierBand, consentFlag, ingestBatch

   Helpers used: dedupeBy, groupTop, groupBottom, pickHighest, pickLowest,
                 exceptRows, semiJoin, antiJoin.
   Stdlib exercised: `Relation.firstBy` / `Relation.lastBy` (neither had an
                 example), `Relation.groupBy` with four different group
                 functions, `Relation.count` with the builtin `Count` field,
                 and `Relation.Sort.limit` through `topK` / `bottomK`.

   SOLVER SHAPES. `groupBy` is the one stdlib combinator that takes a
   FUNCTION between relations, so its two partitions (`kv <- (k,v)` and
   `kv2 <- (k,v2)`) are linked only through that function's type; four
   different group functions are instantiated against the same 15-column row
   here. `exceptRows` against the deduplicated result then makes the solver
   prove the 15-column header survived the round trip.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/Deduplication.e
     >> :import Algebra.Deduplication
     >> latest
     >> dedupeReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Algebra.Helpers

field eventId, customerId, eventVersion, loyaltyScore, ingestBatch : Int
field eventTimestamp, sourceSystem, operation, emailAddress : String
field phoneNumber, addressLine, postalCode, countryCode : String
field tierBand, consentFlag : String
field versionCount : Int

custEvents : [ eventId, customerId, eventVersion, eventTimestamp, sourceSystem
             , operation, emailAddress, phoneNumber, addressLine, postalCode
             , countryCode, loyaltyScore, tierBand, consentFlag, ingestBatch ]
custEvents = relation [
  { eventId = 1, customerId = 4001, eventVersion = 1, eventTimestamp = "2026-01-02T09:14Z", sourceSystem = "crm",  operation = "insert", emailAddress = "ops@aurora.example",   phoneNumber = "+49 30 111", addressLine = "Chausseestr 1",  postalCode = "10115", countryCode = "DE", loyaltyScore = 710, tierBand = "B", consentFlag = "yes", ingestBatch = 900 },
  { eventId = 2, customerId = 4001, eventVersion = 2, eventTimestamp = "2026-01-08T11:02Z", sourceSystem = "crm",  operation = "update", emailAddress = "ops@aurora.example",   phoneNumber = "+49 30 222", addressLine = "Chausseestr 1",  postalCode = "10115", countryCode = "DE", loyaltyScore = 718, tierBand = "B", consentFlag = "yes", ingestBatch = 902 },
  { eventId = 3, customerId = 4001, eventVersion = 3, eventTimestamp = "2026-01-19T16:40Z", sourceSystem = "web",  operation = "update", emailAddress = "billing@aurora.example", phoneNumber = "+49 30 222", addressLine = "Chausseestr 1", postalCode = "10115", countryCode = "DE", loyaltyScore = 718, tierBand = "A", consentFlag = "yes", ingestBatch = 907 },
  { eventId = 4, customerId = 4002, eventVersion = 1, eventTimestamp = "2026-01-03T08:00Z", sourceSystem = "crm",  operation = "insert", emailAddress = "buy@basalt.example",   phoneNumber = "+1 415 000", addressLine = "12 Market St",   postalCode = "94103", countryCode = "US", loyaltyScore = 640, tierBand = "C", consentFlag = "no",  ingestBatch = 900 },
  { eventId = 5, customerId = 4002, eventVersion = 2, eventTimestamp = "2026-01-11T13:25Z", sourceSystem = "erp",  operation = "update", emailAddress = "buy@basalt.example",   phoneNumber = "+1 415 001", addressLine = "12 Market St",   postalCode = "94103", countryCode = "US", loyaltyScore = 663, tierBand = "B", consentFlag = "no",  ingestBatch = 904 },
  { eventId = 6, customerId = 4003, eventVersion = 1, eventTimestamp = "2026-01-04T07:45Z", sourceSystem = "crm",  operation = "insert", emailAddress = "post@cinder.example",  phoneNumber = "+31 20 900", addressLine = "Keizersgracht 5", postalCode = "1015", countryCode = "NL", loyaltyScore = 802, tierBand = "A", consentFlag = "yes", ingestBatch = 901 },
  { eventId = 7, customerId = 4003, eventVersion = 2, eventTimestamp = "2026-01-12T10:10Z", sourceSystem = "web",  operation = "update", emailAddress = "post@cinder.example",  phoneNumber = "+31 20 901", addressLine = "Keizersgracht 5", postalCode = "1015", countryCode = "NL", loyaltyScore = 802, tierBand = "A", consentFlag = "no",  ingestBatch = 905 },
  { eventId = 8, customerId = 4003, eventVersion = 3, eventTimestamp = "2026-01-15T09:30Z", sourceSystem = "erp",  operation = "update", emailAddress = "post@cinder.example",  phoneNumber = "+31 20 901", addressLine = "Keizersgracht 5", postalCode = "1015", countryCode = "NL", loyaltyScore = 780, tierBand = "B", consentFlag = "no",  ingestBatch = 906 },
  { eventId = 9, customerId = 4003, eventVersion = 4, eventTimestamp = "2026-01-22T18:05Z", sourceSystem = "erp",  operation = "delete", emailAddress = "post@cinder.example",  phoneNumber = "+31 20 901", addressLine = "Keizersgracht 5", postalCode = "1015", countryCode = "NL", loyaltyScore = 780, tierBand = "B", consentFlag = "no",  ingestBatch = 908 },
  { eventId = 10, customerId = 4004, eventVersion = 1, eventTimestamp = "2026-01-06T12:00Z", sourceSystem = "web", operation = "insert", emailAddress = "hq@delta.example",     phoneNumber = "+44 20 700", addressLine = "9 Bank St",      postalCode = "E14",  countryCode = "GB", loyaltyScore = 590, tierBand = "D", consentFlag = "yes", ingestBatch = 903 }
]

-- ------------------------------------------------------------ latest wins
--
-- One row per customer: the highest `eventVersion`. `dedupeBy` is
-- `groupBy key (topK ord 1)` -- the whole row survives, not just the key and
-- the ranking column.
latest = dedupeBy {customerId} {eventVersion} custEvents

-- The first version of each customer, for the same price.
earliest = groupBottom {customerId} {eventVersion} 1 custEvents

-- The last three versions of each customer, which is what an audit trail
-- report actually wants.
recentThree = groupTop {customerId} {eventVersion} 3 custEvents

-- ------------------------------------------------- what deduplication dropped
--
-- The superseded rows: everything that is not the latest. `exceptRows` needs
-- both sides at the same 15-column header, and `latest` is a `Mem` while the
-- feed is a `Relation`, so one `asMem` is the price of the subtraction.
superseded = exceptRows (asMem custEvents) latest

-- and the same fact the other way round, as a check
supersededCount = groupBy {customerId} count superseded

-- ------------------------------------------------------- global first and last
--
-- `Relation.firstBy` and `Relation.lastBy` are NOT per-key: they take the top
-- row of the WHOLE relation. And the names are the opposite way round from
-- what one expects -- `firstBy` uses a DESCENDING limit, so it is the highest.
-- `pickHighest` / `pickLowest` say which is which.
mostRecentEventOfAll = pickHighest {ingestBatch} custEvents
firstEventOfAll      = pickLowest  {ingestBatch} custEvents

-- ---------------------------------------------------- how noisy is each source
--
-- `count` folds a group to the builtin `Count` field, so the result row is
-- (sourceSystem, Count) with no arithmetic anywhere.
eventsBySource = groupBy {sourceSystem} count custEvents
versionsPerCustomer = rename Count versionCount (groupBy {customerId} count custEvents)

-- --------------------------------------------------------- deletes and ghosts
--
-- A "delete" event means the latest row is a tombstone. The live set is the
-- deduplicated feed minus the tombstones; the ghosts are the customers whose
-- ONLY surviving row is a delete.
tombstones = semiJoin {eventId} (asMem (filterEq operation "delete" custEvents)) latest
liveRows   = exceptRows latest tombstones
-- Note what this returns: EVENT rows, not customers. The anti-join filters the
-- feed, and the feed is one row per version -- four rows for the two customers
-- the ERP never touched.
eventsOfCustomersErpNeverTouched =
  antiJoin {customerId} (filterEq sourceSystem "erp" custEvents) custEvents

-- ---------------------------------------------------------------- the report

dedupeReport = vflow [
  atomShown "## Change feed, deduplicated",
  atomShown "### Latest version per customer",
  tabular Nothing latest,
  atomShown "### First version per customer",
  tabular Nothing earliest,
  atomShown "### Last three versions per customer (the audit trail)",
  tabular Nothing recentThree,
  atomShown "### Rows deduplication dropped",
  tabular Nothing superseded,
  atomShown "### Versions per customer",
  tabular Nothing versionsPerCustomer,
  atomShown "### Events per source system",
  tabular Nothing eventsBySource,
  atomShown "### Live customers (latest row is not a delete)",
  tabular Nothing liveRows,
  atomShown "### Deleted customers",
  tabular Nothing tombstones,
  atomShown "### Feed events for the customers the ERP never touched",
  tabular Nothing eventsOfCustomersErpNeverTouched
]
