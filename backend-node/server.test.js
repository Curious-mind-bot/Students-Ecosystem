process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp, hashPassword, computeCostView, createMailer } = require('./server');

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

test('GET /api/v1/me/readiness/documents requires authentication', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/me/readiness/documents?countryCode=DE`);
  assert.equal(response.status, 401);
  server.close();
});

test('GET /api/v1/me/readiness/documents requires a countryCode', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/readiness/documents`, { headers: { Authorization: `Bearer ${token}` } });
  assert.equal(response.status, 400);
  server.close();
});

test('GET /api/v1/me/readiness/documents reports REQUIREMENT_NOT_SOURCED when no figure is on file', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/readiness/documents?countryCode=DE`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.status, 'REQUIREMENT_NOT_SOURCED');
  server.close();
});

test('GET /api/v1/me/readiness/documents reports PASSPORT_NOT_TRACKED when the student has no passport on file', async () => {
  const pool = mockPool((text) => {
    if (/FROM visa_requirements/.test(text)) {
      return { rows: [{ minimum_passport_validity_months: 6, source_url: 'https://example.gov/visa', source_checked_on: '2026-08-22' }] };
    }
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/readiness/documents?countryCode=DE`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.status, 'PASSPORT_NOT_TRACKED');
  assert.equal(data.required_validity_months, 6);
  server.close();
});

test('GET /api/v1/me/readiness/documents flags a passport that falls below the required validity', async () => {
  const pool = mockPool((text) => {
    if (/FROM visa_requirements/.test(text)) {
      return { rows: [{ minimum_passport_validity_months: 12, source_url: 'https://example.gov/visa', source_checked_on: '2026-08-22' }] };
    }
    return { rows: [{ document_type: 'PASSPORT', expires_at: '2027-01-01' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/readiness/documents?countryCode=DE`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.status, 'BELOW_REQUIREMENT');
  assert.match(data.disclaimer, /not a visa or immigration decision/i);
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

test('computeCostView includes a whole-programme TUITION_TOTAL fee in the cost estimate', async () => {
  let call = 0;
  const pool = {
    query: async () => {
      call += 1;
      if (call === 1) return { rows: [{ fee_type: 'TUITION_TOTAL', amount_eur: '6237.00' }] };
      return { rows: [] };
    },
  };
  const cost = await computeCostView(pool, 'p1');
  assert.equal(cost.estimated_annual_tuition_eur, 6237);
  assert.equal(cost.estimated_net_annual_cost_if_awarded_eur, 6237);
});

test('computeCostView includes a TUITION_PER_SEMESTER fee in the cost estimate', async () => {
  let call = 0;
  const pool = {
    query: async () => {
      call += 1;
      if (call === 1) return { rows: [{ fee_type: 'TUITION_PER_SEMESTER', amount_eur: '12950.85' }] };
      return { rows: [] };
    },
  };
  const cost = await computeCostView(pool, 'p1');
  assert.equal(cost.estimated_annual_tuition_eur, 12950.85);
  assert.equal(cost.estimated_net_annual_cost_if_awarded_eur, 12950.85);
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
  const pool = mockPool(() => ({ rows: [{ user_id: 42 }] }));
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

test('GET /api/v1/sponsored-content filters by placement, defaulting untagged items to SEARCH_RESULTS', async () => {
  const originalContent = process.env.SPONSORED_CONTENT_JSON;
  process.env.SPONSORED_CONTENT_JSON = JSON.stringify([
    { id: 'sp1', sponsorName: 'Acme Test Prep', headline: 'Prep for your language test', linkUrl: 'https://example.com/acme' },
    { id: 'sp2', sponsorName: 'City Hostels Co', headline: 'Book your first month free', linkUrl: 'https://example.com/hostels', placement: 'accommodation_list' },
  ]);
  try {
    const pool = mockPool(() => ({ rows: [] }));
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const defaultResponse = await fetch(`http://localhost:${port}/api/v1/sponsored-content`);
    const defaultData = await defaultResponse.json();
    assert.equal(defaultData.length, 2);
    assert.equal(defaultData.find((item) => item.id === 'sp1').placement, 'SEARCH_RESULTS');
    assert.equal(defaultData.find((item) => item.id === 'sp2').placement, 'ACCOMMODATION_LIST');
    const accommodationResponse = await fetch(`http://localhost:${port}/api/v1/sponsored-content?placement=accommodation_list`);
    const accommodationData = await accommodationResponse.json();
    assert.equal(accommodationData.length, 1);
    assert.equal(accommodationData[0].id, 'sp2');
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

function withAdminApiKey(fn) {
  return async () => {
    const originalKey = process.env.ADMIN_API_KEY;
    process.env.ADMIN_API_KEY = 'test-admin-key';
    try {
      await fn();
    } finally {
      if (originalKey === undefined) delete process.env.ADMIN_API_KEY;
      else process.env.ADMIN_API_KEY = originalKey;
    }
  };
}

test('GET /api/v1/admin/resources rejects a missing or wrong admin key', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const noKey = await fetch(`http://localhost:${port}/api/v1/admin/resources`);
  assert.equal(noKey.status, 401);
  const wrongKey = await fetch(`http://localhost:${port}/api/v1/admin/resources`, { headers: { 'x-admin-api-key': 'nope' } });
  assert.equal(wrongKey.status, 401);
  server.close();
}));

test('GET /api/v1/admin/resources lists every manageable resource', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/resources`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.ok(data.includes('universities'));
  assert.ok(data.includes('support_resources'));
  server.close();
}));

test('GET /api/v1/admin/:resource/_schema describes a resource\'s columns', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities/_schema`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.idColumn, 'university_id');
  assert.ok(data.columns.includes('country_code'));
  assert.ok(data.requiredColumns.includes('country_code'));
  server.close();
}));

test('GET /api/v1/admin/:resource returns 404 for an unknown resource', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/not_a_table`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  assert.equal(response.status, 404);
  server.close();
}));

test('GET /api/v1/admin/:resource lists rows for a known resource', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    assert.match(text, /SELECT \* FROM universities ORDER BY university_id/);
    return { rows: [{ university_id: '1', name: 'LMU Munich' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].name, 'LMU Munich');
  server.close();
}));

test('POST /api/v1/admin/:resource rejects missing required fields', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' },
    body: JSON.stringify({ name: 'New University' }),
  });
  const data = await response.json();
  assert.equal(response.status, 400);
  assert.match(data.error, /country_code/);
  server.close();
}));

test('POST /api/v1/admin/:resource creates a row with a generated id', withAdminApiKey(async () => {
  let insertText = null;
  let insertParams = null;
  const pool = mockPool((text, params) => {
    insertText = text;
    insertParams = params;
    return {};
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' },
    body: JSON.stringify({ name: 'New University', country_code: 'FR' }),
  });
  const data = await response.json();
  assert.equal(response.status, 201);
  assert.ok(data.university_id);
  assert.match(insertText, /INSERT INTO universities \(university_id, name, country_code\)/);
  assert.equal(insertParams[1], 'New University');
  assert.equal(insertParams[2], 'FR');
  server.close();
}));

test('POST /api/v1/admin/:resource translates a constraint violation into a 400', withAdminApiKey(async () => {
  const pool = mockPool(() => {
    const error = new Error('violates check constraint "academic_programs_degree_level_check"');
    error.code = '23514';
    error.constraint = 'academic_programs_degree_level_check';
    error.detail = 'Failing row contains (..., NOT_A_LEVEL, ...).';
    throw error;
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/academic_programs`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' },
    body: JSON.stringify({ university_id: 'u1', title: 'Weird Degree', degree_level: 'NOT_A_LEVEL' }),
  });
  const data = await response.json();
  assert.equal(response.status, 400);
  assert.match(data.error, /constraint/);
  server.close();
}));

test('PATCH /api/v1/admin/:resource/:id updates only the provided fields', withAdminApiKey(async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /UPDATE universities SET city = \$2, updated_at = now\(\) WHERE university_id = \$1/);
    assert.deepEqual(params, ['u1', 'Berlin']);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities/u1`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' },
    body: JSON.stringify({ city: 'Berlin' }),
  });
  assert.equal(response.status, 204);
  server.close();
}));

test('PATCH /api/v1/admin/:resource/:id returns 404 when not found', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rowCount: 0 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities/does-not-exist`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' },
    body: JSON.stringify({ city: 'Berlin' }),
  });
  assert.equal(response.status, 404);
  server.close();
}));

test('DELETE /api/v1/admin/:resource/:id removes a row', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    assert.match(text, /DELETE FROM universities WHERE university_id = \$1/);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/universities/u1`, {
    method: 'DELETE', headers: { 'x-admin-api-key': 'test-admin-key' },
  });
  assert.equal(response.status, 204);
  server.close();
}));

test('POST /api/v1/submissions requires authentication', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/submissions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetResource: 'universities', proposedData: { name: 'X' }, sourceUrl: 'https://example.edu' }),
  });
  assert.equal(response.status, 401);
  server.close();
});

test('POST /api/v1/submissions rejects an unknown target resource', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/submissions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ targetResource: 'not_a_table', proposedData: { x: 1 }, sourceUrl: 'https://example.edu' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/submissions requires a valid http(s) sourceUrl', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/submissions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ targetResource: 'universities', proposedData: { name: 'X' }, sourceUrl: 'not-a-url' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/submissions queues a PENDING submission', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /INSERT INTO content_submissions/);
    assert.equal(params[2], 'universities');
    assert.equal(params[5], 'https://example.edu/new-campus');
    return {};
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/submissions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ targetResource: 'universities', proposedData: { name: 'New Campus', country_code: 'FR' }, sourceUrl: 'https://example.edu/new-campus' }),
  });
  const data = await response.json();
  assert.equal(response.status, 201);
  assert.equal(data.status, 'PENDING');
  server.close();
});

test('GET /api/v1/me/submissions requires authentication', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/me/submissions`);
  assert.equal(response.status, 401);
  server.close();
});

test('GET /api/v1/me/submissions returns only the caller\'s own submissions', async () => {
  const pool = mockPool((text, params) => {
    assert.match(text, /WHERE submitted_by_user_id = \$1/);
    assert.deepEqual(params, ['u1']);
    return { rows: [{ submission_id: 's1', status: 'PENDING' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/me/submissions`, { headers: { Authorization: `Bearer ${token}` } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].submission_id, 's1');
  server.close();
});

test('GET /api/v1/admin/submissions rejects a missing admin key', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions`);
  assert.equal(response.status, 401);
  server.close();
});

test('GET /api/v1/admin/submissions/:id returns 404 when missing', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    assert.match(text, /FROM content_submissions WHERE submission_id/);
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/does-not-exist`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  const data = await response.json();
  assert.equal(response.status, 404);
  assert.equal(data.error, 'Not found.');
  server.close();
}));

test('GET /api/v1/admin/submissions is not shadowed by the generic /api/v1/admin/:resource route', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    assert.match(text, /FROM content_submissions WHERE/);
    return { rows: [{ submission_id: 's1', status: 'PENDING' }] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions`, { headers: { 'x-admin-api-key': 'test-admin-key' } });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data[0].submission_id, 's1');
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/approve creates a new row for a CREATE-type submission', withAdminApiKey(async () => {
  const pool = mockPool((text, params) => {
    if (/FROM content_submissions WHERE submission_id/.test(text)) {
      return {
        rows: [{
          submission_id: 'sub1', target_resource: 'universities', target_record_id: null,
          proposed_data: { name: 'New Campus', country_code: 'FR' }, source_url: 'https://example.edu/new-campus', status: 'PENDING',
        }],
      };
    }
    if (/INSERT INTO universities/.test(text)) {
      assert.deepEqual(params.slice(1), ['New Campus', 'FR']);
      return {};
    }
    if (/UPDATE content_submissions SET status = 'APPROVED'/.test(text)) return {};
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub1/approve`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({}),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.status, 'APPROVED');
  assert.ok(data.result.university_id);
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/approve updates the existing row for an EDIT-type submission', withAdminApiKey(async () => {
  const pool = mockPool((text, params) => {
    if (/FROM content_submissions WHERE submission_id/.test(text)) {
      return {
        rows: [{
          submission_id: 'sub2', target_resource: 'universities', target_record_id: 'u1',
          proposed_data: { city: 'Lyon' }, source_url: 'https://example.edu/update', status: 'PENDING',
        }],
      };
    }
    if (/UPDATE universities SET/.test(text)) {
      assert.deepEqual(params, ['u1', 'Lyon']);
      return { rowCount: 1 };
    }
    if (/UPDATE content_submissions SET status = 'APPROVED'/.test(text)) return {};
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub2/approve`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({}),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.result.university_id, 'u1');
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/approve rejects a submission that was already reviewed', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    if (/FROM content_submissions WHERE submission_id/.test(text)) {
      return { rows: [{ submission_id: 'sub3', status: 'APPROVED' }] };
    }
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub3/approve`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({}),
  });
  assert.equal(response.status, 400);
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/approve surfaces a missing-required-field error instead of silently succeeding', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    if (/FROM content_submissions WHERE submission_id/.test(text)) {
      return {
        rows: [{
          submission_id: 'sub4', target_resource: 'universities', target_record_id: null,
          proposed_data: { name: 'Incomplete Campus' }, source_url: 'https://example.edu/incomplete', status: 'PENDING',
        }],
      };
    }
    return { rows: [] };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub4/approve`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({}),
  });
  const data = await response.json();
  assert.equal(response.status, 400);
  assert.match(data.error, /country_code/);
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/reject marks the submission rejected', withAdminApiKey(async () => {
  const pool = mockPool((text) => {
    assert.match(text, /UPDATE content_submissions SET status = 'REJECTED'/);
    return { rowCount: 1 };
  });
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub1/reject`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({ reviewNotes: 'Not verifiable.' }),
  });
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.status, 'REJECTED');
  server.close();
}));

test('POST /api/v1/admin/submissions/:id/reject returns 404 when not found or already reviewed', withAdminApiKey(async () => {
  const pool = mockPool(() => ({ rowCount: 0 }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/api/v1/admin/submissions/sub1/reject`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-admin-api-key': 'test-admin-key' }, body: JSON.stringify({}),
  });
  assert.equal(response.status, 404);
  server.close();
}));

// These three creation endpoints (applications_tracker, professor_lor_requests,
// partner_conversions) all insert into tables with DB-generated integer ids via
// RETURNING rather than a client-generated crypto.randomUUID() (see the fix in
// commit 2a48e4e). None of them had test coverage before, which is exactly why
// that bug went unnoticed by this suite -- these tests specifically assert the
// response echoes back the DB-generated id from the mocked RETURNING row.

test('POST /api/v1/applications creates an application and its document checklist using DB-generated ids', async () => {
  const insertedDocuments = [];
  const pool = {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      query: async (text, params) => {
        if (text === 'BEGIN' || text === 'COMMIT' || text === 'ROLLBACK') return {};
        if (/INSERT INTO applications_tracker/.test(text)) {
          assert.deepEqual(params, ['u1', 'DE', 'LMU Munich', 'M.Sc. CS', null, null]);
          return { rows: [{ application_id: 42 }] };
        }
        if (/INSERT INTO application_documents/.test(text)) {
          insertedDocuments.push(params);
          return {};
        }
        throw new Error(`Unexpected query: ${text}`);
      },
      release() {},
    }),
  };
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      countryCode: 'de', universityName: 'LMU Munich', programTitle: 'M.Sc. CS',
      documents: [{ type: 'transcript', sourceUrl: 'https://example.edu' }],
    }),
  });
  const data = await response.json();
  assert.equal(response.status, 201);
  assert.equal(data.applicationId, 42);
  assert.equal(insertedDocuments.length, 1);
  assert.equal(insertedDocuments[0][1], 42);
  assert.equal(insertedDocuments[0][2], 'transcript');
  assert.equal(insertedDocuments[0][3], 'https://example.edu');
  assert.equal(insertedDocuments[0][4], 'NOT_STARTED');
  server.close();
});

test('POST /api/v1/applications requires countryCode, universityName, and programTitle', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ countryCode: 'DE' }),
  });
  assert.equal(response.status, 400);
  server.close();
});

test('POST /api/v1/applications rolls back and returns 400 for an invalid document checklist item', async () => {
  let rolledBack = false;
  const pool = {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      query: async (text) => {
        if (text === 'BEGIN') return {};
        if (text === 'ROLLBACK') { rolledBack = true; return {}; }
        if (/INSERT INTO applications_tracker/.test(text)) return { rows: [{ application_id: 42 }] };
        throw new Error(`Unexpected query: ${text}`);
      },
      release() {},
    }),
  };
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
  const response = await fetch(`http://localhost:${port}/api/v1/applications`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      countryCode: 'DE', universityName: 'LMU Munich', programTitle: 'M.Sc. CS',
      documents: [{ type: '' }],
    }),
  });
  assert.equal(response.status, 400);
  assert.ok(rolledBack);
  server.close();
});

test('POST /api/v1/lor/requests creates a request using the DB-generated id and emails the professor', async () => {
  const pool = mockPool((text, params) => {
    if (/INSERT INTO professor_lor_requests/.test(text)) {
      assert.equal(params[0], 'u1');
      assert.equal(params[1], 'Prof Smith');
      assert.equal(params[2], 'prof@example.com');
      assert.equal(params[3], 'MIT');
      return { rows: [{ request_id: 7 }] };
    }
    return { rows: [] };
  });
  const sent = [];
  const mailer = { sendMail: async (message) => { sent.push(message); } };
  const originalUrl = process.env.PUBLIC_APP_URL;
  process.env.PUBLIC_APP_URL = 'https://students-ecosystem.example';
  try {
    const app = createApp({ pool, mailer });
    const server = app.listen(0);
    const { port } = server.address();
    const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
    const response = await fetch(`http://localhost:${port}/api/v1/lor/requests`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ professorName: 'Prof Smith', professorEmail: 'prof@example.com', universityAffiliation: 'MIT' }),
    });
    const data = await response.json();
    assert.equal(response.status, 201);
    assert.equal(data.requestId, 7);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'prof@example.com');
    assert.match(sent[0].text, /\/referee\/reference\//);
    server.close();
  } finally {
    if (originalUrl === undefined) delete process.env.PUBLIC_APP_URL;
    else process.env.PUBLIC_APP_URL = originalUrl;
  }
});

test('POST /api/v1/lor/requests deletes the request and returns 503 when the email fails to send', async () => {
  let deletedRequestId;
  const pool = mockPool((text, params) => {
    if (/INSERT INTO professor_lor_requests/.test(text)) return { rows: [{ request_id: 7 }] };
    if (/DELETE FROM professor_lor_requests/.test(text)) { deletedRequestId = params[0]; return {}; }
    return { rows: [] };
  });
  const mailer = { sendMail: async () => { throw new Error('SMTP down'); } };
  const originalUrl = process.env.PUBLIC_APP_URL;
  process.env.PUBLIC_APP_URL = 'https://students-ecosystem.example';
  try {
    const app = createApp({ pool, mailer });
    const server = app.listen(0);
    const { port } = server.address();
    const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
    const response = await fetch(`http://localhost:${port}/api/v1/lor/requests`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ professorName: 'Prof Smith', professorEmail: 'prof@example.com', universityAffiliation: 'MIT' }),
    });
    assert.equal(response.status, 503);
    assert.equal(deletedRequestId, 7);
    server.close();
  } finally {
    if (originalUrl === undefined) delete process.env.PUBLIC_APP_URL;
    else process.env.PUBLIC_APP_URL = originalUrl;
  }
});

test('POST /api/v1/partners/:partnerId/continue records a conversion and returns a tracked redirect', async () => {
  let insertParams;
  const pool = mockPool((text, params) => {
    if (/INSERT INTO partner_conversions/.test(text)) { insertParams = params; return {}; }
    return { rows: [] };
  });
  const originalPartners = process.env.PARTNERS_JSON;
  process.env.PARTNERS_JSON = JSON.stringify([{
    id: 'partner-abc', name: 'Test Partner', category: 'ACCOMMODATION',
    redirectUrl: 'https://partner.example/landing', sourceAttribution: 'accommodation_list_click',
  }]);
  try {
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
    const response = await fetch(`http://localhost:${port}/api/v1/partners/partner-abc/continue`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}` },
    });
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.partner, 'Test Partner');
    assert.match(data.redirectUrl, /^https:\/\/partner\.example\/landing\?ref=/);
    assert.deepEqual(insertParams.slice(0, 3), ['u1', 'partner-abc', 'ACCOMMODATION']);
    assert.equal(insertParams[4], 'accommodation_list_click');
    server.close();
  } finally {
    if (originalPartners === undefined) delete process.env.PARTNERS_JSON;
    else process.env.PARTNERS_JSON = originalPartners;
  }
});

test('POST /api/v1/partners/:partnerId/continue records a null user_id for an anonymous visitor', async () => {
  let insertParams;
  const pool = mockPool((text, params) => {
    if (/INSERT INTO partner_conversions/.test(text)) { insertParams = params; return {}; }
    return { rows: [] };
  });
  const originalPartners = process.env.PARTNERS_JSON;
  process.env.PARTNERS_JSON = JSON.stringify([{
    id: 'partner-abc', name: 'Test Partner', category: 'ACCOMMODATION',
    redirectUrl: 'https://partner.example/landing', sourceAttribution: 'accommodation_list_click',
  }]);
  try {
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const response = await fetch(`http://localhost:${port}/api/v1/partners/partner-abc/continue`, { method: 'POST' });
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.match(data.redirectUrl, /^https:\/\/partner\.example\/landing\?ref=/);
    assert.equal(insertParams[0], null);
    server.close();
  } finally {
    if (originalPartners === undefined) delete process.env.PARTNERS_JSON;
    else process.env.PARTNERS_JSON = originalPartners;
  }
});

test('POST /api/v1/partners/:partnerId/continue returns 404 for an unknown partner', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const originalPartners = process.env.PARTNERS_JSON;
  delete process.env.PARTNERS_JSON;
  try {
    const app = createApp({ pool });
    const server = app.listen(0);
    const { port } = server.address();
    const token = require('jsonwebtoken').sign({ sub: 'u1' }, process.env.JWT_SECRET, { algorithm: 'HS256' });
    const response = await fetch(`http://localhost:${port}/api/v1/partners/does-not-exist/continue`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(response.status, 404);
    server.close();
  } finally {
    if (originalPartners === undefined) delete process.env.PARTNERS_JSON;
    else process.env.PARTNERS_JSON = originalPartners;
  }
});

test('GET /privacy serves the privacy policy page', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/privacy`);
  const body = await response.text();
  assert.equal(response.status, 200);
  assert.match(body, /Privacy Policy — Students-Ecosystem/);
  server.close();
});

test('GET /terms serves the terms of service page', async () => {
  const pool = mockPool(() => ({ rows: [] }));
  const app = createApp({ pool });
  const server = app.listen(0);
  const { port } = server.address();
  const response = await fetch(`http://localhost:${port}/terms`);
  const body = await response.text();
  assert.equal(response.status, 200);
  assert.match(body, /Terms of Service — Students-Ecosystem/);
  server.close();
});

test('createMailer throws when BREVO_API_KEY is not configured', () => {
  const original = process.env.BREVO_API_KEY;
  delete process.env.BREVO_API_KEY;
  try {
    assert.throws(() => createMailer(), /BREVO_API_KEY is required/);
  } finally {
    if (original === undefined) delete process.env.BREVO_API_KEY;
    else process.env.BREVO_API_KEY = original;
  }
});
