# Students-Ecosystem

A safety-first, end-to-end ecosystem for planning an international study application: search for a university/programme, check admission requirements, find scholarships, understand fees and cost of living, check visa requirements, and find accommodation — every factual claim ties back to a `source_url` and `source_checked_on` date instead of being invented.

## Current MVP

- **Account** — register/log in (email + password, JWT-based sessions).
- **University & programme search** — browse universities and programmes, with admission requirements attached.
- **Scholarships** — programme-specific, university-wide, or country-wide funding.
- **Fees & cost of living** — application/tuition fees per programme, plus country/university cost-of-living estimates.
- **Visa requirements** — destination-country study/residence permit facts, optionally narrowed by nationality.
- **Accommodation** — university-linked dorm/private-hall listings with rent, deposit, and distance.
- An honest statement-readiness check that suggests review areas but never changes a student's facts.
- A guarded recommendation-request placeholder that never sends an email.

Every requirement/scholarship/fee/visa/accommodation record in the schema requires a `source_url` and `source_checked_on` — the app refuses to state a funding, admission, or visa fact without one.

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
