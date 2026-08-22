-- Students-Ecosystem Sprint 1 schema. Run through a migration tool in production.

CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(254) UNIQUE NOT NULL,
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
