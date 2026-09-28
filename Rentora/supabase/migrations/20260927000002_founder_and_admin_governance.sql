-- ==============================================================================
-- Migration: 20260927000002_founder_and_admin_governance.sql
-- Description: Implements Founder-Controlled Multi-Super-Admin Architecture,
--              single Founder invariant, immutable audit logs, and authorized
--              student verification gating for Rentora.
-- Safe & Non-Destructive: Preserves all existing tables and data.
-- ==============================================================================

BEGIN;

-- 1. Ensure required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Create public.admin_roles table
CREATE TABLE IF NOT EXISTS public.admin_roles (
    admin_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('founder', 'super_admin', 'college_admin')),
    college_id UUID REFERENCES public.campuses(campus_id), -- Reserved for Level 3 scoping
    assigned_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Strict Invariant: Exactly one active Founder account allowed across the entire system
CREATE UNIQUE INDEX IF NOT EXISTS only_one_founder_idx 
    ON public.admin_roles ((1)) 
    WHERE (role = 'founder');

-- 3. Create public.admin_audit_logs table (Strictly append-only)
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID NOT NULL REFERENCES auth.users(id),
    action TEXT NOT NULL,
    target_type TEXT NOT NULL, -- 'user', 'verification_request', 'item', 'campus', 'admin_role'
    target_id UUID NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Revoke UPDATE and DELETE on audit logs for everyone to guarantee append-only immutability
REVOKE UPDATE, DELETE ON public.admin_audit_logs FROM PUBLIC, anon, authenticated;

-- 4. Authorization Helper Functions
CREATE OR REPLACE FUNCTION public.is_founder(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.admin_roles
        WHERE user_id = p_user_id AND role = 'founder'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.admin_roles
        WHERE user_id = p_user_id AND role IN ('founder', 'super_admin')
    );
$$;

-- 5. Founder Initialization Procedure
-- One-time bootstrap: Can only be called if NO founder exists in the database.
CREATE OR REPLACE FUNCTION public.initialize_founder(p_user_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_target_user_id UUID;
BEGIN
    v_caller_id := auth.uid();
    v_target_user_id := COALESCE(p_user_id, v_caller_id);

    IF v_target_user_id IS NULL THEN
        RAISE EXCEPTION 'Founder initialization failed: No user ID provided.';
    END IF;

    -- Verify target user exists in auth.users
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_target_user_id) THEN
        RAISE EXCEPTION 'Founder initialization failed: Target user does not exist in auth.users.';
    END IF;

    -- Assert that no Founder exists in the system
    IF EXISTS (SELECT 1 FROM public.admin_roles WHERE role = 'founder') THEN
        RAISE EXCEPTION 'Founder initialization failed: A Founder account is already initialized.';
    END IF;

    -- Insert the initial Founder
    INSERT INTO public.admin_roles (user_id, role, assigned_by)
    VALUES (v_target_user_id, 'founder', v_target_user_id)
    ON CONFLICT (user_id) DO UPDATE SET role = 'founder';

    -- Record in audit log
    INSERT INTO public.admin_audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (
        v_target_user_id,
        'INITIALIZE_FOUNDER',
        'admin_role',
        v_target_user_id,
        jsonb_build_object('role', 'founder', 'initialized_at', now())
    );

    RETURN jsonb_build_object('success', true, 'message', 'Founder successfully initialized.', 'user_id', v_target_user_id);
END;
$$;

-- 6. Founder-Only Governance Procedures
-- A. Promote to Super Admin
CREATE OR REPLACE FUNCTION public.promote_to_super_admin(p_target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
BEGIN
    v_caller_id := auth.uid();

    IF NOT public.is_founder(v_caller_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only the Founder can promote Super Admins.';
    END IF;

    IF p_target_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid target user ID.';
    END IF;

    -- Target must exist in auth.users
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
        RAISE EXCEPTION 'Target user does not exist.';
    END IF;

    -- Target cannot already be Founder
    IF public.is_founder(p_target_user_id) THEN
        RAISE EXCEPTION 'Target user is already the Founder.';
    END IF;

    INSERT INTO public.admin_roles (user_id, role, assigned_by, updated_at)
    VALUES (p_target_user_id, 'super_admin', v_caller_id, now())
    ON CONFLICT (user_id) DO UPDATE SET
        role = 'super_admin',
        assigned_by = v_caller_id,
        updated_at = now();

    -- Log action (PII-free)
    INSERT INTO public.admin_audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (
        v_caller_id,
        'PROMOTE_SUPER_ADMIN',
        'admin_role',
        p_target_user_id,
        jsonb_build_object('promoted_by', v_caller_id)
    );

    RETURN jsonb_build_object('success', true, 'message', 'User promoted to Super Admin.');
END;
$$;

-- B. Demote Super Admin
CREATE OR REPLACE FUNCTION public.demote_super_admin(p_target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
BEGIN
    v_caller_id := auth.uid();

    IF NOT public.is_founder(v_caller_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only the Founder can demote Super Admins.';
    END IF;

    -- Protection: Founder cannot be demoted via demote_super_admin
    IF public.is_founder(p_target_user_id) THEN
        RAISE EXCEPTION 'The Founder account cannot be demoted or removed. Use transfer_founder_authority instead.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = p_target_user_id AND role = 'super_admin') THEN
        RAISE EXCEPTION 'Target user is not a Super Admin.';
    END IF;

    DELETE FROM public.admin_roles
    WHERE user_id = p_target_user_id AND role = 'super_admin';

    -- Log action
    INSERT INTO public.admin_audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (
        v_caller_id,
        'DEMOTE_SUPER_ADMIN',
        'admin_role',
        p_target_user_id,
        jsonb_build_object('demoted_by', v_caller_id)
    );

    RETURN jsonb_build_object('success', true, 'message', 'Super Admin demoted successfully.');
END;
$$;

-- C. Transfer Founder Authority (Atomic transfer)
CREATE OR REPLACE FUNCTION public.transfer_founder_authority(p_new_founder_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
BEGIN
    v_caller_id := auth.uid();

    IF NOT public.is_founder(v_caller_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only the current Founder can transfer Founder authority.';
    END IF;

    IF p_new_founder_user_id IS NULL OR p_new_founder_user_id = v_caller_id THEN
        RAISE EXCEPTION 'Invalid new Founder user ID: must be a different active user.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_new_founder_user_id) THEN
        RAISE EXCEPTION 'New Founder user does not exist.';
    END IF;

    -- Step 1: Demote existing founder to super_admin
    UPDATE public.admin_roles
    SET role = 'super_admin',
        updated_at = now()
    WHERE user_id = v_caller_id AND role = 'founder';

    -- Step 2: Promote new user to founder
    INSERT INTO public.admin_roles (user_id, role, assigned_by, updated_at)
    VALUES (p_new_founder_user_id, 'founder', v_caller_id, now())
    ON CONFLICT (user_id) DO UPDATE SET
        role = 'founder',
        assigned_by = v_caller_id,
        updated_at = now();

    -- Log transfer
    INSERT INTO public.admin_audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (
        v_caller_id,
        'TRANSFER_FOUNDER_AUTHORITY',
        'admin_role',
        p_new_founder_user_id,
        jsonb_build_object('previous_founder', v_caller_id, 'new_founder', p_new_founder_user_id)
    );

    RETURN jsonb_build_object('success', true, 'message', 'Founder authority transferred successfully.');
END;
$$;

-- 7. Updated Student ID Review Procedure (Restricted to Authorized Admins + Audit Logged)
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

    -- Explicit Authorization Gate: Must be an authorized Super Admin or Founder
    IF NOT public.is_super_admin(v_reviewer_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only authorized Rentora administrators can verify student IDs.';
    END IF;

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

    -- Record in append-only audit log (sanitize PII; do not log raw image URLs)
    INSERT INTO public.admin_audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (
        v_reviewer_id,
        CASE WHEN p_action = 'approved' THEN 'APPROVE_STUDENT_ID' ELSE 'REJECT_STUDENT_ID' END,
        'verification_request',
        p_request_id,
        jsonb_build_object(
            'student_user_id', v_req.user_id,
            'campus_id', v_req.campus_id,
            'status', p_action,
            'rejection_reason', CASE WHEN p_action = 'rejected' THEN p_rejection_reason ELSE NULL END
        )
    );

    RETURN jsonb_build_object('success', true, 'status', p_action);
END;
$$;

-- 8. Table Permissions & Row Level Security
GRANT SELECT ON public.admin_roles TO authenticated;
GRANT SELECT ON public.admin_audit_logs TO authenticated;

ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

-- Admins can view administrative roles
DROP POLICY IF EXISTS "Admins can view admin roles" ON public.admin_roles;
CREATE POLICY "Admins can view admin roles"
    ON public.admin_roles
    FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()));

-- Admins can view audit logs
DROP POLICY IF EXISTS "Admins can view audit logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can view audit logs"
    ON public.admin_audit_logs
    FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()));

-- No direct INSERT, UPDATE, DELETE policies on admin_roles or admin_audit_logs.
-- All mutations are performed via authorized SECURITY DEFINER functions.

COMMIT;
