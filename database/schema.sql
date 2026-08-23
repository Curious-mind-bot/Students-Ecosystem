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

-- Crowdsourced fact submissions ("Live-Verify"). Any logged-in student can
-- suggest a new record or a correction, but nothing here is ever shown to
-- another student until an admin (via the existing ADMIN_API_KEY-gated CMS)
-- approves it — a submission never writes directly to the live content
-- tables. A source_url is mandatory on every submission, independent of
-- whether the target table itself requires one, so every suggestion is
-- traceable to where the submitter says it came from.
CREATE TABLE content_submissions (
    submission_id UUID PRIMARY KEY,
    submitted_by_user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    target_resource VARCHAR(50) NOT NULL
        CHECK (target_resource IN ('universities', 'academic_programs', 'admission_requirements', 'scholarships', 'program_fees', 'living_cost_estimates', 'visa_requirements', 'student_accommodations', 'support_resources')),
    target_record_id UUID,
    proposed_data JSONB NOT NULL,
    source_url TEXT NOT NULL,
    submitter_note TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    review_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX content_submissions_status_idx ON content_submissions(status);
CREATE INDEX content_submissions_submitted_by_user_id_idx ON content_submissions(submitted_by_user_id);

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
    -- Only populated when an official source states a clean, fixed number of
    -- months (not a vague "valid for the duration of your stay" condition,
    -- which can't be reduced to a number without guessing) — left NULL
    -- otherwise, same discipline as every other nullable fact in this table.
    minimum_passport_validity_months SMALLINT CHECK (minimum_passport_validity_months > 0),
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
-- USA / Poland / Portugal batch (added 2026-08-23), continuing toward the
-- requested 32-country / 5-10-universities-each target. Every fact below was
-- researched live against an official source on 2026-08-23. Live ECB rates
-- used: 1 EUR = 1.1699 USD, 1 EUR = 4.3078 PLN (both dated 2026-08-21, via
-- https://api.frankfurter.dev/v1/latest?from=EUR&to=USD,PLN — the most
-- recent ECB reference available). Portugal uses EUR, no conversion needed.
--
-- Notable omissions, deliberately left out rather than guessed:
--  - No US-wide visa_requirements row: every official US government source
--    (travel.state.gov, studyinthestates.dhs.gov, uscis.gov, ice.gov) returned
--    HTTP 403 (anti-bot blocking) on direct fetch, so no F-1 visa figure here
--    could be independently confirmed.
--  - University of Toledo's international scholarship (International Rocket
--    Award, ,000/yr) is confirmed but explicitly for undergraduate
--    freshman/transfer admits, not the seeded MS program — omitted rather
--    than misapplied.
--  - Wichita State's "The Flats" accommodation omitted: the university's own
--    price table shows two conflicting figures for the same room type
--    (8,610 vs 4,305 PLN-equivalent per semester); left out rather than
--    arbitrarily picking one.
--  - UTA and Wichita's own tuition/CoA pages either only break out
--    resident-only line items or blend tuition with living costs with no
--    isolated non-resident tuition-only figure — so program_fees for UTA is
--    omitted entirely (living-cost figures used instead), and only Wichita's
--    own explicitly-labeled (if dated) international tuition estimate is used.
--  - Poznań University of Technology's own dormitory price page is labeled
--    for the 2022/2023 academic year — 4 years stale — omitted rather than
--    presented as current under today's source_checked_on date. Same
--    reasoning applied to Łódź University of Technology's dormitory prices
--    (official price-list documents were unreadable, and third-party
--    aggregator figures are not an official source).
--  - Portugal-wide official cost-of-living data (DGES Observatório) is dated
--    September 2021 — 5 years stale — omitted for the same reason; Lisbon,
--    Porto, and Coimbra therefore have no living_cost_estimates row this
--    batch, only sourced accommodation prices.
--  - ISEP (Instituto Politécnico do Porto): almost nothing could be centrally
--    confirmed for international admissions/fees/scholarships — a recurring
--    pattern also seen with University of Porto/FEUP in an earlier batch —
--    so only its application fee is seeded.
--  - Where a GPA/grade figure uses a different scale than a 0-100 percentage
--    (e.g. Wichita's "3.00 on a 4.0 scale"), it is recorded only in notes,
--    never converted into minimum_cgpa_percentage — that would require an
--    unofficial, invented conversion table.
--  - Poland's D-type visa financial-proof figure: two live official gov.pl
--    consular pages disagree on the 2-month lump-sum figure (1,086 vs 1,270
--    PLN); the better-corroborated recurring monthly figure (701 PLN,
--    consistent on both pages) is used instead, with the disagreement
--    disclosed in notes.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('00661fa1-b3f4-4948-a3af-4b4ad6c0ff53', 'University of Texas at Arlington (UTA)', 'US', 'Arlington', 'https://www.uta.edu'),
    ('67f04ecb-d8cc-4dcd-a027-6f971ec2592b', 'University of Toledo', 'US', 'Toledo', 'https://www.utoledo.edu'),
    ('ae09db90-198e-4dca-ac3e-7502c3ca34ac', 'Wichita State University', 'US', 'Wichita', 'https://www.wichita.edu'),
    ('c6b193eb-d4fe-42f9-9ee2-b05144ae0aae', 'Łódź University of Technology', 'PL', 'Łódź', 'https://p.lodz.pl/en'),
    ('ff47df5a-8c92-481b-a67b-e8f6cb4b13da', 'Poznań University of Technology', 'PL', 'Poznań', 'https://put.poznan.pl/en'),
    ('eca8a5d5-6b6a-48fd-8b5a-0618c0e792a1', 'Vistula University', 'PL', 'Warsaw', 'https://vistula.edu.pl/en'),
    ('713525b1-c2c2-45d8-ba2f-b6da2cbb445e', 'NOVA University Lisbon — NOVA School of Science and Technology', 'PT', 'Caparica/Lisbon', 'https://www.fct.unl.pt/en'),
    ('30607719-9f6f-48e3-bfa5-07d4ec2fe1b2', 'Instituto Politécnico do Porto — ISEP', 'PT', 'Porto', 'https://www.isep.ipp.pt'),
    ('3460c687-54a1-438c-a273-5b41f24016cf', 'University of Coimbra', 'PT', 'Coimbra', 'https://www.uc.pt');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('eb0acdeb-168f-4c80-ab55-cc3ce6319179', '00661fa1-b3f4-4948-a3af-4b4ad6c0ff53', 'M.S. in Computer Science', 'MASTER', 'Computer Science', NULL, 'https://www.uta.edu/academics/programs/computer-science-ms'),
    ('cf385826-83b4-40dc-b3c6-38a20f5c90ad', '67f04ecb-d8cc-4dcd-a027-6f971ec2592b', 'M.S. in Computer Science and Engineering', 'MASTER', 'Computer Science and Engineering', NULL, 'https://www.utoledo.edu/programs/grad/computer-science-engineering/'),
    ('291f02b5-2c9f-461c-93ed-33ed035ad594', 'ae09db90-198e-4dca-ac3e-7502c3ca34ac', 'M.S. in Computer Science', 'MASTER', 'Computer Science', NULL, 'https://www.wichita.edu/academics/majors/computer_science_ms_184.php'),
    ('0f8a7d33-fec5-4649-85c6-b8b9dc9a9a39', 'c6b193eb-d4fe-42f9-9ee2-b05144ae0aae', 'Computer Science and Information Technology (M.Sc.)', 'MASTER', 'Computer Science', 24, 'https://apply.p.lodz.pl/en/kierunek/second-cycle-computer-science-and-information-technology'),
    ('6e259c57-d663-4cff-aeb8-00c195843c14', 'ff47df5a-8c92-481b-a67b-e8f6cb4b13da', 'Computing (M.Sc.)', 'MASTER', 'Computer Science', 18, 'https://www.put.poznan.pl/en/kierunek/informatykacomputing'),
    ('92c160bb-cec9-4424-b045-45726a5f7e19', 'eca8a5d5-6b6a-48fd-8b5a-0618c0e792a1', 'Computer Engineering (M.Sc.)', 'MASTER', 'Computer Engineering', 18, 'https://vistula.edu.pl/en/major/computer-engineering_ii'),
    ('1943a529-e0a9-4541-b04a-78863d40b144', '713525b1-c2c2-45d8-ba2f-b6da2cbb445e', 'Master in Computer Science and Engineering', 'MASTER', 'Computer Science and Engineering', 24, 'https://www.fct.unl.pt/en/education/course/masters-computer-science-and-engineering'),
    ('c7e42589-8f6a-412a-b8eb-55d9b28b20a9', '30607719-9f6f-48e3-bfa5-07d4ec2fe1b2', 'Master in Informatics Engineering', 'MASTER', 'Informatics Engineering', NULL, 'https://www.isep.ipp.pt/files/isep_m_engenharia_informatica.pdf'),
    ('579d57de-4a99-487f-a1b2-fec47434ff36', '3460c687-54a1-438c-a273-5b41f24016cf', 'Master in Informatics Engineering (MEI)', 'MASTER', 'Informatics Engineering', 24, 'https://apps.uc.pt/courses/EN/programme/5041/2026-2027');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('f5e4ec91-8548-4a7f-8914-5e1dd839c5ae', 'eb0acdeb-168f-4c80-ab55-cc3ce6319179', NULL, NULL, 'TOEFL', '79', ARRAY['transcript','english_test_score','financial_support_documents'], 'https://www.uta.edu/admissions/apply/international-graduate', '2026-08-23', 'Alternative English tests also accepted: IELTS 6.5, Duolingo 100. No numeric minimum GPA is published at the general-admissions level (catalog states only "a satisfactory grade-point average"). Foreign transcripts subject to a separate  FCSA credential-evaluation fee. Exact application fee amount not published on any directly-fetched page.'),
    ('d88be701-136c-4441-bcbf-3cab7e1ca14c', 'cf385826-83b4-40dc-b3c6-38a20f5c90ad', NULL, NULL, 'TOEFL', '80', ARRAY['transcript','recommendation_letters','english_test_score','resume'], 'https://www.utoledo.edu/graduate/international/english-language-proficiency.html', '2026-08-23', 'Alternative English tests also accepted: IELTS 6.5, PTE 58, Duolingo 110, Cambridge English 176 (scores expire after 2 years). A completed degree with 2.7 GPA (4.0 scale) from a regionally-accredited English-medium institution exempts from the English test — this is an English-test waiver threshold, not the program''s general admission GPA, which is not separately published ("might differ per program" per the general graduate admissions page).'),
    ('c0c21ead-4070-43e5-a79e-1c0f429623cc', '291f02b5-2c9f-461c-93ed-33ed035ad594', NULL, NULL, 'TOEFL', '79', ARRAY['transcript','degree_certification','financial_certification','english_test_score'], 'https://www.wichita.edu/academics/majors/computer_science_ms_184.php', '2026-08-23', 'Minimum GPA: 3.00 on a 4.0 scale (or recognized international equivalent) — not converted to a 0-100 percentage here since that would require an unofficial conversion. Alternative English tests: IELTS 6.5, PTE 58, Duolingo 115 (TOEFL Essentials explicitly not accepted). Application fee is tiered by deadline:  (priority),  (secondary),  (late).'),
    ('97ca9c06-75c3-4de2-ba24-7440bd16c9da', '0f8a7d33-fec5-4649-85c6-b8b9dc9a9a39', NULL, NULL, 'CEFR', 'B2', ARRAY['diploma_apostilled','transcript','nawa_recognition_statement','language_certificate_b2','passport'], 'https://apply.p.lodz.pl/en/enrollment/enroll/required-documents', '2026-08-23', 'No specific TOEFL/IELTS numeric score or minimum GPA is published — only a general "B2 level" English requirement. NAWA Individual Recognition Statement confirms eligibility for Master''s-level study. Programme duration stated as "4 semesters" (converted to 24 months here).'),
    ('17cdf719-734b-4d3d-a068-414aa5c5ba33', '6e259c57-d663-4cff-aeb8-00c195843c14', NULL, NULL, 'CEFR', 'B2', ARRAY['diploma_translated','transcript','gpa_certificate','nawa_recognition_statement','language_certificate_b2','passport'], 'https://put.poznan.pl/en/admission-for-international/second-cycle/required-documents', '2026-08-23', 'A GPA certificate must be submitted but no numeric pass threshold is published. English requirement is "B2 or higher" with no specific test/score named. NAWA diploma-recognition statement waived for EU/OECD/EFTA diplomas. Programme duration stated as "3 semesters" (converted to 18 months here).'),
    ('4f97a2b2-33b3-40bf-9245-fb0a849c7949', '92c160bb-cec9-4424-b045-45726a5f7e19', 60.00, NULL, 'CEFR', 'B2', ARRAY['diploma','transcript','sworn_translation','language_certificate_b2','medical_certificate','passport'], 'https://vistula.edu.pl/en/faq/foreign-student', '2026-08-23', 'Minimum GPA is explicitly published as "60% from previous studies" — a genuine percentage figure, recorded as-is. English proficiency at B2 level via TOEFL, IELTS, or TOEIC (Duolingo explicitly not accepted); no specific numeric score published for any of the three tests. Programme duration explicitly stated as "1.5 years."'),
    ('07f0cdf0-3a00-49eb-af51-0f28fc52ea13', '1943a529-e0a9-4541-b04a-78863d40b144', NULL, NULL, NULL, NULL, ARRAY['foreign_id','international_student_status_declaration','secondary_education_certificate','higher_ed_access_exam_certificate','language_proficiency_proof'], 'https://www.fct.unl.pt/en/international/international-student-admission', '2026-08-23', 'Selection is based on "degree relevance and final classification" — no numeric minimum GPA published. Required language proficiency level is stated only as "as indicated in the selection notice" — no specific test/score confirmed via a directly-fetched page. Programme duration explicitly stated as "2 years / 120 ECTS."'),
    ('ecae7a24-6af6-489e-bf76-c90e4257c9f9', 'c7e42589-8f6a-412a-b8eb-55d9b28b20a9', NULL, NULL, NULL, NULL, NULL, 'https://www.isep.ipp.pt/Page/ViewPage/INTERNATIONAL', '2026-08-23', 'ISEP''s international admissions page distinguishes only "Full Degree Students" vs "Mobility Students" and does not publish minimum grades, a language-test requirement, or a document checklist for Master''s applicants — points instead to Portugal''s national immigration portal. No admission-requirement facts could be confirmed via a directly-fetched official page.'),
    ('c521f7a9-2356-4fff-ba3b-52a6c6fb3822', '579d57de-4a99-487f-a1b2-fec47434ff36', NULL, NULL, NULL, NULL, ARRAY['bachelor_transcript','degree_certificate'], 'https://apps.uc.pt/courses/en/course/5041', '2026-08-23', 'Applicants need a Bachelor''s in Computer/Informatics/Systems/Communications/Electrical Engineering (Bologna-organized) or a recognized foreign equivalent, evaluated case-by-case by the Department''s Scientific Committee — no numeric minimum GPA published. An English requirement of IELTS 6.5 / TOEFL 92 is widely and consistently cited but could not be confirmed on a directly-fetched official page (the specific international-applicants page returned a 403 error both directly and via proxy), so it is not recorded as a confirmed fact here.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('043df961-ab0d-4851-8563-2bde2b30d86f', 'Tuition Assistance for Mexican Students (TAMS/PASE)', 'University of Texas at Arlington', 'US', '00661fa1-b3f4-4948-a3af-4b4ad6c0ff53', 'eb0acdeb-168f-4c80-ab55-cc3ce6319179', 'PARTIAL_TUITION', NULL, 'Waives the non-resident portion of tuition for students who are Mexican citizens/residents, based on demonstrated financial need and competitive selection. No specific dollar amount is published (the waiver value depends on the current non-resident/resident tuition differential). Narrow eligibility — Mexican nationality/residency required, not open to international students generally.', NULL, NULL, 'https://www.uta.edu/student-affairs/oie/isss/scholarships-loans', '2026-08-23'),
    ('c03e4061-6dea-4ca4-80ff-cbf921df87f9', 'Global Select Scholarship', 'Wichita State University', 'US', 'ae09db90-198e-4dca-ac3e-7502c3ca34ac', '291f02b5-2c9f-461c-93ed-33ed035ad594', 'PARTIAL_TUITION', 5128.64, 'Original figure: USD 6,000/academic year (up to USD 24,000 over the full program), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). Eligibility: international (non-immigrant visa status) student with a GPA of 3.3 (out of 4.0) or recognized international equivalent, enrolled in at least 9 credit hours/semester.', NULL, 'https://www.wichita.edu/globalselect', 'https://www.wichita.edu/globalselect', '2026-08-23'),
    ('a3bbb38c-cb4d-4574-89cd-3811e4dbb123', 'Poland My First Choice (NAWA)', 'Polish National Agency for Academic Exchange (NAWA)', 'PL', NULL, NULL, 'FULL_FUNDING', NULL, 'A Poland-wide, NAWA-administered scholarship program offering full tuition exemption plus a monthly stipend to eligible international students at participating Polish universities. The exact monthly stipend amount (widely but unofficially cited as PLN 2,000/month) could not be confirmed via a directly-fetched official NAWA page (nawa.gov.pl consistently rendered as navigation-only content across five attempted URLs) — amount left unconfirmed rather than reported as fact. Confirmed only via Łódź University of Technology''s own page, which lists this programme (along with the Stefan Banach and General Anders NAWA programmes) among those it participates in — check nawa.gov.pl directly and the specific university''s current partner status before relying on this.', NULL, NULL, 'https://apply.p.lodz.pl/en/enrollment/enroll/fees-and-scholarships', '2026-08-23'),
    ('fd4038b0-a215-4164-82e6-912dd6ad7e00', 'Rector''s Scholarship', 'Vistula University', 'PL', 'eca8a5d5-6b6a-48fd-8b5a-0618c0e792a1', '92c160bb-cec9-4424-b045-45726a5f7e19', 'LIVING_STIPEND', 104.46, 'Original figure: PLN 450 per month, converted at 1 EUR = 4.3078 PLN (ECB reference rate, 2026-08-21) — this is a monthly amount, not an annual total. Eligibility: GPA of 4.3+ on Poland''s 2-5 academic grading scale, open to all foreign students (unlike Vistula''s state-budget-funded Social/Disability/Minister''s scholarships, which are largely restricted to students with Polish residency/citizenship ties).', NULL, 'https://vistula.edu.pl/en/candidate/how-to-reduce-tuition-fees', 'https://vistula.edu.pl/en/candidate/how-to-reduce-tuition-fees', '2026-08-23'),
    ('8356c1e9-0b84-473e-9dad-f6e7f65d4094', 'Santander/NOVA FCT Merit Scholarships', 'NOVA School of Science and Technology', 'PT', '713525b1-c2c2-45d8-ba2f-b6da2cbb445e', NULL, 'PARTIAL_TUITION', 500.00, '10 awards per year of EUR 500 each, weighted 70% academic performance / 30% socio-economic need. Whether non-EU international students specifically qualify is not stated on the official page — could not be confirmed either way.', NULL, 'https://www.fct.unl.pt/en/santander/nova-fct-merit-scholarships', 'https://www.fct.unl.pt/en/santander/nova-fct-merit-scholarships', '2026-08-23'),
    ('88f47155-9d01-460b-8dbd-819c02a5c637', 'Merit Scholarships and Prizes for International Students', 'University of Coimbra', 'PT', '3460c687-54a1-438c-a273-5b41f24016cf', NULL, 'PARTIAL_TUITION', 1500.00, 'Per Regulamento n.º 346/2025: tuition discounts of EUR 1,000-2,000 based on admission grade (EUR 1,500 midpoint recorded here); full tuition exemption available for an international-access-exam admission score of 180+ (e.g. IB/A-Level/Gaokao/ENEM) combined with demonstrated financial need. The regulation number and figures are well-corroborated by independent Portuguese press coverage, but the primary UC scholarship pages (uc.pt/candidatos-internacionais/bolsas and uc.pt/academicos/premios_bolsas/bolsas_estudos_graduados) returned a 403 error on direct and proxied fetch, so this is not a page I personally read — flagged as partially-confirmed.', NULL, NULL, 'https://www.uc.pt', '2026-08-23');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('b824bb7b-1d72-4cd6-8c30-0659db2f7f9f', 'cf385826-83b4-40dc-b3c6-38a20f5c90ad', 'APPLICATION_FEE', 'INTERNATIONAL', 64.11, 'https://www.utoledo.edu/engineering/graduate-studies/prospectivestudents/admissioninformation.html', '2026-08-23', 'Original figure: USD 75 (domestic applicants pay USD 45), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21).'),
    ('bcae6b40-4271-4991-aeb8-c1f341672f14', 'cf385826-83b4-40dc-b3c6-38a20f5c90ad', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 12950.85, 'https://www.utoledo.edu/offices/treasurer/tuition/graduate/', '2026-08-23', 'Original figure: USD 15,151.20 for the Fall/Spring plateau rate (12-15 credit hours, 2026-27), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). Based on the standard graduate per-credit rate of USD 1,203.05 + USD 59.55 general fee; add USD 50/semester international student services fee and USD 619-1,581/term health insurance separately (not included here).'),
    ('768a8e3d-9dec-4c6b-bd69-f42ef3f9dbb7', '291f02b5-2c9f-461c-93ed-33ed035ad594', 'APPLICATION_FEE', 'INTERNATIONAL', 64.11, 'https://www.wichita.edu/admissions/graduate/checklist-international.php', '2026-08-23', 'Original figure: USD 75 for the priority deadline (Mar 1 fall / Aug 31 spring), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). Later deadlines cost more: USD 135 (secondary) or USD 175 (late submission).'),
    ('19adabfc-f00c-4e01-b8b4-c5421ca82fd7', '291f02b5-2c9f-461c-93ed-33ed035ad594', 'TUITION_PER_YEAR', 'INTERNATIONAL', 17180.96, 'https://www.wichita.edu/admissions/graduate/tuition-international.php', '2026-08-23', 'Original figure: USD 20,100 for a 9-month academic year (18 credit hours), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). A 12-month/24-credit-hour estimate of USD 26,500 also exists on the same page. The source page itself explicitly labels both figures as estimates "subject to change" and a current 2026-27-specific international per-credit table could not be located — treat as approximate, not precisely current-year confirmed.'),
    ('d663d618-8b1a-4ab4-86d4-6990e3982d8d', '0f8a7d33-fec5-4649-85c6-b8b9dc9a9a39', 'APPLICATION_FEE', 'INTERNATIONAL', 19.73, 'https://apply.p.lodz.pl/en/enrollment/enroll/fees-and-scholarships', '2026-08-23', 'Original figure: PLN 85 per program (2026/2027 academic year), converted at 1 EUR = 4.3078 PLN (ECB reference rate, 2026-08-21).'),
    ('e8e57756-7ab6-49ed-abd1-1bb0e324cee4', '0f8a7d33-fec5-4649-85c6-b8b9dc9a9a39', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 1973.16, 'https://apply.p.lodz.pl/en/enrollment/enroll/fees-and-scholarships', '2026-08-23', 'Original figure: midpoint of PLN 8,000-9,000 per semester, the published range for English-taught ("IFE") second-cycle programmes generally — not isolated to this specific programme. Converted at 1 EUR = 4.3078 PLN (ECB reference rate, 2026-08-21).'),
    ('a4dce676-1795-4f4b-b2cb-081622683d60', '6e259c57-d663-4cff-aeb8-00c195843c14', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 2950.00, 'https://put.poznan.pl/en/admission-for-international/second-cycle/fees', '2026-08-23', 'Official figure for the Computing programme group: EUR 2,950 for the FIRST semester only (no conversion needed, published directly in EUR). Every subsequent semester is billed separately in PLN, not EUR: PLN 10,500/semester (approx. EUR 2,437.44 at 1 EUR = 4.3078 PLN, ECB reference rate 2026-08-21) — this row represents only the first-semester rate; confirm the full multi-semester cost structure on the official page directly.'),
    ('03020073-81b6-4be6-ab1b-e93c82612c46', '92c160bb-cec9-4424-b045-45726a5f7e19', 'TUITION_PER_YEAR', 'INTERNATIONAL', 4000.00, 'https://vistula.edu.pl/en/major/computer-engineering_ii', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 4,000/year for non-preferential international students. A lower preferential rate of EUR 2,900/year applies to EU nationals and select non-EU nationalities per the same page. A separate entry/registration fee (PLN 400 or EUR 150-250) is described inconsistently across two official Vistula pages (one states an upfront fee, the FAQ page states "no registration fee is required upfront... invoice sent after document review") — this discrepancy is not resolved and the registration fee is deliberately omitted as its own row.'),
    ('08363145-dfae-415f-b0ef-b0e71f8cca37', '1943a529-e0a9-4541-b04a-78863d40b144', 'APPLICATION_FEE', 'INTERNATIONAL', 70.00, 'https://www.fct.unl.pt/en/international/international-student-admission', '2026-08-23', 'Official figure, published directly in EUR: EUR 70 non-refundable application fee. A separate EUR 35 enrollment fee, EUR 1.40 school insurance, and a EUR 100 non-refundable placement/acceptance fee (deducted from tuition) also apply per the official pages, but are not recorded as separate fee rows here.'),
    ('1cf7f516-745a-40ea-93bc-06f23ae21933', '1943a529-e0a9-4541-b04a-78863d40b144', 'TUITION_PER_YEAR', 'INTERNATIONAL', 7000.00, 'https://www.fct.unl.pt/en/international/international-student-admission', '2026-08-23', 'Official figure, published directly in EUR: EUR 7,000/year, same rate for all nationalities (no separate EU/non-EU tier). A 10-installment payment plan is available per the same page.'),
    ('779a6bb7-ef89-4439-9364-c1868ec81a6b', 'c7e42589-8f6a-412a-b8eb-55d9b28b20a9', 'APPLICATION_FEE', 'INTERNATIONAL', 60.00, 'https://www.isep.ipp.pt/files/Regulamentos_DAC/Outros/Despacho_PPORTO-P-043-2025_Regulamento_Propinas.pdf', '2026-08-23', 'Official figure from the P.PORTO fee regulation (Despacho PPORTO-P-043-2025): EUR 60 Master''s application fee (plus a EUR 25 registration/enrollment fee and EUR 53 school insurance, not recorded as separate rows). This regulation does not distinguish national vs. international tuition; a commonly cited figure of "EUR 4,500/year international vs EUR 950/year national" tuition appears repeatedly on third-party aggregator sites but could not be confirmed on any ISEP/P.PORTO primary page or PDF — deliberately omitted rather than reported as fact.'),
    ('26ee5423-d7a5-4416-9bf5-acfcf8940df6', '579d57de-4a99-487f-a1b2-fec47434ff36', 'APPLICATION_FEE', 'INTERNATIONAL', 50.00, 'https://www.uc.pt', '2026-08-23', 'Figure sourced from Regulamento n.º 346/2025 (Diário da República), corroborated by multiple independent Portuguese press outlets citing the same regulation number and figure, but the primary Diário da República PDF could not be text-parsed by available tooling and UC''s own propina/fee portal page returned a 403 error on direct fetch — flagged as well-corroborated but not personally read on a primary official page.'),
    ('59a1fca8-e6ff-4842-985e-eb474c72f91e', '579d57de-4a99-487f-a1b2-fec47434ff36', 'TUITION_PER_YEAR', 'INTERNATIONAL', 7000.00, 'https://www.uc.pt', '2026-08-23', 'Figure sourced from Regulamento n.º 346/2025 (Diário da República), applying to bachelor''s, integrated master''s, and continuity master''s international students alike; corroborated by independent Portuguese press coverage citing the same regulation, but the primary PDF/portal page could not be directly read by this tooling (binary/OCR failure and a 403 error respectively) — flagged as well-corroborated but not personally read on a primary official page.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('519d77e4-3f5b-4511-8319-e3f871732c07', 'US', 'Arlington', '00661fa1-b3f4-4948-a3af-4b4ad6c0ff53', 'GENERAL', 1442.00, 'https://www.uta.edu/administration/fao/average-cost', '2026-08-23', 'Original figure: USD 1,687/month (Housing & Meals, off-campus, from the 2026-27 Cost of Attendance table, USD 15,180 for the 9-month academic year), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21).'),
    ('9e3149a0-e70f-4ded-a6a6-5f563ee24b06', 'US', 'Wichita', 'ae09db90-198e-4dca-ac3e-7502c3ca34ac', 'GENERAL', 1274.47, 'https://www.wichita.edu/administration/financial_aid/coa_grad.php', '2026-08-23', 'Original figure: USD 1,491/month (Food & Housing, off-campus, from the 2026-27 Cost of Attendance table, USD 13,420/academic year at 12 credit hours/semester), converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21).'),
    ('95edcf8f-b2c6-4efb-8e0b-9992505bc06a', 'PL', 'Łódź', NULL, 'GENERAL', 1172.29, 'https://www.uni.lodz.pl/en/international-researchers/cost-of-living', '2026-08-23', 'Original figure: midpoint of PLN 3,600-6,500/month (single-person, all-in estimate), converted at 1 EUR = 4.3078 PLN (ECB reference rate, 2026-08-21). Source is University of Łódź (a different institution in the same city), used because Łódź University of Technology does not publish its own city cost-of-living estimate.'),
    ('e98e0963-7e8c-46bb-b3ab-1f98d5eb2218', 'PL', 'Poznań', 'ff47df5a-8c92-481b-a67b-e8f6cb4b13da', 'GENERAL', 400.00, 'https://put.poznan.pl/en/node/6088', '2026-08-23', 'Official figure, published directly in EUR: midpoint of the university''s own stated "EUR 350 to EUR 450" monthly range. Itemized PLN figures on the same page: dormitory double room 554 PLN, triple 373 PLN, private-flat room ~800 PLN, transport ~50 PLN, food ~500 PLN, health insurance ~46 PLN, entertainment ~250 PLN.'),
    ('ab1b0cce-fb93-4788-ad64-9dbae0fe2394', 'PL', 'Warsaw', NULL, 'GENERAL', 928.55, 'https://welcome.uw.edu.pl/before-you-arrive/living-costs/', '2026-08-23', 'Original figure: midpoint of PLN 3,000-5,000/month disposable-income guidance, converted at 1 EUR = 4.3078 PLN (ECB reference rate, 2026-08-21). Source is University of Warsaw''s official international-student page (a different institution in the same city, used because Vistula''s own city-cost source, en.um.warszawa.pl/cost-of-studying, returned a 403 error on direct fetch). Same page states dorm/shared-flat living specifically at PLN 1,600-2,500/month.');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('722575ed-c6b1-4ce0-8f4a-2fe9299faffc', 'PL', NULL, 'STUDY_VISA', 162.73, 15, ARRAY['passport','acceptance_letter','proof_of_financial_resources','travel_medical_insurance_min_30000_eur','accommodation_proof','biometric_photos'], 'https://www.gov.pl/web/usa-en/d-type-national-visa', 'https://www.gov.pl/web/usa-en/d-type-national-visa', '2026-08-23', 'Officially named the "D-type national visa" (Wiza krajowa); STUDY_VISA is the closest schema category. financial_proof_eur is derived from PLN 701/month (converted at 1 EUR = 4.3078 PLN, ECB reference rate 2026-08-21) — the ongoing monthly minimum for a single/self-employed person, which is consistently stated on two separate live official gov.pl consular pages. Those same two pages DISAGREE on the initial 2-month lump-sum figure (PLN 1,086 vs PLN 1,270) — that disputed figure is deliberately not used here. Minimum EUR 30,000 travel/medical insurance coverage required. Processing time (15 working days standard, up to 30 if extended examination needed, 3 if expedited) and the visa fee (USD 235) are both taken from a US-consulate-specific instance of this gov.pl page and may vary by consulate.'),
    ('4f70d65e-5389-4a2a-bf54-e2f96fceea29', 'PT', NULL, 'STUDY_VISA', NULL, 60, ARRAY['national_visa_application_form','passport_valid_3_months_beyond_return','passport_photos','police_clearance_certificate_apostilled','travel_medical_insurance'], 'https://www.vfsglobal.com/one-pager/portugal/usa/english/', 'https://washingtondc.embaixadaportugal.mne.gov.pt/en/consular-services/visa-information', '2026-08-23', 'Officially the "Residency Visa for Research, Study, Students Exchange, Internship and Voluntary Work" (Type D/D4). Both the Portuguese Embassy Washington DC page and the VFS Global page state a financial-proof requirement exists ("as defined by decree of the competent government members") but do not publish a specific EUR figure — left NULL rather than using the ~EUR 760-920/month figure that only appears on unofficial third-party aggregator sites. After arrival, students transition to a residence permit ("Autorização de Residência Emitida a Estudantes do Ensino Superior," Art. 91), issued by AIMA, standard 2-year duration or program length if shorter, renewable — source: https://aima.gov.pt/pt/estudar/autorizacao-de-residencia-emitida-a-estudantes-do-ensino-superior-art-o-91 (read via a text-rendering proxy of this exact official URL after a direct TLS fetch failure).');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('357ecec1-dbba-4d1b-b6b5-eb4a9ef499d3', '00661fa1-b3f4-4948-a3af-4b4ad6c0ff53', 'UNIVERSITY_DORM', 'UTA Housing & Residence Life — Meadow Run', 'Arlington', 1000.09, NULL, NULL, ARRAY['furnished'], 'https://www.uta.edu/campus-ops/housing/apartments/meadow-run', NULL, 'https://www.uta.edu/campus-ops/housing/apartments/meadow-run', '2026-08-23', 'Original figure: USD 1,170/month for a 1BR/1BA (651 sq ft) unit, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). A 2BR/2BA (981 sq ft) unit is also available at USD 1,655/month. The official page states only "must be UTA students" without explicitly confirming graduate-student eligibility for this specific community.'),
    ('7b0381ec-3dc8-44a1-8bde-a695ad174042', 'eca8a5d5-6b6a-48fd-8b5a-0618c0e792a1', 'PRIVATE_HALL', 'Vistula University-affiliated student residence', 'Warsaw', 210.00, NULL, NULL, ARRAY[]::text[], NULL, NULL, 'https://vistula.edu.pl/en/faq/foreign-student', '2026-08-23', 'Official figure, published directly in EUR: EUR 210/month, per Vistula''s own FAQ page. A specific residence name ("Mangalia 3B") is cited by a Vistula news page, but that specific page returned a 403 error on direct fetch, so the building name/address is not independently confirmed — only the FAQ page''s cost figure is.'),
    ('9ce77181-8d8f-4a42-9bfe-3e4443907a5b', '713525b1-c2c2-45d8-ba2f-b6da2cbb445e', 'UNIVERSITY_DORM', 'SASNOVA — Residência do Lumiar', 'Lisbon', 250.00, NULL, NULL, ARRAY['shared_bathroom'], 'https://sas.unl.pt/wp-content/uploads/2025/05/Precario-RL-2024_2025.pdf', 'alojamento@unl.pt', 'https://sas.unl.pt/wp-content/uploads/2025/05/Precario-RL-2024_2025.pdf', '2026-08-23', 'Official 2024/2025 price table (read via a text-rendering proxy of this exact official PDF URL): double room with shared WC EUR 250/month (recorded here); single room with shared WC EUR 320/month; single room with private WC EUR 450/month; DGES-scholarship-holder rate EUR 89.12/month.'),
    ('d058cfb8-cf26-4dc1-bdf5-4f0d6fa70953', '3460c687-54a1-438c-a273-5b41f24016cf', 'UNIVERSITY_DORM', 'SASUC (Serviços de Ação Social da Universidade de Coimbra)', 'Coimbra', 142.00, NULL, NULL, ARRAY['utilities_included','internet_included','weekly_linen_included'], 'https://www.uc.pt/site/assets/files/1761059/tabelamensalidadesru_2024-2025.pdf', NULL, 'https://www.uc.pt/site/assets/files/1761059/tabelamensalidadesru_2024-2025.pdf', '2026-08-23', 'Official 2024/2025 price table (read via a text-rendering proxy of this exact official PDF URL): single room, non-scholarship rate EUR 142/month (recorded here); scholarship-holder rate EUR 89.12/month; double room EUR 207 (non-scholarship)/EUR 163 (scholarship-holder); apartments (T0/T1/T2) EUR 320-587/month. A EUR 5/month insurance fee may apply additionally. Reserved for international, licenciatura, and integrated-master''s students under the Estatuto do Estudante Internacional.');
-- Hungary batch (added 2026-08-23), continuing toward the 32-country target.
-- Every fact below was researched live against an official source on
-- 2026-08-23. Live ECB rates used: 1 EUR = 1.1699 USD, 1 EUR = 362.78 HUF
-- (both dated 2026-08-21, via https://api.frankfurter.dev/v1/latest, the
-- most recent ECB reference available). Note: BME publishes its own fees
-- and living-cost figures directly in EUR (not HUF) — used as-is, no
-- conversion needed. Debrecen and Pécs publish their fees in USD (not HUF)
-- — also used as-is per their own official pages, only converted to EUR.
--
-- Deliberate omissions:
--  - BME's cost-of-living page gives only itemized component ranges
--    (accommodation "from EUR 250", food "EUR 250-500", utilities
--    "EUR 80-120") with no official single total figure — summing these
--    myself would introduce an unstated assumption, so no living_cost_estimate
--    or student_accommodations row is seeded for BME this batch.
--  - University of Debrecen's confirmed HUF 40,000/month dormitory rate is
--    explicitly stated as being for scholarship-holders only, not
--    fee-paying international students — seeded anyway since it's a real,
--    sourced figure, but the eligibility caveat is disclosed prominently.
--  - No HUF financial-proof figure exists on Hungary's official immigration
--    page (oif.gov.hu) — left NULL rather than using third-party estimates.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('bdb7e39d-4840-48bf-821a-ee07285b9d98', 'Budapest University of Technology and Economics (BME)', 'HU', 'Budapest', 'https://www.bme.hu'),
    ('2ff63c1f-ab53-482c-937c-11752fa04c1d', 'University of Debrecen', 'HU', 'Debrecen', 'https://unideb.hu'),
    ('fd1bc097-c8ca-45b5-b753-63c253957290', 'University of Pécs (PTE)', 'HU', 'Pécs', 'https://pte.hu');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('10475328-876a-4051-81ea-84258bc90bde', 'bdb7e39d-4840-48bf-821a-ee07285b9d98', 'Computer Science Engineer MSc', 'MASTER', 'Computer Science Engineering', 24, 'https://xplore.bme.hu/programme/computer-science-engineer-msc/'),
    ('92428a65-10a3-4f0a-9939-76745f026db3', '2ff63c1f-ab53-482c-937c-11752fa04c1d', 'Computer Science Engineering MSc', 'MASTER', 'Computer Science Engineering', 24, 'https://edu.unideb.hu/p/computer-science-engineering-msc'),
    ('269fb49a-3071-4e99-b35f-103e209b2bb4', 'fd1bc097-c8ca-45b5-b753-63c253957290', 'MSc Computer Science Engineering', 'MASTER', 'Computer Science Engineering', 24, 'https://international.pte.hu/study-programs/msc-computer-science-engineering');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('a643c984-30be-4f38-af9d-3a00245ea154', '10475328-876a-4051-81ea-84258bc90bde', 70.00, NULL, 'IELTS', '5.0', ARRAY['cv','passport','bachelor_certificate','transcript','recommendation_letters','motivation_letter'], 'https://xplore.bme.hu/admission/', '2026-08-23', 'Minimum BSc-diploma quality score explicitly published as "min 70% required" — a genuine percentage, recorded as-is. Alternative English tests: TOEFL iBT 72, Cambridge B2 First (FCE) 160 (all B2-level equivalents). Also requires an electronic e-admission test. Programme duration stated as "4 semesters / 120 ECTS" (converted to 24 months here).'),
    ('bf42c57d-0dca-42c1-a87a-eec1a74c39e4', '92428a65-10a3-4f0a-9939-76745f026db3', NULL, NULL, 'CEFR', 'B2', ARRAY['bachelor_degree_relevant_field'], 'https://edu.unideb.hu/p/computer-science-engineering-msc', '2026-08-23', 'Requires "a relevant bachelor''s degree in information technology" with no numeric GPA threshold published. English requirement is Upper-Intermediate/B2, equivalent to TOEFL PBT 547 or IELTS 6.0 — the page explicitly states a certificate is not strictly mandatory, as language is assessed at the entrance interview (a separate USD 350 entrance procedure fee covers this exam/interview). Programme duration explicitly stated as "2-year program consisting of 4 academic semesters."'),
    ('de5ea0c7-becb-47cd-812b-b638e49f4ac5', '269fb49a-3071-4e99-b35f-103e209b2bb4', NULL, NULL, 'CEFR', 'B2', ARRAY['passport','bachelor_diploma_translated','transcript','motivation_letter','cv','medical_certificate'], 'https://international.pte.hu/study-programs/msc-computer-science-engineering', '2026-08-23', 'Uses a points-based admission score (0-40 points from the average of the last two Bachelor years, e.g. 0 points below 65%, 40 points at 95%+) rather than a single GPA cutoff — not reduced to a single minimum_cgpa_percentage here since that would misrepresent the sliding scale. Total score of at least 60 points required, with a nonzero score in each of three main criteria. Minimum B2 English required; a C1 certificate is optional (5 bonus points). General PTE-wide IELTS 5.5/TOEFL 72 figures exist on a separate admissions page but were not independently confirmed via direct fetch for this specific programme. Programme duration explicitly stated as "2 years (4 semesters)."');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('437d8b86-f137-415f-bb82-5041d9591af4', 'Stipendium Hungaricum', 'Hungarian Government (Ministry of Foreign Affairs and Trade, managed by Tempus Public Foundation)', 'HU', NULL, NULL, 'FULL_FUNDING', 120.46, 'Original figure: HUF 43,700/month stipend (Bachelor''s/Master''s/one-tier Master''s level; doctoral rates differ), converted at 1 EUR = 362.78 HUF (ECB reference rate, 2026-08-21) — this is a monthly amount, not annual. Also includes full tuition-fee exemption, a free dormitory place or a HUF 40,000/month accommodation contribution, and supplementary health insurance coverage up to HUF 65,000/year. Generally restricted to citizens of countries with a bilateral educational cooperation agreement with Hungary — not open to all nationalities; the official page''s exact eligibility wording was not independently re-confirmed by direct fetch, though the programme''s existence, provider, and amounts are directly confirmed.', NULL, 'https://stipendiumhungaricum.hu/about/', 'https://stipendiumhungaricum.hu/about/', '2026-08-23');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('1554765f-5c2d-40dd-9256-7289c722ee16', '10475328-876a-4051-81ea-84258bc90bde', 'APPLICATION_FEE', 'INTERNATIONAL', 150.00, 'https://xplore.bme.hu/admission/', '2026-08-23', 'Official figure, published directly in EUR by BME (no conversion needed): EUR 150, non-refundable.'),
    ('b157c34d-c65e-4375-97f7-229cc2cbf8bf', '10475328-876a-4051-81ea-84258bc90bde', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 3500.00, 'https://xplore.bme.hu/tuition-fees/', '2026-08-23', 'Official figure, published directly in EUR by BME (no conversion needed): EUR 3,500/semester for non-EU citizens (EUR 3,200 reduced rate for BME''s own BSc graduates). EU citizens pay EUR 3,200/semester (EUR 2,850 reduced).'),
    ('ceafcf5c-06a2-406a-af17-57bd5b0aba0e', '92428a65-10a3-4f0a-9939-76745f026db3', 'APPLICATION_FEE', 'INTERNATIONAL', 128.22, 'https://edu.unideb.hu/p/tuition-fee-application-entrance-fee', '2026-08-23', 'Original figure: USD 150 one-time application fee, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21).'),
    ('1ab9de0e-894e-4fa6-9e00-c98ac873d085', '92428a65-10a3-4f0a-9939-76745f026db3', 'ADMINISTRATIVE_FEE', 'INTERNATIONAL', 299.17, 'https://edu.unideb.hu/p/tuition-fee-application-entrance-fee', '2026-08-23', 'Original figure: USD 350 entrance procedure fee, covering the required entrance exam/interview, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21).'),
    ('9f16b433-faa5-4bc4-9f6d-51d0139d1b95', '92428a65-10a3-4f0a-9939-76745f026db3', 'TUITION_PER_YEAR', 'INTERNATIONAL', 6410.80, 'https://edu.unideb.hu/p/tuition-fee-application-entrance-fee', '2026-08-23', 'Original figure: USD 7,500/year, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). Debrecen''s own official fee page states this in USD, not HUF.'),
    ('8dda6816-e3e2-4769-85e1-509ac9ebef4d', '269fb49a-3071-4e99-b35f-103e209b2bb4', 'APPLICATION_FEE', 'INTERNATIONAL', 128.22, 'https://international.pte.hu/admission/fees', '2026-08-23', 'Original figure: USD 150, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). PTE''s own official fee page states this in USD, not HUF.'),
    ('74aa7b8d-6795-4ca3-a8f1-e9c3d417dc78', '269fb49a-3071-4e99-b35f-103e209b2bb4', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 3419.10, 'https://international.pte.hu/study-programs/msc-computer-science-engineering', '2026-08-23', 'Original figure: USD 4,000/semester, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). PTE''s own official programme page states this in USD, not HUF.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('14088708-daac-4cf0-a507-75e511f38fff', 'HU', 'Debrecen', '2ff63c1f-ab53-482c-937c-11752fa04c1d', 'GENERAL', 683.82, 'https://edu.unideb.hu/page.php?id=171', '2026-08-23', 'Original figure: USD 800/month, the university''s own stated estimate ("students living and studying in Debrecen spend about 800 USD per month"), covering shared private accommodation, food, study materials, and local transportation (excludes tuition). Converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). An itemized breakdown exists on the same page as an image and was not extractable as text.'),
    ('1855bc0e-d048-42a4-953d-1c64d643f803', 'HU', 'Pécs', 'fd1bc097-c8ca-45b5-b753-63c253957290', 'GENERAL', 689.12, 'https://international.pte.hu/admission/prepare-your-stay/cost-living', '2026-08-23', 'Official figure, published directly by PTE: "HUF 250,000 (EUR 700) per month" minimum recommended budget — recorded here as HUF 250,000 converted at 1 EUR = 362.78 HUF (ECB reference rate, 2026-08-21), which yields EUR 689.12, close to PTE''s own EUR 700 approximation. Same page breaks this down as: dormitory HUF 72,600-94,100/month, shared flat HUF 80,000-100,000/month, private flat HUF 100,000-250,000/month, food HUF 40,000-60,000/month, monthly student bus pass HUF 4,100.');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('b2912e3b-b06a-41bc-ad3e-c4a1eee534a4', 'HU', NULL, 'STUDY_VISA', NULL, 60, ARRAY['passport','certificate_of_admission','language_proficiency_proof','financial_means_documentation','health_insurance_evidence','accommodation_address_declaration','photo'], 'https://oif.gov.hu/factsheets/residence-of-the-student-pupil', 'https://oif.gov.hu/factsheets/residence-of-the-student-pupil', '2026-08-23', 'Officially "Residence permit for the purpose of studies," issued by the National Directorate-General for Aliens Policing (oif.gov.hu) after an initial Type D long-stay national visa obtained at a Hungarian embassy/consulate abroad. No HUF financial-proof figure is published on the official page — it requires only "sufficient resources" evidenced via bank statements, family support, or a scholarship certificate; left NULL rather than using unofficial third-party estimates. Processing: 15 days for initial examination, final decision within 60 days of submission (60 used here as the outer bound). Procedural fee: HUF 39,000 if submitted in person in Hungary, HUF 26,000 via the "Enter Hungary" online platform; extension fee HUF 26,000 (source: https://oif.gov.hu/factsheets/procedural-fees).');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('60590a19-b6ed-4d08-86d5-d380eafe6e5e', '2ff63c1f-ab53-482c-937c-11752fa04c1d', 'UNIVERSITY_DORM', 'University of Debrecen dormitories', 'Debrecen', 110.26, NULL, NULL, ARRAY[]::text[], 'https://unideb.hu/en/dormitories-university-debrecen', NULL, 'https://unideb.hu/en/dormitories-university-debrecen', '2026-08-23', 'Original figure: HUF 40,000/month, converted at 1 EUR = 362.78 HUF (ECB reference rate, 2026-08-21). IMPORTANT: this rate is explicitly published for "foreign students on scholarships" only — the official page states fee-paying (non-scholarship) domestic student rates "vary by dormitory" and does not publish a specific rate for fee-paying international students. Recorded here as the only confirmed figure, with this eligibility caveat.'),
    ('1f0b7227-7e96-4784-b7f5-159b67d019e1', 'fd1bc097-c8ca-45b5-b753-63c253957290', 'UNIVERSITY_DORM', 'Balassa Dormitory (University of Pécs)', 'Pécs', 220.24, NULL, NULL, ARRAY[]::text[], 'https://international.pte.hu/admission/prepare-your-stay/housing', NULL, 'https://international.pte.hu/admission/prepare-your-stay/housing', '2026-08-23', 'Original figure: HUF 79,900/month, converted at 1 EUR = 362.78 HUF (ECB reference rate, 2026-08-21). Two other named PTE dormitories exist at different rates: Szántó Dormitory Wing A/C HUF 93,300/month, Wing D HUF 79,900/month; Damjanich Dormitory HUF 103,600/month. Payment is made to the university/Faculty Cashier''s office; first payment covers two months.');
-- Czechia / Italy batch (added 2026-08-23), continuing toward the
-- 32-country target. Every fact below was researched live against an
-- official source on 2026-08-23. Live ECB rate used: 1 EUR = 24.116 CZK
-- (dated 2026-08-21, via https://api.frankfurter.dev/v1/latest, the most
-- recent ECB reference available). Note: several Czech and Italian
-- universities publish their international-programme fees directly in EUR
-- (not CZK) — used as-is per their own official pages, no conversion.
--
-- Deliberate omissions (real facts found but not usable as a clean DB
-- figure without an unstated assumption):
--  - VSB-TUO's dormitory pricing is published only as per-night rates
--    (e.g. CZK 120-250/night) with no official monthly figure — converting
--    nightly-to-monthly would require assuming a specific number of nights
--    stayed, which is not officially stated, so omitted.
--  - Brno UT (VUT) and VSE's own dormitories are named/confirmed but neither
--    university's price-list pages rendered actual CZK figures (404s or
--    non-rendering content) — omitted rather than using third-party numbers.
--  - Politecnico di Torino and University of Bologna's regional
--    right-to-study agencies (EDISU Piemonte, ER.GO) have real dormitories,
--    but EDISU's tariffs apply only to competition-winning scholarship
--    recipients (not standard booking) and ER.GO's tariff PDF could not be
--    read directly — both omitted from student_accommodations.
--  - Sapienza's, Bologna's, and PoliTo's ISEE-based tuition tables are
--    published only as PDF regulations that repeatedly failed to parse
--    (corrupted/compressed binary streams) — where a clean figure exists
--    outside that PDF (Bologna's EUR 157.04/year fixed component; Sapienza's
--    EUR 2,924/year standard bracket), that figure is used with a note that
--    it is the fixed/standard rate, not necessarily the full ISEE-adjusted
--    range. PoliTo's tuition is omitted entirely — no figure outside the
--    unreadable PDF was found.
--  - No cost-of-living figure was found for Rome (Sapienza) on any directly
--    fetched official page — omitted rather than using aggregator figures.
--  - ER.GO's and DiSCo Lazio's scholarship cash amounts are not published as
--    fixed numbers on any directly-fetched official page — seeded with
--    amount_eur NULL rather than the unofficial figures found in secondary
--    aggregator sources.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('8fdc8ef9-5b13-4707-98a7-4609feb5dbbd', 'VSB – Technical University of Ostrava', 'CZ', 'Ostrava', 'https://www.vsb.cz/en/'),
    ('8b578bc4-5406-426a-9b1d-a9f8bcf02d40', 'Brno University of Technology (VUT)', 'CZ', 'Brno', 'https://www.vut.cz/en/'),
    ('fd3f5594-e986-46de-9b06-27c960073c7a', 'Prague University of Economics and Business (VŠE)', 'CZ', 'Prague', 'https://www.vse.cz/english/'),
    ('fec2dc3f-448e-49d1-b01e-01162bc4d879', 'Politecnico di Torino', 'IT', 'Turin', 'https://www.polito.it'),
    ('4293e15d-cb74-4e49-8230-e9d80f9bc274', 'University of Bologna (Alma Mater Studiorum)', 'IT', 'Bologna', 'https://www.unibo.it'),
    ('60d564dc-47bd-4758-9671-fc294af85d6c', 'Sapienza University of Rome', 'IT', 'Rome', 'https://www.uniroma1.it');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('a3ed3516-9b4a-4951-9463-3dac647181d7', '8fdc8ef9-5b13-4707-98a7-4609feb5dbbd', 'Computer Science (Follow-up Master''s, Ing.)', 'MASTER', 'Computer Science', 24, 'https://www.vsb.cz/en/study/degree-students/degree-studies/master-degree/master-degree-detail/?programmeId=1103'),
    ('2fc12ee9-9af5-4f26-9cd4-a1dde748431c', '8b578bc4-5406-426a-9b1d-a9f8bcf02d40', 'Master of Information Technology (MIT-EN)', 'MASTER', 'Information Technology', 24, 'https://www.fit.vut.cz/applicants/degree-field-en/18330/.en'),
    ('808798f1-f1b1-455b-862a-0320ab7daef3', 'fd3f5594-e986-46de-9b06-27c960073c7a', 'Information Systems Management (ISM)', 'MASTER', 'Information Systems Management', 24, 'https://fis.vse.cz/english/about/about-the-programmes/ism/'),
    ('cd2a6b19-9f31-435e-9042-292f367e868a', 'fec2dc3f-448e-49d1-b01e-01162bc4d879', 'Computer Engineering (Computer Systems Engineering)', 'MASTER', 'Computer Engineering', NULL, 'https://www.polito.it/en/education/master-s-degree-programmes/computer-engineering'),
    ('4428c014-e76e-4d67-b857-6a6b212abdc3', '4293e15d-cb74-4e49-8230-e9d80f9bc274', 'Artificial Intelligence', 'MASTER', 'Artificial Intelligence', 24, 'https://corsi.unibo.it/2cycle/artificial-intelligence'),
    ('907e5903-9db0-42ac-9303-ad2ef6ff86a0', '60d564dc-47bd-4758-9671-fc294af85d6c', 'Engineering in Computer Science and Artificial Intelligence', 'MASTER', 'Computer Science and Artificial Intelligence', 24, 'https://corsidilaurea.uniroma1.it/en/corso/2025/33515/home');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('6c1e2fc1-92d8-4c10-ad18-d96448263e14', 'a3ed3516-9b4a-4951-9463-3dac647181d7', NULL, NULL, NULL, NULL, ARRAY['bachelor_diploma','transcript','nostrification_document'], 'https://www.vsb.cz/en/study/degree-students/admission-steps/', '2026-08-23', 'Requires a Bachelor''s degree; foreign credentials require official recognition ("nostrification"). Neither a numeric minimum GPA nor a specific IELTS/TOEFL score for this Computer Science programme could be confirmed via direct fetch — the only official admission-conditions document retrievable was for a different faculty (Materials Science and Technology) and an outdated academic year (2020/2021), so its figures are not used here. Third-party aggregators cite IELTS 5.0/TOEFL 62, but these are not confirmed on an official VSB-TUO page.'),
    ('9c1a3cf3-ca79-4841-a83c-a5e7ac2728bd', '2fc12ee9-9af5-4f26-9cd4-a1dde748431c', NULL, NULL, 'TOEFL', '213', ARRAY['cv_with_it_grades','motivation_letter','technical_project_portfolio','bachelor_diploma'], 'https://www.fit.vut.cz/applicants/degree-programme-en/.en', '2026-08-23', 'English requirement officially stated as "TOEFL Basic English 213, written English 550 or other comparable levels" (legacy TOEFL PBT-style scales, reported verbatim as published — 213 recorded as the primary figure, 550 as the written-English companion figure). No numeric minimum GPA is published. A "best copyright project in IT" (technical report + source code) is required in place of a typical portfolio.'),
    ('53973d58-363a-4b9a-9de1-f827efd8e00f', '808798f1-f1b1-455b-862a-0320ab7daef3', NULL, NULL, NULL, NULL, ARRAY['passport','cv','english_proficiency_documentation','assessment_of_previous_education_form'], 'https://fis.vse.cz/english/about/about-the-programmes/ism/', '2026-08-23', 'Requires a Bachelor''s/undergraduate degree "preferably in a related field," proof of English proficiency, and a passing score on an online admission oral exam — the official page genuinely does not publish a specific minimum GPA or English test score (not a fetch failure; the page itself states no number).'),
    ('23dbba1e-2d32-44ee-a9ab-4e5b05472b12', 'cd2a6b19-9f31-435e-9042-292f367e868a', NULL, NULL, NULL, NULL, ARRAY['passport_or_eu_id','cv','bachelor_degree_certificate','transcript','course_syllabi','language_certificate','cimea_declaration_of_value'], 'https://www.polito.it/en/education/applying-studying-graduating/admissions-and-enrolment/master-s-degree-programmes/applicants-with-a-non-italian-qualification', '2026-08-23', 'Requires a Bachelor''s degree (EQF level 6) or equivalent, evaluated by the Academic Committee for curricular fit, and English at B2 level (IELTS/TOEFL/Cambridge accepted) — no specific minimum numeric score is published (page states "B2" only, no score table). Programme duration is not stated on the official page (the 2026/27 Student Guide chapter was listed as "under construction") — left NULL rather than assumed.'),
    ('b5a59220-a8a3-4b75-ae8b-efb6bf44bd26', '4428c014-e76e-4d67-b857-6a6b212abdc3', NULL, NULL, 'IELTS', '5.5', ARRAY['cv','english_certificate','transcript_of_records','id_document'], 'https://corsi.unibo.it/2cycle/artificial-intelligence/how-to-enrol', '2026-08-23', 'Requires a Bachelor''s degree (or equivalent) with at least 180 ECTS in Computer Science/Engineering/Mathematics/Physics/Statistics or a related field — not recorded as minimum_cgpa_percentage since it is a credit-count requirement, not a grade threshold. English requirement is B2, with confirmed score bands IELTS 5.5-6.5 (5.5 floor recorded here) and TOEFL PBT 507-557/CBT 180-217/iBT 80-99; Cambridge FCE, TOEIC, and PTE Academic also accepted. Nationals of English-speaking countries are exempt.'),
    ('f1dec8ed-7a97-4010-a629-f1aef0ff6917', '907e5903-9db0-42ac-9303-ad2ef6ff86a0', NULL, NULL, NULL, NULL, NULL, 'https://www.uniroma1.it/en/pagina/requirements-and-personal-knowledge-assessment-masters-degrees', '2026-08-23', 'Admission requires a passing score on an online "personal knowledge assessment" (EUR 10 fee, confirmed separately as a program_fees row). Specific GPA/ECTS thresholds, English test minimum scores, and a complete document checklist for this exact programme could not be confirmed via direct fetch — the program-specific official PDF (Call for Applications) returned as unreadable compressed content. IELTS ~6.0/TOEFL ~80 figures circulate via secondary sources but are not recorded here as they were not read directly on an official page.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('ce622f27-e458-4f0f-b661-9cfdf38b8bd8', 'BUTalent Scholarship', 'Brno University of Technology', 'CZ', '8b578bc4-5406-426a-9b1d-a9f8bcf02d40', NULL, 'LIVING_STIPEND', 311.00, 'Original figure: CZK 7,500/month for Master''s students (CZK 10,000/month for PhD students), converted at 1 EUR = 24.116 CZK (ECB reference rate, 2026-08-21) — a monthly amount, stated for the September-December 2026 period specifically on the official page. Eligible: enrolled foreign students in English-taught Master''s/PhD programmes not simultaneously receiving a comparable scholarship (e.g. JCMM, government aid, EU4Belarus).', NULL, 'https://www.vut.cz/en/students/scholarships', 'https://www.vut.cz/en/students/scholarships', '2026-08-23'),
    ('f633a30d-7082-4dc5-9fd6-9acc4c5831b2', 'TOPoliTO Scholarship', 'Politecnico di Torino', 'IT', 'fec2dc3f-448e-49d1-b01e-01162bc4d879', NULL, 'PARTIAL_TUITION', 8000.00, 'EUR 8,000/year (gross) cash award for high-achieving international students in Bachelor''s and Master''s programmes. Politecnico di Torino also separately lists MAECI government scholarships, "Invest Your Talent in Italy," COLFUTURO (Colombian nationals), and an Afghan-student-specific EUR 8,000/year scholarship on the same page.', NULL, 'https://www.polito.it/en/education/international-students/financial-aid', 'https://www.polito.it/en/education/international-students/financial-aid', '2026-08-23'),
    ('5879f746-a917-4241-9ab7-2eccbfbba2a7', 'ER.GO Study Grants', 'ER.GO (Emilia-Romagna regional right-to-study agency)', 'IT', '4293e15d-cb74-4e49-8230-e9d80f9bc274', NULL, 'FULL_FUNDING', NULL, 'Regional (Emilia-Romagna) right-to-study agency offering study grants, tuition exemption, housing, and meal subsidies, explicitly open to "foreign students and new graduates on international mobility and research programmes." The exact cash grant amount is not published on any ER.GO or unibo.it page that could be directly fetched — figures circulating on third-party aggregator sites (e.g. "up to EUR 7,171/year") are not used here since they could not be independently confirmed.', NULL, NULL, 'https://www.unibo.it/en/study/study-grants-and-subsidies/ergo', '2026-08-23'),
    ('f3bbf9c1-512c-45b1-a47b-36a75768ed5e', 'DiSCo Lazio Scholarship', 'DiSCo Lazio (Ente regionale per il diritto allo studio e alla conoscenza)', 'IT', '60d564dc-47bd-4758-9671-fc294af85d6c', NULL, 'FULL_FUNDING', NULL, 'Lazio regional right-to-study scholarship, open to non-EU/international students (eligibility assessed via ISEEUP for foreign income); coverage includes a cash grant, tuition/regional-tax exemption, subsidized meals, and possible housing placement. The exact cash amount is not stated on the official page (only eligibility mechanics) — left NULL rather than using unofficial figures. Application window is indicatively May through the third week of July.', NULL, 'https://laziodisco.it/servizi/scholarships/?lang=en', 'https://laziodisco.it/servizi/scholarships/?lang=en', '2026-08-23');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('114ee933-8d93-46df-b4c3-a4b6b8aadd4c', 'a3ed3516-9b4a-4951-9463-3dac647181d7', 'APPLICATION_FEE', 'INTERNATIONAL', 24.88, 'https://www.vsb.cz/en/study/degree-students/admission-steps/', '2026-08-23', 'Original figure: CZK 600, converted at 1 EUR = 24.116 CZK (ECB reference rate, 2026-08-21). An older/other-faculty source states CZK 500 instead — this discrepancy is disclosed rather than resolved by guessing; CZK 600 is used as the current figure on the directly-fetched admission-steps page.'),
    ('4a89ad1c-a0be-4e4a-96be-a6dfca044f72', 'a3ed3516-9b4a-4951-9463-3dac647181d7', 'TUITION_PER_SEMESTER', 'INTERNATIONAL', 2073.31, 'https://www.vsb.cz/en/study/admissions/tuition-fees/', '2026-08-23', 'Original figure: CZK 50,000/semester (~CZK 100,000/year) for English-taught Master''s programmes, effective from 2026/2027, converted at 1 EUR = 24.116 CZK (ECB reference rate, 2026-08-21).'),
    ('15fa5bc2-513a-48e6-8019-1d184b3dff8b', '2fc12ee9-9af5-4f26-9cd4-a1dde748431c', 'APPLICATION_FEE', 'INTERNATIONAL', 28.00, 'https://www.fit.vut.cz/applicants/degree-programme-en/.en', '2026-08-23', 'Official figure, published directly in EUR by VUT (no conversion needed): EUR 28.'),
    ('e3a7e689-3d63-40df-a2a0-0e1fb2821a55', '2fc12ee9-9af5-4f26-9cd4-a1dde748431c', 'TUITION_PER_YEAR', 'INTERNATIONAL', 3000.00, 'https://www.fit.vut.cz/applicants/degree-programme-en/.en', '2026-08-23', 'Official figure, published directly in EUR by VUT (no conversion needed): EUR 3,000/year (EUR 1,500/semester), despite Czechia using CZK as its national currency — reported exactly as officially published.'),
    ('da2d7016-c960-41bc-85ae-8f6643e4397f', '808798f1-f1b1-455b-862a-0320ab7daef3', 'APPLICATION_FEE', 'INTERNATIONAL', 100.00, 'https://admissions.vse.cz/admission-procedure/', '2026-08-23', 'Official figure, published directly in EUR by VSE (no conversion needed): EUR 100.'),
    ('73bb319f-f102-4bb6-9b0c-e9f1fcc4a88d', '808798f1-f1b1-455b-862a-0320ab7daef3', 'TUITION_PER_YEAR', 'INTERNATIONAL', 6000.00, 'https://admissions.vse.cz/admission-procedure/', '2026-08-23', 'Official figure, published directly in EUR by VSE (no conversion needed): EUR 6,000/academic year (EUR 3,000/semester), the general Master''s rate — reduced rates exist for students admitted in earlier cohorts per the same page.'),
    ('b433385e-2f8f-4ddc-843e-0b59befe8a42', 'cd2a6b19-9f31-435e-9042-292f367e868a', 'APPLICATION_FEE', 'INTERNATIONAL', 50.00, 'https://www.polito.it/en/education/applying-studying-graduating/admissions-and-enrolment/master-s-degree-programmes/applicants-with-a-non-italian-qualification', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 50, non-refundable. Per-year tuition uses an ISEE-based sliding scale whose exact minimum/maximum figures could not be confirmed — the official Tuition Fee Regulations PDF (Rectoral Decree No. 722/2025) returned as unreadable compressed content on every fetch attempt — so no tuition fee row is seeded for this programme.'),
    ('ff0b6e3f-1dbf-4633-9ea4-2eedce06025d', '4428c014-e76e-4d67-b857-6a6b212abdc3', 'TUITION_PER_YEAR', 'INTERNATIONAL', 157.04, 'https://www.unibo.it/en/study/enrolment-fees-and-other-procedures/degree-programmes/tuition-fees-and-exemptions/fees-and-exemptions-amounts-deadlines', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 157.04/year — this is only the FIXED component always due; the ISEE-based variable component is fully exempted for family ISEE at or below EUR 27,000, and its maximum "varies depending on the programme" but could not be confirmed for this specific Artificial Intelligence programme (referenced fee-table PDF returned as unreadable compressed content). This figure should not be read as the full possible tuition.'),
    ('444a35bc-61d5-4d5d-8192-bf5bc6c2040b', '907e5903-9db0-42ac-9303-ad2ef6ff86a0', 'APPLICATION_FEE', 'INTERNATIONAL', 10.00, 'https://www.uniroma1.it/en/pagina/requirements-and-personal-knowledge-assessment-masters-degrees', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 10 "enrollment fee" specifically for the personal-knowledge-assessment admission step. No separate general application/pre-selection fee was confirmed (a EUR 30 pre-selection fee appears only in a secondary, unverified source).'),
    ('d4bccb82-42b2-47bb-83dd-0135427805ae', '907e5903-9db0-42ac-9303-ad2ef6ff86a0', 'TUITION_PER_YEAR', 'INTERNATIONAL', 2924.00, 'https://www.uniroma1.it/en/content/standard-registration-fee-amounts', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 2,924/year, the standard (non-ISEE-reduced) rate for the second contribution bracket covering Computer Science, Information Engineering, and Statistics programmes, paid in three installments (EUR 877 + EUR 1,023 + EUR 1,024). An ISEE-based reduced minimum exists per the same page but its exact figure is on a separate "Exemptions and Benefits" page not yet confirmed.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('eb70902d-28b7-4626-8010-c34ef11cb1d1', 'CZ', 'Ostrava', '8fdc8ef9-5b13-4707-98a7-4609feb5dbbd', 'GENERAL', 500.00, 'https://www.vsb.cz/en/study/study-at-vsb-tuo/cost-of-living/', '2026-08-23', 'Official figure, published directly in EUR by VSB-TUO (no conversion needed, no CZK-denominated figure was found on this page): approx. EUR 500/month for food, accommodation, transport, and other expenses.'),
    ('50fcda53-8005-4c6f-b4d4-539d3c4ef772', 'CZ', NULL, NULL, 'GENERAL', 650.00, 'https://www.studyin.cz/get-ready-for-czechia/living-costs/', '2026-08-23', 'Official figure from studyin.cz, the Czech National Agency for International Education and Research (DZS, under the Ministry of Education, Youth and Sports): midpoint of the site''s own stated "EUR 500-800/month" national estimate for basic student living expenses (no conversion needed, published directly in EUR). Breakdown per the same page: food ~EUR 150-230/month; dormitory shared room EUR 160-330/month; dormitory single room EUR 250-450/month; room in shared flat EUR 250-500/month. The page explicitly notes "Prague and Brno are among the most expensive student cities in Czechia" without a separate city-specific total.'),
    ('5540730c-2108-4a71-a981-17553482b98f', 'IT', 'Turin', 'fec2dc3f-448e-49d1-b01e-01162bc4d879', 'ACCOMMODATION', 500.00, 'https://www.polito.it/en/education/international-students/practical-information/cost-of-living', '2026-08-23', 'Original figure: midpoint of the official page''s stated EUR 400-600/month single-room rent range (a shared room costs roughly half). Other stated components on the same page, not summed into this figure to avoid an unstated assumption: food EUR 200-300/month, monthly student transit pass ~EUR 26, utilities ~EUR 70-100/month.'),
    ('a408dd2d-62c0-41a7-92d0-7bcdf7ebc0c5', 'IT', 'Bologna', '4293e15d-cb74-4e49-8230-e9d80f9bc274', 'ACCOMMODATION', 400.00, 'https://www.unibo.it/en/study/life-at-university-and-in-the-city/living-in-the-city/living-costs-in-bologna', '2026-08-23', 'Official figure, published directly in EUR: EUR 400/month for a single room in a shared apartment, plus utilities (utilities amount not separately quantified on the page). A shared room instead costs EUR 300/month + utilities. Other stated components, not summed into this figure: weekly groceries ~EUR 60, university canteen meal EUR 4.50-6.00, monthly student (under-27) bus pass EUR 27.');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('92fdc353-d4c2-48b1-b4cb-01df33ca7d74', 'CZ', NULL, 'RESIDENCE_PERMIT', 4802.21, 60, ARRAY['passport_valid_9_months_beyond_entry','application_form','photos','biometric_data','proof_of_enrollment','proof_of_accommodation','proof_of_financial_means','criminal_record_extract','travel_health_insurance'], 'https://mzv.gov.cz/jnp/en/information_for_aliens/long_stay_visa/study_long_term.html', 'https://mzv.gov.cz/losangeles/en/visa_information/long_term_residence_permit/study.html', '2026-08-23', 'Officially the "Long-term residence permit for the purpose of study," obtained after initial entry on a long-term visa. financial_proof_eur is converted from the officially published worked example for a 12-month academic-year stay — CZK 115,810 (formula: 15x the existential minimum of CZK 3,130 for the first month, plus 2x for each of the 11 subsequent months) — at 1 EUR = 24.116 CZK (ECB reference rate, 2026-08-21); the Ministry''s own page also states this is roughly USD 5,300. A written commitment from a public authority or legal entity (e.g. a full scholarship) can substitute for this financial-means proof. Documents must be in Czech or officially translated and non-passport documents cannot be older than 180 days.'),
    ('78309713-9dc8-4ef3-ac56-4042cae2a4dd', 'IT', NULL, 'STUDY_VISA', NULL, 90, ARRAY['passport_valid_3_months_beyond_visa','application_form','photo','flight_reservation','accommodation_proof','enrollment_letter','prior_educational_records','proof_of_financial_means','travel_medical_insurance_min_30000_eur'], 'https://vistoperitalia.esteri.it/', 'https://constoronto.esteri.it/en/servizi-consolari-e-visti/servizi-per-il-cittadino-straniero/visti/visti-nazionali/visto-per-studio/', '2026-08-23', 'Officially the "National Visa (Visto Nazionale), Type D," for stays over 90 days for study purposes. The central visa portal (vistoperitalia.esteri.it) does not publish a single Italy-wide financial-proof EUR figure — it delegates to individual consulates, whose published minimums vary; no single authoritative number is used here. Minimum EUR 30,000 medical/Schengen insurance coverage is confirmed. Processing time (45-90 business days, 90 used here as the outer bound) and the specific document checklist are both sourced from one specific consulate (Toronto) and may vary by consulate. After arrival, a "Permesso di Soggiorno per Studio" must be requested at the local Questura within 8 working days — this post-arrival step is standard, well-known procedure but was not independently confirmed via a directly-fetched Polizia di Stato/Questura page.');

INSERT INTO student_accommodations (accommodation_id, university_id, accommodation_type, provider_name, city, monthly_rent_eur, deposit_eur, distance_to_university_km, amenities, application_url, contact_email, source_url, source_checked_on, notes) VALUES
    ('5536e678-8e4b-4d2a-b88d-45f1082aff9d', '60d564dc-47bd-4758-9671-fc294af85d6c', 'UNIVERSITY_DORM', 'DiSCo Lazio', 'Rome', 220.50, NULL, NULL, ARRAY[]::text[], 'https://laziodisco.it/servizi/residenze-universitarie/', NULL, 'https://laziodisco.it/servizi/residenze-universitarie/', '2026-08-23', 'Official figure: midpoint of the page''s own stated "un minimo di 143 euro ad un massimo di 298 euro" (EUR 143-298/month depending on accommodation type — single/double rooms, studios, multi-room apartments), published directly in EUR (no conversion needed). Over 3,100 bed spaces across Rome-area residences. Scholarship winners who are also awarded housing get it free (deducted from the grant).');
-- Spain / Slovakia / Malaysia batch (added 2026-08-23), continuing toward
-- the 32-country target and adding the first non-EU/Asian destination
-- (Malaysia). Every fact below was researched live against an official
-- source on 2026-08-23. Live ECB rates used: 1 EUR = 4.7246 MYR,
-- 1 EUR = 0.8567 GBP, 1 EUR = 1.1699 USD (all dated 2026-08-21, via
-- https://api.frankfurter.dev/v1/latest, the most recent ECB reference
-- available). Spain and Slovakia use EUR, no conversion needed there.
--
-- Deliberate omissions:
--  - No Slovakia-wide visa row: every official Slovak government source
--    (mzv.sk, minv.sk, slovensko.sk, stipendia.sk/scholarships.sk) returned
--    HTTP 403 or 404 on direct fetch — same discipline as the earlier US
--    visa omission.
--  - Universidad Politécnica de Madrid and Universidad de Granada have no
--    program_fees rows this batch: neither university's tuition or
--    application-fee figures could be confirmed via direct fetch (pages
--    404'd or lacked the figure) despite genuine attempts.
--  - UTM (Malaysia) admission requirements show two conflicting official
--    CGPA figures (2.50 on one page, 3.0 on another) — neither is used as
--    minimum_cgpa_percentage; both are disclosed in notes instead, along
--    with two conflicting duration statements.
--  - No cost-of-living or accommodation-price rows for Barcelona, Madrid,
--    Granada, Bratislava, Košice, Johor Bahru, or Kuala Lumpur — every
--    official page attempted either 404'd, returned an HTTP error, or
--    (Bratislava/Košice) simply never published a monthly figure.

INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('3d4eaa65-39c3-4ce7-bcab-31931c3a3316', 'Universitat Politècnica de Catalunya (UPC)', 'ES', 'Barcelona', 'https://www.upc.edu'),
    ('8202d466-4820-4018-8ac7-3caea1cdd3c7', 'Universidad Politécnica de Madrid (UPM)', 'ES', 'Madrid', 'https://www.upm.es'),
    ('79fa128a-4917-40f3-9ba9-fb95e083849c', 'Universidad de Granada (UGR)', 'ES', 'Granada', 'https://www.ugr.es'),
    ('065f8c5b-2305-4fdd-8eff-d4ac68664ba7', 'Comenius University Bratislava', 'SK', 'Bratislava', 'https://uniba.sk/en/'),
    ('f22b13d3-d311-489c-8325-09ad17220224', 'Technical University of Košice (TUKE)', 'SK', 'Košice', 'https://www.tuke.sk/en/'),
    ('5d5b4ab1-1c2b-4d07-94b2-cf02b8567293', 'Slovak University of Technology in Bratislava (STU)', 'SK', 'Bratislava', 'https://www.stuba.sk/en/'),
    ('db23c7e3-41dd-4ce5-93a6-fb06f73d9b41', 'Multimedia University (MMU)', 'MY', 'Cyberjaya', 'https://www.mmu.edu.my'),
    ('a3d4b3ed-10b7-4014-9b14-aa0e4aa72a7e', 'Universiti Teknologi Malaysia (UTM)', 'MY', 'Johor Bahru', 'https://www.utm.my'),
    ('3ec4aa7e-53d3-4c97-96f8-96d6fdbd60a6', 'Universiti Malaya (UM)', 'MY', 'Kuala Lumpur', 'https://um.edu.my');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('94eeade1-21df-4eaa-8eac-d594600ef2f2', '3d4eaa65-39c3-4ce7-bcab-31931c3a3316', 'Master in Artificial Intelligence (MAI)', 'MASTER', 'Artificial Intelligence', 18, 'https://www.fib.upc.edu/en/masters/master-artificial-intelligence'),
    ('f9d78aba-9a51-4571-b3fb-5d37976d6af7', '8202d466-4820-4018-8ac7-3caea1cdd3c7', 'Máster Universitario en Ciencia de Datos (MSc Data Science)', 'MASTER', 'Data Science', 12, 'https://mucd.dia.fi.upm.es/'),
    ('555d2314-0164-46b4-9a31-3ce084bfb34d', '79fa128a-4917-40f3-9ba9-fb95e083849c', 'Máster en Ciencia de Datos e Ingeniería de Computadores (DATCOM)', 'MASTER', 'Data Science and Computer Engineering', NULL, 'http://masteres.ugr.es/datcom/'),
    ('9325a0a1-2e20-4fe1-9169-2c31b2498e91', '065f8c5b-2305-4fdd-8eff-d4ac68664ba7', 'Computer Science (Master''s)', 'MASTER', 'Computer Science', 24, 'https://www.fmph.uniba.sk/en/admissions/masters-degree-programs/computer-science/'),
    ('6e455880-57e8-40e5-813a-61d72276ab4e', 'f22b13d3-d311-489c-8325-09ad17220224', 'Artificial Intelligence (joint programme with STU)', 'MASTER', 'Artificial Intelligence', 24, 'https://fei.tuke.sk/en/ai-join-sp'),
    ('d2930f6e-14d6-4278-98ce-3317639fd733', '5d5b4ab1-1c2b-4d07-94b2-cf02b8567293', 'Artificial Intelligence (joint programme with TUKE)', 'MASTER', 'Artificial Intelligence', 24, 'https://www.fiit.stuba.sk/en/students/study/study-programs'),
    ('87412d75-61ac-496c-8f03-f5f91d7b8018', 'db23c7e3-41dd-4ce5-93a6-fb06f73d9b41', 'Master of Computer Science (By Coursework)', 'MASTER', 'Computer Science', NULL, 'https://www.mmu.edu.my/pogrammes-all/programmes-new/master-of-computer-science-by-coursework-conventional/'),
    ('05c8f467-beef-4041-b35c-170e319a774f', 'a3d4b3ed-10b7-4014-9b14-aa0e4aa72a7e', 'Master of Computer Science (MECS)', 'MASTER', 'Computer Science', NULL, 'https://comp.utm.my/master-cs/'),
    ('0e488e7e-3e99-482e-b951-39e5ebf038af', '3ec4aa7e-53d3-4c97-96f8-96d6fdbd60a6', 'Master of Computer Science (Applied Computing), Mixed Mode', 'MASTER', 'Computer Science', NULL, 'https://fsktm.um.edu.my');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('d4bb1d1a-db48-4c1a-81c5-8030ccb566a4', '94eeade1-21df-4eaa-8eac-d594600ef2f2', NULL, NULL, 'CEFR', 'B2', ARRAY['academic_transcript','degree_diploma','language_certificate_b2','grade_equivalence_statement','motivation_letter'], 'https://www.fib.upc.edu/en/masters/do-you-want-study-master-degree/pre-enrolment-and-admission', '2026-08-23', 'B2 CEFR English level is mandatory; no specific IELTS/TOEFL numeric score is published. No minimum GPA is published — admission is evaluated (e.g. academic transcript weighting) rather than a stated cutoff. Requires Spain''s "official statement of equivalence of the average grade obtained" (the country''s foreign-credential equivalence mechanism) and, for non-Spanish documents, translation plus apostille/legalization. Programme duration officially stated as "Three semesters" (converted to 18 months here).'),
    ('13782c78-510b-4a65-9994-e02e689b7b14', 'f9d78aba-9a51-4571-b3fb-5d37976d6af7', NULL, NULL, NULL, NULL, NULL, 'https://www.upm.es/internacional', '2026-08-23', 'Only the general master''s-access requirement was confirmed: a title authorizing access to Master''s-level education, with an explicit note that UPM''s acceptance of a foreign degree for enrollment does not itself constitute Spain''s separate "homologación" (recognition) process. Minimum GPA, English test/score, and a full document checklist could not be confirmed — several official pages either 404''d or lacked this detail.'),
    ('48c19737-11b1-4ede-83ba-8c9dd6801578', '555d2314-0164-46b4-9a31-3ce084bfb34d', NULL, NULL, 'CEFR', 'B2', NULL, 'http://masteres.ugr.es/datcom/estudiantes/acceso-admision', '2026-08-23', 'This programme (DATCOM) is taught in Spanish, not English — B2 Spanish proficiency is required for non-native speakers (recorded as CEFR/B2 here to reflect the language level, not an English requirement). Admission selection is officially "100% sobre la nota de expediente" (based entirely on the academic-transcript grade), with no separate published numeric minimum. Capacity: 60 students/year. Document checklist directs applicants to the Escuela Internacional de Posgrado rather than listing documents on this specific page.'),
    ('7217e113-3c85-408f-b7fa-2912e76c3d38', '9325a0a1-2e20-4fe1-9169-2c31b2498e91', NULL, NULL, NULL, NULL, ARRAY['bachelor_diploma_legalized','official_transcript','english_language_certificate','cv','two_academic_reference_letters','motivation_letter','passport','degree_equivalence_certificate'], 'https://fmph.uniba.sk/en/admissions/admissions-process/masters-degree-admissions/', '2026-08-23', 'International applicants must "fulfill conditions equivalent to Slovak students" but no numeric minimum GPA is published. Requires "an internationally recognized English language certificate" without naming a specific test or minimum score. Non-Slovak degree holders need an additional Certificate of degree equivalence. Programme duration: "2 years" standard track, or a 3-year conversion track for non-CS bachelor''s backgrounds (24 months recorded for the standard track).'),
    ('2575f47b-e0c7-4136-9a4b-dbfada2ae9ce', '6e455880-57e8-40e5-813a-61d72276ab4e', NULL, NULL, NULL, NULL, NULL, 'https://fei.tuke.sk/en/ai-join-sp', '2026-08-23', 'This is a joint Master''s programme delivered by TUKE (Faculty of Electrical Engineering and Informatics) and STU (Faculty of Informatics and Information Technologies, FIIT) — students study semesters 1 and 4 at FIIT STU (Bratislava) and semesters 2 and 3 at FEI TUKE (Košice). Admission-requirement detail (GPA, English test/score, document checklist) could not be confirmed — the relevant pages render via client-side placeholders not captured by direct fetch.'),
    ('730ceb81-9176-42ce-a683-2ef3f2fe8af2', 'd2930f6e-14d6-4278-98ce-3317639fd733', NULL, NULL, NULL, NULL, NULL, 'https://www.fiit.stuba.sk/en/students/study/study-programs', '2026-08-23', 'Same joint Artificial Intelligence programme as the Technical University of Košice (TUKE) row — see that row''s notes for the shared delivery structure. STU''s English-language pages give contact information for the Master''s admission process but no published GPA threshold, named English test, or itemized document checklist.'),
    ('791f6fb4-5df1-40aa-ba9c-4421746e2fea', '87412d75-61ac-496c-8f03-f5f91d7b8018', NULL, NULL, 'IELTS', '6.0', NULL, 'https://www.mmu.edu.my/pogrammes-all/programmes-new/master-of-computer-science-by-coursework-conventional/', '2026-08-23', 'Minimum CGPA of 2.50 required for a Computing bachelor''s degree (2.00-2.49 admitted subject to internal assessment; non-Computing bachelor''s degree needs CGPA >=2.00 plus prerequisite courses) — this is Malaysia''s CGPA scale (typically out of 4.0), not recorded as minimum_cgpa_percentage to avoid an unofficial scale conversion. Alternative English tests to IELTS 6.0: MUET B4.0, TOEFL iBT 60, TOEFL Essentials 8.5, Pearson PTE 59, Linguaskill Online 169; waived for native speakers or prior English-medium qualification. Duration officially stated as "Min. 1 year, Max. 3 years" full-time — not reduced to a single figure here.'),
    ('838a29d6-3b39-4d89-b370-3b36c23a1dd9', '05c8f467-beef-4041-b35c-170e319a774f', NULL, NULL, 'IELTS', '6.0', ARRAY['letter_of_undertaking','health_assessment_form','transcripts','english_certification','passport_copy','passport_photo'], 'https://admission.utm.my/english-language-requirements-3/', '2026-08-23', 'Two different official UTM pages state two different minimum CGPA figures for this programme — comp.utm.my/master-cs/ states 2.50 (2.50-2.75 needs Faculty evaluation; below 2.50 needs 5 years work experience), while admission.utm.my/international-postgraduate-study/ states "at least 3.0 CGPA" — neither is recorded as minimum_cgpa_percentage given the conflict and the CGPA-vs-percentage scale issue; both figures are disclosed here rather than resolved by guessing. Alternative English tests to IELTS 6.0: TOEFL iBT 60, Pearson PTE 59, MUET band 4.0, Cambridge English 169. Duration is also inconsistently stated: comp.utm.my says "maximum of four (4) years," while the fee page frames the programme around "3 semesters" — both reported without reconciling.'),
    ('4cb664fa-1e5d-4865-8533-f839af5bc49c', '0e488e7e-3e99-482e-b951-39e5ebf038af', NULL, NULL, NULL, NULL, NULL, 'https://fsktm.um.edu.my', '2026-08-23', 'The Faculty of Computer Science & Information Technology (FSKTM) lists this programme by name among several Master''s offerings, but a dedicated per-programme admission page with minimum CGPA and English-test-score detail could not be reached. Only a university-wide application fee (recorded as a program_fees row) and the intake schedule (Semester I October intake for AY2026/2027, applications open 9 Feb 2026, deadline 30 Aug 2026) were confirmed.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('3fa8bb0b-8444-4b80-a726-43231372d65e', 'Fundación Carolina Scholarships', 'Fundación Carolina', 'ES', NULL, NULL, 'FULL_FUNDING', NULL, 'A Spain-based foundation offering postgraduate scholarships for Iberoamerican (Latin American and Iberian) students specifically — not open to international applicants generally. Named as an option by Universidad de Granada''s International School of Postgraduate Studies, but the exact coverage amount was not confirmed on that page and fundacioncarolina.es itself was not directly fetched this batch — left NULL rather than guessed.', NULL, NULL, 'https://escuelaposgrado.ugr.es/pages/becas', '2026-08-23'),
    ('1a5a4384-e3f5-40ef-bcf1-d4b605163c96', 'MTCP Scholarship (Malaysian Technical Cooperation Programme)', 'Government of Malaysia', 'MY', NULL, NULL, 'FULL_FUNDING', NULL, 'Covers tuition fees, allowances, and return economy-class airfare; no single fixed cash figure is published (bundle of benefits). Eligibility: nationals of MTCP recipient (developing) countries, age 45 or under, minimum Second Class Upper Honours or CGPA 3.00 (Malaysian scale, not a percentage), English requirement IELTS 6.0+/TOEFL iBT 60+ or a prior degree taught in English. Duration 24-36 months for Master''s level.', NULL, NULL, 'https://admission.utm.my/scholarship-and-financial-aid/', '2026-08-23'),
    ('d331ead0-dca1-4392-bccd-80fa78c56843', 'PTE x Universiti Malaya Scholarship 2026', 'Pearson PTE & Universiti Malaya', 'MY', '3ec4aa7e-53d3-4c97-96f8-96d6fdbd60a6', NULL, 'PARTIAL_TUITION', 3501.81, 'Original figure: GBP 3,000 toward tuition fees, converted at 1 EUR = 0.8567 GBP (ECB reference rate, 2026-08-21). Open to international students; application deadline 31 December 2026.', '2026-12-31', 'https://aasd.um.edu.my/financial-aid-for-postgraduate', 'https://aasd.um.edu.my/financial-aid-for-postgraduate', '2026-08-23');

INSERT INTO program_fees (fee_id, program_id, fee_type, student_category, amount_eur, source_url, source_checked_on, notes) VALUES
    ('3b731e84-d915-4f8a-abe7-d270fbda0fe9', '94eeade1-21df-4eaa-8eac-d594600ef2f2', 'APPLICATION_FEE', 'INTERNATIONAL', 300.00, 'https://www.upc.edu/en/masters/fees-grants', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 300 pre-enrolment/admission fee, non-refundable. Additional yearly administrative fees also apply per the same page: academic record handling EUR 69.80, teaching/learning support EUR 70.00, degree certificate EUR 218.15 (not recorded as separate rows).'),
    ('4b8723a8-f257-4560-aa80-af8529015dab', '94eeade1-21df-4eaa-8eac-d594600ef2f2', 'TUITION_TOTAL', 'INTERNATIONAL', 4600.00, 'https://www.upc.edu/en/masters/fees-grants', '2026-08-23', 'Official figure, published directly in EUR by UPC as its own approximate total (no conversion needed): "approximately EUR 4,600 for non-EU students" for the full 90-ECTS programme, based on a published per-credit rate of EUR 45.00/credit for non-EU students (vs EUR 17.69-19.37/credit for EU students, giving an EU total around EUR 2,100-2,300).'),
    ('22e9ca29-70b8-4f71-84a4-576701bf042a', '9325a0a1-2e20-4fe1-9169-2c31b2498e91', 'APPLICATION_FEE', 'INTERNATIONAL', 15.00, 'https://fmph.uniba.sk/en/admissions/fee-schedule/', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 15 for the electronic application form (EUR 33 for a paper form).'),
    ('b0eb7df2-bd80-4888-b4a2-d2b68e2acafc', '9325a0a1-2e20-4fe1-9169-2c31b2498e91', 'TUITION_PER_YEAR', 'INTERNATIONAL', 1800.00, 'https://fmph.uniba.sk/en/admissions/fee-schedule/', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 1,800/year for the English-language Master''s programme, for AY 2026/2027 (consistent with AY 2025/2026 per the same page).'),
    ('b8c07daf-0770-4e76-a0ac-58959cea4451', '6e455880-57e8-40e5-813a-61d72276ab4e', 'TUITION_PER_YEAR', 'INTERNATIONAL', 7000.00, 'https://fei.tuke.sk/en/ai-join-sp', '2026-08-23', 'Official figure, published directly in EUR (no conversion needed): EUR 7,000/year, independently cross-confirmed via STU''s own signed rector''s-directive fee schedule PDF (Annex 1 to Directive 8/2025-SR), which lists the identical figure for FIIT 2nd-degree programmes taught exclusively in a foreign language, for students admitted in AY 2026/2027.'),
    ('7c2131f3-93ae-480d-9f52-9d66c35f8b2b', 'd2930f6e-14d6-4278-98ce-3317639fd733', 'TUITION_PER_YEAR', 'INTERNATIONAL', 7000.00, 'https://www.stuba.sk/buxus/docs/stu/pracoviska/rektorat/odd_vzdelavania/legislativa/predpisy_2025/P1_smernica_8_2025_skolne_a_poplatky_2026_2027.pdf', '2026-08-23', 'Official figure from STU''s own signed rector''s-directive PDF (Annex 1 to Directive 8/2025-SR, Table 3: annual tuition, full-time, exclusively foreign-language-taught programmes, students admitted AY2026/2027): FIIT 2nd degree (Master''s) = EUR 7,000/year. Same figure independently confirmed on TUKE''s own programme page (see that row).'),
    ('d2abd0f8-f098-472b-bf2c-eb2fc3625157', '87412d75-61ac-496c-8f03-f5f91d7b8018', 'APPLICATION_FEE', 'INTERNATIONAL', 423.32, 'https://www.mmu.edu.my/fee-structure-international/', '2026-08-23', 'Original figure: MYR 2,000 registration fee, converted at 1 EUR = 4.7246 MYR (ECB reference rate, 2026-08-21). A separate MYR 3,500 International Processing Fee (Student Visa) also applies, and is not included in this figure.'),
    ('fb4c26af-13dc-4336-bd8a-b1c980f7373c', '87412d75-61ac-496c-8f03-f5f91d7b8018', 'TUITION_TOTAL', 'INTERNATIONAL', 6138.09, 'https://www.mmu.edu.my/fee-structure-international/', '2026-08-23', 'Original figure: MYR 29,000 Total Programme Fee for the Master of Computer Science, converted at 1 EUR = 4.7246 MYR (ECB reference rate, 2026-08-21). This is a whole-programme total, not a per-year figure.'),
    ('36959532-ff79-4edd-beee-55a6fae60184', '05c8f467-beef-4041-b35c-170e319a774f', 'TUITION_TOTAL', 'INTERNATIONAL', 5608.94, 'https://admission.utm.my/fees-pg-inter/', '2026-08-23', 'Original figure: MYR 26,500 for the coursework/mixed-mode Master''s programme (3 semesters), converted at 1 EUR = 4.7246 MYR (ECB reference rate, 2026-08-21). Excludes hostel, convocation, visa, and personal-bond fees, and the source page notes figures are "subject to changes."'),
    ('efbe5d2e-4655-4a01-b2f6-ba848749f9cd', '0e488e7e-3e99-482e-b951-39e5ebf038af', 'APPLICATION_FEE', 'INTERNATIONAL', 63.50, 'https://study.um.edu.my/how-to-apply', '2026-08-23', 'Original figure: MYR 300.00 per application, converted at 1 EUR = 4.7246 MYR (ECB reference rate, 2026-08-21). Stated for Full-Time Conventional (Master''s & Doctoral), Full-Time ODL Master''s, and Part-Time Conventional Master''s/Doctoral. No per-year tuition figure could be confirmed for this university.');

INSERT INTO living_cost_estimates (estimate_id, country_code, city, university_id, category, monthly_estimate_eur, source_url, source_checked_on, notes) VALUES
    ('f7f22ef0-c681-478c-b196-ea3dd2245902', 'MY', NULL, NULL, 'GENERAL', 497.48, 'https://educationmalaysia.gov.my/plan-your-studies/plan-your-budget/cost-of-living', '2026-08-23', 'Original figure: USD 582/month, Education Malaysia Global Services'' (EMGS, the official government body overseeing international student admissions) own stated national average cost of living, converted at 1 EUR = 1.1699 USD (ECB reference rate, 2026-08-21). Not city-specific. Same page breaks this down (also in USD): on-campus accommodation USD 50-150/month, off-campus USD 100-300/month, combined utilities USD 40-65/month — not summed into this figure to avoid an unstated assumption.');

INSERT INTO visa_requirements (visa_requirement_id, destination_country_code, applicant_country_code, visa_type, financial_proof_eur, estimated_processing_days, required_documents, application_url, source_url, source_checked_on, notes) VALUES
    ('15c4c6c4-ef13-41e1-97a4-62a3f114ba92', 'ES', NULL, 'STUDY_VISA', 600.00, 35, ARRAY['visa_application_form','passport_photo','passport_valid_1_year_2_blank_pages','proof_of_admission_with_tuition_payment_evidence','financial_means_documentation','health_insurance_min_30000_eur_or_no_limits','medical_certificate','criminal_background_check_apostilled','signed_disclaimer_form'], 'https://www.exteriores.gob.es/Consulados/washington/en/ServiciosConsulares/Paginas/Consular/study-visa.aspx', 'https://www.exteriores.gob.es/Consulados/washington/en/ServiciosConsulares/Paginas/Consular/study-visa.aspx', '2026-08-23', 'Officially the national "Study Visa" (visado de estudios), for stays over 90 days. financial_proof_eur is 100% of the monthly IPREM (Spain''s official public income indicator) = EUR 600/month of stay, published directly in EUR (no conversion needed) — additional family members require 75%/50% of IPREM each. Processing: minimum 5 weeks between complete submission and visa collection (35 days used here), applications may be submitted 6 months to 2 months ahead; post-submission inter-agency consultation can add up to 7 more days; explicitly stated the process "cannot be expedited." For stays over 180 days, holder must apply for the TIE (foreigner ID/residence card) within 30 days of entering Spain, valid for the enrollment period up to 1 year (renewable). Visa fee stated as USD 106-548 depending on nationality and length of stay. Sourced from the Washington D.C. consulate''s page specifically — the IPREM formula and TIE requirement are national policy, but some procedural details may vary by consulate.'),
    ('c2fdf73c-f8dd-4972-8569-46ce8db24347', 'MY', NULL, 'STUDY_VISA', NULL, 14, ARRAY['passport_photo','passport_biodata_page','offer_letter','health_declaration_form','academic_certificates_and_transcripts'], 'https://educationmalaysia.gov.my/get-in-touch/faq', 'https://educationmalaysia.gov.my/get-in-touch/faq', '2026-08-23', 'Administered by Education Malaysia Global Services (EMGS) as the "Student Pass" (with a separate 12-month post-study "Graduate Pass" also available). No MYR financial-proof figure is published on any EMGS page fetched — left NULL rather than guessed. Processing time per EMGS''s own "client charter": 14 working days for a complete application (incomplete/incorrect submissions may add time); a separate official Universiti Malaya visa-guidance page states "4-6 weeks" instead — both figures are reported from their respective official sources rather than reconciled.');
-- Greece batch (added 2026-08-23) — a deliberately leaner research pass to
-- test lower token usage: narrower scope (skipped cost-of-living,
-- accommodation, and visa research entirely), capped tool-call budget, and
-- a terse report requirement. Yield was correspondingly thin — most facts
-- beyond name/city/website/programme-title could not be confirmed within
-- the tighter budget (detail pages were JS-rendered and needed more
-- navigation than allotted). Seeded honestly with what was confirmed;
-- nothing invented to fill the gaps.
INSERT INTO universities (university_id, name, country_code, city, website_url) VALUES
    ('596247b0-42a0-4a7a-a015-2c5b9ced7237', 'National Technical University of Athens (NTUA)', 'GR', 'Athens', 'https://www.ntua.gr/en/'),
    ('c5f910d1-f70a-48a7-9f4b-e0ad92598e92', 'Aristotle University of Thessaloniki (AUTh)', 'GR', 'Thessaloniki', 'https://www.auth.gr/en/');

INSERT INTO academic_programs (program_id, university_id, title, degree_level, field_of_study, duration_months, programme_url) VALUES
    ('86a61787-c618-42e8-bf50-f3f7f787cfad', '596247b0-42a0-4a7a-a015-2c5b9ced7237', 'Data Science and Machine Learning', 'MASTER', 'Data Science and Machine Learning', NULL, 'https://dsml.ece.ntua.gr/'),
    ('30b96861-2ba4-462c-9059-9f9eedda084c', 'c5f910d1-f70a-48a7-9f4b-e0ad92598e92', 'Artificial Intelligence', 'MASTER', 'Artificial Intelligence', NULL, 'https://csd.auth.gr/en/');

INSERT INTO admission_requirements (requirement_id, program_id, minimum_cgpa_percentage, official_funds_requirement_eur, language_test_name, minimum_language_score, required_documents, source_url, source_checked_on, notes) VALUES
    ('10683f77-3ec0-45a3-8c9d-759c12c47622', '86a61787-c618-42e8-bf50-f3f7f787cfad', NULL, NULL, NULL, NULL, NULL, 'https://dsml.ece.ntua.gr/', '2026-08-23', 'Confirmed only that this interdepartmental MSc programme (School of Electrical & Computer Engineering) exists under this title. Degree-level detail, admission GPA/English-test thresholds, and a document checklist could not be confirmed — the programme page did not render this content via direct fetch within a deliberately capped research budget for this batch.'),
    ('0f0c8f4c-5176-4260-b004-40b5a77a3f64', '30b96861-2ba4-462c-9059-9f9eedda084c', NULL, NULL, NULL, NULL, NULL, 'https://csd.auth.gr/en/', '2026-08-23', 'AUTh''s School of Informatics confirmed to offer 5 MSc programmes including "Artificial Intelligence" and "Data and Web Science" — this row covers the Artificial Intelligence title. Admission GPA/English-test thresholds and a dedicated per-programme URL could not be confirmed within a deliberately capped research budget for this batch.');

INSERT INTO scholarships (scholarship_id, name, provider, country_code, university_id, program_id, coverage_type, amount_eur, eligibility_notes, application_deadline, application_url, source_url, source_checked_on) VALUES
    ('8a52fd17-6e44-42aa-84b4-9e0327b1eed1', 'IKY Postgraduate Scholarships', 'IKY (Greek State Scholarships Foundation)', 'GR', NULL, NULL, 'PARTIAL_TUITION', NULL, 'IKY confirmed to run several postgraduate-relevant programmes, including "IKY-Fulbright," "IKY-Max Weber" (2026-2027 postgraduate call), and the "Theodorideio Bequest Scholarships for Postgraduate Studies Abroad" (2025-2026 call) — award amounts were not stated on the page fetched and are left NULL rather than guessed.', NULL, NULL, 'https://www.iky.gr/en/', '2026-08-23');
