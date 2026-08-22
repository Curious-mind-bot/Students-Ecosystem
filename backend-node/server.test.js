process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp, hashPassword, computeCostView } = require('./server');

function mockPool(handler) {
  return { query: async (text, params) => handler(text, params), connect: async () => ({ query: async () => ({ rows: [] }), release() {} }) };
}

test('GET /api/v1/universities filters by search and country', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /ILIKE/);
    assert.match(text, /country_code = \$2/);
    assert.deepEqual(params, ['%Delft%', 'NL']);
    return { rows: [{ university_id: '1', name: 'TU Delft', country_code: 'NL', city: 'Delft', website_url: 'https://tudelft.nl' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/universities?search=Delft&country=nl`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].name, 'TU Delft');
  server.close();
});

test('GET /api/v1/universities/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/universities/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/universities/:id returns university with programs, living cost estimates, visa requirements, and accommodations when found', async () => {
  const pool = mockPool(() => ({
    rows: [{
      university_id: '1', name: 'LMU Munich', country_code: 'DE', programs: [{ program_id: 'p1', title: 'M.Sc. CS' }],
      living_cost_estimates: [{ category: 'GENERAL', monthly_estimate_eur: 934, source_url: 'https://daad.de', source_checked_on: '2026-01-15' }],
      visa_requirements: [{ destination_country_code: 'DE', applicant_country_code: null, visa_type: 'STUDY_VISA', source_url: 'https://germany.info', source_checked_on: '2026-01-15' }],
      accommodations: [{ accommodation_type: 'UNIVERSITY_DORM', provider_name: 'Studierendenwerk', city: 'Munich', monthly_rent_eur: 430, source_url: 'https://studierendenwerk-muenchen-oberbayern.de', source_checked_on: '2026-01-15' }],
    }],
  }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/universities/1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.name, 'LMU Munich');
  assert.equal(data.programs.length, 1);
  assert.equal(data.living_cost_estimates[0].category, 'GENERAL');
  assert.equal(data.visa_requirements[0].visa_type, 'STUDY_VISA');
  assert.equal(data.accommodations[0].provider_name, 'Studierendenwerk');
  server.close();
});

test('GET /api/v1/programs/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/programs/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/programs/:id returns admission requirements, scholarships, and fees when found', async () => {
  const pool = mockPool(() => ({
    rows: [{
      program_id: 'p1', title: 'M.Sc. CS', university_name: 'LMU Munich', country_code: 'DE',
      admission_requirements: [{ minimum_cgpa_percentage: 70, source_url: 'https://lmu.de', source_checked_on: '2026-01-15' }],
      scholarships: [{ name: 'LMU Merit Scholarship', coverage_type: 'PARTIAL_TUITION', source_url: 'https://lmu.de', source_checked_on: '2026-01-15' }],
      fees: [{ fee_type: 'APPLICATION_FEE', student_category: 'INTERNATIONAL', amount_eur: 75, source_url: 'https://lmu.de', source_checked_on: '2026-01-15' }],
    }],
  }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/programs/p1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.admission_requirements[0].minimum_cgpa_percentage, 70);
  assert.equal(data.scholarships[0].name, 'LMU Merit Scholarship');
  assert.equal(data.fees[0].fee_type, 'APPLICATION_FEE');
  server.close();
});

test('GET /api/v1/scholarships filters by search and country', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /ILIKE/);
    assert.match(text, /country_code = \$2/);
    assert.deepEqual(params, ['%DAAD%', 'DE']);
    return { rows: [{ scholarship_id: '1', name: 'DAAD Study Scholarship', provider: 'DAAD', country_code: 'DE' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/scholarships?search=DAAD&country=de`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].name, 'DAAD Study Scholarship');
  server.close();
});

test('GET /api/v1/scholarships/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/scholarships/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/scholarships/:id returns the record when found', async () => {
  const pool = mockPool(() => ({ rows: [{ scholarship_id: '1', name: 'DAAD Study Scholarship' }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/scholarships/1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.name, 'DAAD Study Scholarship');
  server.close();
});

test('GET /api/v1/support-resources filters by category and country', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /category = \$1/);
    assert.match(text, /country_code = \$2 OR country_code IS NULL/);
    assert.deepEqual(params, ['TEST_FEE_WAIVER', 'US']);
    return { rows: [{ resource_id: '1', name: 'Duolingo English Test Access Program', category: 'TEST_FEE_WAIVER' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/support-resources?category=test_fee_waiver&country=us`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].name, 'Duolingo English Test Access Program');
  server.close();
});

test('GET /api/v1/support-resources/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/support-resources/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/support-resources/:id returns the record when found', async () => {
  const pool = mockPool(() => ({ rows: [{ resource_id: '1', name: 'EducationUSA Advising Centers' }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/support-resources/1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.name, 'EducationUSA Advising Centers');
  server.close();
});

test('GET /api/v1/living-costs filters by country, city, and universityId', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /country_code = \$1/);
    assert.match(text, /city ILIKE \$2/);
    assert.match(text, /university_id = \$3/);
    assert.deepEqual(params, ['DE', '%Munich%', 'u1']);
    return { rows: [{ estimate_id: '1', country_code: 'DE', city: 'Munich', category: 'GENERAL', monthly_estimate_eur: 934 }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/living-costs?country=de&city=Munich&universityId=u1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].category, 'GENERAL');
  server.close();
});

test('GET /api/v1/visa-requirements filters by destinationCountry and applicantCountry', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /destination_country_code = \$1/);
    assert.match(text, /applicant_country_code = \$2 OR applicant_country_code IS NULL/);
    assert.deepEqual(params, ['DE', 'IN']);
    return { rows: [{ visa_requirement_id: '1', destination_country_code: 'DE', applicant_country_code: null, visa_type: 'STUDY_VISA' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/visa-requirements?destinationCountry=de&applicantCountry=in`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].visa_type, 'STUDY_VISA');
  server.close();
});

test('GET /api/v1/visa-requirements/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/visa-requirements/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/visa-requirements/:id returns the record when found', async () => {
  const pool = mockPool(() => ({ rows: [{ visa_requirement_id: '1', destination_country_code: 'DE', visa_type: 'STUDY_VISA' }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/visa-requirements/1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.visa_type, 'STUDY_VISA');
  server.close();
});

test('GET /api/v1/accommodations filters by city, universityId, type, and maxRent', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /city ILIKE \$1/);
    assert.match(text, /university_id = \$2/);
    assert.match(text, /accommodation_type = \$3/);
    assert.match(text, /monthly_rent_eur <= \$4/);
    assert.deepEqual(params, ['%Munich%', 'u1', 'UNIVERSITY_DORM', 700]);
    return { rows: [{ accommodation_id: '1', provider_name: 'Studierendenwerk', city: 'Munich', monthly_rent_eur: 430 }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/accommodations?city=Munich&universityId=u1&type=university_dorm&maxRent=700`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].provider_name, 'Studierendenwerk');
  server.close();
});

test('GET /api/v1/accommodations/:id returns 404 when missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/accommodations/does-not-exist`);
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/accommodations/:id returns the record when found', async () => {
  const pool = mockPool(() => ({ rows: [{ accommodation_id: '1', provider_name: 'Studierendenwerk', monthly_rent_eur: 430 }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/accommodations/1`);
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.provider_name, 'Studierendenwerk');
  server.close();
});

test('GET /api/v1/me/profile returns the stored profile', async () => {
  const pool = mockPool(() => ({ rows: [{ user_id: 'u1', full_name: 'Jane Student', email: 'jane@example.com', passport_country: 'IN', cgpa_percentage: 78, liquid_funds_eur: 12000 }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/profile`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.passport_country, 'IN');
  server.close();
});

test('GET /api/v1/me/profile returns 404 when the account is missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'missing-user' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/profile`, { headers: { Authorization: `Bearer ${token}` } });
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/universities/:id passes the nationality filter through to the query', async () => {
  const pool = mockPool((text, params) => {
    if (/INSERT INTO demand_events/.test(text)) return {};
    assert.match(text, /applicant_country_code = \$2/);
    assert.deepEqual(params, ['1', 'IN']);
    return { rows: [{ university_id: '1', name: 'LMU Munich', country_code: 'DE', programs: [], living_cost_estimates: [], visa_requirements: [], accommodations: [] }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/universities/1?nationality=in`);
  assert.equal(response.status, 200);
  server.close();
});

test('GET /api/v1/matches ranks programmes against the student profile', async () => {
  const pool = mockPool((text) => {
    if (/FROM users WHERE user_id/.test(text)) {
      return { rows: [{ cgpa_percentage: 85, liquid_funds_eur: 15000 }] };
    }
    return {
      rows: [
        {
          program_id: 'p1', title: 'M.Sc. CS', degree_level: 'MASTER', field_of_study: 'Computer Science',
          university_name: 'LMU Munich', country_code: 'DE',
          minimum_cgpa_percentage: 70, official_funds_requirement_eur: 11208,
          source_url: 'https://example.edu/requirements', source_checked_on: '2026-01-01',
          estimated_annual_tuition_eur: 0, one_time_fees_eur: 0, total_potential_scholarship_value_eur: 0,
        },
        {
          program_id: 'p2', title: 'M.Sc. Data Science', degree_level: 'MASTER', field_of_study: 'Data Science',
          university_name: 'Some University', country_code: 'DE',
          minimum_cgpa_percentage: 95, official_funds_requirement_eur: 11208,
          source_url: 'https://example.edu/requirements2', source_checked_on: '2026-01-01',
          estimated_annual_tuition_eur: 0, one_time_fees_eur: 0, total_potential_scholarship_value_eur: 0,
        },
      ],
    };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/matches`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.matches.length, 2);
  assert.equal(data.matches[0].program_id, 'p1');
  assert.equal(data.matches[0].academic.status, 'MEETS_STATED_MINIMUM');
  assert.equal(data.matches[1].academic.status, 'BELOW_STATED_MINIMUM');
  server.close();
});

test('GET /api/v1/matches returns 404 when the student profile is missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/matches`, { headers: { Authorization: `Bearer ${token}` } });
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/matches requires authentication', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/matches`);
  assert.equal(response.status, 401);
  server.close();
});

test('computeCostView returns null when no fee rows exist for the programme', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const cost = await computeCostView(pool, 'p1');
  assert.equal(cost, null);
});

test('computeCostView sums tuition/fees/scholarships into a net-cost estimate', async () => {
  let call = 0;
  const pool = {
    query: async () => {
      call += 1;
      if (call === 1) return { rows: [{ fee_type: 'TUITION_PER_YEAR', amount_eur: '20396.00' }, { fee_type: 'APPLICATION_FEE', amount_eur: '100.00' }] };
      return { rows: [{ amount_eur: '3000.00' }, { amount_eur: '12000.00' }] };
    },
  };
  const cost = await computeCostView(pool, 'p1');
  assert.equal(cost.estimated_annual_tuition_eur, 20396);
  assert.equal(cost.one_time_fees_eur, 100);
  assert.equal(cost.total_potential_scholarship_value_eur, 15000);
  assert.equal(cost.estimated_net_annual_cost_if_awarded_eur, 5396);
  assert.equal(typeof cost.caveat, 'string');
});

test('PUT /api/v1/me/profile updates an existing account (not an upsert)', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /UPDATE users SET/);
    assert.deepEqual(params, ['u1', 'Jane Student', 'jane@example.com', 'IN', 78, 12000]);
    return { rows: [{ user_id: 'u1', full_name: 'Jane Student', email: 'jane@example.com', passport_country: 'IN', cgpa_percentage: 78, liquid_funds_eur: 12000 }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/profile`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ fullName: 'Jane Student', email: 'jane@example.com', passportCountry: 'IN', cgpaPercentage: 78, liquidFundsEur: 12000 }),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.email, 'jane@example.com');
  server.close();
});

test('PUT /api/v1/me/profile returns 404 when the account no longer exists', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'missing-user' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/profile`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ fullName: 'Jane Student', email: 'jane@example.com' }),
  });
  assert.equal(response.status, 404);
  server.close();
});

test('PATCH /api/v1/applications/:id/status updates the status', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /submission_status = \$1::varchar\(30\)/);
    assert.deepEqual(params, ['SUBMITTED', 'app1', 'u1']);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/status`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ status: 'SUBMITTED' }),
  });
  assert.equal(response.status, 204);
  server.close();
});

test('PATCH /api/v1/applications/:id/status rejects an invalid status', async () => {
  const pool = mockPool(() => ({ rowCount: 0 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/status`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ status: 'NOT_A_REAL_STATUS' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('PATCH /api/v1/applications/:id/deadline updates the deadline', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /deadline_at = \$1::date/);
    assert.deepEqual(params, ['2026-12-01', 'app1', 'u1']);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/deadline`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ deadlineAt: '2026-12-01' }),
  });
  assert.equal(response.status, 204);
  server.close();
});

test('PATCH /api/v1/applications/:id/deadline returns 404 when the application is missing', async () => {
  const pool = mockPool(() => ({ rowCount: 0 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/deadline`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ deadlineAt: '2026-12-01' }),
  });
  assert.equal(response.status, 404);
  server.close();
});

test('PATCH /api/v1/applications/:id/deadline rejects an invalid date', async () => {
  const pool = mockPool(() => ({ rowCount: 1 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/deadline`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ deadlineAt: 'not-a-date' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/applications/:id/documents adds a checklist item to an existing application', async () => {
  const pool = mockPool((text) => {
    if (/SELECT 1 FROM applications_tracker/.test(text)) return { rows: [{}] };
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/documents`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ type: 'TRANSCRIPT', sourceUrl: 'https://example.edu/requirements' }),
  });
  assert.equal(response.status, 201);
  server.close();
});

test('POST /api/v1/applications/:id/documents returns 404 when the application is not owned by the caller', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/documents`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ type: 'TRANSCRIPT' }),
  });
  assert.equal(response.status, 404);
  server.close();
});

test('PATCH /api/v1/applications/:id/documents/:documentId updates status', async () => {
  const pool = mockPool((text, params) => {
    assert.deepEqual(params, ['READY', false, null, null, 'doc1', 'app1', 'u1']);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/documents/doc1`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ status: 'READY' }),
  });
  assert.equal(response.status, 204);
  server.close();
});

test('PATCH /api/v1/applications/:id/documents/:documentId rejects an invalid status', async () => {
  const pool = mockPool(() => ({ rowCount: 1 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications/app1/documents/doc1`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ status: 'NOT_A_STATUS' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('GET /api/v1/me/documents lists the caller\'s tracked documents', async () => {
  const pool = mockPool(() => ({ rows: [{ student_document_id: 'd1', document_type: 'IELTS', expires_at: '2028-01-01' }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/documents`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].document_type, 'IELTS');
  server.close();
});

test('POST /api/v1/me/documents creates a personal document record', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/documents`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ documentType: 'IELTS', obtainedAt: '2026-01-01', expiresAt: '2028-01-01' }),
  });
  assert.equal(response.status, 201);
  server.close();
});

test('POST /api/v1/me/documents rejects a missing documentType', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/documents`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({}),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('DELETE /api/v1/me/documents/:id removes a personal document record', async () => {
  const pool = mockPool(() => ({ rowCount: 1 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/documents/d1`, {
    method: 'DELETE', headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 204);
  server.close();
});

test('DELETE /api/v1/me/documents/:id returns 404 when not found', async () => {
  const pool = mockPool(() => ({ rowCount: 0 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/documents/d1`, {
    method: 'DELETE', headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 404);
  server.close();
});

test('POST /api/v1/auth/register creates an account and returns a token', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/register`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fullName: 'Jane Student', email: 'jane@example.com', password: 'password123' }),
  });
  const data = await response.json();
  assert.equal(response.status, 201);
  assert.equal(typeof data.token, 'string');
  assert.equal(data.user.email, 'jane@example.com');
  assert.equal(data.user.password_hash, undefined);
  server.close();
});

test('POST /api/v1/auth/register rejects a short password', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/register`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fullName: 'Jane Student', email: 'jane@example.com', password: 'short' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/auth/register returns 409 when the email already exists', async () => {
  const pool = mockPool(() => { const error = new Error('duplicate'); error.code = '23505'; throw error; });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/register`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fullName: 'Jane Student', email: 'jane@example.com', password: 'password123' }),
  });
  assert.equal(response.status, 409);
  server.close();
});

test('POST /api/v1/auth/login returns a token for the correct password', async () => {
  const storedHash = hashPassword('password123');
  const pool = mockPool(() => ({ rows: [{ user_id: 'u1', full_name: 'Jane Student', password_hash: storedHash }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'jane@example.com', password: 'password123' }),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(typeof data.token, 'string');
  server.close();
});

test('POST /api/v1/auth/login returns 401 for the wrong password', async () => {
  const storedHash = hashPassword('password123');
  const pool = mockPool(() => ({ rows: [{ user_id: 'u1', full_name: 'Jane Student', password_hash: storedHash }] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'jane@example.com', password: 'wrong-password' }),
  });
  assert.equal(response.status, 401);
  server.close();
});

test('POST /api/v1/auth/login returns 401 for an unknown email', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'unknown@example.com', password: 'password123' }),
  });
  assert.equal(response.status, 401);
  server.close();
});

test('POST /api/v1/auth/password-reset/request sends no email and gives a generic message for an unknown address', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const sent = [];
  const mailer = { sendMail: async (message) => { sent.push(message); } };
  const app = createApp({ pool, mailer });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/password-reset/request`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'unknown@example.com' }),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.match(data.message, /if an account with that email exists/i);
  assert.equal(sent.length, 0);
  server.close();
});

test('POST /api/v1/auth/password-reset/request emails a reset link for a known address', async () => {
  const originalUrl = process.env.PUBLIC_APP_URL;
  process.env.PUBLIC_APP_URL = 'https://students-ecosystem.example';
  try {
    const pool = mockPool((text) => {
      if (/FROM users WHERE email/.test(text)) return { rows: [{ user_id: 'u1', full_name: 'Jane Student' }] };
      return {};
    });
    const sent = [];
    const mailer = { sendMail: async (message) => { sent.push(message); } };
    const app = createApp({ pool, mailer });
    const server = app.listen(0);
    const { port } = server.address();
    const response = await fetch(`http://localhost:${port}/api/v1/auth/password-reset/request`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'jane@example.com' }),
    });
    assert.equal(response.status, 200);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'jane@example.com');
    assert.match(sent[0].text, /resetToken=/);
    server.close();
  } finally {
    if (originalUrl === undefined) delete process.env.PUBLIC_APP_URL;
    else process.env.PUBLIC_APP_URL = originalUrl;
  }
});

test('POST /api/v1/auth/password-reset/confirm rejects a short new password', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/password-reset/confirm`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: 'abc', newPassword: 'short' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/auth/password-reset/confirm rejects an invalid or expired token', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/password-reset/confirm`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: 'not-a-real-token', newPassword: 'newpassword123' }),
  });
  const data = await response.json();
  assert.equal(response.status, 400);
  assert.match(data.error, /invalid or has expired/i);
  server.close();
});

test('POST /api/v1/auth/password-reset/confirm updates the password for a valid token', async () => {
  const queries = [];
  const pool = mockPool((text, params) => {
    queries.push(text);
    if (/FROM password_reset_tokens WHERE token_hash/.test(text)) return { rows: [{ token_id: 't1', user_id: 'u1' }] };
    if (/UPDATE users SET password_hash/.test(text)) { assert.equal(params[1], 'u1'); return {}; }
    if (/UPDATE password_reset_tokens SET consumed_at/.test(text)) { assert.equal(params[0], 't1'); return {}; }
    return {};
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/auth/password-reset/confirm`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: 'a-real-looking-token', newPassword: 'newpassword123' }),
  });
  assert.equal(response.status, 200);
  assert.ok(queries.some((text) => /UPDATE users SET password_hash/.test(text)));
  assert.ok(queries.some((text) => /UPDATE password_reset_tokens SET consumed_at/.test(text)));
  server.close();
});

test('GET /api/v1/me/export returns 404 when the account is missing', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/export`, { headers: { Authorization: `Bearer ${token}` } });
  assert.equal(response.status, 404);
  server.close();
});

test('GET /api/v1/me/export bundles the account\'s own applications, documents, and referrals', async () => {
  const pool = mockPool((text) => {
    if (/FROM users WHERE user_id/.test(text)) return { rows: [{ user_id: 'u1', full_name: 'Jane Student', email: 'jane@example.com' }] };
    if (/FROM applications_tracker/.test(text)) return { rows: [{ application_id: 'a1', program_title: 'M.Sc. CS' }] };
    if (/FROM student_documents/.test(text)) return { rows: [{ student_document_id: 'd1', document_type: 'IELTS' }] };
    if (/FROM professor_lor_requests/.test(text)) return { rows: [] };
    if (/FROM partner_conversions/.test(text)) return { rows: [] };
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/export`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.profile.email, 'jane@example.com');
  assert.equal(data.applications[0].program_title, 'M.Sc. CS');
  assert.equal(data.personalDocuments[0].document_type, 'IELTS');
  server.close();
});

test('DELETE /api/v1/me requires the current password in the body', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me`, {
    method: 'DELETE', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify({}),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('DELETE /api/v1/me rejects an incorrect password and does not delete the account', async () => {
  const storedHash = hashPassword('correct-password');
  let deleteCalled = false;
  const pool = mockPool((text) => {
    if (/DELETE FROM users/.test(text)) { deleteCalled = true; return {}; }
    return { rows: [{ password_hash: storedHash }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me`, {
    method: 'DELETE', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ password: 'wrong-password' }),
  });
  assert.equal(response.status, 401);
  assert.equal(deleteCalled, false);
  server.close();
});

test('DELETE /api/v1/me deletes the account when the password is correct', async () => {
  const storedHash = hashPassword('correct-password');
  const pool = mockPool((text) => {
    if (/DELETE FROM users/.test(text)) return {};
    return { rows: [{ password_hash: storedHash }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me`, {
    method: 'DELETE', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ password: 'correct-password' }),
  });
  assert.equal(response.status, 204);
  server.close();
});

test('GET /api/v1/sponsored-content returns an empty list when unconfigured', async () => {
  const originalContent = process.env.SPONSORED_CONTENT_JSON;
  delete process.env.SPONSORED_CONTENT_JSON;
  try {
    const pool = mockPool(() => ({ rows: [] }));
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const response = await fetch(`http://localhost:${port}/api/v1/sponsored-content`);
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(data, []);
    server.close();
  } finally {
    if (originalContent === undefined) delete process.env.SPONSORED_CONTENT_JSON;
    else process.env.SPONSORED_CONTENT_JSON = originalContent;
  }
});

test('GET /api/v1/sponsored-content filters by country and always attaches a disclosure', async () => {
  const originalContent = process.env.SPONSORED_CONTENT_JSON;
  process.env.SPONSORED_CONTENT_JSON = JSON.stringify([
    { id: 'sp1', sponsorName: 'Acme Test Prep', headline: 'Prep for your language test', linkUrl: 'https://example.com/acme', countryCode: 'DE' },
    { id: 'sp2', sponsorName: 'Global Insurance Co', headline: 'Student health cover', linkUrl: 'https://example.com/global' },
  ]);
  try {
    const pool = mockPool(() => ({ rows: [] }));
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const deResponse = await fetch(`http://localhost:${port}/api/v1/sponsored-content?countryCode=de`);
    const deData = await deResponse.json();
    assert.equal(deData.length, 2);
    assert.ok(deData.every((item) => item.disclosure.includes('Sponsored')));
    const nlResponse = await fetch(`http://localhost:${port}/api/v1/sponsored-content?countryCode=nl`);
    const nlData = await nlResponse.json();
    assert.equal(nlData.length, 1);
    assert.equal(nlData[0].id, 'sp2');
    server.close();
  } finally {
    if (originalContent === undefined) delete process.env.SPONSORED_CONTENT_JSON;
    else process.env.SPONSORED_CONTENT_JSON = originalContent;
  }
});

test('GET /api/v1/universities/:id records an anonymous demand event on a successful lookup', async () => {
  let insertParams = null;
  const pool = mockPool((text, params) => {
    if (/INSERT INTO demand_events/.test(text)) {
      assert.match(text, /'UNIVERSITY_VIEW'/);
      insertParams = params;
      return {};
    }
    return { rows: [{ university_id: 'u1', name: 'LMU Munich', country_code: 'DE', programs: [], living_cost_estimates: [], visa_requirements: [], accommodations: [] }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/universities/u1`);
  assert.equal(response.status, 200);
  assert.deepEqual(insertParams.slice(1), ['u1', 'DE']);
  server.close();
});

test('GET /api/v1/analytics/demand rejects a missing or unknown API key', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const noKeyResponse = await fetch(`http://localhost:${port}/api/v1/analytics/demand`);
  assert.equal(noKeyResponse.status, 401);
  const wrongKeyResponse = await fetch(`http://localhost:${port}/api/v1/analytics/demand`, { headers: { 'x-institute-api-key': 'not-a-real-key' } });
  assert.equal(wrongKeyResponse.status, 401);
  server.close();
});

test('GET /api/v1/analytics/demand scopes results to the key\'s own university only', async () => {
  const originalKeys = process.env.INSTITUTE_ANALYTICS_KEYS_JSON;
  process.env.INSTITUTE_ANALYTICS_KEYS_JSON = JSON.stringify([{ apiKey: 'test-key-1', universityId: 'u1' }]);
  try {
    const pool = mockPool((text, params) => {
      assert.match(text, /WHERE university_id = \$1/);
      assert.deepEqual(params, ['u1']);
      return { rows: [{ event_type: 'UNIVERSITY_VIEW', day: '2026-08-20', view_count: 3 }] };
    });
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const response = await fetch(`http://localhost:${port}/api/v1/analytics/demand`, { headers: { 'x-institute-api-key': 'test-key-1' } });
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.universityId, 'u1');
    assert.equal(data.events[0].view_count, 3);
    server.close();
  } finally {
    if (originalKeys === undefined) delete process.env.INSTITUTE_ANALYTICS_KEYS_JSON;
    else process.env.INSTITUTE_ANALYTICS_KEYS_JSON = originalKeys;
  }
});

test('auth endpoints are rate-limited per window', async () => {
  const originalMax = process.env.AUTH_RATE_LIMIT_MAX;
  process.env.AUTH_RATE_LIMIT_MAX = '2';
  try {
    const pool = mockPool(() => ({ rows: [] }));
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const attempt = () => fetch(`http://localhost:${port}/api/v1/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'x@example.com', password: 'wrong-password' }),
    });
    assert.equal((await attempt()).status, 401);
    assert.equal((await attempt()).status, 401);
    const third = await attempt();
    assert.equal(third.status, 429);
    const body = await third.json();
    assert.match(body.error, /too many attempts/i);
    server.close();
  } finally {
    if (originalMax === undefined) delete process.env.AUTH_RATE_LIMIT_MAX;
    else process.env.AUTH_RATE_LIMIT_MAX = originalMax;
  }
});
