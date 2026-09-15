# DAMUMU Repository Instructions

These instructions apply to the entire repository. Read this file before making
changes, then read `docs/PROJECT.md`, `docs/STATUS.md`, and the relevant module
README. Read the relevant entries in `docs/DECISIONS.md` for work involving
architecture, databases, authentication, concurrency, communication, deployment,
storage, security, or cross-module contracts.

## Required task workflow

Before changing code:

1. Read `docs/PROJECT.md` and `docs/STATUS.md`.
2. Inspect the actual code, configuration, tests, and current Git status.
3. Unless the user explicitly requests the current branch, create a new branch
   before editing. Choose a concise task-based name using `feature/`, `fix/`,
   `docs/`, or `chore/`; do not ask the user to supply the name. If task changes
   already exist in the working tree, create the branch from that state without
   discarding or rewriting those changes.
4. State the task outcome, applicable constraints, intended edit scope, and
   validation plan.

While working, keep edits within the requested task, preserve unrelated user
changes, and surface conflicts with an accepted ADR instead of silently replacing
the decision.

At task completion:

1. Run relevant formatting, analysis, builds, and tests.
2. Update `docs/STATUS.md` with current facts, the next action, and blockers.
3. Add or update an ADR only for a durable architectural decision.
4. Update `docs/PROJECT.md` only when product boundaries, system composition,
   technology, or long-term business rules change.
5. Review the final diff and secret scan, then create a focused conventional Git
   commit for the completed task without waiting for another instruction. Push
   the task branch to `origin` when a remote is configured, unless the user asks
   to keep the work local. Never commit or push credentials, local configuration,
   build output, generated logs, or unrelated user changes.

## Product invariants

- DAMUMU (current UI name: 搭慕慕) is a Korea-focused offline activity and
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
- `docs/`: canonical long-term project context, status, and ADRs.
- `DEVELOPMENT_CONTEXT.md`: detailed legacy handoff and implementation notes.
- `MVP.md`: MVP scope and acceptance criteria.
- `FIRST_RELEASE_FLOWS.md`: detailed first-release flow analysis.

## Working rules

1. Inspect the relevant UI, API, database, and admin paths before changing a
   cross-cutting feature.
2. Preserve user changes. Check `git status --short` and the relevant diff before
   editing; never discard unrelated work.
3. Treat source code, migrations, Git state, and test results as more current than
   documentation. Update `docs/STATUS.md` when implementation status changes.
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
10. When completing a task, record important lasting choices in
    `docs/DECISIONS.md` and leave an exact next action in `docs/STATUS.md`.

## Technology baseline

- Backend: ASP.NET Core 10 minimal API with Npgsql.
- Database: PostgreSQL with PostGIS and ordered SQL migrations.
- App: Flutter/Dart for Web, Android, and iOS.
- Admin: React 19 with Vite.
- Marketing site: standalone static site under `website/`.
- Object storage, push notifications, and realtime messaging: not yet selected;
  do not present them as implemented infrastructure.

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

Windows PowerShell:

```powershell
.\dev.ps1 -d chrome --web-port 3000
.\dev.ps1 --services
```

Linux, macOS, or an environment with Bash:

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
- `docs/STATUS.md` reflects the resulting state and does not claim unverified
  work.

The former root-level `PROJECT.md`, `HANDOFF.md`, and `DECISIONS.md` are retained
as historical references. The files under `docs/` are canonical for new tasks.
