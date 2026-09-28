-- ==============================================================================
-- Migration: 20260927000000_institutional_auth_and_security.sql
-- Description: Enforces authoritative server-side institutional email verification,
--              automated campus mapping, user profile creation, immutable user fields,
--              and Row Level Security (RLS) policies for Rentora.
-- Safe & Non-Destructive: Preserves all existing data.
-- ==============================================================================

BEGIN;

-- 1. Ensure required extensions exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Ensure UNIQUE constraint on campuses.domain for idempotent seeding & conflict resolution
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'campuses'
          AND con.contype = 'u'
          AND ARRAY['domain'::name] <@ (
              SELECT array_agg(att.attname)
              FROM pg_attribute att
              WHERE att.attrelid = con.conrelid
                AND att.attnum = ANY(con.conkey)
          )
    ) THEN
        ALTER TABLE public.campuses ADD CONSTRAINT campuses_domain_key UNIQUE (domain);
    END IF;
END $$;

-- 3. Seed initial approved campus registry if not already present
-- These serve as the authoritative whitelist for institutional domains.
INSERT INTO public.campuses (campus_id, name, domain)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Stanford University', 'stanford.edu'),
    ('a0000000-0000-0000-0000-000000000002', 'Massachusetts Institute of Technology', 'mit.edu'),
    ('a0000000-0000-0000-0000-000000000003', 'University of California, Berkeley', 'berkeley.edu'),
    ('a0000000-0000-0000-0000-000000000004', 'University of Oxford', 'ox.ac.uk'),
    ('a0000000-0000-0000-0000-000000000005', 'University of Cambridge', 'cam.ac.uk'),
    ('a0000000-0000-0000-0000-000000000006', 'Indian Institute of Technology Delhi', 'iitd.ac.in')
ON CONFLICT (domain) DO UPDATE
SET name = EXCLUDED.name;

-- 4. Trigger Function: Validate institutional email and provision user profile
-- Runs with SECURITY DEFINER and fixed search_path to prevent escalation.
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
BEGIN
    -- Extract domain from the registered email (case-insensitive & trimmed)
    v_email_domain := LOWER(SPLIT_PART(TRIM(NEW.email), '@', 2));

    IF v_email_domain IS NULL OR v_email_domain = '' THEN
        RAISE EXCEPTION 'Registration rejected: A valid institutional email is required.';
    END IF;

    -- Query authoritative campuses registry for domain match
    SELECT campus_id INTO v_campus_id
    FROM public.campuses
    WHERE LOWER(domain) = v_email_domain
    LIMIT 1;

    -- Reject registration if domain is not registered in campuses table
    IF v_campus_id IS NULL THEN
        RAISE EXCEPTION 'Registration rejected: Domain "%" is not an authorized institutional campus domain.', v_email_domain;
    END IF;

    -- Extract full name from registration metadata; sanitize and provide default
    v_full_name := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''), 'Student');

    -- Insert into public.users
    -- Note: campus_id is assigned strictly from the authoritative database match,
    -- completely ignoring any client-provided campus_id in raw_user_meta_data.
    INSERT INTO public.users (
        user_id,
        email,
        full_name,
        campus_id,
        is_verified,
        created_at
    ) VALUES (
        NEW.id,
        NEW.email,
        v_full_name,
        v_campus_id,
        (NEW.email_confirmed_at IS NOT NULL),
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (user_id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name;

    RETURN NEW;
END;
$$;

-- 5. Attach trigger to auth.users for new registrations
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

-- 6. Trigger Function: Sync Supabase email confirmation to public.users.is_verified
CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    IF NEW.email_confirmed_at IS NOT NULL AND (OLD.email_confirmed_at IS NULL OR OLD.email_confirmed_at IS DISTINCT FROM NEW.email_confirmed_at) THEN
        PERFORM set_config('rentora.internal_sync', 'true', true);
        UPDATE public.users
        SET is_verified = TRUE
        WHERE user_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_confirmed
    AFTER UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_email_confirmation();

-- 7. Trigger Function: Prevent tampering with immutable user profile fields
-- Disallows client updates to user_id, campus_id, is_verified, and email.
CREATE OR REPLACE FUNCTION public.prevent_immutable_user_field_updates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_client_role BOOLEAN;
BEGIN
    -- Determine if caller is a client role (authenticated or anon)
    v_is_client_role := (
        COALESCE(auth.role(), '') IN ('authenticated', 'anon')
        OR CURRENT_USER IN ('authenticated', 'anon')
    );

    -- Prevent altering user_id (always immutable)
    IF NEW.user_id <> OLD.user_id THEN
        RAISE EXCEPTION 'user_id is immutable.';
    END IF;

    -- Prevent altering campus_id by clients
    IF NEW.campus_id IS DISTINCT FROM OLD.campus_id THEN
        IF v_is_client_role THEN
            RAISE EXCEPTION 'campus_id is immutable and derived strictly from institutional email.';
        END IF;
    END IF;

    -- Prevent direct alteration of is_verified by client
    IF NEW.is_verified IS DISTINCT FROM OLD.is_verified THEN
        IF current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'is_verified can only be modified by system verification triggers.';
        END IF;
    END IF;

    -- Prevent direct alteration of email by client (must use auth email change)
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        IF v_is_client_role AND current_setting('rentora.internal_sync', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'email must be changed through the authentication service.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_user_profile_update ON public.users;
CREATE TRIGGER on_user_profile_update
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_immutable_user_field_updates();

-- 8. Table Permissions (Ensure API access before RLS filters)
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.campuses TO anon, authenticated;
GRANT SELECT, UPDATE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.items TO authenticated;
GRANT SELECT ON public.items TO anon;

-- 9. Row Level Security: public.campuses
ALTER TABLE public.campuses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view campuses" ON public.campuses;
CREATE POLICY "Anyone can view campuses"
    ON public.campuses
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 10. Row Level Security: public.users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile" ON public.users;
CREATE POLICY "Users can view own profile"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
CREATE POLICY "Users can update own profile"
    ON public.users
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Note: No direct INSERT or DELETE policies exist for authenticated/anon on public.users.
-- User profile creation is exclusively managed by the SECURITY DEFINER trigger.

-- 11. Row Level Security: public.items (Marketplace Gate)
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active items" ON public.items;
CREATE POLICY "Anyone can view active items"
    ON public.items
    FOR SELECT
    TO anon, authenticated
    USING (status = 'active' OR status IS NULL);

DROP POLICY IF EXISTS "Verified users can insert own items" ON public.items;
CREATE POLICY "Verified users can insert own items"
    ON public.items
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = owner_id
        AND EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.user_id = auth.uid()
            AND u.is_verified = true
        )
    );

DROP POLICY IF EXISTS "Users can update own items" ON public.items;
CREATE POLICY "Users can update own items"
    ON public.items
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Users can delete own items" ON public.items;
CREATE POLICY "Users can delete own items"
    ON public.items
    FOR DELETE
    TO authenticated
    USING (auth.uid() = owner_id);

COMMIT;
