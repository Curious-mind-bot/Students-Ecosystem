const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('./server');

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
