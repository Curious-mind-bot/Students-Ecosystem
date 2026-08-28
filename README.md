# Students-Ecosystem

A safety-first, end-to-end ecosystem for planning an international study application: search for a university/programme, check admission requirements, find scholarships, understand fees and cost of living, check visa requirements, and find accommodation — every factual claim ties back to a `source_url` and `source_checked_on` date instead of being invented.

## Current MVP

- **Account** — register/log in (email + password, JWT-based sessions), forgot-password recovery via a one-time emailed link, plus self-service data export (`GET /api/v1/me/export`) and account deletion (`DELETE /api/v1/me`, password-confirmed).
- **University & programme search** — browse universities and programmes, with admission requirements attached. `academic_programs.degree_level` includes `SHORT_COURSE` (alongside the traditional `BACHELOR`/`MASTER`/`PHD`/`DIPLOMA`/`CERTIFICATE`) for summer schools and other short-form courses, plus a nullable `duration_weeks` column for programmes measured in weeks rather than months. Seed data currently covers 85 universities across 32 countries (Germany, Netherlands, UK, Canada, Ireland, Cyprus, Austria, USA, Poland, Portugal, Hungary, Czechia, Italy, Spain, Slovakia, Malaysia, Greece, France, Belgium, Australia, Sweden, Singapore, New Zealand, Denmark, Finland, Estonia, Lithuania, Latvia, Romania, Bulgaria, Croatia, Luxembourg) — this reaches the project's original ~32-country target; further batches (e.g. Malta, Slovenia, and adding more universities per country) continue to grow depth over time.
- **Scholarships** — programme-specific, university-wide, or country-wide funding.
- **Fees & cost of living** — application/tuition fees per programme, plus country/university cost-of-living estimates. Cost estimates (`computeCostView`, `GET /api/v1/matches`) fold in `TUITION_PER_YEAR`, `TUITION_TOTAL`, and `TUITION_PER_SEMESTER` fee rows alike — a per-semester or whole-programme figure is disclosed as such via the response's own caveat, never silently dropped.
- **Visa requirements** — destination-country study/residence permit facts, optionally narrowed by nationality. `GET /api/v1/me/readiness/documents` compares a student's own tracked passport expiry against a destination's sourced minimum passport validity (when one is on file) as an informational heads-up only — never a visa/immigration decision, and never populated with an assumed "typical" validity rule for a country that hasn't disclosed one. As of this writing only 2 of the 28 seeded destination countries have a confirmed figure — New Zealand's Fee Paying Student Visa (official immigration.govt.nz page: passport valid for at least 3 months beyond the planned departure date) and Bulgaria's Visa D for students (official mfa.bg document: passport valid for at least 18 months). Every other country was checked by directly fetching that country's own official page and none stated a clean absolute number for its student/residence-permit route (several state only a relative rule, e.g. "valid longer than the permit itself," which isn't reducible to a fixed number of months) — the column stays NULL for all of them rather than defaulting to a commonly assumed rule (e.g. the Schengen tourist-visa "6 months" convention, which does not necessarily apply to a national student residence permit).
- **Accommodation** — university-linked dorm/private-hall listings with rent, deposit, and distance.
- **Support & Resources** — free advising networks, test/application fee waivers, refugee-specific credential-recovery programs (e.g. EducationUSA, the Duolingo English Test Access Program, Article 26 Backpack), and a peer-mentorship/"chat with a current student" category (currently TU Delft and European University Cyprus — only programs whose official page could be directly confirmed), plus globally-open need-based scholarships (Chevening, Fulbright, UNHCR's DAFI programme) for students who can't afford a paid agent or a test fee.
- **Document tracking** — per-application document checklist items can now be added and updated (`POST`/`PATCH /api/v1/applications/:id/documents...`), plus a personal "My Documents" vault (`/api/v1/me/documents`) for expiry-dated records like an IELTS score or passport — metadata only (type, dates, notes), no file storage.
- **Find My Matches** — `GET /api/v1/matches` ranks every programme in the database against a student's own saved CGPA/funds (compared only to a sourced admission-requirements row) and estimated net annual cost after scholarships; optional `maxBudgetEur`/`countryCode`/`degreeLevel` filters. Never predicts an outcome — it's a sourced comparison, same engine as the single-programme eligibility check.
- **Deadline reminders** — `backend-node/scripts/send-deadline-digest.js` emails each student a digest of their own tracked, unsubmitted application deadlines (due within `DEADLINE_REMINDER_WINDOW_DAYS`, default 14). Run it on a schedule (e.g. a daily cron calling `node backend-node/scripts/send-deadline-digest.js`) with `DATABASE_URL` and the same `EMAIL_*` variables as recommendation emails set.
- An honest statement-readiness check that suggests review areas but never changes a student's facts.
- A guarded recommendation-request placeholder that never sends an email.
- **Low-bandwidth / multi-language** — installable PWA (manifest + a service worker that caches only the static app shell, never `/api/` responses) so the shell still loads offline or on a slow connection, plus an English/French/Arabic/Spanish language switcher (with right-to-left layout for Arabic) covering the app's core navigation and actions.

Every requirement/scholarship/fee/visa/accommodation/support-resource record in the schema requires a `source_url` and `source_checked_on` — the app refuses to state a funding, admission, visa, or support fact without one.

## Not included

This project does **not** predict admission or visa outcomes, calculate official financial requirements, generate insurance policies, give legal or immigration advice, or help a user conceal or alter material facts. The passport-validity check is a same-spirit informational comparison against a sourced figure, not a determination of visa eligibility. Always use official university and government sources for requirements. Seed data in `database/schema.sql` is illustrative for local development only — it is not verified, current official data.

## Run locally

```bash
cd backend-node
npm install
npm start
```

Open `http://localhost:3000`. The public browse endpoints (universities, scholarships, fees, living costs, visa requirements, accommodations) and the statement-readiness check work once you've registered/logged in via the Account card. A Postgres database is required for anything beyond the health check — point `DATABASE_URL` at one and load `database/schema.sql` first:

```bash
createdb students_ecosystem
psql -d students_ecosystem -f ../database/schema.sql
DATABASE_URL=postgresql://localhost:5432/students_ecosystem JWT_SECRET=<any-value> npm start
```

Recommendation (LOR) requests are intentionally not implemented yet: they require a secure file-upload system, access controls, retention rules, and a verified mail provider.

## License

Copyright (c) 2026 Curious-mind-bot. All Rights Reserved. This is proprietary, closed-source software — see [LICENSE](./LICENSE). No reuse, redistribution, or derivative works are permitted without written consent.

## Tests

```bash
cd backend-node
npm test
```

## Monetization (students are never charged)

The app never charges a student. Institutes and sponsors can support it instead, and every one of these is designed so paid placement can never influence search results or the "Find My Matches" ranking:

- **Verified partners** (`GET /api/v1/partners`, `POST /api/v1/partners/:id/continue`) — affiliate-style referrals (e.g. a visa consultant, test-prep provider) shown in the "Trusted Partners" card with an explicit commission disclosure on every listing. Configure real partners via the `PARTNERS_JSON` env var, e.g.:
  ```
  PARTNERS_JSON=[{"id":"...","name":"...","category":"CONSULTANT","redirectUrl":"https://...","sourceAttribution":"..."}]
  ```
  Clicking "Continue to partner" is logged to `partner_conversions` with a per-click tracking token appended to the outbound URL.
- **Sponsored content** (`GET /api/v1/sponsored-content?countryCode=..`) — direct-sold, non-behavioral placements (no tracking, no student data used for targeting) shown in a clearly labeled "Sponsored" block above university search results. Configure via `SPONSORED_CONTENT_JSON`, e.g.:
  ```
  SPONSORED_CONTENT_JSON=[{"id":"...","sponsorName":"...","headline":"...","linkUrl":"https://...","countryCode":"DE"}]
  ```
  Omit `countryCode` for a sponsor shown regardless of search filters.
- **Institute demand analytics** (`GET /api/v1/analytics/demand`, header `x-institute-api-key`) — sells a university aggregate, anonymized view-count data for its own listing only (no individual student data, ever). Each API key is scoped to exactly one `universityId` via `INSTITUTE_ANALYTICS_KEYS_JSON`:
  ```
  INSTITUTE_ANALYTICS_KEYS_JSON=[{"apiKey":"...","universityId":"..."}]
  ```
  Backed by an anonymous `demand_events` log (no `user_id`, no IP) recorded whenever a university or programme page is viewed.

The example values above are placeholders — no real partner, sponsor, or institute deal is included. An operator fills these in once real agreements exist.

## Admin CMS

Open `/admin.html` (served alongside the main app) to manage sourced content — universities, programmes, admission requirements, scholarships, fees, living costs, visa requirements, accommodations, and support resources — through a UI instead of a hand-written SQL migration. Set `ADMIN_API_KEY` on the server and enter the same value in the page (kept only in that browser tab's `sessionStorage`). Backed by a generic CRUD API:

```
GET    /api/v1/admin/resources
GET    /api/v1/admin/:resource
GET    /api/v1/admin/:resource/_schema
GET    /api/v1/admin/:resource/:id
POST   /api/v1/admin/:resource
PATCH  /api/v1/admin/:resource/:id
DELETE /api/v1/admin/:resource/:id
```

Every request is header-gated by `x-admin-api-key`. Postgres still enforces every `NOT NULL`/`CHECK` constraint (e.g. `source_url`/`source_checked_on` being required) — the API just translates a constraint violation into a readable 400 instead of a raw Postgres error.

### Crowdsourced submissions ("Live-Verify")

Any logged-in student can suggest a new record or a correction via `POST /api/v1/submissions` (a `sourceUrl` is mandatory — nothing is accepted without one) and check their own submission history at `GET /api/v1/me/submissions`. **Nothing a student submits is ever written to a live table or shown to anyone else automatically** — every submission lands in a `PENDING` queue and only reaches students after an admin reviews and approves it from the same `/admin.html` page (`GET /api/v1/admin/submissions`, `POST /api/v1/admin/submissions/:id/approve` or `.../reject`). Approving reuses the exact same column-whitelist and constraint-checked write path as the admin CRUD API above, so an incomplete or malformed suggestion is rejected with a clear error rather than silently corrupting a record.

## Operations

- **Rate limiting** — `/api/v1/auth/register` and `/api/v1/auth/login` are limited (default 20 requests / 15 minutes per IP; tune with `AUTH_RATE_LIMIT_MAX`).
- **Error tracking** — set `SENTRY_DSN` to report unhandled errors to Sentry (optional; every request is always logged as structured JSON to stdout regardless).
- **Staleness report** — `node backend-node/scripts/staleness-report.js` scans every sourced table (admission requirements, scholarships, fees, living costs, visa requirements, accommodations, support resources) for rows whose `source_checked_on` is older than `STALENESS_THRESHOLD_MONTHS` (default 6) and exits non-zero if any are found — run it on a schedule to know when seed data needs re-verification.
- **CI** (`.github/workflows/test.yml`) — every push/PR to `main` runs the backend test suite, plus a separate job that loads `database/schema.sql` into a real Postgres service container and checks that every `academic_programs` row has an `admission_requirements` row (the exact class of gap a manual seed-data batch missed earlier in this project's history).
