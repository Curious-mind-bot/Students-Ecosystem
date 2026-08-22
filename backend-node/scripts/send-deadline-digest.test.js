process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildDigests, renderDigestEmail, sendDeadlineDigests, ACTIVE_STATUSES } = require('./send-deadline-digest');

function mockPool(rows) {
  return { query: async (text, params) => { assert.deepEqual(params[1], ACTIVE_STATUSES); return { rows }; } };
}

test('buildDigests groups tracked applications by student email', async () => {
  const pool = mockPool([
    { email: 'a@example.com', full_name: 'A Student', program_title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE', deadline_at: '2026-09-01', submission_status: 'DRAFT' },
    { email: 'a@example.com', full_name: 'A Student', program_title: 'M.Sc. DS', university_name: 'TU Delft', country_code: 'NL', deadline_at: '2026-09-05', submission_status: 'DOCUMENTS_IN_PROGRESS' },
    { email: 'b@example.com', full_name: 'B Student', program_title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE', deadline_at: '2026-09-10', submission_status: 'DRAFT' },
  ]);
  const digests = await buildDigests(pool);
  assert.equal(digests.length, 2);
  assert.equal(digests[0].applications.length, 2);
  assert.equal(digests[1].applications.length, 1);
});

test('renderDigestEmail lists each application with a day count and never invents a deadline', async () => {
  const digest = {
    fullName: 'A Student', email: 'a@example.com',
    applications: [{ program_title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE', deadline_at: '2099-01-01', submission_status: 'DRAFT' }],
  };
  const { subject, text } = renderDigestEmail(digest);
  assert.match(subject, /1 application deadline/);
  assert.match(text, /M\.Sc\. CS/);
  assert.match(text, /2099-01-01/);
  assert.match(text, /confirm the real deadline/);
});

test('sendDeadlineDigests sends exactly one email per student', async () => {
  const pool = mockPool([
    { email: 'a@example.com', full_name: 'A Student', program_title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE', deadline_at: '2026-09-01', submission_status: 'DRAFT' },
    { email: 'b@example.com', full_name: 'B Student', program_title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE', deadline_at: '2026-09-10', submission_status: 'DRAFT' },
  ]);
  const sent = [];
  const mailer = { sendMail: async (message) => { sent.push(message); } };
  const { digestsSent } = await sendDeadlineDigests({ pool, mailer });
  assert.equal(digestsSent, 2);
  assert.equal(sent.length, 2);
  assert.deepEqual(sent.map((m) => m.to).sort(), ['a@example.com', 'b@example.com']);
});

test('sendDeadlineDigests sends nothing when no applications have a tracked deadline', async () => {
  const pool = mockPool([]);
  const sent = [];
  const mailer = { sendMail: async (message) => { sent.push(message); } };
  const { digestsSent } = await sendDeadlineDigests({ pool, mailer });
  assert.equal(digestsSent, 0);
  assert.equal(sent.length, 0);
});
