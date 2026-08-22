const { Pool } = require('pg');
const { createMailer } = require('../server');
require('dotenv').config();

const REMINDER_WINDOW_DAYS = Number(process.env.DEADLINE_REMINDER_WINDOW_DAYS || 14);
const ACTIVE_STATUSES = ['DRAFT', 'DOCUMENTS_IN_PROGRESS'];

async function buildDigests(pool) {
  const { rows } = await pool.query(
    `SELECT u.email, u.full_name, a.program_title, a.university_name, a.country_code, a.deadline_at, a.submission_status
     FROM applications_tracker a
     JOIN users u ON u.user_id = a.user_id
     WHERE a.deadline_at IS NOT NULL
       AND a.deadline_at <= (CURRENT_DATE + $1::int)
       AND a.submission_status = ANY($2::varchar[])
     ORDER BY u.email, a.deadline_at`,
    [REMINDER_WINDOW_DAYS, ACTIVE_STATUSES],
  );
  const byEmail = new Map();
  for (const row of rows) {
    if (!byEmail.has(row.email)) byEmail.set(row.email, { fullName: row.full_name, email: row.email, applications: [] });
    byEmail.get(row.email).applications.push(row);
  }
  return [...byEmail.values()];
}

function renderDigestEmail(digest) {
  const lines = digest.applications.map((application) => {
    const deadlineDate = new Date(application.deadline_at).toISOString().slice(0, 10);
    const days = Math.ceil((new Date(application.deadline_at) - new Date()) / (1000 * 60 * 60 * 24));
    const label = days < 0 ? `${Math.abs(days)} day(s) overdue` : days === 0 ? 'due today' : `${days} day(s) left`;
    return `- ${application.program_title} · ${application.university_name} (${application.country_code}): deadline ${deadlineDate} (${label}), status ${application.submission_status}`;
  });
  return {
    subject: `${digest.applications.length} application deadline(s) need your attention`,
    text: `Hi ${digest.fullName},\n\nHere are the application deadlines you're tracking that are coming up or overdue:\n\n${lines.join('\n')}\n\n`
      + 'Always confirm the real deadline on the university\'s official page — this reminder is generated only from the date you entered yourself.\n',
  };
}

async function sendDeadlineDigests({ pool, mailer }) {
  const digests = await buildDigests(pool);
  let digestsSent = 0;
  for (const digest of digests) {
    const { subject, text } = renderDigestEmail(digest);
    await mailer.sendMail({ from: process.env.EMAIL_FROM || process.env.EMAIL_USER, to: digest.email, subject, text });
    digestsSent += 1;
  }
  return { digestsSent };
}

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const mailer = createMailer();
  try {
    const { digestsSent } = await sendDeadlineDigests({ pool, mailer });
    console.log(`Sent ${digestsSent} deadline reminder email(s).`);
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

module.exports = { buildDigests, renderDigestEmail, sendDeadlineDigests, REMINDER_WINDOW_DAYS, ACTIVE_STATUSES };
