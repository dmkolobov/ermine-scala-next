#!/usr/bin/env node
// ONE SOURCE for the ErmineSales schema (tracker/db/SCHEMA-SALES.md, DB-PLAN S1).
// Writes, next to itself:
//   sales.contract.json   the column contract the generator and loaders consume
//   sales.mssql.sql       idempotent T-SQL DDL (tables, views, indexes)
//   sales.sqlite.sql      idempotent SQLite DDL, the D13 twin
//   sales.smoke.sql       T-SQL smoke (counts + the Fetch totals)
//   sales.smoke.sqlite.sql  the same smoke in SQLite
// Edit THIS file, then `node data/schema/build-sales-schema.mjs`; never hand-edit the outputs.
// Plain node (no deps, no TypeScript build) so the schema does not wait on data/'s toolchain.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------- type map
// SURVEY-CORPUS §5 (MEASURED): Int->int, Double->float, String->nvarchar,
// Date->date (read with getDate(x, GMT)). SQLite column types are what
// SqliteEmitter.sqlTypeName writes for the same Ermine type
// (SqlEmitter.scala:717-728): Int integer, Double real, String text,
// Date integer (EPOCH MILLISECONDS; its Date literal is d.getTime, :696).
const T = {
  Int:    { mssql: 'int',   sqlite: 'INTEGER' },
  Double: { mssql: 'float', sqlite: 'REAL' },
  Date:   { mssql: 'date',  sqlite: 'INTEGER' },
  String: (n) => ({ mssql: `nvarchar(${n})`, sqlite: 'TEXT', maxLength: n }),
};

// col(name, ermineType, sqlType, hint, opts)
function col(name, ermine, sql, hint, opts = {}) {
  const nullable = !!opts.nullable;
  return {
    name,
    ermine: nullable ? `Nullable ${ermine}` : ermine,
    mssql: sql.mssql,
    sqlite: sql.sqlite,
    ...(sql.maxLength ? { maxLength: sql.maxLength } : {}),
    nullable,
    hint,
  };
}
const S = T.String;

// ---------------------------------------------------------------- tiers
// D11: xs = exactly today's literal rows; s ~1k fact rows; m ~100k; l ~2M.
const tiers = {
  xs: { factRows: 8, dateRange: 'literal', note: 'exactly the Doc fixture literals (FetchData.e, Sales.e, SalesReport.e); every row given in tables[].xs.rows' },
  s:  { factRows: 1000, dateRange: '2026-01-01..2026-12-31' },
  m:  { factRows: 100000, dateRange: '2025-01-01..2026-12-31' },
  l:  { factRows: 2000000, dateRange: '2024-01-01..2026-12-31' },
};

// ---------------------------------------------------------------- xs rows
// The fact literals: FetchData.e:21-29 (region, day, amount, units) and
// Sales.e:98-107 (the same eight, plus item). Totals pinned in FetchData.e:18-19.
const sales8 = [
  ['north', '2026-01-05', 1200.5, 3, 'widget'],
  ['north', '2026-01-19', 840.0, 2, 'gizmo'],
  ['north', '2026-02-14', 2310.25, 7, 'widget'],
  ['south', '2026-01-09', 615.75, 1, 'doohickey'],
  ['south', '2026-02-02', 1990.0, 5, 'widget'],
  ['east', '2026-02-20', 75.5, 1, 'gizmo'],
  ['east', '2026-03-03', 4100.0, 11, 'doohickey'],
  ['west', '2026-03-17', 1550.0, 4, 'widget'],
];
const regionIds = { north: 1, south: 2, east: 3, west: 4 };
const productIds = { widget: 1, gizmo: 2, doohickey: 3 };
const r4 = (x) => Math.round(x * 1e4) / 1e4;
const r2 = (x) => Math.round(x * 1e2) / 1e2;

const xsDays = [...new Set(sales8.map((s) => s[1]))].sort();
const isoWeekday = (d) => { const w = new Date(d + 'T00:00:00Z').getUTCDay(); return w === 0 ? 7 : w; };
const weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const xsFact = sales8.map(([region, day, amount, units, item], i) => {
  const unitPrice = r4(amount / units);
  const lineAmount = r2(units * unitPrice * (1 - 0));
  if (lineAmount !== amount) throw new Error(`xs row ${i + 1}: ${lineAmount} != ${amount}`);
  return {
    orderId: i + 1, lineNo: 1, orderDate: day,
    regionId: regionIds[region], customerId: regionIds[region], productId: productIds[item],
    repId: regionIds[region], channelId: 1,
    quantity: units, unitPrice, discountPct: 0.0, lineAmount: amount, promoCode: null,
  };
});

// ---------------------------------------------------------------- tables
const tables = [
  {
    name: 'dim_region', layer: 'full',
    doc: 'One row per sales region. regionCode is the Ermine `region` value every view exposes.',
    rows: { xs: 4, s: 8, m: 12, l: 20 },
    pk: ['regionId'], unique: [['regionCode']], fks: [],
    columns: [
      col('regionId', 'Int', T.Int, { kind: 'id' }),
      col('regionCode', 'String', S(40), { kind: 'code', vocabulary: 'region', case: 'lower-ascii', uniqueCaseInsensitive: true }),
      col('regionName', 'String', S(80), { kind: 'name', of: 'region' }),
      col('regionGroup', 'String', S(8), { kind: 'code', values: ['EMEA', 'APAC', 'AMER'] }),
      col('countryName', 'String', S(80), { kind: 'name', source: 'country' }),
      col('countryCode', 'String', S(2), { kind: 'code', source: 'iso3166-alpha2' }),
      col('populationWeight', 'Double', T.Double, { kind: 'weight', min: 0, max: 1, sumsTo: 1, source: 'vendored population of the country, normalised over the regions' }),
    ],
    xs: { rows: [
      { regionId: 1, regionCode: 'north', regionName: 'North', regionGroup: 'EMEA', countryName: 'United Kingdom', countryCode: 'GB', populationWeight: 0.3 },
      { regionId: 2, regionCode: 'south', regionName: 'South', regionGroup: 'AMER', countryName: 'Brazil', countryCode: 'BR', populationWeight: 0.25 },
      { regionId: 3, regionCode: 'east', regionName: 'East', regionGroup: 'APAC', countryName: 'Japan', countryCode: 'JP', populationWeight: 0.25 },
      { regionId: 4, regionCode: 'west', regionName: 'West', regionGroup: 'AMER', countryName: 'United States', countryCode: 'US', populationWeight: 0.2 },
    ] },
  },
  {
    name: 'dim_product', layer: 'full',
    doc: 'The catalogue. productName is the Ermine `item` value (Sales.e).',
    rows: { xs: 3, s: 40, m: 200, l: 1000 },
    pk: ['productId'], unique: [['sku'], ['productName']], fks: [],
    columns: [
      col('productId', 'Int', T.Int, { kind: 'id' }),
      col('sku', 'String', S(20), { kind: 'code', pattern: 'SKU-[0-9]{5}' }),
      col('productName', 'String', S(80), { kind: 'name', of: 'product', uniqueCaseInsensitive: true }),
      col('category', 'String', S(40), { kind: 'name', of: 'category' }),
      col('subCategory', 'String', S(40), { kind: 'name', of: 'subCategory' }),
      col('priceBand', 'String', S(10), { kind: 'code', values: ['low', 'mid', 'high', 'premium'] }),
      col('listPrice', 'Double', T.Double, { kind: 'money', min: 1, max: 5000, bandBy: 'priceBand', cents: true }),
      col('unitCost', 'Double', T.Double, { kind: 'money', min: 0.5, max: 4000, lessThan: 'listPrice', cents: true }),
    ],
    xs: { rows: [
      { productId: 1, sku: 'SKU-00001', productName: 'widget', category: 'Hardware', subCategory: 'Widgets', priceBand: 'mid', listPrice: 400.0, unitCost: 240.0 },
      { productId: 2, sku: 'SKU-00002', productName: 'gizmo', category: 'Hardware', subCategory: 'Gizmos', priceBand: 'mid', listPrice: 420.0, unitCost: 250.0 },
      { productId: 3, sku: 'SKU-00003', productName: 'doohickey', category: 'Hardware', subCategory: 'Parts', priceBand: 'mid', listPrice: 500.0, unitCost: 310.0 },
    ] },
  },
  {
    name: 'dim_channel', layer: 'full',
    doc: 'Sales channel (Ai/SalesByRegion.e channel dimension). isDirect is a Y/N String: the corpus has 0 Bool columns (SURVEY-CORPUS §5).',
    rows: { xs: 1, s: 4, m: 5, l: 6 },
    pk: ['channelId'], unique: [['channelName']], fks: [],
    columns: [
      col('channelId', 'Int', T.Int, { kind: 'id' }),
      col('channelName', 'String', S(40), { kind: 'name', of: 'channel', values: ['Direct', 'Online', 'Partner', 'Retail', 'Marketplace', 'Telesales'] }),
      col('isDirect', 'String', S(1), { kind: 'flag', values: ['Y', 'N'] }),
    ],
    xs: { rows: [ { channelId: 1, channelName: 'Direct', isDirect: 'Y' } ] },
  },
  {
    name: 'dim_rep', layer: 'full',
    doc: 'Sales reps; each belongs to one region. repScore is the one Nullable Int (Present/SalesDashboard.e repScore).',
    rows: { xs: 4, s: 24, m: 60, l: 150 },
    pk: ['repId'], unique: [], fks: [{ columns: ['regionId'], ref: 'dim_region', refColumns: ['regionId'] }],
    columns: [
      col('repId', 'Int', T.Int, { kind: 'id' }),
      col('repName', 'String', S(80), { kind: 'name', of: 'person', source: 'faker' }),
      col('regionId', 'Int', T.Int, { kind: 'fk', ref: 'dim_region.regionId' }),
      col('repTeam', 'String', S(40), { kind: 'name', of: 'team' }),
      col('hireDate', 'Date', T.Date, { kind: 'date', range: '2015-01-01..2025-12-31', notAfter: 'first orderDate of the tier' }),
      col('repScore', 'Int', T.Int, { kind: 'score', min: 0, max: 100, nullRate: 0.15 }, { nullable: true }),
    ],
    xs: { rows: [
      { repId: 1, repName: 'Ada Byrne', regionId: 1, repTeam: 'North Field', hireDate: '2021-03-01', repScore: 82 },
      { repId: 2, repName: 'Bruno Costa', regionId: 2, repTeam: 'South Field', hireDate: '2019-07-15', repScore: 64 },
      { repId: 3, repName: 'Chiaki Mori', regionId: 3, repTeam: 'East Field', hireDate: '2023-01-09', repScore: 71 },
      { repId: 4, repName: 'Dana Hale', regionId: 4, repTeam: 'West Field', hireDate: '2024-10-01', repScore: null },
    ] },
  },
  {
    name: 'dim_customer', layer: 'full',
    doc: 'Customers; each belongs to one region (Algebra/OrderLedger.e customerDim, complete here: FKs are enforced).',
    rows: { xs: 4, s: 200, m: 5000, l: 50000 },
    pk: ['customerId'], unique: [], fks: [{ columns: ['regionId'], ref: 'dim_region', refColumns: ['regionId'] }],
    columns: [
      col('customerId', 'Int', T.Int, { kind: 'id' }),
      col('customerName', 'String', S(120), { kind: 'name', of: 'company', source: 'faker' }),
      col('customerTier', 'String', S(10), { kind: 'code', values: ['gold', 'silver', 'bronze'], weights: [0.1, 0.3, 0.6] }),
      col('regionId', 'Int', T.Int, { kind: 'fk', ref: 'dim_region.regionId', weightBy: 'dim_region.populationWeight' }),
      col('signupDate', 'Date', T.Date, { kind: 'date', range: '2018-01-01..2026-12-31', notAfter: 'the customer\'s first orderDate' }),
    ],
    xs: { rows: [
      { customerId: 1, customerName: 'Northwind Traders', customerTier: 'gold', regionId: 1, signupDate: '2020-02-10' },
      { customerId: 2, customerName: 'Southgate Supply', customerTier: 'silver', regionId: 2, signupDate: '2021-05-03' },
      { customerId: 3, customerName: 'Eastern Parts Co', customerTier: 'bronze', regionId: 3, signupDate: '2022-08-22' },
      { customerId: 4, customerName: 'Westwood Retail', customerTier: 'silver', regionId: 4, signupDate: '2023-11-30' },
    ] },
  },
  {
    name: 'dim_date', layer: 'full',
    doc: 'The calendar. xs = exactly the 8 sale days (so the `calendar` view equals FetchCrosstab.e\'s literal); s+ = every day of the tier range. monthName is FetchCrosstab\'s "YYYY-MM" key.',
    rows: { xs: 8, s: 365, m: 730, l: 1096 },
    pk: ['day'], unique: [], fks: [],
    columns: [
      col('day', 'Date', T.Date, { kind: 'date', range: 'tier', contiguous: 'every day of the tier range (s, m, l); the 8 sale days at xs' }),
      col('yearNo', 'Int', T.Int, { kind: 'derived', from: 'day', rule: 'year' }),
      col('quarterNo', 'Int', T.Int, { kind: 'derived', from: 'day', rule: 'quarter 1..4' }),
      col('monthNo', 'Int', T.Int, { kind: 'derived', from: 'day', rule: 'month 1..12' }),
      col('monthName', 'String', S(7), { kind: 'derived', from: 'day', rule: 'YYYY-MM' }),
      col('quarterName', 'String', S(7), { kind: 'derived', from: 'day', rule: 'YYYY-Qn' }),
      col('weekdayNo', 'Int', T.Int, { kind: 'derived', from: 'day', rule: 'ISO weekday, 1 = Monday .. 7 = Sunday' }),
      col('weekdayName', 'String', S(9), { kind: 'derived', from: 'day', rule: 'English weekday name' }),
    ],
    xs: { rows: xsDays.map((d) => {
      const [y, m] = d.split('-').map(Number); const q = Math.floor((m - 1) / 3) + 1; const w = isoWeekday(d);
      return { day: d, yearNo: y, quarterNo: q, monthNo: m, monthName: d.slice(0, 7), quarterName: `${y}-Q${q}`, weekdayNo: w, weekdayName: weekdayNames[w] };
    }) },
  },
  {
    name: 'fact_order_line', layer: 'full',
    doc: 'One row per order line. lineAmount is the Ermine `amount`, quantity the Ermine `units`, both summed by the views.',
    rows: { xs: 8, s: 1000, m: 100000, l: 2000000 },
    pk: ['orderId', 'lineNo'], unique: [],
    fks: [
      { columns: ['orderDate'], ref: 'dim_date', refColumns: ['day'] },
      { columns: ['regionId'], ref: 'dim_region', refColumns: ['regionId'] },
      { columns: ['customerId'], ref: 'dim_customer', refColumns: ['customerId'] },
      { columns: ['productId'], ref: 'dim_product', refColumns: ['productId'] },
      { columns: ['repId'], ref: 'dim_rep', refColumns: ['repId'] },
      { columns: ['channelId'], ref: 'dim_channel', refColumns: ['channelId'] },
    ],
    columns: [
      col('orderId', 'Int', T.Int, { kind: 'id' }),
      col('lineNo', 'Int', T.Int, { kind: 'count', min: 1, max: 8, rule: '1..n within an order, no gaps' }),
      col('orderDate', 'Date', T.Date, { kind: 'fk', ref: 'dim_date.day', shape: 'weekday + seasonal' }),
      col('regionId', 'Int', T.Int, { kind: 'fk', ref: 'dim_region.regionId', weightBy: 'dim_region.populationWeight' }),
      col('customerId', 'Int', T.Int, { kind: 'fk', ref: 'dim_customer.customerId', sameAs: 'dim_customer.regionId = regionId' }),
      col('productId', 'Int', T.Int, { kind: 'fk', ref: 'dim_product.productId' }),
      col('repId', 'Int', T.Int, { kind: 'fk', ref: 'dim_rep.repId', sameAs: 'dim_rep.regionId = regionId' }),
      col('channelId', 'Int', T.Int, { kind: 'fk', ref: 'dim_channel.channelId' }),
      col('quantity', 'Int', T.Int, { kind: 'count', min: 1, max: 50, by: 'dim_product.category' }),
      col('unitPrice', 'Double', T.Double, { kind: 'money', min: 0.5, max: 5000, rule: 'listPrice * (1 + small spread), 4 dp; at xs round(amount/units, 4)' }),
      col('discountPct', 'Double', T.Double, { kind: 'ratio', min: 0, max: 0.3, rule: '0 at xs' }),
      col('lineAmount', 'Double', T.Double, { kind: 'money', min: 0, max: 50000, rule: 'round(quantity * unitPrice * (1 - discountPct), 2)' }),
      col('promoCode', 'String', S(20), { kind: 'code', pattern: '[A-Z]{4,8}[0-9]{2}', nullRate: 0.8, rule: 'non-NULL only when discountPct > 0' }, { nullable: true }),
    ],
    xs: { rows: xsFact },
  },
  {
    name: 'fact_target', layer: 'full',
    doc: 'A sales target per region per quarter; the `targets` view sums them per region.',
    rows: { xs: 4, s: 32, m: 96, l: 240 },
    pk: ['regionId', 'yearNo', 'quarterNo'], unique: [],
    fks: [{ columns: ['regionId'], ref: 'dim_region', refColumns: ['regionId'] }],
    columns: [
      col('regionId', 'Int', T.Int, { kind: 'fk', ref: 'dim_region.regionId' }),
      col('yearNo', 'Int', T.Int, { kind: 'derived', rule: 'every year of the tier range' }),
      col('quarterNo', 'Int', T.Int, { kind: 'derived', rule: '1..4; xs has only Q1' }),
      col('targetAmount', 'Double', T.Double, { kind: 'money', min: 0, max: 50000000, rule: 'derived from history: the region\'s actual quarter sales * U(0.9, 1.2), cents' }),
    ],
    xs: { rows: [
      { regionId: 1, yearNo: 2026, quarterNo: 1, targetAmount: 4000.0 },
      { regionId: 2, yearNo: 2026, quarterNo: 1, targetAmount: 3000.0 },
      { regionId: 3, yearNo: 2026, quarterNo: 1, targetAmount: 2000.0 },
      { regionId: 4, yearNo: 2026, quarterNo: 1, targetAmount: 2500.0 },
    ] },
  },
  {
    name: 'sales_report', layer: 'minimal',
    doc: 'Backs Doc/SalesReport.e (sales : [srRegion, srSales, srDelta]). A BASE TABLE (a mart snapshot) at every tier: its xs values are literals no view over the 8 sales can derive.',
    rows: { xs: 3, s: 3, m: 3, l: 3 },
    pk: ['srRegion'], unique: [], fks: [],
    columns: [
      col('srRegion', 'String', S(8), { kind: 'code', values: ['EMEA', 'APAC', 'AMER'], ref: 'dim_region.regionGroup' }),
      col('srSales', 'Double', T.Double, { kind: 'money', unit: 'thousands', rule: 's+: sum(lineAmount)/1000 of the regionGroup in the last full quarter of the tier range, 2 dp' }),
      col('srDelta', 'Double', T.Double, { kind: 'ratio', min: -1, max: 5, rule: 's+: (last quarter - previous quarter) / previous quarter, 3 dp' }),
    ],
    xs: { rows: [
      { srRegion: 'EMEA', srSales: 120.5, srDelta: 0.125 },
      { srRegion: 'APAC', srSales: 98.25, srDelta: -0.04 },
      { srRegion: 'AMER', srSales: 310.75, srDelta: 0.5 },
    ] },
  },
];

// ---------------------------------------------------------------- views
// The minimal layer: what the Doc fixtures' Ermine `table` statements name.
// Each view GROUPs BY its full key, so its rows are distinct at every tier:
// the scanner marks a base relation already-distinct (SqlScanner.scala:1027-1031).
// The body is written once with a {S} schema prefix: 'dbo.' on MSSQL, '' on SQLite.
const views = [
  {
    name: 'sales', fixture: 'FetchData.e:20 `sales : [region, day, amount, units]`',
    key: ['region', 'day'],
    columns: [
      col('region', 'String', S(40), { kind: 'view', from: 'dim_region.regionCode' }),
      col('day', 'Date', T.Date, { kind: 'view', from: 'fact_order_line.orderDate' }),
      col('amount', 'Double', T.Double, { kind: 'view', from: 'SUM(fact_order_line.lineAmount)' }),
      col('units', 'Int', T.Int, { kind: 'view', from: 'SUM(fact_order_line.quantity)' }),
    ],
    body: `SELECT r.regionCode AS region, f.orderDate AS day,
       SUM(f.lineAmount) AS amount, SUM(f.quantity) AS units
FROM {S}fact_order_line AS f
JOIN {S}dim_region AS r ON r.regionId = f.regionId
GROUP BY r.regionCode, f.orderDate`,
  },
  {
    name: 'sales_items', fixture: 'Sales.e:71-75 the Sale record (region, day, amount, units, item)',
    key: ['region', 'day', 'item'],
    columns: [
      col('region', 'String', S(40), { kind: 'view', from: 'dim_region.regionCode' }),
      col('day', 'Date', T.Date, { kind: 'view', from: 'fact_order_line.orderDate' }),
      col('item', 'String', S(80), { kind: 'view', from: 'dim_product.productName' }),
      col('amount', 'Double', T.Double, { kind: 'view', from: 'SUM(fact_order_line.lineAmount)' }),
      col('units', 'Int', T.Int, { kind: 'view', from: 'SUM(fact_order_line.quantity)' }),
    ],
    body: `SELECT r.regionCode AS region, f.orderDate AS day, p.productName AS item,
       SUM(f.lineAmount) AS amount, SUM(f.quantity) AS units
FROM {S}fact_order_line AS f
JOIN {S}dim_region AS r ON r.regionId = f.regionId
JOIN {S}dim_product AS p ON p.productId = f.productId
GROUP BY r.regionCode, f.orderDate, p.productName`,
  },
  {
    name: 'targets', fixture: 'FetchData.e:33 `targets : [region, target]`',
    key: ['region'],
    columns: [
      col('region', 'String', S(40), { kind: 'view', from: 'dim_region.regionCode' }),
      col('target', 'Double', T.Double, { kind: 'view', from: 'SUM(fact_target.targetAmount)' }),
    ],
    body: `SELECT r.regionCode AS region, SUM(t.targetAmount) AS target
FROM {S}fact_target AS t
JOIN {S}dim_region AS r ON r.regionId = t.regionId
GROUP BY r.regionCode`,
  },
  {
    name: 'calendar', fixture: 'FetchCrosstab.e `calendar : [day, monthName]` (a module-local literal today)',
    key: ['day'],
    columns: [
      col('day', 'Date', T.Date, { kind: 'view', from: 'dim_date.day' }),
      col('monthName', 'String', S(7), { kind: 'view', from: 'dim_date.monthName' }),
    ],
    body: `SELECT d.day AS day, d.monthName AS monthName
FROM {S}dim_date AS d`,
  },
];

// ---------------------------------------------------------------- indexes
const indexes = [
  { name: 'ix_fol_region_date', table: 'fact_order_line', columns: ['regionId', 'orderDate'], mssqlInclude: ['lineAmount', 'quantity', 'productId'] },
  { name: 'ix_fol_date', table: 'fact_order_line', columns: ['orderDate'] },
  { name: 'ix_fol_product', table: 'fact_order_line', columns: ['productId'] },
  { name: 'ix_rep_region', table: 'dim_rep', columns: ['regionId'] },
  { name: 'ix_customer_region', table: 'dim_customer', columns: ['regionId'] },
];

// ---------------------------------------------------------------- invariants
const invariants = [
  'No NULL outside the two Nullable columns (dim_rep.repScore, fact_order_line.promoCode): a NULL in a non-Nullable column fails the scan (SURVEY-CORPUS §5, SqlExecution.scala:62-87).',
  'Every PK and UNIQUE holds; every FK resolves (the DDL enforces both on MSSQL and on SQLite with PRAGMA foreign_keys = ON).',
  'String natural keys (regionCode, productName, channelName, regionGroup) are unique case-insensitively: MSSQL default collation is CI, SQLite BINARY; a CI collision would merge groups on one dialect only (SURVEY-CORPUS §4, §9.3 row).',
  'regionCode is lowercase ASCII [a-z][a-z0-9-]*: the Fetch reports sort and filter on it (FetchTabs scanInOrder by region); keeps MSSQL and SQLite ordering identical.',
  'lineAmount = round(quantity * unitPrice * (1 - discountPct), 2); money columns carry cents (2 dp) except unitPrice (4 dp).',
  'fact_order_line: dim_rep[repId].regionId = regionId and dim_customer[customerId].regionId = regionId; all lines of one orderId share orderDate, regionId, customerId, repId, channelId.',
  'dim_date is contiguous over the tier range at s, m, l; at xs it is exactly the 8 sale days. Every orderDate is a dim_date.day (FK).',
  'fact_target has one row per (region, year, quarter) of the tier range, so the `targets` view has one row per region.',
  'Dates carry no time of day. CSV carries YYYY-MM-DD; the SQLite loader writes INTEGER epoch milliseconds at 00:00:00 GMT (Date.UTC(y, m-1, d)), because SqliteEmitter compares Date columns against d.getTime literals (SqlEmitter.scala:696).',
  'Every tier is a pure function of (seed, tier); xs ignores the seed and is exactly tables[].xs.rows.',
  'No String column holds the empty string: an empty CSV field means NULL (only legal in a Nullable column), so a Nullable String value is either NULL or non-empty (BULK INSERT loads "" in a nullable column as NULL; REVIEW-S1 M3).',
];

// ---------------------------------------------------------------- contract
const contract = {
  contract: 'ErmineSales column contract',
  version: 1,
  domain: 'sales',
  database: 'ErmineSales',
  schema: 'dbo',
  source: 'data/schema/build-sales-schema.mjs (edit that, rerun; do not hand-edit this file)',
  doc: 'tracker/db/SCHEMA-SALES.md',
  dialects: {
    mssql: { ddl: 'data/schema/sales.mssql.sql', names: 'dbo.<table>', date: 'date', double: 'float', string: 'nvarchar(n)', int: 'int' },
    sqlite: { ddl: 'data/schema/sales.sqlite.sql', names: '<table> in main (no schema)', date: 'INTEGER epoch ms at 00:00 GMT', double: 'REAL', string: 'TEXT (STRICT tables)', int: 'INTEGER' },
  },
  csv: { header: true, delimiter: ',', quote: '"', null: 'An empty CSV field (quoted "" or unquoted) means NULL. A Nullable String column never holds the empty string, and a non-Nullable String column never holds it either (BULK INSERT loads "" in a nullable column as NULL; REVIEW-S1 M3).', date: 'YYYY-MM-DD', double: 'shortest round-trip decimal (JS Number#toString)', encoding: 'UTF-8, LF' },
  hintKinds: ['id', 'fk', 'code', 'name', 'money', 'ratio', 'count', 'date', 'derived', 'weight', 'score', 'flag', 'view'],
  tiers,
  loadOrder: tables.map((t) => t.name),
  invariants,
  tables: tables.map((t) => ({
    name: t.name, kind: 'table', layer: t.layer, doc: t.doc,
    pk: t.pk, unique: t.unique, fks: t.fks, rows: t.rows,
    columns: t.columns, xs: t.xs,
  })),
  views: views.map((v) => ({
    name: v.name, kind: 'view', layer: 'minimal', fixture: v.fixture, key: v.key,
    rows: v.name === 'sales' || v.name === 'sales_items' ? { xs: 8, s: 'derived: distinct keys of fact_order_line' , m: 'derived', l: 'derived' }
        : v.name === 'targets' ? { xs: 4, s: 8, m: 12, l: 20 }
        : { xs: 8, s: 365, m: 730, l: 1096 },
    columns: v.columns,
    sql: v.body.replaceAll('{S}', 'dbo.'),
  })),
  fkGraph: tables.flatMap((t) => t.fks.map((f) => `${t.name}(${f.columns.join(',')}) -> ${f.ref}(${f.refColumns.join(',')})`)),
  indexes,
  xsPinned: {
    source: 'FetchData.e:18-19 and FetchTopN.e (the met count); units and targets totals are sums of the literals',
    regionAmount: { north: 4350.75, south: 2605.75, east: 4175.5, west: 1550.0 },
    totalAmount: 12682.0, totalUnits: 34, targetTotal: 11500.0, targetsMet: 2,
    monthRows: { '2026-01': 3, '2026-02': 3, '2026-03': 2 },
    srSalesTotal: 529.5,
  },
};

// ---------------------------------------------------------------- DDL
const HEAD = (dialect) => `-- GENERATED by data/schema/build-sales-schema.mjs -- do not edit; edit the generator and rerun.
-- ErmineSales schema, ${dialect} variant (tracker/db/SCHEMA-SALES.md; contract data/schema/sales.contract.json).
-- Idempotent: drops every view, then every table (facts before dims, for the FKs), then creates.
`;

const DIFFS = `-- Dialect differences from the twin file (and ONLY these):
--   D-1 names: MSSQL objects live in dbo and are written dbo.x; SQLite has no schemas
--       (a qualified name means an ATTACHed database), so objects are bare in main.
--   D-2 Date: MSSQL date; SQLite INTEGER holding epoch milliseconds at 00:00 GMT,
--       because SqliteEmitter writes a Date literal as d.getTime (SqlEmitter.scala:696)
--       and its own temp-table DDL types Date as integer (:724).
--   D-3 String: MSSQL nvarchar(n) (the length is the contract's maxLength); SQLite TEXT.
--       Double: float vs REAL. Int: int vs INTEGER. SQLite tables are STRICT so a
--       wrongly typed CSV value fails the load instead of being stored as text.
--   D-4 batches: CREATE VIEW must start a T-SQL batch, hence GO (sqlcmd); SQLite needs none.
--   D-5 indexes: MSSQL ix_fol_region_date INCLUDEs the summed columns; SQLite has no INCLUDE.
--   D-6 FKs: enforced by MSSQL always; by SQLite only under PRAGMA foreign_keys = ON,
--       which this file sets for its own connection (loaders must set it too).
--   D-7 guard: the MSSQL file refuses to run in a system database; SQLite has none.
--   D-8 quoting: T-SQL column names are [bracketed] (lineNo is the reserved LINENO); SQLite bare.
`;

// Column names are bracketed in the T-SQL DDL: `lineNo` is a reserved T-SQL keyword
// (LINENO; measured: Msg 156 against the server). The scanner brackets every column on
// MSSQL too (EmitName_MsSql, SqlEmitter.scala:616-617), so a report's `lineNo` works.
// SQLite needs no quoting for any of these names.
const q = (n, dialect) => dialect === 'mssql' ? `[${n}]` : n;
const qs = (ns, dialect) => ns.map((n) => q(n, dialect)).join(', ');

function tableDDL(t, dialect) {
  const P = dialect === 'mssql' ? 'dbo.' : '';
  const lines = t.columns.map((c) => `  ${q(c.name, dialect)} ${dialect === 'mssql' ? c.mssql : c.sqlite}${c.nullable ? ' NULL' : ' NOT NULL'}`);
  lines.push(`  CONSTRAINT pk_${t.name} PRIMARY KEY (${qs(t.pk, dialect)})`);
  for (const u of t.unique) lines.push(`  CONSTRAINT uq_${t.name}_${u.join('_')} UNIQUE (${qs(u, dialect)})`);
  for (const f of t.fks) lines.push(`  CONSTRAINT fk_${t.name}_${f.columns.join('_')} FOREIGN KEY (${qs(f.columns, dialect)}) REFERENCES ${P}${f.ref} (${qs(f.refColumns, dialect)})`);
  return `CREATE TABLE ${P}${t.name} (\n${lines.join(',\n')}\n)${dialect === 'sqlite' ? ' STRICT' : ''};`;
}

function mssql() {
  const out = [HEAD('T-SQL (SQL Server 2022)'), DIFFS,
    'SET NOCOUNT ON;',
    "IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')",
    "  THROW 50001, N'sales.mssql.sql: connect to the domain database (ErmineSales), not a system database', 1;",
    'GO', ''];
  for (const v of [...views].reverse()) out.push(`DROP VIEW IF EXISTS dbo.${v.name};`);
  for (const t of [...tables].reverse()) out.push(`DROP TABLE IF EXISTS dbo.${t.name};`);
  out.push('GO', '');
  for (const t of tables) out.push(`-- ${t.doc}`, tableDDL(t, 'mssql'), '');
  for (const i of indexes) {
    const inc = i.mssqlInclude ? ` INCLUDE (${qs(i.mssqlInclude, 'mssql')})` : '';
    out.push(`CREATE INDEX ${i.name} ON dbo.${i.table} (${qs(i.columns, 'mssql')})${inc};`);
  }
  out.push('GO', '');
  for (const v of views) {
    out.push(`-- backs ${v.fixture}; key (${v.key.join(', ')})`, `CREATE VIEW dbo.${v.name} AS`, `${v.body.replaceAll('{S}', 'dbo.')};`, 'GO', '');
  }
  return out.join('\n');
}

function sqlite() {
  const out = [HEAD('SQLite (3.37+, STRICT tables)'), DIFFS, 'PRAGMA foreign_keys = ON;', ''];
  for (const v of [...views].reverse()) out.push(`DROP VIEW IF EXISTS ${v.name};`);
  for (const t of [...tables].reverse()) out.push(`DROP TABLE IF EXISTS ${t.name};`);
  out.push('');
  for (const t of tables) out.push(`-- ${t.doc}`, tableDDL(t, 'sqlite'), '');
  for (const i of indexes) out.push(`CREATE INDEX ${i.name} ON ${i.table} (${i.columns.join(', ')});`);
  out.push('');
  for (const v of views) out.push(`-- backs ${v.fixture}; key (${v.key.join(', ')})`, `CREATE VIEW ${v.name} AS`, `${v.body.replaceAll('{S}', '')};`, '');
  return out.join('\n');
}

// ---------------------------------------------------------------- smoke
// One result set of (k, v) text pairs in a fixed order, so the output is a
// plain diff against sales.smoke.expected-xs.txt. Counts are tier-dependent;
// the totals are the xs pins.
function smoke(dialect) {
  const P = dialect === 'mssql' ? 'dbo.' : '';
  const num = (e) => dialect === 'mssql' ? `CAST(CAST(${e} AS decimal(18,2)) AS varchar(40))` : `printf('%.2f', ${e})`;
  const int = (e) => dialect === 'mssql' ? `CAST(${e} AS varchar(40))` : `CAST(${e} AS TEXT)`;
  const rows = [];
  for (const t of tables) rows.push([`count.${t.name}`, int(`(SELECT COUNT(*) FROM ${P}${t.name})`)]);
  for (const v of views) rows.push([`count.${v.name}`, int(`(SELECT COUNT(*) FROM ${P}${v.name})`)]);
  for (const r of ['north', 'south', 'east', 'west']) rows.push([`amount.${r}`, num(`(SELECT SUM(amount) FROM ${P}sales WHERE region = '${r}')`)]);
  rows.push(['amount.all', num(`(SELECT SUM(amount) FROM ${P}sales)`)]);
  rows.push(['units.all', int(`(SELECT SUM(units) FROM ${P}sales)`)]);
  rows.push(['items.amount.all', num(`(SELECT SUM(amount) FROM ${P}sales_items)`)]);
  rows.push(['target.all', num(`(SELECT SUM(target) FROM ${P}targets)`)]);
  rows.push(['targets.met', int(`(SELECT COUNT(*) FROM ${P}targets AS t JOIN (SELECT region, SUM(amount) AS amount FROM ${P}sales GROUP BY region) AS s ON s.region = t.region WHERE s.amount >= t.target)`)]);
  for (const m of ['2026-01', '2026-02', '2026-03']) rows.push([`sales.month.${m}`, int(`(SELECT COUNT(*) FROM ${P}sales AS s JOIN ${P}calendar AS c ON c.day = s.day WHERE c.monthName = '${m}')`)]);
  rows.push(['srSales.all', num(`(SELECT SUM(srSales) FROM ${P}sales_report)`)]);
  rows.push(['null.repScore', int(`(SELECT COUNT(*) FROM ${P}dim_rep WHERE repScore IS NULL)`)]);
  const body = rows.map(([k, e], i) => `SELECT ${i + 1} AS n, '${k}' AS k, ${e} AS v`).join('\nUNION ALL ');
  const head = `-- GENERATED by data/schema/build-sales-schema.mjs -- do not edit.
-- ErmineSales smoke, ${dialect}. Prints k|v lines; at tier xs the output must equal
-- data/schema/sales.smoke.expected-xs.txt byte for byte.
${dialect === 'mssql' ? `-- Run: scripts/db.sh sql ErmineSales -i data/schema/sales.smoke.sql -h -1 -W -s '|' -b | sed '/^$/d'
--   (go-sqlcmd appends one empty line after the result set; the sed drops it. MEASURED 2026-09-24.)
SET NOCOUNT ON;` : '-- Run: node data/schema/verify-sqlite.mjs (or any SQLite shell with | as the separator)'}
`;
  return `${head}SELECT k, v FROM (\n${body}\n) AS x ORDER BY n;\n`;
}

function expectedXs() {
  const L = [];
  for (const t of tables) L.push(`count.${t.name}|${t.rows.xs}`);
  for (const v of views) L.push(`count.${v.name}|${contract.views.find((x) => x.name === v.name).rows.xs}`);
  const p = contract.xsPinned;
  for (const r of ['north', 'south', 'east', 'west']) L.push(`amount.${r}|${p.regionAmount[r].toFixed(2)}`);
  L.push(`amount.all|${p.totalAmount.toFixed(2)}`, `units.all|${p.totalUnits}`, `items.amount.all|${p.totalAmount.toFixed(2)}`,
    `target.all|${p.targetTotal.toFixed(2)}`, `targets.met|${p.targetsMet}`);
  for (const [m, n] of Object.entries(p.monthRows)) L.push(`sales.month.${m}|${n}`);
  L.push(`srSales.all|${p.srSalesTotal.toFixed(2)}`, 'null.repScore|1');
  return L.join('\n') + '\n';
}

writeFileSync(join(here, 'sales.contract.json'), JSON.stringify(contract, null, 2) + '\n');
writeFileSync(join(here, 'sales.mssql.sql'), mssql());
writeFileSync(join(here, 'sales.sqlite.sql'), sqlite());
writeFileSync(join(here, 'sales.smoke.sql'), smoke('mssql'));
writeFileSync(join(here, 'sales.smoke.sqlite.sql'), smoke('sqlite'));
writeFileSync(join(here, 'sales.smoke.expected-xs.txt'), expectedXs());
console.log(`build-sales-schema: ${tables.length} tables, ${views.length} views, ${tables.reduce((a, t) => a + t.columns.length, 0) + views.reduce((a, v) => a + v.columns.length, 0)} columns -> ${here}`);
