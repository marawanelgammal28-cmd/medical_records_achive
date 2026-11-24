-- Project 7: Medical Records Archive
-- Phase 1 relational schema draft for PostgreSQL / Supabase
-- Align with the team's final ER diagram and approved attributes before running.
-- This file creates tables and constraints; it does NOT configure RLS policies.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE role (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name VARCHAR(30) NOT NULL UNIQUE
        CHECK (role_name IN ('doctor','nurse','archive_admin','receptionist','system_admin')),
    description VARCHAR(200)
);

CREATE TABLE patient (
    patient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_number VARCHAR(30) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    phone VARCHAR(30),
    email VARCHAR(254),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE staff_user (
    user_id UUID PRIMARY KEY, -- Use the corresponding Supabase Auth UUID
    employee_id VARCHAR(30) NOT NULL UNIQUE,
    role_id UUID NOT NULL REFERENCES role(role_id) ON DELETE RESTRICT,
    email VARCHAR(254) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE retention_policy (
    policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_name VARCHAR(80) NOT NULL UNIQUE,
    record_category VARCHAR(40) NOT NULL,
    retention_period_months INTEGER NOT NULL CHECK (retention_period_months > 0),
    review_interval_months INTEGER NOT NULL DEFAULT 12 CHECK (review_interval_months > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE medical_record (
    record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    created_by UUID NOT NULL REFERENCES staff_user(user_id) ON DELETE RESTRICT,
    policy_id UUID REFERENCES retention_policy(policy_id) ON DELETE SET NULL,
    record_type VARCHAR(40) NOT NULL,
    diagnosis TEXT,
    clinical_notes TEXT,
    record_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (record_status IN ('active','archived','under_review')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE archive_entry (
    archive_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    record_id UUID NOT NULL REFERENCES medical_record(record_id) ON DELETE RESTRICT,
    archived_by UUID NOT NULL REFERENCES staff_user(user_id) ON DELETE RESTRICT,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archive_reason VARCHAR(300) NOT NULL,
    archive_status VARCHAR(20) NOT NULL DEFAULT 'archived'
        CHECK (archive_status IN ('archived','retrieved')),
    retrieved_at TIMESTAMPTZ,
    retrieved_by UUID REFERENCES staff_user(user_id) ON DELETE SET NULL,
    CONSTRAINT chk_retrieval_details CHECK (
        (archive_status = 'archived' AND retrieved_at IS NULL)
        OR (archive_status = 'retrieved' AND retrieved_at IS NOT NULL)
    )
);

CREATE TABLE erasure_request (
    request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    submitted_by UUID NOT NULL REFERENCES staff_user(user_id) ON DELETE RESTRICT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_reason TEXT,
    request_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (request_status IN ('pending','approved','rejected','more_info','completed')),
    reviewed_by UUID REFERENCES staff_user(user_id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    decision_reason TEXT,
    completed_at TIMESTAMPTZ
);

CREATE TABLE audit_log (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID NOT NULL REFERENCES staff_user(user_id) ON DELETE RESTRICT,
    record_id UUID REFERENCES medical_record(record_id) ON DELETE SET NULL,
    action VARCHAR(60) NOT NULL,
    target_type VARCHAR(40) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    outcome VARCHAR(20) NOT NULL DEFAULT 'success'
        CHECK (outcome IN ('success','denied','failed')),
    details TEXT
);

-- Relational algebra example 1: π patient_id, full_name (PATIENT)
SELECT patient_id, full_name FROM patient;

-- Relational algebra example 2: σ patient_id = requested_id (MEDICAL_RECORD)
-- Bind :requested_patient_id as a parameter in the application/query tool.
SELECT record_id, record_type, record_status, created_at
FROM medical_record
WHERE patient_id = :requested_patient_id;

-- Relational algebra example 3:
-- π record_id, patient_id, record_type (σ record_status = 'archived' (MEDICAL_RECORD))
SELECT record_id, patient_id, record_type
FROM medical_record
WHERE record_status = 'archived';

-- Security reminder:
-- Enable and configure Row-Level Security on every exposed table before app access.
-- Never place the Supabase service_role key in the Flutter application.
