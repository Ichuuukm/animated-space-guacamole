# Rentora — Google Antigravity Agent Execution Rules

## 1. Project Vision & Architecture Boundaries
- **Project Goal:** Campus-exclusive peer-to-peer marketplace for buying, renting, and swapping academic gear/textbooks.
- **Brand Name:** Rentora
- **Tech Stack:** React (Vite) + Material-UI (Frontend), Supabase PostgreSQL + Auth (Database), Cloudinary (Image CDN), Resend (Email OTP).
- **Hard Constraint — Zero Cost Tier:** Never introduce paid cloud services (e.g., paid AWS services, paid payment gateways, redis enterprise). All architectural patterns MUST fit within free-tier limits.

---

## 2. Behavioral Loop & Workflow (Plan -> Act -> Verify)
For every task or feature request, the agent MUST execute in order:
1. **Plan:** Write/update an `implementation_plan.md` artifact detailing file changes, API signatures, and component schemas before modifying code.
2. **Act:** Execute changes incrementally in small, testable increments.
3. **Trace:** Log key decisions or schema changes to `.antigravity/decisions/log.md`.
4. **Verify:** Evidence before claims. Test code in the integrated browser or run terminal commands and inspect full stdout/stderr before reporting task completion.

---

## 3. Data Schema & Domain Constraints
- **Multi-Intent Listings:** Every product record must support boolean flags for `is_for_sale`, `is_for_rent`, and `is_for_swap`.
- **Academic Indexing:** Ensure textbook/academic listings index `department` (e.g., Computer Science) and `course_code` (e.g., CST 305).
- **Email Validation:** Auth flows must reject non-institutional emails. Only validate domains matching `.edu`, `.ac.uk`, `.edu.in`, or whitelisted campus TLDs.

---

## 4. Frontend & Performance Standards
- **Client-Side Image Optimization:** Handover photos MUST pass through `browser-image-compression` (max width 1024px, quality 0.7, webp format) before sending to Cloudinary to preserve free storage quotas.
- **UI Quality:** Use Material-UI components with explicit color badges:
  - `Rent` -> Primary Blue badge (`$X/day`).
  - `Buy` -> Green badge (`$X`).
  - `Swap` -> Purple badge (`Open to Trade`).

---

## 5. Safety & Security Guardrails
- **Secrets Management:** Never commit raw Supabase keys or Cloudinary credentials into source code. Always reference `process.env` or `import.meta.env`.
- **Destructive Commands:** Never delete database tables or large directories without explicit user confirmation in the prompt.
- **Immutability:** Handover photo records and transaction audit logs must remain append-only for dispute resolution.