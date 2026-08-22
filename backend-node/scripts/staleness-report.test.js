const test = require('node:test');
const assert = require('node:assert/strict');
const { findStaleRows, formatReport, SOURCED_TABLES } = require('./staleness-report');

function mockPool(handler) {
  return { query: async (text, params) => handler(text, params) };
}

test('findStaleRows queries every sourced table with the given threshold', async () => {
  const queriedTables = [];
  const pool = mockPool((text, params) => {
    queriedTables.push(text);
    assert.deepEqual(params, [6]);
    return { rows: [] };
  });
  const report = await findStaleRows(pool, 6);
  assert.equal(report.length, SOURCED_TABLES.length);
  for (const { table } of SOURCED_TABLES) {
    assert.ok(queriedTables.some((text) => text.includes(`FROM ${table} `)), `expected a query against ${table}`);
  }
});

test('findStaleRows reports a labeled stale row', async () => {
  const pool = mockPool((text) => {
    if (text.includes('FROM scholarships')) {
      return { rows: [{ record_id: 's1', label: 'DAAD Study Scholarship', source_checked_on: '2025-01-01' }] };
    }
    return { rows: [] };
  });
  const report = await findStaleRows(pool, 6);
  const scholarships = report.find((entry) => entry.table === 'scholarships');
  assert.equal(scholarships.staleCount, 1);
  assert.equal(scholarships.rows[0].label, 'DAAD Study Scholarship');
});

test('formatReport shows OK for tables with no stale rows and totals the rest', () => {
  const report = [
    { table: 'admission_requirements', staleCount: 0, rows: [] },
    { table: 'scholarships', staleCount: 1, rows: [{ record_id: 's1', label: 'DAAD Study Scholarship', source_checked_on: '2025-01-01' }] },
  ];
  const text = formatReport(report, 6);
  assert.match(text, /admission_requirements: OK \(0 stale\)/);
  assert.match(text, /scholarships: 1 stale row\(s\)/);
  assert.match(text, /DAAD Study Scholarship/);
  assert.match(text, /TOTAL: 1 row\(s\) need re-verification\./);
});

test('formatReport reports a clean bill of health when nothing is stale', () => {
  const report = SOURCED_TABLES.map(({ table }) => ({ table, staleCount: 0, rows: [] }));
  const text = formatReport(report, 6);
  assert.match(text, /TOTAL: everything is within the freshness window\./);
});
