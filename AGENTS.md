# MUDA Repository Instructions

These instructions apply to the entire repository. Read this file before making
changes, then read `PROJECT.md`, `HANDOFF.md`, and the relevant module README.

## Product invariants

- MUDA (current UI name: 搭慕慕) is a Korea-focused offline activity and
  companion-finding app.
- The platform does not collect activity fees, provide payments, guarantee
  transfers, or act as an escrow service. Amounts shown are estimated offline
  per-person spending in KRW.
- Never expose an exact meeting point to anonymous users, unapproved applicants,
  waitlisted applicants, or rejected applicants. Only the organizer and users
  with `approved` or `attended` participation may receive it.
- New events currently publish immediately. The admin review API is reserved for
  a future policy change; do not make review mandatory without an explicit
  product decision.
- Categories, administrative regions, and production event lists come from the
  API/database. Do not reintroduce hard-coded production catalogs or demo data.
- Unimplemented flows must be labelled honestly. Do not present an explanatory
  placeholder as a completed feature.

## Repository map

- `app/`: Flutter/Dart user application.
- `restapi/`: ASP.NET Core 10 API backed by PostgreSQL/PostGIS.
- `admin/`: React 19/Vite operations console.
- `restapi/Migrations/`: ordered SQL migrations.
- `DEVELOPMENT_CONTEXT.md`: detailed legacy handoff and implementation notes.
- `MVP.md`: MVP scope and acceptance criteria.
- `FIRST_RELEASE_FLOWS.md`: detailed first-release flow analysis.

## Working rules

1. Inspect the relevant UI, API, database, and admin paths before changing a
   cross-cutting feature.
2. Preserve user changes. Check `git status --short` and the relevant diff before
   editing; never discard unrelated work.
3. Treat source code, migrations, Git state, and test results as more current than
   documentation. Update `HANDOFF.md` when implementation status changes.
4. Database changes require a new sequential, preferably idempotent migration.
   Do not rewrite an already-applied migration to represent a new change.
5. Keep API responses in the existing `{ data, meta, error, traceId }` envelope.
6. New production UI strings belong in `app/lib/l10n.dart` and should account for
   Chinese, English, and Korean. Avoid adding scattered hard-coded strings.
7. Do not perform broad refactors of `app/lib/main.dart` or `admin/src/App.jsx`
   while implementing a feature unless the refactor is necessary and verified.
8. Never commit credentials, real user data, local connection strings, build
   output, or generated logs. Local example credentials are development-only.
9. Before using a database container, run `docker ps` and confirm its actual name;
   historical documentation contains more than one container name.
10. When completing a task, record important lasting choices in `DECISIONS.md`
    and leave an exact next action in `HANDOFF.md`.

## Important implementation constraints

- The Flutter event identifier currently has legacy integer/hash behavior. New
  event detail, join, leave, edit, and organizer flows should preserve the real
  database UUID string end-to-end.
- Event creation should eventually be one database transaction so a failed event
  insert cannot leave an orphaned place.
- The current custom user token and static admin API key are development-stage
  mechanisms, not production authentication.
- Existing category icons are stored mainly as emoji. Do not delete or reinterpret
  this data until an `icon_key` migration and compatibility plan are approved.
- PostgreSQL and unknown server exceptions must produce safe JSON errors; do not
  expose stack traces, request headers, tokens, or connection details.

## Common commands

From the repository root:

```bash
./dev.sh -d chrome --web-port 3000
./dev.sh --services
```

Flutter:

```bash
cd app
dart format lib test
flutter analyze
flutter test
```

REST API:

```bash
dotnet build restapi/Muda.Api.csproj
```

Admin:

```bash
cd admin
npm run lint
npm run build
```

Use the executable paths available on the current machine when these commands are
not on `PATH`. Do not update Flutter golden files solely to make a failing test
pass; inspect the rendered difference first.

## Definition of done

- The requested behavior works through the real data path, not only with demo
  objects or mocked UI state.
- Relevant formatters, analyzers, builds, and tests have run, or the handoff names
  exactly what could not run and why.
- Privacy, activity-cost, localization, and authorization invariants remain true.
- `HANDOFF.md` reflects the resulting state and does not claim unverified work.

