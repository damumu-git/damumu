# DAMUMU Project Overview

Last reviewed: 2026-09-01 (Asia/Seoul)

## Purpose

DAMUMU, currently presented in much of the UI as “搭慕慕”, helps people in Korea
discover, create, join, and manage nearby offline activities. The intended core
loop is:

```text
register or sign in
-> discover database-backed activities
-> view a real activity detail
-> read cost and safety information
-> join or apply
-> organizer approval when required
-> reveal the exact meeting point only after approval
-> track the activity in My Activities
-> receive notifications and communicate with participants
```

## Applications

| Component | Directory | Technology | Typical local URL |
| --- | --- | --- | --- |
| User app | `app/` | Flutter / Dart | `http://localhost:3000` for web |
| REST API | `restapi/` | ASP.NET Core 10 | `http://localhost:8080/api/v1` |
| Admin console | `admin/` | React 19 / Vite | `http://localhost:5173` |
| Database | external container | PostgreSQL + PostGIS | `127.0.0.1:5432` |

OpenAPI is normally available at `http://localhost:8080/openapi/v1.json`.

## Main code entry points

### Flutter

- `app/lib/main.dart`: most screens, widgets, navigation, and current UI state.
- `app/lib/auth.dart`: registration, login, token persistence, profiles, avatars.
- `app/lib/event_service.dart`: event lists, creation, My Activities, regions.
- `app/lib/category_service.dart`: category catalog API.
- `app/lib/location_service.dart`: device/browser location and geocoding cache.
- `app/lib/l10n.dart`: Chinese, English, and Korean strings.

### API

- `restapi/Program.cs`: service setup, CORS, middleware, and route registration.
- `restapi/Infrastructure/Db.cs`: data access and participation transactions.
- `restapi/Infrastructure/ApiSupport.cs`: response envelope and request identity.
- `restapi/Endpoints/`: user, event, catalog, social, safety, governance, and admin
  endpoint groups.
- `restapi/Migrations/`: numbered schema and seed migrations, currently `001`
  through `008`.

### Admin

- `admin/src/App.jsx`: current admin pages and primary interactions.
- `admin/src/api.js`: admin API client.
- `admin/src/App.css`: primary admin styling.

## Current capabilities

The following paths are described as connected to the API/database in the latest
project context and should still be verified when touched:

- Registration, login, and login-state restoration.
- Profile retrieval and partial updates.
- System avatar selection and custom avatar upload.
- Category and administrative-region loading.
- Event publication and event lists.
- My Activities for hosted and joined events.
- Admin management for users, events, reports, safety alerts, categories, regions,
  avatars, feature flags, audits, and announcements.

The API contains additional endpoints whose Flutter flows remain incomplete:

- Real event detail loading.
- Join and leave behavior.
- Organizer member approval and rejection.
- Event editing, cancellation, and check-in.
- Conversations, messages, and notifications.
- Reports, blocking, reviews, and safety meetings.

Several Flutter message, chat, notification, statistics, and policy screens still
contain demo data or explanatory placeholders.

## Data and API conventions

- API base path: `/api/v1`.
- User requests normally use `Authorization: Bearer <token>`.
- Development also supports `X-User-Id`; normal app flows should use the bearer
  token.
- Local admin requests use `X-Admin-Key`; this must be replaced before production.
- Successful and failed responses use the common `data`, `meta`, `error`, and
  `traceId` envelope.
- Geographic data uses PostGIS `geography(Point, 4326)`.
- Administrative-region codes are stable identifiers and region display data is
  loaded dynamically.

## Release boundary

The first release is not complete until two real accounts can publish and join an
activity through the database-backed flow, organizer decisions and capacity are
correct, approved users receive the correct notification and private location,
the admin can operate core catalogs/users/events, and release builds contain no
development credentials or automatic login.

## Known technical debt

- Flutter event IDs need conversion from an integer/hash representation to real
  UUID strings.
- Event/place creation is not yet one complete transaction.
- API exception handling needs safe coverage for database and unknown failures.
- User and admin authentication are not production-ready.
- `app/lib/main.dart` and `admin/src/App.jsx` are oversized.
- Older databases may differ from the initial migration definitions.
- Automated API integration coverage is currently missing.
- Some UI text and screens are not fully localized.

## Detailed references

- `HANDOFF.md`: current state and exact continuation point.
- `DECISIONS.md`: accepted decisions and their reasons.
- `DEVELOPMENT_CONTEXT.md`: detailed pre-split development context.
- `MVP.md`: MVP requirements and acceptance criteria.
- `FIRST_RELEASE_FLOWS.md`: full first-release flows and gaps.
- `app/README.md`, `restapi/README.md`, `admin/README.md`: module-specific setup.

