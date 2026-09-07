module Algebra.Customer360 where

{- SIX SYSTEMS, SIX NAMES FOR THE SAME CUSTOMER: building one wide row out of
   sources that agree on nothing but the customer.

   Every operational system names the customer key differently -- `crmAccountId`
   in the CRM, `billingCustNo` in billing, `webUserId` on the web, and so on --
   and Ermine's `join` is a NATURAL join, so until the columns are made to agree
   nothing joins at all. Making them agree is the whole job, and the module that
   claims to do it does not work (see the note at the bottom).

   Sources (all keyed on the same customer under six different names):
     crmAccounts      (crmAccountId, accountName, accountSegment, ownerEmail)
     billingCustomers (billingCustNo, legalName, billingCountry, paymentTerms)
     webUsers         (webUserId, loginEmail, signupDate, marketingOptIn)
     supportSummary   (ticketCustomerRef, openTickets, lastTicketDate,
                       satisfaction)
     erpPartners      (partnerCode, taxId, creditLimitEur, blocked)
     loyaltyMembers   (loyaltyAccount, tierName, pointsBalance, enrolledDate)
   Lookup: countryNames (billingCountry -> countryDisplay), deliberately
           incomplete.

   The joined row is 19 columns wide (4 crm + 3 billing + 3 web + 3 erp +
   3 support + 3 loyalty; the six key columns collapse into one).

   Helpers used: alias, enrich, translate, semiJoin, antiJoin, dedupeBy,
                 groupSum.
   Stdlib exercised: `Relation.partialLookup` (no example used it before),
                 `Relation.rename`, `Relation.UnifyFields.unify1` (likewise),
                 `Relation.joinBy` as a spelled-out key assertion.

   SOLVER SHAPES. Six successive `alias` calls each cancel a CONCRETE
   left-hand side (the source's literal header) against a two-part partition,
   which is the `concrete` branch; the six results are then joined into a
   19-column row, so the final `joinBy` assertion is discharged against one of
   the widest concrete headers in this directory. `translate` (`partialLookup`)
   contributes a `coalesce'` whose `RUnion2` sits underneath a rename and an
   `except`.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/Customer360.e
     >> :import Algebra.Customer360
     >> customer360
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.UnifyFields as UF
import Syntax.Relation
import Algebra.Helpers

field customerId, crmAccountId, billingCustNo, webUserId : Int
field ticketCustomerRef, partnerCode, loyaltyAccount, openTickets : Int
field pointsBalance : Int
field accountName, accountSegment, ownerEmail : String
field legalName, billingCountry, paymentTerms, countryDisplay : String
field loginEmail, signupDate, marketingOptIn : String
field lastTicketDate, tierName, enrolledDate, taxId, blocked : String
field satisfaction, creditLimitEur, segmentCredit : Double

-- ------------------------------------------------------------- the sources

crmAccounts : [crmAccountId, accountName, accountSegment, ownerEmail]
crmAccounts = relation [
  { crmAccountId = 4001, accountName = "Aurora Retail",  accountSegment = "enterprise", ownerEmail = "kim@ex.com" },
  { crmAccountId = 4002, accountName = "Basalt Trading", accountSegment = "mid",        ownerEmail = "lee@ex.com" },
  { crmAccountId = 4003, accountName = "Cinder & Co",    accountSegment = "enterprise", ownerEmail = "kim@ex.com" },
  { crmAccountId = 4004, accountName = "Delta Works",    accountSegment = "smb",        ownerEmail = "rao@ex.com" }
]

billingCustomers : [billingCustNo, legalName, billingCountry, paymentTerms]
billingCustomers = relation [
  { billingCustNo = 4001, legalName = "Aurora Retail GmbH",   billingCountry = "DE", paymentTerms = "net30" },
  { billingCustNo = 4002, legalName = "Basalt Trading LLC",   billingCountry = "US", paymentTerms = "net45" },
  { billingCustNo = 4003, legalName = "Cinder en Co B.V.",    billingCountry = "NL", paymentTerms = "net30" },
  { billingCustNo = 4004, legalName = "Delta Works Ltd",      billingCountry = "GB", paymentTerms = "prepay" }
]

webUsers : [webUserId, loginEmail, signupDate, marketingOptIn]
webUsers = relation [
  { webUserId = 4001, loginEmail = "ops@aurora.example",  signupDate = "2023-02-11", marketingOptIn = "yes" },
  { webUserId = 4002, loginEmail = "buy@basalt.example",  signupDate = "2024-06-30", marketingOptIn = "no" },
  { webUserId = 4003, loginEmail = "post@cinder.example", signupDate = "2022-11-02", marketingOptIn = "yes" },
  { webUserId = 4004, loginEmail = "hq@delta.example",    signupDate = "2025-08-19", marketingOptIn = "no" }
]

-- support has no row for 4004: nobody there has raised a ticket yet
supportSummary : [ticketCustomerRef, openTickets, lastTicketDate, satisfaction]
supportSummary = relation [
  { ticketCustomerRef = 4001, openTickets = 2, lastTicketDate = "2026-01-03", satisfaction = 4.2 },
  { ticketCustomerRef = 4002, openTickets = 0, lastTicketDate = "2025-10-27", satisfaction = 4.9 },
  { ticketCustomerRef = 4003, openTickets = 7, lastTicketDate = "2026-01-19", satisfaction = 2.8 }
]

erpPartners : [partnerCode, taxId, creditLimitEur, blocked]
erpPartners = relation [
  { partnerCode = 4001, taxId = "DE811907980", creditLimitEur =  50000.0, blocked = "no" },
  { partnerCode = 4002, taxId = "US99-1234567", creditLimitEur = 120000.0, blocked = "no" },
  { partnerCode = 4003, taxId = "NL004495445B01", creditLimitEur = 25000.0, blocked = "yes" },
  { partnerCode = 4004, taxId = "GB123456789", creditLimitEur =   5000.0, blocked = "no" }
]

-- loyalty holds TWO rows for 4002: an old enrolment and a current one
loyaltyMembers : [loyaltyAccount, tierName, pointsBalance, enrolledDate]
loyaltyMembers = relation [
  { loyaltyAccount = 4001, tierName = "gold",   pointsBalance = 18400, enrolledDate = "2023-03-01" },
  { loyaltyAccount = 4002, tierName = "bronze", pointsBalance =   300, enrolledDate = "2024-07-01" },
  { loyaltyAccount = 4002, tierName = "silver", pointsBalance =  6100, enrolledDate = "2025-09-15" },
  { loyaltyAccount = 4003, tierName = "gold",   pointsBalance = 41250, enrolledDate = "2022-12-05" },
  { loyaltyAccount = 4004, tierName = "bronze", pointsBalance =    80, enrolledDate = "2025-08-20" }
]

-- ------------------------------------------------- step 1: agree on the key
--
-- `alias` is `Relation.rename` with a signature that says what it is for. Six
-- calls, six sources, one key name.

crm     = alias crmAccountId      customerId crmAccounts
billing = alias billingCustNo     customerId billingCustomers
web     = alias webUserId         customerId webUsers
support = alias ticketCustomerRef customerId supportSummary
erp     = alias partnerCode       customerId erpPartners
loyalty = alias loyaltyAccount    customerId loyaltyMembers

-- ------------------------------------ step 2: one row per customer per source
--
-- Loyalty has a history, not a state: keep the latest enrolment only. Note
-- what `dedupeBy` groups on and what it ranks by -- the ranking column must be
-- OUTSIDE the key, which is why `enrolledDate` cannot also be a key column.
currentLoyalty = dedupeBy {customerId} {enrolledDate} loyalty

-- ------------------------------------------- step 3: join, defaulting misses
--
-- Four of the six sources have a row for every customer, so a natural join is
-- honest for them. Support does not, so it gets `enrich` and a default record.

core4 = crm ** billing ** web ** erp

withSupport =
  enrich core4 support
    { openTickets = 0, lastTicketDate = "(never)", satisfaction = 0.0 }

customer360 = asMem withSupport ** currentLoyalty

-- ------------------------------- step 4: fold a lookup into an existing column
--
-- `translate` (`Relation.partialLookup`) REPLACES `billingCountry` with the
-- display name where the lookup has one and LEAVES THE RAW CODE where it does
-- not -- the result has the same header either way, which is what makes it
-- usable in the middle of a pipeline. "GB" is missing on purpose.
countryNames : [billingCountry, countryDisplay]
countryNames = relation [
  { billingCountry = "DE", countryDisplay = "Germany" },
  { billingCountry = "US", countryDisplay = "United States" },
  { billingCountry = "NL", countryDisplay = "Netherlands" }
]

displayed = translate billingCountry countryDisplay (asMem countryNames) customer360

-- ------------------------------------------ step 5: assert the key you meant
--
-- `joinOnExactly` fails to compile if the two operands share any column other
-- than `customerId`. Against a 19-column row that is a real assertion: add a
-- column to two sources under the same name and this line, not the report,
-- is where it is caught.
checkedJoin = joinOnExactly {customerId} (asMem core4) currentLoyalty

-- --------------------------------------------------------------- the answers

blockedCustomers = filterEq blocked "yes" erp
blockedButActive = semiJoin {customerId} (asMem blockedCustomers) customer360
neverLoggedIn    = antiJoin {customerId} web crm
creditBySegment  = rename creditLimitEur segmentCredit
                     (groupSum {accountSegment} creditLimitEur customer360)

{- ------------------------------------------------------------------------
   AND THE MODULE THAT WAS SUPPOSED TO DO ALL THIS.

   `Relation.UnifyFields` exports exactly one function:

       unify1 : (r <- (h,f,t), r2 <- (h,f2,t))
             => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]
       unify1 f1 f2 r r2 = join (rename f1 f2 (except {f2} r2)) r

   Read the constraints. `r2 <- (h, f2, t)` and `r <- (h, f, t)` share BOTH
   `h` and `t`, so the two operands must agree on every column but one each;
   and `f1` -- the column actually being renamed -- appears in no constraint at
   all. Feeding it the two sources this file exists to reconcile,

       unify1 crmAccountId customerId crm crmAccounts

   is rejected (measured 2026-09-06, `-Dermine.rowSound` on):

       Row partitions are unsatisfiable at field 'customerId':
       the whole contains it but no part does

   Every call that DOES check has the two operands at the same header, which
   makes it a semi-join of a relation against itself under a key alias -- the
   line below is the only shape that works, and it is not a unification. So
   this file uses `alias` (plain `rename`) six times instead, and the stdlib
   module stays exercised but unused.
   ------------------------------------------------------------------------ -}

selfAliasSemiJoin = unify1_UF customerId crmAccountId
                              (carry customerId crmAccountId crm)
                              (carry customerId crmAccountId crm)

-- ---------------------------------------------------------------- the report

customer360Report = vflow [
  atomShown "## Customer 360",
  atomShown "### One row per customer, twenty columns, six systems",
  tabular Nothing displayed,
  atomShown "### Customers ERP has blocked but the CRM still calls active",
  tabular Nothing blockedButActive,
  atomShown "### In the CRM, never seen on the web",
  tabular Nothing neverLoggedIn,
  atomShown "### Credit limit by CRM segment",
  tabular Nothing creditBySegment
]
