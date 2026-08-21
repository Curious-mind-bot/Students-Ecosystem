# Students-Ecosystem

A safety-first prototype for organising an international-study application.

## Current MVP

- a mobile-friendly application dashboard prototype;
- an honest statement-readiness check that suggests review areas but never changes a student's facts;
- a guarded recommendation-request placeholder that never sends an email.

## Not included

This project does **not** predict admission or visa outcomes, calculate official financial requirements, generate insurance policies, or help a user conceal or alter material facts. Always use official university and government sources for requirements.

## Run locally

```bash
cd backend-node
npm install
npm start
```

Open `http://localhost:3000`. The statement-readiness check works without configuration. Recommendation requests are intentionally not implemented yet: they require a secure file-upload system, access controls, retention rules, and a verified mail provider.
