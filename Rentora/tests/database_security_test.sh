#!/bin/bash
set -e

echo "=== Rentora Database Security, Verification & Governance Test Suite ==="

# Database execution helper
run_sql() {
    docker exec -i rentora-test-db psql -U postgres -v ON_ERROR_STOP=1 "$@"
}

run_sql_tolerant() {
    docker exec -i rentora-test-db psql -U postgres "$@"
}

echo "1. Initializing Base Schema & Supabase Mock Environment..."

run_sql << 'EOF'
-- Clean slate
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA public;
CREATE SCHEMA auth;

-- Roles mock
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated;
    END IF;
END $$;

-- auth helper functions mocking Supabase Auth environment
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text AS $$
    SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')::text;
$$ LANGUAGE sql STABLE;

-- auth.users table mock
CREATE TABLE auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text UNIQUE,
    raw_user_meta_data jsonb,
    email_confirmed_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Existing public schema tables before migration
CREATE TABLE public.campuses (
    campus_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    domain text UNIQUE
);

CREATE TABLE public.users (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email text NOT NULL,
    full_name text,
    campus_id uuid REFERENCES public.campuses(campus_id),
    created_at timestamptz DEFAULT now(),
    is_verified boolean DEFAULT false
);

CREATE TABLE public.items (
    item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    description text,
    owner_id uuid REFERENCES public.users(user_id) ON DELETE CASCADE,
    sale_price numeric,
    is_for_sale boolean DEFAULT false,
    is_for_rent boolean DEFAULT false,
    is_for_swap boolean DEFAULT false,
    department text,
    course_code text,
    swap_preferences text,
    status text DEFAULT 'active',
    created_at timestamptz DEFAULT now()
);

-- Grant schema permissions to test roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
EOF

echo "Base schema setup complete."

echo "2. Applying Migration 1 (20260927000000_institutional_auth_and_security.sql)..."
docker exec -i rentora-test-db psql -U postgres -v ON_ERROR_STOP=1 < supabase/migrations/20260927000000_institutional_auth_and_security.sql

echo "3. Applying Migration 2 (20260927000001_indian_campuses_and_id_verification.sql)..."
docker exec -i rentora-test-db psql -U postgres -v ON_ERROR_STOP=1 < supabase/migrations/20260927000001_indian_campuses_and_id_verification.sql

echo "4. Applying Migration 3 (20260927000002_founder_and_admin_governance.sql)..."
docker exec -i rentora-test-db psql -U postgres -v ON_ERROR_STOP=1 < supabase/migrations/20260927000002_founder_and_admin_governance.sql

echo "All 3 migrations applied successfully."

echo "--------------------------------------------------------"
echo "Running Verification Tests..."
echo "--------------------------------------------------------"

# Test 1, 3, 4: Approved registration, auto campus assignment, profile creation
echo "Test 1, 3, 4: Registering student with approved domain (student@stanford.edu)..."
USER1_ID="11111111-1111-1111-1111-111111111111"
run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES ('$USER1_ID', 'student@stanford.edu', '{"full_name": "Jane Stanford"}', NULL);
EOF

PROFILE1=$(run_sql -t -A -c "SELECT u.email, u.full_name, c.name, u.is_verified, u.verification_method, u.verification_status FROM public.users u JOIN public.campuses c ON u.campus_id = c.campus_id WHERE u.user_id = '$USER1_ID';")
echo "Created Profile: $PROFILE1"
if [[ "$PROFILE1" == "student@stanford.edu|Jane Stanford|Stanford University|f|institutional_email|unverified" ]]; then
    echo "PASS: Test 1, 3, 4 Passed."
else
    echo "FAIL: Expected 'student@stanford.edu|Jane Stanford|Stanford University|f|institutional_email|unverified', got '$PROFILE1'"
    exit 1
fi

# Test 2: Registration using an unapproved domain without campus selection
echo ""
echo "Test 2: Registering with unapproved domain without campus selection (attacker@gmail.com)..."
UNAPPROVED_RESULT=$(run_sql_tolerant -c "INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES ('22222222-2222-2222-2222-222222222222', 'attacker@gmail.com', '{\"full_name\": \"Attacker\"}');" 2>&1 || true)
if echo "$UNAPPROVED_RESULT" | grep -q "Registration rejected: Domain \"gmail.com\" is not an authorized campus domain"; then
    echo "PASS: Test 2 Passed (Unapproved domain without college selection was rejected)."
else
    echo "FAIL: Unapproved domain was not rejected as expected. Output was: $UNAPPROVED_RESULT"
    exit 1
fi

# Test 5: Attempt to modify campus_id via client UPDATE
echo ""
echo "Test 5: Authenticated student attempting to modify campus_id..."
MODIFY_CAMPUS_RESULT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
UPDATE public.users SET campus_id = 'a0000000-0000-0000-0000-000000000002' WHERE user_id = '$USER1_ID';
EOF
)
if echo "$MODIFY_CAMPUS_RESULT" | grep -q "campus_id is immutable"; then
    echo "PASS: Test 5 Passed (Direct campus_id tampering was blocked with exception)."
else
    echo "FAIL: campus_id modification was not blocked. Output: $MODIFY_CAMPUS_RESULT"
    exit 1
fi

# Test 6: Attempt to modify is_verified and verification_status via client UPDATE
echo ""
echo "Test 6: Authenticated student attempting to self-verify..."
MODIFY_VERIFIED_RESULT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
UPDATE public.users SET is_verified = true WHERE user_id = '$USER1_ID';
EOF
)
if echo "$MODIFY_VERIFIED_RESULT" | grep -q "is_verified can only be modified by system verification triggers"; then
    echo "PASS: Test 6a Passed (Unauthorized is_verified modification blocked)."
else
    echo "FAIL: is_verified modification was not blocked. Output: $MODIFY_VERIFIED_RESULT"
    exit 1
fi

MODIFY_STATUS_RESULT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
UPDATE public.users SET verification_status = 'verified' WHERE user_id = '$USER1_ID';
EOF
)
if echo "$MODIFY_STATUS_RESULT" | grep -q "verification_status can only be modified by system verification triggers or reviews"; then
    echo "PASS: Test 6b Passed (Unauthorized verification_status modification blocked)."
else
    echo "FAIL: verification_status modification was not blocked. Output: $MODIFY_STATUS_RESULT"
    exit 1
fi

# Test 7: Attempt to access another user's profile under RLS
echo ""
echo "Test 7: Attempting to access another user's profile under RLS..."
USER2_ID="33333333-3333-3333-3333-333333333333"
run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES ('$USER2_ID', 'scholar@mit.edu', '{"full_name": "Bob MIT"}', now());
EOF

OTHER_PROFILE_ACCESS=$(run_sql -t -A << EOF | tail -n 1
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT count(*) FROM public.users WHERE user_id = '$USER2_ID';
EOF
)
if [[ "$OTHER_PROFILE_ACCESS" == "0" ]]; then
    echo "PASS: Test 7 Passed (User 1 cannot view User 2's profile under RLS: count = 0)."
else
    echo "FAIL: User 1 was able to view User 2's profile! count = $OTHER_PROFILE_ACCESS"
    exit 1
fi

# Test 8: Unverified account marketplace access
echo ""
echo "Test 8: Unverified account attempting to insert marketplace item..."
UNVERIFIED_ITEM_ATTEMPT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
INSERT INTO public.items (title, description, owner_id, sale_price, is_for_sale)
VALUES ('TI-84 Calculator', 'Used 1 sem', '$USER1_ID', 45, true);
EOF
)
if echo "$UNVERIFIED_ITEM_ATTEMPT" | grep -q "violates row-level security policy"; then
    echo "PASS: Unverified user cannot create items (blocked by RLS policy)."
else
    echo "FAIL: Unverified user was able to insert item! Output: $UNVERIFIED_ITEM_ATTEMPT"
    exit 1
fi

# Confirm email for institutional user
run_sql -c "UPDATE auth.users SET email_confirmed_at = now() WHERE id = '$USER1_ID';"

# Test 10: Kerala Institutional Email (NIT Calicut)
echo ""
echo "Test 10: Registering Kerala student with confirmed institutional domain (arjun@nitc.ac.in)..."
NITC_USER_ID="55555555-5555-5555-5555-555555555555"
run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES ('$NITC_USER_ID', 'arjun@nitc.ac.in', '{"full_name": "Arjun K"}', now());
EOF

NITC_PROFILE=$(run_sql -t -A -c "SELECT c.name, u.verification_method, u.verification_status, u.is_verified FROM public.users u JOIN public.campuses c ON u.campus_id = c.campus_id WHERE u.user_id = '$NITC_USER_ID';")
if [[ "$NITC_PROFILE" == "National Institute of Technology Calicut|institutional_email|verified|t" ]]; then
    echo "PASS: Test 10 Passed (NITC student auto-assigned and verified upon confirmation)."
else
    echo "FAIL: Expected 'National Institute of Technology Calicut|institutional_email|verified|t', got '$NITC_PROFILE'"
    exit 1
fi

# Test 11: Personal Email Registration with Selected Kerala College (GEC Thrissur)
echo ""
echo "Test 11: Registering student with personal email and selected Kerala college (GEC Thrissur)..."
GECT_USER_ID="66666666-6666-6666-6666-666666666666"
GECT_CAMPUS_ID="b0000000-0000-0000-0000-000000000009"

run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES ('$GECT_USER_ID', 'student.gec@gmail.com', '{"full_name": "Devika M", "campus_id": "$GECT_CAMPUS_ID"}', NULL);
EOF

# Submitting ID verification request
REQ_ID="77777777-7777-7777-7777-777777777777"
run_sql << EOF
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$GECT_USER_ID';
SET "request.jwt.claim.role" = 'authenticated';
INSERT INTO public.id_verification_requests (request_id, user_id, campus_id, id_card_url, student_id_number, graduation_year)
VALUES ('$REQ_ID', '$GECT_USER_ID', '$GECT_CAMPUS_ID', 'https://res.cloudinary.com/rentora/id/gec_123.jpg', 'TCR21CS045', 2025);
EOF

# Test 12: Unauthorized student verification attempt
echo ""
echo "Test 12: Unauthorized student attempting to approve ID verification request..."
UNAUTH_REVIEW=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.review_id_verification_request('$REQ_ID', 'approved');
EOF
)
if echo "$UNAUTH_REVIEW" | grep -q "Unauthorized: Only authorized Rentora administrators can verify student IDs"; then
    echo "PASS: Test 12 Passed (Unauthorized student ID approval blocked with exception)."
else
    echo "FAIL: Unauthorized student was able to approve request! Output: $UNAUTH_REVIEW"
    exit 1
fi

# ========================================================
# Phase 2A.2: Founder & Admin Governance Tests
# ========================================================

echo ""
echo "--------------------------------------------------------"
echo "Running Phase 2A.2 Governance & Founder Tests..."
echo "--------------------------------------------------------"

# Test 13: Founder Initialization
echo "Test 13: Founder initialization using authenticated user's UUID..."
FOUNDER_ID="99999999-9999-9999-9999-999999999999"
run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES ('$FOUNDER_ID', 'founder@stanford.edu', '{"full_name": "Rentora Founder"}', now());
SELECT public.initialize_founder('$FOUNDER_ID');
EOF

FOUNDER_CHECK=$(run_sql -t -A -c "SELECT public.is_founder('$FOUNDER_ID');")
if [[ "$FOUNDER_CHECK" == "t" ]]; then
    echo "PASS: Test 13 Passed (Founder successfully initialized)."
else
    echo "FAIL: Founder initialization failed. Check: $FOUNDER_CHECK"
    exit 1
fi

# Test 14: Single Founder Invariant (Attempting to initialize a second Founder)
echo ""
echo "Test 14: Testing Single Founder Invariant..."
SECOND_FOUNDER_ATTEMPT=$(run_sql_tolerant -c "SELECT public.initialize_founder('$USER1_ID');" 2>&1 || true)
if echo "$SECOND_FOUNDER_ATTEMPT" | grep -q "Founder initialization failed: A Founder account is already initialized"; then
    echo "PASS: Test 14a Passed (Function blocked initializing a second Founder)."
else
    echo "FAIL: Second founder initialization was not blocked! Output: $SECOND_FOUNDER_ATTEMPT"
    exit 1
fi

# Direct table insert attempt of second founder
DIRECT_FOUNDER_INSERT=$(run_sql_tolerant -c "INSERT INTO public.admin_roles (user_id, role) VALUES ('$USER1_ID', 'founder');" 2>&1 || true)
if echo "$DIRECT_FOUNDER_INSERT" | grep -q "duplicate key value violates unique constraint \"only_one_founder_idx\""; then
    echo "PASS: Test 14b Passed (Database index only_one_founder_idx strictly blocked second Founder insert)."
else
    echo "FAIL: Database constraint failed to block second Founder! Output: $DIRECT_FOUNDER_INSERT"
    exit 1
fi

# Test 15: Multiple Super Admins (Founder promotes Super Admins)
echo ""
echo "Test 15: Founder promoting multiple Super Admins..."
SUPERADMIN1_ID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
SUPERADMIN2_ID="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

run_sql << EOF
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at)
VALUES 
    ('$SUPERADMIN1_ID', 'admin1@stanford.edu', '{"full_name": "Super Admin 1"}', now()),
    ('$SUPERADMIN2_ID', 'admin2@nitc.ac.in', '{"full_name": "Super Admin 2"}', now());

SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$FOUNDER_ID';
SET "request.jwt.claim.role" = 'authenticated';

SELECT public.promote_to_super_admin('$SUPERADMIN1_ID');
SELECT public.promote_to_super_admin('$SUPERADMIN2_ID');
EOF

SUPERADMIN_COUNT=$(run_sql -t -A -c "SELECT count(*) FROM public.admin_roles WHERE role = 'super_admin';")
if [[ "$SUPERADMIN_COUNT" == "2" ]]; then
    echo "PASS: Test 15 Passed (Founder successfully promoted multiple Super Admins: count = 2)."
else
    echo "FAIL: Expected 2 Super Admins, got $SUPERADMIN_COUNT"
    exit 1
fi

# Test 16: Unauthorized Promotion Attempt (Super Admin or student tries promoting someone)
echo ""
echo "Test 16: Super Admin attempting to promote another user..."
UNAUTH_PROMOTION=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$SUPERADMIN1_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.promote_to_super_admin('$USER1_ID');
EOF
)
if echo "$UNAUTH_PROMOTION" | grep -q "Unauthorized: Only the Founder can promote Super Admins"; then
    echo "PASS: Test 16 Passed (Super Admin blocked from promoting users)."
else
    echo "FAIL: Super Admin was able to promote a user! Output: $UNAUTH_PROMOTION"
    exit 1
fi

# Test 17: Direct Client Tampering with admin_roles table
echo ""
echo "Test 17: Direct client attempt to insert or update admin_roles..."
DIRECT_ADMIN_MUTATION=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$USER1_ID';
SET "request.jwt.claim.role" = 'authenticated';
INSERT INTO public.admin_roles (user_id, role) VALUES ('$USER1_ID', 'super_admin');
EOF
)
if echo "$DIRECT_ADMIN_MUTATION" | grep -Eq "permission denied for table admin_roles|violates row-level security policy"; then
    echo "PASS: Test 17 Passed (Direct client insert into admin_roles strictly blocked)."
else
    echo "FAIL: Direct client mutation was not blocked! Output: $DIRECT_ADMIN_MUTATION"
    exit 1
fi

# Test 18: Authorized Student Verification by Super Admin
echo ""
echo "Test 18: Authorized Super Admin approving student ID..."
run_sql << EOF
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$SUPERADMIN1_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.review_id_verification_request('$REQ_ID', 'approved');
EOF

GECT_VERIFIED_CHECK=$(run_sql -t -A -c "SELECT is_verified, verification_status FROM public.users WHERE user_id = '$GECT_USER_ID';")
if [[ "$GECT_VERIFIED_CHECK" == "t|verified" ]]; then
    echo "PASS: Test 18 Passed (Super Admin successfully verified student ID; user promoted to t|verified)."
else
    echo "FAIL: Super Admin approval failed. Status: $GECT_VERIFIED_CHECK"
    exit 1
fi

# Test 19: Founder Protection & Demotion Enforcement
echo ""
echo "Test 19: Attempting to demote the Founder..."
FOUNDER_DEMOTE_ATTEMPT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$FOUNDER_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.demote_super_admin('$FOUNDER_ID');
EOF
)
if echo "$FOUNDER_DEMOTE_ATTEMPT" | grep -q "The Founder account cannot be demoted or removed"; then
    echo "PASS: Test 19a Passed (Founder account protected from accidental demotion)."
else
    echo "FAIL: Founder demotion was not blocked! Output: $FOUNDER_DEMOTE_ATTEMPT"
    exit 1
fi

# Founder demoting a Super Admin
run_sql << EOF
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$FOUNDER_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.demote_super_admin('$SUPERADMIN2_ID');
EOF

REMAINING_SUPERADMINS=$(run_sql -t -A -c "SELECT count(*) FROM public.admin_roles WHERE role = 'super_admin';")
if [[ "$REMAINING_SUPERADMINS" == "1" ]]; then
    echo "PASS: Test 19b Passed (Founder successfully demoted Super Admin 2; 1 Super Admin remaining)."
else
    echo "FAIL: Demotion failed. Remaining count: $REMAINING_SUPERADMINS"
    exit 1
fi

# Test 20: Founder Authority Transfer
echo ""
echo "Test 20: Founder transferring ultimate authority to Super Admin 1..."
run_sql << EOF
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$FOUNDER_ID';
SET "request.jwt.claim.role" = 'authenticated';
SELECT public.transfer_founder_authority('$SUPERADMIN1_ID');
EOF

NEW_FOUNDER_CHECK=$(run_sql -t -A -c "SELECT public.is_founder('$SUPERADMIN1_ID');")
OLD_FOUNDER_CHECK=$(run_sql -t -A -c "SELECT public.is_founder('$FOUNDER_ID');")
OLD_FOUNDER_ROLE=$(run_sql -t -A -c "SELECT role FROM public.admin_roles WHERE user_id = '$FOUNDER_ID';")

if [[ "$NEW_FOUNDER_CHECK" == "t" && "$OLD_FOUNDER_CHECK" == "f" && "$OLD_FOUNDER_ROLE" == "super_admin" ]]; then
    echo "PASS: Test 20 Passed (Founder authority atomically transferred; old Founder is now Super Admin, new user is Founder)."
else
    echo "FAIL: Authority transfer failed! New: $NEW_FOUNDER_CHECK, Old: $OLD_FOUNDER_CHECK, Old role: $OLD_FOUNDER_ROLE"
    exit 1
fi

# Test 21: Audit Log Integrity & Immutability
echo ""
echo "Test 21: Checking Audit Log entries and immutability..."
AUDIT_ENTRIES=$(run_sql -t -A -c "SELECT count(*) FROM public.admin_audit_logs;")
echo "Total logged administrative actions: $AUDIT_ENTRIES"
if [[ "$AUDIT_ENTRIES" -ge 5 ]]; then
    echo "PASS: Test 21a Passed (Audit log recorded all administrative events: count = $AUDIT_ENTRIES)."
else
    echo "FAIL: Expected at least 5 audit entries, got $AUDIT_ENTRIES"
    exit 1
fi

# Attempting to delete audit log entry
DELETE_AUDIT_ATTEMPT=$(run_sql_tolerant << EOF 2>&1 || true
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$SUPERADMIN1_ID';
SET "request.jwt.claim.role" = 'authenticated';
DELETE FROM public.admin_audit_logs;
EOF
)
if echo "$DELETE_AUDIT_ATTEMPT" | grep -q "permission denied for table admin_audit_logs"; then
    echo "PASS: Test 21b Passed (Audit logs are strictly append-only; DELETE permission denied)."
else
    echo "FAIL: Audit log deletion was not denied! Output: $DELETE_AUDIT_ATTEMPT"
    exit 1
fi

echo ""
echo "=========================================================="
echo "ALL 21 GOVERNANCE & SECURITY VERIFICATION TESTS PASSED!"
echo "=========================================================="
