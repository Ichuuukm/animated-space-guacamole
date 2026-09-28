# Rentora Architecture & Decisions Log

## 2026-09-27 — Phase 2, Step 2: Institutional Authentication UI Implementation

### Context
Phase 2 implements the institutional authentication system for Rentora. In Step 2, the client-facing UI, state management, and protected routing were created using React 18, React Router v7, Material UI (MUI), and Supabase Auth.

### Key Architectural Decisions
1. **Frontend Validation as Convenience Only**:
   - Institutional domain validation is performed in `src/pages/Register.jsx` to prevent common user error and improve UX by detecting institutional TLDs (`.edu`, `.ac.uk`, `.edu.in`) and registered campuses dynamically loaded from Supabase's `campuses` table.
   - However, frontend validation is explicitly treated as a client convenience, not a security boundary. Authoritative institutional verification and immutable campus assignment will be enforced server-side via Supabase triggers/functions in the upcoming database migration step.

2. **Session & State Management**:
   - Implemented `AuthContext` (`src/context/AuthContext.jsx`) subscribing to Supabase's `onAuthStateChange`.
   - Exposed `user`, `session`, `loading`, `signOut`, and `refreshSession` for consistent cross-component session handling.
   - Properly subscribed and unsubscribed using `@supabase/supabase-js` v2 `subscription.unsubscribe()` pattern.

3. **Multi-State Route Protection**:
   - `ProtectedRoute` (`src/components/ProtectedRoute.jsx`) differentiates between:
     1. Unauthenticated users (redirects to `/login`).
     2. Authenticated but unverified users (redirects to `/verify` with email state).
     3. Fully authenticated and institutional-email-verified students (allows access to `/dashboard`).

4. **Recovery & Reset Flow**:
   - `ResetPassword` handles hash fragment parameters (`#access_token=...`), PKCE authorization codes (`?code=...`), and `PASSWORD_RECOVERY` events, ensuring compatibility across Supabase Auth flows.

5. **Secrets & Security Compliance**:
   - Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are used in frontend client.
   - No service-role key is exposed.
   - Database schema was untouched in this step as required.


## 2026-09-27 — Phase 2, Step 3: Database Security & Institutional Verification

### Context
Phase 2 Step 3 establishes server-side security boundaries for Rentora, ensuring institutional domain enforcement, automated profile generation, immutable campus assignments, and Row Level Security (RLS) policies.

### Key Architectural Decisions
1. **Server-Side Authoritative Email Domain Whitelisting**:
   - Implemented `handle_new_auth_user()` trigger function executing `AFTER INSERT ON auth.users` with `SECURITY DEFINER` and fixed `search_path = public, auth, pg_temp`.
   - Domain is extracted via `LOWER(SPLIT_PART(NEW.email, '@', 2))` and matched against `public.campuses`.
   - If unapproved, `RAISE EXCEPTION` aborts the registration transaction, rejecting the sign-up at the database level.
   - Initial approved campuses seeded: Stanford (`stanford.edu`), MIT (`mit.edu`), UC Berkeley (`berkeley.edu`), Oxford (`ox.ac.uk`), Cambridge (`cam.ac.uk`), and IIT Delhi (`iitd.ac.in`).

2. **Immutable Campus Assignment & Anti-Tampering**:
   - `campus_id` is assigned strictly from the authoritative database match in `public.campuses`. Any client-supplied `campus_id` in metadata is ignored.
   - Implemented `prevent_immutable_user_field_updates()` trigger function on `BEFORE UPDATE ON public.users`.
   - Blocks any modification to `user_id`, `campus_id`, `email`, and `is_verified` using a transaction-local configuration guard (`rentora.internal_sync`).

3. **Supabase Email Confirmation Sync**:
   - Trigger `on_auth_user_confirmed` fires on `auth.users AFTER UPDATE OF email_confirmed_at`.
   - Automatically promotes `public.users.is_verified` to `TRUE` without trusting client-side flags.

4. **Granular Row Level Security (RLS)**:
   - `public.campuses`: Read-only for `anon` and `authenticated`.
   - `public.users`: Authenticated students can `SELECT` and `UPDATE` exclusively their own profile (`auth.uid() = user_id`). Direct client inserts/deletes are disallowed.
   - `public.items`: Active items are viewable by all. Creating items (`INSERT`) strictly requires `auth.uid() = owner_id` and verified institutional status (`is_verified = TRUE`).

5. **Safe Verification & Zero-Cost Compliance**:
   - All 9 test cases verified locally in PostgreSQL Docker container (`npm run test:db`).
   - Zero-cost tier constraints preserved; no paid cloud services introduced.
   - Production database untouched; awaiting user review and explicit approval before deployment.


## 2026-09-27 — Phase 2A: Indian College Verification & Multi-Domain Database Architecture

### Context
Adapting Rentora's verification system for Indian colleges and universities (with specific support for Kerala institutions). The architecture resolves the challenge that many genuine students in Indian colleges do not receive official institutional email addresses, while preventing unauthorized access via unverified personal emails.

### Key Architectural Decisions
1. **Dual-Track Verification Architecture**:
   - **Track 1 (Institutional Email)**: For students possessing confirmed institutional email domains (e.g. `@nitc.ac.in`, `@iitpkd.ac.in`, `@cet.ac.in`). Instant verification upon Supabase email link confirmation (`verification_method = 'institutional_email'`).
   - **Track 2 (College ID Card Verification)**: For genuine students attending registered colleges that lack student institutional email provision (e.g. GEC Thrissur, St. Teresa's College). Allows registration with personal email provided a valid registered campus is selected. Account remains strictly unverified (`verification_status = 'unverified'`) until a student ID card is uploaded and reviewed by an administrator.

2. **Multi-Domain Registry (`public.campus_domains`)**:
   - Introduced `public.campus_domains` referencing `public.campuses(campus_id)` with `UNIQUE(domain)`.
   - Allows institutions to map primary domains, student subdomains (`@student.cet.ac.in`), and departmental subdomains to the same campus entity without breaking existing queries referencing `campuses.domain`.

3. **Conservative Seed Policy (Confirmed Domains Only)**:
   - In accordance with safety rules, only verified domains were seeded with `allow_email_verification = TRUE` (NITC, IIT Palakkad, CET, MEC, TKMCE, CUSAT, MITS, FISAT).
   - Institutions without confirmed student email domains (GEC Thrissur, St. Teresa's, SH College, Farook College) are registered with `allow_id_verification = TRUE` and `domain = NULL`.

4. **Multi-Level Security & Tamper-Proof Verification State**:
   - Extended `public.users` with `verification_method`, `verification_status`, and `student_id_number`.
   - Updated `prevent_immutable_user_field_updates()` trigger to strictly disallow client tampering with `verification_status`, `verification_method`, `is_verified`, and `campus_id`.
   - Confirmation of a personal email (`@gmail.com`) only proves email inbox ownership; trigger explicitly **refuses** to promote `is_verified` or `verification_status` to verified for `college_id` users.
   - Marketplace item posting (`public.items` RLS) remains completely blocked until the student is verified.

5. **Local Verification Test Suite**:
   - Created automated test coverage in `tests/database_security_test.sh` executing 15 comprehensive security tests across both migrations. All tests passed with exit code 0.


## 2026-09-27 — ICET Configuration & Verification Rules

### Context
Incorporated confirmed configuration decisions for Ilahia College of Engineering and Technology (ICET), Muvattupuzha, Ernakulam, Kerala (APJ Abdul Kalam Technological University).

### Key Decisions
1. **Confirmed Primary Domain**:
   - `icet.ac.in` is confirmed as the official student email domain.
   - Institutional email verification enabled (`allow_email_verification = TRUE`).
   - Domain matching rule: Validates the domain itself (`LOWER(SPLIT_PART(TRIM(email), '@', 2)) = 'icet.ac.in'`) without username pattern constraints (accommodating `muhammedirfan23cs@icet.ac.in`, `studentname24ec@icet.ac.in`, `studentname25me@icet.ac.in`, etc.).
2. **Dual-Track Support for ICET**:
   - College ID verification is enabled for ICET (`allow_id_verification = TRUE`) to allow students without `@icet.ac.in` email to register via personal email, select ICET, and submit their College ID card for review.
3. **Conservative Subdomain Stance**:
   - Additional student subdomains remain flagged as unconfirmed. None are assumed or automatically added.
4. **Administrative Boundaries**:
   - ID card approvals strictly require authorized Rentora administrator review.
   - Super Admin role remains separate from student verification.


## 2026-09-27 — Founder-Controlled Multi-Super-Admin Architecture

### Context
Incorporated architectural specifications for a Founder-Controlled, Multi-Super-Admin governance model. Establishes clear separation between the sole Founder (ultimate authority) and operational Super Admins.

### Key Architectural Decisions
1. **Role Hierarchy**:
   - **Founder (Level 1)**: Exactly one account, enforced by a database partial unique index (`only_one_founder_idx`). Holds exclusive rights to promote/demote Super Admins and transfer Founder authority. Immutable from modification by other admins.
   - **Super Admins (Level 2)**: Multiple accounts. Delegated authority to verify students, manage campuses, moderate listings, suspend users, and inspect audit logs. Cannot create or modify admin accounts.
   - **College Admins (Level 3)**: Reserved for future college-scoped roles.
2. **Dedicated Administration Table (`public.admin_roles`)**:
   - Admin roles live in a dedicated table, isolated from student profile data (`public.users`).
   - RLS strictly forbids client writes (`INSERT`, `UPDATE`, `DELETE`).
   - Privilege changes are executed exclusively via `SECURITY DEFINER` stored procedures verifying `is_founder(auth.uid())`.
3. **Append-Only Audit Logging (`public.admin_audit_logs`)**:
   - All administrative actions (Super Admin promotions/demotions, ID approvals, bans) are logged with actor, target, action, and timestamp.
   - Strict immutability: table-level write controls prevent any user or admin from updating or deleting log entries.
4. **Student Verification Gating**:
   - `review_id_verification_request()` is updated to strictly assert `is_super_admin(auth.uid())`, preventing student self-approval.
