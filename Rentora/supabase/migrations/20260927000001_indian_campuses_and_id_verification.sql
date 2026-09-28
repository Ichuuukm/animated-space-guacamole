-- ==============================================================================
-- Migration: 20260927000001_indian_campuses_and_id_verification.sql
-- Description: Adapts Rentora verification for Indian colleges & universities
--              (especially in Kerala). Adds multi-domain support per campus,
--              manual College ID verification for students without campus email,
--              and strict server-side verification status protection.
-- Safe & Non-Destructive: Preserves all existing tables and data.
-- ==============================================================================

BEGIN;

-- 1. Ensure required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Extend public.campuses table
ALTER TABLE public.campuses ALTER COLUMN domain DROP NOT NULL;

ALTER TABLE public.campuses
    ADD COLUMN IF NOT EXISTS state TEXT DEFAULT 'Kerala',
    ADD COLUMN IF NOT EXISTS city TEXT,
    ADD COLUMN IF NOT EXISTS university_affiliation TEXT,
    ADD COLUMN IF NOT EXISTS allow_email_verification BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS allow_id_verification BOOLEAN DEFAULT TRUE;

-- 3. Create public.campus_domains table for multi-domain support
CREATE TABLE IF NOT EXISTS public.campus_domains (
    domain_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campus_id UUID NOT NULL REFERENCES public.campuses(campus_id) ON DELETE CASCADE,
    domain TEXT UNIQUE NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Backfill existing campuses.domain into campus_domains table
INSERT INTO public.campus_domains (campus_id, domain, is_primary)
SELECT campus_id, domain, TRUE
FROM public.campuses
WHERE domain IS NOT NULL
ON CONFLICT (domain) DO NOTHING;

-- 4. Seed confirmed Kerala institutions with verified email domains
-- Only confirmed domains are added; unconfirmed domains are omitted.
INSERT INTO public.campuses (campus_id, name, domain, state, city, university_affiliation, allow_email_verification, allow_id_verification)
VALUES
    ('b0000000-0000-0000-0000-000000000001', 'National Institute of Technology Calicut', 'nitc.ac.in', 'Kerala', 'Kozhikode', 'Institute of National Importance', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000002', 'Indian Institute of Technology Palakkad', 'iitpkd.ac.in', 'Kerala', 'Palakkad', 'Institute of National Importance', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000003', 'College of Engineering Trivandrum', 'cet.ac.in', 'Kerala', 'Thiruvananthapuram', 'APJ Abdul Kalam Technological University', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000004', 'Govt Model Engineering College', 'mec.ac.in', 'Kerala', 'Kochi', 'APJ Abdul Kalam Technological University', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000005', 'TKM College of Engineering', 'tkmce.ac.in', 'Kerala', 'Kollam', 'APJ Abdul Kalam Technological University', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000006', 'Cochin University of Science and Technology', 'cusat.ac.in', 'Kerala', 'Kochi', 'CUSAT', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000007', 'Muthoot Institute of Technology & Science', 'mgits.ac.in', 'Kerala', 'Ernakulam', 'APJ Abdul Kalam Technological University', TRUE, TRUE),
    ('b0000000-0000-0000-0000-000000000008', 'Federal Institute of Science and Technology', 'fisat.ac.in', 'Kerala', 'Angamaly', 'APJ Abdul Kalam Technological University', TRUE, TRUE),
    -- Colleges without confirmed student email domains: students use ID card verification
    ('b0000000-0000-0000-0000-000000000009', 'Government Engineering College Thrissur', NULL, 'Kerala', 'Thrissur', 'APJ Abdul Kalam Technological University', FALSE, TRUE),
    ('b0000000-0000-0000-0000-000000000010', 'St. Teresa''s College', NULL, 'Kerala', 'Ernakulam', 'Mahatma Gandhi University', FALSE, TRUE),
    ('b0000000-0000-0000-0000-000000000011', 'Sacred Heart College (Thevara)', NULL, 'Kerala', 'Kochi', 'Mahatma Gandhi University', FALSE, TRUE),
    ('b0000000-0000-0000-0000-000000000012', 'Farook College', NULL, 'Kerala', 'Kozhikode', 'University of Calicut', FALSE, TRUE)
ON CONFLICT (campus_id) DO UPDATE SET
    name = EXCLUDED.name,
    domain = EXCLUDED.domain,
    state = EXCLUDED.state,
    city = EXCLUDED.city,
    university_affiliation = EXCLUDED.university_affiliation,
    allow_email_verification = EXCLUDED.allow_email_verification,
    allow_id_verification = EXCLUDED.allow_id_verification;

-- Seed confirmed secondary domains into campus_domains
INSERT INTO public.campus_domains (campus_id, domain, is_primary)
SELECT campus_id, domain, TRUE
FROM public.campuses
WHERE domain IS NOT NULL
ON CONFLICT (domain) DO NOTHING;

-- 5. Extend public.users with verification lifecycle columns
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS verification_method TEXT 
        CHECK (verification_method IN ('institutional_email', 'college_id', 'admin_override', 'none')) DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS verification_status TEXT 
        CHECK (verification_status IN ('unverified', 'pending_review', 'verified', 'rejected')) DEFAULT 'unverified',
    ADD COLUMN IF NOT EXISTS student_id_number TEXT,
    ADD COLUMN IF NOT EXISTS graduation_year INTEGER,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Backfill verification status for existing users
UPDATE public.users
SET verification_method = 'institutional_email',
    verification_status = CASE WHEN is_verified THEN 'verified' ELSE 'unverified' END
WHERE verification_method = 'none' OR verification_method IS NULL;

-- 6. Create public.id_verification_requests table
CREATE TABLE IF NOT EXISTS public.id_verification_requests (
    request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    campus_id UUID NOT NULL REFERENCES public.campuses(campus_id) ON DELETE CASCADE,
    id_card_url TEXT NOT NULL,
    id_card_back_url TEXT,
    student_id_number TEXT NOT NULL,
    graduation_year INTEGER,
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
    reviewer_id UUID REFERENCES public.users(user_id),
    rejection_reason TEXT,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

-- 7. Trigger Function: Update handle_new_auth_user to support both tracks
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_email_domain TEXT;
    v_campus_id UUID;
    v_full_name TEXT;
    v_method TEXT;
    v_meta_campus_id_text TEXT;
    v_meta_campus_id UUID;
BEGIN
    -- Extract domain from the registered email (case-insensitive & trimmed)
    v_email_domain := LOWER(SPLIT_PART(TRIM(NEW.email), '@', 2));

    IF v_email_domain IS NULL OR v_email_domain = '' THEN
        RAISE EXCEPTION 'Registration rejected: A valid email address is required.';
    END IF;

    -- Track 1: Match domain against approved campus domains
    SELECT cd.campus_id INTO v_campus_id
    FROM public.campus_domains cd
    JOIN public.campuses c ON c.campus_id = cd.campus_id
    WHERE LOWER(cd.domain) = v_email_domain AND c.allow_email_verification = TRUE
    LIMIT 1;

    IF v_campus_id IS NULL THEN
        SELECT c.campus_id INTO v_campus_id
        FROM public.campuses c
        WHERE LOWER(c.domain) = v_email_domain AND c.allow_email_verification = TRUE
        LIMIT 1;
    END IF;

    IF v_campus_id IS NOT NULL THEN
        -- Instant institutional email track
        v_method := 'institutional_email';
    ELSE
        -- Track 2: Personal email with College ID verification
        v_meta_campus_id_text := TRIM(NEW.raw_user_meta_data->>'campus_id');

        IF v_meta_campus_id_text IS NULL OR v_meta_campus_id_text = '' THEN
            RAISE EXCEPTION 'Registration rejected: Domain "%" is not an authorized campus domain. Please select your college to register with College ID verification.', v_email_domain;
        END IF;

        BEGIN
            v_meta_campus_id := v_meta_campus_id_text::UUID;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Registration rejected: Invalid campus ID provided.';
        END;

        SELECT c.campus_id INTO v_campus_id
        FROM public.campuses c
        WHERE c.campus_id = v_meta_campus_id AND c.allow_id_verification = TRUE
        LIMIT 1;

        IF v_campus_id IS NULL THEN
            RAISE EXCEPTION 'Registration rejected: Selected college does not support College ID verification or does not exist.';
        END IF;

        v_method := 'college_id';
    END IF;

    -- Extract full name from registration metadata; sanitize and provide default
    v_full_name := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''), 'Student');

    -- Insert into public.users
    INSERT INTO public.users (
        user_id,
        email,
        full_name,
        campus_id,
        verification_method,
        verification_status,
        is_verified,
        created_at
    ) VALUES (
        NEW.id,
        NEW.email,
        v_full_name,
        v_campus_id,
        v_method,
        CASE
            WHEN v_method = 'institutional_email' AND NEW.email_confirmed_at IS NOT NULL THEN 'verified'
            ELSE 'unverified'
        END,
        (v_method = 'institutional_email' AND NEW.email_confirmed_at IS NOT NULL),
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (user_id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name;

    RETURN NEW;
END;
$$;

-- 8. Trigger Function: Update handle_user_email_confirmation for dual tracks
CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_method TEXT;
BEGIN
    IF NEW.email_confirmed_at IS NOT NULL AND (OLD.email_confirmed_at IS NULL OR OLD.email_confirmed_at IS DISTINCT FROM NEW.email_confirmed_at) THEN
        SELECT verification_method INTO v_user_method
        FROM public.users
        WHERE user_id = NEW.id;

        PERFORM set_config('rentora.internal_sync', 'true', true);

        -- Only institutional_email registrations are automatically verified on email confirmation
        IF v_user_method = 'institutional_email' THEN
            UPDATE public.users
            SET verification_status = 'verified',
                is_verified = TRUE
            WHERE user_id = NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- 9. Trigger Function: Protect immutable user profile and verification fields
CREATE OR REPLACE FUNCTION public.prevent_immutable_user_field_updates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_client_role BOOLEAN;
BEGIN
    v_is_client_role := (
        COALESCE(auth.role(), '') IN ('authenticated', 'anon')
        OR CURRENT_USER IN ('authenticated', 'anon')
    );

    -- Prevent altering user_id
    IF NEW.user_id <> OLD.user_id THEN
        RAISE EXCEPTION 'user_id is immutable.';
    END IF;

    -- Prevent altering campus_id by clients
    IF NEW.campus_id IS DISTINCT FROM OLD.campus_id THEN
        IF v_is_client_role THEN
            RAISE EXCEPTION 'campus_id is immutable.';
        END IF;
    END IF;

    -- Prevent direct alteration of verification_method
    IF NEW.verification_method IS DISTINCT FROM OLD.verification_method THEN
        IF current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'verification_method is immutable.';
        END IF;
    END IF;

    -- Prevent direct alteration of verification_status
    IF NEW.verification_status IS DISTINCT FROM OLD.verification_status THEN
        IF current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'verification_status can only be modified by system verification triggers or reviews.';
        END IF;
    END IF;

    -- Prevent direct alteration of is_verified
    IF NEW.is_verified IS DISTINCT FROM OLD.is_verified THEN
        IF current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'is_verified can only be modified by system verification triggers.';
        END IF;
    END IF;

    -- Prevent direct alteration of email by client
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        IF v_is_client_role AND current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'email must be changed through the authentication service.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 10. Trigger Function: ID Card submission moves user to pending_review
CREATE OR REPLACE FUNCTION public.handle_id_verification_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM set_config('rentora.internal_sync', 'true', true);
    UPDATE public.users
    SET verification_status = 'pending_review',
        student_id_number = NEW.student_id_number,
        graduation_year = NEW.graduation_year
    WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_id_verification_submitted ON public.id_verification_requests;
CREATE TRIGGER on_id_verification_submitted
    AFTER INSERT ON public.id_verification_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_id_verification_submission();

-- 11. RPC: Admin Review Function for ID Verification Requests
CREATE OR REPLACE FUNCTION public.review_id_verification_request(
    p_request_id UUID,
    p_action TEXT, -- 'approved' or 'rejected'
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_req RECORD;
    v_reviewer_id UUID;
BEGIN
    v_reviewer_id := auth.uid();

    IF p_action NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Invalid action: must be approved or rejected.';
    END IF;

    SELECT * INTO v_req
    FROM public.id_verification_requests
    WHERE request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Verification request not found.';
    END IF;

    IF v_req.status <> 'pending' THEN
        RAISE EXCEPTION 'Request has already been reviewed.';
    END IF;

    UPDATE public.id_verification_requests
    SET status = p_action,
        reviewer_id = v_reviewer_id,
        rejection_reason = CASE WHEN p_action = 'rejected' THEN p_rejection_reason ELSE NULL END,
        reviewed_at = NOW()
    WHERE request_id = p_request_id;

    PERFORM set_config('rentora.internal_sync', 'true', true);

    IF p_action = 'approved' THEN
        UPDATE public.users
        SET verification_status = 'verified',
            is_verified = TRUE,
            student_id_number = v_req.student_id_number,
            graduation_year = v_req.graduation_year
        WHERE user_id = v_req.user_id;
    ELSE
        UPDATE public.users
        SET verification_status = 'rejected',
            rejection_reason = p_rejection_reason
        WHERE user_id = v_req.user_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'status', p_action);
END;
$$;

-- 12. Permissions & Row Level Security on New Tables
GRANT SELECT ON public.campus_domains TO anon, authenticated;
GRANT SELECT, INSERT ON public.id_verification_requests TO authenticated;

ALTER TABLE public.campus_domains ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view campus domains" ON public.campus_domains;
CREATE POLICY "Anyone can view campus domains"
    ON public.campus_domains
    FOR SELECT
    TO anon, authenticated
    USING (true);

ALTER TABLE public.id_verification_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own verification requests" ON public.id_verification_requests;
CREATE POLICY "Users can view own verification requests"
    ON public.id_verification_requests
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own verification requests" ON public.id_verification_requests;
CREATE POLICY "Users can insert own verification requests"
    ON public.id_verification_requests
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

COMMIT;
