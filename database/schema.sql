-- Students-Ecosystem Sprint 1 schema. Run through a migration tool in production.

CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(254) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    passport_country CHAR(2),
    cgpa_percentage NUMERIC(5,2) CHECK (cgpa_percentage BETWEEN 0 AND 100),
    liquid_funds_eur NUMERIC(12,2) CHECK (liquid_funds_eur >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE applications_tracker (
    application_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    country_code CHAR(2) NOT NULL,
    university_name VARCHAR(200) NOT NULL,
    program_title VARCHAR(200) NOT NULL,
    programme_url TEXT,
    deadline_at DATE,
    submission_status VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (submission_status IN ('DRAFT', 'DOCUMENTS_IN_PROGRESS', 'SUBMITTED', 'OFFER_RECEIVED', 'DECLINED', 'WITHDRAWN')),
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE application_documents (
    document_id UUID PRIMARY KEY,
    application_id UUID NOT NULL REFERENCES applications_tracker(application_id) ON DELETE CASCADE,
    document_type VARCHAR(80) NOT NULL,
    requirement_source_url TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'NOT_STARTED'
        CHECK (status IN ('NOT_STARTED', 'IN_PROGRESS', 'READY', 'SUBMITTED', 'NOT_REQUIRED')),
    due_at DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE professor_lor_requests (
    request_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    professor_name VARCHAR(150) NOT NULL,
    professor_email VARCHAR(254) NOT NULL,
    university_affiliation VARCHAR(200) NOT NULL,
    token_hash CHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    submitted_document_key TEXT,
    request_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
        CHECK (request_status IN ('PENDING', 'SUBMITTED', 'EXPIRED', 'CANCELLED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE partner_conversions (
    conversion_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    partner_id VARCHAR(80) NOT NULL,
    partner_category VARCHAR(50) NOT NULL,
    unique_tracking_token VARCHAR(128) UNIQUE NOT NULL,
    source_attribution TEXT NOT NULL,
    conversion_status VARCHAR(30) NOT NULL DEFAULT 'REFERRAL_OPENED'
        CHECK (conversion_status IN ('REFERRAL_OPENED', 'CONVERTED', 'REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX applications_user_id_idx ON applications_tracker(user_id);
CREATE INDEX application_documents_application_id_idx ON application_documents(application_id);
CREATE INDEX lor_token_hash_idx ON professor_lor_requests(token_hash);

-- Module: university/college search & admission requirements.
-- source_url and source_checked_on are NOT NULL: no requirement fact may be
-- stored without an official source, matching backend-python/match_engine.py's
-- evaluate_profile(), which already refuses to compare against unsourced data.

CREATE TABLE universities (
    university_id UUID PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    country_code CHAR(2) NOT NULL,
    city VARCHAR(120),
    website_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE academic_programs (
    program_id UUID PRIMARY KEY,
    university_id UUID NOT NULL REFERENCES universities(university_id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    degree_level VARCHAR(30) NOT NULL
        CHECK (degree_level IN ('BACHELOR', 'MASTER', 'PHD', 'DIPLOMA', 'CERTIFICATE')),
    field_of_study VARCHAR(120),
    duration_months SMALLINT CHECK (duration_months > 0),
    programme_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE admission_requirements (
    requirement_id UUID PRIMARY KEY,
    program_id UUID NOT NULL REFERENCES academic_programs(program_id) ON DELETE CASCADE,
    minimum_cgpa_percentage NUMERIC(5,2) CHECK (minimum_cgpa_percentage BETWEEN 0 AND 100),
    official_funds_requirement_eur NUMERIC(12,2) CHECK (official_funds_requirement_eur >= 0),
    language_test_name VARCHAR(50),
    minimum_language_score VARCHAR(20),
    required_documents TEXT[],
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX universities_country_code_idx ON universities(country_code);
CREATE INDEX academic_programs_university_id_idx ON academic_programs(university_id);
CREATE INDEX admission_requirements_program_id_idx ON admission_requirements(program_id);

-- Local development seed data only. These are illustrative sample records,
-- not verified official admission figures. Do not use to advise real students;
-- always confirm current requirements on the university's own site.
INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('11111111-1111-1111-1111-111111111111', 'LMU Munich', 'DE', 'Munich', 'https://www.lmu.de'),
    ('22222222-2222-2222-2222-222222222222', 'TU Delft', 'NL', 'Delft', 'https://www.tudelft.nl');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'M.Sc. Computer Science', 'MASTER', 'Computer Science', 24, 'https://www.lmu.de/en/study/degree-programmes/computer-science-msc'),
    ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'M.Sc. Computer Science', 'MASTER', 'Computer Science', 24, 'https://www.tudelft.nl/en/education/programmes/masters/computer-science');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', 70.00, 11208.00, 'IELTS', '6.5', ARRAY['transcript', 'CV', 'motivation_letter'], 'https://www.lmu.de/en/study/degree-programmes/computer-science-msc', '2026-01-15', 'Sample record for local development only — verify on the official page before use.'),
    ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 75.00, 13000.00, 'IELTS', '6.5', ARRAY['transcript', 'CV', 'statement_of_purpose'], 'https://www.tudelft.nl/en/education/programmes/masters/computer-science', '2026-01-15', 'Sample record for local development only — verify on the official page before use.');

-- Module: scholarships. university_id and program_id are nullable because a
-- scholarship may be programme-specific, university-wide, or country-wide
-- (e.g. DAAD, Chevening). Same NOT NULL sourcing rule as admission_requirements.

CREATE TABLE scholarships (
    scholarship_id UUID PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    provider VARCHAR(200) NOT NULL,
    country_code CHAR(2),
    university_id UUID REFERENCES universities(university_id) ON DELETE CASCADE,
    program_id UUID REFERENCES academic_programs(program_id) ON DELETE CASCADE,
    coverage_type VARCHAR(30) NOT NULL
        CHECK (coverage_type IN ('FULL_TUITION', 'PARTIAL_TUITION', 'LIVING_STIPEND', 'FULL_FUNDING', 'TRAVEL_GRANT')),
    amount_eur NUMERIC(12,2) CHECK (amount_eur >= 0),
    eligibility_notes TEXT,
    application_deadline DATE,
    application_url TEXT,
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX scholarships_university_id_idx ON scholarships(university_id);
CREATE INDEX scholarships_program_id_idx ON scholarships(program_id);
CREATE INDEX scholarships_country_code_idx ON scholarships(country_code);

-- Local development seed data only. Illustrative sample records, not verified
-- official award figures. Always confirm current terms with the provider.
INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('77777777-7777-7777-7777-777777777777', 'LMU Munich International Merit Scholarship', 'LMU Munich', 'DE', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'PARTIAL_TUITION', 3000.00, 'Open to admitted international M.Sc. Computer Science students with a strong academic record.', '2026-05-01', 'https://www.lmu.de/en/study/financing-and-funding', 'https://www.lmu.de/en/study/financing-and-funding', '2026-01-15'),
    ('88888888-8888-8888-8888-888888888888', 'DAAD Study Scholarship', 'German Academic Exchange Service (DAAD)', 'DE', NULL, NULL, 'FULL_FUNDING', 12000.00, 'Country-wide funding for international students admitted to any German university; check DAAD for programme-specific criteria.', '2026-08-31', 'https://www.daad.de/en/study-and-research-in-germany/scholarships/', 'https://www.daad.de/en/study-and-research-in-germany/scholarships/', '2026-01-15');

-- Module: fees requirements. program_fees is always programme-scoped (like
-- admission_requirements). living_cost_estimates is nullable on university_id
-- (like scholarships) so a country-wide estimate can apply when no
-- university-specific figure has been sourced yet. Same NOT NULL sourcing rule.

CREATE TABLE program_fees (
    fee_id UUID PRIMARY KEY,
    program_id UUID NOT NULL REFERENCES academic_programs(program_id) ON DELETE CASCADE,
    fee_type VARCHAR(30) NOT NULL
        CHECK (fee_type IN ('APPLICATION_FEE', 'TUITION_PER_SEMESTER', 'TUITION_PER_YEAR', 'TUITION_TOTAL', 'ADMINISTRATIVE_FEE')),
    student_category VARCHAR(20) NOT NULL DEFAULT 'INTERNATIONAL'
        CHECK (student_category IN ('DOMESTIC', 'EU', 'INTERNATIONAL')),
    amount_eur NUMERIC(12,2) NOT NULL CHECK (amount_eur >= 0),
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE living_cost_estimates (
    estimate_id UUID PRIMARY KEY,
    country_code CHAR(2) NOT NULL,
    city VARCHAR(120),
    university_id UUID REFERENCES universities(university_id) ON DELETE CASCADE,
    category VARCHAR(30) NOT NULL DEFAULT 'GENERAL'
        CHECK (category IN ('GENERAL', 'ACCOMMODATION', 'FOOD', 'TRANSPORT', 'HEALTH_INSURANCE')),
    monthly_estimate_eur NUMERIC(10,2) NOT NULL CHECK (monthly_estimate_eur >= 0),
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX program_fees_program_id_idx ON program_fees(program_id);
CREATE INDEX living_cost_estimates_university_id_idx ON living_cost_estimates(university_id);
CREATE INDEX living_cost_estimates_country_code_idx ON living_cost_estimates(country_code);

-- Local development seed data only. Illustrative sample figures, not verified
-- official fee/cost-of-living data. Always confirm with the university and
-- an official cost-of-living source before advising a real student.
INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333', 'APPLICATION_FEE', 'INTERNATIONAL', 75.00, 'https://www.lmu.de/en/study/degree-programmes/computer-science-msc', '2026-01-15', 'Sample record for local development only — verify on the official page before use.'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'TUITION_PER_YEAR', 'INTERNATIONAL', 0.00, 'https://www.lmu.de/en/study/degree-programmes/computer-science-msc', '2026-01-15', 'Sample record for local development only — verify on the official page before use.'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'APPLICATION_FEE', 'INTERNATIONAL', 100.00, 'https://www.tudelft.nl/en/education/programmes/masters/computer-science', '2026-01-15', 'Sample record for local development only — verify on the official page before use.'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '44444444-4444-4444-4444-444444444444', 'TUITION_PER_YEAR', 'INTERNATIONAL', 20396.00, 'https://www.tudelft.nl/en/education/programmes/masters/computer-science', '2026-01-15', 'Sample record for local development only — verify on the official page before use.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'DE', NULL, NULL, 'GENERAL', 934.00, 'https://www.daad.de/en/study-and-research-in-germany/plan-your-studies/costs/', '2026-01-15', 'Sample record for local development only — verify with an official cost-of-living source.'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'NL', NULL, NULL, 'GENERAL', 1100.00, 'https://www.studyinnl.org/plan-your-stay/cost-of-living', '2026-01-15', 'Sample record for local development only — verify with an official cost-of-living source.');

-- Module: visa requirements. Scoped to a destination country, matched onto a
-- university via its country_code (like living_cost_estimates), independent
-- of any specific programme since visa rules are set by national immigration
-- authorities. applicant_country_code is nullable: NULL means the row is the
-- general process for any nationality; a set value narrows it to applicants
-- holding that passport. Same NOT NULL sourcing rule as every prior module —
-- this is a legal domain where an unsourced guess is actively dangerous.

CREATE TABLE visa_requirements (
    visa_requirement_id UUID PRIMARY KEY,
    destination_country_code CHAR(2) NOT NULL,
    applicant_country_code CHAR(2),
    visa_type VARCHAR(50) NOT NULL
        CHECK (visa_type IN ('STUDY_VISA', 'RESIDENCE_PERMIT', 'SHORT_STAY_EXEMPT', 'TRANSIT_VISA')),
    financial_proof_eur NUMERIC(12,2) CHECK (financial_proof_eur >= 0),
    estimated_processing_days SMALLINT CHECK (estimated_processing_days > 0),
    required_documents TEXT[],
    application_url TEXT,
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX visa_requirements_destination_country_code_idx ON visa_requirements(destination_country_code);
CREATE INDEX visa_requirements_applicant_country_code_idx ON visa_requirements(applicant_country_code);

-- Local development seed data only. Illustrative sample figures, not verified
-- official visa/immigration data. Always confirm current requirements with
-- the destination country's official immigration authority before advising
-- a real student.
INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'DE', NULL, 'STUDY_VISA', 11208.00, 90, ARRAY['passport', 'university_admission_letter', 'proof_of_financial_resources', 'health_insurance_proof', 'biometric_photo'], 'https://www.germany.info/us-en/service/visa', 'https://www.germany.info/us-en/service/visa', '2026-01-15', 'Sample record for local development only — verify on the official mission/embassy page before use.'),
    ('00000000-0000-0000-0000-000000000001', 'NL', NULL, 'RESIDENCE_PERMIT', 13000.00, 60, ARRAY['passport', 'university_admission_letter', 'proof_of_financial_resources', 'tuberculosis_test_if_required'], 'https://ind.nl/en/study', 'https://ind.nl/en/study', '2026-01-15', 'Sample record for local development only — verify on the official IND page before use.');

-- Module: hostel/student accommodation. Always tied to one university
-- (NOT NULL FK, like admission_requirements/program_fees) since a listing is
-- a place near a specific campus, not a national or generic estimate. Same
-- NOT NULL sourcing rule as every prior module.

CREATE TABLE student_accommodations (
    accommodation_id UUID PRIMARY KEY,
    university_id UUID NOT NULL REFERENCES universities(university_id) ON DELETE CASCADE,
    accommodation_type VARCHAR(30) NOT NULL
        CHECK (accommodation_type IN ('UNIVERSITY_DORM', 'PRIVATE_HALL', 'SHARED_APARTMENT', 'HOMESTAY', 'STUDIO_APARTMENT')),
    provider_name VARCHAR(200) NOT NULL,
    city VARCHAR(120) NOT NULL,
    monthly_rent_eur NUMERIC(10,2) NOT NULL CHECK (monthly_rent_eur >= 0),
    deposit_eur NUMERIC(10,2) CHECK (deposit_eur >= 0),
    distance_to_university_km NUMERIC(5,2) CHECK (distance_to_university_km >= 0),
    amenities TEXT[],
    application_url TEXT,
    contact_email VARCHAR(254),
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX student_accommodations_university_id_idx ON student_accommodations(university_id);
CREATE INDEX student_accommodations_city_idx ON student_accommodations(city);

-- Local development seed data only. Illustrative sample figures, not verified
-- official rent/availability data. Always confirm current rent, availability,
-- and terms with the housing provider before advising a real student.
INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('00000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'UNIVERSITY_DORM', 'Studierendenwerk München Oberschleißheim', 'Munich', 430.00, 500.00, 8.50, ARRAY['furnished', 'wifi', 'shared_kitchen', 'laundry'], 'https://www.studierendenwerk-muenchen-oberbayern.de/wohnen/', 'wohnen@studierendenwerk-muenchen-oberbayern.de', 'https://www.studierendenwerk-muenchen-oberbayern.de/wohnen/', '2026-01-15', 'Sample record for local development only — verify current rent and availability on the official page.'),
    ('00000000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'PRIVATE_HALL', 'DUWO Delft', 'Delft', 650.00, 750.00, 2.00, ARRAY['furnished', 'wifi', 'private_bathroom'], 'https://duwo.nl/en/', 'info@duwo.nl', 'https://duwo.nl/en/', '2026-01-15', 'Sample record for local development only — verify current rent and availability on the official page.');

-- Additional seed universities (added 2026-08-22), diversifying beyond DE/NL
-- into North America and the UK. Every fact below was researched live against
-- an official source (university page, national immigration authority, or
-- ECB reference rates for currency conversion) on 2026-08-22, not invented.
-- All monetary figures were published in CAD (Canada) or GBP (UK) and are
-- converted here to EUR using that day's ECB euro foreign exchange reference
-- rate (1 EUR = 1.6074 CAD; 1 EUR = 0.8567 GBP), since this schema stores
-- amounts in EUR uniformly — the original figure and conversion rate/source
-- are recorded in each row's notes so a future reader can verify or redo the
-- conversion rather than trust a stale number. Where the research could not
-- confirm a fact from an official source (e.g. Canada's exact study-permit
-- processing time, Manchester's postgraduate application fee, Ashburne Hall's
-- deposit), that field is left NULL rather than guessed.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('742fe519-872b-4bc6-b17d-40944021636f', 'University of Toronto', 'CA', 'Toronto', 'https://www.utoronto.ca/'),
    ('87c1705f-1721-4d4b-8936-3230cc128a2e', 'The University of Manchester', 'GB', 'Manchester', 'https://www.manchester.ac.uk/');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('e57d58bc-6f27-4525-81ea-24aeb4efd757', '742fe519-872b-4bc6-b17d-40944021636f', 'Master of Science in Applied Computing (MScAC)', 'MASTER', 'Applied Computing', 16, 'https://mscac.utoronto.ca/overview-of-the-mscac-program'),
    ('c6073b8c-5eb7-45a6-9280-469371b0d554', '87c1705f-1721-4d4b-8936-3230cc128a2e', 'MSc Advanced Computer Science', 'MASTER', 'Computer Science', 12, 'https://www.manchester.ac.uk/study/masters/courses/list/21573/msc-advanced-computer-science/');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('8d13bbf4-bf7f-4189-b734-1663c13d69be', 'e57d58bc-6f27-4525-81ea-24aeb4efd757', 77.00, NULL, 'IELTS', '7.0', ARRAY['transcript', 'CV', 'statement_of_purpose', 'three_referee_contacts', 'English_test_scores'], 'https://mscac.utoronto.ca/apply/', '2026-08-22', 'IELTS 7.0 overall with no band below 6.5 (TOEFL iBT 100, Writing ≥22, also accepted). Confirmed live: the standard MSc in Computer Science does NOT consider international applicants (https://web.cs.toronto.edu/graduate/msc) — MScAC is the graduate CS program actually open to international students. Minimum stated as B+ standing (77–79% or 3.3/4.0 GPA). GRE strongly recommended for non-Canadian-degree holders. No distinct admissions-stage funds figure is published by the program itself — see visa_requirements for Canada''s study-permit financial proof instead.'),
    ('68657e1b-9fb8-4e15-8cfd-1ecbc5b447ac', 'c6073b8c-5eb7-45a6-9280-469371b0d554', 70.00, NULL, 'IELTS', '7.0', ARRAY['transcript', 'degree_certificate', 'CV', 'English_language_certificate'], 'https://www.manchester.ac.uk/study/masters/courses/list/21573/msc-advanced-computer-science/', '2026-08-22', 'IELTS 7.0 overall with no sub-score below 6.5. Headline requirement: UK First-class honours (70% average) or overseas equivalent, minimum 50% Computer Science content. Published country-specific equivalents vary, e.g. China ≈87%, India ≈65% (First Class with Distinction) — verify the exact figure for your own country on the official page. CV required only if graduated more than 3 years ago. No distinct admissions-stage funds figure is published by the program itself — see visa_requirements for the UK Student visa''s maintenance-funds requirement instead.');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('97509fa9-c0e4-4983-bf68-a815aabfdcea', 'e57d58bc-6f27-4525-81ea-24aeb4efd757', 'APPLICATION_FEE', 'INTERNATIONAL', 80.88, 'https://www.sgs.utoronto.ca/future-students/admission-application-requirements/', '2026-08-22', 'Original figure: CAD 130 (non-refundable, applies to all School of Graduate Studies applicants), converted to EUR using the ECB reference rate (1 EUR = 1.6074 CAD, 2026-08-21) — https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/eurofxref-graph-cad.en.html. Verify the current CAD figure directly.'),
    ('74863581-87ac-4d9d-b6de-e3192ad2fc81', 'e57d58bc-6f27-4525-81ea-24aeb4efd757', 'TUITION_TOTAL', 'INTERNATIONAL', 56022.15, 'https://mscac.utoronto.ca/apply/', '2026-08-22', 'Original figure: CAD 90,050 total for the whole 16-month MScAC program (includes a mandatory CAD 2,200 pre-program fee), converted to EUR using the ECB reference rate (1 EUR = 1.6074 CAD, 2026-08-21). This is a program TOTAL, not a per-year figure — do not compare directly to per-year tuition at other universities without adjusting. Standard MSc/PhD CS tuition (≈ CAD 34,900/year) does not apply here since international students are not admitted to that program. Verify the current CAD figure directly.'),
    ('de8ff7cf-5b58-4cd4-8503-dbd5a6992464', 'c6073b8c-5eb7-45a6-9280-469371b0d554', 'TUITION_PER_YEAR', 'INTERNATIONAL', 45990.43, 'https://www.manchester.ac.uk/study/masters/courses/list/21573/msc-advanced-computer-science/', '2026-08-22', 'Original figure: GBP 39,400/year (2026 entry), converted to EUR using the ECB reference rate (1 EUR = 0.8567 GBP, 2026-08-21) — https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/eurofxref-graph-gbp.en.html. A GBP 2,500 tuition deposit is also required before CAS issuance for self-funded students (not included here). No application fee row is included: a GBP 60 figure appears on third-party sites but could not be confirmed on an official manchester.ac.uk page, so it is omitted rather than stated as fact. Verify the current GBP figure directly.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('b6583e0b-e49b-4ded-9c29-a1ba9f19c8a0', 'Ontario Graduate Scholarship (OGS)', 'Government of Ontario, jointly with University of Toronto', 'CA', '742fe519-872b-4bc6-b17d-40944021636f', NULL, 'LIVING_STIPEND', 3110.61, 'International students with a valid study permit are eligible for a limited allocation. Requires full-time enrolment in an eligible 2–3 term graduate program and generally an A- average or equivalent in the last two completed years of study. Award is CAD 5,000/session (converted here), CAD 10,000 for two consecutive sessions, or CAD 15,000 for three — this record reflects the single-session amount only. Deadlines are set individually by each graduate unit, not university-wide, so no single application_deadline is recorded.', NULL, 'https://www.sgs.utoronto.ca/awards-funding/scholarships-awards/ontario-graduate-scholarship-application-instructions/', 'https://www.sgs.utoronto.ca/awards/ontario-graduate-scholarship/', '2026-08-22'),
    ('dfdec4b3-94b3-4b00-8222-62b9b4950c7d', 'Global Futures Scholarship (South Asia)', 'The University of Manchester', 'GB', '87c1705f-1721-4d4b-8936-3230cc128a2e', NULL, 'PARTIAL_TUITION', 11672.70, 'Restricted to international fee-paying students domiciled in Bangladesh, India, Pakistan, or Sri Lanka (having predominantly lived there the last 3 years), holding an offer for a full-time, on-campus master''s starting September, and self-funded (not sponsored). Excludes MBA, MPhil, MArch, MA Architecture & Urbanism, MLA, PGCE, Clinical Medicine, Dentistry, and some Master''s by Research programmes. Amount shown (GBP 10,000, converted here) is the confirmed figure for students domiciled in India specifically; the broader Global Futures Scholarship also covers ~20 other countries (China, Nigeria, UAE, etc.) at amounts this research could not individually confirm. Deadline recurs annually (most recently 24 April) — confirm the current cycle''s exact date with international@manchester.ac.uk before relying on it, since no future-dated cycle was published at time of writing. Applied via an online form sent to eligible offer-holders, not a standalone public URL.', NULL, NULL, 'https://www.manchester.ac.uk/study/international/country-specific-information/india/', '2026-08-22');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('a100e9d6-ee58-4a37-a171-43f63c69edfe', 'CA', NULL, 'STUDY_VISA', 14243.50, NULL, ARRAY['letter_of_acceptance', 'passport', 'proof_of_financial_support'], 'https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/apply.html', 'https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/get-documents/financial-support.html', '2026-08-22', 'Original figure: CAD 22,895 (single applicant, outside Quebec, effective 2025-09-01 — IRCC re-indexes this every September 1, so it may change shortly after this check date), converted to EUR using the ECB reference rate (1 EUR = 1.6074 CAD, 2026-08-21). Excludes tuition and transportation, which must be shown separately. Processing time intentionally left blank: IRCC does not publish one fixed figure for a standard (non-doctoral) study permit on the pages checked — only a 2-week fast-track for doctoral students, which does not apply here. Check current times at https://www.canada.ca/en/immigration-refugees-citizenship/services/application/check-processing-times.html rather than relying on a guessed number.'),
    ('8cbe5955-b8cd-4b93-b3bf-1887a621fb8e', 'GB', NULL, 'STUDY_VISA', 12301.86, 21, ARRAY['CAS_number', 'passport', 'proof_of_financial_support', 'English_language_certificate', 'tb_test_certificate_if_required'], 'https://www.gov.uk/student-visa/apply', 'https://www.gov.uk/student-visa/money', '2026-08-22', 'Original figure: GBP 1,171/month maintenance funds (outside London — applies to Manchester) × 9 months = GBP 10,539 total, converted to EUR using the ECB reference rate (1 EUR = 0.8567 GBP, 2026-08-21). London-based study requires a higher GBP 1,529/month. A GBP 558 visa application fee and a GBP 776/year Immigration Health Surcharge also apply and are not included in this figure. Processing time of 21 days reflects gov.uk''s "usually within 3 weeks" guidance for applications made from outside the UK; applications made inside the UK usually take up to 8 weeks instead. Verify current GBP figures directly at gov.uk.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('cb5f4fc7-c842-4a5d-acda-339494e2ed09', 'CA', 'Toronto', '742fe519-872b-4bc6-b17d-40944021636f', 'GENERAL', 1790.16, 'https://www.studentlife.utoronto.ca/task/living-costs-in-toronto/', '2026-08-22', 'The University of Toronto''s Student Life office publishes category ranges (e.g. housing CAD 1,220–2,700, groceries CAD 350+, transport, utilities, etc.) rather than one lump monthly total. This figure is the midpoint (CAD 2,877.50/month) of the summed published ranges (≈ CAD 2,025–3,730/month), converted to EUR using the ECB reference rate (1 EUR = 1.6074 CAD, 2026-08-21). Treat as a rough estimate, not an official single figure — see the source page for the full breakdown.'),
    ('e797665b-ec48-4889-a3d0-ba52290b28dc', 'GB', 'Manchester', '87c1705f-1721-4d4b-8936-3230cc128a2e', 'GENERAL', 1732.23, 'https://www.manchester.ac.uk/study/undergraduate/fees-and-funding/cost-of-living/', '2026-08-22', 'Original figure: GBP 1,484/month (self-catered, own accommodation), from the university''s published 2026/7 cost-of-living guide, converted to EUR using the ECB reference rate (1 EUR = 0.8567 GBP, 2026-08-21). The source page is labelled for undergraduates — no distinct official postgraduate-specific Manchester cost-of-living figure was found, so this is used as a general city estimate. Guide value only, based on April 2026 grocery prices and student money survey data.');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('f2ce2ee5-db4e-4206-a8a8-1b9cbc2a8039', '742fe519-872b-4bc6-b17d-40944021636f', 'UNIVERSITY_DORM', 'Graduate House (University of Toronto)', 'Toronto', 910.74, 311.06, NULL, ARRAY['furnished', 'wifi', 'all_utilities_included', 'shared_kitchen'], 'https://gradhouse.utoronto.ca/', 'information.gradhouse@utoronto.ca', 'https://gradhouse.utoronto.ca/fees-2026-27/', '2026-08-22', 'On-campus graduate-only residence at 60 Harbord Street — no distance-to-campus figure applies since it is directly on the St. George campus (left NULL rather than guessed). Rent shown is the official 2026-27 Economy Single rate (CAD 1,463.93/month); Double CAD 1,208.05, Regular Single CAD 1,581.52, and Premium Single CAD 1,766.03/month are also available. A CAD 350 application fee applies to all, and the CAD 500 damage deposit shown applies only to non-University of Toronto students. Converted to EUR using the ECB reference rate (1 EUR = 1.6074 CAD, 2026-08-21). Verify current CAD rates directly.'),
    ('a59da7a0-6d6f-445b-a9ce-f2239634dbaf', '87c1705f-1721-4d4b-8936-3230cc128a2e', 'UNIVERSITY_DORM', 'Ashburne Hall (University of Manchester)', 'Manchester', 814.37, NULL, 2.57, ARRAY['furnished', 'wifi', 'bills_included', 'laundry', 'bike_storage'], 'https://www.manchester.ac.uk/study/accommodation/student-accommodation/search/ashburne-hall/', 'accommodation@manchester.ac.uk', 'https://www.manchester.ac.uk/study/accommodation/student-accommodation/search/ashburne-hall/', '2026-08-22', 'Rent shown is the official 2026/27 postgraduate 51-week Standard Room rate (GBP 161/week, converted to a monthly figure using 52/12 weeks-per-month, then to EUR at the ECB reference rate 1 EUR = 0.8567 GBP, 2026-08-21). A postgraduate 51-week Super Single is also available at GBP 181/week; standard 41-week undergraduate contracts range GBP 178–198/week. Distance is ~1.6 miles (converted to km) from University Place (main campus), per the official page. Security deposit amount is not published on the official page and is left NULL rather than guessed.');

-- Global, need-based scholarships (added 2026-08-22). Unlike the university-tied
-- scholarships above, these are large, well-known, globally-open funding
-- programmes explicitly aimed at students who could not otherwise afford to
-- study abroad — the core of this project's mission to help students from
-- under-resourced and displaced backgrounds reach their target degree. Amounts
-- are intentionally left NULL where the provider varies the award by country
-- or circumstance rather than publishing one figure, per this schema's
-- never-guess rule.
INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('1a2b3c4d-0001-4a1a-9c1a-000000000001', 'Chevening Scholarship', 'UK Foreign, Commonwealth & Development Office (FCDO)', 'GB', NULL, NULL, 'FULL_FUNDING', NULL, 'UK government''s flagship global master''s scholarship: fully funds a one-year taught master''s at any UK university (tuition, living costs, and travel). Requires citizenship of a Chevening-eligible country (most of Asia, Africa, Latin America, and parts of Europe are covered — check the official country list, since eligibility is NOT global), a completed bachelor''s degree, and at least two years (2,800 hours) of work experience; scholars must return to their home country for at least two years afterward. Selection is based on leadership, networking, career plan, and study proposal — not financial need specifically, but it removes the entire cost barrier for admitted students from eligible countries.', '2026-10-06', 'https://www.chevening.org/apply/', 'https://www.chevening.org/scholarship/india/', '2026-08-22'),
    ('1a2b3c4d-0002-4a1a-9c1a-000000000002', 'Fulbright Foreign Student Program', 'U.S. Department of State / Bureau of Educational and Cultural Affairs', 'US', NULL, NULL, 'FULL_FUNDING', NULL, 'Fully funds graduate study or research in the US (tuition, airfare, living stipend, health insurance) for ~4,000 international students per year. Eligibility, exact benefits, deadlines, and application process are set per country by the local Fulbright Commission or the U.S. Embassy''s Public Affairs Section (49 countries have a binational Commission; others are run directly by the embassy) — applicants must find and apply through their own country''s Fulbright page via the official portal, not a single global form. No age limit; applicants may not simultaneously hold US citizenship/permanent residency.', NULL, 'https://foreign.fulbrightonline.org/apply', 'https://foreign.fulbrightonline.org/about/foreign-student-program', '2026-08-22'),
    ('1a2b3c4d-0003-4a1a-9c1a-000000000003', 'DAFI Tertiary Scholarship Programme (Albert Einstein German Academic Refugee Initiative)', 'UNHCR, funded principally by the Government of Germany', NULL, NULL, NULL, 'FULL_FUNDING', NULL, 'Specifically for recognized refugees and returnees (not open to the general public) to pursue an undergraduate degree, normally in their country of asylum or home country. Active in 59 countries; has supported 27,200+ students since 1992. Coverage (tuition, study materials, food, transport, accommodation) and the exact application process vary by country and are run through the local UNHCR country office, not a single global application form — a student should contact their nearest UNHCR office or national partner to check current eligibility and deadlines. Country_code is left NULL because the programme is not tied to one destination country; it funds study wherever the student has asylum or is returning to.', NULL, NULL, 'https://www.unhcr.org/what-we-do/build-better-futures/education/higher-education-and-skills/dafi-tertiary-scholarship-0', '2026-08-22');

-- Module: support & resources. Not every barrier a student from an
-- under-resourced or displaced background faces is a scholarship, admission
-- requirement, or visa rule — some are simply not knowing free, legitimate
-- help exists (a real advising office instead of a paid "consultancy"; a fee
-- waiver instead of an unaffordable test fee; a way to prove your own
-- transcript exists when your home country's records office is destroyed or
-- inaccessible). This table exists to surface exactly those, each with the
-- same NOT NULL sourcing rule as every other factual module — a made-up
-- "free help" listing would be worse than none at all.
CREATE TABLE support_resources (
    resource_id UUID PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    provider VARCHAR(200) NOT NULL,
    category VARCHAR(30) NOT NULL
        CHECK (category IN ('FREE_ADVISING', 'TEST_FEE_WAIVER', 'APPLICATION_FEE_WAIVER', 'REFUGEE_SUPPORT', 'CREDENTIAL_RECOVERY', 'EMERGENCY_FUND', 'MENTAL_HEALTH', 'LEGAL_AID')),
    country_code CHAR(2),
    description TEXT NOT NULL,
    eligibility_notes TEXT,
    application_url TEXT,
    contact_email VARCHAR(254),
    source_url TEXT NOT NULL,
    source_checked_on DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX support_resources_category_idx ON support_resources(category);
CREATE INDEX support_resources_country_code_idx ON support_resources(country_code);

-- Real, currently operating programmes only, each checked live on 2026-08-22
-- against an official/authoritative source. country_code is the destination
-- the resource is most relevant to, or NULL when the resource is genuinely
-- global and not tied to one destination.
INSERT INTO support_resources (resource_id, name, provider, category, country_code, description, eligibility_notes, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('2b3c4d5e-0001-4b1b-9c1b-000000000001', 'EducationUSA Advising Centers', 'U.S. Department of State', 'FREE_ADVISING', 'US', 'A US government network of 430+ advising centers in 175+ countries and territories giving free, accurate, unbiased guidance on US admissions, accredited/SEVP-certified colleges, and the visa process — the intended alternative to a paid education agent.', 'Free for all international students; centers are located in embassies/consulates or partner institutions (Fulbright commissions, NGOs like AMIDEAST and American Councils, universities, libraries). Find your nearest center on the official site.', 'https://educationusa.state.gov/find-advising-center', NULL, 'https://educationusa.state.gov/educationusa-advising-centers', '2026-08-22', 'Advising is free; it does not itself fund tuition or fees — pair with a needs-based scholarship such as Fulbright.'),
    ('2b3c4d5e-0002-4b1b-9c1b-000000000002', 'Duolingo English Test Access Program', 'Duolingo', 'TEST_FEE_WAIVER', NULL, 'Distributes 10,000+ full fee waivers a year for the Duolingo English Test, the language-proficiency test accepted by thousands of universities worldwide, plus free official prep materials, to students who could not otherwise afford the test fee.', 'A student cannot apply directly — a school counselor or an official at a partner institution, NGO, or global education program must request the waiver on the student''s behalf. Prioritizes low-income, refugee, and displaced applicants. Ask your target university''s international office or an EducationUSA/DAAD-type advising center whether they hold Access Program codes.', 'https://englishtest.duolingo.com/access', NULL, 'https://blog.englishtest.duolingo.com/duolingo-access-program', '2026-08-22', 'Since 2018 the program has distributed 117,000+ waivers (~$8M USD value); 25,563 waivers were given in 2024 alone, per Duolingo''s own program page.'),
    ('2b3c4d5e-0003-4b1b-9c1b-000000000003', 'Article 26 Backpack', 'UC Davis Article 26 Backpack initiative', 'CREDENTIAL_RECOVERY', NULL, 'A free, secure online platform (named for the UDHR''s right-to-education article) where refugees and other displaced students can store and share transcripts, diplomas, CVs, and video testimonials with universities, scholarship providers, and employers — including limited support to reconstruct or assess credentials when a student''s home institution or national records office is destroyed, inaccessible, or unable to issue documents.', 'Aimed at refugees and other forcibly displaced or at-risk students. Local "Backpack Guides" (often fellow students) can assist with uploading documents. Available in English, Arabic, Dari/Farsi, French, and Spanish.', 'https://backpack.ucdavis.edu/', NULL, 'https://globalaffairs.ucdavis.edu/a26backpack', '2026-08-22', 'Has reached 5,000+ student refugees worldwide as of the last published figures.');
