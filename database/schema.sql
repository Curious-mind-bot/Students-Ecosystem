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

-- A student's personal document registry (e.g. IELTS score, passport) tracked
-- by metadata only — obtained/expiry dates and notes, no file storage. Actual
-- uploads are intentionally out of scope until a secure storage/retention
-- policy exists (see application_documents and professor_lor_requests below).
CREATE TABLE student_documents (
    student_document_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    document_type VARCHAR(80) NOT NULL,
    label VARCHAR(150),
    obtained_at DATE,
    expires_at DATE,
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

CREATE TABLE password_reset_tokens (
    token_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    token_hash CHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
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
CREATE INDEX student_documents_user_id_idx ON student_documents(user_id);
CREATE INDEX lor_token_hash_idx ON professor_lor_requests(token_hash);
CREATE INDEX password_reset_tokens_token_hash_idx ON password_reset_tokens(token_hash);

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
        CHECK (degree_level IN ('BACHELOR', 'MASTER', 'PHD', 'DIPLOMA', 'CERTIFICATE', 'SHORT_COURSE')),
    field_of_study VARCHAR(120),
    duration_months SMALLINT CHECK (duration_months > 0),
    duration_weeks SMALLINT CHECK (duration_weeks > 0),
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

-- Anonymous demand-signal log for the institute analytics product: no
-- user_id, no IP, nothing that identifies a student — only which
-- university/programme was looked at and when, so we can sell universities
-- an aggregate "how much interest are we getting" view without touching
-- individual student data.
CREATE TABLE demand_events (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(30) NOT NULL CHECK (event_type IN ('UNIVERSITY_VIEW', 'PROGRAM_VIEW')),
    university_id UUID REFERENCES universities(university_id) ON DELETE CASCADE,
    program_id UUID REFERENCES academic_programs(program_id) ON DELETE CASCADE,
    country_code CHAR(2),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX demand_events_university_id_idx ON demand_events(university_id);
CREATE INDEX demand_events_program_id_idx ON demand_events(program_id);
CREATE INDEX demand_events_occurred_at_idx ON demand_events(occurred_at);

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
        CHECK (category IN ('FREE_ADVISING', 'TEST_FEE_WAIVER', 'APPLICATION_FEE_WAIVER', 'REFUGEE_SUPPORT', 'CREDENTIAL_RECOVERY', 'EMERGENCY_FUND', 'MENTAL_HEALTH', 'LEGAL_AID', 'PEER_MENTORSHIP')),
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

-- Peer mentorship / "chat with a current student" programmes. Researched
-- against several universities already seeded above; only kept the two whose
-- official page could actually be fetched and confirmed live on 2026-08-22.
-- Programmes found at University of Nicosia, TU Dublin, University of
-- Manchester, LMU Munich, the three Austrian universities, and the
-- Erasmus Student Network buddy system were all either unconfirmable from a
-- live official page, out of scope (staff/alumni networking rather than a
-- prospective-student chat), or restricted to already-admitted students —
-- omitted rather than guessed at; can be added once independently confirmed.
INSERT INTO support_resources (resource_id, name, provider, category, country_code, description, eligibility_notes, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('2b3c4d5e-0004-4b1b-9c1b-000000000004', 'Chat with a Student', 'TU Delft', 'PEER_MENTORSHIP', 'NL', 'Lets prospective bachelor''s and master''s applicants message a current TU Delft student directly to ask about a programme, studying and living in Delft, and student life before applying.', 'Free and open to prospective applicants; no admission decision or enrollment required first. Students aim to reply within 24 hours.', 'https://www.tudelft.nl/en/education/study-programme-orientation/preparing-for-a-bachelor/chat-with-a-student', NULL, 'https://www.tudelft.nl/en/education/study-programme-orientation/preparing-for-a-bachelor/chat-with-a-student', '2026-08-22', NULL),
    ('2b3c4d5e-0005-4b1b-9c1b-000000000005', 'Talk to a Current Student (Student Ambassadors)', 'European University Cyprus', 'PEER_MENTORSHIP', 'CY', 'A student-ambassador program connecting prospective students with current European University Cyprus students for informal advice on courses, housing, and student life before applying.', 'No eligibility restriction stated on the official page.', NULL, 'nicosia@euc.ac.cy', 'https://euc.ac.cy/en/student-ambassadors/', '2026-08-22', 'The fetched page did not surface a direct chat link — it lists the Nicosia campus contact (nicosia@euc.ac.cy, +357 22713000) and a Frankfurt campus contact (frankfurt@euc.ac.cy, +49 69 210855800) instead.');

-- Additional seed universities (added 2026-08-22, second batch): Cyprus and
-- Austria, part of growing coverage toward the requested 32-country /
-- 5-10-universities-each target. Every fact below was researched live against
-- an official source (university page or national/EU immigration authority)
-- on 2026-08-22. Both countries use EUR, so no currency conversion is needed
-- here. Several figures could not be confirmed from a live, fully-loading
-- official page during research (e.g. University of Nicosia's tuition, which
-- appeared only in a search-index snippet of a page that returned truncated
-- content on direct fetch, and Cyprus's exact visa financial-proof figure,
-- which appeared only via a search-cached quote of a 403-blocked gov.cy page)
-- — those fields are left NULL rather than stated as fact, with the
-- unconfirmed figure disclosed in notes for a future reader to verify
-- directly. A scholarship for European University Cyprus was also dropped
-- entirely rather than seeded, because its official page 404s.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('4fc306dd-4e23-41e4-83e6-9347b1d43525', 'University of Nicosia', 'CY', 'Nicosia', 'https://www.unic.ac.cy/'),
    ('c2b136d8-ae59-443a-b8f4-a7d870b4a38f', 'Frederick University', 'CY', 'Nicosia', 'https://www.frederick.ac.cy/'),
    ('04a392cb-8e78-40ee-b628-e5a2a4413a81', 'European University Cyprus', 'CY', 'Nicosia', 'https://euc.ac.cy/'),
    ('eec24dc1-e8d5-4c38-9464-667b9e7af527', 'FH Technikum Wien', 'AT', 'Vienna', 'https://www.technikum-wien.at'),
    ('4510f82d-2eaa-4f40-a152-7ce3957a341c', 'MODUL University Vienna', 'AT', 'Vienna', 'https://www.modul.ac.at'),
    ('ec3581c8-c157-48c4-b4f4-bab3d21e8a69', 'FHWien der WKW', 'AT', 'Vienna', 'https://www.fh-wien.ac.at');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('06984a9c-c6fb-4653-a685-195e0c52be64', '4fc306dd-4e23-41e4-83e6-9347b1d43525', 'MSc Computer Science (Cyber Security / Mobile Systems)', 'MASTER', 'Computer Science', 18, 'https://www.unic.ac.cy/computer-science-concentrations-1-cyber-security-2-mobile-systems-msc-1-5-years-or-3-semesters/'),
    ('76bc0c86-98e5-40c9-ba81-9b561ac2e2e0', 'c2b136d8-ae59-443a-b8f4-a7d870b4a38f', 'MSc in Marine Engineering and Management', 'MASTER', 'Marine Engineering', 18, 'https://www.frederick.ac.cy/en/msc-in-marine-engineering-and-management'),
    ('99428d92-ad32-4987-ae47-891dd77522bb', '04a392cb-8e78-40ee-b628-e5a2a4413a81', 'MSc in Cybersecurity', 'MASTER', 'Cybersecurity', 18, 'https://euc.ac.cy/en/programs/master-cybersecurity/'),
    ('a63f701c-c510-459a-8533-0f765715f5eb', 'eec24dc1-e8d5-4c38-9464-667b9e7af527', 'Master Industrial Engineering and Business (MSc)', 'MASTER', 'Industrial Engineering', 24, 'https://www.technikum-wien.at/en/programs/master-industrial-engineering-and-business/'),
    ('fa3c21a8-b72b-40c9-9494-6615d29b7402', '4510f82d-2eaa-4f40-a152-7ce3957a341c', 'MSc in International Tourism Management', 'MASTER', 'Tourism Management', 24, 'https://www.modul.ac.at/programs/masters-programs/msc-in-international-tourism-management'),
    ('2909b2d4-e7d1-4e78-945b-e420d10c2dcb', 'ec3581c8-c157-48c4-b4f4-bab3d21e8a69', 'Master Executive Management (MA)', 'MASTER', 'Business Administration', 24, 'https://www.fh-wien.ac.at/en/study/master/executive-management/');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('238d467d-2a14-4485-98fd-ef736cdc8045', '06984a9c-c6fb-4653-a685-195e0c52be64', NULL, NULL, 'IELTS', '6.5', ARRAY['transcript', 'CV', 'two_recommendation_letters', 'personal_statement'], 'https://www.unic.ac.cy/', '2026-08-22', 'Bachelor''s degree from a recognized/accredited institution required. IELTS 6.5 or TOEFL iBT 79 (also accepted, per the official admission-requirements page as indexed — the live page returned truncated content on direct fetch, so re-verify the exact score before relying on it). No numeric minimum CGPA is published. Tuition and application fee could not be confirmed on a fully-loading official page (a €134/ECTS × 90 = €12,060 figure appeared only in a search-index snippet) — left out of program_fees entirely rather than stated as fact.'),
    ('a3b12b85-f02e-44d8-a68e-fa41b3348557', '76bc0c86-98e5-40c9-ba81-9b561ac2e2e0', NULL, NULL, NULL, NULL, ARRAY['official_transcripts', 'grade_reports'], 'https://www.frederick.ac.cy/en/msc-in-marine-engineering-and-management', '2026-08-22', 'Requires an undergraduate degree in Mechanical, Naval, or Electrical Engineering (or equivalent). English proficiency via TOEFL/IELTS/GCSE/IGCSE/Cambridge CPE, an English-medium school certificate, OR 50%+ on Frederick''s own English Placement Test — no single numeric IELTS/TOEFL threshold is published on this programme''s own page (a general figure of TOEFL 70+/IELTS 6+ appears elsewhere on the domain but is not confirmed for this specific programme, so language_test_name/minimum_language_score are left NULL). No numeric minimum CGPA published.'),
    ('3ca01ba4-30ca-4dbe-804c-eb692a0ebeb3', '99428d92-ad32-4987-ae47-891dd77522bb', NULL, NULL, NULL, NULL, ARRAY['online_application_form', 'bachelor_degree_transcript', 'high_school_certificate', 'two_referee_contacts', 'passport_copy', 'CV_and_photo'], 'https://euc.ac.cy/en/programs/master-cybersecurity/', '2026-08-22', 'This programme is offered in ONLINE/distance-learning mode only (flagged since on-campus study was the general research target). Requires a Bachelor''s in Computer Science/Computer Engineering/Information Systems/Electronic Engineering or related field (preparatory courses available otherwise). English requirement is CEFR B2+ (exempt for UK/Canada/Australia/US/New Zealand nationals) — no numeric IELTS/TOEFL score is published, so language_test_name/minimum_language_score are left NULL. Next intake: October 2026.'),
    ('542020c5-20c9-4543-900e-0a987c78e60b', 'a63f701c-c510-459a-8533-0f765715f5eb', NULL, NULL, NULL, NULL, ARRAY['transcript', 'CV'], 'https://www.technikum-wien.at/en/programs/master-industrial-engineering-and-business/', '2026-08-22', 'Taught in German (35 ECTS offered in English). Requires a Bachelor''s degree from a University of Applied Sciences in a relevant field, or an equivalent degree (at least 180 ECTS) from a recognised post-secondary institution; supplementary exams may be imposed for missing prerequisites. No numeric minimum CGPA or German/English test score is published on the official programme page — left NULL rather than guessed.'),
    ('2750703f-0f70-4dc1-9eba-c469e04453e2', 'fa3c21a8-b72b-40c9-9494-6615d29b7402', NULL, NULL, 'IELTS', '7.0', ARRAY['CV', 'motivation_letter', 'transcript', 'passport_copy', 'passport_photo', 'two_recommendation_letters', 'english_test_certificate'], 'https://www.modul.ac.at/programs/masters-programs/msc-in-international-tourism-management', '2026-08-22', 'Requires a Bachelor''s degree (minimum 3-year duration) in a related field (tourism/hospitality, marketing, management science, geography, planning, sociology, policy, or economics). English proficiency (CEFR C1): IELTS 7.0 overall with no sub-score below 6.5, or TOEFL 95 iBT (570 PBT/230 CBT), or Pearson Academic 76, or Cambridge Grade C (min. 180 points) — IELTS shown here as the representative figure. No numeric minimum GPA is published.'),
    ('00bd53d5-fa36-4cd0-87f4-4151b36fe974', '2909b2d4-e7d1-4e78-945b-e420d10c2dcb', NULL, NULL, NULL, NULL, ARRAY['application_form'], 'https://www.fh-wien.ac.at/en/study/application/admissions-procedure-master/executive-management/', '2026-08-22', 'Admission requires a relevant Bachelor''s degree/basic business knowledge, assessed via a computer-based admissions test (general business administration plus subject-specific) and a personal interview conducted in English — English competency is assessed through the interview itself rather than a certificate threshold, so no numeric IELTS/TOEFL score or minimum CGPA is published. Application deadline: 30 March 2026 for Fall 2026 intake (9 March 2026 for applicants whose final academic documents come from a third country); test window 8-24 April 2026; interviews from 6 May 2026.');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('0850ee77-3d98-4a23-827d-62bb3efada98', '76bc0c86-98e5-40c9-ba81-9b561ac2e2e0', 'APPLICATION_FEE', 'INTERNATIONAL', 55.00, 'https://www.frederick.ac.cy/en/tuition-and-other-fees', '2026-08-22', 'Non-refundable, one-time. A separate EUR 200 visa-processing fee also applies to third-country nationals per the same page (not included here — it is an immigration fee, not a university fee).'),
    ('3117a35a-86fa-471e-afde-5ff0b9928e3e', '76bc0c86-98e5-40c9-ba81-9b561ac2e2e0', 'TUITION_TOTAL', 'INTERNATIONAL', 9000.00, 'https://www.frederick.ac.cy/en/msc-in-marine-engineering-and-management', '2026-08-22', 'Uniform rate for all students (no separate international rate published) for the whole 18-month programme.'),
    ('c3c3ae63-0c07-4dd0-8a56-8dfcbdede903', '99428d92-ad32-4987-ae47-891dd77522bb', 'APPLICATION_FEE', 'INTERNATIONAL', 80.00, 'https://euc.ac.cy/en/programs/master-cybersecurity/', '2026-08-22', 'Base figure; the official page also mentions "or EUR 200 where applicable" for certain nationalities/routes without specifying which — verify your own case directly.'),
    ('f9cc7c14-d133-499a-adea-f17bb6b65ceb', '99428d92-ad32-4987-ae47-891dd77522bb', 'TUITION_TOTAL', 'INTERNATIONAL', 6237.00, 'https://euc.ac.cy/en/programs/master-cybersecurity/', '2026-08-22', 'For the full 90-ECTS, 18-month programme.'),
    ('e6aff346-c6cb-46ba-acbb-5b20be8e4aa3', 'a63f701c-c510-459a-8533-0f765715f5eb', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 3000.00, 'https://www.technikum-wien.at/en/student-guide/tution/', '2026-08-22', 'Third-country/non-EU rate (EU/EEA students pay EUR 363.36/semester instead). A refundable EUR 250 deposit is also due within 5 working days of a conditional admission offer (not a fee, so not included as its own row).'),
    ('26887adf-52f1-4d30-8663-a4ff77565bc7', 'a63f701c-c510-459a-8533-0f765715f5eb', 'ADMINISTRATIVE_FEE', 'INTERNATIONAL', 25.20, 'https://www.technikum-wien.at/en/student-guide/tution/', '2026-08-22', 'Mandatory ÖH (Austrian National Union of Students) fee per semester, applies to all students regardless of nationality.'),
    ('f27c6258-3a38-4571-a4b7-db875be4e9ff', 'fa3c21a8-b72b-40c9-9494-6615d29b7402', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 7000.00, 'https://www.modul.ac.at/study-at-mu/tuition-fees', '2026-08-22', 'MODUL is a private university; no separate application fee or ÖH fee is published on the official fees page.'),
    ('da0185a7-3783-446c-8a9f-5d0b7d4befdc', '2909b2d4-e7d1-4e78-945b-e420d10c2dcb', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 1000.00, 'https://www.fh-wien.ac.at/en/study/application/program-costs/', '2026-08-22', 'Rate for "other third-country nationals" (EU/EEA/Swiss and some exceptional third-country cases pay EUR 363.36/semester instead). A refundable EUR 200 deposit for third-country nationals is credited toward tuition (not included as its own row). No published application fee — admission is via a paid-free computer-based test plus interview instead.'),
    ('b70dd1c1-c0cc-4110-b9a9-7c64ab4bf7ac', '2909b2d4-e7d1-4e78-945b-e420d10c2dcb', 'ADMINISTRATIVE_FEE', 'INTERNATIONAL', 26.20, 'https://www.fh-wien.ac.at/en/study/application/program-costs/', '2026-08-22', 'Mandatory ÖH fee per semester, applies to all students regardless of nationality.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('45981600-12b2-47c5-9169-895631988671', 'CyprusAid Scholarship', 'University of Nicosia, in cooperation with the Cyprus Ministry of Foreign Affairs', 'CY', '4fc306dd-4e23-41e4-83e6-9347b1d43525', NULL, 'FULL_FUNDING', NULL, 'Covers 100% of tuition (for selected Bachelor''s programmes, excluding Medical School, and selected Master''s programmes: MBA, MA International Relations & Eastern Mediterranean Studies, MA Digital Media & Communications — NOT the MSc Computer Science programme this university is otherwise seeded with here), plus accommodation, living expenses, travel, medical exams, and visa/residence fees. Restricted to nationals of Kenya, Uganda, Rwanda, Zambia, Botswana, Mauritius, Ghana, Senegal, Tanzania, and Madagascar. Fall intake deadline as published: 31 July 2026; Spring intake: 4 December 2026 — confirm the current cycle''s date before relying on it.', '2026-07-31', 'https://www.unic.ac.cy/university-of-nicosia-announces-cyprusaid-scholarship-opportunities-for-students-from-selected-countries/', 'https://www.unic.ac.cy/university-of-nicosia-announces-cyprusaid-scholarship-opportunities-for-students-from-selected-countries/', '2026-08-22'),
    ('72adffb9-40b8-4618-8f3b-11c9c122e0c5', 'International Student Scholarship', 'Frederick University', 'CY', 'c2b136d8-ae59-443a-b8f4-a7d870b4a38f', NULL, 'PARTIAL_TUITION', NULL, 'Up to 25% tuition reduction in the first year based on prior academic performance (high-school certificate for undergrad / Bachelor''s overall grade for postgrad); renewable in later years subject to performance at Frederick. Exact eligibility cutoff and deadline are not itemized on the official page — contact the Admissions Office directly, as the page itself advises. A separate "Women in Engineering" scholarship also exists for female undergraduate applicants to the School of Engineering (not applicable to this graduate seed programme).', NULL, NULL, 'https://www.frederick.ac.cy/en/scholarships-financial-assistance', '2026-08-22'),
    ('049b1ae1-74f7-490f-99ff-7271ba1a3e1c', 'Ernst Mach Grant (for Universities of Applied Sciences)', 'OeAD-GmbH, on behalf of Austria''s Federal Ministry of Education, Science and Research', 'AT', NULL, NULL, 'LIVING_STIPEND', 1300.00, 'Country-wide grant (not tied to one Fachhochschule) for a study visit of 4-10 months, open to undergraduate/graduate students from non-European universities aged 35 or under from developing countries. Both FH Technikum Wien and FHWien der WKW (both Universities of Applied Sciences) qualify. Amount shown is the monthly stipend (EUR 1,300); a travel subsidy of up to EUR 730 is also provided. This is a study-visit grant, not full-degree funding. Deadline for 2026/27: 1 February 2026, 23:59 CET. The official OeAD page blocked automated fetching directly during research — this was confirmed via search-engine-cached content, so double-check the live page before relying on the exact figures.', '2026-02-01', 'https://oead.at/en/study-research-teaching/overview-grants-and-scholarships/ernst-mach-grant/faq-ernst-mach-grant-fachhochschule', 'https://oead.at/en/study-research-teaching/overview-grants-and-scholarships/ernst-mach-grant/faq-ernst-mach-grant-fachhochschule', '2026-08-22'),
    ('4ae6e40d-0405-4215-af5e-a4ee3d636d89', 'Graduate Academic Excellence Scholarship', 'MODUL University Vienna', 'AT', '4510f82d-2eaa-4f40-a152-7ce3957a341c', 'fa3c21a8-b72b-40c9-9494-6615d29b7402', 'PARTIAL_TUITION', NULL, 'Merit-based tuition reduction: 10% for GPA over 80%, 15% over 85%, or 20% over 90% (alternatively, 10-20% based on GMAT score); maximum combined reduction is 25%. Cannot be combined with most other MODUL scholarships. Explicitly lists the MSc in International Tourism Management as an eligible programme. Deadline is rolling/intake-based — the official page states "Apply for Fall 2026 before September 7th" for EU/visa-free applicants.', NULL, NULL, 'https://www.modul.ac.at/study-at-mu/tuition-fees/graduate-excellence-scholarship', '2026-08-22');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('4674259d-ec6e-4909-8939-8631b31de182', 'CY', NULL, 'RESIDENCE_PERMIT', NULL, NULL, ARRAY['admission_letter', 'proof_of_financial_resources', 'health_insurance', 'criminal_record_certificate', 'passport_copy', 'transcripts'], 'https://www.gov.cy/mip-md/en/documents/students/', 'https://home-affairs.ec.europa.eu/policies/migration-and-asylum/eu-immigration-portal/student-cyprus_en', '2026-08-22', 'Temporary Residence Permit (Student), issued by the Civil Registry and Migration Department under EU Directive 2016/801. Non-EU students must register with the Migration Department within 7-10 days of arrival (sources vary between 7 and 10). Permit valid 1 year, renewable annually; renewal should be filed 1 month before expiry. Students may work up to 20 hours/week during term. A EUR 800 minimum bank balance figure appears via a search-cached quote of the Migration Department''s own page, but that page returned HTTP 403 on direct fetch and the EU Immigration Portal (which loaded fully) gives no EUR figure at all, only "sufficient financial resources for living expenses and health insurance" — financial_proof_eur is left NULL rather than stating the unconfirmed EUR 800 figure as fact. Processing time is not published on any official source found — left NULL rather than guessed.'),
    ('ebc03fb9-1c9d-4184-bb4a-67d55b5ea709', 'AT', NULL, 'RESIDENCE_PERMIT', 8670.96, 90, ARRAY['passport', 'admission_letter', 'police_clearance_certificate', 'proof_of_accommodation', 'health_insurance_min_30000_eur', 'proof_of_financial_resources', 'birth_certificate'], 'https://www.migration.gv.at/en/types-of-immigration/temporary-residence/', 'https://www.akbild.ac.at/en/studies/general-study-information/visas-and-residency/non-eu-citizens', '2026-08-22', 'Residence permit "Students" (Aufenthaltsbewilligung - Studierende), for stays over 6 months. Financial proof shown (EUR 8,670.96) is EUR 722.58/month (the under-24 rate, which already includes accommodation costs up to EUR 386.43/month) x 12 months, since funds must be shown up to a year in advance; students 24 or older must show EUR 1,308.39/month instead (EUR 15,700.68/year) - use the higher figure if the applicant is 24+. Permit fee has two conflicting officially-sourced figures: EUR 218 (akbild.ac.at, 2026) vs EUR 120 + EUR 20 personalisation (Austrian Embassy Astana checklist, Feb 2024) - likely different fee stages/dates, not included as a distinct figure here. Processing time of 90 days is the midpoint of the only officially published range, "2 to 4 months" (Austrian Embassy Astana checklist) - treat as approximate, not precise. Automated fetching of migration.gv.at and oead.at was blocked during research; verify directly before final use.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('bc55461b-5911-4e74-9b94-aad855312f97', 'CY', 'Limassol', NULL, 'GENERAL', 900.00, 'https://www.cut.ac.cy/studies/admissions/financial-matters/cost_of_living/', '2026-08-22', 'Official Cyprus University of Technology figure: EUR 800-1,000/month total (tuition excluded), midpoint used here. Breakdown: accommodation EUR 400-600, living expenses EUR 200-400, books/materials EUR 20-80, plus a one-time EUR 300-350 medical exam/insurance cost. This is a Limassol figure; the three universities seeded for Cyprus are Nicosia-based and costs there may differ somewhat.'),
    ('02bfe80a-da46-407f-bf06-cbd10a9d497d', 'AT', NULL, NULL, 'GENERAL', 1300.00, 'https://studyinaustria.at/en/live-and-work/living-costs', '2026-08-22', 'Official OeAD (Austria''s Agency for Education and Internationalisation) figure: approx. EUR 1,300/month (accommodation EUR 450-700, food EUR 300, studies & personal needs EUR 500), underlying data from Statistik Austria''s Studierenden-Sozialerhebung 2025. The source explicitly states this is a guideline, not binding, and that Vienna (where all three Austrian universities seeded here are located) tends to be pricier than smaller cities like Linz or Graz — left as a national figure rather than a possibly-overstated Vienna-specific one.');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('b71fc913-8640-40f9-9bfa-5a1e2ebe6cca', '4fc306dd-4e23-41e4-83e6-9347b1d43525', 'UNIVERSITY_DORM', 'UNIC Residences ("U" building, Premium Studio)', 'Nicosia', 784.33, 1000.00, NULL, ARRAY['furnished', 'studio_unit'], 'https://residences.unic.ac.cy/u/product/premium-studio-7th-floor-single-use/', NULL, 'https://residences.unic.ac.cy/u/product/premium-studio-7th-floor-single-use/', '2026-08-22', 'Official rate is EUR 181/week; converted to a monthly figure here using 52/12 weeks-per-month (a 50-week contract totals EUR 9,050). Distance to campus is not published on the official page (only described as within UNIC''s "urban campus") — left NULL rather than guessed.'),
    ('a3637ba9-68b4-484d-91a1-95308fe3f8f5', 'c2b136d8-ae59-443a-b8f4-a7d870b4a38f', 'UNIVERSITY_DORM', 'Platonos Residences (Frederick University)', 'Nicosia', 693.33, 1000.00, NULL, ARRAY['furnished', 'electricity_included', 'water_included', 'internet_included'], 'https://residences.frederick.ac.cy/pricing', NULL, 'https://residences.frederick.ac.cy/pricing', '2026-08-22', 'Official rate is EUR 160/week for a Standard 1st-floor studio (converted to monthly using 52/12 weeks-per-month); Standard-upper-floor/Premium studios run EUR 170/week and a Special Accessibility unit EUR 175/week. Distance to campus is only described as "walking distance" on the official page — left NULL rather than guessed.'),
    ('d21f376a-3b90-4238-9dd3-420d6d8a98fd', '04a392cb-8e78-40ee-b628-e5a2a4413a81', 'PRIVATE_HALL', 'ERB Cyprialife (officially listed by European University Cyprus)', 'Nicosia', 600.00, NULL, 0.20, ARRAY['furnished'], 'https://euc.ac.cy/en/campus-life/housing/', NULL, 'https://euc.ac.cy/en/campus-life/housing/', '2026-08-22', 'Deposit amount is not published on the official page — left NULL rather than guessed. EUC''s own housing page also officially lists Mirage Residence II (EUR 800-850/month, 250m) and Unihalls Premier (EUR 152-222/week, "near campus") as alternatives.'),
    ('1e34c7b8-85e7-4b46-b9fb-b2aa706e6b5b', 'eec24dc1-e8d5-4c38-9464-667b9e7af527', 'PRIVATE_HALL', 'OeAD-Guesthouse Molkereistrasse', 'Vienna', 666.00, 1332.00, NULL, ARRAY['furnished'], 'https://www.oeadstudenthousing.at/en/accommodation/vienna/', NULL, 'https://www.oeadstudenthousing.at/en/accommodation/vienna/', '2026-08-22', 'Official "Category A" single-room rate, valid from 1 September 2026; deposit shown is the standard 2-months''-rent figure used across OeAD''s Vienna properties. A EUR 35 application fee and EUR 21-per-booked-month booking fee also apply. OeAD''s Vienna-wide listing shows rents from EUR 340 to EUR 1,290/month across its properties. Distance to FH Technikum Wien''s campus is not tied to this specific residence on the official listing — left NULL rather than guessed.'),
    ('5fda504e-61e1-48d1-8ae8-99cffe59f50d', '4510f82d-2eaa-4f40-a152-7ce3957a341c', 'PRIVATE_HALL', 'Viennabase 19 (Base19)', 'Vienna', 500.00, 1000.00, NULL, ARRAY['furnished', 'utilities_included', 'internet_included'], 'https://www.modul.ac.at/study-at-mu/student-accommodation', NULL, 'https://www.modul.ac.at/study-at-mu/student-accommodation', '2026-08-22', 'Official rent range is EUR 400-600/month; midpoint used here. Deposit is officially stated as 2 months'' rent (computed off the midpoint). Distance to campus is given only as "approx. 30 minutes by public transport" on the official page, not a km figure — left NULL rather than guessed.'),
    ('f3a75bb6-2b9e-49da-8b3c-56803b42e840', 'ec3581c8-c157-48c4-b4f4-bab3d21e8a69', 'PRIVATE_HALL', 'OeAD Student Housing (Tigergasse)', 'Vienna', 446.00, NULL, NULL, ARRAY['furnished'], 'https://www.oeadstudenthousing.at/en/accommodation/vienna/', NULL, 'https://www.oeadstudenthousing.at/en/accommodation/vienna/', '2026-08-22', 'Deposit and distance to FHWien der WKW''s campus (Hebbelplatz) are not tied to this specific residence on the official listing — left NULL rather than guessed.');

-- Additional seed university (added 2026-08-22, same batch): Ireland. Ireland
-- uses EUR, so no currency conversion is needed. Every fact below was
-- researched live against an official source (irishimmigration.ie, the
-- Higher Education Authority, or the university's own site) on 2026-08-22.
-- Deposit amounts and exact campus distances that no official source
-- published are left NULL rather than guessed, per this schema's rule.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('69ad599a-2999-446f-82ed-fcc543dc0a28', 'Technological University Dublin (TU Dublin)', 'IE', 'Dublin', 'https://www.tudublin.ie'),
    ('11c7a6b9-afaf-4cc3-aaba-2afc8d8968be', 'Munster Technological University (MTU)', 'IE', 'Cork', 'https://www.mtu.ie'),
    ('81361940-dd7f-4839-ab74-65d4f2d768b8', 'Atlantic Technological University (ATU)', 'IE', 'Galway', 'https://www.atu.ie');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('0744b104-809b-4b21-a63d-e2d465d008e4', '69ad599a-2999-446f-82ed-fcc543dc0a28', 'MSc in Computer Science (Data Science)', 'MASTER', 'Data Science', 15, 'https://www.tudublin.ie/study/postgraduate/courses/computing-data-science/'),
    ('bb266b09-51d0-40f2-9ac7-4434339d092f', '11c7a6b9-afaf-4cc3-aaba-2afc8d8968be', 'MSc in Data Science and Analytics', 'MASTER', 'Data Science and Analytics', 12, 'https://www.mtu.ie/courses/crsdaan9/'),
    ('797f86ec-a14a-45b0-8973-2ab3fa423922', '81361940-dd7f-4839-ab74-65d4f2d768b8', 'MSc in Computing', 'MASTER', 'Computing', 12, 'https://www.atu.ie/courses/master-of-science-computing-galway-full-time');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('dd72aa4a-c50f-4cf6-87ff-f3dbf0ca2eb0', '0744b104-809b-4b21-a63d-e2d465d008e4', NULL, NULL, 'IELTS', '6.5', ARRAY['transcript', 'CV', 'proof_of_english_proficiency', 'application_form'], 'https://www.tudublin.ie/study/postgraduate/courses/computing-data-science/', '2026-08-22', 'Requires a BSc (Hons) in Computer Science, Software Development, Mathematics, or a numerate discipline with significant computing content, at 2.1 Honours or better (2.2 + 2 years'' relevant software development work experience also accepted). IELTS Academic 6.5 overall with no component below 6.0. An interview may be required. No numeric minimum CGPA is separately published (the classification requirement above stands in for it). Non-EU application deadline for Sept 2026 intake: 26 June 2026.'),
    ('035f9f89-de68-428d-a44c-2d28ef92dd1e', 'bb266b09-51d0-40f2-9ac7-4434339d092f', NULL, NULL, 'IELTS', '6.0', ARRAY['CV', 'transcript', 'motivation_statement', 'interview'], 'https://www.mtu.ie/courses/crsdaan9/', '2026-08-22', 'Requires a 2.1 in a Level 8 Honours degree, or a 2.2 Honours plus 3 years'' relevant experience. IELTS 6.0 minimum. Also requires an up-to-date CV, transcripts, a 500-word motivation statement, and an interview. Non-EU application deadline: 31 May (for September entry).'),
    ('9cd70f5e-e52a-48e4-bf31-b870eac36b28', '797f86ec-a14a-45b0-8973-2ab3fa423922', NULL, NULL, 'IELTS', '6.0', ARRAY['transcript', 'CV'], 'https://www.atu.ie/courses/master-of-science-computing-galway-full-time', '2026-08-22', 'Requires an undergraduate Honours Degree in computing (software development)/computer engineering or a higher qualification. IELTS 6.0+ (minimum 5.5 per component) is also satisfied by TOEFL 79+, Duolingo 100+, FCE, or CAE. No numeric minimum CGPA separately published.');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('e93a89b2-cda5-4f33-9841-481fea4e8947', '0744b104-809b-4b21-a63d-e2d465d008e4', 'APPLICATION_FEE', 'INTERNATIONAL', 50.00, 'https://www.tudublin.ie/study/international/how-to-apply/postgraduate-courses/', '2026-08-22', 'Non-refundable. A deposit of the greater of 50% of tuition or EUR 6,000 is separately required to secure a place, with the balance due by 31 January for September-start programmes.'),
    ('419efb57-7486-4557-a3a2-f3f51390a4b8', '0744b104-809b-4b21-a63d-e2d465d008e4', 'TUITION_PER_YEAR', 'INTERNATIONAL', 21750.00, 'https://www.tudublin.ie/media/website/study/international-students/fees-amp-funding/documents/TU-Dublin-International-Postgraduate-Brochure-2026.pdf', '2026-08-22', 'From TU Dublin''s official 2026/27 International Postgraduate Brochure.'),
    ('672f29f3-a048-4248-a4ca-1835a5d300f8', 'bb266b09-51d0-40f2-9ac7-4434339d092f', 'TUITION_PER_YEAR', 'INTERNATIONAL', 15000.00, 'https://www.mtu.ie/international/non-eu/fees/', '2026-08-22', 'This programme sits in MTU''s higher non-EU fee band alongside MSc Cybersecurity/AI (other MTU postgraduate programmes are EUR 13,500/year). No separate application fee is charged; a EUR 1,000 deposit is required from international students upon accepting an offer (not included as its own row, since it is credited toward tuition rather than a distinct fee).'),
    ('004215ba-0707-4e9c-a407-df75e6f8605a', 'bb266b09-51d0-40f2-9ac7-4434339d092f', 'ADMINISTRATIVE_FEE', 'INTERNATIONAL', 7.00, 'https://www.mtu.ie/international/non-eu/fees/', '2026-08-22', 'Union of Students in Ireland (USI) levy, applies to all students regardless of nationality.'),
    ('7269423e-42e9-41d0-9eb5-3d9872cb8bcf', '797f86ec-a14a-45b0-8973-2ab3fa423922', 'APPLICATION_FEE', 'INTERNATIONAL', 30.00, 'https://noneuapply.atu.ie/courses/course/370-msc-master-science-computing', '2026-08-22', 'One-time, via the non-EU applicant portal.'),
    ('480b7c13-6e38-498c-bbab-3e7e54475b6f', '797f86ec-a14a-45b0-8973-2ab3fa423922', 'TUITION_PER_YEAR', 'INTERNATIONAL', 14000.00, 'https://noneuapply.atu.ie/courses/course/370-msc-master-science-computing', '2026-08-22', 'From ATU''s official non-EU applicant portal.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('b95ec00b-3092-486c-8631-a2c2debc65d2', 'Government of Ireland International Education Scholarship (GOI-IES)', 'Higher Education Authority (HEA)', 'IE', NULL, NULL, 'FULL_FUNDING', 10000.00, 'Country-wide scholarship: EUR 10,000 stipend plus a full tuition/registration fee waiver for one year at NFQ level 9 or 10, for students domiciled outside the EU/EEA/Switzerland/UK holding a conditional or final offer at an eligible Irish higher-education institution. IMPORTANT: eligibility is by specific course list, decided per institution, not a blanket "any programme" rule — e.g. ATU''s own eligible-course list includes MSc Computing in DevOps, MSc Cyberpsychology, and several Engineering/Science MSc''s, but explicitly does NOT include the general "MSc in Computing" programme seeded here; TU Dublin''s course-level eligibility list was not confirmed in this research pass. Always check the specific institution''s own GOI-IES page for its current eligible-course list before assuming a given programme qualifies. The 2026 national cycle closed 12 March 2026; the next cycle had not been announced as of the check date.', '2026-03-12', 'https://hea.ie/policy/internationalisation/goi-ies/', 'https://hea.ie/policy/internationalisation/goi-ies/', '2026-08-22'),
    ('dca75cc2-1abc-4a4e-a8e0-5132ad9977c8', 'MTU Non-EU International Student Scholarship', 'Munster Technological University', 'IE', '11c7a6b9-afaf-4cc3-aaba-2afc8d8968be', 'bb266b09-51d0-40f2-9ac7-4434339d092f', 'PARTIAL_TUITION', 3000.00, 'Automatically applied for AY2026/27 to self-funded, non-EU-fee-status applicants to MSc Data Science and Analytics (also covers MSc Cybersecurity and MSc AI) — no separate application needed once the programme offer is made. A EUR 1,000 deposit is due within 4 weeks of the offer to secure the scholarship.', '2026-05-31', NULL, 'https://www.mtu.ie/international/non-eu/fees/', '2026-08-22');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('e428f12a-5da8-4c6f-b894-3053a651496e', 'IE', NULL, 'STUDY_VISA', 10000.00, NULL, ARRAY['passport', 'letter_of_acceptance', 'proof_of_english_proficiency', 'evidence_of_academic_ability', 'proof_of_fee_payment', 'bank_statements_6_months', 'private_medical_insurance', 'police_clearance_certificate'], 'https://www.irishimmigration.ie/coming-to-study-in-ireland/what-are-my-study-visa-options/how-to-apply-for-long-term-study-visa/', 'https://www.irishimmigration.ie/coming-to-study-in-ireland/what-are-my-study-options/a-fee-paying-private-primary-or-secondary-school/information-on-student-finances/', '2026-08-22', 'Long-term "D study visa" (courses starting on/after 1 July 2023, resulting in residence over 8 months), followed by registration for a Stamp 2 immigration permission (Irish Residence Permit). Financial proof shown (EUR 10,000) is the minimum required for one academic year, in addition to that year''s course fees, and is required again for each subsequent year; for courses of 8 months or less the rule is instead EUR 833/month capped at EUR 6,665. Tuition pre-payment rule: if course fees are under EUR 6,000, all fees must be paid before the visa application; if over EUR 6,000, at least EUR 6,000 must be paid first. Credit cards are not accepted as evidence of funds — 6 months of bank statements or an approved education bond are required instead. Visa fee is separate: EUR 60 single-entry / EUR 100 multi-entry, plus a EUR 300 first-time IRP registration fee (not included in the figure above). Processing time is intentionally left NULL: irishimmigration.ie publishes rolling weekly cutoff-date tables rather than one fixed figure, and advises applying up to 3 months before travel — check https://www.irishimmigration.ie/visa-decisions/ for the current cutoff rather than relying on a guessed number.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('e09fab0d-bc7d-4622-8cb6-f311b527d06a', 'IE', 'Dublin', NULL, 'GENERAL', 1817.00, 'https://www.tudublin.ie/media/website/for-students/documents/TU-Dublin-Cost-of-Living-Guide-2026.pdf', '2026-08-22', 'Official TU Dublin Cost of Living Guide 2026/27 gives a range of EUR 1,320-2,314/month for students living away from home in Dublin (midpoint used here), depending on accommodation type: purpose-built student accommodation ~EUR 1,453/month, "digs" (5-day) ~EUR 559, "digs" (7-day) ~EUR 709; plus food ~EUR 205, travel ~EUR 48, books ~EUR 78, clothes/medical ~EUR 43, mobile ~EUR 12.99, social/misc ~EUR 96, and the mandatory Student Contribution Charge ~EUR 278. Students living at home are estimated at EUR 845/month instead. This is a Dublin-specific figure; costs in Cork (MTU) and Galway (ATU) are typically lower.');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('51fea227-0fb4-45cf-9059-0cceab1fb259', '69ad599a-2999-446f-82ed-fcc543dc0a28', 'PRIVATE_HALL', 'Mezzino Student Living (TU Dublin''s official PBSA accommodation partner)', 'Dublin', 1453.00, NULL, NULL, ARRAY['furnished'], 'https://www.tudublin.ie/for-students/student-services-and-support/accommodation--living-in-dublin/campus-commute/international-students/', NULL, 'https://www.tudublin.ie/media/website/for-students/documents/TU-Dublin-Cost-of-Living-Guide-2026.pdf', '2026-08-22', 'TU Dublin has no on-campus halls; this figure is TU Dublin''s own published market-average purpose-built-student-accommodation rate (including service charge), not a single named room type. Cheaper "digs" (room in a family home) options are also available from ~EUR 559-709/month per the same official cost-of-living guide. Deposit amount and distance to campus for a specific room type are not published — left NULL rather than guessed.'),
    ('abeafb36-2943-44c1-9a82-c60ce238aa6e', '11c7a6b9-afaf-4cc3-aaba-2afc8d8968be', 'PRIVATE_HALL', 'Parchment Square (Model Farm Road, adjoining MTU Bishopstown campus)', 'Cork', 489.00, 300.00, NULL, ARRAY['furnished'], 'https://www.parchmentsquarecork.com/student-accommodation-cork/accommodation/rates-2026', NULL, 'https://www.parchmentsquarecork.com/student-accommodation-cork/accommodation/rates-2026', '2026-08-22', 'Cheapest official 2026/27 option: a Shared Room, Shared Bathroom for the ~41-week academic year (21 Aug 2026-4 Jun 2027), EUR 4,600 total including a EUR 900 service charge (averaged to a monthly figure here). A non-refundable EUR 250 booking fee also applies (not included in rent). Adjoins MTU''s Bishopstown campus via a private walkway — exact distance in km is not stated, so left NULL.'),
    ('8115518f-1849-4c44-836b-6c7b661e3c50', '81361940-dd7f-4839-ab74-65d4f2d768b8', 'SHARED_APARTMENT', 'Private rental market (rooms/apartments/"digs") — ATU Galway does not operate its own accommodation', 'Galway', 550.00, NULL, NULL, ARRAY[]::text[], NULL, NULL, 'https://www.atu.ie/student-life/accommodation', '2026-08-22', 'ATU''s own accommodation page states it owns/manages no student housing and is not party to these private tenancy agreements; it instead signposts a EUR 450-650/month private-market range (rooms, apartments, and "digs" — a room in a family home), midpoint used here. Deposit amount and distance to campus are therefore not published for any single property — left NULL rather than guessed. Student villages near ATU Galway typically open bookings in January/February.');

-- Short courses / summer schools batch (added 2026-08-22). Researched live
-- against each already-seeded university's official site. Only currently
-- open, individually-applicable programmes were seeded — several real
-- programmes were found and deliberately excluded: MODUL University Vienna's
-- GoGlobal Summer School is real but its own page states it is "currently
-- postponed until further notice"; European University Cyprus's Summer
-- Science Academy is real but for high-school students, not this app's
-- international-applicant audience; University of Nicosia's and Frederick
-- University's summer-school pages either returned truncated content or a
-- dead link on direct fetch; TU Dublin, MTU, ATU, FH Technikum Wien, and
-- FHWien der WKW had no genuine externally-applicable short course found.
-- Where a fact (admission requirement, fee) was not disclosed on the fetched
-- official page, it is left NULL rather than guessed, per this project's
-- standing rule — see notes on each row below.
INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_weeks, programme_url) VALUES
    ('f228d519-b6be-4e1e-bca3-5f017008d4d8', '87c1705f-1721-4d4b-8936-3230cc128a2e', 'International Summer School — Biosciences, Medicine & Public Health', 'SHORT_COURSE', 'Biosciences, Medicine & Public Health', 3, 'https://www.bmh.manchester.ac.uk/study/summer-schools/'),
    ('669f7532-9a8f-4280-9acd-06e6f69fee41', '22222222-2222-2222-2222-222222222222', 'Summer School: Circularity in the Built Environment', 'SHORT_COURSE', 'Built Environment', NULL, 'https://www.tudelft.nl/en/architecture-and-the-built-environment/study/summerschools'),
    ('8d36381b-c8e5-4adc-94ee-7484956b6553', '11111111-1111-1111-1111-111111111111', 'Munich International Summer University (MISU)', 'SHORT_COURSE', NULL, NULL, 'https://www.lmu.de/en/study/all-degrees-and-programs/programs-for-international-visiting-students/munich-international-summer-university/');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('67771cfa-2fa8-43c7-a94e-53a241e4b1cd', 'f228d519-b6be-4e1e-bca3-5f017008d4d8', 55.00, NULL, 'IELTS', '6.0', NULL, 'https://www.bmh.manchester.ac.uk/study/summer-schools/', '2026-08-22', 'Open to undergraduates registered at another institution "from around the world." Academic minimum is stated as a British Lower Second (55%) or international equivalent, not a raw university GPA scale — recorded here as-is. IELTS 6.0 overall with 6.0 in each component required for non-native English speakers. 2026 dates: Mon 20 Jul - Fri 7 Aug 2026.'),
    ('ab157b3c-23e2-4265-86cc-79131d1770e2', '669f7532-9a8f-4280-9acd-06e6f69fee41', NULL, NULL, NULL, NULL, NULL, 'https://www.tudelft.nl/en/architecture-and-the-built-environment/study/summerschools', '2026-08-22', 'Open to "students from all levels of education (BSc, MSc) as well as PhD researchers and professionals," per the official page. No specific admission requirement, fee, or scholarship is disclosed there — confirm directly before applying. Offered in two 2026 track options: 3 days (26-28 Jun) or 8 days (26 Jun-3 Jul); TU Delft also runs three other named 2026 summer schools on the same page (Sustainable Housing; IDEA League Advancing Decision Support; Planning and Design for the Just City) with dates but no eligibility/fee disclosed either.'),
    ('e27f97e6-6876-44d1-8de7-de7440000c26', '8d36381b-c8e5-4adc-94ee-7484956b6553', NULL, NULL, NULL, NULL, NULL, 'https://www.lmu.de/en/study/all-degrees-and-programs/programs-for-international-visiting-students/munich-international-summer-university/', '2026-08-22', 'Recurring annual program ("500+ students from 80+ countries" per year); open to international bachelor''s/master''s/PhD students and young professionals. Individual academies run 2-10 weeks depending on track, some blended (1 week online + 2 weeks onsite) — no single duration applies, which is why duration_weeks is left NULL on the programme row. Admission requirement and fee are not disclosed on the fetched page (it references a separate "Fees and funding" section whose content could not be retrieved) — confirm directly before applying.');

-- Manchester's summer-school fee is a single all-inclusive package (course +
-- single-room accommodation + airport transfers + activities), not a
-- tuition-only figure — recorded as TUITION_TOTAL with that caveat in notes
-- so it isn't mistaken for a comparable per-year tuition rate. Converted from
-- GBP at the live ECB reference rate (1 EUR = 0.8567 GBP, 2026-08-21, via
-- https://api.frankfurter.dev/v1/latest?from=EUR&to=GBP). No fee row is
-- seeded for the TU Delft or LMU Munich programmes above since neither
-- discloses one.
INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('b1c99501-0df2-44e7-a2c3-90cca985f85e', 'f228d519-b6be-4e1e-bca3-5f017008d4d8', 'TUITION_TOTAL', 'INTERNATIONAL', 3501.81, 'https://www.bmh.manchester.ac.uk/study/summer-schools/', '2026-08-22', 'Original figure: GBP 3,000, converted at 1 EUR = 0.8567 GBP (ECB reference rate, 2026-08-21). This is an all-inclusive package fee covering the course, single-room accommodation, airport transfers, and activities — not a tuition-only figure. No scholarship or fee waiver is mentioned on the official page.');
