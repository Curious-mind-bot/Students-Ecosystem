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
