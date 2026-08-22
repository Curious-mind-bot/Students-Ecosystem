# Students-Ecosystem

A safety-first, end-to-end ecosystem for planning an international study application: search for a university/programme, check admission requirements, find scholarships, understand fees and cost of living, check visa requirements, and find accommodation — every factual claim ties back to a `source_url` and `source_checked_on` date instead of being invented.

## Current MVP

- **Account** — register/log in (email + password, JWT-based sessions).
- **University & programme search** — browse universities and programmes, with admission requirements attached.
- **Scholarships** — programme-specific, university-wide, or country-wide funding.
- **Fees & cost of living** — application/tuition fees per programme, plus country/university cost-of-living estimates.
- **Visa requirements** — destination-country study/residence permit facts, optionally narrowed by nationality.
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

This project does **not** predict admission or visa outcomes, calculate official financial requirements, generate insurance policies, or help a user conceal or alter material facts. Always use official university and government sources for requirements. Seed data in `database/schema.sql` is illustrative for local development only — it is not verified, current official data.

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

## Tests

```bash
cd backend-node
npm test
```
