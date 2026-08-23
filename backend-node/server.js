const crypto = require('crypto');
const { spawn } = require('child_process');
const path = require('path');
const express = require('express');
const jwt = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const rateLimit = require('express-rate-limit');
const Sentry = require('@sentry/node');
const { Pool } = require('pg');
require('dotenv').config();

// Optional — only activates when an operator sets a real Sentry DSN. Never
// required for local development or tests.
if (process.env.SENTRY_DSN) {
  Sentry.init({ dsn: process.env.SENTRY_DSN, tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE || 0) });
}

const APPLICATION_STATUSES = new Set(['DRAFT', 'DOCUMENTS_IN_PROGRESS', 'SUBMITTED', 'OFFER_RECEIVED', 'DECLINED', 'WITHDRAWN']);
const DOCUMENT_STATUSES = new Set(['NOT_STARTED', 'IN_PROGRESS', 'READY', 'SUBMITTED', 'NOT_REQUIRED']);

// Admin CMS: a generic CRUD layer over the sourced content tables, so a new
// university/scholarship/fee/etc. can be entered through an authenticated API
// call instead of a hand-written SQL migration. Column lists are a fixed
// whitelist taken straight from database/schema.sql — never derived from
// request input — so building SQL with them by string interpolation is safe;
// only the values are parameterized. NOT NULL/CHECK constraints (e.g. a
// source_url being required) are still enforced by Postgres itself and
// surfaced back as a friendly 400 via friendlyDbError().
const ADMIN_RESOURCES = {
  universities: {
    idColumn: 'university_id',
    columns: ['name', 'country_code', 'city', 'website_url'],
    requiredColumns: ['name', 'country_code'],
  },
  academic_programs: {
    idColumn: 'program_id',
    columns: ['university_id', 'title', 'degree_level', 'field_of_study', 'duration_months', 'duration_weeks', 'programme_url'],
    requiredColumns: ['university_id', 'title', 'degree_level'],
  },
  admission_requirements: {
    idColumn: 'requirement_id',
    columns: ['program_id', 'minimum_cgpa_percentage', 'official_funds_requirement_eur', 'language_test_name', 'minimum_language_score', 'required_documents', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['program_id', 'source_url', 'source_checked_on'],
  },
  scholarships: {
    idColumn: 'scholarship_id',
    columns: ['name', 'provider', 'country_code', 'university_id', 'program_id', 'coverage_type', 'amount_eur', 'eligibility_notes', 'application_deadline', 'application_url', 'source_url', 'source_checked_on'],
    requiredColumns: ['name', 'provider', 'coverage_type', 'source_url', 'source_checked_on'],
  },
  program_fees: {
    idColumn: 'fee_id',
    columns: ['program_id', 'fee_type', 'student_category', 'amount_eur', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['program_id', 'fee_type', 'amount_eur', 'source_url', 'source_checked_on'],
  },
  living_cost_estimates: {
    idColumn: 'estimate_id',
    columns: ['country_code', 'city', 'university_id', 'category', 'monthly_estimate_eur', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['country_code', 'monthly_estimate_eur', 'source_url', 'source_checked_on'],
  },
  visa_requirements: {
    idColumn: 'visa_requirement_id',
    columns: ['destination_country_code', 'applicant_country_code', 'visa_type', 'financial_proof_eur', 'estimated_processing_days', 'minimum_passport_validity_months', 'required_documents', 'application_url', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['destination_country_code', 'visa_type', 'source_url', 'source_checked_on'],
  },
  student_accommodations: {
    idColumn: 'accommodation_id',
    columns: ['university_id', 'accommodation_type', 'provider_name', 'city', 'monthly_rent_eur', 'deposit_eur', 'distance_to_university_km', 'amenities', 'application_url', 'contact_email', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['university_id', 'accommodation_type', 'provider_name', 'city', 'monthly_rent_eur', 'source_url', 'source_checked_on'],
  },
  support_resources: {
    idColumn: 'resource_id',
    columns: ['name', 'provider', 'category', 'country_code', 'description', 'eligibility_notes', 'application_url', 'contact_email', 'source_url', 'source_checked_on', 'notes'],
    requiredColumns: ['name', 'provider', 'category', 'description', 'source_url', 'source_checked_on'],
  },
};

function friendlyDbError(error) {
  if (error.code === '23502') return `Missing required field: ${error.column}.`;
  if (error.code === '23503') return `Invalid reference — ${error.detail || 'a referenced row does not exist'}.`;
  if (error.code === '23505') return `Duplicate value — ${error.detail || error.message}.`;
  if (error.code === '23514') return `Value violates a constraint (${error.constraint}) — ${error.detail || error.message}.`;
  return null;
}

function httpError(statusCode, message) {
  return Object.assign(new Error(message), { statusCode });
}

// Shared by the direct admin CRUD endpoints and by approving a crowdsourced
// submission — both ultimately need to insert/update one row against the
// same column whitelist and the same friendly-error translation.
async function createResourceRow(pool, resource, body) {
  const config = ADMIN_RESOURCES[resource];
  if (!config) throw httpError(404, 'Unknown resource.');
  const missing = config.requiredColumns.filter((column) => body[column] === undefined || body[column] === null || body[column] === '');
  if (missing.length) throw httpError(400, `Missing required field(s): ${missing.join(', ')}.`);
  const id = crypto.randomUUID();
  const providedColumns = config.columns.filter((column) => body[column] !== undefined);
  const allColumns = [config.idColumn, ...providedColumns];
  const values = [id, ...providedColumns.map((column) => body[column])];
  const placeholders = allColumns.map((_column, index) => `$${index + 1}`);
  try {
    await pool.query(`INSERT INTO ${resource} (${allColumns.join(', ')}) VALUES (${placeholders.join(', ')})`, values);
  } catch (error) {
    const friendly = friendlyDbError(error);
    if (friendly) throw httpError(400, friendly);
    throw error;
  }
  return { [config.idColumn]: id };
}

async function updateResourceRow(pool, resource, id, body) {
  const config = ADMIN_RESOURCES[resource];
  if (!config) throw httpError(404, 'Unknown resource.');
  const providedColumns = config.columns.filter((column) => body[column] !== undefined);
  if (!providedColumns.length) throw httpError(400, 'No updatable fields were provided.');
  const setClause = providedColumns.map((column, index) => `${column} = $${index + 2}`).join(', ');
  const values = [id, ...providedColumns.map((column) => body[column])];
  try {
    const { rowCount } = await pool.query(`UPDATE ${resource} SET ${setClause}, updated_at = now() WHERE ${config.idColumn} = $1`, values);
    if (!rowCount) throw httpError(404, 'Not found.');
  } catch (error) {
    if (error.statusCode) throw error;
    const friendly = friendlyDbError(error);
    if (friendly) throw httpError(400, friendly);
    throw error;
  }
}

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
  const estimatedAnnualTuitionEur = sum(['TUITION_PER_YEAR', 'ADMINISTRATIVE_FEE', 'TUITION_TOTAL', 'TUITION_PER_SEMESTER']);
  const oneTimeFeesEur = sum(['APPLICATION_FEE']);
  const { rows: scholarshipRows } = await pool.query('SELECT amount_eur FROM scholarships WHERE program_id = $1', [programId]);
  const totalPotentialScholarshipValueEur = scholarshipRows.reduce((total, s) => total + Number(s.amount_eur || 0), 0);
  return {
    estimated_annual_tuition_eur: estimatedAnnualTuitionEur,
    one_time_fees_eur: oneTimeFeesEur,
    total_potential_scholarship_value_eur: totalPotentialScholarshipValueEur,
    estimated_net_annual_cost_if_awarded_eur: Math.max(0, estimatedAnnualTuitionEur - totalPotentialScholarshipValueEur),
    caveat: 'This assumes you receive every listed scholarship at once, which is unlikely — check eligibility criteria for each individually. '
      + 'If the programme\'s fee is published as a one-time whole-programme/whole-course total or a per-semester rate rather than a per-year rate (see the fee\'s own notes), this figure is that total or single-semester amount, not necessarily a full year\'s cost — not an official cost figure either way.',
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

function adminApiKeyRequired(req, res, next) {
  const configuredKey = process.env.ADMIN_API_KEY;
  const providedKey = req.get('x-admin-api-key');
  if (!configuredKey || !providedKey || providedKey !== configuredKey) {
    return res.status(401).json({ error: 'A valid admin API key is required.' });
  }
  return next();
}

// Institute analytics API keys — each key is scoped to exactly one
// universityId so one institute can never see another's demand data.
// Configured per operator via INSTITUTE_ANALYTICS_KEYS_JSON, e.g.
// '[{"apiKey":"...","universityId":"..."}]'.
function getInstituteApiKeys() {
  try {
    const parsed = JSON.parse(process.env.INSTITUTE_ANALYTICS_KEYS_JSON || '[]');
    return Array.isArray(parsed) ? parsed.filter((entry) => entry && entry.apiKey && entry.universityId) : [];
  } catch (_error) {
    return [];
  }
}

// Contextual, direct-sold sponsor placements — never behavioral/tracking ads,
// never mixed into search ranking or Find My Matches. Configured per operator
// via SPONSORED_CONTENT_JSON, same shape/spirit as PARTNERS_JSON above.
function getSponsoredContent() {
  try {
    const parsed = JSON.parse(process.env.SPONSORED_CONTENT_JSON || '[]');
    return Array.isArray(parsed) ? parsed.filter((item) =>
      item && item.id && item.sponsorName && item.headline && item.linkUrl,
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

  app.use((req, res, next) => {
    const startedAt = Date.now();
    res.on('finish', () => {
      console.log(JSON.stringify({
        level: 'info', type: 'request', method: req.method, path: req.path,
        status: res.statusCode, durationMs: Date.now() - startedAt,
      }));
    });
    next();
  });

  const authRateLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: Number(process.env.AUTH_RATE_LIMIT_MAX || 20),
    standardHeaders: true,
    legacyHeaders: false,
    handler: (_req, res) => res.status(429).json({ error: 'Too many attempts. Please wait a few minutes and try again.' }),
  });

  app.get('/api/v1/health', (_req, res) => res.json({ status: 'ok' }));

  app.post('/api/v1/auth/register', authRateLimiter, async (req, res) => {
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

  app.post('/api/v1/auth/login', authRateLimiter, async (req, res) => {
    const { email, password } = req.body || {};
    if (!email || typeof password !== 'string') return res.status(400).json({ error: 'email and password are required.' });
    const { rows } = await pool.query('SELECT user_id, full_name, password_hash FROM users WHERE email = $1', [email]);
    if (!rows[0] || !verifyPassword(password, rows[0].password_hash)) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }
    return res.json({ token: signToken(rows[0].user_id), user: { userId: rows[0].user_id, fullName: rows[0].full_name, email } });
  });

  app.post('/api/v1/auth/password-reset/request', authRateLimiter, async (req, res) => {
    const { email } = req.body || {};
    if (!email) return res.status(400).json({ error: 'email is required.' });
    const genericResponse = { message: 'If an account with that email exists, a password reset link has been sent.' };
    try {
      const { rows } = await pool.query('SELECT user_id, full_name FROM users WHERE email = $1', [email]);
      if (rows[0]) {
        const transporter = mailer || createMailer();
        requireEnv('PUBLIC_APP_URL');
        const token = crypto.randomBytes(32).toString('base64url');
        const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
        const expiresAt = new Date(Date.now() + 60 * 60 * 1000);
        await pool.query(
          'INSERT INTO password_reset_tokens (token_id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)',
          [crypto.randomUUID(), rows[0].user_id, tokenHash, expiresAt],
        );
        const url = new URL('/', process.env.PUBLIC_APP_URL);
        url.searchParams.set('resetToken', token);
        await transporter.sendMail({
          from: process.env.EMAIL_FROM || process.env.EMAIL_USER, to: email,
          subject: 'Reset your Students-Ecosystem password',
          text: `Hi ${rows[0].full_name},\n\nUse this link within 1 hour to reset your password: ${url.toString()}\n\nIf you didn't request this, you can ignore this email.`,
        });
      }
    } catch (_error) { /* never leak account existence or infra/config errors to an unauthenticated caller */ }
    return res.json(genericResponse);
  });

  app.post('/api/v1/auth/password-reset/confirm', authRateLimiter, async (req, res) => {
    const { token, newPassword } = req.body || {};
    if (typeof token !== 'string' || !token || typeof newPassword !== 'string' || newPassword.length < 8) {
      return res.status(400).json({ error: 'A valid token and a password of at least 8 characters are required.' });
    }
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const { rows } = await pool.query(
      `SELECT token_id, user_id FROM password_reset_tokens WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > now()`,
      [tokenHash],
    );
    if (!rows[0]) return res.status(400).json({ error: 'This reset link is invalid or has expired.' });
    await pool.query('UPDATE users SET password_hash = $1, updated_at = now() WHERE user_id = $2', [hashPassword(newPassword), rows[0].user_id]);
    await pool.query('UPDATE password_reset_tokens SET consumed_at = now() WHERE token_id = $1', [rows[0].token_id]);
    return res.status(200).json({ message: 'Password updated. You can now log in with your new password.' });
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

  app.get('/api/v1/me/readiness/documents', authRequired, async (req, res) => {
    const countryCode = req.query.countryCode ? String(req.query.countryCode).toUpperCase() : null;
    if (!countryCode) return res.status(400).json({ error: 'countryCode is required.' });
    const nationality = req.query.nationality ? String(req.query.nationality).toUpperCase() : null;
    const [{ rows: docRows }, { rows: requirementRows }] = await Promise.all([
      pool.query('SELECT document_type, expires_at FROM student_documents WHERE user_id = $1', [req.user.id]),
      pool.query(
        `SELECT minimum_passport_validity_months, source_url, source_checked_on
         FROM visa_requirements
         WHERE destination_country_code = $1
           AND ($2::char(2) IS NULL OR applicant_country_code IS NULL OR applicant_country_code = $2)
         ORDER BY applicant_country_code NULLS LAST, source_checked_on DESC LIMIT 1`,
        [countryCode, nationality],
      ),
    ]);
    try {
      const result = await runPython({
        action: 'check_document_readiness',
        documents: docRows,
        requirement: requirementRows[0] || null,
      });
      return res.json(result);
    } catch (_error) {
      return res.status(503).json({ error: 'The document readiness checker is temporarily unavailable.' });
    }
  });

  app.get('/api/v1/matches', authRequired, async (req, res) => {
    const { rows: userRows } = await pool.query(
      'SELECT cgpa_percentage, liquid_funds_eur FROM users WHERE user_id = $1', [req.user.id],
    );
    if (!userRows[0]) return res.status(404).json({ error: 'Student profile not found.' });
    const profile = userRows[0];

    const conditions = [];
    const params = [];
    if (req.query.countryCode) {
      params.push(String(req.query.countryCode).toUpperCase());
      conditions.push(`u.country_code = $${params.length}`);
    }
    if (req.query.degreeLevel) {
      params.push(String(req.query.degreeLevel).toUpperCase());
      conditions.push(`p.degree_level = $${params.length}`);
    }
    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const { rows: candidateRows } = await pool.query(
      `SELECT p.program_id, p.title, p.degree_level, p.field_of_study,
              u.name AS university_name, u.country_code,
              req.minimum_cgpa_percentage, req.official_funds_requirement_eur, req.source_url, req.source_checked_on,
              COALESCE(fee.estimated_annual_tuition_eur, 0) AS estimated_annual_tuition_eur,
              COALESCE(fee.one_time_fees_eur, 0) AS one_time_fees_eur,
              COALESCE(sch.total_potential_scholarship_value_eur, 0) AS total_potential_scholarship_value_eur
       FROM academic_programs p
       JOIN universities u ON u.university_id = p.university_id
       LEFT JOIN LATERAL (
         SELECT minimum_cgpa_percentage, official_funds_requirement_eur, source_url, source_checked_on
         FROM admission_requirements ar WHERE ar.program_id = p.program_id
         ORDER BY source_checked_on DESC LIMIT 1
       ) req ON true
       LEFT JOIN LATERAL (
         SELECT SUM(amount_eur) FILTER (WHERE fee_type IN ('TUITION_PER_YEAR', 'ADMINISTRATIVE_FEE', 'TUITION_TOTAL', 'TUITION_PER_SEMESTER')) AS estimated_annual_tuition_eur,
                SUM(amount_eur) FILTER (WHERE fee_type = 'APPLICATION_FEE') AS one_time_fees_eur
         FROM program_fees WHERE program_id = p.program_id AND student_category = 'INTERNATIONAL'
       ) fee ON true
       LEFT JOIN LATERAL (
         SELECT SUM(amount_eur) AS total_potential_scholarship_value_eur FROM scholarships WHERE program_id = p.program_id
       ) sch ON true
       ${whereClause}
       ORDER BY u.name, p.title`,
      params,
    );

    let evaluations;
    try {
      evaluations = await runPython({
        action: 'evaluate_candidates',
        profile,
        candidates: candidateRows.map((row) => ({
          program_id: row.program_id,
          requirements: {
            minimum_cgpa_percentage: row.minimum_cgpa_percentage,
            official_funds_requirement_eur: row.official_funds_requirement_eur,
            source_url: row.source_url,
            source_checked_on: row.source_checked_on,
          },
        })),
      });
    } catch (_error) {
      return res.status(503).json({ error: 'The matching engine is temporarily unavailable.' });
    }
    const evaluationByProgramId = new Map(evaluations.map((evaluation) => [evaluation.program_id, evaluation]));
    const maxBudgetEur = req.query.maxBudgetEur !== undefined ? Number(req.query.maxBudgetEur) : null;
    const rank = (academicStatus) => (academicStatus === 'MEETS_STATED_MINIMUM' ? 0 : academicStatus === 'BELOW_STATED_MINIMUM' ? 2 : 1);

    const matches = candidateRows
      .map((row) => {
        const evaluation = evaluationByProgramId.get(row.program_id) || {};
        const estimatedNetAnnualCostIfAwardedEur = Math.max(
          0, Number(row.estimated_annual_tuition_eur) - Number(row.total_potential_scholarship_value_eur),
        );
        return {
          program_id: row.program_id,
          title: row.title,
          degree_level: row.degree_level,
          field_of_study: row.field_of_study,
          university_name: row.university_name,
          country_code: row.country_code,
          estimated_annual_tuition_eur: Number(row.estimated_annual_tuition_eur),
          one_time_fees_eur: Number(row.one_time_fees_eur),
          total_potential_scholarship_value_eur: Number(row.total_potential_scholarship_value_eur),
          estimated_net_annual_cost_if_awarded_eur: estimatedNetAnnualCostIfAwardedEur,
          academic: evaluation.academic || { status: 'NOT_COMPARED' },
          funding: evaluation.funding || { status: 'NOT_COMPARED' },
        };
      })
      .filter((match) => maxBudgetEur === null || Number.isNaN(maxBudgetEur)
        || match.estimated_annual_tuition_eur === 0 || match.estimated_net_annual_cost_if_awarded_eur <= maxBudgetEur)
      .sort((a, b) => {
        const rankDiff = rank(a.academic.status) - rank(b.academic.status);
        return rankDiff !== 0 ? rankDiff : a.estimated_net_annual_cost_if_awarded_eur - b.estimated_net_annual_cost_if_awarded_eur;
      });

    return res.json({
      matches,
      caveat: 'Ranked from your self-reported CGPA/funds against the most recently checked official requirement on file. '
        + 'Programmes with no sourced requirement or fee data are still listed, marked as not compared — always confirm directly with the university.',
    });
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
    if (!rows[0]) return res.status(404).json({ error: 'University not found.' });
    try {
      await pool.query(
        `INSERT INTO demand_events (event_id, event_type, university_id, country_code) VALUES ($1, 'UNIVERSITY_VIEW', $2, $3)`,
        [crypto.randomUUID(), rows[0].university_id, rows[0].country_code],
      );
    } catch (_error) { /* best-effort demand analytics; never blocks or breaks the response */ }
    return res.json(rows[0]);
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
    if (!rows[0]) return res.status(404).json({ error: 'Programme not found.' });
    try {
      await pool.query(
        `INSERT INTO demand_events (event_id, event_type, university_id, program_id, country_code) VALUES ($1, 'PROGRAM_VIEW', $2, $3, $4)`,
        [crypto.randomUUID(), rows[0].university_id, rows[0].program_id, rows[0].country_code],
      );
    } catch (_error) { /* best-effort demand analytics; never blocks or breaks the response */ }
    return res.json(rows[0]);
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

  app.get('/api/v1/me/export', authRequired, async (req, res) => {
    const { rows: userRows } = await pool.query(
      'SELECT user_id, full_name, email, passport_country, cgpa_percentage, liquid_funds_eur, created_at FROM users WHERE user_id = $1',
      [req.user.id],
    );
    if (!userRows[0]) return res.status(404).json({ error: 'Account not found.' });
    const [{ rows: applications }, { rows: personalDocuments }, { rows: lorRequests }, { rows: partnerReferrals }] = await Promise.all([
      pool.query(
        `SELECT a.*, COALESCE(json_agg(d) FILTER (WHERE d.document_id IS NOT NULL), '[]') AS documents
         FROM applications_tracker a LEFT JOIN application_documents d ON d.application_id = a.application_id
         WHERE a.user_id = $1 GROUP BY a.application_id`, [req.user.id],
      ),
      pool.query('SELECT * FROM student_documents WHERE user_id = $1', [req.user.id]),
      pool.query(
        'SELECT request_id, professor_name, professor_email, university_affiliation, request_status, created_at FROM professor_lor_requests WHERE user_id = $1',
        [req.user.id],
      ),
      pool.query('SELECT conversion_id, partner_id, partner_category, conversion_status, created_at FROM partner_conversions WHERE user_id = $1', [req.user.id]),
    ]);
    return res.json({
      exportedAt: new Date().toISOString(),
      profile: userRows[0],
      applications,
      personalDocuments,
      referenceRequests: lorRequests,
      partnerReferrals,
    });
  });

  app.delete('/api/v1/me', authRequired, async (req, res) => {
    const { password } = req.body || {};
    if (typeof password !== 'string' || !password) return res.status(400).json({ error: 'Your current password is required to delete your account.' });
    const { rows } = await pool.query('SELECT password_hash FROM users WHERE user_id = $1', [req.user.id]);
    if (!rows[0]) return res.status(404).json({ error: 'Account not found.' });
    if (!verifyPassword(password, rows[0].password_hash)) return res.status(401).json({ error: 'Incorrect password.' });
    await pool.query('DELETE FROM users WHERE user_id = $1', [req.user.id]);
    return res.status(204).end();
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

  app.patch('/api/v1/applications/:applicationId/deadline', authRequired, async (req, res) => {
    const { deadlineAt } = req.body || {};
    if (deadlineAt !== null && Number.isNaN(Date.parse(deadlineAt))) {
      return res.status(400).json({ error: 'deadlineAt must be a valid date or null.' });
    }
    const { rowCount } = await pool.query(
      `UPDATE applications_tracker SET deadline_at = $1::date, updated_at = now() WHERE application_id = $2 AND user_id = $3`,
      [deadlineAt, req.params.applicationId, req.user.id],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Application not found.' });
  });

  app.post('/api/v1/applications/:applicationId/documents', authRequired, async (req, res) => {
    const { type, sourceUrl, status, dueAt, notes } = req.body || {};
    if (!type || (status && !DOCUMENT_STATUSES.has(status))) {
      return res.status(400).json({ error: 'A document type (and a valid status, if provided) is required.' });
    }
    const { rows: applicationRows } = await pool.query(
      'SELECT 1 FROM applications_tracker WHERE application_id = $1 AND user_id = $2', [req.params.applicationId, req.user.id],
    );
    if (!applicationRows[0]) return res.status(404).json({ error: 'Application not found.' });
    const documentId = crypto.randomUUID();
    await pool.query(
      `INSERT INTO application_documents (document_id, application_id, document_type, requirement_source_url, status, due_at, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [documentId, req.params.applicationId, type, sourceUrl || null, status || 'NOT_STARTED', dueAt || null, notes || null],
    );
    return res.status(201).json({ documentId });
  });

  app.patch('/api/v1/applications/:applicationId/documents/:documentId', authRequired, async (req, res) => {
    const { status, dueAt, notes } = req.body || {};
    if (status !== undefined && !DOCUMENT_STATUSES.has(status)) return res.status(400).json({ error: 'Invalid document status.' });
    if (dueAt !== undefined && dueAt !== null && Number.isNaN(Date.parse(dueAt))) return res.status(400).json({ error: 'dueAt must be a valid date or null.' });
    const { rowCount } = await pool.query(
      `UPDATE application_documents d SET
         status = COALESCE($1, d.status), due_at = CASE WHEN $2::boolean THEN $3::date ELSE d.due_at END,
         notes = COALESCE($4, d.notes), updated_at = now()
       FROM applications_tracker a
       WHERE d.application_id = a.application_id AND d.document_id = $5 AND d.application_id = $6 AND a.user_id = $7`,
      [status || null, dueAt !== undefined, dueAt ?? null, notes ?? null, req.params.documentId, req.params.applicationId, req.user.id],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Document not found.' });
  });

  app.get('/api/v1/me/documents', authRequired, async (req, res) => {
    const { rows } = await pool.query(
      'SELECT * FROM student_documents WHERE user_id = $1 ORDER BY expires_at NULLS LAST, document_type', [req.user.id],
    );
    res.json(rows);
  });

  app.post('/api/v1/me/documents', authRequired, async (req, res) => {
    const { documentType, label, obtainedAt, expiresAt, notes } = req.body || {};
    if (!documentType) return res.status(400).json({ error: 'documentType is required.' });
    if (obtainedAt && Number.isNaN(Date.parse(obtainedAt))) return res.status(400).json({ error: 'obtainedAt must be a valid date.' });
    if (expiresAt && Number.isNaN(Date.parse(expiresAt))) return res.status(400).json({ error: 'expiresAt must be a valid date.' });
    const studentDocumentId = crypto.randomUUID();
    await pool.query(
      `INSERT INTO student_documents (student_document_id, user_id, document_type, label, obtained_at, expires_at, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [studentDocumentId, req.user.id, documentType, label || null, obtainedAt || null, expiresAt || null, notes || null],
    );
    return res.status(201).json({ studentDocumentId });
  });

  app.patch('/api/v1/me/documents/:studentDocumentId', authRequired, async (req, res) => {
    const { label, obtainedAt, expiresAt, notes } = req.body || {};
    if (obtainedAt !== undefined && obtainedAt !== null && Number.isNaN(Date.parse(obtainedAt))) return res.status(400).json({ error: 'obtainedAt must be a valid date or null.' });
    if (expiresAt !== undefined && expiresAt !== null && Number.isNaN(Date.parse(expiresAt))) return res.status(400).json({ error: 'expiresAt must be a valid date or null.' });
    const { rowCount } = await pool.query(
      `UPDATE student_documents SET
         label = COALESCE($1, label),
         obtained_at = CASE WHEN $2::boolean THEN $3::date ELSE obtained_at END,
         expires_at = CASE WHEN $4::boolean THEN $5::date ELSE expires_at END,
         notes = COALESCE($6, notes), updated_at = now()
       WHERE student_document_id = $7 AND user_id = $8`,
      [label || null, obtainedAt !== undefined, obtainedAt ?? null, expiresAt !== undefined, expiresAt ?? null, notes ?? null, req.params.studentDocumentId, req.user.id],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Document not found.' });
  });

  app.delete('/api/v1/me/documents/:studentDocumentId', authRequired, async (req, res) => {
    const { rowCount } = await pool.query(
      'DELETE FROM student_documents WHERE student_document_id = $1 AND user_id = $2', [req.params.studentDocumentId, req.user.id],
    );
    return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Document not found.' });
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

  app.get('/api/v1/sponsored-content', (req, res) => {
    const countryCode = req.query.countryCode ? String(req.query.countryCode).toUpperCase() : null;
    const items = getSponsoredContent()
      .filter((item) => !item.countryCode || item.countryCode === countryCode)
      .map((item) => ({
        id: item.id, sponsorName: item.sponsorName, headline: item.headline, body: item.body || null,
        linkUrl: item.linkUrl, countryCode: item.countryCode || null,
        disclosure: item.disclosure || 'Sponsored placement — paid for by the sponsor. It never affects search results or Find My Matches ranking.',
      }));
    return res.json(items);
  });

  app.get('/api/v1/analytics/demand', async (req, res) => {
    const providedKey = req.get('x-institute-api-key');
    const keyEntry = getInstituteApiKeys().find((entry) => entry.apiKey === providedKey);
    if (!keyEntry) return res.status(401).json({ error: 'A valid institute analytics API key is required.' });
    const { rows } = await pool.query(
      `SELECT event_type, date_trunc('day', occurred_at)::date AS day, count(*)::int AS view_count
       FROM demand_events WHERE university_id = $1 GROUP BY event_type, day ORDER BY day DESC`,
      [keyEntry.universityId],
    );
    return res.json({
      universityId: keyEntry.universityId,
      events: rows,
      disclaimer: 'Aggregate, anonymized view counts for your institution only — no individual student data is included or ever shared.',
    });
  });

  app.get('/api/v1/admin/resources', adminApiKeyRequired, (_req, res) => {
    res.json(Object.keys(ADMIN_RESOURCES));
  });

  app.get('/api/v1/admin/:resource/_schema', adminApiKeyRequired, (req, res) => {
    const config = ADMIN_RESOURCES[req.params.resource];
    if (!config) return res.status(404).json({ error: 'Unknown resource.' });
    return res.json({ idColumn: config.idColumn, columns: config.columns, requiredColumns: config.requiredColumns });
  });

  // Crowdsourced "Live-Verify" submissions. Any logged-in student can suggest
  // a new record or a correction, but nothing here ever reaches another
  // student until an admin approves it via the endpoints below — a
  // submission never writes to the live content tables on its own. These
  // must be registered before the generic /api/v1/admin/:resource[/:id]
  // routes below, or Express would match "submissions" as a :resource value
  // there instead of reaching these handlers.
  app.post('/api/v1/submissions', authRequired, async (req, res) => {
    const { targetResource, targetRecordId, proposedData, sourceUrl, submitterNote } = req.body || {};
    if (!ADMIN_RESOURCES[targetResource]) return res.status(400).json({ error: 'Unknown target resource.' });
    if (!proposedData || typeof proposedData !== 'object' || Array.isArray(proposedData)) {
      return res.status(400).json({ error: 'proposedData must be an object of field values.' });
    }
    if (typeof sourceUrl !== 'string' || !/^https?:\/\//i.test(sourceUrl)) {
      return res.status(400).json({ error: 'A valid sourceUrl (http:// or https://) is required — nothing is accepted without a source.' });
    }
    const submissionId = crypto.randomUUID();
    await pool.query(
      `INSERT INTO content_submissions (submission_id, submitted_by_user_id, target_resource, target_record_id, proposed_data, source_url, submitter_note)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [submissionId, req.user.id, targetResource, targetRecordId || null, JSON.stringify(proposedData), sourceUrl, submitterNote || null],
    );
    return res.status(201).json({
      submissionId, status: 'PENDING',
      message: 'Thanks — this is queued for review and will not appear to other students until an admin approves it.',
    });
  });

  app.get('/api/v1/me/submissions', authRequired, async (req, res) => {
    const { rows } = await pool.query(
      `SELECT submission_id, target_resource, target_record_id, proposed_data, source_url, submitter_note, status, review_notes, reviewed_at, created_at
       FROM content_submissions WHERE submitted_by_user_id = $1 ORDER BY created_at DESC`,
      [req.user.id],
    );
    return res.json(rows);
  });

  app.get('/api/v1/admin/submissions', adminApiKeyRequired, async (req, res) => {
    const status = req.query.status ? String(req.query.status).toUpperCase() : null;
    const { rows } = await pool.query(
      `SELECT * FROM content_submissions WHERE ($1::varchar IS NULL OR status = $1) ORDER BY created_at ASC`,
      [status],
    );
    return res.json(rows);
  });

  app.get('/api/v1/admin/submissions/:id', adminApiKeyRequired, async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM content_submissions WHERE submission_id = $1', [req.params.id]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Not found.' });
  });

  app.post('/api/v1/admin/submissions/:id/approve', adminApiKeyRequired, async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM content_submissions WHERE submission_id = $1', [req.params.id]);
    const submission = rows[0];
    if (!submission) return res.status(404).json({ error: 'Not found.' });
    if (submission.status !== 'PENDING') return res.status(400).json({ error: `This submission was already ${submission.status.toLowerCase()}.` });
    const config = ADMIN_RESOURCES[submission.target_resource];
    const mergedData = { ...submission.proposed_data };
    if (config.columns.includes('source_url') && !mergedData.source_url) mergedData.source_url = submission.source_url;
    try {
      let result;
      if (submission.target_record_id) {
        await updateResourceRow(pool, submission.target_resource, submission.target_record_id, mergedData);
        result = { [config.idColumn]: submission.target_record_id };
      } else {
        result = await createResourceRow(pool, submission.target_resource, mergedData);
      }
      await pool.query(
        `UPDATE content_submissions SET status = 'APPROVED', review_notes = $2, reviewed_at = now() WHERE submission_id = $1`,
        [req.params.id, (req.body && req.body.reviewNotes) || null],
      );
      return res.status(200).json({ status: 'APPROVED', result });
    } catch (error) {
      if (error.statusCode) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  });

  app.post('/api/v1/admin/submissions/:id/reject', adminApiKeyRequired, async (req, res) => {
    const { rowCount } = await pool.query(
      `UPDATE content_submissions SET status = 'REJECTED', review_notes = $2, reviewed_at = now() WHERE submission_id = $1 AND status = 'PENDING'`,
      [req.params.id, (req.body && req.body.reviewNotes) || null],
    );
    return rowCount ? res.status(200).json({ status: 'REJECTED' }) : res.status(404).json({ error: 'Not found or already reviewed.' });
  });

  app.get('/api/v1/admin/:resource', adminApiKeyRequired, async (req, res) => {
    const config = ADMIN_RESOURCES[req.params.resource];
    if (!config) return res.status(404).json({ error: 'Unknown resource.' });
    const { rows } = await pool.query(`SELECT * FROM ${req.params.resource} ORDER BY ${config.idColumn} LIMIT 500`);
    return res.json(rows);
  });

  app.get('/api/v1/admin/:resource/:id', adminApiKeyRequired, async (req, res) => {
    const config = ADMIN_RESOURCES[req.params.resource];
    if (!config) return res.status(404).json({ error: 'Unknown resource.' });
    const { rows } = await pool.query(`SELECT * FROM ${req.params.resource} WHERE ${config.idColumn} = $1`, [req.params.id]);
    return rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Not found.' });
  });

  app.post('/api/v1/admin/:resource', adminApiKeyRequired, async (req, res) => {
    try {
      const result = await createResourceRow(pool, req.params.resource, req.body || {});
      return res.status(201).json(result);
    } catch (error) {
      if (error.statusCode) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  });

  app.patch('/api/v1/admin/:resource/:id', adminApiKeyRequired, async (req, res) => {
    try {
      await updateResourceRow(pool, req.params.resource, req.params.id, req.body || {});
      return res.status(204).end();
    } catch (error) {
      if (error.statusCode) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  });

  app.delete('/api/v1/admin/:resource/:id', adminApiKeyRequired, async (req, res) => {
    const config = ADMIN_RESOURCES[req.params.resource];
    if (!config) return res.status(404).json({ error: 'Unknown resource.' });
    try {
      const { rowCount } = await pool.query(`DELETE FROM ${req.params.resource} WHERE ${config.idColumn} = $1`, [req.params.id]);
      return rowCount ? res.status(204).end() : res.status(404).json({ error: 'Not found.' });
    } catch (error) {
      const friendly = friendlyDbError(error);
      if (friendly) return res.status(400).json({ error: friendly });
      throw error;
    }
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    console.error(JSON.stringify({ level: 'error', type: 'unhandled_error', method: req.method, path: req.path, message: err.message }));
    if (process.env.SENTRY_DSN) Sentry.captureException(err);
    if (res.headersSent) return;
    res.status(500).json({ error: 'Something went wrong. Please try again.' });
  });

  return app;
}

if (require.main === module) {
  const app = createApp();
  const port = process.env.PORT || 3000;
  app.listen(port, () => console.log(`Students-Ecosystem running on http://localhost:${port}`));
}

module.exports = { createApp, runPython, hashPassword, verifyPassword, computeCostView, createMailer };
