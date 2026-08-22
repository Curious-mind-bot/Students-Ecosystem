const crypto = require('crypto');
const { spawn } = require('child_process');
const path = require('path');
const express = require('express');
const jwt = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const { Pool } = require('pg');
require('dotenv').config();

const APPLICATION_STATUSES = new Set(['DRAFT', 'DOCUMENTS_IN_PROGRESS', 'SUBMITTED', 'OFFER_RECEIVED', 'DECLINED', 'WITHDRAWN']);
const DOCUMENT_STATUSES = new Set(['NOT_STARTED', 'IN_PROGRESS', 'READY', 'SUBMITTED', 'NOT_REQUIRED']);

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required for this operation.`);
  return value;
}

function authRequired(req, res, next) {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Authentication required.' });
  try {
    const payload = jwt.verify(token, requireEnv('JWT_SECRET'), { algorithms: ['HS256'] });
    if (!payload.sub) return res.status(401).json({ error: 'Token subject is required.' });
    req.user = { id: payload.sub };
    return next();
  } catch (_error) {
    return res.status(401).json({ error: 'Invalid or expired authentication token.' });
  }
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  const [salt, hash] = stored.split(':');
  const candidate = crypto.scryptSync(password, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return candidate.length === expected.length && crypto.timingSafeEqual(candidate, expected);
}

function signToken(userId) {
  return jwt.sign({ sub: userId }, requireEnv('JWT_SECRET'), { algorithm: 'HS256', expiresIn: '7d' });
}

async function computeCostView(pool, programId) {
  const { rows: feeRows } = await pool.query(
    "SELECT fee_type, amount_eur FROM program_fees WHERE program_id = $1 AND student_category = 'INTERNATIONAL'",
    [programId],
  );
  if (!feeRows.length) return null;
  const sum = (types) => feeRows.filter((f) => types.includes(f.fee_type)).reduce((total, f) => total + Number(f.amount_eur), 0);
  const estimatedAnnualTuitionEur = sum(['TUITION_PER_YEAR', 'ADMINISTRATIVE_FEE']);
  const oneTimeFeesEur = sum(['APPLICATION_FEE']);
  const { rows: scholarshipRows } = await pool.query('SELECT amount_eur FROM scholarships WHERE program_id = $1', [programId]);
  const totalPotentialScholarshipValueEur = scholarshipRows.reduce((total, s) => total + Number(s.amount_eur || 0), 0);
  return {
    estimated_annual_tuition_eur: estimatedAnnualTuitionEur,
    one_time_fees_eur: oneTimeFeesEur,
    total_potential_scholarship_value_eur: totalPotentialScholarshipValueEur,
    estimated_net_annual_cost_if_awarded_eur: Math.max(0, estimatedAnnualTuitionEur - totalPotentialScholarshipValueEur),
    caveat: 'This assumes you receive every listed scholarship at once, which is unlikely — check eligibility criteria for each individually. Not an official cost figure.',
  };
}

function runPython(payload) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.PYTHON_BIN || 'python3', [path.join(__dirname, '..', 'backend-python', 'match_engine.py')]);
    let output = '';
    let error = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { error += chunk; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) return reject(new Error(error || 'Clarity engine failed.'));
      try { return resolve(JSON.parse(output)); } catch (parseError) { return reject(parseError); }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

function getPartners() {
  try {
    const parsed = JSON.parse(process.env.PARTNERS_JSON || '[]');
    return Array.isArray(parsed) ? parsed.filter((partner) =>
      partner && partner.id && partner.name && partner.category && partner.redirectUrl && partner.sourceAttribution,
    ) : [];
  } catch (_error) {
    return [];
  }
}

function createMailer() {
  return nodemailer.createTransport({
    host: requireEnv('EMAIL_HOST'),
    port: Number(process.env.EMAIL_PORT || 465),
    secure: process.env.EMAIL_SECURE !== 'false',
    auth: { user: requireEnv('EMAIL_USER'), pass: requireEnv('EMAIL_PASSWORD') },
  });
}

function createApp({ pool = new Pool({ connectionString: process.env.DATABASE_URL }), mailer = null } = {}) {
  const app = express();
  app.use(express.json({ limit: '100kb' }));
  app.use(express.static(path.join(__dirname, '..', 'frontend-flutter')));

  app.get('/api/v1/health', (_req, res) => res.json({ status: 'ok' }));

  app.post('/api/v1/auth/register', async (req, res) => {
    const { fullName, email, password } = req.body || {};
    if (!fullName || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email || '') || typeof password !== 'string' || password.length < 8) {
      return res.status(400).json({ error: 'fullName, a valid email, and a password of at least 8 characters are required.' });
    }
    const userId = crypto.randomUUID();
    try {
      await pool.query(
        'INSERT INTO users (user_id, full_name, email, password_hash) VALUES ($1, $2, $3, $4)',
        [userId, fullName, email, hashPassword(password)],
      );
      return res.status(201).json({ token: signToken(userId), user: { userId, fullName, email } });
    } catch (error) {
      if (error.code === '23505') return res.status(409).json({ error: 'An account with this email already exists.' });
      throw error;
    }
  });

  app.post('/api/v1/auth/login', async (req, res) => {
    const { email, password } = req.body || {};
    if (!email || typeof password !== 'string') return res.status(400).json({ error: 'email and password are required.' });
    const { rows } = await pool.query('SELECT user_id, full_name, password_hash FROM users WHERE email = $1', [email]);
    if (!rows[0] || !verifyPassword(password, rows[0].password_hash)) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }
    return res.json({ token: signToken(rows[0].user_id), user: { userId: rows[0].user_id, fullName: rows[0].full_name, email } });
  });

  app.post('/api/v1/readiness/sop', authRequired, async (req, res) => {
    const { statement } = req.body || {};
    if (typeof statement !== 'string' || statement.trim().length < 20 || statement.length > 15000) {
      return res.status(400).json({ error: 'Provide a statement between 20 and 15,000 characters.' });
    }
    try {
      return res.json(await runPython({ action: 'lint_sop', statement }));
    } catch (_error) {
      return res.status(503).json({ error: 'The clarity checker is temporarily unavailable.' });
    }
  });

  app.post('/api/v1/readiness/eligibility', authRequired, async (req, res) => {
    let { requirements } = req.body || {};
    const { programId } = req.body || {};
    const { rows } = await pool.query(
      'SELECT cgpa_percentage, liquid_funds_eur FROM users WHERE user_id = $1', [req.user.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'Student profile not found.' });
    if (programId) {
      const { rows: requirementRows } = await pool.query(
        `SELECT minimum_cgpa_percentage, official_funds_requirement_eur, source_url, source_checked_on
         FROM admission_requirements WHERE program_id = $1 ORDER BY source_checked_on DESC LIMIT 1`,
        [programId],
      );
      if (!requirementRows[0]) return res.status(404).json({ error: 'No admission requirements found for this programme.' });
      requirements = requirementRows[0];
    }
    try {
      const result = await runPython({ action: 'evaluate_profile', profile: rows[0], requirements });
      if (programId) {
        const cost = await computeCostView(pool, programId);
        if (cost) result.cost = cost;
      }
      return res.json(result);
    } catch (_error) {
      return res.status(503).json({ error: 'The eligibility checker is temporarily unavailable.' });
    }
  });

  app.get('/api/v1/universities', async (req, res) => {
    const { search, country } = req.query;
    const conditions = [];
    const params = [];
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`name ILIKE $${params.length}`);
    }
    if (country) {
      params.push(String(country).toUpperCase());
      conditions.push(`country_code = $${params.length}`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT university_id, name, country_code, city, website_url FROM universities ${whereClause} ORDER BY name LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/universities/:universityId', async (req, res) => {
    const nationality = req.query.nationality ? String(req.query.nationality).toUpperCase() : null;
    const { rows } = await pool.query(
      `SELECT u.*, COALESCE(json_agg(p ORDER BY p.title) FILTER (WHERE p.program_id IS NOT NULL), '[]') AS programs,
       COALESCE((SELECT json_agg(l) FROM living_cost_estimates l
                 WHERE l.university_id = u.university_id OR (l.university_id IS NULL AND l.country_code = u.country_code)), '[]') AS living_cost_estimates,
       COALESCE((SELECT json_agg(v ORDER BY v.applicant_country_code NULLS FIRST) FROM visa_requirements v
                 WHERE v.destination_country_code = u.country_code
                 AND ($2::char(2) IS NULL OR v.applicant_country_code IS NULL OR v.applicant_country_code = $2)), '[]') AS visa_requirements,
       COALESCE((SELECT json_agg(a ORDER BY a.monthly_rent_eur) FROM student_accommodations a
                 WHERE a.university_id = u.university_id), '[]') AS accommodations
       FROM universities u LEFT JOIN academic_programs p ON p.university_id = u.university_id
       WHERE u.university_id = $1 GROUP BY u.university_id`,
      [req.params.universityId, nationality],
    );
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'University not found.' });
  });

  app.get('/api/v1/programs/:programId', async (req, res) => {
    const { rows } = await pool.query(
      `SELECT p.*, u.name AS university_name, u.country_code, u.city,
       COALESCE((SELECT json_agg(r ORDER BY r.source_checked_on DESC) FROM admission_requirements r WHERE r.program_id = p.program_id), '[]') AS admission_requirements,
       COALESCE((SELECT json_agg(s ORDER BY s.application_deadline NULLS LAST) FROM scholarships s WHERE s.program_id = p.program_id), '[]') AS scholarships,
       COALESCE((SELECT json_agg(f ORDER BY f.fee_type) FROM program_fees f WHERE f.program_id = p.program_id), '[]') AS fees
       FROM academic_programs p JOIN universities u ON u.university_id = p.university_id
       WHERE p.program_id = $1`,
      [req.params.programId],
    );
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Programme not found.' });
  });

  app.get('/api/v1/living-costs', async (req, res) => {
    const { country, city, universityId } = req.query;
    const conditions = [];
    const params = [];
    if (country) {
      params.push(String(country).toUpperCase());
      conditions.push(`country_code = $${params.length}`);
    }
    if (city) {
      params.push(`%${city}%`);
      conditions.push(`city ILIKE $${params.length}`);
    }
    if (universityId) {
      params.push(universityId);
      conditions.push(`university_id = $${params.length}`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM living_cost_estimates ${whereClause} ORDER BY country_code, category LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/scholarships', async (req, res) => {
    const { search, country, universityId, programId } = req.query;
    const conditions = [];
    const params = [];
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`(name ILIKE $${params.length} OR provider ILIKE $${params.length})`);
    }
    if (country) {
      params.push(String(country).toUpperCase());
      conditions.push(`country_code = $${params.length}`);
    }
    if (universityId) {
      params.push(universityId);
      conditions.push(`university_id = $${params.length}`);
    }
    if (programId) {
      params.push(programId);
      conditions.push(`program_id = $${params.length}`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM scholarships ${whereClause} ORDER BY application_deadline NULLS LAST LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/scholarships/:scholarshipId', async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM scholarships WHERE scholarship_id = $1', [req.params.scholarshipId]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Scholarship not found.' });
  });

  app.get('/api/v1/visa-requirements', async (req, res) => {
    const { destinationCountry, applicantCountry } = req.query;
    const conditions = [];
    const params = [];
    if (destinationCountry) {
      params.push(String(destinationCountry).toUpperCase());
      conditions.push(`destination_country_code = $${params.length}`);
    }
    if (applicantCountry) {
      params.push(String(applicantCountry).toUpperCase());
      conditions.push(`(applicant_country_code = $${params.length} OR applicant_country_code IS NULL)`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM visa_requirements ${whereClause} ORDER BY destination_country_code, applicant_country_code NULLS FIRST LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/visa-requirements/:visaRequirementId', async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM visa_requirements WHERE visa_requirement_id = $1', [req.params.visaRequirementId]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Visa requirement not found.' });
  });

  app.get('/api/v1/accommodations', async (req, res) => {
    const { city, universityId, type, maxRent } = req.query;
    const conditions = [];
    const params = [];
    if (city) {
      params.push(`%${city}%`);
      conditions.push(`city ILIKE $${params.length}`);
    }
    if (universityId) {
      params.push(universityId);
      conditions.push(`university_id = $${params.length}`);
    }
    if (type) {
      params.push(String(type).toUpperCase());
      conditions.push(`accommodation_type = $${params.length}`);
    }
    if (maxRent) {
      params.push(Number(maxRent));
      conditions.push(`monthly_rent_eur <= $${params.length}`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM student_accommodations ${whereClause} ORDER BY monthly_rent_eur LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/accommodations/:accommodationId', async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM student_accommodations WHERE accommodation_id = $1', [req.params.accommodationId]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Accommodation not found.' });
  });

  app.get('/api/v1/support-resources', async (req, res) => {
    const { category, country } = req.query;
    const conditions = [];
    const params = [];
    if (category) {
      params.push(String(category).toUpperCase());
      conditions.push(`category = $${params.length}`);
    }
    if (country) {
      params.push(String(country).toUpperCase());
      conditions.push(`(country_code = $${params.length} OR country_code IS NULL)`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM support_resources ${whereClause} ORDER BY category, name LIMIT 50`,
      params,
    );
    res.json(rows);
  });

  app.get('/api/v1/support-resources/:resourceId', async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM support_resources WHERE resource_id = $1', [req.params.resourceId]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Support resource not found.' });
  });

  app.get('/api/v1/me/profile', authRequired, async (req, res) => {
    const { rows } = await pool.query(
      'SELECT user_id, full_name, email, passport_country, cgpa_percentage, liquid_funds_eur FROM users WHERE user_id = $1',
      [req.user.id],
    );
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Account not found.' });
  });

  app.put('/api/v1/me/profile', authRequired, async (req, res) => {
    const { fullName, email, passportCountry, cgpaPercentage, liquidFundsEur } = req.body || {};
    if (!fullName || !email) return res.status(400).json({ error: 'fullName and email are required.' });
    try {
      const { rows } = await pool.query(
        `UPDATE users SET full_name = $2, email = $3, passport_country = $4,
         cgpa_percentage = $5, liquid_funds_eur = $6, updated_at = now()
         WHERE user_id = $1
         RETURNING user_id, full_name, email, passport_country, cgpa_percentage, liquid_funds_eur;`,
        [req.user.id, fullName, email, passportCountry || null, cgpaPercentage ?? null, liquidFundsEur ?? null],
      );
      if (!rows[0]) return res.status(404).json({ error: 'Account not found.' });
      return res.status(200).json(rows[0]);
    } catch (error) {
      if (error.code === '23505') return res.status(409).json({ error: 'That email is already in use by another account.' });
      throw error;
    }
  });

  app.get('/api/v1/applications', authRequired, async (req, res) => {
    const { rows } = await pool.query(
      `SELECT a.*, COALESCE(json_agg(d ORDER BY d.due_at) FILTER (WHERE d.document_id IS NOT NULL), '[]') AS documents
       FROM applications_tracker a LEFT JOIN application_documents d ON d.application_id = a.application_id
       WHERE a.user_id = $1 GROUP BY a.application_id ORDER BY a.deadline_at NULLS LAST`, [req.user.id],
    );
    res.json(rows);
  });

  app.post('/api/v1/applications', authRequired, async (req, res) => {
    const { countryCode, universityName, programTitle, programmeUrl, deadlineAt, documents = [] } = req.body || {};
    if (!/^[A-Za-z]{2}$/.test(countryCode || '') || !universityName || !programTitle || !Array.isArray(documents)) {
      return res.status(400).json({ error: 'countryCode, universityName, programTitle, and documents are required.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const applicationId = crypto.randomUUID();
      await client.query(
        `INSERT INTO applications_tracker (application_id, user_id, country_code, university_name, program_title, programme_url, deadline_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [applicationId, req.user.id, countryCode.toUpperCase(), universityName, programTitle, programmeUrl || null, deadlineAt || null],
      );
      for (const document of documents) {
        if (!document.type || (document.status && !DOCUMENT_STATUSES.has(document.status))) throw new Error('Invalid document checklist item.');
        await client.query(
          `INSERT INTO application_documents (document_id, application_id, document_type, requirement_source_url, status, due_at, notes)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [crypto.randomUUID(), applicationId, document.type, document.sourceUrl || null, document.status || 'NOT_STARTED', document.dueAt || null, document.notes || null],
        );
      }
      await client.query('COMMIT');
      return res.status(201).json({ applicationId });
    } catch (error) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: error.message });
    } finally { client.release(); }
  });

  app.patch('/api/v1/applications/:applicationId/status', authRequired, async (req, res) => {
    const { status } = req.body || {};
    if (!APPLICATION_STATUSES.has(status)) return res.status(400).json({ error: 'Invalid application status.' });
    const { rowCount } = await pool.query(
      `UPDATE applications_tracker SET submission_status = $1::varchar(30), submitted_at = CASE WHEN $1::varchar(30) = 'SUBMITTED' THEN now() ELSE submitted_at END,
       updated_at = now() WHERE application_id = $2 AND user_id = $3`,
      [status, req.params.applicationId, req.user.id],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Application not found.' });
  });

  app.post('/api/v1/lor/requests', authRequired, async (req, res) => {
    const { professorName, professorEmail, universityAffiliation } = req.body || {};
    if (!professorName || !professorEmail || !universityAffiliation) return res.status(400).json({ error: 'Professor name, email, and affiliation are required.' });
    let transporter;
    try { transporter = mailer || createMailer(); requireEnv('PUBLIC_APP_URL'); }
    catch (_error) { return res.status(503).json({ error: 'The recommendation email service is not configured. No email was sent.' }); }
    const requestId = crypto.randomUUID();
    const token = crypto.randomBytes(32).toString('base64url');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000);
    try {
      await pool.query(
        `INSERT INTO professor_lor_requests (request_id, user_id, professor_name, professor_email, university_affiliation, token_hash, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [requestId, req.user.id, professorName, professorEmail, universityAffiliation, tokenHash, expiresAt],
      );
      const url = new URL(`/referee/reference/${token}`, process.env.PUBLIC_APP_URL);
      await transporter.sendMail({
        from: process.env.EMAIL_FROM || process.env.EMAIL_USER, to: professorEmail,
        subject: 'Request for an academic reference',
        text: `Dear ${professorName},\n\nA student has requested an academic reference. If you choose to provide one, use this single-use link before ${expiresAt.toISOString()}: ${url}\n\nThank you.`,
      });
      return res.status(201).json({ requestId, expiresAt });
    } catch (_error) {
      await pool.query('DELETE FROM professor_lor_requests WHERE request_id = $1', [requestId]);
      return res.status(503).json({ error: 'The reference request could not be sent. No active request was created.' });
    }
  });

  app.get('/api/v1/referee/reference/:token', async (req, res) => {
    const tokenHash = crypto.createHash('sha256').update(req.params.token).digest('hex');
    const { rows } = await pool.query(
      `SELECT professor_name, university_affiliation, expires_at FROM professor_lor_requests
       WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > now() AND request_status = 'PENDING'`, [tokenHash],
    );
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'This reference link is invalid, expired, or already used.' });
  });

  app.post('/api/v1/referee/reference/:token', async (req, res) => {
    const { documentKey } = req.body || {};
    if (typeof documentKey !== 'string' || !documentKey.trim() || documentKey.length > 500) return res.status(400).json({ error: 'A secure documentKey is required.' });
    const tokenHash = crypto.createHash('sha256').update(req.params.token).digest('hex');
    const { rowCount } = await pool.query(
      `UPDATE professor_lor_requests SET consumed_at = now(), submitted_document_key = $1, request_status = 'SUBMITTED'
       WHERE token_hash = $2 AND consumed_at IS NULL AND expires_at > now() AND request_status = 'PENDING'`, [documentKey, tokenHash],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'This reference link is invalid, expired, or already used.' });
  });

  app.get('/api/v1/partners', (_req, res) => {
    res.json(getPartners().map(({ redirectUrl, ...partner }) => ({ ...partner, affiliateDisclosure: 'This link may generate a commission for Students-Ecosystem at no additional cost to you.' })));
  });

  app.post('/api/v1/partners/:partnerId/continue', authRequired, async (req, res) => {
    const partner = getPartners().find((item) => item.id === req.params.partnerId);
    if (!partner) return res.status(404).json({ error: 'Verified partner not found.' });
    const trackingToken = crypto.randomBytes(24).toString('base64url');
    await pool.query(
      `INSERT INTO partner_conversions (conversion_id, user_id, partner_id, partner_category, unique_tracking_token, source_attribution)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [crypto.randomUUID(), req.user.id, partner.id, partner.category, trackingToken, partner.sourceAttribution],
    );
    const destination = new URL(partner.redirectUrl);
    destination.searchParams.set('ref', trackingToken);
    return res.json({ partner: partner.name, sourceAttribution: partner.sourceAttribution, affiliateDisclosure: 'Students-Ecosystem may earn a commission if you choose this partner. You are free to compare alternatives.', redirectUrl: destination.toString() });
  });

  return app;
}

if (require.main === module) {
  const app = createApp();
  const port = process.env.PORT || 3000;
  app.listen(port, () => console.log(`Students-Ecosystem running on http://localhost:${port}`));
}

module.exports = { createApp, runPython, hashPassword, verifyPassword, computeCostView };
