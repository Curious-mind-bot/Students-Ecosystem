const { Pool } = require('pg');
require('dotenv').config();

const STALENESS_THRESHOLD_MONTHS = Number(process.env.STALENESS_THRESHOLD_MONTHS || 6);

// Every table below carries the project's core promise — no fact without a
// checked source — so every one of them needs periodic re-verification.
const SOURCED_TABLES = [
  { table: 'admission_requirements', idColumn: 'requirement_id' },
  { table: 'scholarships', idColumn: 'scholarship_id', labelColumn: 'name' },
  { table: 'program_fees', idColumn: 'fee_id' },
  { table: 'living_cost_estimates', idColumn: 'estimate_id' },
  { table: 'visa_requirements', idColumn: 'visa_requirement_id' },
  { table: 'student_accommodations', idColumn: 'accommodation_id', labelColumn: 'provider_name' },
  { table: 'support_resources', idColumn: 'resource_id', labelColumn: 'name' },
];

async function findStaleRows(pool, thresholdMonths = STALENESS_THRESHOLD_MONTHS) {
  const report = [];
  for (const { table, idColumn, labelColumn } of SOURCED_TABLES) {
    const selectCols = labelColumn
      ? `${idColumn} AS record_id, ${labelColumn} AS label, source_checked_on`
      : `${idColumn} AS record_id, source_checked_on`;
    // table/idColumn/labelColumn come only from the fixed SOURCED_TABLES list above, never from user input.
    const { rows } = await pool.query(
      `SELECT ${selectCols} FROM ${table} WHERE source_checked_on < (CURRENT_DATE - ($1 || ' months')::interval) ORDER BY source_checked_on ASC`,
      [thresholdMonths],
    );
    report.push({ table, staleCount: rows.length, rows });
  }
  return report;
}

function formatReport(report, thresholdMonths = STALENESS_THRESHOLD_MONTHS) {
  const totalStale = report.reduce((sum, entry) => sum + entry.staleCount, 0);
  const lines = [`Staleness report — facts not re-checked in over ${thresholdMonths} month(s):`, ''];
  for (const { table, staleCount, rows } of report) {
    if (!staleCount) { lines.push(`${table}: OK (0 stale)`); continue; }
    lines.push(`${table}: ${staleCount} stale row(s)`);
    for (const row of rows.slice(0, 5)) {
      const label = row.label ? ` "${row.label}"` : '';
      const checkedOn = new Date(row.source_checked_on).toISOString().slice(0, 10);
      lines.push(`  - ${row.record_id}${label} (checked ${checkedOn})`);
    }
    if (rows.length > 5) lines.push(`  ...and ${rows.length - 5} more`);
  }
  lines.push('', totalStale ? `TOTAL: ${totalStale} row(s) need re-verification.` : 'TOTAL: everything is within the freshness window.');
  return lines.join('\n');
}

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    const report = await findStaleRows(pool);
    console.log(formatReport(report));
    const totalStale = report.reduce((sum, entry) => sum + entry.staleCount, 0);
    if (totalStale > 0) process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { findStaleRows, formatReport, SOURCED_TABLES, STALENESS_THRESHOLD_MONTHS };
