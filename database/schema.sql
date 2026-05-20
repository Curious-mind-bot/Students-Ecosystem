CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    passport_country VARCHAR(100) NOT NULL,
    cgpa_percentage NUMERIC(5,2) NOT NULL,
    has_dependent_child BOOLEAN DEFAULT FALSE,
    max_liquid_savings_usd INT DEFAULT 0
);

CREATE TABLE professor_lor_requests (
    request_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE CASCADE,
    professor_name VARCHAR(150) NOT NULL,
    professor_email VARCHAR(150) NOT NULL,
    university_affiliation VARCHAR(200) NOT NULL,
    secure_access_token VARCHAR(64) UNIQUE NOT NULL,
    request_status VARCHAR(30) DEFAULT 'Pending_Request'
);

CREATE TABLE applications_tracker (
    application_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE CASCADE,
    university_name VARCHAR(200) NOT NULL,
    program_title VARCHAR(200) NOT NULL,
    current_milestone VARCHAR(50) DEFAULT 'Document_Verification'
);

CREATE TABLE partner_conversions (
    conversion_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE SET NULL,
    unique_tracking_token VARCHAR(255) UNIQUE NOT NULL,
    expected_payout_eur NUMERIC(6,2) NOT NULL,
    conversion_status VARCHAR(50) DEFAULT 'Lead_Generated'
);
